terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      # Permet un "terraform destroy" propre même si un élève a ajouté des ressources à la main
      prevent_deletion_if_contains_resources = false
    }
  }

  # Si null, le provider lit la variable d'environnement ARM_SUBSCRIPTION_ID
  subscription_id = var.subscription_id
}
