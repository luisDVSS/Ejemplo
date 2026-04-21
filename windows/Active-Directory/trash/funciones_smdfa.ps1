# ============================================================
#  funciones_smdfa.ps1
#  Seguridad, MFA, Delegacion, FGPP y Auditoria
#  Complemento de funciones_ad.ps1 / main.ps1
# ============================================================

# ------------------------------------------------------------
# FUNCION 13 - Crear los 4 usuarios administradores delegados
# ------------------------------------------------------------
function crear_admins {
    Write-Host "`n[+] Creando OU de administradores delegados..." -ForegroundColor Cyan

    if (-not (Get-ADOrganizationalUnit -Filter { Name -eq "AdminsDelegados" } -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name "AdminsDelegados" `
            -Path "DC=empresa,DC=local" `
            -Description "Administradores con roles delegados RBAC"
    }

    $ouPath = "OU=AdminsDelegados,DC=empresa,DC=local"

    $admins = @(
        @{
            Name        = "Admin Identidad"
            Sam         = "admin_identidad"
            Description = "Rol 1: IAM Operator - Gestion ciclo de vida de usuarios"
            Pass        = "P@ssw0rd_Identidad1!"
        },
        @{
            Name        = "Admin Storage"
            Sam         = "admin_storage"
            Description = "Rol 2: Storage Operator - Cuotas y FSRM"
            Pass        = "P@ssw0rd_Storage2!"
        },
        @{
            Name        = "Admin Politicas"
            Sam         = "admin_politicas"
            Description = "Rol 3: GPO Compliance - GPOs y FGPP"
            Pass        = "P@ssw0rd_Politicas3!"
        },
        @{
            Name        = "Admin Auditoria"
            Sam         = "admin_auditoria"
            Description = "Rol 4: Security Auditor - Solo lectura de logs"
            Pass        = "P@ssw0rd_Auditoria4!"
        }
    )

    foreach ($admin in $admins) {
        $samBuscar = $admin.Sam
        if (-not (Get-ADUser -Filter "SamAccountName -eq '$samBuscar'" -ErrorAction SilentlyContinue)) {
            New-ADUser `
                -Name              $admin.Name `
                -SamAccountName    $admin.Sam `
                -UserPrincipalName "$($admin.Sam)@empresa.local" `
                -Path              $ouPath `
                -Description       $admin.Description `
                -AccountPassword   (ConvertTo-SecureString $admin.Pass -AsPlainText -Force) `
                -Enabled           $true `
                -PasswordNeverExpires   $false `
                -ChangePasswordAtLogon  $true

            Write-Host "  [OK] Creado: $($admin.Sam)" -ForegroundColor Green
        } else {
            Write-Host "  [--] Ya existe: $($admin.Sam)" -ForegroundColor Yellow
        }
    }

    Write-Host "[+] Usuarios administradores delegados creados.`n" -ForegroundColor Cyan
}


# ------------------------------------------------------------
# FUNCION 14 - Asignar permisos RBAC con dsacls / ACLs en AD
# ------------------------------------------------------------
function asignar_permisos_admins {
    Write-Host "`n[+] Asignando permisos RBAC a los administradores delegados..." -ForegroundColor Cyan

    $ouCuates   = "OU=Cuates,DC=empresa,DC=local"
    $ouNoCuates = "OU=NoCuates,DC=empresa,DC=local"
    $domainRoot = "DC=empresa,DC=local"

    # ----------------------------------------------------------------
    # ROL 1 - admin_identidad: Crear/Eliminar/Modificar usuarios + Reset Password
    # ----------------------------------------------------------------
    Write-Host "  [ROL 1] admin_identidad - IAM Operator" -ForegroundColor White

    foreach ($ou in @($ouCuates, $ouNoCuates)) {
        dsacls $ou /I:T /G "EMPRESA\admin_identidad:CCDC;user"                           | Out-Null
        dsacls $ou /I:S /G "EMPRESA\admin_identidad:WP;telephoneNumber;user"             | Out-Null
        dsacls $ou /I:S /G "EMPRESA\admin_identidad:WP;physicalDeliveryOfficeName;user"  | Out-Null
        dsacls $ou /I:S /G "EMPRESA\admin_identidad:WP;mail;user"                        | Out-Null
        dsacls $ou /I:S /G "EMPRESA\admin_identidad:WP;displayName;user"                 | Out-Null
        dsacls $ou /I:S /G "EMPRESA\admin_identidad:CA;Reset Password;user"              | Out-Null
        dsacls $ou /I:S /G "EMPRESA\admin_identidad:WP;lockoutTime;user"                 | Out-Null
        dsacls $ou /I:S /G "EMPRESA\admin_identidad:WP;userAccountControl;user"          | Out-Null
        Write-Host "    [OK] Permisos IAM aplicados en: $ou" -ForegroundColor Green
    }

    $domainAdminsPath = "CN=Domain Admins,CN=Users,DC=empresa,DC=local"
    dsacls $domainAdminsPath /D "EMPRESA\admin_identidad:WP" | Out-Null
    Write-Host "    [OK] Denegada modificacion de Domain Admins a admin_identidad" -ForegroundColor Green

    # ----------------------------------------------------------------
    # ROL 2 - admin_storage: Solo FSRM, denegado Reset Password
    # ----------------------------------------------------------------
    Write-Host "  [ROL 2] admin_storage - Storage Operator" -ForegroundColor White

    dsacls $domainRoot /I:T /G "EMPRESA\admin_storage:GR"                     | Out-Null
    dsacls $domainRoot /I:T /D "EMPRESA\admin_storage:CA;Reset Password;user" | Out-Null

    Write-Host "    [OK] Denegado Reset Password a admin_storage en todo el dominio" -ForegroundColor Green
    Write-Host "    [INFO] Permisos FSRM se gestionan localmente en el servidor" -ForegroundColor DarkYellow

    # ----------------------------------------------------------------
    # ROL 3 - admin_politicas: Lectura global + escritura solo en GPOs
    # ----------------------------------------------------------------
    Write-Host "  [ROL 3] admin_politicas - GPO Compliance" -ForegroundColor White

    dsacls $domainRoot /I:T /G "EMPRESA\admin_politicas:GR" | Out-Null

    # Buscar el grupo GPO Creator Owners por nombre parcial (puede estar en espanol)
    $grupoGPO = Get-ADGroup -Filter * -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*reador*directiva*" -or $_.Name -like "*Policy Creator*" } |
                Select-Object -First 1
    if ($grupoGPO) {
        Add-ADGroupMember -Identity $grupoGPO.DistinguishedName -Members "admin_politicas" -ErrorAction SilentlyContinue
        Write-Host "    [OK] admin_politicas agregado a: $($grupoGPO.Name)" -ForegroundColor Green
    } else {
        Write-Host "    [!] Grupo GPO Creator Owners no encontrado. Ejecuta:" -ForegroundColor Yellow
        Write-Host "        Get-ADGroup -Filter * | Select Name | Where Name -like '*directiva*'" -ForegroundColor Yellow
    }

    foreach ($ou in @($ouCuates, $ouNoCuates, $domainRoot)) {
        dsacls $ou /I:T /G "EMPRESA\admin_politicas:WP;gpLink"    | Out-Null
        dsacls $ou /I:T /G "EMPRESA\admin_politicas:WP;gpOptions" | Out-Null
    }

    dsacls $domainRoot /I:T /D "EMPRESA\admin_politicas:WP;user" | Out-Null

    Write-Host "    [OK] admin_politicas: lectura global + escritura sobre GPOs/Links" -ForegroundColor Green

    # ----------------------------------------------------------------
    # ROL 4 - admin_auditoria: Solo lectura + acceso a Event Log
    # ----------------------------------------------------------------
    Write-Host "  [ROL 4] admin_auditoria - Security Auditor (Read-Only)" -ForegroundColor White

    dsacls $domainRoot /I:T /G "EMPRESA\admin_auditoria:GR" | Out-Null
    dsacls $domainRoot /I:T /D "EMPRESA\admin_auditoria:GW" | Out-Null
    dsacls $domainRoot /I:T /D "EMPRESA\admin_auditoria:GA" | Out-Null

    # Buscar el grupo Event Log Readers por nombre parcial (puede estar en espanol)
    $grupoEventLog = Get-ADGroup -Filter * -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -like "*Event Log*" -or $_.Name -like "*Registro de eventos*" -or $_.Name -like "*lectores*registro*" } |
                     Select-Object -First 1
    if ($grupoEventLog) {
        Add-ADGroupMember -Identity $grupoEventLog.DistinguishedName -Members "admin_auditoria" -ErrorAction SilentlyContinue
        Write-Host "    [OK] admin_auditoria agregado a: $($grupoEventLog.Name)" -ForegroundColor Green
    } else {
        Write-Host "    [!] Grupo Event Log Readers no encontrado. Ejecuta:" -ForegroundColor Yellow
        Write-Host "        Get-ADGroup -Filter * | Select Name | Where Name -like '*registro*'" -ForegroundColor Yellow
    }

    Write-Host "    [OK] admin_auditoria: solo lectura configurada" -ForegroundColor Green
    Write-Host "[+] Permisos RBAC asignados correctamente.`n" -ForegroundColor Cyan
}


# ------------------------------------------------------------
# FUNCION 15 - Configurar auditoria de eventos (auditpol)
# ------------------------------------------------------------
function configurar_auditoria {
    Write-Host "`n[+] Configurando politicas de auditoria..." -ForegroundColor Cyan

    auditpol /set /subcategory:"Logon"                              /success:enable /failure:enable
    auditpol /set /subcategory:"Logoff"                             /success:enable /failure:enable
    auditpol /set /subcategory:"Credential Validation"              /success:enable /failure:enable
    auditpol /set /subcategory:"Kerberos Authentication Service"    /success:enable /failure:enable
    auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable
    auditpol /set /subcategory:"File System"                        /success:enable /failure:enable
    auditpol /set /subcategory:"Other Object Access Events"         /success:enable /failure:enable
    auditpol /set /subcategory:"User Account Management"            /success:enable /failure:enable
    auditpol /set /subcategory:"Security Group Management"          /success:enable /failure:enable
    auditpol /set /subcategory:"Audit Policy Change"                /success:enable /failure:enable
    auditpol /set /subcategory:"Special Logon"                      /success:enable /failure:enable

    Write-Host "[+] Auditoria configurada. Estado actual:`n" -ForegroundColor Cyan
    auditpol /get /category:*
}


# ------------------------------------------------------------
# FUNCION 16 - Configurar FGPP (Fine-Grained Password Policy)
# ------------------------------------------------------------
function configurar_FGPP {
    Write-Host "`n[+] Configurando Politicas de Contrasena Ajustada (FGPP)..." -ForegroundColor Cyan

    # FGPP 1 - Admins (minimo 12 caracteres)
    $nombreFGPP_Admin = "FGPP-AdminPrivilegiados"

    if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$nombreFGPP_Admin'" -ErrorAction SilentlyContinue)) {
        New-ADFineGrainedPasswordPolicy `
            -Name                        $nombreFGPP_Admin `
            -Precedence                  10 `
            -MinPasswordLength           12 `
            -PasswordHistoryCount        10 `
            -ComplexityEnabled           $true `
            -ReversibleEncryptionEnabled $false `
            -MinPasswordAge              (New-TimeSpan -Days 1) `
            -MaxPasswordAge              (New-TimeSpan -Days 60) `
            -LockoutThreshold            5 `
            -LockoutDuration             (New-TimeSpan -Minutes 30) `
            -LockoutObservationWindow    (New-TimeSpan -Minutes 30) `
            -Description                 "Politica para cuentas administrativas - min 12 chars"

        Write-Host "  [OK] FGPP '$nombreFGPP_Admin' creada." -ForegroundColor Green
    } else {
        Write-Host "  [--] FGPP '$nombreFGPP_Admin' ya existe." -ForegroundColor Yellow
    }

    foreach ($sam in @("admin_identidad","admin_storage","admin_politicas","admin_auditoria")) {
        try {
            Add-ADFineGrainedPasswordPolicySubject -Identity $nombreFGPP_Admin -Subjects $sam
            Write-Host "  [OK] FGPP admin aplicada a: $sam" -ForegroundColor Green
        } catch {
            Write-Host "  [!] Error al aplicar FGPP a $sam : $_" -ForegroundColor Red
        }
    }

    $grupoDomainAdmins = Get-ADGroup -Filter * -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -like "*Domain Admins*" -or $_.Name -like "*Admins. del dominio*" -or $_.Name -like "*Administradores*dominio*" } |
                         Select-Object -First 1
    if ($grupoDomainAdmins) {
        try {
            Add-ADFineGrainedPasswordPolicySubject -Identity $nombreFGPP_Admin -Subjects $grupoDomainAdmins.SamAccountName
            Write-Host "  [OK] FGPP admin aplicada al grupo: $($grupoDomainAdmins.Name)" -ForegroundColor Green
        } catch {
            Write-Host "  [!] Error al aplicar FGPP a $($grupoDomainAdmins.Name): $_" -ForegroundColor Red
        }
    } else {
        Write-Host "  [!] Grupo Domain Admins no encontrado. Ejecuta: Get-ADGroup -Filter * | Select Name" -ForegroundColor Yellow
    }

    # FGPP 2 - Usuarios estandar (minimo 8 caracteres)
    $nombreFGPP_User = "FGPP-UsuariosEstandar"

    if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$nombreFGPP_User'" -ErrorAction SilentlyContinue)) {
        New-ADFineGrainedPasswordPolicy `
            -Name                        $nombreFGPP_User `
            -Precedence                  20 `
            -MinPasswordLength           8 `
            -PasswordHistoryCount        5 `
            -ComplexityEnabled           $true `
            -ReversibleEncryptionEnabled $false `
            -MinPasswordAge              (New-TimeSpan -Days 1) `
            -MaxPasswordAge              (New-TimeSpan -Days 90) `
            -LockoutThreshold            5 `
            -LockoutDuration             (New-TimeSpan -Minutes 30) `
            -LockoutObservationWindow    (New-TimeSpan -Minutes 30) `
            -Description                 "Politica para usuarios estandar - min 8 chars"

        Write-Host "  [OK] FGPP '$nombreFGPP_User' creada." -ForegroundColor Green
    } else {
        Write-Host "  [--] FGPP '$nombreFGPP_User' ya existe." -ForegroundColor Yellow
    }

    foreach ($grupo in @("Cuates","NoCuates")) {
        try {
            Add-ADFineGrainedPasswordPolicySubject -Identity $nombreFGPP_User -Subjects $grupo
            Write-Host "  [OK] FGPP estandar aplicada al grupo: $grupo" -ForegroundColor Green
        } catch {
            Write-Host "  [!] Error al aplicar FGPP al grupo $grupo : $_" -ForegroundColor Red
        }
    }

    Write-Host "[+] FGPP configuradas correctamente.`n" -ForegroundColor Cyan
    Get-ADFineGrainedPasswordPolicy -Filter * | Select-Object Name, Precedence, MinPasswordLength, LockoutThreshold, LockoutDuration | Format-Table -AutoSize
}


# ------------------------------------------------------------
# FUNCION 17 - Extraer reporte de accesos denegados (ID 4625)
# ------------------------------------------------------------
function extraer_accesos_denegados {
    Write-Host "`n[+] Extrayendo los ultimos 10 eventos de Acceso Denegado (ID 4625)..." -ForegroundColor Cyan

    $fechaReporte = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $rutaReporte  = "C:\Reportes_Auditoria\AccesosDenegados_$fechaReporte.txt"

    if (-not (Test-Path "C:\Reportes_Auditoria")) {
        New-Item -Path "C:\Reportes_Auditoria" -ItemType Directory | Out-Null
    }

    $eventos = Get-WinEvent -LogName Security -FilterXPath "*[System[(EventID=4625)]]" `
        -MaxEvents 10 -ErrorAction SilentlyContinue

    if (-not $eventos) {
        Write-Host "  [!] No se encontraron eventos ID 4625 en el Security Log." -ForegroundColor Yellow
        "No se encontraron eventos de acceso denegado (ID 4625) al momento del reporte." | Out-File $rutaReporte
        return
    }

    $lineas = @()
    $lineas += "=" * 70
    $lineas += "  REPORTE DE ACCESOS DENEGADOS - empresa.local"
    $lineas += "  Generado: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
    $lineas += "  Servidor: $env:COMPUTERNAME"
    $lineas += "=" * 70
    $lineas += ""

    $contador = 1
    foreach ($evento in $eventos) {
        $xml       = [xml]$evento.ToXml()
        $eventData = $xml.Event.EventData.Data

        $usuarioNombre = ($eventData | Where-Object { $_.Name -eq "TargetUserName" }).'#text'
        $dominio       = ($eventData | Where-Object { $_.Name -eq "TargetDomainName" }).'#text'
        $workstation   = ($eventData | Where-Object { $_.Name -eq "WorkstationName" }).'#text'
        $ipOrigen      = ($eventData | Where-Object { $_.Name -eq "IpAddress" }).'#text'
        $tipoLogon     = ($eventData | Where-Object { $_.Name -eq "LogonType" }).'#text'
        $razonFallo    = ($eventData | Where-Object { $_.Name -eq "SubStatus" }).'#text'

        $descripcionFallo = switch ($razonFallo) {
            "0xC000006A" { "Contrasena incorrecta" }
            "0xC0000064" { "Usuario no existe" }
            "0xC000006D" { "Credenciales invalidas (usuario/pass)" }
            "0xC000006F" { "Restriccion de horario de inicio de sesion" }
            "0xC0000070" { "Restriccion de estacion de trabajo" }
            "0xC0000072" { "Cuenta deshabilitada" }
            "0xC000015B" { "Tipo de inicio de sesion no permitido" }
            "0xC0000193" { "Cuenta expirada" }
            "0xC0000234" { "Cuenta bloqueada" }
            default      { "Codigo: $razonFallo" }
        }

        $lineas += "--- Evento #$contador ---"
        $lineas += "  Fecha/Hora  : $($evento.TimeCreated)"
        $lineas += "  Usuario     : $usuarioNombre"
        $lineas += "  Dominio     : $dominio"
        $lineas += "  Workstation : $workstation"
        $lineas += "  IP Origen   : $ipOrigen"
        $lineas += "  Tipo Logon  : $tipoLogon"
        $lineas += "  Razon Fallo : $descripcionFallo"
        $lineas += ""
        $contador++
    }

    $lineas += "=" * 70
    $lineas += "  Total de eventos reportados: $($eventos.Count)"
    $lineas += "  Ruta del reporte: $rutaReporte"
    $lineas += "=" * 70

    $lineas | Out-File -FilePath $rutaReporte -Encoding UTF8

    Write-Host "[+] Reporte exportado a: $rutaReporte" -ForegroundColor Green
    Write-Host ""
    $lineas | ForEach-Object { Write-Host $_ }
}
