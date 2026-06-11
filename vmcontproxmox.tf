###############################################################################
# CYNA — Infrastructure as Code Terraform
# Projet : CYNA Cybersecurity SaaS (EDR / XDR / SOC)
# Rédacteur : KHALDI Ilyas — Cloud + Infrastructure
# École : INGETIS / SUP DE VINCI — CPI Bachelor RNCP 38478
# Promo : 2025–2026
#
# IMPORTANT : Ce fichier décrit l'infrastructure réelle déployée sur Proxmox.
# Il n'est pas appliqué en production en raison des contraintes RAM du serveur
# (certaines VMs ne peuvent pas tourner simultanément). Il sert de référence
# IaC reproductible et constitue la documentation technique du déploiement.
#
# Prérequis :
#   - Proxmox VE >= 8.x
#   - Provider bpg/proxmox >= 0.66.0
#   - Token API Proxmox avec droits VM.Allocate, VM.Config.*, Datastore.AllocateSpace
#   - Templates ISO disponibles dans le stockage local
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.66.0"
    }
  }
}

###############################################################################
# PROVIDER — Connexion au nœud Proxmox
###############################################################################

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true # Certificat auto-signé Proxmox — à remplacer par un vrai cert en prod
}

###############################################################################
# VARIABLES
###############################################################################

variable "proxmox_endpoint" {
  description = "URL de l'API Proxmox (ex: https://192.168.1.10:8006/)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Token API Proxmox au format USER@pam!TOKENID=SECRET"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Nom du nœud Proxmox cible"
  type        = string
  default     = "laurent"
}

variable "storage_pool" {
  description = "Datastore principal pour les disques VMs"
  type        = string
  default     = "local-zfs"
}

###############################################################################
# LOCALS — Plan d'adressage et configuration réseau (DAT CYNA)
###############################################################################

locals {
  # Passerelles par VLAN
  gw_vlan10 = "10.0.10.1"   # VLAN 10 — User / Endpoints
  gw_vlan20 = "10.0.20.1"   # VLAN 20 — DMZ
  gw_vlan40 = "10.0.40.1"   # VLAN 40 — Serveurs internes
  gw_vlan50 = "10.0.50.1"   # VLAN 50 — Stockage
  gw_vlan60 = "10.0.60.1"   # VLAN 60 — Administration / Bastion

  dns_primary   = "10.0.40.2" # srv-ad (Active Directory / DNS interne)
  dns_secondary = "1.1.1.1"   # Cloudflare — fallback externe

  # Tags Proxmox pour identification rapide dans l'interface
  tag_firewall   = "firewall"
  tag_siem       = "siem"
  tag_auth       = "auth"
  tag_ad         = "active-directory"
  tag_bastion    = "bastion"
  tag_nas        = "storage"
  tag_proxy      = "reverse-proxy"
  tag_ansible    = "automation"
  tag_vpn        = "vpn"
  tag_endpoint   = "endpoint"
}

###############################################################################
# VM 200 — PFR-OPNsense (Firewall + Routeur + VPN WireGuard + IDS Suricata)
# VLAN : LAN (bridge principal) — IP : 10.0.10.1
# Rôle : Point d'entrée unique, filtrage stateful, NAT, DHCP, DNS Unbound,
#         VPN WireGuard, IDS/IPS Suricata, export Syslog vers Wazuh
###############################################################################

resource "proxmox_virtual_environment_vm" "opnsense" {
  name        = "PFR-OPNsense"
  vm_id       = 200
  node_name   = var.proxmox_node
  description = "Firewall OPNsense — Point d'entrée unique WAN/LAN. Services : WireGuard VPN, Suricata IPS, DHCP, DNS Unbound, Syslog→Wazuh"
  tags        = [local.tag_firewall]

  on_boot  = true
  started  = true

  cpu {
    cores   = 2
    sockets = 1
    type    = "x86-64-v2-AES" # AES-NI requis pour les performances WireGuard
  }

  memory {
    dedicated = 2048
  }

  # Interface WAN — exposée sur Internet (seul port UDP WireGuard ouvert)
  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = 0 # WAN — pas de tag VLAN
  }

  # Interface LAN — routeur inter-VLAN
  network_device {
    bridge  = "vmbr1"
    model   = "virtio"
    vlan_id = 10 # VLAN 10 — User/Endpoints
  }

  disk {
    datastore_id = var.storage_pool
    size         = 20
    interface    = "virtio0"
    file_format  = "raw"
  }

  operating_system {
    type = "other" # FreeBSD — Proxmox n'a pas de type natif FreeBSD
  }

  # Démarrage prioritaire : OPNsense doit être up avant toutes les autres VMs
  boot_order = ["virtio0"]

  lifecycle {
    # Ne pas recréer la VM si l'ISO change (déjà installé)
    ignore_changes = [cdrom]
  }
}

###############################################################################
# VM 199 — PFR-Winserver-2022 (Active Directory + AD Connect + DNS + GPO)
# VLAN 40 — Serveurs internes — IP : 10.0.40.2
# Rôle : Contrôleur de domaine cyna.labo, gestion GPO, synchronisation
#         hybride Entra ID via AD Connect (Password Hash Sync, cycle 30 min)
###############################################################################

resource "proxmox_virtual_environment_vm" "samba_ad" {
  name        = "PFR-SAMBA-AD"
  vm_id       = 203 # VM 199 en prod — VM 203 dans l'inventaire Proxmox réel
  node_name   = var.proxmox_node
  description = "Active Directory Windows Server 2022 — Domaine cyna.labo. GPO, DNS interne, AD Connect → Entra ID (PHS, sync 30min)"
  tags        = [local.tag_ad]

  on_boot = true
  started = true

  cpu {
    cores   = 2
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096 # 4 Go minimum pour AD + AD Connect
  }

  network_device {
    bridge  = "vmbr1"
    model   = "virtio"
    vlan_id = 40 # VLAN 40 — Serveurs
  }

  disk {
    datastore_id = var.storage_pool
    size         = 60 # 60 Go — OS Windows Server + base AD + logs
    interface    = "virtio0"
    file_format  = "raw"
  }

  # IP fixe — DNS du domaine cyna.labo
  initialization {
    ip_config {
      ipv4 {
        address = "10.0.40.2/24"
        gateway = local.gw_vlan40
      }
    }
    dns {
      servers = ["127.0.0.1"] # AD pointe sur lui-même pour le DNS
    }
  }

  operating_system {
    type = "win11" # Windows Server 2022 — type win11 dans Proxmox
  }
}

###############################################################################
# VM 205 — PFR-Wazuh (SIEM — Wazuh Manager + OpenSearch Dashboard)
# VLAN 40 — Serveurs internes — IP : 10.0.40.3
# Rôle : Centralisation logs (agents + Syslog OPNsense UDP 514),
#         alertes temps réel, SCA, corrélation Suricata
###############################################################################

resource "proxmox_virtual_environment_vm" "wazuh" {
  name        = "PFR-Wazuh"
  vm_id       = 205
  node_name   = var.proxmox_node
  description = "SIEM Wazuh Manager + OpenSearch Dashboard — Ubuntu 24.04 LTS. Collecte : agents Wazuh + Syslog OPNsense (UDP 514). Rétention logs : 90 jours minimum."
  tags        = [local.tag_siem]

  on_boot = true
  started = true

  cpu {
    cores   = 4  # Wazuh + OpenSearch sont gourmands en CPU
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 8192 # 8 Go — OpenSearch nécessite au minimum 4 Go de heap JVM
  }

  network_device {
    bridge  = "vmbr1"
    model   = "virtio"
    vlan_id = 40
  }

  disk {
    datastore_id = var.storage_pool
    size         = 100 # 100 Go — stockage des logs (rétention 90 jours)
    interface    = "virtio0"
    file_format  = "raw"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "10.0.40.3/24"
        gateway = local.gw_vlan40
      }
    }
    dns {
      servers = [local.dns_primary, local.dns_secondary]
    }
  }

  operating_system {
    type = "l26" # Linux 2.6+ — Ubuntu 24.04 LTS
  }
}

###############################################################################
# VM 201 — PFR-Debian-Bastion (Serveur Bastion SSH)
# VLAN 60 — Administration — IP : 10.0.60.2
# Rôle : Point d'accès SSH unique vers les VMs critiques.
#         Authentification par clé uniquement — mot de passe désactivé.
#         Agent Wazuh déployé pour audit des sessions SSH.
###############################################################################

resource "proxmox_virtual_environment_vm" "bastion" {
  name        = "PFR-Debian-Bastion"
  vm_id       = 201
  node_name   = var.proxmox_node
  description = "Bastion SSH Debian 13 — VLAN Admin (10.0.60.0/28). Accès SSH par clé uniquement. Zéro accès direct aux VMs critiques sans passer par ce bastion."
  tags        = [local.tag_bastion]

  on_boot = true
  started = true

  cpu {
    cores   = 1
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 1024
  }

  network_device {
    bridge  = "vmbr1"
    model   = "virtio"
    vlan_id = 60 # VLAN 60 — Administration isolée
  }

  disk {
    datastore_id = var.storage_pool
    size         = 20
    interface    = "virtio0"
    file_format  = "raw"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "10.0.60.2/28"
        gateway = local.gw_vlan60
      }
    }
    dns {
      servers = [local.dns_primary, local.dns_secondary]
    }
  }

  operating_system {
    type = "l26"
  }
}

###############################################################################
# VM 207 — LeNAS (TrueNAS — Stockage centralisé NAS)
# VLAN 50 — Stockage — IP : 10.0.50.2
# Rôle : Stockage NAS centralisé, partages SMB/NFS pour le domaine,
#         synchronisation FreeFileSync vers cloud S3 (backup hors-site)
###############################################################################

resource "proxmox_virtual_environment_vm" "nas" {
  name        = "LeNAS"
  vm_id       = 207
  node_name   = var.proxmox_node
  description = "TrueNAS — Stockage NAS VLAN 50. Partages SMB/NFS. Backup hors-site via FreeFileSync → S3 cloud (cron 02h00 quotidien + dimanche 03h00)."
  tags        = [local.tag_nas]

  on_boot = true
  started = true

  cpu {
    cores   = 2
    sockets = 1
    type    = "host" # Passthrough CPU recommandé pour TrueNAS (accès ZFS optimisé)
  }

  memory {
    dedicated = 4096 # ZFS recommande 1 Go RAM par To de stockage minimum
  }

  network_device {
    bridge  = "vmbr1"
    model   = "virtio"
    vlan_id = 50 # VLAN 50 — Stockage isolé
  }

  # Disque OS TrueNAS
  disk {
    datastore_id = var.storage_pool
    size         = 32
    interface    = "virtio0"
    file_format  = "raw"
  }

  # Disque de données NAS (à passer en physique via passthrough en prod)
  disk {
    datastore_id = var.storage_pool
    size         = 200
    interface    = "virtio1"
    file_format  = "raw"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "10.0.50.2/28"
        gateway = local.gw_vlan50
      }
    }
    dns {
      servers = [local.dns_primary]
    }
  }

  operating_system {
    type = "other" # TrueNAS Scale (Linux) ou Core (FreeBSD)
  }
}

###############################################################################
# VM 112 — PFR-CYPO002 (Endpoint Windows 11 simulé — Agent Wazuh)
# VLAN 10 — User/Endpoints — IP : 10.0.10.112
# Rôle : Poste utilisateur simulé joint au domaine cyna.labo.
#         Agent Wazuh déployé via GPO. Tests de détection et scénarios d'attaque.
###############################################################################

resource "proxmox_virtual_environment_vm" "endpoint_cypo002" {
  name        = "PFR-CYPO002"
  vm_id       = 112
  node_name   = var.proxmox_node
  description = "Endpoint Windows 11 — Domaine cyna.labo. Agent Wazuh déployé via GPO (MSI silencieux). Utilisé pour les tests de détection Wazuh et simulations d'attaque."
  tags        = [local.tag_endpoint]

  on_boot = false # Endpoint allumé à la demande uniquement (contrainte RAM)
  started = false

  cpu {
    cores   = 2
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  network_device {
    bridge  = "vmbr1"
    model   = "virtio"
    vlan_id = 10 # VLAN 10 — Endpoints utilisateurs
  }

  disk {
    datastore_id = var.storage_pool
    size         = 60
    interface    = "virtio0"
    file_format  = "raw"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "10.0.10.112/24"
        gateway = local.gw_vlan10
      }
    }
    dns {
      servers = [local.dns_primary]
    }
  }

  operating_system {
    type = "win11"
  }
}

###############################################################################
# CONTENEUR LXC 104 — PFR-Debian-Authelia (MFA — Double authentification)
# VLAN 40 — Serveurs — IP : 10.0.40.5
# Rôle : Portail MFA TOTP + LDAP (Active Directory cyna.labo).
#         Protège toutes les applications internes derrière Nginx.
#         Compte de service : authelia-svc (lecture seule AD)
###############################################################################

resource "proxmox_virtual_environment_container" "authelia" {
  description   = "Authelia MFA — Proxy d'authentification TOTP + LDAP. Protège Wazuh Dashboard, GLPI, Zabbix. Compte service : authelia-svc@cyna.labo (lecture seule)."
  node_name     = var.proxmox_node
  vm_id         = 104
  tags          = [local.tag_auth]

  on_boot  = true
  started  = true
  unprivileged = true # Conteneur non-privilégié — bonne pratique sécurité

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
    swap      = 256
  }

  network_interface {
    name    = "eth0"
    bridge  = "vmbr1"
    vlan_id = 40
  }

  disk {
    datastore_id = var.storage_pool
    size         = 8
  }

  initialization {
    ip_config {
      ipv4 {
        address = "10.0.40.5/24"
        gateway = local.gw_vlan40
      }
    }
    dns {
      servers = [local.dns_primary, local.dns_secondary]
    }
    hostname = "srv-authelia"
  }

  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_amd64.tar.zst"
    type             = "debian"
  }
}

###############################################################################
# CONTENEUR LXC 105 — PFR-Nginx (Reverse Proxy)
# VLAN 20 — DMZ — IP : 10.0.20.2
# Rôle : Reverse proxy HTTPS pour toutes les applications internes.
#         Terminaison TLS, auth_request vers Authelia (MFA).
#         Headers de sécurité (HSTS, X-Frame-Options, CSP).
###############################################################################

resource "proxmox_virtual_environment_container" "nginx" {
  description   = "Nginx Reverse Proxy — DMZ (10.0.20.2). Terminaison TLS, intégration auth_request Authelia. Applications exposées : Wazuh Dashboard, GLPI, Zabbix."
  node_name     = var.proxmox_node
  vm_id         = 105
  tags          = [local.tag_proxy]

  on_boot  = true
  started  = true
  unprivileged = true

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
    swap      = 256
  }

  network_interface {
    name    = "eth0"
    bridge  = "vmbr1"
    vlan_id = 20 # VLAN 20 — DMZ
  }

  disk {
    datastore_id = var.storage_pool
    size         = 8
  }

  initialization {
    ip_config {
      ipv4 {
        address = "10.0.20.2/24"
        gateway = local.gw_vlan20
      }
    }
    dns {
      servers = [local.dns_primary, local.dns_secondary]
    }
    hostname = "srv-nginx"
  }

  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_amd64.tar.zst"
    type             = "debian"
  }
}

###############################################################################
# CONTENEUR LXC 108 — PFR-Ansible (Automatisation / IaC)
# VLAN 60 — Administration — IP : 10.0.60.5
# Rôle : Nœud de contrôle Ansible. Déploiement VPN WireGuard, agents Wazuh,
#         durcissement OS. Secrets gérés via Ansible Vault (AES-256).
###############################################################################

resource "proxmox_virtual_environment_container" "ansible" {
  description   = "Ansible Control Node — VLAN Admin. Playbooks : wireguard_deploy.yml, wazuh-agent deploy, hardening CIS. Vault AES-256 pour secrets (clé API OPNsense, creds WinRM)."
  node_name     = var.proxmox_node
  vm_id         = 108
  tags          = [local.tag_ansible]

  on_boot  = true
  started  = true
  unprivileged = true

  cpu {
    cores = 1
  }

  memory {
    dedicated = 1024
    swap      = 512
  }

  network_interface {
    name    = "eth0"
    bridge  = "vmbr1"
    vlan_id = 60 # VLAN 60 — Administration (accès à toutes les zones pour les déploiements)
  }

  disk {
    datastore_id = var.storage_pool
    size         = 16 # 16 Go — dépôts Ansible, logs de déploiement, vault
  }

  initialization {
    ip_config {
      ipv4 {
        address = "10.0.60.5/28"
        gateway = local.gw_vlan60
      }
    }
    dns {
      servers = [local.dns_primary, local.dns_secondary]
    }
    hostname = "srv-ansible"
  }

  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_amd64.tar.zst"
    type             = "debian"
  }
}

###############################################################################
# CONTENEUR LXC 150 — NEW-VPN (WireGuard — Nouveau point d'entrée VPN)
# VLAN 40 — Serveurs — IP : 10.0.40.10
# Rôle : Instance WireGuard secondaire ou de remplacement.
#         Déployé en LXC pour tests de migration / basculement VPN.
###############################################################################

resource "proxmox_virtual_environment_container" "vpn" {
  description   = "WireGuard VPN — Instance LXC. Peers déployés automatiquement via Ansible (wireguard_deploy.yml). Point d'entrée alternatif ou de test."
  node_name     = var.proxmox_node
  vm_id         = 150
  tags          = [local.tag_vpn]

  on_boot  = true
  started  = true
  unprivileged = false # WireGuard nécessite des droits réseau élevés dans LXC

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
    swap      = 256
  }

  network_interface {
    name    = "eth0"
    bridge  = "vmbr1"
    vlan_id = 40
  }

  disk {
    datastore_id = var.storage_pool
    size         = 4
  }

  initialization {
    ip_config {
      ipv4 {
        address = "10.0.40.10/24"
        gateway = local.gw_vlan40
      }
    }
    dns {
      servers = [local.dns_primary, local.dns_secondary]
    }
    hostname = "srv-vpn"
  }

  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_amd64.tar.zst"
    type             = "debian"
  }
}

###############################################################################
# OUTPUTS — Récapitulatif IPs après déploiement
###############################################################################

output "infrastructure_summary" {
  description = "Récapitulatif de l'infrastructure CYNA déployée"
  value = {
    firewall  = "OPNsense        → VM 200 — 10.0.10.1   (VLAN 10 — WAN/LAN)"
    ad        = "Active Directory → VM 203 — 10.0.40.2   (VLAN 40 — Serveurs)"
    siem      = "Wazuh SIEM      → VM 205 — 10.0.40.3   (VLAN 40 — Serveurs)"
    bastion   = "Bastion SSH     → VM 201 — 10.0.60.2   (VLAN 60 — Admin)"
    nas       = "TrueNAS         → VM 207 — 10.0.50.2   (VLAN 50 — Stockage)"
    endpoint  = "CYPO002 Win11   → VM 112 — 10.0.10.112 (VLAN 10 — Endpoints)"
    authelia  = "Authelia MFA    → LXC 104 — 10.0.40.5  (VLAN 40 — Serveurs)"
    nginx     = "Nginx Proxy     → LXC 105 — 10.0.20.2  (VLAN 20 — DMZ)"
    ansible   = "Ansible Control → LXC 108 — 10.0.60.5  (VLAN 60 — Admin)"
    vpn       = "WireGuard VPN   → LXC 150 — 10.0.40.10 (VLAN 40 — Serveurs)"
  }
}
