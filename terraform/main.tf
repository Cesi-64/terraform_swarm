# ---------------------------------------------------------------------------
# Calculs locaux
# ---------------------------------------------------------------------------

locals {
  manager_size = coalesce(var.manager_vm_size, var.vm_size)

  # manager-1..N puis worker-1..N
  nodes = merge(
    { for i in range(var.manager_count) : "manager-${i + 1}" => { role = "manager", size = local.manager_size } },
    { for i in range(var.worker_count) : "worker-${i + 1}" => { role = "worker", size = var.vm_size } },
  )

  # vCPU des tailles courantes (x86_64). Une taille absente compte pour 0 : le garde-fou ne bloque pas.
  known_vcpus = {
    Standard_B1ls     = 1
    Standard_B1s      = 1
    Standard_B1ms     = 1
    Standard_B2s      = 2
    Standard_B2ms     = 2
    Standard_B2ats_v2 = 2
    Standard_B2als_v2 = 2
    Standard_B2ts_v2  = 2
    Standard_B2ls_v2  = 2
    Standard_B2s_v2   = 2
    Standard_D2s_v5   = 2
    Standard_D2as_v5  = 2
  }
  total_vcpus = sum([for n in values(local.nodes) : lookup(local.known_vcpus, n.size, 0)])

  # Clé SSH : fournie ou générée
  generate_key   = var.ssh_public_key_path == ""
  ssh_public_key = local.generate_key ? tls_private_key.ssh[0].public_key_openssh : file(pathexpand(var.ssh_public_key_path))
  ssh_private_key_file = (
    local.generate_key
    ? abspath(local_sensitive_file.ssh_private_key[0].filename)
    : pathexpand(trimsuffix(var.ssh_public_key_path, ".pub"))
  )

  admin_cidr = var.admin_cidr != "" ? var.admin_cidr : "${chomp(data.http.my_ip[0].response_body)}/32"
}

# IP publique de la machine qui lance Terraform (pour restreindre SSH / Portainer)
data "http" "my_ip" {
  count = var.admin_cidr == "" ? 1 : 0
  url   = "https://api.ipify.org"
}

# ---------------------------------------------------------------------------
# Clé SSH (générée si aucune n'est fournie)
# ---------------------------------------------------------------------------

resource "tls_private_key" "ssh" {
  count     = local.generate_key ? 1 : 0
  algorithm = "RSA" # RSA : accepté partout côté Azure / azurerm
  rsa_bits  = 4096
}

resource "local_sensitive_file" "ssh_private_key" {
  count           = local.generate_key ? 1 : 0
  content         = tls_private_key.ssh[0].private_key_openssh
  filename        = "${path.module}/.ssh/swarm_key"
  file_permission = "0600"
}

# ---------------------------------------------------------------------------
# Groupe de ressources + réseau
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = var.tags

  lifecycle {
    precondition {
      condition     = local.total_vcpus <= var.vcpu_quota
      error_message = "Les VM demandées totalisent ${local.total_vcpus} vCPU, au-delà du quota de ${var.vcpu_quota}. Réduire vm_size / manager_vm_size / worker_count."
    }
  }
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_subnet" "swarm" {
  name                 = "swarm"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}

# Le trafic interne Swarm (2377/tcp, 7946/tcp+udp, 4789/udp) circule dans le VNet :
# il est déjà autorisé par la règle par défaut AllowVnetInBound du NSG.
resource "azurerm_network_security_group" "swarm" {
  name                = "${var.prefix}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  security_rule {
    name                       = "ssh-admin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.admin_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "portainer-admin"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9443"
    source_address_prefix      = local.admin_cidr
    destination_address_prefix = "*"
  }

  dynamic "security_rule" {
    for_each = length(var.public_app_ports) > 0 ? [1] : []
    content {
      name                       = "apps-public"
      priority                   = 200
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = [for p in var.public_app_ports : tostring(p)]
      source_address_prefix      = "Internet"
      destination_address_prefix = "*"
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "swarm" {
  subnet_id                 = azurerm_subnet.swarm.id
  network_security_group_id = azurerm_network_security_group.swarm.id
}

# ---------------------------------------------------------------------------
# Une IP publique + une carte réseau + une VM par nœud
# ---------------------------------------------------------------------------

resource "azurerm_public_ip" "node" {
  for_each            = local.nodes
  name                = "${var.prefix}-${each.key}-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "node" {
  for_each            = local.nodes
  name                = "${var.prefix}-${each.key}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.swarm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.node[each.key].id
  }
}

resource "azurerm_linux_virtual_machine" "node" {
  for_each              = local.nodes
  name                  = "${var.prefix}-${each.key}"
  computer_name         = each.key # = nom du nœud dans "docker node ls"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = each.value.size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.node[each.key].id]

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  tags = merge(var.tags, { role = each.value.role })
}

# ---------------------------------------------------------------------------
# Inventaire Ansible généré automatiquement
# ---------------------------------------------------------------------------

resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory.ini"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/inventory.tftpl", {
    managers = {
      for k, n in local.nodes : k => {
        public_ip  = azurerm_public_ip.node[k].ip_address
        private_ip = azurerm_network_interface.node[k].private_ip_address
      } if n.role == "manager"
    }
    workers = {
      for k, n in local.nodes : k => {
        public_ip  = azurerm_public_ip.node[k].ip_address
        private_ip = azurerm_network_interface.node[k].private_ip_address
      } if n.role == "worker"
    }
    admin_username = var.admin_username
    ssh_key_file   = local.ssh_private_key_file
  })

  depends_on = [azurerm_linux_virtual_machine.node]
}
