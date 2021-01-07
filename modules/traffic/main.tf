### Traffic Manager

resource "azurerm_traffic_manager_profile" "microservice" {
  name                   = var.name
  resource_group_name    = var.resource_group_name
  traffic_routing_method = "Performance"

  dns_config {
    relative_name = var.name
    ttl           = 60
  }

  monitor_config {
    protocol                     = "https"
    port                         = 443
    path                         = "/"
    interval_in_seconds          = 30
    timeout_in_seconds           = 10
    tolerated_number_of_failures = 3
  }
}

resource "azurerm_traffic_manager_endpoint" "microservice_appservice" {
  for_each = var.http_target == "appservice" ? var.app_services : {}

  name                = each.value.location
  resource_group_name = var.resource_group_name
  profile_name        = azurerm_traffic_manager_profile.microservice.name
  type                = "azureEndpoints"
  target_resource_id  = each.value.id
}

resource "azurerm_traffic_manager_endpoint" "microservice_function" {
  for_each = var.http_target == "function" ? { for function in var.function_apps : function.id => { id = function.id, location = function.location } } : {}

  name                = each.value.location
  resource_group_name = var.resource_group_name
  profile_name        = azurerm_traffic_manager_profile.microservice.name
  type                = "azureEndpoints"
  target_resource_id  = each.value.id
}

# resource "azurerm_traffic_manager_endpoint" "traffic_app_service" {
#   for_each = { for resource in var.app_service_endpoint_resources : resource.id => resource }

#   name                = each.value.location
#   resource_group_name = var.resource_group_name
#   profile_name        = azurerm_traffic_manager_profile.microservice.name
#   type                = "azureEndpoints"
#   target_resource_id  = each.value.id
# }

# resource "azurerm_traffic_manager_endpoint" "traffic_function_app" {
#   for_each = { for resource in var.function_app_endpoint_resources : resource.id => resource }

#   name                = each.value.location
#   resource_group_name = var.resource_group_name
#   profile_name        = azurerm_traffic_manager_profile.microservice.name
#   type                = "azureEndpoints"
#   target_resource_id  = each.value.id
# }
