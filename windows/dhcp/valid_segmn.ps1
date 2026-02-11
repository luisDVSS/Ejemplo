function IP-ToInt {
    param (
        [string]$ip
    )

    $octetos = $ip.Split('.')

    return (
        ([uint32]$octetos[0] -shl 24) -bor
        ([uint32]$octetos[1] -shl 16) -bor
        ([uint32]$octetos[2] -shl 8)  -bor
        ([uint32]$octetos[3])
    )
}

function Is-Int {
    param (
        [string]$valor
    )

    return $valor -match '^[0-9]+$'
}

function Mismo-Segmento {
    param (
        [string]$ip1,
        [string]$ip2,
        [string]$mask
    )

    $ip1Int  = IP-ToInt $ip1
    $ip2Int  = IP-ToInt $ip2
    $maskInt = IP-ToInt $mask

    if ( ($ip1Int -band $maskInt) -eq ($ip2Int -band $maskInt) ) {
        return $true
    } else {
        return $false
    }
}
