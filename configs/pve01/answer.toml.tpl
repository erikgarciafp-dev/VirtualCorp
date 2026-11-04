# VirtualCorp - fitxer de respostes de Proxmox VE (pve01).
# Es renderitza en preparar la ISO (contrasenya i claus SSH de root).

[global]
keyboard = "es"
country = "es"
fqdn = "pve01.vcorp.local"
mailto = "sysadmin@vcorp.local"
timezone = "Europe/Madrid"
root-password-hashed = "${ROOT_PASSWORD_HASH}"
root-ssh-keys = [
${ROOT_SSH_KEYS}
]

[network]
source = "from-answer"
cidr = "10.7.0.133/26"
dns = "8.8.8.8"
gateway = "10.7.0.129"
filter.ID_NET_NAME = "en*"

[disk-setup]
filesystem = "ext4"
disk-list = ["sda"]
