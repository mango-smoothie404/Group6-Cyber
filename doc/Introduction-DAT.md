Introduction

Dans le cadre du projet CYNA, nous devions concevoir et mettre en place une infrastructure informatique répondant aux besoins d’une entreprise spécialisée dans la cybersécurité.

Le document de cadrage initial prévoyait une architecture assez complète, avec une infrastructure hybride, plusieurs sites géographiques, une interconnexion entre Genève et Paris, ainsi qu’une partie cloud.

Cependant, lors de la phase de réalisation, nous avons été confrontés à des contraintes budgétaires, matérielles et techniques. Nous avons donc fait évoluer l’architecture prévue afin de proposer une solution plus réaliste, mais toujours exploitable dans un contexte d’entreprise.

L’objectif de ce DAT est donc de présenter l’architecture réellement mise en place, les choix techniques effectués, les raisons de ces choix, ainsi que les preuves de fonctionnement de l’infrastructure.

Cette évolution ne remet pas en cause les objectifs du projet. Elle montre au contraire notre capacité à adapter une architecture à des contraintes réelles, notamment le budget, l’hébergement, la simplicité d’administration et la mobilité des utilisateurs. 

Rappel

Lors du document de cadrage, nous avions défini une architecture cible ambitieuse basée sur un modèle hybride.

Cette architecture reposait sur :

un site principal à Genève,
une filiale à Paris,
une interconnexion sécurisée entre les deux sites (SD-WAN),
une intégration avec des services cloud (Azure),
la mise en place de solutions avancées de cybersécurité (SOC, SIEM, EDR/XDR),
une infrastructure virtualisée avec conteneurisation (Kubernetes),
une supervision centralisée et automatisée.

L’objectif était de proposer une infrastructure moderne, sécurisée, scalable et adaptée à une entreprise de cybersécurité.

Lors de la phase de mise en œuvre, plusieurs limites sont apparues, rendant cette architecture difficilement réalisable dans le cadre du projet. 


La mise en place d’une infrastructure multi-sites avec redondance, équipements réseau avancés et solutions de sécurité professionnelles implique des coûts importants :

équipements réseau (firewalls, switchs, liens redondés),
licences (SIEM, EDR/XDR, solutions cloud),
coûts d’hébergement et de consommation cloud.

Ces coûts dépassent largement les moyens disponibles pour le projet.

L’infra faisable.

L’infrastructure du projet repose sur un environnement hébergé chez un membre du groupe (ainsi qu’une machine windows en cloud).

Cela limite :

la capacité matérielle disponible,
la redondance réelle des équipements,
la possibilité de simuler plusieurs sites physiques (Genève / Paris).

C’est donc une version simplifiée mais réaliste de celle prévue initialement.

Elle permet de répondre aux besoins principaux du projet tout en tenant compte des contraintes réelles.

Cette évolution montre notre capacité à adapter une solution technique en fonction du contexte, ce qui correspond à une problématique fréquente en entreprise.

L’ensemble des services est hébergé sur un seul serveur de virtualisation, ce qui permet de regrouper tous les composants du système d’information au même endroit tout en conservant une bonne isolation grâce aux machines virtuelles.

L’accès à l’infrastructure se fait exclusivement à distance via un VPN WireGuard. Lorsqu’un utilisateur se connecte, il entre dans le réseau interne mais n’a pas directement accès aux services sensibles. Une couche supplémentaire de sécurité est mise en place avec Authelia, qui agit comme un point de contrôle d’authentification avant d’autoriser l’accès aux différentes applications.

Le cœur de l’infrastructure repose sur un contrôleur de domaine Samba Active Directory, qui permet de gérer les utilisateurs, les postes et les politiques de sécurité. Les machines clientes sont intégrées au domaine, ce qui permet d’appliquer automatiquement des configurations via des GPO, comme le montage des lecteurs réseau, le déploiement de l’agent Wazuh ou encore la personnalisation de l’environnement utilisateur.

Les données sont centralisées sur un serveur de stockage TrueNAS. Ce NAS contient les fichiers utilisateurs, les profils itinérants ainsi que les partages réseau. Cela permet aux utilisateurs de retrouver leur environnement de travail même en cas de changement de machine. Cette centralisation facilite également la gestion des données et leur sécurisation.

Une solution de supervision est mise en place avec Wazuh, qui permet de surveiller les machines du système d’information et de remonter des alertes en cas de comportement suspect. Les agents Wazuh sont déployés automatiquement sur les postes via les GPO, ce qui simplifie leur gestion et garantit une couverture homogène.

L’administration de l’infrastructure est sécurisée grâce à un serveur bastion, qui permet de centraliser les accès administrateurs et d’éviter les connexions directes aux machines critiques. Cela renforce la sécurité globale en limitant les points d’entrée sensibles.

En complément, une solution de sauvegarde a été mise en place. Les données stockées sur le NAS sont synchronisées vers une machine hébergée dans le cloud via FreeFileSync. Cela permet de disposer d’une copie externe des données en cas de problème sur l’infrastructure principale, tout en évitant les coûts d’une solution cloud complète.

Enfin, le réseau est protégé par un firewall (OPNsense), qui contrôle les flux entrants et sortants, gère les accès VPN et assure un premier niveau de sécurité.

Dans l’ensemble, cette architecture permet de proposer un système cohérent, sécurisé et fonctionnel. Même si elle est plus simple que celle prévue initialement, elle reste proche d’un fonctionnement réel en entreprise, notamment grâce à la centralisation des services, l’accès distant sécurisé, la gestion des utilisateurs et la protection des données.

OPNsense : firewall principal de l’infrastructure, gestion des flux réseau et point d’entrée du VPN WireGuard.

VM Bastion / Reverse Proxy (Debian) : machine utilisée pour sécuriser les accès administrateurs et héberger les services d’accès (Authelia, proxy).

Authelia (sur Debian) : service d’authentification permettant de contrôler l’accès aux applications internes après connexion VPN.

Samba Active Directory : contrôleur de domaine permettant la gestion des utilisateurs, des postes et des politiques de groupe (GPO).

TrueNAS (NAS) : serveur de stockage centralisé contenant les données utilisateurs, les profils itinérants et les partages réseau.

Wazuh Server : solution de supervision et de sécurité permettant de collecter les logs et de détecter des comportements suspects sur les machines.

Machine de sauvegarde (cloud) : serveur distant utilisé pour stocker une copie des données du NAS via FreeFileSync.
