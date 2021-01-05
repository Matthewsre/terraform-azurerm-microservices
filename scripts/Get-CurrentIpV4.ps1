$ipv4 = Test-Connection -ComputerName (hostname) -Count 1  | Select IPV4Address

@{
    ip_address = $ipv4.IPV4Address.IPAddressToString;
} | ConvertTo-Json