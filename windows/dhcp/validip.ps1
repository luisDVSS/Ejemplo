function Valid-IP {
    param (
        [string]$ip
    )

    # Validar formato general X.X.X.X
    if ($ip -notmatch '^([0-9]{1,3}\.){3}[0-9]{1,3}$') {
        return $false
    }

    # Separar octetos
    $octetos = $ip.Split('.')

    # Validar rango 0-255
    foreach ($octeto in $octetos) {
        if ([int]$octeto -lt 0 -or [int]$octeto -gt 255) {
            return $false
        }
    }

    # IPs explícitamente no permitidas
    $ipsBloqueadas = @(
        '0.0.0.0',
        '1.0.0.0',
        '127.0.0.0',
        '127.0.0.1',
        '255.255.255.255'
    )

    if ($ipsBloqueadas -contains $ip) {
        return $false
    }

    # Bloquear 127.0.0.0/8 (loopback)
    if ([int]$octetos[0] -eq 127) {
        return $false
    }

    # Bloquear 0.x.x.x
    if ([int]$octetos[0] -eq 0) {
        return $false
    }

    return $true
}

function Validar-Formato-IP {
    param (
        [string]$ip
    )

    # Validar estructura básica
    if ($ip -notmatch '^([0-9]{1,3}\.){3}[0-9]{1,3}$') {
        return $false
    }

    # Separar octetos
    $octetos = $ip.Split('.')

    # Validar rango
    foreach ($octeto in $octetos) {
        if ([int]$octeto -lt 0 -or [int]$octeto -gt 255) {
            return $false
        }
    }

    return $true
}
