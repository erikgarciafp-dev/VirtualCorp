# Activitat 2 - Desplegament d'equipament

## Ús

    make create_templates     # crea les plantilles Debian Server i Debian Desktop
    make deploy_equipment     # 19 clons enllaçats + pve01 (Proxmox VE)
    make verify-equipment     # comprova que tot respon (SSH, IP, xarxa)
    make delete-equipment     # esborra clons i pve01

Tot es desplega amb scripts, sense passos manuals. Les contrasenyes i claus
no són al repositori: la contrasenya de `sysadmin` és al `.env` (ignorat per git).

## On són les versions i URLs

Totes les versions, URLs i sumes SHA256 de les ISO estan fixades com a variables
a `infrastructure/bash/common.sh` (DEBIAN_*, PROXMOX_*, TEMPLATE_*, PVE01_*,
PVE_ASSISTANT_*). Les ISO es baixen i es verifiquen amb `iso.sh`.

## Plantilles (`create_templates.sh`)

- Debian 13.7.0 amb instal·lació desatesa de VirtualBox (`VBoxManage unattended`)
  i overrides de preseed a `configs/preseed/`.
- **Server**: sistema mínim amb `openssh-server` i `sudo`.
- **Desktop**: LXQt + SDDM + Falkon (sense tasksel, per evitar GNOME).
- Post-instal·lació (`postinstall_custom.sh`): claus autoritzades (professor i
  alumne), `sudo` sense contrasenya per a `sysadmin`, teclat `es` i servei de
  primer arrencada.

## Equips (`deploy_equipment.sh` + `configs/equipment.conf`)

19 clons enllaçats de les plantilles, definits a `equipment.conf`
(id | nom | plantilla | xarxa | RAM | CPUs | descripció).
Cada màquina té MAC `08:00:27:07:00:<id en hexadecimal>` i es connecta a la xarxa
interna indicada. Opcions: `--list`, `--verify`, `--delete`.

## pve01 (`deploy_pve01.sh`)

Proxmox VE 9.2-1 amb instal·lació desatesa:
`proxmox-auto-install-assistant prepare-iso` amb `configs/pve01/answer.toml.tpl`
(fqdn pve01.vcorp.local, 10.7.0.133/26, gateway 10.7.0.129, ext4, disc `sda`).
Les contrasenyes i claus s'injecten amb `envsubst`. Virtualització anidada
activada. L'eina d'Proxmox es baixa del repositori amb la clau GPG verificada
per empremta.

## Xarxa

Veure `docs/network.pdf` (font: `docs/network.dot`).
Routers: mikrotik0..3 en cadena, NAT només a mikrotik0.

## Comprovacions fetes

- `make verify-equipment`: les 19 màquines responen per SSH amb la IP esperada.
- pve01: SSH, versió de Proxmox, virtualització anidada i xarxa correctes.
- Sortida a Internet des dels routers a través de mikrotik0.

## Decisions i supòsits

- conserge1 i conserge2 usen el template Debian Desktop, tal com indica l'activitat 2 (apartat 4.2); l'enunciat general els descriu com a equips Windows.
- Noms pc1-3 i dir1-3 inventats; l'enunciat no els fixa.
- Servidors de projecte, DHCP i DNS queden fora d'aquesta activitat.
- `sysadmin` té `sudo` sense contrasenya: decisió de laboratori.
- pve01 usa DNS 8.8.8.8.

## Incidències

- download.proxmox.com amb certificat que no coincidia: s'usa
  enterprise.proxmox.com amb SHA256 fixat, sense desactivar la verificació TLS.
- La plantilla Desktop instal·lava GNOME i no arrencava SSH: es desactiva
  tasksel i s'indiquen els paquets explícitament.
- Faltava `openssh-server` a la primera versió de la plantilla.
- Teclat en anglès a les VM: fixat a `es` a `/etc/default/keyboard`.
- `answer.toml` no es llegia per una variable dins d'un comentari.
- La ISO de pve01 no s'expulsava: s'usa `--forceunmount`.

## Màquines i xarxes internes VirtualBox

Totes les interfícies són en mode xarxa interna (Internal Network); només
mikrotik0 té una interfície NAT. Els templates no tenen cap interfície.

| Màquina | Template | Xarxa interna | RAM (MB) | CPUs |
|---|---|---|---|---|
| websrv | server | dmz | 1024 | 1 |
| dbsrv | server | privada | 1024 | 1 |
| infosrv | server | privada | 1024 | 1 |
| printer0 | server | pl0 | 512 | 1 |
| printer1 | server | pl1 | 512 | 1 |
| printer2 | server | pl2 | 512 | 1 |
| printer3 | server | pl3 | 512 | 1 |
| expo1 | desktop | pl0 | 1024 | 2 |
| expo2 | desktop | pl0 | 1024 | 2 |
| expo3 | desktop | pl0 | 1024 | 2 |
| expo4 | desktop | pl0 | 1024 | 2 |
| conserge1 | desktop | pl0 | 1024 | 2 |
| conserge2 | desktop | pl0 | 1024 | 2 |
| pc1 | desktop | pl1 | 1024 | 2 |
| pc2 | desktop | pl2 | 1024 | 2 |
| pc3 | desktop | pl3 | 1024 | 2 |
| dir1 | desktop | pl3_direccio | 1024 | 2 |
| dir2 | desktop | pl3_direccio | 1024 | 2 |
| dir3 | desktop | pl3_direccio | 1024 | 2 |
| pve01 | ISO Proxmox pròpia | privada | 8192 | 4 |

## Recursos de pve01

4 vCPU, 8192 MB de RAM i 64 GB de disc (ext4, sense ZFS), xarxa `privada`,
IP 10.7.0.133/26, MAC 080027070014. La virtualització anidada s'activa amb
`VBoxManage modifyvm pve01 --nested-hw-virt on` dins `deploy_pve01.sh`.
Valors a les variables PVE01_* de `common.sh`.

## IP per DHCP

Els templates Debian obtenen la IP per DHCP (`iface enp0s3 inet dhcp`, valor
per defecte de l'instal·lador, comprovat en un clon). Com que encara no hi ha
servidor DHCP a les xarxes internes, les màquines queden amb adreça d'enllaç
local fins a l'activitat de serveis de xarxa. Només pve01 té IP estàtica.

## Requisits per reproduir el desplegament

1. Copiar `.env.example` a `.env` i definir `SYSADMIN_PASSWORD` (no es versiona).
2. `make ssh-keys` per generar les claus del projecte, si no existeixen.
3. Routers en marxa (`make deploy-routers` i arrencar-los): pve01 es valida a través de mikrotik0.
4. `make create_templates` i `make deploy_equipment`.
