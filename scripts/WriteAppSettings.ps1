Param
(   [Parameter(Mandatory = $true)][string]$appSettings,
    [Parameter(Mandatory = $true)][string]$filePath
)

$jsonAppSettings = ConvertFrom-Json $appSettings 
If (!(Test-Path $filePath)) { New-Item -Path $filePath -Force }
$jsonAppSettings | ConvertTo-Json -depth 100 | Out-File $filePath