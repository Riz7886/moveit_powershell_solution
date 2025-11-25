variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name for security resources"
  type        = string
  default     = "rg-moveit-security"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "moveit"
}

variable "environment" {
  description = "Environment"
  type        = string
  default     = "prod"
}

variable "existing_vnet_name" {
  description = "Existing VNet name"
  type        = string
}

variable "existing_vnet_rg" {
  description = "Existing VNet resource group"
  type        = string
}

variable "existing_subnet_name" {
  description = "Existing subnet name"
  type        = string
}

variable "moveit_private_ip" {
  description = "MOVEit server private IP"
  type        = string
}

variable "enable_waf" {
  description = "Enable WAF"
  type        = bool
  default     = true
}

variable "waf_mode" {
  description = "WAF mode (Detection or Prevention)"
  type        = string
  default     = "Prevention"
}
