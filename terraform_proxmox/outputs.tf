###############################################################################
# CYNA — outputs.tf
# Récapitulatif des IPs affichées après terraform apply
###############################################################################

output "infrastructure_summary" {
  description = "Récapitulatif de l'infrastructure CYNA déployée"
  value = {
    firewall = "OPNsense         → VM  200 — 10.0.10.1    (VLAN 10 — WAN/LAN)"
    ad       = "Active Directory → VM  203 — 10.0.40.2    (VLAN 40 — Serveurs)"
    siem     = "Wazuh SIEM       → VM  205 — 10.0.40.3    (VLAN 40 — Serveurs)"
    bastion  = "Bastion SSH      → VM  201 — 10.0.60.2    (VLAN 60 — Admin)"
    nas      = "TrueNAS          → VM  207 — 10.0.50.2    (VLAN 50 — Stockage)"
    endpoint = "CYPO002 Win11    → VM  112 — 10.0.10.112  (VLAN 10 — Endpoints)"
    authelia = "Authelia MFA     → LXC 104 — 10.0.40.5    (VLAN 40 — Serveurs)"
    nginx    = "Nginx Proxy      → LXC 105 — 10.0.20.2    (VLAN 20 — DMZ)"
    ansible  = "Ansible Control  → LXC 108 — 10.0.60.5    (VLAN 60 — Admin)"
    vpn      = "WireGuard VPN    → LXC 150 — 10.0.40.10   (VLAN 40 — Serveurs)"
  }
}
