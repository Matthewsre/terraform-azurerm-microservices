# Terraform module for standardizing microservice infrastructure provisioning

This module is to help standardize microservice provisioning

Documentation will be added soon

## Features

Provisioning multi-region microservices on Azure with minimal input to describe your service

Hosting Configurations:
* App Service
* Functions

Data Store Configurations:
* SQL Elastic Pool
* CosmosDB

Additional Configurations:
* Application Insights
* Storage
* Key Vault
* Deployment Slots
* Managed Identity
* Traffic Manager
* SQL Failover Group

## Structure

![architecture](documentation/microservice-architecture.PNG)

## Usage

For large services there are sometimes conflict issues between app service slots, function app slots, and traffic manager. To avoid these issues until this can be resolved you can run apply with the `-parallelism=1` argument

```
terraform apply -parallelism=1 "dev.tfplan"
```

```hcl
module "microservice" {
  source = "Matthewsre/microservices/azurerm"

  service_name = "myservice"
  regions      = ["westus2", "eastus"]
  environment  = "dev"

  microservices = [
    {
      name       = "service1"
      appservice = "plan"
    },
    {
      name       = "service2"
      appservice = "plan"
      function   = "plan"
      cosmos_containers = [
        {
          name               = "container1"
          partition_key_path = "/PartitionKey"
          max_throughput     = 0
        }
      ]
    },
    {
      name       = "service3"
      appservice = "plan"
      function   = "consumption"
      sql        = "elastic"
    },
    {
      name       = "service4"
      appservice = "plan"
      sql        = "elastic"
    },
    {
      name       = "service5"
      appservice = "plan"
      cosmos_containers = [
        {
          name               = "container2"
          partition_key_path = "/PartitionKey"
          max_throughput     = 0
        }
      ]
    }
  ]
}

```

# Resource Naming Conventions

Names for resources will be derived from the variables provided:
* service_name
* environment
* regions
* microservice.name
* environment_differentiator (optional)

## Global Names

Standard names for global resources will be

```
# example "myservice-prd"
"${service_name}-${environment}"
```
Differentiators are available for scenarios such as
1. Multiple test/ppe environments needed for validating different features
2. Multiple dev environments needed for different developers
3. Multiple instances in production (beta, migrations, etc.)

If an environment_differentiator is provided it will be:

```
# example "myservice-env2-ppe"
"${service_name}-${environment_differentiator}-${environment}"
```

Environment differentiators will automatically be provided by default for the dev environment based on the logged in user. If an environment_differentiator is provided that will be used instead of the logged in user.

```
# example "myservice-matthewsre-dev"
"${service_name}-${environment_differentiator}-${environment}"
```

## Region Resource Names

Names for regional resources will include the region when naming requirement must be unique. The environment_differentiator will be included based on same criteria from global rules.

```
# example "myservice-westus2-tst"
"${service_name}-${region}-${environment}"

# example "myservice-westus2-matthewsre-tst"
"${service_name}-${region}-${environment_differentiator}-${environment}"

```

## Microservice Resource Names

Microservices will use thier provided microservice.name instead of the service_name. For this reason a **microservice.name should not be the same as the service_name**. Terraform does not currently support validation on multiple attributes. The names will also include the region when naming requirement must be unique.

```
# example "finance-prd"
"${microservice.name}-${environment}"

# example "finance-matthewsre-dev"
"${microservice.name}-${environment_differentiator}-${environment}"

# example "finance-westus2-ppe"
"${microservice.name}-${region}-${environment}"

# example "finance-westus2-feature1-tst"
"${microservice.name}-${region}-${environment_differentiator}-${environment}"
```

## Naming Exceptions

Storage Accounts and Key Vaults have restrictions to 24 characters. To reduce issues with this you should try to keep the combined length of variables under 24 characters

Storage Account Example
```hcl
# Example "myservicewestus2prd"
"${service_name}${region}${environment}"
```

KeyVault Examples
```hcl
# Global Example "myservice-prd"
"${service_name}-${environment}"

# Microservice Example "finance-prd"
"${microservice.name}-${environment}"
```

When using environment_differentiator we automatically try to accomodate the length restrictions on these resources and will shorten this value to fit. See the following examples for how the environment_differentiator "matthewsre" will be shortened

Storage Account Example
```hcl
# Example "myservice2westus2matthprd"
"${service_name}${region}${environment}"
```

KeyVault
```hcl
# Global Example "myservice2-matthewsr-prd"
"${service_name}-${environment}"

# Microservice Example "financials-matthewsr-prd"
"${microservice.name}-${environment}"
```

# Global Resources

## Primary Region

The order of the regions passed into the region variable is used to determine the primary region that will be used for global resources.

```hcl
module "microservice" {
  source = "Matthewsre/microservices/azurerm"

  ...

  regions = [
    "westus2",  # <== Primary Region
    "eastus",   # <== Secondary Region
    "japan"
  ]
}
```

## Resource Group (azurerm_resource_group)

All resources for the service will be put into a single global resource group.

If tags are needed on the resource group you can pass them into the resource_group_tags variable:

```hcl
module "microservice" {
  source = "Matthewsre/microservices/azurerm"

  ...

  resource_group_tags = {
    environment = "production"
    role        = "service"
    foo         = "bar"
  }
}
```

## Application Insights (azurerm_application_insights)

A single Application Insights instance will be created and will be added to the configuration of App Services and Function Apps.

The retention_in_days variable, which defaults to 90 and is used for multiple resource types, sets the retention period for Application Insights.

The application_insights_application_type is used to specify the type to create. Default is "web".

## Azure CosmosDB Account (azurerm_cosmosdb_account)

A single Cosmos DB Account will be created if any of the microservices have a container specified.

```hcl
module "microservice" {
  source = "Matthewsre/microservices/azurerm"

  ...

  microservices = [
    {
      ...
    
      cosmos_containers = [
        {
          name               = "AppObjectContainer"
          partition_key_path = "/PartitionKey"
          max_throughput     = 0
        },
    }
  ]
}
```

 The Cosmos DB Location will be set to the primary region. Any additional regions will be added as geo_locations with a failover priority that matches their index specified.

```hcl
module "microservice" {
  source = "Matthewsre/microservices/azurerm"

  ...

  regions = [
    "westus2",  # <== failover_priority = 0
    "eastus",   # <== failover_priority = 1
    "japan"     # <== failover_priority = 2
  ]
}
```

The cosmos_enable_free_tier variable can optionally be set to true to enable the free tier pricing option.

# Regional Resources


# Microservice Resources