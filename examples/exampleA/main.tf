module "microservice" {
  source = "../../"

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
