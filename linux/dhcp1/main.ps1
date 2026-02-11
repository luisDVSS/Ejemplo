# ==========================================
# DHCP MANAGER ESTRICTO - WINDOWS SERVER
# ==========================================

# --------- FUNCIONES BASE ---------

function Convert-IpToInt {
    param ($ip)
    $o = $ip.Split(".")
    return ([int64]$o[0] -shl 24) -bor
           ([int64]$o[1] -shl 16) -bor
           ([int64]$o[2] -shl 8)  -bor
           ([int64]$o[3])
}

function Convert-IntToIp {
    param ($int)
    return "$(($int -shr 24) -band 255)." +
           "$(($int -shr 16) -band 255)." +
           "$(($int -shr 8) -band 255)." +
           "$($int -band 255)"
}

function Validar-FormatoIP {
    param ($ip)

    if ($ip -notmatch "^(\d{1,3}\.){3}\d{1,3}$") { return $false }

    $oct = $ip.Split(".")
    foreach ($o in $oct) {
        if ([int]$o -lt 0 -or [int]$o -gt 255) { return $false }
    }
    return $true
}

function Validar-IPHost {
    param ($ip)

    if (!(Validar-FormatoIP $ip)) { return $false }

    $o1 = [int]($ip.Split(".")[0])

    if ($ip -eq "0.0.0.0") { return $false }
    if ($ip -eq "255.255.255.255") { return $false }
    if ($o1 -eq 127) { return $false }
    if ($o1 -eq 0) { return $false }

    return $true
}

function Prefijo-A-Mascara {
    param ($prefijo)
    $mask = [uint32]0xFFFFFFFF -shl (32 - $prefijo)
    return Convert-IntToIp $mask
}

function Mismo-Segmento {
    param ($ip1, $ip2, $mask)

    $ip1int = Convert-IpToInt $ip1
    $ip2int = Convert-IpToInt $ip2
    $maskint = Convert-IpToInt $mask

    return (($ip1int -band $maskint) -eq ($ip2int -band $maskint))
}

function Validar-IPNetworkReal {
    param ($network, $prefijo)

    if (!(Validar-FormatoIP $network)) { return $false }

    $ipInt = Convert-IpToInt $network
    $mask = [uint32]0xFFFFFFFF -shl (32 - $prefijo)
    $networkReal = $ipInt -band $mask

    return ($ipInt -eq $networkReal)
}

# -------- INSTALACION DHCP --------

function Instalar-DHCP {
    if (!(Get-WindowsFeature DHCP).Installed) {
        Install-WindowsFeature DHCP -IncludeManagementTools
        Add-DhcpServerInDC -ErrorAction SilentlyContinue
    }
}

# -------- CONFIGURACION DHCP --------

function Configurar-DHCP {

    # -------- INTERFAZ --------
    while ($true) {
        $interfaz = Read-Host "Ingresa la interfaz de red"

        if (!(Get-NetAdapter -Name $interfaz -ErrorAction SilentlyContinue)) {
            Write-Host "[AVISO] Interfaz no existente"
        }
        else { break }
    }

    # -------- NETWORK --------
    while ($true) {
        $network = Read-Host "IP de la network"

        if (!(Validar-FormatoIP $network)) {
            Write-Host "[AVISO] Formato IP invalido"
            continue
        }

        while ($true) {
            $prefijo = Read-Host "Prefijo (1-30)"
            if ($prefijo -notmatch "^\d+$" -or [int]$prefijo -lt 1 -or [int]$prefijo -gt 30) {
                Write-Host "Prefijo invalido"
            }
            else { break }
        }

        if (Validar-IPNetworkReal $network $prefijo) {
            break
        }
        else {
            Write-Host "La IP no corresponde a una network real"
        }
    }

    $mascara = Prefijo-A-Mascara $prefijo

    $ipInt = Convert-IpToInt $network
    $serverIp = Convert-IntToIp ($ipInt + 1)

    New-NetIPAddress -InterfaceAlias $interfaz `
                     -IPAddress $serverIp `
                     -PrefixLength $prefijo `
                     -AddressFamily IPv4 `
                     -ErrorAction SilentlyContinue

    # -------- RANGO --------
    while ($true) {

        while ($true) {
            $ipMin = Read-Host "IP minima"
            if (Validar-IPHost $ipMin) { break }
            Write-Host "[AVISO] IP invalida"
        }

        while ($true) {
            $ipMax = Read-Host "IP maxima"
            if (Validar-IPHost $ipMax) { break }
            Write-Host "[AVISO] IP invalida"
        }

        if ((Convert-IpToInt $ipMax) -le (Convert-IpToInt $ipMin)) {
            Write-Host "[AVISO] IP maxima debe ser mayor"
            continue
        }

        if ((Convert-IpToInt $serverIp) -gt (Convert-IpToInt $ipMin) -and
            (Convert-IpToInt $serverIp) -lt (Convert-IpToInt $ipMax)) {

            Write-Host "[AVISO] La IP del servidor no puede estar dentro del rango"
            continue
        }

        if (!(Mismo-Segmento $ipMin $serverIp $mascara)) {
            Write-Host "Rango fuera del segmento"
            continue
        }

        break
    }

    # -------- DNS --------
    while ($true) {
        $dns = Read-Host "DNS (opcional)"
        if ([string]::IsNullOrWhiteSpace($dns)) { break }
        if (Validar-IPHost $dns) { break }
        Write-Host "[AVISO] DNS invalido"
    }

    # -------- GATEWAY --------
    while ($true) {
        $gateway = Read-Host "Gateway (opcional)"
        if ([string]::IsNullOrWhiteSpace($gateway)) { break }

        if (!(Validar-IPHost $gateway)) {
            Write-Host "[AVISO] Gateway invalido"
            continue
        }

        if (!(Mismo-Segmento $gateway $network $mascara)) {
            Write-Host "Gateway fuera del segmento"
            continue
        }

        break
    }

    # -------- LEASE --------
    while ($true) {
        $lease = Read-Host "Lease en segundos"
        if ($lease -match "^\d+$" -and [int]$lease -gt 0) { break }
        Write-Host "[AVISO] Lease invalido"
    }

    $leaseTime = [TimeSpan]::FromSeconds([int]$lease)

    # -------- CREAR SCOPE --------
    Add-DhcpServerv4Scope `
        -Name "ScopePrincipal" `
        -StartRange $ipMin `
        -EndRange $ipMax `
        -SubnetMask $mascara `
        -State Active

    if ($gateway) {
        Set-DhcpServerv4OptionValue -Router $gateway
    }

    if ($dns) {
        Set-DhcpServerv4OptionValue -DnsServer $dns
    }

    Set-DhcpServerv4Scope `
        -ScopeId $network `
        -LeaseDuration $leaseTime

    Write-Host "DHCP configurado correctamente"
}

# -------- MONITOREO --------

function Monitorear {
    while ($true) {
        Clear-Host
        Write-Host "1) Estado del servicio"
        Write-Host "2) Concesiones activas"
        Write-Host "3) Salir"

        $opc = Read-Host "Selecciona"

        switch ($opc) {
            1 { Get-Service DHCPServer; Pause }
            2 { Get-DhcpServerv4Lease; Pause }
            3 { break }
            default { Write-Host "Opcion invalida"; Pause }
        }
    }
}

# -------- MENU PRINCIPAL --------

while ($true) {

    Write-Host "==============================="
    Write-Host "1) Instalar DHCP y configurar"
    Write-Host "2) Monitoreo"
    Write-Host "3) Salir"

    $op = Read-Host "Selecciona"

    switch ($op) {
        1 {
            Instalar-DHCP
            Configurar-DHCP
        }
        2 { Monitorear }
        3 { break }
        default { Write-Host "Opcion invalida" }
    }
}
