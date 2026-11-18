# Terraform: contenidor LXC `kea01` a Proxmox

Crea el contenidor `kea01` (servidor DHCP Kea) a `pve01` amb el provider `bpg/proxmox` (sèrie 0.112.x).

## Requisits

- Terraform >= 1.6 al node de control.
- Túnel WireGuard actiu: `pve01` (10.7.0.133) només s'hi arriba per la VPN.
- Plantilla Debian 13 `amd64`, rol, usuari i token de Terraform: `infrastructure/bash/prepare_terraform_proxmox.sh`.
- NIC de `pve01` amb `--nicpromisc1 allow-all` (ja ho fa `deploy_pve01.sh`); sense això els contenidors no reben tràfic unicast a VirtualBox.

## Credencials

El script escriu `proxmox_endpoint`, `proxmox_token_id` i `proxmox_token_secret` a `terraform.local.tfvars` (mode 0600, ignorat per Git). No hi ha cap token ni contrasenya als `.tf` ni al repositori.

## Ús

    cd infrastructure/terraform/proxmox
    terraform init
    terraform fmt -check
    terraform validate
    terraform plan -var-file=terraform.local.tfvars
    terraform apply -var-file=terraform.local.tfvars

`-var-file` és necessari perquè el nom `terraform.local.tfvars` no es carrega automàticament.

## Paràmetres de `kea01`

Definits a la variable `kea01` de `variables.tf`: ID 201, hostname `kea01`, IP 10.7.0.136/26, gateway 10.7.0.129, DNS 8.8.8.8, bridge `vmbr0` (xarxa privada), plantilla `local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst`, 1 nucli, 512 MB de RAM i 6 GB de disc a `local-lvm`. Contenidor sense privilegis, amb arrencada automàtica i les claus SSH de `vcorp_auditor` i `sysadmin`.

## Verificació

Després de l'`apply`, `terraform plan` ha de dir `No changes` i `ssh -i ~/.ssh/vcorp_sysadmin root@10.7.0.136` ha d'entrar.

## Git

Es versiona `.terraform.lock.hcl`. S'ignoren `.terraform/`, `terraform.tfstate*` i `terraform.local.tfvars`.
