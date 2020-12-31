module "microservice" {
  source = "Matthewsre/microservices/azurerm"

  service_name = "myservice"
  regions      = ["westus2"]
  environment  = "dev"
  microservices = [
    {
      name       = "app"
      appservice = "plan"
    }
  ]
}
