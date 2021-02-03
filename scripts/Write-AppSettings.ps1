Param
(   [Parameter(Mandatory = $true)][string]$appSettings,
    [Parameter(Mandatory = $true)][string]$filePath
)

if (!(Get-Module -ListAvailable -Name Newtonsoft.Json)) {
    Install-Module -Name Newtonsoft.Json -Scope CurrentUser -Force
}

Import-Module Newtonsoft.Json

$jsonAppSettings = ConvertFrom-Json $appSettings 
If (!(Test-Path $filePath)) { New-Item -Path $filePath -Force }
$jsonAppSettings | ConvertTo-Json -depth 100 | Out-File $filePath