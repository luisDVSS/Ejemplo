# ================= UTILIDADES =================

function IP-ToInt {
    param([string]$ip)
    $o = $ip.Split('.')
    return ([uint32]$o[0] -shl 24) -bor
           ([uint32]$o[1] -shl 16) -bor
           ([uint32]$o[2] -shl 8)  -bor
           ([uint32]$o[3])
}

function Int-ToIP {
    param([uint32]$ip)
    return "{0}.{1}.{2}.{3}" -f `
        (($ip -shr 24) -band 255),
        (($ip -shr 16) -band 255),
        (($ip -shr 8)  -band 255),
        ($ip -band 255)
}

function Valid-IP {
    param([string]$ip)
    return $ip -match '^(\d{1,3}\.){3}\d{1,3}$'
}

function Mismo-Segmento {
    param($ip1, $ip2, $mask)
    return ((IP-ToInt $ip1 -band IP-ToInt $mask) `
         -eq (IP-ToInt $ip2 -band IP-ToInt $mask))
}

function Prefijo-A-Mascara {
    param([int]$prefijo)
    $mask = [uint32](0xFFFFFFFF -shl (32 - $prefijo))
    return Int-ToIP $mask
}

# ================= DHCP =================

function Instalar-DHCP {
    if (-not (Get-WindowsFeature DHCP).Installed) {
        Install-WindowsFeature DHCP -IncludeManagementTools
        Add-DhcpServerInDC
    }
}

function Configurar-DHCP {
    do {
        $network = Read-Host "IP de red (ej. 192.168.1.0)"
    } until (Valid-IP $network)

    do {
        $prefijo = Read-Host "Prefijo (1-30)"
    } until ($prefijo -match '^\d+$' -and $prefijo -ge 1 -and $prefijo -le 30)

    $mask = Prefijo-A-Mascara $prefijo

    do {
        $ipMin = Read-Host "IP mínima del rango"
    } until (Valid-IP $ipMin)

    do {
        $ipMax = Read-Host "IP máxima del rango"
    } until (Valid-IP $ipMax -and (IP-ToInt $ipMax) -gt (IP-ToInt $ipMin))

    do {
        $gateway = Read-Host "Gateway (opcional)"
        if ($gateway -eq "") { break }
    } until (Valid-IP $gateway -and (Mismo-Segmento $gateway $network $mask))

    do {
        $dns = Read-Host "DNS (opcional)"
        if ($dns -eq "") { break }
    } until (Valid-IP $dns)

    do {
        $lease = Read-Host "Lease time (segundos)"
    } until ($lease -match '^\d+$' -and $lease -gt 0)

    $scopeName = "Scope_$network"

    Add-DhcpServerv4Scope `
        -Name $scopeName `
        -StartRange $ipMin `
        -EndRange $ipMax `
        -SubnetMask $mask `
        -State Active

    if ($gateway) {
        Set-DhcpServerv4OptionValue `
            -ScopeId $network `
            -Router $gateway
    }

    if ($dns) {
        Set-DhcpServerv4OptionValue `
            -ScopeId $network `
            -DnsServer $dns
    }

    Set-DhcpServerv4Scope `
        -ScopeId $network `
        -LeaseDuration ([TimeSpan]::FromSeconds($lease))

    Restart-Service DHCPServer
    Write-Host "DHCP configurado y activo"
}

# ================= MENU =================

do {
    Write-Host "========== MENU DHCP =========="
    Write-Host "1) Instalar y configurar DHCP"
    Write-Host "2) Salir"
    $op = Read-Host "Selecciona opcion"

    switch ($op) {
        1 {
            Instalar-DHCP
            Configurar-DHCP
        }
        2 {
            Write-Host "Hasta luego"
        }
        default {
            Write-Host "Opcion invalida"
        }
    }
} until ($op -eq 2)
