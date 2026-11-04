#!/usr/bin/env bash
#
# Desplega pve01 (Proxmox VE) amb instal.lacio desatesa.
# Us: deploy_pve01.sh [--verify | --delete]
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/iso.sh"

ROUTER_USER="sysadmin"
ROUTER_SSH_PORT=2200
ROUTER_IPS=(10.7.0.225 10.7.0.226 10.7.0.230 10.7.0.234)
PUBLIC_IP="1.1.1.1"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

PVE_FAILURES=0

vm_exists() {
    "$VBOXMANAGE_BIN" showvminfo "$1" &>/dev/null
}

vm_running() {
    "$VBOXMANAGE_BIN" list runningvms | grep -q "^\"$1\" "
}

# SSH a pve01 passant per mikrotik0 (l'unic dispositiu accessible des de l'amfitrio).
ssh_pve() {
    ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -o ConnectTimeout=8 \
        -o ProxyCommand="ssh -i ${SYSADMIN_PRIVATE_KEY_FILE} -p ${ROUTER_SSH_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -W %h:%p ${ROUTER_USER}@127.0.0.1" \
        -i "$SYSADMIN_PRIVATE_KEY_FILE" \
        "root@${PVE01_IP}" "$@"
}

# Descarrega l'eina de Proxmox sense modificar la configuracio d'apt del sistema.
ensure_assistant() {
    [[ -x "$PVE_ASSISTANT_BIN" ]] && return 0

    local work="$TOOLS_DIR/pve-apt" key="$TOOLS_DIR/proxmox-release-trixie.gpg" fpr deb
    mkdir -p "$work/lists/partial" "$work/cache/archives/partial" "$TOOLS_DIR/pve-assistant"

    log_info "Descarregant la clau oficial de Proxmox"
    curl -fsSL "$PVE_APT_KEY_URL" -o "$key" \
        || { log_error "No s'ha pogut descarregar la clau de Proxmox."; return 1; }

    fpr="$(gpg --show-keys --with-colons "$key" | awk -F: '/^fpr:/ {print $10; exit}')"
    if [[ "$fpr" != "$PVE_APT_KEY_FPR" ]]; then
        log_error "La clau de Proxmox no coincideix amb la fixada (obtinguda: $fpr)."
        return 1
    fi

    echo "deb [signed-by=$key] $PVE_APT_URL trixie pve-no-subscription" > "$work/sources.list"
    local opts=(-o Dir::Etc::sourcelist="$work/sources.list" -o Dir::Etc::sourceparts=/dev/null \
                -o Dir::State::Lists="$work/lists" -o Dir::Cache="$work/cache" -o Debug::NoLocking=1)

    apt-get "${opts[@]}" update >/dev/null || return 1
    (cd "$TOOLS_DIR" && apt-get "${opts[@]}" download "proxmox-auto-install-assistant=${PVE_ASSISTANT_VERSION}") \
        || { log_error "Versio ${PVE_ASSISTANT_VERSION} no disponible. Investiga-ho abans d'actualitzar la configuracio."; return 1; }

    deb="$(ls "$TOOLS_DIR"/proxmox-auto-install-assistant_"${PVE_ASSISTANT_VERSION}"_*.deb | head -n 1)"
    dpkg -x "$deb" "$TOOLS_DIR/pve-assistant" || return 1
    [[ -x "$PVE_ASSISTANT_BIN" ]] || { log_error "No s'ha trobat l'eina despres d'extreure-la."; return 1; }
    log_ok "Eina proxmox-auto-install-assistant ${PVE_ASSISTANT_VERSION} preparada"
}

# Genera el fitxer de respostes (amb la contrasenya del .env), el valida i prepara la ISO.
prepare_iso() {
    local answer="$TMP_ROOT/answer.toml" stage="$ISO_DIR/.pve-stage"

    ROOT_PASSWORD_HASH="$(printf '%s' "$SYSADMIN_PASSWORD" | openssl passwd -6 -stdin)"
    ROOT_SSH_KEYS="$(for k in "$AUDIT_PUB_KEY_FILE" "$SYSADMIN_PUB_KEY_FILE"; do printf '  "%s",\n' "$(cat "$k")"; done)"
    export ROOT_PASSWORD_HASH ROOT_SSH_KEYS
    envsubst '${ROOT_PASSWORD_HASH} ${ROOT_SSH_KEYS}' < "$PVE01_ANSWER_TEMPLATE" > "$answer"
    unset ROOT_PASSWORD_HASH ROOT_SSH_KEYS
    chmod 600 "$answer"

    "$PVE_ASSISTANT_BIN" validate-answer "$answer" || return 1

    log_info "Preparant la ISO d'instal.lacio automatica (pot trigar un parell de minuts)"
    rm -rf "$stage"; mkdir -p "$stage"
    rm -f "$PVE01_AUTO_ISO_PATH"
    "$PVE_ASSISTANT_BIN" prepare-iso "$PROXMOX_ISO_PATH" \
        --fetch-from iso --answer-file "$answer" \
        --output "$PVE01_AUTO_ISO_PATH" --tmp "$stage" || { rm -rf "$stage"; return 1; }
    rm -rf "$stage"
    chmod 600 "$PVE01_AUTO_ISO_PATH"
    log_ok "ISO preparada: $(basename "$PVE01_AUTO_ISO_PATH")"
}

create_vm() {
    local vm_cfg vm_dir
    "$VBOXMANAGE_BIN" createvm --name "$PVE01_NAME" --ostype Debian13_64 \
        --register --groups "$VM_EQUIPMENT_GROUP" >/dev/null || return 1

    # Virtualitzacio anidada activada des de l'script (no depen de cap operacio manual).
    "$VBOXMANAGE_BIN" modifyvm "$PVE01_NAME" \
        --memory "$PVE01_MEMORY" --cpus "$PVE01_CPUS" \
        --nested-hw-virt on \
        --graphicscontroller vmsvga --vram 16 --audio-driver none \
        --nic1 intnet --intnet1 "$PVE01_NETWORK" \
        --macaddress1 "$PVE01_MAC" --cableconnected1 on \
        --boot1 disk --boot2 dvd --boot3 none --boot4 none || return 1

    vm_cfg="$("$VBOXMANAGE_BIN" showvminfo "$PVE01_NAME" --machinereadable | grep '^CfgFile=' | cut -d'"' -f2)"
    vm_dir="$(dirname "$vm_cfg")"

    "$VBOXMANAGE_BIN" createmedium disk --filename "$vm_dir/${PVE01_NAME}.vdi" \
        --size "$PVE01_DISK_MB" --format VDI >/dev/null || return 1
    "$VBOXMANAGE_BIN" storagectl "$PVE01_NAME" --name SATA --add sata --controller IntelAhci || return 1
    "$VBOXMANAGE_BIN" storageattach "$PVE01_NAME" --storagectl SATA \
        --port 0 --device 0 --type hdd --medium "$vm_dir/${PVE01_NAME}.vdi" || return 1
    "$VBOXMANAGE_BIN" storageattach "$PVE01_NAME" --storagectl SATA \
        --port 1 --device 0 --type dvddrive --medium "$PVE01_AUTO_ISO_PATH" || return 1
}

wait_for_install() {
    local i
    log_info "Instal.lant Proxmox VE (uns 10-15 minuts). Esperant l'acces SSH a ${PVE01_IP} via mikrotik0..."
    for i in $(seq 1 480); do
        if ssh_pve true 2>/dev/null; then
            log_ok "pve01 respon per SSH"
            return 0
        fi
        if ! vm_running "$PVE01_NAME"; then
            log_error "La VM '${PVE01_NAME}' s'ha aturat abans d'acabar la instal.lacio."
            return 1
        fi
        sleep 5
    done
    "$VBOXMANAGE_BIN" controlvm "$PVE01_NAME" screenshotpng "/tmp/${PVE01_NAME}-error.png" 2>/dev/null || true
    log_error "Temps esgotat. Captura de la VM: /tmp/${PVE01_NAME}-error.png"
    return 1
}

check_remote() {
    local desc="$1" cmd="$2"
    if ssh_pve "$cmd" >/dev/null 2>&1; then
        log_ok "$desc"
    else
        log_error "$desc"
        PVE_FAILURES=$((PVE_FAILURES + 1))
    fi
}

verify_pve01() {
    local ip
    PVE_FAILURES=0
    ssh_pve true >/dev/null 2>&1 \
        || { log_error "No es pot accedir a ${PVE01_NAME} per SSH (a traves de mikrotik0)."; return 1; }

    check_remote "Acces SSH com a root amb clau, a traves de mikrotik0" "true"
    check_remote "Nom de maquina ${PVE01_NAME}" "test \"\$(hostname)\" = ${PVE01_NAME}"
    check_remote "Adreca IP estatica ${PVE01_IP}/26" "ip -4 -o addr show | grep -q '${PVE01_IP}/26'"
    check_remote "Proxmox VE instal.lat" "pveversion | grep -q '^pve-manager/'"
    check_remote "Arrel en ext4 i sense ZFS" "findmnt -n -o FSTYPE / | grep -qx ext4 && ! pvesm status | grep -qw zfspool"
    check_remote "Extensions de virtualitzacio exposades (vmx/svm)" "grep -Eq 'vmx|svm' /proc/cpuinfo"
    check_remote "KVM disponible (/dev/kvm)" "test -c /dev/kvm"
    check_remote "Clau del professor autoritzada" "grep -q vcorp_auditor /root/.ssh/authorized_keys"
    for ip in "${ROUTER_IPS[@]}" "$PUBLIC_IP"; do
        check_remote "Ping a ${ip}" "ping -c 2 -W 2 ${ip}"
    done

    if [[ $PVE_FAILURES -eq 0 ]]; then
        log_ok "Totes les comprovacions de ${PVE01_NAME} son correctes."
    else
        log_error "${PVE_FAILURES} comprovacions de ${PVE01_NAME} han fallat."
        return 1
    fi
}

deploy_pve01() {
    local f
    : "${SYSADMIN_PASSWORD:?SYSADMIN_PASSWORD no definida (fitxer .env)}"

    if vm_exists "$PVE01_NAME"; then
        log_warn "La maquina '${PVE01_NAME}' ja existeix. S'omet (make delete-pve01 per esborrar-la)."
        return 0
    fi

    for f in "$SYSADMIN_PRIVATE_KEY_FILE" "$AUDIT_PUB_KEY_FILE" "$SYSADMIN_PUB_KEY_FILE" "$PVE01_ANSWER_TEMPLATE"; do
        [[ -r "$f" ]] || { log_error "No es pot llegir '$f'."; exit 1; }
    done
    command -v envsubst >/dev/null || { log_error "Cal envsubst (paquet gettext-base)."; exit 1; }
    vm_running mikrotik0 \
        || { log_error "mikrotik0 ha d'estar en marxa (es valida pve01 a traves seu). Executa 'make deploy-routers' i arrenca els routers."; exit 1; }

    download_iso "$PROXMOX_ISO_URL" "$PROXMOX_ISO_PATH" "$PROXMOX_ISO_SHA256" || exit 1
    ensure_assistant || exit 1
    prepare_iso || exit 1

    log_info "Creant la VM '${PVE01_NAME}'"
    create_vm || { log_error "No s'ha pogut crear la VM."; exit 1; }

    "$VBOXMANAGE_BIN" startvm "$PVE01_NAME" --type headless || exit 1
    wait_for_install || exit 1
    verify_pve01 || exit 1

    # Traiem la ISO automatica un cop instal.lat, perque no es pugui tornar a executar.
    "$VBOXMANAGE_BIN" storageattach "$PVE01_NAME" --storagectl SATA --port 1 --device 0 \
        --type dvddrive --medium emptydrive --forceunmount 2>/dev/null \
        || log_warn "No s'ha pogut treure la ISO de la unitat."

    log_info "=========================================="
    log_info "[+] ${PVE01_NAME} desplegat correctament."
    log_info "=========================================="
}

delete_pve01() {
    if vm_exists "$PVE01_NAME"; then
        log_info "Esborrant '${PVE01_NAME}'"
        "$VBOXMANAGE_BIN" controlvm "$PVE01_NAME" poweroff 2>/dev/null || true
        sleep 2
        "$VBOXMANAGE_BIN" unregistervm "$PVE01_NAME" --delete >/dev/null
    fi
}

case "${1:-}" in
    "")       deploy_pve01 ;;
    --verify) verify_pve01 ;;
    --delete) delete_pve01 ;;
    *)        echo "Us: $0 [--verify | --delete]" >&2; exit 1 ;;
esac
