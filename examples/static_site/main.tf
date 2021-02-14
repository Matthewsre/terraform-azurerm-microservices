# Description: Create a service with a statically hosted Web UI, Azure Function API layer, and Cosmos DB storage
module "microservice" {
  source = "../../"
  #source = "Matthewsre/microservices/azurerm"
  
  service_name              = "staticsample"
  regions                   = ["westus2", "eastus2"]
  environment               = "dev"

  microservices = [
      {
        name                = "web"
        static_site         = {
            index_document  = "index.html"
            error_document  = "index.html"
            #domain         = "my-domain.io"
        }
      },
      {
        name                = "api"
        function            = "consumption"
        cosmos_containers = [
            {
                name               = "MyData"
                partition_key_path = "/Area"
                max_throughput     = 0
            }
        ]
      }
    ]
}