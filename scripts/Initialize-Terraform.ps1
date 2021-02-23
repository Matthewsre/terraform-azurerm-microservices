param(
    [Parameter(Mandatory)] [string] $serviceName,
    [Parameter(Mandatory)] [ValidateSet("dev", "tst", "ppe", "prd")] [string] $environment,
    [string] $stateStorageRegion = "westus2",
    [string] $stateStorageSku = "Standard_LRS",
    [string] [AllowNull()] $stateResourceGroupName,
    [string] [AllowNull()] $stateStorageAccountName,
    [string] [AllowNull()] $stateStorageContainerName,
    [string] [AllowNull()] $stateFileName,
    # Valid options from here: https://www.terraform.io/docs/language/settings/backends/azurerm.html#environment
    [ValidateSet("public", "china", "german", "stack", "usgovernment")] [string] $cloudEnvironment = "public",
    [string] $subscriptionId,
    [string] $tenantId,
    [switch] $useMsi,
    [string] $clientId,
    [string] $objectId,
    [switch] $planOnly)

$resourceGroupName = if ([String]::IsNullOrWhiteSpace($stateResourceGroupName)) { "${serviceName}-tf-${environment}".ToLower() } else { $stateResourceGroupName }
$storageAccountName = if ([String]::IsNullOrWhiteSpace($stateStorageAccountName)) { "${serviceName}tf${environment}".ToLower() } else { $stateStorageAccountName }
$containerName = if ([String]::IsNullOrWhiteSpace($stateStorageContainerName)) { "${serviceName}-${environment}".ToLower() } else { $stateStorageContainerName }
$fileName = if ([String]::IsNullOrWhiteSpace($stateFileName)) { "${serviceName}-${environment}.tfstate".ToLower() } else { "${stateFileName}" }

Write-Host "Using the following options for State Management:"
Write-Host "Resource Group Name: $resourceGroupName"
Write-Host "Storage Account Name: $storageAccountName"
Write-Host "Storage Container Name: $containerName"
Write-Host "State File Name: $fileName"

$resourceGroupExists = $(az group exists -n $resourceGroupName) -eq 'true'
$storageAccountExists = $resourceGroupExists -eq $true -and $(az storage account list --query "[?name=='$storageAccountName'] && [?resourceGroup=='$resourceGroupName']" -o tsv).Length -ne 0

# fndtnwestus2matthewsrdev

Write-Host "Resoure Group Exists: $resourceGroupExists"
Write-Host "Storage Account Exists: $storageAccountExists"

if ($storageAccountExists -eq $false) {
    Write-Host "Validating Storage Account Name"
    $storageAccountNameAvailable = (az storage account check-name -n $storageAccountName --query "nameAvailable") -eq $true
    if (-not $storageAccountNameAvailable) {
        throw "Storage Account Name is not available: $storageAccountName"
    }
}

# Create resource group if it does not exist
if (-not $resourceGroupExists) {
    Write-Host "Creating resource group: $resourceGroupName"
    az group create -l $stateStorageRegion -n $resourceGroupName
    if ($LASTEXITCODE -ne 0) { Throw "ERROR: Error creating resource group" }
    Write-Host "Resource group created"
}

# Create storage account if it does not exist
if (-not $storageAccountExists) {
    Write-Host "Creating storage account: $storageAccountName"
    az storage account create -n $storageAccountName -g $resourceGroupName -l $stateStorageRegion --sku $stateStorageSku
    if ($LASTEXITCODE -ne 0) { Throw "ERROR: Error creating storage account" }
    Write-Host "Storage account created"
}

# Ensure current user has role to create/manage Storage Container
$objectId = if ([String]::IsNullOrWhiteSpace($objectId)) { az ad signed-in-user show --query objectId -o tsv } else { $objectId }
$subscriptionId = if ([String]::IsNullOrWhiteSpace($subscriptionId)) { az account show --query id --output tsv } else { $subscriptionId }
$tenantId = if ([String]::IsNullOrWhiteSpace($tenantId)) { az account show --query tenantId --output tsv } else { $tenantId }
$scope = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$storageAccountName"
$storageAccountRole = "Storage Blob Data Contributor"

Write-Host "Checking Permissions for '$objectId'"
#$storageAccountPermission = az role assignment list --assignee $objectId --role $storageAccountRole --scope $scope -o tsv
$storageAccountPermissionExists = $(az role assignment list --assignee $objectId --role $storageAccountRole --scope $scope -o tsv).Length -ne 0
Write-Host $storageAccountPermissionExists

if (-not $storageAccountPermissionExists) {
    Write-Host "Creating '$storageAccountRole' role assignment for '$objectId'"
    az role assignment create --assignee $objectId --role $storageAccountRole --scope $scope
    if ($LASTEXITCODE -ne 0) { Throw "ERROR: Error creating role assignment" }
}

$containerExists = $storageAccountExists -eq $true -and $(az storage container exists -n $containerName --account-name $storageAccountName --query "exists" --auth-mode login) -eq $true
Write-Host "Container Exists: ${containerExists}"

# Create container if it does not exist
if (-not $containerExists) {
    #Using exponential retry loop if permissions were just created
    $maxRetry = if (-not $storageAccountPermissionExists) { 5 } else { 0 }
    $attempts = 1
    $successfulContainerCreation = $false
    Write-Host "Creating storage container: $containerName"

    while (-not $successfulContainerCreation -and $attempts -le ($maxRetry + 1)) {
        $retryDelaySeconds = [math]::Pow(2, $attempts)
        Start-Sleep -s $retryDelaySeconds
        az storage container create -n $containerName --account-name $storageAccountName --auth-mode login 
        $successfulContainerCreation = $LASTEXITCODE -eq 0
        Write-Host "Successful: ${successfulContainerCreation} Attempts: ${attempts} RetryDelay: ${retryDelaySeconds}"
        $attempts++
    }
    if (-not $successfulContainerCreation) { Throw "ERROR: Error creating storage container" }
    Write-Host "Storage container created"
}

if (-not (Test-Path env:ARM_TENANT_ID)) { $env:ARM_TENANT_ID = "$tenantId" }
if (-not (Test-Path env:ARM_SUBSCRIPTION_ID)) { $env:ARM_SUBSCRIPTION_ID = "$subscriptionId" }
if (-not (Test-Path env:ARM_ENVIRONMENT)) { $env:ARM_ENVIRONMENT = "$cloudEnvironment" }


Write-Host "Initializing Terraform Backend"

terraform init -input=false `
    -backend-config="resource_group_name=${resourceGroupName}" `
    -backend-config="storage_account_name=${storageAccountName}" `
    -backend-config="container_name=${containerName}" `
    -backend-config="key=${fileName}"

if ($planOnly) {
    Write-Host "Creating Terraform Plan"
    terraform plan -input=false `
        -var="service_name=${serviceName}" `
        -var-file=".\config\${serviceName}.tfvars" `
        -var-file=".\config\${environment}.tfvars" `
        -out "${fileName}.tfplan"
}
else {
    Write-Host "Applying Terraform"
    terraform apply -input=false `
        -auto-approve `
        -var="service_name=${serviceName}" `
        -var-file=".\config\${serviceName}.tfvars" `
        -var-file=".\config\${environment}.tfvars"
}

# First - run this to download modules without initializing the back end
# terraform init -input=false -get=true -backend=false

# Second - run this to initialize with back end created.
# .\scripts\Initialize-Terraform.ps1 -serviceName "foundation" -environment "dev"
# .\.terraform\modules\microservice\scripts\Initialize-Terraform.ps1 -serviceName "foundation" -environment "dev"
# ..\..\scripts\Initialize-Terraform.ps1 -serviceName "foundation" -environment "dev"