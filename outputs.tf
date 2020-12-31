output "current_azurerm" {
  value = data.azurerm_client_config.current
}

output "current_user" {
  value = data.azuread_user.current_user
}

output "locals" {
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

output "azurerm_app_service_plan_service" {
  value = azurerm_app_service_plan.service
}

output "microservices" {
  value = module.microservice
}
