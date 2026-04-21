
$ADMINS_MFA = @(
    "admin_identidad",
    "admin_storage",
    "admin_politicas",
    "admin_auditoria"
)

# Ruta de instalacion de MultiOTP
$MULTIOTP_DIR    = "C:\multiotp"
$MULTIOTP_EXE    = "$MULTIOTP_DIR\multiotp.exe"
$MULTIOTP_URL    = "https://github.com/multiOTP/multiotp/releases/download/5.9.9.1/multiotp_5.9.9.1.zip"
$MULTIOTP_ZIP    = "C:\multiotp_install.zip"

# Ruta del script wrapper que usara OpenSSH como ForceCommand
$WRAPPER_SCRIPT  = "C:\multiotp\ssh_mfa_wrapper.ps1"

# Ruta del sshd_config de OpenSSH en Windows
$SSHD_CONFIG        = "$env:ProgramData\ssh\sshd_config"
$SSHD_CONFIG_BACKUP = "$env:ProgramData\ssh\sshd_config.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"


function instalar_multiotp {
    Write-Host "`n[PASO 1] Instalando MultiOTP..." -ForegroundColor Cyan

    if (Test-Path $MULTIOTP_EXE) {
        Write-Host "  [--] MultiOTP ya esta instalado en $MULTIOTP_DIR" -ForegroundColor Yellow
        return
    }

    # Crear directorio principal
    if (-not (Test-Path $MULTIOTP_DIR)) {
        New-Item -Path $MULTIOTP_DIR -ItemType Directory | Out-Null
    }

    # Descargar ZIP desde GitHub
    Write-Host "  [..] Descargando MultiOTP desde GitHub..." -ForegroundColor White
    try {
        Invoke-WebRequest -Uri $MULTIOTP_URL -OutFile $MULTIOTP_ZIP -UseBasicParsing
    } catch {
        Write-Host "  [!] Error al descargar MultiOTP." -ForegroundColor Red
        Write-Host "      Descarga manual desde: https://github.com/multiOTP/multiotp/releases" -ForegroundColor Yellow
        Write-Host "      Extrae el contenido en C:\multiotp y vuelve a ejecutar." -ForegroundColor Yellow
        return
    }

    # Extraer ZIP a directorio temporal para inspeccionar estructura
    $tempDir = "C:\multiotp_temp"
    Write-Host "  [..] Extrayendo archivos..." -ForegroundColor White
    Expand-Archive -Path $MULTIOTP_ZIP -DestinationPath $tempDir -Force
    Remove-Item $MULTIOTP_ZIP -Force

    # Buscar multiotp.exe en cualquier nivel de la extraccion
    $exeEncontrado = Get-ChildItem -Path $tempDir -Recurse -Filter "multiotp.exe" | Select-Object -First 1

    if ($exeEncontrado) {
        # Mover TODO el contenido del directorio donde esta el exe al MULTIOTP_DIR
        $dirFuente = $exeEncontrado.DirectoryName
        Get-ChildItem -Path $dirFuente | Move-Item -Destination $MULTIOTP_DIR -Force
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] MultiOTP instalado correctamente en $MULTIOTP_DIR" -ForegroundColor Green
    } else {
        Write-Host "  [!] No se encontro multiotp.exe en el ZIP extraido." -ForegroundColor Red
        Write-Host "      Revisa manualmente el contenido de $tempDir" -ForegroundColor Yellow
    }
}

