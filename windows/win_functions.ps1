function Is-Installed {
    param (
        [string]$ServiceName
    )

    Write-Host "Validando que el servicio: $ServiceName esté instalado..."

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

    if ($service) {
        Write-Host "El servicio '$ServiceName' ya se encuentra instalado"
        return $true
    } else {
        Write-Host "El servicio '$ServiceName' NO se encuentra instalado"
        return $false
    }
}
function Get-ServiceInstall {
    param (
        [string]$FeatureName
    )

    Write-Host "Instalando..."
    Add-WindowsCapability -Online -Name $FeatureName -ErrorAction SilentlyContinue
}
function Is-Root {
    $currentUser = [Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()

    if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        Write-Host "Este script debe ejecutarse como Administrador"
        exit 1
    }
}
function sshConectar {
    param (
        [string]$User,
        [string]$IP
    )

    ssh "$User@$IP"
}
function SetLocalRed {
    param (
        [string]$Interfaz,
        [string]$IP,
        [int]$Prefijo
    )

    if (-not $Interfaz -or -not $IP -or -not $Prefijo) {
        Write-Host "Uno de los datos está vacío"
        exit 1
    }

    Write-Host "Configurando interfaz: $Interfaz..."

    # Eliminar IPs previas
    Get-NetIPAddress -InterfaceAlias $Interfaz -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

    # Asignar nueva IP estática
    New-NetIPAddress -InterfaceAlias $Interfaz `
                     -IPAddress $IP `
                     -PrefixLength $Prefijo

    Write-Host "Configuración aplicada correctamente"
}
function Is-HostIp {
    param([string]$Ip)

    if (-not (Is-IpFormat $Ip)) { return $false }

    $octets = $Ip.Split('.').ForEach({ [int]$_ })

    if ($Ip -in @("0.0.0.0","1.0.0.0","127.0.0.0","127.0.0.1","255.255.255.255")) {
        return $false
    }

    if ($octets[0] -eq 0) { return $false }

    return $true
}
function Is-IpFormat {
    param([string]$Ip)

    if ($Ip -notmatch '^(\d{1,3}\.){3}\d{1,3}$') { return $false }

    foreach ($oct in $Ip.Split('.')) {
        if ([int]$oct -lt 0 -or [int]$oct -gt 255) {
            return $false
        }
    }

    return $true
}

function Test-IPStatica {
    param (
        [string]$Interfaz
    )

    if (-not $Interfaz) {
        Write-Host "[ERROR] Debes indicar el nombre de la interfaz"
        return
    }

    $config = Get-NetIPInterface -InterfaceAlias $Interfaz -AddressFamily IPv4 -ErrorAction SilentlyContinue

    if (-not $config) {
        Write-Host "[ERROR] La interfaz no existe"
        return
    }

    if ($config.Dhcp -eq "Disabled") {
        Write-Host "La interfaz $Interfaz tiene IP ESTATICA" -ForegroundColor Green
        return $true
    }
    else {
        Write-Host "La interfaz $Interfaz usa DHCP (IP DINAMICA)" -ForegroundColor Yellow
        return $false
    }
}
function Is-Int {
    param($Value)
    return $Value -match '^\d+$'
}
function Ip-ToInt {
    param([string]$Ip)

    $o = $Ip.Split('.') | ForEach-Object { [int]$_ }
    return ($o[0] -shl 24) -bor ($o[1] -shl 16) -bor ($o[2] -shl 8) -bor $o[3]
}
function Is-SameSegment {
    param($Ip1, $Ip2, $Mask)

    return ((Ip-ToInt $Ip1 -band Ip-ToInt $Mask) -eq (Ip-ToInt $Ip2 -band Ip-ToInt $Mask))
}
function Prefix-ToMask {
    param([int]$Prefix)

    $mask = [uint32]0xFFFFFFFF -shl (32 - $Prefix)
    return Int-ToIp $mask
}
function Int-ToIp {
    param([uint32]$Int)

    return "{0}.{1}.{2}.{3}" -f `
        (($Int -shr 24) -band 255),
        (($Int -shr 16) -band 255),
        (($Int -shr 8) -band 255),
        ($Int -band 255)
}
function Get-Octet {
    param([string]$Ip, [int]$Num)

    if ($Num -lt 1 -or $Num -gt 4) { return $null }
    if (-not (Is-IpFormat $Ip)) { return $null }

    return $Ip.Split('.')[$Num - 1]
}
