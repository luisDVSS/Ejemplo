function Config-RedSV {
    param (
        [string]$interfaz,
        [string]$ip,
        [int]$prefijo
    )

    if ([string]::IsNullOrWhiteSpace($interfaz) -or
        [string]::IsNullOrWhiteSpace($ip) -or
        [string]::IsNullOrWhiteSpace($prefijo)) {

        Write-Host "Uno de los datos esta vacio"
        exit 1
    }

    Write-Host "Configurando interfaz: $interfaz..."

    # Deshabilitar DHCP
    Set-NetIPInterface -InterfaceAlias $interfaz -Dhcp Disabled -ErrorAction Stop

    # Eliminar IPs previas
    Get-NetIPAddress -InterfaceAlias $interfaz -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false

    # Asignar IP estática
    New-NetIPAddress `
        -InterfaceAlias $interfaz `
        -IPAddress $ip `
        -PrefixLength $prefijo `
        -AddressFamily IPv4

    Write-Host "Configuracion aplicada correctamente :D"
}
