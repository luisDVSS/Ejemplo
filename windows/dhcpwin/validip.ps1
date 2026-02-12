function Test-ValidIP {
    param ([string]$IP)

    # Validar formato general X.X.X.X
    if ($IP -notmatch '^([0-9]{1,3}\.){3}[0-9]{1,3}$') {
        return $false
    }

    # Separar octetos
    $octets = $IP.Split('.')

    # Validar rango 0-255
    foreach ($o in $octets) {
        if ([int]$o -lt 0 -or [int]$o -gt 255) {
            return $false
        }
    }

    # IPs explícitamente no permitidas
    $blockedIPs = @(
        "0.0.0.0",
        "1.0.0.0",
        "127.0.0.0",
        "127.0.0.1",
        "255.255.255.255"
    )

    if ($blockedIPs -contains $IP) {
        return $false
    }

    # Bloquear red 127.0.0.0/8 (loopback)
    if ([int]$octets[0] -eq 127) {
        return $false
    }

    # Bloquear 0.x.x.x
    if ([int]$octets[0] -eq 0) {
        return $false
    }

    return $true
}
function Test-ValidNetworkIP {
    param ([string]$IP)

    $ipInt = Convert-IPToInt $IP

    # 0.0.0.0
    if ($ipInt -eq 0) { return $false }

    # 127.0.0.0/8 (loopback)
    if ($ipInt -ge (Convert-IPToInt "127.0.0.0") -and
        $ipInt -le (Convert-IPToInt "127.255.255.255")) {
        return $false
    }

    # Multicast 224.0.0.0/4
    if ($ipInt -ge (Convert-IPToInt "224.0.0.0")) {
        return $false
    }

    return $true
}

function Test-ValidIPFormat {
    param ([string]$IP)

    # Validar estructura básica X.X.X.X
    if ($IP -notmatch '^([0-9]{1,3}\.){3}[0-9]{1,3}$') {
        return $false
    }

    # Separar octetos
    $octets = $IP.Split('.')

    # Validar rango 0-255
    foreach ($o in $octets) {
        if ([int]$o -lt 0 -or [int]$o -gt 255) {
            return $false
        }
    }

    return $true
}
