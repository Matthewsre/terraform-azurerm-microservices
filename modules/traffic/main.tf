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


resource "azurerm_traffic_manager_endpoint" "microservice" {
  for_each = var.azure_endpoint_resources

  name                = each.value.location
  resource_group_name = var.resource_group_name
  profile_name        = azurerm_traffic_manager_profile.microservice.name
  type                = "azureEndpoints"
  target_resource_id  = each.value.id
}
