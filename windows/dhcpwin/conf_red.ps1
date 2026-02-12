function Config-RedSV {
    param (
        [string]$Interfaz,
        [string]$IP,
        [int]$Prefijo
    )

    if (-not $Interfaz -or -not $IP -or -not $Prefijo) {
        Write-Host "[AVISO] Uno de los datos esta vacio"
        exit 1
    }

    Write-Host "Configurando IP estatica en $Interfaz..."

    # Eliminar IPs previas
    Get-NetIPAddress -InterfaceAlias $Interfaz -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false

    New-NetIPAddress `
        -InterfaceAlias $Interfaz `
        -IPAddress $IP `
        -PrefixLength $Prefijo `
        -AddressFamily IPv4

    Write-Host "Configuracion aplicada correctamente" -ForegroundColor Green
}
