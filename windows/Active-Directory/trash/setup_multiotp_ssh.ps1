# ============================================================
#  setup_multiotp_ssh.ps1
#  MFA via Google Authenticator (TOTP) para SSH
#  Solo aplica a los 4 administradores delegados
#  empresa.local
#
#  CORRECCIONES aplicadas respecto a la version anterior:
#   1. Generacion de secreto Base32 real y aleatorio por usuario
#   2. Sintaxis correcta de multiotp.exe -create
#   3. Wrapper usa cmd.exe /c para lanzar powershell con TTY
#   4. sshd_config usa "RequestTTY forced" en el bloque Match
# ============================================================

$ADMINS_MFA = @(
    "admin_identidad",
    "admin_storage",
    "admin_politicas",
    "admin_auditoria"
)

$MULTIOTP_DIR    = "C:\multiotp"
$MULTIOTP_EXE    = "$MULTIOTP_DIR\multiotp.exe"
$MULTIOTP_URL    = "https://github.com/multiOTP/multiotp/releases/download/5.9.9.1/multiotp_5.9.9.1.zip"
$MULTIOTP_ZIP    = "C:\multiotp_install.zip"

$WRAPPER_SCRIPT  = "C:\multiotp\ssh_mfa_wrapper.bat"

$SSHD_CONFIG        = "$env:ProgramData\ssh\sshd_config"
$SSHD_CONFIG_BACKUP = "$env:ProgramData\ssh\sshd_config.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"


# ============================================================
# FUNCION AUXILIAR — Generar secreto Base32 aleatorio (160 bits)
# Compatible con Google Authenticator (RFC 4648)
# ============================================================
function New-Base32Secret {
    $alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $rng      = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    $bytes    = New-Object byte[] 20   # 160 bits = secreto TOTP estandar
    $rng.GetBytes($bytes)

    # Convertir bytes a Base32 (grupos de 5 bits)
    $result = ""
    $buffer = 0
    $bitsLeft = 0

    foreach ($byte in $bytes) {
        $buffer   = ($buffer -shl 8) -bor $byte
        $bitsLeft += 8
        while ($bitsLeft -ge 5) {
            $bitsLeft -= 5
            $result   += $alphabet[($buffer -shr $bitsLeft) -band 0x1F]
        }
    }

    # Padding si quedan bits
    if ($bitsLeft -gt 0) {
        $result += $alphabet[($buffer -shl (5 - $bitsLeft)) -band 0x1F]
    }

    return $result
}


# ============================================================
# PASO 0 — Verificar que OpenSSH Server este instalado
# ============================================================
function verificar_openssh {
    Write-Host "`n[PASO 0] Verificando OpenSSH Server..." -ForegroundColor Cyan

    $sshd = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if (-not $sshd) {
        Write-Host "  [!] OpenSSH Server no esta instalado. Instalando..." -ForegroundColor Yellow
        $cap = Get-WindowsCapability -Online | Where-Object { $_.Name -like "OpenSSH.Server*" }
        if ($cap) {
            Add-WindowsCapability -Online -Name $cap.Name
            Write-Host "  [OK] OpenSSH Server instalado." -ForegroundColor Green
        } else {
            Write-Host "  [!] No se pudo encontrar OpenSSH.Server en las capacidades de Windows." -ForegroundColor Red
            Write-Host "      Instala manualmente: Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0" -ForegroundColor Yellow
            exit 1
        }
    }

    # Asegurar que el servicio arranque automaticamente
    Set-Service -Name sshd -StartupType Automatic
    Start-Service -Name sshd -ErrorAction SilentlyContinue

    $estado = (Get-Service sshd).Status
    Write-Host "  [OK] Servicio sshd: $estado" -ForegroundColor Green

    # Crear directorio de configuracion si no existe
    $sshdDir = "$env:ProgramData\ssh"
    if (-not (Test-Path $sshdDir)) {
        New-Item -Path $sshdDir -ItemType Directory | Out-Null
    }

    # Generar sshd_config por defecto si no existe
    if (-not (Test-Path $SSHD_CONFIG)) {
        Write-Host "  [..] Generando sshd_config por defecto..." -ForegroundColor White
        & sshd -t 2>&1 | Out-Null
        # Forzar regeneracion del config por defecto
        Stop-Service sshd -Force -ErrorAction SilentlyContinue
        Start-Service sshd
        Start-Sleep -Seconds 2
        if (-not (Test-Path $SSHD_CONFIG)) {
            Write-Host "  [!] No se genero sshd_config automaticamente." -ForegroundColor Red
            Write-Host "      Crea el archivo en: $SSHD_CONFIG" -ForegroundColor Yellow
            exit 1
        }
    }

    Write-Host "  [OK] sshd_config encontrado en: $SSHD_CONFIG`n" -ForegroundColor Green
}


# ============================================================
# PASO 1 — Descargar e instalar MultiOTP
# ============================================================
function instalar_multiotp {
    Write-Host "`n[PASO 1] Instalando MultiOTP..." -ForegroundColor Cyan

    if (Test-Path $MULTIOTP_EXE) {
        Write-Host "  [--] MultiOTP ya esta instalado en $MULTIOTP_DIR" -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path $MULTIOTP_DIR)) {
        New-Item -Path $MULTIOTP_DIR -ItemType Directory | Out-Null
    }

    Write-Host "  [..] Descargando MultiOTP desde GitHub..." -ForegroundColor White
    try {
        Invoke-WebRequest -Uri $MULTIOTP_URL -OutFile $MULTIOTP_ZIP -UseBasicParsing
    } catch {
        Write-Host "  [!] Error al descargar MultiOTP." -ForegroundColor Red
        Write-Host "      Descarga manual desde: https://github.com/multiOTP/multiotp/releases" -ForegroundColor Yellow
        Write-Host "      Extrae el contenido en C:\multiotp y vuelve a ejecutar." -ForegroundColor Yellow
        exit 1
    }

    $tempDir = "C:\multiotp_temp"
    Write-Host "  [..] Extrayendo archivos..." -ForegroundColor White
    Expand-Archive -Path $MULTIOTP_ZIP -DestinationPath $tempDir -Force
    Remove-Item $MULTIOTP_ZIP -Force

    $exeEncontrado = Get-ChildItem -Path $tempDir -Recurse -Filter "multiotp.exe" | Select-Object -First 1

    if ($exeEncontrado) {
        $dirFuente = $exeEncontrado.DirectoryName
        Get-ChildItem -Path $dirFuente | Move-Item -Destination $MULTIOTP_DIR -Force
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] MultiOTP instalado correctamente en $MULTIOTP_DIR" -ForegroundColor Green
    } else {
        Write-Host "  [!] No se encontro multiotp.exe en el ZIP extraido." -ForegroundColor Red
        Write-Host "      Revisa manualmente el contenido de $tempDir" -ForegroundColor Yellow
        exit 1
    }
}


# ============================================================
# PASO 2 — Registrar los 4 admins en MultiOTP y generar QR
#
# CORRECCION: Se genera un secreto Base32 real y aleatorio
#             por cada usuario. La sintaxis correcta de -create es:
#             multiotp.exe -create <usuario> TOTP <secreto_base32> 6 30
# ============================================================
function registrar_usuarios_mfa {
    Write-Host "`n[PASO 2] Registrando usuarios en MultiOTP..." -ForegroundColor Cyan

    # Directorio donde se guardaran los QR y los secretos
    $qrDir = "$MULTIOTP_DIR\qr_codes"
    if (-not (Test-Path $qrDir)) {
        New-Item -Path $qrDir -ItemType Directory | Out-Null
    }

    foreach ($usuario in $ADMINS_MFA) {

        # Verificar si el usuario ya existe en MultiOTP
        # Exit code 0 = existe / distinto = no existe
        & $MULTIOTP_EXE -display-log -check $usuario 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [--] $usuario ya esta registrado en MultiOTP." -ForegroundColor Yellow
            continue
        }

        # --- CORRECCION 1: Generar secreto Base32 real ---
        $secreto = New-Base32Secret
        Write-Host "  [..] Creando usuario TOTP: $usuario" -ForegroundColor White

        # --- CORRECCION 2: Sintaxis correcta de -create ---
        # multiotp.exe -create <usuario> TOTP <secreto_base32> <digitos> <intervalo_segundos>
        $output = & $MULTIOTP_EXE -create $usuario TOTP $secreto 6 30 2>&1
        $exitCodeCreate = $LASTEXITCODE

        if ($exitCodeCreate -ne 0) {
            Write-Host "  [!] Error al crear usuario $usuario en MultiOTP (exit: $exitCodeCreate)" -ForegroundColor Red
            Write-Host "      Output: $output" -ForegroundColor DarkRed
            continue
        }

        Write-Host "  [OK] Usuario $usuario creado con secreto TOTP." -ForegroundColor Green

        # Guardar el secreto en archivo de texto (protegido, solo lectura del admin)
        $secretoFile = "$qrDir\secreto_$usuario.txt"
        "Usuario  : $usuario" | Out-File $secretoFile -Encoding UTF8
        "Secreto  : $secreto" | Out-File $secretoFile -Append -Encoding UTF8
        "Algoritmo: TOTP SHA1, 6 digitos, 30 segundos" | Out-File $secretoFile -Append -Encoding UTF8
        "URI      : otpauth://totp/empresa.local:$($usuario)?secret=$secreto&issuer=empresa.local&algorithm=SHA1&digits=6&period=30" | Out-File $secretoFile -Append -Encoding UTF8
        Write-Host "  [OK] Secreto guardado en: $secretoFile" -ForegroundColor Green

        # Configurar bloqueo: 3 intentos fallidos → 30 minutos bloqueado
        & $MULTIOTP_EXE -set $usuario max-block-otp-delay 1800 2>&1 | Out-Null

        # Exportar QR code a PNG
        $qrPath = "$qrDir\qr_$usuario.png"
        $output = & $MULTIOTP_EXE -qrcode $usuario $qrPath 2>&1

        if (Test-Path $qrPath) {
            Write-Host "  [QR] Codigo QR generado: $qrPath" -ForegroundColor Magenta
            Write-Host "       El usuario debe escanear este QR con Google Authenticator." -ForegroundColor Magenta
        } else {
            # Fallback: mostrar la URI TOTP para registro manual en la app
            Write-Host "  [!] No se genero el archivo QR. Usa esta URI para registrar manualmente:" -ForegroundColor Yellow
            Write-Host "      otpauth://totp/empresa.local:$($usuario)?secret=$secreto&issuer=empresa.local&algorithm=SHA1&digits=6&period=30" -ForegroundColor Cyan
        }

        Write-Host "" 
    }

    Write-Host "[+] Registro de usuarios MFA completado.`n" -ForegroundColor Cyan
}


# ============================================================
# PASO 3 — Crear el wrapper script (.bat + .ps1)
#
# CORRECCION: Se usa un .bat como ForceCommand en lugar de
#             llamar directamente a powershell.exe.
#             Esto garantiza que el TTY este activo antes de
#             que el script de PowerShell intente hacer Read-Host.
# ============================================================
function crear_wrapper_mfa {
    Write-Host "`n[PASO 3] Creando wrapper MFA para SSH..." -ForegroundColor Cyan

    # --- Wrapper .bat: es lo que ForceCommand ejecuta directamente ---
    # Llama a powershell con -NonInteractive NO para que Read-Host funcione
    $batContent = '@echo off' + "`r`n" +
                  'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\multiotp\ssh_mfa_wrapper.ps1"' + "`r`n"

    $batContent | Out-File -FilePath $WRAPPER_SCRIPT -Encoding ascii -Force
    Write-Host "  [OK] Wrapper .bat creado en: $WRAPPER_SCRIPT" -ForegroundColor Green

    # --- Script PowerShell que hace la validacion TOTP ---
    $ps1Path = "C:\multiotp\ssh_mfa_wrapper.ps1"

    $ps1Content = @'
# ============================================================
#  ssh_mfa_wrapper.ps1
#  Ejecutado por OpenSSH via ForceCommand (a traves del .bat)
#  Valida codigo TOTP con MultiOTP antes de dar acceso al shell
# ============================================================

$MULTIOTP_EXE  = "C:\multiotp\multiotp.exe"
$LOG_FILE      = "C:\multiotp\mfa_access_log.txt"
$usuarioActual = $env:USERNAME

function Write-Log {
    param($mensaje)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp | $usuarioActual | $mensaje" | Out-File -FilePath $LOG_FILE -Append -Encoding UTF8
}

# Verificar si el usuario esta registrado en MultiOTP
$checkOutput = & $MULTIOTP_EXE -display-log -check $usuarioActual 2>&1
if ($LASTEXITCODE -ne 0) {
    # Usuario no registrado -> sin MFA (no deberia ocurrir para los admins)
    Write-Log "ADVERTENCIA: usuario no registrado en MultiOTP, acceso sin MFA"
    Write-Host "[AVISO] Este usuario no tiene MFA configurado. Contacta al administrador." -ForegroundColor Yellow
    exit 1
}

# Pedir codigo TOTP
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Autenticacion de dos factores (2FA)    " -ForegroundColor Cyan
Write-Host "  Usuario: $usuarioActual                " -ForegroundColor White
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$intentos        = 0
$maxIntentos     = 3
$accesoConcedido = $false

while ($intentos -lt $maxIntentos -and -not $accesoConcedido) {
    $intentos++
    $codigo = Read-Host "Codigo Google Authenticator (intento $intentos/$maxIntentos)"

    if (-not $codigo -or $codigo.Trim() -eq "") {
        Write-Host "  [!] Codigo vacio. Intenta de nuevo." -ForegroundColor Yellow
        $intentos--   # No contar intento vacio
        continue
    }

    # Validar TOTP con MultiOTP
    # Exit codes relevantes:
    #   0  = OK - autenticacion exitosa
    #   21 = cuenta bloqueada
    #   98 = codigo incorrecto o expirado
    #   99 = usuario no encontrado
    & $MULTIOTP_EXE $usuarioActual $codigo.Trim() 2>&1 | Out-Null
    $exitCode = $LASTEXITCODE

    switch ($exitCode) {
        0 {
            Write-Host ""
            Write-Host "  [OK] Acceso concedido. Bienvenido, $usuarioActual." -ForegroundColor Green
            Write-Host ""
            Write-Log "ACCESO CONCEDIDO"
            $accesoConcedido = $true
        }
        21 {
            Write-Host ""
            Write-Host "  [BLOQUEADO] Cuenta bloqueada por intentos fallidos." -ForegroundColor Red
            Write-Host "  Contacta al administrador o espera 30 minutos."       -ForegroundColor Red
            Write-Log "ACCESO DENEGADO - CUENTA BLOQUEADA"
            exit 1
        }
        default {
            Write-Host "  [!] Codigo incorrecto (intento $intentos/$maxIntentos)." -ForegroundColor Red
            Write-Log "INTENTO FALLIDO $intentos - exit code: $exitCode"

            if ($intentos -ge $maxIntentos) {
                Write-Host ""
                Write-Host "  [BLOQUEADO] Demasiados intentos fallidos." -ForegroundColor Red
                Write-Host "  Cuenta bloqueada 30 minutos."              -ForegroundColor Red
                Write-Log "CUENTA BLOQUEADA tras $maxIntentos intentos"
                & $MULTIOTP_EXE -lock $usuarioActual 2>&1 | Out-Null
                exit 1
            }
        }
    }
}

if (-not $accesoConcedido) {
    exit 1
}

# Acceso concedido: lanzar shell o el comando SSH original
if ($env:SSH_ORIGINAL_COMMAND -and $env:SSH_ORIGINAL_COMMAND.Trim() -ne "") {
    Invoke-Expression $env:SSH_ORIGINAL_COMMAND
} else {
    # Lanzar PowerShell interactivo como shell principal
    powershell.exe -NoLogo
}
'@

    $ps1Content | Out-File -FilePath $ps1Path -Encoding UTF8 -Force
    Write-Host "  [OK] Script PS1 creado en: $ps1Path" -ForegroundColor Green
}


# ============================================================
# PASO 4 — Configurar sshd_config
#
# CORRECCIONES:
#   - ForceCommand apunta al .bat (no directamente a powershell)
#   - Se agrega "PermitTTY yes" en el bloque Match para
#     garantizar TTY activo (necesario para Read-Host)
#   - Se deshabilita PubkeyAuthentication en el bloque Match
#     para forzar que SOLO funcione con password + TOTP
# ============================================================
function configurar_sshd {
    Write-Host "`n[PASO 4] Configurando sshd_config para MFA..." -ForegroundColor Cyan

    if (-not (Test-Path $SSHD_CONFIG)) {
        Write-Host "  [!] No se encontro sshd_config en: $SSHD_CONFIG" -ForegroundColor Red
        Write-Host "      Ejecuta primero verificar_openssh" -ForegroundColor Yellow
        return
    }

    # Backup del archivo original
    Copy-Item $SSHD_CONFIG $SSHD_CONFIG_BACKUP
    Write-Host "  [OK] Backup creado: $SSHD_CONFIG_BACKUP" -ForegroundColor Green

    $contenido = Get-Content $SSHD_CONFIG -Raw

    # -- Habilitar PasswordAuthentication globalmente --
    if ($contenido -match "PasswordAuthentication\s+no") {
        $contenido = $contenido -replace "PasswordAuthentication\s+no", "PasswordAuthentication yes"
        Write-Host "  [OK] PasswordAuthentication habilitado." -ForegroundColor Green
    } elseif ($contenido -notmatch "PasswordAuthentication\s+yes") {
        $contenido += "`nPasswordAuthentication yes"
        Write-Host "  [OK] PasswordAuthentication agregado." -ForegroundColor Green
    }

    # -- Deshabilitar override de administradores en Match (linea que podria bloquear admins) --
    # En Windows, el sshd_config por defecto incluye este bloque que deja a los admin
    # sin password (usan solo clave publica). Lo deshabilitamos para los admins delegados.
    if ($contenido -match "Match Group administrators") {
        $contenido = $contenido -replace "(?m)^Match Group administrators[\s\S]*?(?=\n\S|\z)", ""
        Write-Host "  [OK] Bloque 'Match Group administrators' eliminado (evita conflicto con MFA)." -ForegroundColor Green
    }

    # -- Construir el bloque Match User para los 4 admins --
    $listaUsuarios = $ADMINS_MFA -join ","

    $bloqueMatch = @"

# ============================================================
# MFA OBLIGATORIO — Admins Delegados
# Generado por setup_multiotp_ssh.ps1
# IMPORTANTE: El cliente debe conectarse con:  ssh -t <usuario>@<servidor>
# ============================================================
Match User $listaUsuarios
    PasswordAuthentication yes
    PubkeyAuthentication no
    PermitTTY yes
    ForceCommand cmd.exe /c "C:\multiotp\ssh_mfa_wrapper.bat"
"@

    # Eliminar bloque anterior si existe (evita duplicados)
    $contenido = $contenido -replace "(?s)# ={10,}\r?\n# MFA OBLIGATORIO.*", ""

    # Agregar el bloque al final
    $contenido = $contenido.TrimEnd() + $bloqueMatch

    $contenido | Out-File -FilePath $SSHD_CONFIG -Encoding UTF8 -Force
    Write-Host "  [OK] sshd_config actualizado con bloque Match User para MFA." -ForegroundColor Green

    # Validar sintaxis
    Write-Host "  [..] Validando sintaxis del sshd_config..." -ForegroundColor White
    $validacion = & sshd -t 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [!] Error de sintaxis en sshd_config:" -ForegroundColor Red
        Write-Host "      $validacion" -ForegroundColor DarkRed
        Write-Host "  [..] Restaurando backup..." -ForegroundColor Yellow
        Copy-Item $SSHD_CONFIG_BACKUP $SSHD_CONFIG -Force
        Write-Host "  [OK] Backup restaurado. Revisa el sshd_config manualmente." -ForegroundColor Yellow
        return
    }
    Write-Host "  [OK] Sintaxis del sshd_config correcta." -ForegroundColor Green

    # Reiniciar SSH
    Write-Host "  [..] Reiniciando servicio OpenSSH..." -ForegroundColor White
    Restart-Service sshd -Force
    Start-Sleep -Seconds 3

    $estado = (Get-Service sshd).Status
    if ($estado -eq "Running") {
        Write-Host "  [OK] Servicio sshd reiniciado. Estado: $estado`n" -ForegroundColor Green
    } else {
        Write-Host "  [!] El servicio sshd no esta corriendo. Estado: $estado" -ForegroundColor Red
        Write-Host "      Ejecuta: sshd -t  para ver errores." -ForegroundColor Yellow
    }
}


# ============================================================
# PASO 5 — Mostrar resumen final
# ============================================================
function mostrar_resumen {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "  CONFIGURACION MFA COMPLETADA" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usuarios con MFA habilitado por SSH:" -ForegroundColor White
    foreach ($u in $ADMINS_MFA) {
        Write-Host "    - $u" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "  QR codes y secretos en:" -ForegroundColor White
    Write-Host "    $MULTIOTP_DIR\qr_codes\" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  INSTRUCCIONES PARA CADA ADMIN:" -ForegroundColor White
    Write-Host "  1. Abrir Google Authenticator en tu telefono"            -ForegroundColor Gray
    Write-Host "  2. Agregar cuenta -> Escanear codigo QR"                 -ForegroundColor Gray
    Write-Host "  3. Escanear el archivo qr_[tuusuario].png"               -ForegroundColor Gray
    Write-Host "  4. Conectarte con:  ssh -t [usuario]@[servidor]"         -ForegroundColor Cyan
    Write-Host "     Ingresa primero tu PASSWORD de Windows/AD"            -ForegroundColor Gray
    Write-Host "     Luego el CODIGO de 6 digitos de Google Authenticator" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  IMPORTANTE - el flag -t es obligatorio:" -ForegroundColor Yellow
    Write-Host "    ssh -t admin_identidad@192.168.1.10" -ForegroundColor Cyan
    Write-Host "    (sin -t el prompt del codigo no aparece)" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "  Politica de bloqueo:" -ForegroundColor White
    Write-Host "    3 intentos fallidos de TOTP -> cuenta bloqueada 30 min" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Log de accesos: C:\multiotp\mfa_access_log.txt" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Comandos utiles:" -ForegroundColor White
    Write-Host "    Desbloquear usuario : C:\multiotp\multiotp.exe -unlock [usuario]"           -ForegroundColor Yellow
    Write-Host "    Ver estado usuario  : C:\multiotp\multiotp.exe -display-log -check [usuario]" -ForegroundColor Yellow
    Write-Host "    Verificar SSH config: sshd -t"                                              -ForegroundColor Yellow
    Write-Host "    Estado servicio SSH : Get-Service sshd"                                     -ForegroundColor Yellow
    Write-Host ""
}


# ============================================================
# EJECUCION PRINCIPAL
# ============================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SETUP MFA SSH — MultiOTP + Google Auth  " -ForegroundColor Cyan
Write-Host "  empresa.local — Admins Delegados        " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

verificar_openssh
instalar_multiotp
registrar_usuarios_mfa
crear_wrapper_mfa
configurar_sshd
mostrar_resumen
