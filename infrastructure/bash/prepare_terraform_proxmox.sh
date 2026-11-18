#!/usr/bin/env bash
# Prepara Proxmox per a Terraform: plantilla LXC Debian 13, rol, usuari i token API.
# El secret del token nomes s'escriu a terraform.local.tfvars (0600, ignorat per Git).
set -euo pipefail

PVE_HOST="${PVE01_IP:-10.7.0.133}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/vcorp_sysadmin}"
TF_DIR="$(cd "$(dirname "$0")/../terraform/proxmox" && pwd)"
TFVARS="$TF_DIR/terraform.local.tfvars"
TF_USER="terraform@pve"
TF_ROLE="TerraformKea"
TF_TOKEN="tf"
PRIVS="Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Audit Sys.Audit SDN.Use VM.Allocate VM.Audit VM.Config.CPU VM.Config.Disk VM.Config.Memory VM.Config.Network VM.Config.Options VM.PowerMgmt"

log() { printf '[prepare] %s\n' "$*"; }
pve() { ssh -i "$SSH_KEY" -o BatchMode=yes "root@$PVE_HOST" "$@"; }

log "Plantilla LXC Debian 13"
pve 'pveam update >/dev/null'
TEMPLATE="$(pve "pveam available --section system | awk '/debian-13-standard.*amd64/ {print \$2}' | sort -V | tail -n1")"
[ -n "$TEMPLATE" ] || { log "No s'ha trobat cap plantilla debian-13-standard"; exit 1; }
pve "pveam list local | grep -q '$TEMPLATE' || pveam download local '$TEMPLATE'"
log "Plantilla disponible: $TEMPLATE"

log "Rol, usuari i permisos"
if pve "pveum role list | grep -q '$TF_ROLE'"; then
  pve "pveum role modify '$TF_ROLE' -privs '$PRIVS'"
else
  pve "pveum role add '$TF_ROLE' -privs '$PRIVS'"
fi
pve "pveum user list | grep -q '$TF_USER' || pveum user add '$TF_USER' --comment 'Terraform'"
pve "pveum acl modify / --users '$TF_USER' --roles '$TF_ROLE'"

log "Token API"
if [ -f "$TFVARS" ] && pve "pveum user token list '$TF_USER' | grep -q '$TF_TOKEN'"; then
  log "El token i $(basename "$TFVARS") ja existeixen; no es toca res"
  exit 0
fi
pve "pveum user token remove '$TF_USER' '$TF_TOKEN'" >/dev/null 2>&1 || true
SECRET="$(pve "pveum user token add '$TF_USER' '$TF_TOKEN' --privsep 0 --output-format json" \
  | python3 -c 'import sys, json; print(json.load(sys.stdin)["value"])')"
umask 077
cat > "$TFVARS" <<TFEOF
proxmox_endpoint     = "https://${PVE_HOST}:8006/"
proxmox_token_id     = "${TF_USER}!${TF_TOKEN}"
proxmox_token_secret = "${SECRET}"
TFEOF
chmod 600 "$TFVARS"
log "Escrit $(basename "$TFVARS") (0600); el secret no es mostra ni es versiona"
