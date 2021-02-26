variable "name" {
  description = "Name for the traffic manager resources"
  type        = string
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
}

variable "azure_endpoint_resources" {
  description = "Endpoint resources to be included in traffic management"
  type = map(object({
    id       = string
    location = string
  }))
}

variable "static_endpoint_resources" {
  description = "Endpoint resources to be included in front door"
  type = map(object({
    id   = string
    host = string
  }))
}

variable "custom_domain" {
  description = "Custom domain name to use for exposing the service"
  type        = string
  default     = ""
}

variable "tls_certificate" {
  description = "Source to retrieve an tls/ssl certificate for the service"
  type = object({
    source      = string
    secret_id   = optional(string)
    keyvault_id = optional(string)
  })
}
