terraform {
  required_version = ">= 0.14"
  experiments      = [module_variable_optional_attrs]
}

data "azurerm_subscription" "current" {}

resource "azurerm_cosmosdb_sql_container" "ui_containers" {
  for_each = { for container in var.cosmos_containers : container.name => container }

  name                = each.value.name
  partition_key_path  = each.value.partition_key_path
  resource_group_name = var.resource_group_name
  account_name        = var.cosmosdb_account_name
  database_name       = var.cosmosdb_sql_database_name

  dynamic "autoscale_settings" {
    for_each = each.value.max_throughput != null && each.value.max_throughput != 0 ? [each.value.max_throughput] : []
    content {
      max_throughput = autoscale_settings
    }
  }
}

output "microservices_module" {
  value = var.name
}
