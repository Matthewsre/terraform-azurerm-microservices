output "name" {
  description = "Name of the Microservice"
  value       = var.name
}

output "database_id" {
  description = "SQL primary database id that was created"
  value       = local.has_sql_database ? azurerm_mssql_database.microservice_primary[0].id : null
}

output "traffic_data" {
  description = "Data that can be used to setup traffic routing"
  value = {
    microservice_environment_name = local.trafficmanager_name
    azure_endpoint_resources      = local.azure_endpoint_resources
    static_endpoint_resources     = local.static_endpoint_resources
    custom_domain                 = var.custom_domain
    tls_certificate               = local.tls_certificate
  }
}

output "application_data" {
  description = "AAD Application Data to use for role assignments"
  value = {
    application       = azuread_application.microservice
    application_roles = random_uuid.app_role_id
    service_consumers = local.consumers
  }
}

output "appsettings" {
  description = "AppSettings object to use for optionally creating json files"
  value       = local.appsettings
}
