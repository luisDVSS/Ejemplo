Write-Host "`n> 2. Verificando Visual C++ Redistributable x64..." -ForegroundColor Yellow

$vcInstalado = Get-ItemProperty `
    "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" `
    -ErrorAction SilentlyContinue

if ($vcInstalado -and $vcInstalado.Installed -eq 1) {
    Write-Host "  [+] VC++ ya instalado (version $($vcInstalado.Version))." -ForegroundColor Green
} else {
    Write-Host "  [!] VC++ no encontrado. Descargando..." -ForegroundColor Yellow
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest `
            -Uri     "https://aka.ms/vs/17/release/vc_redist.x64.exe" `
            -OutFile $VCDest `
            -UseBasicParsing
        Write-Host "  [+] Descarga completada." -ForegroundColor Green
    } catch {
        Write-Host "  [-] Error: $($_.Exception.Message)" -ForegroundColor Red
        exit
    }

    $vcResult = Start-Process $VCDest `
        -ArgumentList "/install /quiet /norestart" `
        -Wait -PassThru

    switch ($vcResult.ExitCode) {
        0    { Write-Host "  [+] VC++ instalado." -ForegroundColor Green }
        3010 { Write-Host "  [+] VC++ instalado (reinicio pendiente, continuamos)." -ForegroundColor Green }
        default {
            Write-Host "  [-] VC++ fallo: $($vcResult.ExitCode)" -ForegroundColor Red
            exit
        }
    }
    Start-Sleep -Seconds 5
}
