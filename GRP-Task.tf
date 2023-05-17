# TERRAFORM AND PROVIDER DETAILS
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.51.0"
    }
  }
}
provider "azurerm" {

  client_id       = "5e636370-3b89-4d4a-8742-0cc9346f9308"
  tenant_id       = "be4fe9dc-a5f8-4649-b927-a49592994082"
  subscription_id = "d786964d-240f-4088-9247-4ba08f0c47d0"
  client_secret   = "qJH8Q~Klh5-PcjIslNfFcSi9hsUX2YBjFTlYGbtz"

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

variable "vm_admin_username" {}
variable "vm_admin_password" {}

# RESOURCE GROUP
resource "azurerm_resource_group" "test" {
  name     = "RG"
  location = "Australia Central"

  tags = {
    environment = "group-demo"
  }
}

# VIRTUAL NETWORK
resource "azurerm_virtual_network" "VNet" {
  name                = "VNet"
  address_space       = ["192.168.0.0/20"]
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
}

# SUBNETS
variable "subnet-names" {
  type    = list(string)
  default = ["Subnet-Web", "Subnet-App", "Subnet-DB"]
}

resource "azurerm_subnet" "Subnets" {
  count                = length(var.subnet-names)
  name                 = var.subnet-names[count.index]
  resource_group_name  = azurerm_resource_group.test.name
  virtual_network_name = azurerm_virtual_network.VNet.name
  address_prefixes     = count.index == 0 ? ["192.168.0.0/26"] : count.index == 1 ? ["192.168.0.64/28"] : ["192.168.0.128/25"]
}

#NETWORK INTERFACE 
resource "azurerm_network_interface" "nic" {
  count               = length(var.subnet-names)
  name                = count.index == 0 ? "NIC-Web" : count.index == 1 ? "NIC-App" : "NIC-DB"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name

  ip_configuration {
    name                          = "testconfiguration1"
    subnet_id                     = azurerm_subnet.Subnets[count.index].id
    private_ip_address_allocation = "Dynamic"
  }
}

# CENT OS - VIRTUAL MACHINEs
resource "azurerm_virtual_machine" "AZURE-VM" {
  count                 = length(var.subnet-names)
  name                  = count.index == 0 ? "VM-Web" : count.index == 1 ? "VM-App" : "VM-DB"
  location              = azurerm_resource_group.test.location
  resource_group_name   = azurerm_resource_group.test.name
  network_interface_ids = [azurerm_network_interface.nic[count.index].id]
  vm_size               = "Standard_B1ls"

  storage_image_reference {
    publisher = "OpenLogic"
    offer     = "CentOS"
    sku       = "7.5"
    version   = "latest"
  }
  storage_os_disk {
    name              = "myosdisk-${count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }
  os_profile {
    computer_name  = "hostname-${count.index}"
    admin_username = var.vm_admin_username
    admin_password = var.vm_admin_password
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }

}

# DNS RECORD
resource "azurerm_dns_zone" "dns_host_name" {
  name                = "dns_host.name"
  resource_group_name = azurerm_resource_group.test.name
}


resource "azurerm_dns_a_record" "dns_record" {
  count               = 3
  name    = count.index==0? "AZ_EUS_L_HCS_VMweb" : count.index==1? "AZ_EUS_L_HCS_VMapp" : "AZ_EUS_L_HCS_VMdb"
  zone_name           = azurerm_dns_zone.dns_host_name.name
  resource_group_name = azurerm_resource_group.test.name
  ttl                 = 3600
  records = count.index==0? ["192.168.0.5"] : count.index==1? ["192.168.0.68"] : ["192.168.0.132"]
}

# NETWORK SECURITY GROUP
resource "azurerm_network_security_group" "NSG" {
  count               = length(var.subnet-names)
  name                = "NSG"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name

  security_rule {
    name                                       = "inbound-for-ASG"
    priority                                   = 104
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "22"
    source_address_prefix                      = azurerm_network_interface.nic-window.private_ip_address
    destination_application_security_group_ids = [azurerm_application_security_group.ASG.id]
  }

  security_rule {
    name                   = "Outbound-for-ASG"
    priority               = 100
    direction              = "Outbound"
    access                 = "Allow"
    protocol               = "Tcp"
    source_port_range      = "*"
    destination_port_range = "22"
    source_application_security_group_ids = [azurerm_application_security_group.ASG.id]
    destination_address_prefix            = azurerm_network_interface.nic[count.index].private_ip_address
  }

  security_rule {
    name                                       = "Allow-inbound-for-ASG"
    priority                                   = 105
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "3389"
    source_address_prefix                      = azurerm_network_interface.nic-window.private_ip_address
    destination_application_security_group_ids = [azurerm_application_security_group.ASG.id]
  }

  security_rule {
    name                                  = "Allow-Outbound-for-ASG"
    priority                              = 101
    direction                             = "Outbound"
    access                                = "Allow"
    protocol                              = "Tcp"
    source_port_range                     = "*"
    destination_port_range                = "3389"
    source_application_security_group_ids = [azurerm_application_security_group.ASG.id]
    destination_address_prefix            = azurerm_network_interface.nic[count.index].private_ip_address
  }

  security_rule {
    name                                       = "Allow-inbound-for-HTTP"
    priority                                   = 106
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "80"
    source_address_prefix                      = azurerm_network_interface.nic-window.private_ip_address
    destination_application_security_group_ids = [azurerm_application_security_group.ASG.id]
  }

  security_rule {
    name                                  = "Allow-Outbound-for-HTTP"
    priority                              = 102
    direction                             = "Outbound"
    access                                = "Allow"
    protocol                              = "Tcp"
    source_port_range                     = "*"
    destination_port_range                = "80"
    source_application_security_group_ids = [azurerm_application_security_group.ASG.id]
    destination_address_prefix            = azurerm_network_interface.nic[count.index].private_ip_address
  }

  security_rule {
    name                                       = "Allow-inbound-for-HTTPS"
    priority                                   = 107
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "443"
    source_address_prefix                      = azurerm_network_interface.nic-window.private_ip_address
    destination_application_security_group_ids = [azurerm_application_security_group.ASG.id]
  }

  security_rule {
    name                                  = "Allow-Outbound-for-HTTPS"
    priority                              = 103
    direction                             = "Outbound"
    access                                = "Allow"
    protocol                              = "Tcp"
    source_port_range                     = "*"
    destination_port_range                = "443"
    source_application_security_group_ids = [azurerm_application_security_group.ASG.id]
    destination_address_prefix            = azurerm_network_interface.nic[count.index].private_ip_address
  }
}

resource "azurerm_subnet_network_security_group_association" "Associate-SG" {
  count                     = length(var.subnet-names)
  subnet_id                 = azurerm_subnet.Subnets[count.index].id
  network_security_group_id = azurerm_network_security_group.NSG[count.index].id

  depends_on = [azurerm_subnet.Subnets]
}

#APPLICATION SECURITY GROUP
resource "azurerm_application_security_group" "ASG" {
  name                = "ASG"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
}

resource "azurerm_network_interface_application_security_group_association" "application_security_group_association" {
  count                         = (length(var.subnet-names))
  network_interface_id          = azurerm_network_interface.nic[count.index].id
  application_security_group_id = azurerm_application_security_group.ASG.id
}

# WINDOWS-VM-----------------------------------------------------------------------------------------------------

# PUBLIC IP ADDRESS
resource "azurerm_public_ip" "public-ip" {
  name                = "public-ip"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  allocation_method   = "Dynamic"
}

#NETWORK INTERFACE
resource "azurerm_network_interface" "nic-window" {
  name                = "nic-window"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name

  ip_configuration {
    name                          = "testconfiguration1"
    subnet_id                     = azurerm_subnet.Subnets[0].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public-ip.id
  }
}

# WINDOWS - VM
resource "azurerm_windows_virtual_machine" "Windows-VM" {
  name                = "Windows-VM"
  resource_group_name = azurerm_resource_group.test.name
  location            = azurerm_resource_group.test.location
  size                = "Standard_B1ls"
  admin_username      = var.vm_admin_username
  admin_password      = var.vm_admin_password

  network_interface_ids = [
    azurerm_network_interface.nic-window.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
}

resource "azurerm_public_ip" "PublicIP" {
  name                = "example-PIP"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway" "NatGateway" {
  name                = "NatGateway"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  sku_name            = "Standard"
}


resource "azurerm_nat_gateway_public_ip_association" "NatGateway-publicIP-association" {
  nat_gateway_id       = azurerm_nat_gateway.NatGateway.id
  public_ip_address_id = azurerm_public_ip.PublicIP.id
}

# STANDARD LOAD BALANCER (INTERNAL LOAD BALANCER)--------------------------------------------------------------------
resource "azurerm_lb" "standardLB" {
  name                = "standardLB"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name = "LB-IP"
    /* subnet_id                     = azurerm_subnet.Subnets[0].id */
    private_ip_address_allocation = "Dynamic"
  }
}

# STANDARD LB - BACKEND POOL 

resource "azurerm_lb_backend_address_pool" "BackEndAddressPool" {
  loadbalancer_id = azurerm_lb.standardLB.id
  name            = "BackEndAddressPool"
}

resource "azurerm_network_interface_backend_address_pool_association" "BackEndAddressPool-association" {
  network_interface_id    = azurerm_network_interface.nic[0].id
  ip_configuration_name   = "testconfiguration1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.BackEndAddressPool.id
}


resource "azurerm_lb_nat_rule" "http" {
  name                           = "http-rule"
  resource_group_name            = azurerm_resource_group.test.name
  loadbalancer_id                = azurerm_lb.standardLB.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = azurerm_lb.standardLB.frontend_ip_configuration[0].name
}

resource "azurerm_lb_nat_rule" "https" {
  name                           = "https-rule"
  resource_group_name            = azurerm_resource_group.test.name
  loadbalancer_id                = azurerm_lb.standardLB.id
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 443
  frontend_ip_configuration_name = azurerm_lb.standardLB.frontend_ip_configuration[0].name
}

#PUBLIC LOAD BALANCER ------------------------------------------------------------------------------------------------------

resource "azurerm_public_ip" "PublicIP-LB" {
  name                = "PIP-LB"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

/* resource "azurerm_lb" "standardLB" {
  name                = "standardLB"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.PublicIP-LB.id
  }
} */

/* resource "azurerm_lb_outbound_rule" "example" {
  name            = "OutboundRule"
  loadbalancer_id = azurerm_lb.standardLB.id
  protocol        = "Tcp"

  backend_address_pool_id = azurerm_lb_backend_address_pool.BackEndAddressPool.id

  frontend_ip_configuration {
    name = "LB-IP"
  }
} */





/* resource "azurerm_lb_rule" "inbound" {
  name = "inbound-rule"
  loadbalancer_id                = azurerm_lb.standardLB.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = azurerm_lb.standardLB.frontend_ip_configuration[0].name
  backend_address_pool_id = azurerm_lb.example.backend_address_pool[0].id
}

resource "azurerm_lb_rule" "outbound" {
  name = "outbound-rule"
  loadbalancer_id                = azurerm_lb.standardLB.id
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 443
  frontend_ip_configuration_name = azurerm_lb.standardLB.frontend_ip_configuration[0].name
  backend_address_pool_id = azurerm_lb..backend_address_pool[0].id
} */

#CREATING BASTION HOST

resource "azurerm_virtual_network" "VNet1" {
  name                = "VNet1"
  address_space       = ["192.168.0.0/26"]
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
}

resource "azurerm_subnet" "Subnet" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.test.name
  virtual_network_name = azurerm_virtual_network.VNet1.name
  address_prefixes     = ["192.168.0.0/26"]
}


resource "azurerm_bastion_host" "bastionhost" {
  name                = "bastionhost"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.Subnet.id
    public_ip_address_id = azurerm_public_ip.PublicIP-LB.id
  }
}