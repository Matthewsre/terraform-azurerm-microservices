# recommended solution by Microsoft that is returning correct IP
# https://techcommunity.microsoft.com/t5/itops-talk-blog/determining-the-public-ip-address-of-your-cloudshell-session/ba-p/1085251
$client = New-Object System.Net.WebClient
[xml]$response = $client.DownloadString("http://checkip.dyndns.org")
$returnedIpv4 = ($response.html.body -split ':')[1].Trim()
$pattern = "^([1-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])(\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){3}$"
$validIpv4 = $returnedIpv4 -match $pattern
$ipv4 = if($validIpv4) {$returnedIpv4} else {null}
@{
    ip_address = $ipv4;
} | ConvertTo-Json