function Monitorear {

    while ($true) {
        Clear-Host

        Write-Host "Selecciona accion"
        Write-Host "========================"
        Write-Host
        Write-Host "1) Ver estado del servicio DHCP"
        Write-Host
        Write-Host "2) Ver Conexiones activas"
        Write-Host
        Write-Host "3) Salir"
        Write-Host

        $opc = Read-Host

        switch ($opc) {

            '1' {
                Write-Host
                Write-Host "ESTADO DEL SERVIDOR DHCP"
                Write-Host "----------------------"
                Write-Host

                Get-Service -Name 'DHCPServer' | Format-Table Status, Name, DisplayName

                Read-Host "Presiona ENTER para volver al menu"
            }

            '2' {
                Write-Host
                Write-Host "Conexiones DHCP activas:"
                Write-Host "--------------------------"
                Write-Host

                # Requiere rol DHCP instalado
                Get-DhcpServerv4Lease |
                    Select-Object IPAddress, ClientId, HostName, AddressState |
                    Format-Table -AutoSize

                Write-Host
                Read-Host "Presiona ENTER para volver al menu"
            }

            '3' {
                Write-Host
                Write-Host "Saliendo.."
                exit 0
            }

            Default {
                Write-Host
                Write-Host "OPCION INVALIDA"
                Write-Host
                Start-Sleep -Seconds 1
            }
        }
    }
}
