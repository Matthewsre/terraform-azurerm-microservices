output "current_azurerm" {
  description = "current azure client configuration"
  value       = data.azurerm_client_config.current
}

output "current_user" {
  description = "current user account performing operation"
  value       = data.azuread_user.current_user
}

output "external_ip_address" {
  description = "External IP Address retrieved for simpilfying dev configurations"
  value       = local.external_ip_address
}

output "current_ip_address" {
  description = "IP Address being used for simpilfying dev configurations"
  value       = local.current_ip_address
}

output "locals" {
  description = "local values created base on input data"
  value = {
    is_dev                     = local.is_dev
    primary_region             = local.primary_region
    service_name               = local.service_name
    service_environment_name   = local.service_environment_name
    environment_differentiator = local.environment_differentiator
    has_cosmos                 = local.has_cosmos
    has_appservice_plan        = local.has_appservice_plan
    max_region_length          = local.max_region_length
  }
}

output "microservices" {
  description = "Details from microservice creation."
  value       = module.microservice
}
