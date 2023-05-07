terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.51.0"
    }
  }
  # backend "azurerm" {
  #   resource_group_name  = "test-rg"
  #   storage_account_name = var.backend_storage_name
  #   container_name       = "tfstate"
  #   key                  = "terraform.tfstate"
  # }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "test-rg" {
  name     = "test-rg"
  location = "westeurope"
}

resource "azurerm_storage_account" "tfstorage" {
  name                     = "neyotfstorage"
  location                 = azurerm_resource_group.test-rg.location
  resource_group_name      = azurerm_resource_group.test-rg.name
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    enviroment = "testing"
  }

}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  container_access_type = "private"
  storage_account_name  = azurerm_storage_account.tfstorage.name
}

resource "azurerm_storage_container" "scripts" {
  name                  = "scripts"
  container_access_type = "blob"
  storage_account_name  = azurerm_storage_account.tfstorage.name
}

resource "azurerm_storage_blob" "startup-script" {
  name                   = "nginx.sh"
  storage_account_name   = azurerm_storage_account.tfstorage.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source                 = "./nginx.sh"
}
# user infrastructure

resource "azurerm_network_security_group" "allowTCP" {
  name                = "allowTCP"
  resource_group_name = azurerm_resource_group.test-rg.name
  location            = azurerm_resource_group.test-rg.location
  security_rule {
    name                       = "allowInboundHTTP"
    priority                   = 100
    access                     = "Allow"
    direction                  = "Inbound"
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "8080", "443", "22"]
  }
}

resource "azurerm_virtual_network" "tfnetwork" {
  name                = "tfnetwork"
  resource_group_name = azurerm_resource_group.test-rg.name
  location            = azurerm_resource_group.test-rg.location
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet1" {
  name                 = "subnet1"
  resource_group_name  = azurerm_resource_group.test-rg.name
  virtual_network_name = azurerm_virtual_network.tfnetwork.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "frontendsubnet" {
  name                 = "frontendsubnet"
  resource_group_name  = azurerm_resource_group.test-rg.name
  virtual_network_name = azurerm_virtual_network.tfnetwork.name
  address_prefixes     = ["10.0.2.0/27"]
}

resource "azurerm_network_interface" "nic1" {
  depends_on = [
    azurerm_public_ip.server1-ip
  ]
  name                = "nic1"
  location            = azurerm_resource_group.test-rg.location
  resource_group_name = azurerm_resource_group.test-rg.name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.server1-ip.id
  }
}

resource "azurerm_network_interface" "nic2" {
  name                = "nic2"
  location            = azurerm_resource_group.test-rg.location
  resource_group_name = azurerm_resource_group.test-rg.name
  ip_configuration {
    name                          = "internal"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.subnet1.id
  }
}

resource "azurerm_subnet_network_security_group_association" "allowTCPsubnet1" {
  subnet_id                 = azurerm_subnet.subnet1.id
  network_security_group_id = azurerm_network_security_group.allowTCP.id
}

resource "azurerm_public_ip" "server1-ip" {
  name                = "server1-ip"
  location            = azurerm_resource_group.test-rg.location
  resource_group_name = azurerm_resource_group.test-rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "gateway-ip" {
  name                = "gateway-ip"
  location            = azurerm_resource_group.test-rg.location
  resource_group_name = azurerm_resource_group.test-rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_virtual_machine" "myvm1" {
  name                          = "myvm1"
  resource_group_name           = azurerm_resource_group.test-rg.name
  location                      = azurerm_resource_group.test-rg.location
  network_interface_ids         = [azurerm_network_interface.nic1.id]
  vm_size                       = var.instance_type
  delete_os_disk_on_termination = true
  os_profile {
    computer_name  = "server1"
    admin_username = "name"
    admin_password = "password"
    custom_data    = <<-EOF
      #!/bin/bash
      sudo apt update
      sudo apt -y install nginx 
      echo "<h1>The custom script was fully successful</h1> >> /var/www/html/index.nginx-debian.html
    EOF
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
  storage_os_disk {
    name              = "tfdisk1"
    caching           = "ReadWrite"
    managed_disk_type = "Standard_LRS"
    create_option     = "FromImage"
  }
  storage_image_reference {
    publisher = "Canonical"
    offer     = var.os_image_offer
    sku       = var.os_image_sku
    version   = "latest"
  }
}

resource "azurerm_virtual_machine" "myvm2" {
  name                          = "myvm2"
  resource_group_name           = azurerm_resource_group.test-rg.name
  location                      = azurerm_resource_group.test-rg.location
  vm_size                       = var.instance_type
  network_interface_ids         = [azurerm_network_interface.nic2.id]
  delete_os_disk_on_termination = true
  os_profile {
    computer_name  = "server2"
    admin_username = "name"
    admin_password = "password"
    custom_data    = <<-EOF
      #!/bin/bash
      sudo apt update
      sudo apt -y install nginx 
      echo "<h1>The custom script was fully successful</h1> >> /var/www/html/index.nginx-debian.html
    EOF
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
  storage_os_disk {
    name              = "tfdisk2"
    caching           = "ReadWrite"
    managed_disk_type = "Standard_LRS"
    create_option     = "FromImage"
  }
  storage_image_reference {
    publisher = "Canonical"
    offer     = var.os_image_offer
    sku       = var.os_image_sku
    version   = "latest"
  }
}



resource "azurerm_application_gateway" "tf-appgateway" {
  depends_on = [
    azurerm_public_ip.gateway-ip
  ]
  name                = "tf-appgateway"
  resource_group_name = azurerm_resource_group.test-rg.name
  location            = azurerm_resource_group.test-rg.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }
  gateway_ip_configuration {
    name      = "tf-gateway-ip-config"
    subnet_id = azurerm_subnet.frontendsubnet.id
  }
  frontend_port {
    name = "gateway-port"
    port = 80
  }
  frontend_ip_configuration {
    name                 = "tfgateway-frontend-ip"
    public_ip_address_id = azurerm_public_ip.gateway-ip.id
  }
  backend_address_pool {
    name         = "tfgateway-backened-pool"
    ip_addresses = [azurerm_network_interface.nic1.private_ip_address, azurerm_network_interface.nic2.private_ip_address]
  }
  backend_http_settings {
    name                  = "tf-gateway-backend-http-settings"
    port                  = 80
    protocol              = "Http"
    cookie_based_affinity = "Disabled"
    request_timeout       = 60
  }

  http_listener {
    name                           = "tf-gateway-httplistener"
    frontend_ip_configuration_name = "tfgateway-frontend-ip"
    frontend_port_name             = "gateway-port"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "tf-gateway-RRR"
    rule_type                  = "Basic"
    backend_address_pool_name  = "tfgateway-backened-pool"
    backend_http_settings_name = "tf-gateway-backend-http-settings"
    http_listener_name         = "tf-gateway-httplistener"
    priority                   = 100
  }
}

# resource "azurerm_dns_zone" "myresumes" {
#   name                = "myresume.live"
#   resource_group_name = azurerm_resource_group.test-rg.name
# }

# resource "azurerm_dns_a_record" "www" {
#   name                = "app"
#   zone_name           = azurerm_dns_zone.myresumes.name
#   resource_group_name = azurerm_resource_group.test-rg.name
#   ttl                 = 300
#   records             = [azurerm_public_ip.gateway-ip.ip_address]
# }

