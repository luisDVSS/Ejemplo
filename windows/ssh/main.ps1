# Cargar funciones
. (Join-Path (Split-Path $PSScriptRoot -Parent) "win_functions.ps1")

# Validar ejecución como Administrador
Is-Root

Write-Host "Script de configuración de SSH"

# Validar si el servicio sshd está instalado
if (-not (Is-Installed "sshd")) {

    Write-Host "Instalando OpenSSH Server..."

    Get-ServiceInstall "OpenSSH.Server~~~~0.0.1.0"

    Start-Service sshd
    Set-Service -Name sshd -StartupType Automatic
}

Write-Host "Configurando interfaz a usar en SSH..."

SetLocalRed -Interfaz "Ethernet 4" -IP "192.168.99.11" -Prefijo 24