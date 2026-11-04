#!/usr/bin/env bash

VBOXMANAGE_BIN="${VBOXMANAGE_BIN:-$(command -v VBoxManage 2>/dev/null || command -v vboxmanage 2>/dev/null || true)}"
if [ -z "$VBOXMANAGE_BIN" ]; then
    echo "Error: VBoxManage no està instal·lat o no es troba al PATH del sistema." >&2
    exit 1
fi

VBOX_ROOT_GROUP="${VBOX_ROOT_GROUP:-/VirtualCorp}"
VM_ROUTERS_GROUP="${VM_ROUTERS_GROUP:-$VBOX_ROOT_GROUP/Routers}"
VM_TEMPLATES_GROUP="${VM_TEMPLATES_GROUP:-$VBOX_ROOT_GROUP/templates}"


ROUTEROS_VERSION="${ROUTEROS_VERSION:-7.21.4}"
ROUTEROS_VDI_FILENAME="${ROUTEROS_VDI_FILENAME:-chr-${ROUTEROS_VERSION}.vdi}"
URL="${ROUTEROS_URL:-https://download.mikrotik.com/routeros/${ROUTEROS_VERSION}/${ROUTEROS_VDI_FILENAME}.zip}"

ROUTER_MEMORY=256
ROUTER_CPU=1

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$COMMON_DIR/../.." && pwd)}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${PROJECT_ROOT}/artifacts/images/chr}"
CONFIGS_DIR="${CONFIGS_DIR:-${PROJECT_ROOT}/configs}"
SSH_PUBLIC_KEY_DIR="${SSH_PUBLIC_KEY_DIR:-${CONFIGS_DIR}/ssh}"
SSH_PRIVATE_KEY_DIR="${SSH_PRIVATE_KEY_DIR:-${HOME}/.ssh}"
ROUTEROS_VDI_PATH="${ROUTEROS_VDI_PATH:-${ARTIFACTS_DIR}/${ROUTEROS_VDI_FILENAME}}"

VM_NAME="routeros_template"
BOX_NAME="${ROUTEROS_BOX_NAME:-routeros-base}"
BOX_FILE="${ROUTEROS_BOX_FILE:-${ARTIFACTS_DIR}/${BOX_NAME}.box}"

SSH_PORT=2222
SSH_USER=sysadmin

AUDIT_PRIVATE_KEY_FILE="${SSH_PRIVATE_KEY_DIR}/vcorp_auditor"
AUDIT_PUB_KEY_FILE="${SSH_PUBLIC_KEY_DIR}/vcorp_auditor.pub"
SYSADMIN_PRIVATE_KEY_FILE="${SSH_PRIVATE_KEY_DIR}/vcorp_sysadmin"
SYSADMIN_PUB_KEY_FILE="${SSH_PUBLIC_KEY_DIR}/vcorp_sysadmin.pub"

# Colors ANSI
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_ok() {
    echo -e "${GREEN}[ OK ]${NC} $*"
}

log_err() {
    echo -e "${RED}[ERROR]${NC} $*"
}

wait_ssh() {
    local ip="${1:-127.0.0.1}"
    local port="${2:-22}"
    local max_wait="${3:-60}"
    local elapsed=0
    local interval=5

    log_info "Esperant servei SSH a ${ip}:${port} (màx ${max_wait}s)..."

    while [ "$elapsed" -lt "$max_wait" ]; do
        # ssh-keyscan valida que el dimoni SSH estigui actiu i responent
        if ssh-keyscan -p "$port" "$ip" >/dev/null 2>&1; then
            log_info "SSH disponible a ${ip}:${port}!"
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    log_error "Timeout: SSH no disponible a ${ip}:${port} després de ${max_wait}s."
    return 1
}

log_error() {
    log_err "$@"
}

# ------------------------------------------------------------
# Versions fixes de les ISO (no cercar mai l'ultima versio)
# ------------------------------------------------------------

ISO_DIR="${ISO_DIR:-${PROJECT_ROOT}/artifacts/isos}"

DEBIAN_VERSION="${DEBIAN_VERSION:-13.7.0}"
DEBIAN_ISO_FILENAME="${DEBIAN_ISO_FILENAME:-debian-${DEBIAN_VERSION}-amd64-netinst.iso}"
DEBIAN_ISO_URL="${DEBIAN_ISO_URL:-https://cdimage.debian.org/debian-cd/${DEBIAN_VERSION}/amd64/iso-cd/${DEBIAN_ISO_FILENAME}}"
DEBIAN_ISO_SHA256="${DEBIAN_ISO_SHA256:-a7ef94ac2fb9a7fec454552abd629b7cc9d5155c886165a45649f5ce6167e355}"
DEBIAN_ISO_PATH="${DEBIAN_ISO_PATH:-${ISO_DIR}/${DEBIAN_ISO_FILENAME}}"

PROXMOX_VERSION="${PROXMOX_VERSION:-9.2-1}"
PROXMOX_ISO_FILENAME="${PROXMOX_ISO_FILENAME:-proxmox-ve_${PROXMOX_VERSION}.iso}"
# download.proxmox.com presenta un certificat que no coincideix amb el nom
# del servidor; s'utilitza el servidor oficial enterprise.proxmox.com.
PROXMOX_ISO_URL="${PROXMOX_ISO_URL:-https://enterprise.proxmox.com/iso/${PROXMOX_ISO_FILENAME}}"
PROXMOX_ISO_SHA256="${PROXMOX_ISO_SHA256:-4e88fe416df9b527624a175f24c9aa07c714d3332afb1ee3dbf3879573ef2c6c}"
PROXMOX_ISO_PATH="${PROXMOX_ISO_PATH:-${ISO_DIR}/${PROXMOX_ISO_FILENAME}}"

# ------------------------------------------------------------
# Templates Debian (instal.lacio desatesa)
# ------------------------------------------------------------

VBOX_UNATTENDED_DIR="${VBOX_UNATTENDED_DIR:-/usr/share/virtualbox/UnattendedTemplates}"
PRESEED_DIR="${PRESEED_DIR:-${CONFIGS_DIR}/preseed}"

TEMPLATE_SERVER_NAME="${TEMPLATE_SERVER_NAME:-tpl-debian-server}"
TEMPLATE_DESKTOP_NAME="${TEMPLATE_DESKTOP_NAME:-tpl-debian-desktop}"
TEMPLATE_SNAPSHOT_NAME="${TEMPLATE_SNAPSHOT_NAME:-base}"
TEMPLATE_USER="${TEMPLATE_USER:-sysadmin}"
TEMPLATE_DOMAIN="${TEMPLATE_DOMAIN:-vcorp.local}"
TEMPLATE_CPUS="${TEMPLATE_CPUS:-2}"
TEMPLATE_SERVER_MEMORY="${TEMPLATE_SERVER_MEMORY:-1024}"
TEMPLATE_SERVER_DISK_MB="${TEMPLATE_SERVER_DISK_MB:-8192}"
TEMPLATE_DESKTOP_MEMORY="${TEMPLATE_DESKTOP_MEMORY:-2048}"
TEMPLATE_DESKTOP_DISK_MB="${TEMPLATE_DESKTOP_DISK_MB:-16384}"
TEMPLATE_SERVER_SSH_PORT="${TEMPLATE_SERVER_SSH_PORT:-2230}"
TEMPLATE_DESKTOP_SSH_PORT="${TEMPLATE_DESKTOP_SSH_PORT:-2231}"

# ------------------------------------------------------------
# Equips (linked clones)
# ------------------------------------------------------------

VM_EQUIPMENT_GROUP="${VM_EQUIPMENT_GROUP:-${VBOX_ROOT_GROUP:-/VirtualCorp}/Equipment}"
EQUIPMENT_FILE="${EQUIPMENT_FILE:-${CONFIGS_DIR}/equipment.conf}"

# ------------------------------------------------------------
# pve01 (Proxmox VE)
# ------------------------------------------------------------

PVE01_NAME="${PVE01_NAME:-pve01}"
PVE01_CPUS="${PVE01_CPUS:-4}"
PVE01_MEMORY="${PVE01_MEMORY:-8192}"
PVE01_DISK_MB="${PVE01_DISK_MB:-65536}"
PVE01_NETWORK="${PVE01_NETWORK:-privada}"
PVE01_MAC="${PVE01_MAC:-080027070014}"
PVE01_IP="${PVE01_IP:-10.7.0.133}"
PVE01_ANSWER_TEMPLATE="${PVE01_ANSWER_TEMPLATE:-${CONFIGS_DIR}/pve01/answer.toml.tpl}"
PVE01_AUTO_ISO_PATH="${PVE01_AUTO_ISO_PATH:-${ISO_DIR}/proxmox-ve_${PROXMOX_VERSION}-auto.iso}"

# Eina de Proxmox per preparar la ISO (versio i clau fixades).
TOOLS_DIR="${TOOLS_DIR:-${PROJECT_ROOT}/artifacts/tools}"
PVE_ASSISTANT_VERSION="${PVE_ASSISTANT_VERSION:-9.2.8}"
PVE_ASSISTANT_BIN="${PVE_ASSISTANT_BIN:-${TOOLS_DIR}/pve-assistant/usr/bin/proxmox-auto-install-assistant}"
PVE_APT_URL="${PVE_APT_URL:-http://download.proxmox.com/debian/pve}"
PVE_APT_KEY_URL="${PVE_APT_KEY_URL:-https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg}"
PVE_APT_KEY_FPR="${PVE_APT_KEY_FPR:-24B30F06ECC1836A4E5EFECBA7BCD1420BFE778E}"

# ------------------------------------------------------------
# pve01 (Proxmox VE)
# ------------------------------------------------------------

PVE01_NAME="${PVE01_NAME:-pve01}"
PVE01_CPUS="${PVE01_CPUS:-4}"
PVE01_MEMORY="${PVE01_MEMORY:-8192}"
PVE01_DISK_MB="${PVE01_DISK_MB:-65536}"
PVE01_NETWORK="${PVE01_NETWORK:-privada}"
PVE01_MAC="${PVE01_MAC:-080027070014}"
PVE01_IP="${PVE01_IP:-10.7.0.133}"
PVE01_ANSWER_TEMPLATE="${PVE01_ANSWER_TEMPLATE:-${CONFIGS_DIR}/pve01/answer.toml.tpl}"
PVE01_AUTO_ISO_PATH="${PVE01_AUTO_ISO_PATH:-${ISO_DIR}/proxmox-ve_${PROXMOX_VERSION}-auto.iso}"

# Eina de Proxmox per preparar la ISO (versio i clau fixades).
TOOLS_DIR="${TOOLS_DIR:-${PROJECT_ROOT}/artifacts/tools}"
PVE_ASSISTANT_VERSION="${PVE_ASSISTANT_VERSION:-9.2.8}"
PVE_ASSISTANT_BIN="${PVE_ASSISTANT_BIN:-${TOOLS_DIR}/pve-assistant/usr/bin/proxmox-auto-install-assistant}"
PVE_APT_URL="${PVE_APT_URL:-http://download.proxmox.com/debian/pve}"
PVE_APT_KEY_URL="${PVE_APT_KEY_URL:-https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg}"
PVE_APT_KEY_FPR="${PVE_APT_KEY_FPR:-24B30F06ECC1836A4E5EFECBA7BCD1420BFE778E}"
