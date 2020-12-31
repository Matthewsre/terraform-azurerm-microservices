module "microservice" {
  source = "Matthewsre/microservices/azurerm"

  service_name                = "serv"
  regions                     = ["westus2", "eastus2"]
  environment                 = "dev"
  appservice_deployment_slots = ["staging"]
  microservices = [
    {
      name       = "cosm1"
      appservice = "plan"
      function   = "plan"
      sql        = "elastic"
      roles      = ["Admin", "Support"]
      cosmos_containers = [
        {
          name               = "container1"
          partition_key_path = "/PartitionKey"
          max_throughput     = 0
        },
        {
          name               = "container2"
          partition_key_path = "/PartitionKey"
          max_throughput     = 0
        }
      ]
    },
    {
      name       = "confun"
      appservice = "plan"
      function   = "consumption"
      sql        = "elastic"
    },
    {
      name       = "basic"
      appservice = "plan"
      function   = "plan"
      sql        = "elastic"
    },
    {
      name       = "cosm2"
      appservice = "plan"
      cosmos_containers = [
        {
          name               = "container3"
          partition_key_path = "/PartitionKey"
          max_throughput     = 0
        }
      ]
    },
    {
      name     = "funp"
      function = "plan"
    },
    {
      name     = "func"
      function = "consumption"
    },
    {
      name       = "apponly"
      appservice = "plan"
    }
  ]
}
