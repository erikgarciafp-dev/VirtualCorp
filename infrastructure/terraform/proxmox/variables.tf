variable "proxmox_endpoint" {
  type        = string
  description = "URL de l'API de Proxmox VE (a terraform.local.tfvars)."
}

variable "proxmox_token_id" {
  type        = string
  description = "ID del token API, per exemple terraform@pve!tf."
}

variable "proxmox_token_secret" {
  type        = string
  sensitive   = true
  description = "Secret del token API (a terraform.local.tfvars, fora de Git)."
}

variable "proxmox_insecure" {
  type        = bool
  default     = true
  description = "pve01 usa un certificat autosignat al laboratori."
}

variable "node_name" {
  type    = string
  default = "pve01"
}

variable "node_address" {
  type        = string
  default     = "10.7.0.133"
  description = "Adreca de pve01 per a les operacions SSH del proveidor."
}

variable "ssh_private_key_path" {
  type    = string
  default = "~/.ssh/vcorp_sysadmin"
}

variable "ssh_public_key_files" {
  type = list(string)
  default = [
    "../../../configs/ssh/vcorp_auditor.pub",
    "../../../configs/ssh/vcorp_sysadmin.pub",
  ]
  description = "Claus publiques autoritzades a kea01, relatives a aquest directori."
}

variable "template_file_id" {
  type    = string
  default = "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
}

variable "kea01" {
  type = object({
    vm_id     = number
    hostname  = string
    address   = string
    gateway   = string
    dns       = string
    bridge    = string
    datastore = string
    cores     = number
    memory_mb = number
    disk_gb   = number
  })
  default = {
    vm_id     = 201
    hostname  = "kea01"
    address   = "10.7.0.136/26"
    gateway   = "10.7.0.129"
    dns       = "8.8.8.8"
    bridge    = "vmbr0"
    datastore = "local-lvm"
    cores     = 1
    memory_mb = 512
    disk_gb   = 6
  }
}
