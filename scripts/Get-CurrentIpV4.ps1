# $ipv4 = Test-Connection -ComputerName (hostname) -Count 1  | Select IPV4Address
$ipv4 = $(ipconfig | where {$_ -match 'IPv4.+\s(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})' } | out-null; $Matches[1])

@{
    ip_address = $ipv4;
} | ConvertTo-Json