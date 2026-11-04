
#
# VirtualCorp: configuracio comuna dels templates.
# S'insereix a la postinstal.lacio de VirtualBox, abans de desmuntar el cdrom.
# Variables definides abans d'aquest bloc: VCORP_USER, VCORP_VARIANT, VCORP_AUTHORIZED_KEYS
#
echo '** VirtualCorp: usuari, claus SSH i primera arrencada' | tee -a "${MY_LOGFILE}"

# --- Claus SSH autoritzades (professor + alumne) ---
mkdir -p "${MY_TARGET}/home/${VCORP_USER}/.ssh"
printf '%s\n' "${VCORP_AUTHORIZED_KEYS}" > "${MY_TARGET}/home/${VCORP_USER}/.ssh/authorized_keys"
chmod 700 "${MY_TARGET}/home/${VCORP_USER}/.ssh"
chmod 600 "${MY_TARGET}/home/${VCORP_USER}/.ssh/authorized_keys"
log_command_in_target chown -R "${VCORP_USER}:${VCORP_USER}" "/home/${VCORP_USER}/.ssh"

# --- sudo sense contrasenya ---
mkdir -p "${MY_TARGET}/etc/sudoers.d"
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "${VCORP_USER}" > "${MY_TARGET}/etc/sudoers.d/90-vcorp"
chmod 440 "${MY_TARGET}/etc/sudoers.d/90-vcorp"

# --- Servei de primera arrencada (cada clon: nom de maquina i claus de host) ---
mkdir -p "${MY_TARGET}/usr/local/sbin"
cat > "${MY_TARGET}/usr/local/sbin/vcorp-firstboot" <<'VCORP_EOF'
#!/bin/sh
# Primera arrencada d'un clon: nom de maquina i claus SSH de host.
set -eu
name="$(cat /sys/class/dmi/id/product_serial 2>/dev/null || true)"
case "$name" in
    [a-z][a-z0-9-]*[a-z0-9]) ;;
    *) name="" ;;
esac
if [ -n "$name" ]; then
    hostname "$name"
    echo "$name" > /etc/hostname
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$name/" /etc/hosts
fi
ssh-keygen -A
touch /var/lib/vcorp-firstboot.done
systemctl disable vcorp-firstboot.service || true
VCORP_EOF
chmod 755 "${MY_TARGET}/usr/local/sbin/vcorp-firstboot"

cat > "${MY_TARGET}/etc/systemd/system/vcorp-firstboot.service" <<'VCORP_EOF'
[Unit]
Description=VirtualCorp primera arrencada: nom de maquina i claus SSH
DefaultDependencies=no
After=local-fs.target
Before=network-pre.target ssh.service
ConditionPathExists=!/var/lib/vcorp-firstboot.done

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/vcorp-firstboot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
VCORP_EOF
log_command_in_target systemctl enable vcorp-firstboot.service

# --- Desktop: assegurem que no hi ha Firefox ni suites ofimatiques ---
if [ "${VCORP_VARIANT}" = "desktop" ]; then
    MY_IGNORE_EXITCODE=100
    log_command_in_target env DEBIAN_FRONTEND=noninteractive apt-get -y purge firefox-esr 'libreoffice*'
    MY_IGNORE_EXITCODE=
fi


# --- Teclat en castella (VirtualBox fixa 'us' amb parametres del nucli) ---
cat > "${MY_TARGET}/etc/default/keyboard" <<'KBD_EOF'
XKBMODEL="pc105"
XKBLAYOUT="es"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
KBD_EOF
