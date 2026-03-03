. "$PSScriptRoot\funciones.ps1"

function Inicializar-FTP {

    instalarFTP

    Set-WebConfigurationProperty `
        -Filter "/system.applicationHost/sites/site[@name='FTP']/ftpServer/userIsolation" `
        -Name "mode" `
        -Value "IsolateAllDirectories"

    $global:ADSI = [ADSI]"WinNT://$env:ComputerName"

    CrearGrupos

    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.security.ssl.controlChannelPolicy `
        -Value 0

    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.security.ssl.dataChannelPolicy `
        -Value 0

    Restart-WebItem "IIS:\Sites\FTP"

    Write-Host "Servidor FTP listo."
}

function Menu-Principal {

    do {

        Clear-Host
        Write-Host "========= PANEL ADMINISTRADOR FTP ========="
        Write-Host "1 - Inicializar FTP"
        Write-Host "2 - Agregar Usuario"
        Write-Host "3 - Cambiar Usuario de Grupo"
        Write-Host "4 - Reiniciar Servicio FTP"
        Write-Host "5 - Salir"
        Write-Host "==========================================="
        $opc = Read-Host "Seleccione una opcion"

        switch ($opc) {

            "1" {
                Inicializar-FTP
            }
            "2" {
                $num = Read-Host "Ingrese el numero de usuarios a registrar"
                for ($i = 1; $i -le $num; $i++) { 
                 CrearUsuario
                 Permisos
                 Pause
                }
            }

            "3" {
                
                 $usuario = Read-Host "Ingrese el nombre del usuario"
                 CambiarGrupoUsuario -NombreUsuario $usuario
                 Pause
                
            }

            "4" {
                Restart-WebItem "IIS:\Sites\FTP"
                Write-Host "FTP reiniciado correctamente."
                Pause
            }

            "5" {
                Write-Host "Saliendo..."
                exit
            }

            default {
                Write-Host "Opcion no valida."
                Pause
            }
        }

    } while ($opc -ne "4")
}

# ====== EJECUCION ======
Menu-Principal
