terraform {
  required_version = ">= 0.14"
  experiments      = [module_variable_optional_attrs]
}
locals {
  has_traffic_manager_resources = var.azure_endpoint_resources == null ? false : length(var.azure_endpoint_resources) > 0
  has_frontdoor_resources       = var.static_endpoint_resources == null ? false : length(var.static_endpoint_resources) > 0
  frontdoor_hosts               = local.has_frontdoor_resources ? var.static_endpoint_resources : {}

  has_custom_domain      = var.custom_domain != null && var.custom_domain != ""
  has_tls_certificate    = var.tls_certificate != null ? var.tls_certificate.source != null : false
  tls_certificate_source = local.has_tls_certificate ? lower(var.tls_certificate.source) == "frontdoor" ? "FrontDoor" : lower(var.tls_certificate.source) == "keyvault" ? "AzureKeyVault" : "" : ""

  has_kevault_secret      = local.tls_certificate_source == "AzureKeyVault"
  keyvault_secret_parts   = local.has_kevault_secret ? split("/", var.tls_certificate.secret_id) : []
  keyvault_secret_name    = local.has_kevault_secret ? local.keyvault_secret_parts[4] : ""
  keyvault_secret_version = local.has_kevault_secret ? local.keyvault_secret_parts[5] : ""
  keyvault_hostname       = local.has_kevault_secret ? local.keyvault_secret_parts[2] : ""
  keyvault_id             = local.has_kevault_secret ? var.tls_certificate.keyvault_id : ""
}
resource "azurerm_traffic_manager_profile" "microservice" {
  count = local.has_traffic_manager_resources ? 1 : 0

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
  profile_name        = azurerm_traffic_manager_profile.microservice[0].name
  type                = "azureEndpoints"
  target_resource_id  = each.value.id
}

resource "azurerm_frontdoor" "microservice" {
  count = local.has_frontdoor_resources ? 1 : 0

  name                                         = var.name
  resource_group_name                          = var.resource_group_name
  enforce_backend_pools_certificate_name_check = false

  routing_rule {
    name               = "routing-default"
    accepted_protocols = ["Https"]
    patterns_to_match  = ["/*"]
    frontend_endpoints = ["frontend-default"]
    forwarding_configuration {
      forwarding_protocol = "HttpsOnly"
      backend_pool_name   = "backend-default"
    }
  }

  backend_pool_load_balancing {
    name = "loadbalancing-default"
  }

  backend_pool_health_probe {
    name     = "healthprobe-default"
    protocol = "Https"
  }

  backend_pool {
    name = "backend-default"

    dynamic "backend" {
      for_each = local.frontdoor_hosts
      content {
        host_header = backend.value
        address     = backend.value
        http_port   = 80
        https_port  = 443
      }
    }

    load_balancing_name = "loadbalancing-default"
    health_probe_name   = "healthprobe-default"
  }

  frontend_endpoint {
    name                              = "frontend-default"
    host_name                         = local.has_custom_domain ? var.custom_domain : "${var.name}.azurefd.net"
    custom_https_provisioning_enabled = false
  }
}

resource "azurerm_frontdoor_custom_https_configuration" "microservice_frontdoor" {
  count = local.has_frontdoor_resources && local.tls_certificate_source == "FrontDoor" ? 1 : 0

  frontend_endpoint_id              = azurerm_frontdoor.microservice[0].frontend_endpoint[0].id
  custom_https_provisioning_enabled = true

  custom_https_configuration {
    certificate_source = local.tls_certificate_source
  }
}

resource "azurerm_frontdoor_custom_https_configuration" "microservice_keyvault" {
  count = local.has_frontdoor_resources && local.tls_certificate_source == "AzureKeyVault" ? 1 : 0

  frontend_endpoint_id              = azurerm_frontdoor.microservice[0].frontend_endpoint[0].id
  custom_https_provisioning_enabled = true

  custom_https_configuration {
    certificate_source                         = local.tls_certificate_source
    azure_key_vault_certificate_secret_name    = local.keyvault_secret_name
    azure_key_vault_certificate_secret_version = local.keyvault_secret_version
    azure_key_vault_certificate_vault_id       = local.keyvault_id
  }
}
