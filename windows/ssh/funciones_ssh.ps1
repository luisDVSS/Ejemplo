
function Validar-Servicio {
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

# Instalar característica (ej: OpenSSH en Windows)
function Get-ServiceInstall {
    param (
        [string]$FeatureName
    )

    Write-Host "Instalando..."
    Add-WindowsCapability -Online -Name $FeatureName -ErrorAction SilentlyContinue
}

# Validar si se ejecuta como Administrador
function Is-Root {
    $currentUser = [Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()

    if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        Write-Host "Este script debe ejecutarse como Administrador"
        exit 1
    }
}

# Conectar por SSH
function Conectar {
    param (
        [string]$User,
        [string]$IP
    )

    ssh "$User@$IP"
}

# Configurar IP estática (Windows)
function Config-RedSV {
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