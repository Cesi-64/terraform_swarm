# ---------------------------------------------------------------------------
# Compte / région
# ---------------------------------------------------------------------------

variable "subscription_id" {
  description = "ID de l'abonnement Azure. Laisser null pour utiliser ARM_SUBSCRIPTION_ID."
  type        = string
  default     = null
}

variable "location" {
  description = <<-EOT
    Région Azure. ATTENTION : un compte Azure for Students n'a droit qu'à ~5 régions,
    différentes d'un élève à l'autre. Vérifier avec scripts/check-azure.sh
    (ou Portail > Policy > Assignments > "Allowed resource deployment regions").
  EOT
  type        = string
  default     = "francecentral"
}

variable "prefix" {
  description = "Préfixe des ressources (ex: initiales de l'élève). Minuscules, chiffres et tirets."
  type        = string
  default     = "swarm"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,15}$", var.prefix))
    error_message = "prefix : 2 à 15 caractères, minuscules, chiffres ou tirets."
  }
}

# ---------------------------------------------------------------------------
# Taille des VM — LE paramètre sensible pour les comptes étudiants
# ---------------------------------------------------------------------------

variable "vm_size" {
  description = <<-EOT
    Taille par défaut de toutes les VM.
    Azure for Students = quota de 4 vCPU par région en général :
      - 3 x Standard_B1s (1 vCPU / 1 Go)       = 3 vCPU  -> OK (défaut)
      - 3 x Standard_B1ms (1 vCPU / 2 Go)      = 3 vCPU  -> OK, plus confortable
      - 3 x Standard_B2ats_v2 (2 vCPU / 1 Go)  = 6 vCPU  -> REFUSÉ
  EOT
  type        = string
  default     = "Standard_B1s"
}

variable "manager_vm_size" {
  description = "Taille spécifique pour les managers (null = vm_size). Ex : Standard_B2ats_v2 + 2 workers B1s = 4 vCPU."
  type        = string
  default     = null
}

variable "vcpu_quota" {
  description = "Quota vCPU régional de l'abonnement (4 pour Azure for Students). Sert de garde-fou avant l'appel à Azure."
  type        = number
  default     = 4
}

variable "os_disk_type" {
  description = "Type de disque OS : Standard_LRS (HDD), StandardSSD_LRS ou Premium_LRS (B1s le supporte)."
  type        = string
  default     = "StandardSSD_LRS"
}

variable "os_disk_size_gb" {
  description = "Taille du disque OS en Go."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# Topologie du cluster
# ---------------------------------------------------------------------------

variable "manager_count" {
  description = "Nombre de managers Swarm (1 ou 3 — jamais 2, le quorum Raft ne le tolère pas)."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 3], var.manager_count)
    error_message = "manager_count doit valoir 1 ou 3."
  }
}

variable "worker_count" {
  description = "Nombre de workers Swarm."
  type        = number
  default     = 2
}

# ---------------------------------------------------------------------------
# Accès
# ---------------------------------------------------------------------------

variable "admin_username" {
  description = "Utilisateur Linux créé sur les VM."
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Clé publique SSH existante (RSA conseillé ; la clé privée doit être au même chemin sans .pub). Vide = Terraform génère une paire dans ./.ssh/."
  type        = string
  default     = ""
}

variable "admin_cidr" {
  description = "Plage autorisée pour SSH et Portainer. Vide = ton IP publique actuelle détectée automatiquement (/32)."
  type        = string
  default     = ""
}

variable "public_app_ports" {
  description = "Ports ouverts à tout Internet pour les applis déployées sur le Swarm (routing mesh)."
  type        = list(number)
  default     = [80, 443, 8080]
}

variable "tags" {
  description = "Tags appliqués à toutes les ressources."
  type        = map(string)
  default = {
    projet = "tp-docker-swarm"
  }
}
