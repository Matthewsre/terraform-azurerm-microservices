# $ipv4 = Test-Connection -ComputerName (hostname) -Count 1  | Select IPV4Address
# $ipv4 = $(ipconfig | where {$_ -match 'IPv4.+\s(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})' } | out-null; $Matches[1])
$returnedIpv4 = (Invoke-WebRequest -uri "https://ifconfig.me/ip").Content
$pattern = "^([1-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])(\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){3}$"
$validIpv4 = $returnedIpv4 -match $pattern
$ipv4 = if($validIpv4) {$returnedIpv4} else {null}
@{
    ip_address = $ipv4;
} | ConvertTo-Json