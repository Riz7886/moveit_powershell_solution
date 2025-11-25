# Data sources - existing resources
data "azurerm_virtual_network" "existing" {
  name                = var.existing_vnet_name
  resource_group_name = var.existing_vnet_rg
}

data "azurerm_subnet" "existing" {
  name                 = var.existing_subnet_name
  virtual_network_name = var.existing_vnet_name
  resource_group_name  = var.existing_vnet_rg
}

# Resource Group for security resources
resource "azurerm_resource_group" "security" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# Network Security Group
resource "azurerm_network_security_group" "moveit" {
  name                = "nsg-${var.project_name}-${var.environment}"
  location            = azurerm_resource_group.security.location
  resource_group_name = azurerm_resource_group.security.name

  security_rule {
    name                       = "Allow-SFTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTPS"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "azurerm_subnet_network_security_group_association" "moveit" {
  subnet_id                 = data.azurerm_subnet.existing.id
  network_security_group_id = azurerm_network_security_group.moveit.id
}

resource "azurerm_public_ip" "moveit" {
  name                = "pip-${var.project_name}-${var.environment}"
  location            = azurerm_resource_group.security.location
  resource_group_name = azurerm_resource_group.security.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "azurerm_lb" "moveit" {
  name                = "lb-${var.project_name}-${var.environment}"
  location            = azurerm_resource_group.security.location
  resource_group_name = azurerm_resource_group.security.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.moveit.id
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "azurerm_lb_backend_address_pool" "moveit" {
  name            = "backend-pool"
  loadbalancer_id = azurerm_lb.moveit.id
}

resource "azurerm_lb_backend_address_pool_address" "moveit" {
  name                    = "moveit-server"
  backend_address_pool_id = azurerm_lb_backend_address_pool.moveit.id
  virtual_network_id      = data.azurerm_virtual_network.existing.id
  ip_address              = var.moveit_private_ip
}

resource "azurerm_lb_probe" "https" {
  name            = "probe-https"
  loadbalancer_id = azurerm_lb.moveit.id
  protocol        = "Tcp"
  port            = 443
}

resource "azurerm_lb_probe" "sftp" {
  name            = "probe-sftp"
  loadbalancer_id = azurerm_lb.moveit.id
  protocol        = "Tcp"
  port            = 22
}

resource "azurerm_lb_rule" "sftp" {
  name                           = "rule-sftp-22"
  loadbalancer_id                = azurerm_lb.moveit.id
  protocol                       = "Tcp"
  frontend_port                  = 22
  backend_port                   = 22
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.moveit.id]
  probe_id                       = azurerm_lb_probe.sftp.id
  enable_floating_ip             = false
  idle_timeout_in_minutes        = 30
}

resource "azurerm_cdn_frontdoor_profile" "moveit" {
  name                = "afd-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.security.name
  sku_name            = "Standard_AzureFrontDoor"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "azurerm_cdn_frontdoor_endpoint" "moveit" {
  name                     = "${var.project_name}-${var.environment}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.moveit.id

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "azurerm_cdn_frontdoor_origin_group" "moveit" {
  name                     = "moveit-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.moveit.id

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
    additional_latency_in_milliseconds = 50
  }

  health_probe {
    protocol            = "Https"
    interval_in_seconds = 100
    path                = "/"
    request_type        = "HEAD"
  }
}

resource "azurerm_cdn_frontdoor_origin" "moveit" {
  name                          = "moveit-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.moveit.id

  enabled                        = true
  host_name                      = var.moveit_private_ip
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = var.moveit_private_ip
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = false
}

resource "azurerm_cdn_frontdoor_route" "moveit" {
  name                          = "moveit-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.moveit.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.moveit.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.moveit.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  link_to_default_domain = true
  https_redirect_enabled = true

  cdn_frontdoor_rule_set_ids = var.enable_waf ? [azurerm_cdn_frontdoor_rule_set.security.id] : []
}

resource "azurerm_cdn_frontdoor_rule_set" "security" {
  name                     = "SecurityRules"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.moveit.id
}

resource "azurerm_cdn_frontdoor_firewall_policy" "moveit" {
  count               = var.enable_waf ? 1 : 0
  name                = "waf${var.project_name}${var.environment}"
  resource_group_name = azurerm_resource_group.security.name
  sku_name            = azurerm_cdn_frontdoor_profile.moveit.sku_name
  enabled             = true
  mode                = var.waf_mode

  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"
  }

  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.0"
    action  = "Block"
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "azurerm_cdn_frontdoor_security_policy" "moveit" {
  count                    = var.enable_waf ? 1 : 0
  name                     = "security-policy"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.moveit.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.moveit[0].id

      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.moveit.id
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}

resource "azurerm_security_center_subscription_pricing" "defender" {
  tier          = "Standard"
  resource_type = "VirtualMachines"
}
