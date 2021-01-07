variable "name" {
  description = "Name for the traffic manager resources"
  type        = string
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
}

variable "http_target" {
  type        = string
  description = "Resource type to target for endpoints"
}

variable "app_services" {
  description = "app services to be included in traffic management"
  type = map(object({
    id       = string
    location = string
  }))
}

variable "function_apps" {
  description = "function apps to be included in traffic management"
  type = map(object({
    id       = string
    location = string
  }))
}

# variable "app_service_endpoint_resources" {
#   description = "Endpoint resources to be included in traffic management"
#   type = list(object({
#     id       = string
#     location = string
#   }))
# }

# variable "function_app_endpoint_resources" {
#   description = "Endpoint resources to be included in traffic management"
#   type = list(object({
#     id       = string
#     location = string
#   }))
# }

# variable "azure_endpoint_resources" {
#   description = "Endpoint resources to be included in traffic management"
#   type = list(object({
#     id       = string
#     location = string
#   }))
# }
