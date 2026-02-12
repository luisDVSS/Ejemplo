function Monitorear {
    while ($true) {
        Clear-Host
        Write-Host "Selecciona accion"
        Write-Host "========================"
        Write-Host "1) Ver estado del servicio DHCP"
        Write-Host "2) Ver concesiones DHCP activas"
        Write-Host "3) Ver Ambitos"
        Write-Host "4) Salir"
        $opc = Read-Host "Opcion"

        switch ($opc) {
            1 {
                Get-Service -Name DHCPServer
                Read-Host "Presiona ENTER para volver al menu"
            }
            2 {
                Get-DhcpServerv4Lease | Format-Table IPAddress, ClientId, HostName, AddressState
                Read-Host "Presiona ENTER para volver al menu"
            }
            3 {
                Get-DhcpServerv4Scope
		Read-Host "Presiona Enter para volver al menu"
            }
            4 {
                Write-Host "Saliendo.."
                return
            }
            default {
                Write-Host "Opcion invalida" -ForegroundColor Red
                Start-Sleep 1
            }
        }
    }
}
