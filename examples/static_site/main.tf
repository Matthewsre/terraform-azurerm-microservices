module "microservice" {
  source = "../../"
  #source = "Matthewsre/microservices/azurerm"
  
  service_name              = "staticsample"
  regions                   = ["westus2", "eastus2"]
  environment               = "dev"

  microservices = [
      {
        name                = "web"
        static_site = {
            index_document  = "index.html"
            error_document  = "index.html"
            #domain         = "my-domain.io"
        }
      }
    ]
}