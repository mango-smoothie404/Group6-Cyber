###############################################################################
# CYNA — variables.tf
# Toutes les variables injectées via secrets.tfvars (fichier hors GIT)
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
  description = "Datastore principal pour les disques VMs et LXC"
  type        = string
  default     = "local-zfs"
}
