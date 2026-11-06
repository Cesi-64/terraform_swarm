output "nodes" {
  description = "IP publiques / privées de chaque nœud"
  value = {
    for k, n in local.nodes : k => {
      role       = n.role
      size       = n.size
      public_ip  = azurerm_public_ip.node[k].ip_address
      private_ip = azurerm_network_interface.node[k].private_ip_address
    }
  }
}

output "total_vcpus" {
  description = "vCPU consommés sur le quota régional"
  value       = local.total_vcpus
}

output "ssh_manager" {
  description = "Commande SSH vers le premier manager"
  value       = "ssh -i ${local.ssh_private_key_file} ${var.admin_username}@${azurerm_public_ip.node["manager-1"].ip_address}"
}

output "portainer_url" {
  description = "URL de Portainer (après le playbook Ansible)"
  value       = "https://${azurerm_public_ip.node["manager-1"].ip_address}:9443"
}

output "admin_cidr" {
  description = "Plage autorisée pour SSH / Portainer"
  value       = local.admin_cidr
}
