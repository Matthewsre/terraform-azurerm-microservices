output "mapping" {
  value = {

    //Public Regions
    //{displayName|name} = "{region char(s)}{countrycode}[numerical designator]" => "West US 2" => {"West" => 'w'}{"US" => "us"}[2 => 2] => "wus2"
    //Country Code List: https://www.nationsonline.org/oneworld/country_code_list.htm

    //US
    "Central US"           = "cus"
    "centralus"            = "cus"
    "East US"              = "eus"
    "eastus"               = "eus"
    "East US 2"            = "eus2"
    "eastus2"              = "eus2"
    "North Central US"     = "ncus"
    "northcentralus"       = "ncus"
    "South Central US"     = "scus"
    "southcentralus"       = "scus"
    "West Central US"      = "wcus"
    "westcentralus"        = "wcus"
    "West US"              = "wus"
    "westus"               = "wus"
    "West US 2"            = "wus2"
    "westus2"              = "wus2"
    "West US 3"            = "wus3"
    "westus3"              = "wus3"

    //CA
    "Canada Central"       = "cca"
    "canadacentral"        = "cca"
    "Canada East"          = "eca"
    "canadaeast"           = "eca"

    //BR
    "Brazil South"         = "sbr"
    "brazilsouth"          = "sbr"
    "Brazil Southeast"     = "sebr"
    "brazilsoutheast"      = "sebr"

    //AS
    "East Asia"            = "eas"
    "eastasia"             = "eas"
    "Southeast Asia"       = "seas"
    "southeastasia"        = "seas"

    //JP
    "Japan East"           = "ejp"
    "japaneast"            = "ejp"
    "Japan West"           = "wjp"
    "japanwest"            = "wjp"

    //KR
    "Korea Central"        = "ckr"
    "koreacentral"         = "ckr"
    "Korea South"          = "skr"
    "koreasouth"           = "skr"

    //IN
    "Central India"        = "cin"
    "centralindia"         = "cin"
    "South India"          = "sin"
    "southindia"           = "sin"
    "West India"           = "win"
    "westindia"            = "win"

    //AU
    "Australia Central"    = "cau"
    "australiacentral"     = "cau"
    "Australia Central 2"  = "cau2"
    "australiacentral2"    = "cau2"
    "Australia East"       = "eau"
    "australiaeast"        = "eau"
    "Australia Southeast"  = "seau"
    "australiasoutheast"   = "seau"

    //EU
    "North Europe"         = "neu"
    "northeurope"          = "neu"
    "West Europe"          = "weu"
    "westeurope"           = "weu"

    //UK
    "UK South"             = "suk"
    "uksouth"              = "suk"
    "UK West"              = "wuk"
    "ukwest"               = "wuk"

    //CH
    "Switzerland North"    = "nch"
    "switzerlandnorth"     = "nch"
    "Switzerland West"     = "wch"
    "switzerlandwest"      = "wch"

    //DE
    "Germany North"        = "nde"
    "germanynorth"         = "nde"
    "Germany West Central" = "wcde"
    "germanywestcentral"   = "wcde"

    //NO
    "Norway East"          = "eno"
    "norwayeast"           = "eno"
    "Norway West"          = "wno"
    "norwaywest"           = "wno"

    //FR
    "France Central"       = "cfr"
    "francecentral"        = "cfr"
    "France South"         = "sfr"
    "francesouth"          = "sfr"

    //AE
    "UAE Central"          = "cae"
    "uaecentral"           = "cae"
    "UAE North"            = "nae"
    "uaenorth"             = "nae"

    //ZA
    "South Africa North"   = "nza"
    "southafricanorth"     = "nza"
    "South Africa West"    = "wza"
    "southafricawest"      = "wza"

    //Gov Regions
    //{displayName|name} = "{'g'}{statecode}" => "USGov Arizona" => {"USGov" => 'g'}{"Arizona" => "az"} => "gaz"
    "USGov Arizona"        = "gaz"
    "usgovarizona"         = "gaz"
    "USGov Iowa"           = "gia"
    "usgoviowa"            = "gia"
    "USGov Texas"          = "gtx"
    "usgovtexas"           = "gtx"
    "USGov Virginia"       = "gva"
    "usgovvirginia"        = "gva"

    //Gov DoD Regions
    //{displayName|name} = "{'d'}{region char(s)}" => "USDoD East" => {"USDoD" => 'd'}{"East" => "e"} => "de"
    "USDoD East"           = "de"
    "usdodeast"            = "de"
    "USDoD Central"        = "dc"
    "usdodcentral"         = "dc"
  }
}