#!/usr/bin/env bash
#
# Crea els templates Debian (server i desktop) amb instal.lacio desatesa.
# Us: create_templates.sh [server] [desktop]   |   create_templates.sh --delete
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/iso.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

ssh_template() {
    local port="$1"
    shift
    ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -o ConnectTimeout=10 \
        -i "$SYSADMIN_PRIVATE_KEY_FILE" \
        -p "$port" \
        "${TEMPLATE_USER}@127.0.0.1" "$@"
}

vm_exists() {
    "$VBOXMANAGE_BIN" showvminfo "$1" &>/dev/null
}

# Un template esta llest quan te el snapshot base.
template_ready() {
    "$VBOXMANAGE_BIN" snapshot "$1" list --machinereadable 2>/dev/null \
        | grep -q "^SnapshotName=\"${TEMPLATE_SNAPSHOT_NAME}\"$"
}

delete_template() {
    local name="$1"
    if vm_exists "$name"; then
        log_info "Esborrant '$name'"
        "$VBOXMANAGE_BIN" controlvm "$name" poweroff 2>/dev/null || true
        sleep 3
        "$VBOXMANAGE_BIN" unregistervm "$name" --delete || return 1
    fi
}

# Treu tots els DVD (ISO) de la VM.
detach_isos() {
    local name="$1" line key rest dev port ctl
    while IFS= read -r line; do
        key="${line%%=*}"
        key="${key//\"/}"
        dev="${key##*-}"
        rest="${key%-*}"
        port="${rest##*-}"
        ctl="${rest%-*}"
        "$VBOXMANAGE_BIN" storageattach "$name" --storagectl "$ctl" \
            --port "$port" --device "$dev" --medium emptydrive || true
    done < <("$VBOXMANAGE_BIN" showvminfo "$name" --machinereadable \
             | grep -E '^"[^"]+-[0-9]+-[0-9]+"=".*\.iso"$' || true)
}

# Plantilla de preseed: la de VirtualBox + els nostres ajustos.
build_preseed() {
    local out="$1" variant="$2"
    cat "$VBOX_UNATTENDED_DIR/debian_preseed.cfg" \
        "$PRESEED_DIR/${variant}_overrides.cfg" > "$out"
}

# Postinstalacio: la de VirtualBox + el nostre bloc abans de desmuntar el cdrom.
build_postinstall() {
    local out="$1" variant="$2" snippet
    snippet="$(mktemp -p "$TMP_ROOT")"
    {
        printf 'VCORP_USER=%q\n' "$TEMPLATE_USER"
        printf 'VCORP_VARIANT=%q\n' "$variant"
        printf 'VCORP_AUTHORIZED_KEYS=%q\n' \
            "$(printf '%s\n%s' "$(cat "$AUDIT_PUB_KEY_FILE")" "$(cat "$SYSADMIN_PUB_KEY_FILE")")"
        cat "$PRESEED_DIR/postinstall_custom.sh"
    } > "$snippet"

    awk -v snippet="$snippet" '
        /^# Unmount the cdrom if we bound it/ && !done {
            while ((getline line < snippet) > 0) print line
            close(snippet)
            done = 1
        }
        { print }
    ' "$VBOX_UNATTENDED_DIR/debian_postinstall.sh" > "$out"

    if ! grep -q 'VCORP_AUTHORIZED_KEYS' "$out"; then
        log_error "No s'ha pogut inserir el bloc a la postinstal.lacio."
        return 1
    fi
}

create_template() {
    local name="$1" variant="$2" memory="$3" disk_mb="$4" ssh_port="$5" vram="$6"
    local tmp="$TMP_ROOT/$name" vm_cfg vm_dir state i

    mkdir -p "$tmp"
    log_info "=========================================="
    log_info "Creant template '$name' ($variant)"
    log_info "=========================================="

    build_preseed "$tmp/preseed.cfg" "$variant" || return 1
    build_postinstall "$tmp/postinstall.sh" "$variant" || return 1

    "$VBOXMANAGE_BIN" createvm --name "$name" --ostype Debian13_64 \
        --register --groups "$VM_TEMPLATES_GROUP" || return 1

    "$VBOXMANAGE_BIN" modifyvm "$name" \
        --memory "$memory" --cpus "$TEMPLATE_CPUS" \
        --graphicscontroller vmsvga --vram "$vram" \
        --audio-driver none \
        --nic1 nat --cableconnected1 on \
        --natpf1 "ssh,tcp,127.0.0.1,${ssh_port},,22" || return 1

    vm_cfg="$("$VBOXMANAGE_BIN" showvminfo "$name" --machinereadable | grep '^CfgFile=' | cut -d'"' -f2)"
    vm_dir="$(dirname "$vm_cfg")"

    "$VBOXMANAGE_BIN" createmedium disk --filename "$vm_dir/${name}.vdi" \
        --size "$disk_mb" --format VDI || return 1
    "$VBOXMANAGE_BIN" storagectl "$name" --name "SATA" --add sata \
        --controller IntelAhci || return 1
    "$VBOXMANAGE_BIN" storageattach "$name" --storagectl "SATA" \
        --port 0 --device 0 --type hdd --medium "$vm_dir/${name}.vdi" || return 1

    log_info "Preparant la instal.lacio desatesa"
    printf '%s' "$SYSADMIN_PASSWORD" | "$VBOXMANAGE_BIN" unattended install "$name" \
        --iso="$DEBIAN_ISO_PATH" \
        --user="$TEMPLATE_USER" \
        --full-user-name="$TEMPLATE_USER" \
        --user-password-file=stdin \
        --hostname="${name}.${TEMPLATE_DOMAIN}" \
        --locale=en_US --country=ES --time-zone=Europe/Madrid \
        --no-install-additions \
        --script-template="$tmp/preseed.cfg" \
        --post-install-template="$tmp/postinstall.sh" || return 1

    # Disc primer, DVD despres: arrenca la instal.lacio i, un cop feta, el disc.
    "$VBOXMANAGE_BIN" modifyvm "$name" --boot1 disk --boot2 dvd --boot3 none --boot4 none || return 1

    log_info "Arrencant la instal.lacio (pot trigar entre 10 i 30 minuts)"
    "$VBOXMANAGE_BIN" startvm "$name" --type headless || return 1
    wait_ssh 127.0.0.1 "$ssh_port" 2400 || return 1

    for i in $(seq 1 12); do
        ssh_template "$ssh_port" true && break
        sleep 5
    done

    log_info "Verificant el template"
    ssh_template "$ssh_port" 'sudo -n true' \
        || { log_error "sysadmin no pot fer sudo sense contrasenya."; return 1; }
    if [[ "$variant" == "desktop" ]]; then
        ssh_template "$ssh_port" 'dpkg -s lxqt-core falkon >/dev/null 2>&1 && ! dpkg -s firefox-esr >/dev/null 2>&1' \
            || { log_error "Falten LXQt/Falkon o hi ha Firefox."; return 1; }
    else
        ssh_template "$ssh_port" 'dpkg -s openssh-server >/dev/null 2>&1 && ! dpkg -s xorg >/dev/null 2>&1' \
            || { log_error "El template server no es l'esperat."; return 1; }
    fi

    log_info "Preparant el template per clonar"
    ssh_template "$ssh_port" 'sudo sh -s' <<'REMOTE' || true
rm -f /var/lib/vcorp-firstboot.done /etc/ssh/ssh_host_*
: > /etc/machine-id
rm -f /var/lib/dbus/machine-id
apt-get clean
systemctl enable vcorp-firstboot.service
sync
poweroff
REMOTE

    log_info "Esperant que '$name' s'apagui..."
    state=""
    for i in $(seq 1 60); do
        state="$("$VBOXMANAGE_BIN" showvminfo "$name" --machinereadable | grep '^VMState=' | cut -d'"' -f2)"
        [[ "$state" == "poweroff" ]] && break
        sleep 2
    done
    [[ "$state" == "poweroff" ]] || { log_error "La VM no s'ha apagat."; return 1; }
    sleep 3

    detach_isos "$name"
    "$VBOXMANAGE_BIN" modifyvm "$name" --natpf1 delete ssh || true
    "$VBOXMANAGE_BIN" modifyvm "$name" --nic1 none || return 1
    "$VBOXMANAGE_BIN" snapshot "$name" take "$TEMPLATE_SNAPSHOT_NAME" \
        --description "Template base per a linked clones" || return 1

    log_ok "Template '$name' creat correctament."
}

main() {
    local targets=("$@") t name mem disk port vram

    if [[ "${targets[0]:-}" == "--delete" ]]; then
        delete_template "$TEMPLATE_SERVER_NAME"
        delete_template "$TEMPLATE_DESKTOP_NAME"
        return 0
    fi
    [[ ${#targets[@]} -eq 0 ]] && targets=(server desktop)

    : "${SYSADMIN_PASSWORD:?SYSADMIN_PASSWORD no definida (fitxer .env)}"
    for f in "$SYSADMIN_PRIVATE_KEY_FILE" "$AUDIT_PUB_KEY_FILE" "$SYSADMIN_PUB_KEY_FILE" \
             "$VBOX_UNATTENDED_DIR/debian_preseed.cfg" \
             "$VBOX_UNATTENDED_DIR/debian_postinstall.sh" \
             "$PRESEED_DIR/postinstall_custom.sh"; do
        [[ -r "$f" ]] || { log_error "No es pot llegir '$f'."; exit 1; }
    done

    download_iso "$DEBIAN_ISO_URL" "$DEBIAN_ISO_PATH" "$DEBIAN_ISO_SHA256" || exit 1

    for t in "${targets[@]}"; do
        case "$t" in
            server)
                name="$TEMPLATE_SERVER_NAME"; mem="$TEMPLATE_SERVER_MEMORY"
                disk="$TEMPLATE_SERVER_DISK_MB"; port="$TEMPLATE_SERVER_SSH_PORT"; vram=16 ;;
            desktop)
                name="$TEMPLATE_DESKTOP_NAME"; mem="$TEMPLATE_DESKTOP_MEMORY"
                disk="$TEMPLATE_DESKTOP_DISK_MB"; port="$TEMPLATE_DESKTOP_SSH_PORT"; vram=64 ;;
            *) log_error "Template desconegut: $t (server o desktop)"; exit 1 ;;
        esac

        if template_ready "$name"; then
            log_warn "El template '$name' ja existeix. S'omet."
            continue
        fi
        if vm_exists "$name"; then
            log_warn "El template '$name' era incomplet. S'esborra i es torna a crear."
            delete_template "$name" || exit 1
        fi
        create_template "$name" "$t" "$mem" "$disk" "$port" "$vram" \
            || { log_error "No s'ha pogut crear '$name'."; exit 1; }
    done

    log_info "=========================================="
    log_info "[+] Templates creats correctament."
    log_info "=========================================="
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
