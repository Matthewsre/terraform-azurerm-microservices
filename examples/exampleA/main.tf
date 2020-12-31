module "microservice" {
  source = "../../"

  service_name = "myservice"
  regions      = ["westus2"]
  environment  = "dev"
  #environment_differentiator = "matt"
  microservices = [
    {
      name       = "app"
      appservice = "plan"
    }
  ]
}
