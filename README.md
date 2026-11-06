# TP Docker Swarm sur Azure (Terraform + Ansible + Portainer)

Trois VM Ubuntu 24.04 dans un abonnement **Azure for Students**, un cluster Docker Swarm
(1 manager + 2 workers par défaut) et **Portainer CE** pour piloter le cluster.

```
terraform/  -> crée réseau, NSG, IP publiques, VM  + génère ansible/inventory.ini
ansible/    -> installe Docker, init/join Swarm, déploie Portainer (+ stack de démo)
scripts/    -> check-azure.sh : régions, quota et tailles autorisés pour TON abonnement
```

## 0. Prérequis sur le poste de l'élève

- Azure CLI (`az`), Terraform ≥ 1.6 (ou OpenTofu), `make`, Python ≥ 3.10 avec `venv` (`sudo apt install python3-venv` sur Debian/Ubuntu)
- **Pas besoin d'installer Ansible** : `make swarm` l'installe tout seul dans `.venv/`
  (version fixée dans `requirements.txt`, ansible-core ≥ 2.16 pour piloter Ubuntu 24.04)
- Sous Windows : travailler dans **WSL** (Ansible ne tourne pas nativement sous Windows)
- `az login`, puis :

```bash
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

## 1. Vérifier ce que l'abonnement étudiant autorise

Les comptes Azure for Students sont bridés, et **différemment d'un élève à l'autre** :

| Contrainte | Valeur habituelle |
|---|---|
| Régions | ~5 régions imposées par une policy « Allowed resource deployment regions » |
| Quota vCPU | **4 vCPU par région**, non augmentable |
| Tailles | surtout la famille B ; certaines tailles renvoient `NotAvailableForSubscription` |

```bash
./scripts/check-azure.sh francecentral     # ou : make check REGION=swedencentral
```

Le script affiche les régions autorisées, le quota restant et les petites tailles réellement
utilisables dans la région. Choisir `location` et `vm_size` en conséquence.

**Le calcul qui compte : 3 VM × vCPU par VM ≤ 4.**

| Combinaison | vCPU | Remarque |
|---|---|---|
| 3 × `Standard_B1s` (1 vCPU / 1 Go) | 3 | **défaut**, swap ajouté automatiquement |
| 3 × `Standard_B1ms` (1 vCPU / 2 Go) | 3 | plus confortable si dispo |
| manager `Standard_B2ats_v2` + 2 × `B1s` | 4 | manager à 2 vCPU |
| 3 × `Standard_B2ats_v2` | 6 | refusé (quota) |

Terraform refuse de lui‑même une combinaison qui dépasse `vcpu_quota` (garde-fou avant
l'appel à Azure, pour les tailles qu'il connaît).

## 2. Créer les VM

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars   # adapter prefix / location / vm_size
make init
make infra
```

Par défaut :
- une paire de clés SSH est générée dans `terraform/.ssh/swarm_key` ;
- SSH (22) et Portainer (9443) ne sont ouverts **qu'à l'IP publique du poste** (détectée
  automatiquement) — à ouvrir avec `admin_cidr` si l'élève change de réseau ;
- les ports 80, 443, 8080 sont ouverts à Internet pour les applis du Swarm ;
- le trafic Swarm interne (2377, 7946, 4789) reste dans le VNet.

## 3. Monter le Swarm et Portainer

```bash
make swarm          # crée .venv (Ansible) au 1er lancement, puis ansible-playbook site.yml
make password       # mot de passe admin Portainer
```

Ouvrir `https://<IP du manager>:9443` (certificat auto-signé), utilisateur `admin`.
Le compte admin est créé d'office via un secret Swarm : pas de course contre le délai
d'initialisation de 5 minutes de Portainer.

Vérification en SSH :

```bash
make ssh
docker node ls
docker service ls
```

## 4. Démo (optionnel)

```bash
make demo
```

Déploie 6 réplicas de `traefik/whoami` sur le port 80. En rafraîchissant
`http://<IP de n'importe quel nœud>/`, le hostname change : routing mesh + load balancing.
Dans Portainer : *Swarm → Cluster visualizer* pour voir la répartition.

Idées d'exercices : `docker service scale demo_whoami=10`, `docker node update --availability drain worker-1`,
rolling update d'image, passer en 3 managers (`manager_count = 3`, `worker_count = 0`) et arrêter le leader.

## 5. Arrêter de consommer du crédit

```bash
make down          # détruit tout le groupe de ressources
```

Pour une simple pause : `az vm deallocate --ids $(az vm list -g <prefix>-rg --query "[].id" -o tsv)`
(les IP publiques Standard restent facturées, quelques centimes par jour).

## Paramètres Terraform

| Variable | Défaut | Rôle |
|---|---|---|
| `location` | `francecentral` | région (doit être autorisée !) |
| `prefix` | `swarm` | préfixe des ressources / nom du RG |
| `vm_size` | `Standard_B1s` | taille de toutes les VM |
| `manager_vm_size` | `null` | taille spécifique des managers |
| `vcpu_quota` | `4` | garde-fou quota |
| `manager_count` / `worker_count` | `1` / `2` | topologie (1 ou 3 managers) |
| `admin_cidr` | IP du poste | accès SSH + Portainer |
| `ssh_public_key_path` | génération | clé existante (RSA conseillé) |
| `public_app_ports` | `[80,443,8080]` | ports publics des applis |
| `os_disk_type` / `os_disk_size_gb` | `StandardSSD_LRS` / `30` | disque OS |

## Dépannage

| Erreur | Cause / solution |
|---|---|
| `RequestDisallowedByPolicy` | région non autorisée → changer `location` |
| `OperationNotAllowed … exceeding approved Total Regional Cores quota` | trop de vCPU → réduire `vm_size` |
| `SkuNotAvailable` / `NotAvailableForSubscription` | taille indisponible ici → autre taille B ou autre région autorisée |
| Ansible : `UNREACHABLE` | l'IP du poste a changé → `terraform apply` (ré-détecte l'IP) ou `admin_cidr` |
| Ansible : `unexpected keyword argument 'cert_file'` | Ansible système trop ancien → passer par `make swarm` (Ansible du `.venv`) |
| `make` : « Impossible de créer le venv » | `sudo apt install python3-venv` |
| Portainer ne répond pas | `docker service ps portainer_portainer --no-trunc` sur le manager |
