terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.0"
    }
  }
}

# Configure the Azure provider
provider "azurerm" {
  features {}
  client_id       = var.client_id
  client_secret   = var.client_secret
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

##### NETWORK ######

# Create a resource group for the virtual network and subnet
resource "azurerm_resource_group" "rg" {
  name     = "${var.app_name}-rg"
  location = "West Europe"
}

# Create a network security group
resource "azurerm_network_security_group" "nsg" {
  name                = "${var.app_name}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create a network security group rule to allow SSH traffic
resource "azurerm_network_security_rule" "stresstest_ssh_rule" {
  name                        = "stresstest-ssh-rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

# Create a virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.app_name}-network"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.0.0.0/16"]
}

# Create a subnet
resource "azurerm_subnet" "subnet" {
  name                 = "${var.app_name}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

##### INSTANCE ######

# Instance's network interface
resource "azurerm_network_interface" "nic" {
  name                = "${var.app_name}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "${var.app_name}-configuration"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

# Instance's public ip
resource "azurerm_public_ip" "pip" {

  name                = "${var.app_name}-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

# Instance's Virtual Machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "${var.app_name}-vm"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = "Standard_F2"
  admin_username        = "adminuser"
  network_interface_ids = [azurerm_network_interface.nic.id]
  computer_name         = "${var.app_name}-vm"

  os_disk {
    name                 = "${var.app_name}-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  disable_password_authentication = true

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }
}

resource "time_sleep" "wait" {
  depends_on = [azurerm_linux_virtual_machine.vm]

  create_duration = "1m"
}

resource "azurerm_network_interface_security_group_association" "stresstest_leader_nsg_association" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Give the network services enough time to initialize
resource "null_resource" "delay" {
  provisioner "local-exec" {
    command = "sleep 20"
  }
}

# output "vm_public_ip" {
#   description = "The public IP address of the virtual machine"
#   value       = azurerm_linux_virtual_machine.vm.public_ip_address
# }

# resource "null_resource" "vm_public_ip_debug" {
#   depends_on = [azurerm_linux_virtual_machine.vm]

#   provisioner "local-exec" {
#     command = "echo The VM public IP is: ${azurerm_linux_virtual_machine.vm.public_ip_address}"
#   }
# }

resource "null_resource" "docker_install" {
  depends_on = [azurerm_linux_virtual_machine.vm]

  connection {
    host        = azurerm_linux_virtual_machine.vm.public_ip_address
    user        = "adminuser"
    type        = "ssh"
    private_key = file("~/.ssh/id_rsa")
    agent       = false
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'SSH connection test succeeded'",
      "export DEBIAN_FRONTEND=noninteractive",

      # pull packages
      "apt update && apt -y upgrade",

      # swap file
      "sudo fallocate -l 1G /swapfile",
      "sudo chmod 600 /swapfile",
      "sudo mkswap /swapfile",
      "sudo swapon /swapfile",
      "echo '/swapfile none swap 0 0' | sudo tee -a /etc/fstab",

      # Digital ocean monitoring
      "curl -sSL https://agent.digitalocean.com/install.sh | sh",

      "sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -",
      "sudo add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\"",
      "sudo apt-get update",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io",
      "sudo usermod -aG docker adminuser",
      # "grep docker /etc/group",
      #"sudo chmod 777 /var/run/docker.sock",
      "sudo systemctl enable docker --now docker",

      // install docker-compose
      "curl -L \"https://github.com/docker/compose/releases/download/1.28.5/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose",
      "chmod +x /usr/local/bin/docker-compose",

      # security
      "ufw allow 22",
      "ufw allow 80",
      "ufw --force enable"
    ]
  }
}
