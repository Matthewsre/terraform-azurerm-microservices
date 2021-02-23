terraform {
  required_version = ">= 0.14"
  backend "azurerm" {}
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "2.47.0"
    }
  }
}

locals {
  environment        = lower(var.environment)
  resource_group_env = local.environment == "prd" ? "Production" : "Pre-Production"
  is_dev             = local.environment == "dev"
  microservices      = jsondecode(file("${path.module}/config/${var.service_name}.json"))
  resource_group_tags = merge({
    "env" = local.resource_group_env
  }, var.resource_group_tags)
}


module "microservice" {
  source = "../../"
  # source  = "Matthewsre/microservices/azurerm"
  # version = "0.1.34"

  service_name = var.service_name
  regions      = var.regions
  environment  = local.environment

  create_appsettings = local.is_dev
  exclude_hosts      = local.is_dev

  resource_group_tags = local.resource_group_tags

  key_vault_developer_user_principal_names = var.key_vault_developer_user_principal_names
  key_vault_include_ip_address             = var.key_vault_include_ip_address

  microservices = local.microservices
}
