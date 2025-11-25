output "public_ip_address" {
  description = "Public IP for SFTP"
  value       = azurerm_public_ip.moveit.ip_address
}

output "frontdoor_endpoint_url" {
  description = "Front Door URL for HTTPS"
  value       = "https://${azurerm_cdn_frontdoor_endpoint.moveit.host_name}"
}

output "deployment_summary" {
  description = "Deployment summary"
  value = <<-EOT
  
  ================================================================
  MOVEIT DEPLOYMENT COMPLETE
  ================================================================
  
  SFTP ACCESS:
  - IP: ${azurerm_public_ip.moveit.ip_address}
  - Port: 22
  - Connect: sftp username@${azurerm_public_ip.moveit.ip_address}
  
  HTTPS ACCESS:
  - URL: https://${azurerm_cdn_frontdoor_endpoint.moveit.host_name}
  - WAF: ${var.enable_waf ? "ENABLED (${var.waf_mode} mode)" : "DISABLED"}
  
  SECURITY:
  - NSG: ${azurerm_network_security_group.moveit.name}
  - Load Balancer: ${azurerm_lb.moveit.name}
  - Front Door: ${azurerm_cdn_frontdoor_profile.moveit.name}
  - Defender: Standard tier
  
  BACKEND:
  - MOVEit IP: ${var.moveit_private_ip}
  - VNet: ${var.existing_vnet_name}
  - Subnet: ${var.existing_subnet_name}
  
  COST: ~83 USD/month
  
  ================================================================
  EOT
}
