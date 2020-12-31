output "name" {
  value = var.name
}

output "database_id" {
  value = local.has_sql_database ? azurerm_mssql_database.microservice[0].id : null
}
