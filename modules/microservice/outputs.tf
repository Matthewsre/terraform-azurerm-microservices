output "name" {
  description = "Name of the Microservice"
  value       = var.name
}

output "database_id" {
  description = "SQL primary database id that was created"
  value       = local.has_sql_database ? azurerm_mssql_database.microservice_primary[0].id : null
}

output "app_services" {
  description = "Data that can be used to setup traffic routing"
  value       = azurerm_app_service.microservice
}

output "function_apps" {
  description = "Data that can be used to setup traffic routing"
  value       = azurerm_function_app.microservice
  sensitive   = true
}

output "traffic_data" {
  description = "Data that can be used to setup traffic routing"
  value = {
    microservice_environment_name = local.microservice_environment_name
    http_target                   = local.http_target
    # app_services                    = azurerm_app_service.microservice
    # function_apps                   = azurerm_function_app.microservice
    # app_service_endpoint_resources  = local.app_service_endpoint_resources
    # function_app_endpoint_resources = local.function_app_endpoint_resources
    # azure_endpoint_resources        = local.azure_endpoint_resources
  }
}

output "application_data" {
  description = "AAD Application Data to use for role assignments"
  value = {
    application       = azuread_application.microservice
    application_roles = azuread_application_app_role.microservice
    service_consumers = local.consumers
  }
}
