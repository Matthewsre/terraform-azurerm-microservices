output "name" {
  description = "Name of the Microservice"
  value       = var.name
}

output "database_id" {
  description = "SQL database id that was created"
  value       = local.has_sql_database ? azurerm_mssql_database.microservice[0].id : null
}

output "application_data" {
  description = "AAD Application Data to use for role assignments"
  value = {
    application       = azuread_application.microservice
    application_roles = azuread_application_app_role.microservice
    service_consumers = local.consumers
  }
}
