function Test-SameNetwork {
    param (
        [Parameter(Mandatory)]
        [string]$IP1,

        [Parameter(Mandatory)]
        [string]$IP2,

        [Parameter(Mandatory)]
        [string]$Mask
    )

    try {
        $ip1Bytes = ([IPAddress]$IP1).GetAddressBytes()
        $ip2Bytes = ([IPAddress]$IP2).GetAddressBytes()
        $maskBytes = ([IPAddress]$Mask).GetAddressBytes()
    }
    catch {
        Write-Error "IP o mascara invalida"
        return $false
    }

    for ($i = 0; $i -lt 4; $i++) {
        if (($ip1Bytes[$i] -band $maskBytes[$i]) -ne
            ($ip2Bytes[$i] -band $maskBytes[$i])) {
            return $false
        }
    }

    return $true
}

#if(Test-SameNetwork 192.168.140.100 192.168.140.199 255.255.255.0){
#Write-Host "TRUE"
#}else{
#Write-Host "FALSE"
#}