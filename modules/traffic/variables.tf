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
