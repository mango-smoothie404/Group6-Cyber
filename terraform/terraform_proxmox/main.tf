###############################################################################
# CYNA — main.tf
# Provisionnement Proxmox : 6 VMs + 4 conteneurs LXC
###############################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    proxmox = { source = "bpg/proxmox", version = ">= 0.66.0" }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true
}

# ── VM 200 — OPNsense (Firewall + WireGuard + Suricata) ──────────────────────
resource "proxmox_virtual_environment_vm" "opnsense" {
  name      = "PFR-OPNsense"
  vm_id     = 200
  node_name = var.proxmox_node
  on_boot   = true

  cpu    { cores = 2 ; type = "x86-64-v2-AES" }
  memory { dedicated = 2048 }
  disk   { datastore_id = var.storage_pool ; size = 20 ; interface = "virtio0" ; file_format = "raw" }
  network_device { bridge = "vmbr0" ; model = "virtio" }
  network_device { bridge = "vmbr1" ; model = "virtio" ; vlan_id = 10 }
  operating_system { type = "other" }
}

# ── VM 203 — Active Directory (Windows Server 2022) ──────────────────────────
resource "proxmox_virtual_environment_vm" "samba_ad" {
  name      = "PFR-SAMBA-AD"
  vm_id     = 203
  node_name = var.proxmox_node
  on_boot   = true

  cpu    { cores = 2 ; type = "x86-64-v2-AES" }
  memory { dedicated = 4096 }
  disk   { datastore_id = var.storage_pool ; size = 60 ; interface = "virtio0" ; file_format = "raw" }
  network_device { bridge = "vmbr1" ; model = "virtio" ; vlan_id = 40 }
  initialization {
    ip_config { ipv4 { address = "10.0.40.2/24" ; gateway = "10.0.40.1" } }
  }
  operating_system { type = "win11" }
}

# ── VM 205 — Wazuh SIEM (Ubuntu 24.04) ───────────────────────────────────────
resource "proxmox_virtual_environment_vm" "wazuh" {
  name      = "PFR-Wazuh"
  vm_id     = 205
  node_name = var.proxmox_node
  on_boot   = true

  cpu    { cores = 4 ; type = "x86-64-v2-AES" }
  memory { dedicated = 8192 }
  disk   { datastore_id = var.storage_pool ; size = 100 ; interface = "virtio0" ; file_format = "raw" }
  network_device { bridge = "vmbr1" ; model = "virtio" ; vlan_id = 40 }
  initialization {
    ip_config { ipv4 { address = "10.0.40.3/24" ; gateway = "10.0.40.1" } }
  }
  operating_system { type = "l26" }
}

# ── VM 201 — Bastion SSH (Debian) ─────────────────────────────────────────────
resource "proxmox_virtual_environment_vm" "bastion" {
  name      = "PFR-Debian-Bastion"
  vm_id     = 201
  node_name = var.proxmox_node
  on_boot   = true

  cpu    { cores = 1 }
  memory { dedicated = 1024 }
  disk   { datastore_id = var.storage_pool ; size = 20 ; interface = "virtio0" ; file_format = "raw" }
  network_device { bridge = "vmbr1" ; model = "virtio" ; vlan_id = 60 }
  initialization {
    ip_config { ipv4 { address = "10.0.60.2/28" ; gateway = "10.0.60.1" } }
  }
  operating_system { type = "l26" }
}

# ── VM 207 — TrueNAS (NAS + backup S3) ───────────────────────────────────────
resource "proxmox_virtual_environment_vm" "nas" {
  name      = "LeNAS"
  vm_id     = 207
  node_name = var.proxmox_node
  on_boot   = true

  cpu    { cores = 2 ; type = "host" }
  memory { dedicated = 4096 }
  disk   { datastore_id = var.storage_pool ; size = 32  ; interface = "virtio0" ; file_format = "raw" }
  disk   { datastore_id = var.storage_pool ; size = 200 ; interface = "virtio1" ; file_format = "raw" }
  network_device { bridge = "vmbr1" ; model = "virtio" ; vlan_id = 50 }
  initialization {
    ip_config { ipv4 { address = "10.0.50.2/28" ; gateway = "10.0.50.1" } }
  }
  operating_system { type = "other" }
}

# ── VM 112 — Endpoint Windows 11 (agent Wazuh) ───────────────────────────────
resource "proxmox_virtual_environment_vm" "endpoint_cypo002" {
  name      = "PFR-CYPO002"
  vm_id     = 112
  node_name = var.proxmox_node
  on_boot   = false
  started   = false  # Allumé à la demande (contrainte RAM)

  cpu    { cores = 2 }
  memory { dedicated = 4096 }
  disk   { datastore_id = var.storage_pool ; size = 60 ; interface = "virtio0" ; file_format = "raw" }
  network_device { bridge = "vmbr1" ; model = "virtio" ; vlan_id = 10 }
  operating_system { type = "win11" }
}

# ── LXC 104 — Authelia (MFA TOTP + LDAP) ─────────────────────────────────────
resource "proxmox_virtual_environment_container" "authelia" {
  vm_id        = 104
  node_name    = var.proxmox_node
  on_boot      = true
  unprivileged = true

  cpu    { cores = 1 }
  memory { dedicated = 512 ; swap = 256 }
  disk   { datastore_id = var.storage_pool ; size = 8 }
  network_interface { name = "eth0" ; bridge = "vmbr1" ; vlan_id = 40 }
  initialization {
    hostname = "srv-authelia"
    ip_config { ipv4 { address = "10.0.40.5/24" ; gateway = "10.0.40.1" } }
  }
  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_amd64.tar.zst"
    type             = "debian"
  }
}

# ── LXC 105 — Nginx (Reverse Proxy HTTPS) ────────────────────────────────────
resource "proxmox_virtual_environment_container" "nginx" {
  vm_id        = 105
  node_name    = var.proxmox_node
  on_boot      = true
  unprivileged = true

  cpu    { cores = 1 }
  memory { dedicated = 512 ; swap = 256 }
  disk   { datastore_id = var.storage_pool ; size = 8 }
  network_interface { name = "eth0" ; bridge = "vmbr1" ; vlan_id = 20 }
  initialization {
    hostname = "srv-nginx"
    ip_config { ipv4 { address = "10.0.20.2/24" ; gateway = "10.0.20.1" } }
  }
  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_amd64.tar.zst"
    type             = "debian"
  }
}

# ── LXC 108 — Ansible (Nœud de contrôle) ─────────────────────────────────────
resource "proxmox_virtual_environment_container" "ansible" {
  vm_id        = 108
  node_name    = var.proxmox_node
  on_boot      = true
  unprivileged = true

  cpu    { cores = 1 }
  memory { dedicated = 1024 ; swap = 512 }
  disk   { datastore_id = var.storage_pool ; size = 16 }
  network_interface { name = "eth0" ; bridge = "vmbr1" ; vlan_id = 60 }
  initialization {
    hostname = "srv-ansible"
    ip_config { ipv4 { address = "10.0.60.5/28" ; gateway = "10.0.60.1" } }
  }
  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_amd64.tar.zst"
    type             = "debian"
  }
}

# ── LXC 150 — WireGuard VPN ───────────────────────────────────────────────────
resource "proxmox_virtual_environment_container" "vpn" {
  vm_id        = 150
  node_name    = var.proxmox_node
  on_boot      = true
  unprivileged = false  # Droits réseau requis pour WireGuard

  cpu    { cores = 1 }
  memory { dedicated = 512 ; swap = 256 }
  disk   { datastore_id = var.storage_pool ; size = 4 }
  network_interface { name = "eth0" ; bridge = "vmbr1" ; vlan_id = 40 }
  initialization {
    hostname = "srv-vpn"
    ip_config { ipv4 { address = "10.0.40.10/24" ; gateway = "10.0.40.1" } }
  }
  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_amd64.tar.zst"
    type             = "debian"
  }
}
