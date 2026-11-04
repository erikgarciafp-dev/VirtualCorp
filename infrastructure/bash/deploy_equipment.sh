#!/usr/bin/env bash
#
# Desplega els servidors, impressores i equips d'escriptori com a linked clones.
# Us: deploy_equipment.sh [--list | --verify | --delete]
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

VALID_NETWORKS=(dmz privada pl0 pl1 pl2 pl3 pl3_direccio rt0_1 rt1_2 rt2_3)
DMI_SERIAL_KEY="VBoxInternal/Devices/pcbios/0/Config/DmiSystemSerial"

trim() {
    local v="$1"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    printf '%s' "$v"
}

# Escriu una linia per maquina: id|nom|template|xarxa|ram|cpus
read_equipment() {
    local line id name kind net ram cpus desc
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        IFS='|' read -r id name kind net ram cpus desc <<<"$line"
        printf '%s|%s|%s|%s|%s|%s\n' "$(trim "$id")" "$(trim "$name")" "$(trim "$kind")" \
            "$(trim "$net")" "$(trim "$ram")" "$(trim "$cpus")"
    done < "$EQUIPMENT_FILE"
}

valid_network() {
    local n
    for n in "${VALID_NETWORKS[@]}"; do
        [[ "$n" == "$1" ]] && return 0
    done
    return 1
}

validate_equipment() {
    local id name kind net ram cpus bad=0 seen_ids=" " seen_names=" "
    while IFS='|' read -r -u 3 id name kind net ram cpus; do
        if ! [[ "$id" =~ ^[0-9]+$ ]] || (( id < 1 || id > 254 )); then
            log_error "Id invalid per a '$name': '$id' (ha de ser 1-254)"; bad=1
        fi
        if ! [[ "$name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]]; then
            log_error "Nom invalid: '$name'"; bad=1
        fi
        case "$kind" in
            server|desktop) ;;
            *) log_error "Template desconegut per a '$name': '$kind'"; bad=1 ;;
        esac
        if ! valid_network "$net"; then
            log_error "Xarxa interna no permesa per a '$name': '$net'"; bad=1
        fi
        if ! [[ "$ram" =~ ^[0-9]+$ && "$cpus" =~ ^[0-9]+$ ]]; then
            log_error "RAM o CPUs invalids per a '$name'"; bad=1
        fi
        if [[ "$seen_ids" == *" $id "* || "$seen_names" == *" $name "* ]]; then
            log_error "Id o nom repetit: '$id' / '$name'"; bad=1
        fi
        seen_ids+="$id "; seen_names+="$name "
    done 3< <(read_equipment)
    return $bad
}

vm_exists() {
    "$VBOXMANAGE_BIN" showvminfo "$1" &>/dev/null
}

template_name() {
    case "$1" in
        server)  printf '%s' "$TEMPLATE_SERVER_NAME" ;;
        desktop) printf '%s' "$TEMPLATE_DESKTOP_NAME" ;;
    esac
}

mac_for() {
    printf '0800270700%02X' "$1"
}

check_templates() {
    local t
    for t in "$TEMPLATE_SERVER_NAME" "$TEMPLATE_DESKTOP_NAME"; do
        if ! "$VBOXMANAGE_BIN" snapshot "$t" list --machinereadable 2>/dev/null \
             | grep -q "^SnapshotName=\"${TEMPLATE_SNAPSHOT_NAME}\"$"; then
            log_error "El template '$t' no existeix o no te el snapshot '$TEMPLATE_SNAPSHOT_NAME'. Executa 'make create_templates'."
            return 1
        fi
    done
}

deploy_machine() {
    local id="$1" name="$2" kind="$3" net="$4" ram="$5" cpus="$6" template mac
    template="$(template_name "$kind")"
    mac="$(mac_for "$id")"

    if vm_exists "$name"; then
        log_warn "La maquina '$name' ja existeix. S'omet."
        return 0
    fi

    log_info "Clonant '$template' -> '$name' (xarxa $net)"
    "$VBOXMANAGE_BIN" clonevm "$template" \
        --snapshot="$TEMPLATE_SNAPSHOT_NAME" --options=link \
        --name="$name" --groups="$VM_EQUIPMENT_GROUP" --register >/dev/null || return 1

    "$VBOXMANAGE_BIN" modifyvm "$name" \
        --memory "$ram" --cpus "$cpus" \
        --nic1 intnet --intnet1 "$net" \
        --macaddress1 "$mac" --cableconnected1 on || return 1

    # El nom de maquina es llegeix del DMI en la primera arrencada del clon.
    "$VBOXMANAGE_BIN" setextradata "$name" "$DMI_SERIAL_KEY" "$name" || return 1

    log_ok "'$name' creada (xarxa $net, MAC $mac)"
}

deploy_all() {
    local id name kind net ram cpus
    validate_equipment || exit 1
    check_templates || exit 1

    while IFS='|' read -r -u 3 id name kind net ram cpus; do
        deploy_machine "$id" "$name" "$kind" "$net" "$ram" "$cpus" \
            || { log_error "No s'ha pogut crear '$name'."; exit 1; }
    done 3< <(read_equipment)

    log_info "=========================================="
    log_info "[+] Equips desplegats correctament."
    log_info "=========================================="
}

delete_all() {
    local id name kind net ram cpus
    validate_equipment || exit 1
    while IFS='|' read -r -u 3 id name kind net ram cpus; do
        if vm_exists "$name"; then
            log_info "Esborrant '$name'"
            "$VBOXMANAGE_BIN" controlvm "$name" poweroff 2>/dev/null || true
            sleep 1
            "$VBOXMANAGE_BIN" unregistervm "$name" --delete >/dev/null \
                || log_warn "No s'ha pogut esborrar '$name'"
        fi
    done 3< <(read_equipment)
}

# Una maquina es un linked clone si el seu disc te un disc pare.
is_linked() {
    local disk
    disk="$("$VBOXMANAGE_BIN" showvminfo "$1" --machinereadable \
            | sed -n 's/^"SATA-0-0"="\(.*\)"$/\1/p')"
    [[ -n "$disk" ]] || return 1
    "$VBOXMANAGE_BIN" showmediuminfo disk "$disk" 2>/dev/null \
        | grep -E '^Parent UUID:' | grep -qv 'base'
}

verify_all() {
    local id name kind net ram cpus info linked network nat serial result vm failures=0
    validate_equipment || exit 1

    printf '%-10s %-8s %-14s %-5s %-10s %s\n' MAQUINA LINKED XARXA NAT DMI RESULTAT
    while IFS='|' read -r -u 3 id name kind net ram cpus; do
        info="$("$VBOXMANAGE_BIN" showvminfo "$name" --machinereadable 2>/dev/null || true)"
        if [[ -z "$info" ]]; then
            printf '%-10s %s\n' "$name" "no existeix"
            failures=$((failures + 1))
            continue
        fi
        linked=NO; is_linked "$name" && linked=SI
        network="$(sed -n 's/^intnet1="\(.*\)"$/\1/p' <<<"$info")"
        nat=NO; grep -qE '^nic[0-9]+="nat"$' <<<"$info" && nat=SI
        serial="$("$VBOXMANAGE_BIN" getextradata "$name" "$DMI_SERIAL_KEY" | sed -n 's/^Value: //p')"
        result=OK
        [[ "$linked" == SI && "$network" == "$net" && "$nat" == NO && "$serial" == "$name" ]] || result=ERROR
        [[ "$result" == OK ]] || failures=$((failures + 1))
        printf '%-10s %-8s %-14s %-5s %-10s %s\n' "$name" "$linked" "$network" "$nat" "$serial" "$result"
    done 3< <(read_equipment)

    # Cap maquina, a part de mikrotik0, pot tenir una interficie NAT.
    while IFS= read -r -u 4 vm; do
        [[ "$vm" == "mikrotik0" ]] && continue
        if "$VBOXMANAGE_BIN" showvminfo "$vm" --machinereadable | grep -qE '^nic[0-9]+="nat"$'; then
            log_error "'$vm' te una interficie NAT (nomes mikrotik0 en pot tenir)."
            failures=$((failures + 1))
        fi
    done 4< <("$VBOXMANAGE_BIN" list vms | sed -n 's/^"\(.*\)" {.*}$/\1/p')

    if [[ $failures -eq 0 ]]; then
        log_ok "Totes les comprovacions son correctes."
    else
        log_error "$failures comprovacions han fallat."
        return 1
    fi
}

list_all() {
    local id name kind net ram cpus
    validate_equipment || exit 1
    printf '%-3s %-10s %-8s %-14s %6s %s\n' ID NOM TEMPLATE XARXA RAM CPUS
    while IFS='|' read -r -u 3 id name kind net ram cpus; do
        printf '%-3s %-10s %-8s %-14s %6s %s\n' "$id" "$name" "$kind" "$net" "$ram" "$cpus"
    done 3< <(read_equipment)
}

case "${1:-}" in
    "")       deploy_all ;;
    --list)   list_all ;;
    --verify) verify_all ;;
    --delete) delete_all ;;
    *)        echo "Us: $0 [--list | --verify | --delete]" >&2; exit 1 ;;
esac
