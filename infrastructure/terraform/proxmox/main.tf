terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.112.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  insecure  = var.proxmox_insecure

  ssh {
    agent       = false
    username    = "root"
    private_key = file(pathexpand(var.ssh_private_key_path))

    node {
      name    = var.node_name
      address = var.node_address
    }
  }
}

locals {
  ssh_public_keys = [
    for f in var.ssh_public_key_files : trimspace(file("${path.module}/${f}"))
  ]
}

resource "proxmox_virtual_environment_container" "kea01" {
  node_name     = var.node_name
  vm_id         = var.kea01.vm_id
  description   = "Servidor DHCP Kea (gestionat amb Terraform)"
  unprivileged  = true
  start_on_boot = true
  started       = true

  initialization {
    hostname = var.kea01.hostname

    dns {
      servers = [var.kea01.dns]
    }

    ip_config {
      ipv4 {
        address = var.kea01.address
        gateway = var.kea01.gateway
      }
    }

    user_account {
      keys = local.ssh_public_keys
    }
  }

  cpu {
    cores = var.kea01.cores
  }

  memory {
    dedicated = var.kea01.memory_mb
  }

  disk {
    datastore_id = var.kea01.datastore
    size         = var.kea01.disk_gb
  }

  network_interface {
    name   = "eth0"
    bridge = var.kea01.bridge
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = "debian"
  }

  features {
    nesting = true
  }
}

output "kea01" {
  value = {
    vm_id    = proxmox_virtual_environment_container.kea01.vm_id
    hostname = var.kea01.hostname
    address  = var.kea01.address
    gateway  = var.kea01.gateway
    bridge   = var.kea01.bridge
    template = var.template_file_id
  }
}
