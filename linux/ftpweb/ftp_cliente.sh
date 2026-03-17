#!/usr/bin/env bash
# ============================================================
#  ftp_cliente.sh  –  Práctica 7
#  Cliente FTP dinámico:
#    - Navega estructura /http/Linux/<Servicio>/<archivo>
#    - Descarga binario + .sha256
#    - Verifica integridad
#    - Instala el paquete descargado
# ============================================================

# ── Configuración del servidor FTP repositorio ───────────────
FTP_HOST=""
FTP_USER=""
FTP_PASS=""
FTP_BASE="/http/Linux"
DOWNLOAD_DIR="/tmp/repo_ftp"

configurar_ftp_repo() {
    echo ""
    echo "=== Configuración del repositorio FTP privado ==="
    read -rp "  IP del servidor FTP repositorio: " FTP_HOST
    read -rp "  Usuario FTP: " FTP_USER
    read -rsp "  Contraseña FTP: " FTP_PASS
    echo ""
    mkdir -p "$DOWNLOAD_DIR"
}

# ── Listar carpetas remotas vía curl ─────────────────────────
ftp_listar() {
    local ruta="$1"
    curl -s --user "$FTP_USER:$FTP_PASS" \
        --ssl --insecure \
        "ftp://$FTP_HOST$ruta/" 2>/dev/null |
        awk '{print $NF}' |
        grep -v '^\.' |
        grep -v '^$'
}

# ── Descargar archivo desde FTP ───────────────────────────────
ftp_descargar() {
    local ruta_remota="$1"
    local destino="$2"

    echo "  Descargando: ftp://$FTP_HOST$ruta_remota ..."
    curl -s --user "$FTP_USER:$FTP_PASS" \
        --ssl --insecure \
        "ftp://$FTP_HOST$ruta_remota" \
        -o "$destino"

    if [[ $? -eq 0 && -f "$destino" ]]; then
        echo "  [OK] Guardado en $destino"
        return 0
    else
        echo "  [ERROR] Fallo al descargar $ruta_remota"
        return 1
    fi
}

# ── Verificar integridad SHA256 ───────────────────────────────
verificar_integridad() {
    local archivo="$1"
    local hash_file="${archivo}.sha256"

    if [[ ! -f "$hash_file" ]]; then
        echo "  [ERROR] No se encontró el archivo de hash: $hash_file"
        return 1
    fi

    echo "  Verificando integridad de $(basename "$archivo") ..."

    # sha256sum -c espera formato: "HASH  nombre_archivo"
    # El .sha256 del servidor puede tener ruta absoluta; lo normalizamos
    local hash_remoto
    hash_remoto=$(awk '{print $1}' "$hash_file")
    local hash_local
    hash_local=$(sha256sum "$archivo" | awk '{print $1}')

    if [[ "$hash_local" == "$hash_remoto" ]]; then
        echo "  [OK] Integridad verificada correctamente."
        echo "       SHA256: $hash_local"
        return 0
    else
        echo "  [FAIL] El archivo está CORRUPTO o fue modificado."
        echo "         Esperado : $hash_remoto"
        echo "         Calculado: $hash_local"
        return 1
    fi
}

# ── Instalar paquete descargado ───────────────────────────────
instalar_paquete() {
    local archivo="$1"
    local ext="${archivo##*.}"

    echo ""
    echo "  Instalando $(basename "$archivo") ..."

    case "$ext" in
    deb)
        sudo dpkg -i "$archivo" 2>/dev/null
        # Siempre completar dependencias faltantes después de dpkg
        echo "  Completando dependencias ..."
        sudo apt-get install -f -y -q
        ;;
    gz | tgz)
        # Asumir tar.gz; extraer en /opt
        sudo tar -xzf "$archivo" -C /opt/
        echo "  [INFO] Extraído en /opt/. Configura el servicio manualmente si es necesario."
        ;;
    *)
        echo "  [ADVERTENCIA] Extensión .$ext no reconocida. Instalación manual necesaria."
        return 1
        ;;
    esac

    echo "  [OK] Instalación completada."
}

# ── Flujo principal: navegación FTP dinámica ─────────────────
instalar_desde_ftp() {
    configurar_ftp_repo

    echo ""
    echo "  Conectando al repositorio FTP $FTP_HOST ..."

    # 1. Listar servicios disponibles bajo /http/Linux/
    echo ""
    echo "  Servicios disponibles en el repositorio:"
    mapfile -t servicios < <(ftp_listar "$FTP_BASE")

    if [[ ${#servicios[@]} -eq 0 ]]; then
        echo "  [ERROR] No se encontraron servicios en $FTP_BASE"
        echo "          Verifica la IP, usuario, contraseña y estructura de directorios."
        return 1
    fi

    for i in "${!servicios[@]}"; do
        echo "    $((i + 1))) ${servicios[$i]}"
    done

    local idx_svc
    while true; do
        read -rp "  Selecciona el servicio [1-${#servicios[@]}]: " idx_svc
        [[ "$idx_svc" =~ ^[0-9]+$ ]] &&
            ((idx_svc >= 1 && idx_svc <= ${#servicios[@]})) && break
        echo "  Opción inválida."
    done
    local servicio="${servicios[$((idx_svc - 1))]}"
    local ruta_svc="$FTP_BASE/$servicio"

    # 2. Listar archivos dentro del servicio elegido (excluir .sha256)
    echo ""
    echo "  Versiones disponibles de $servicio:"
    mapfile -t archivos < <(ftp_listar "$ruta_svc" | grep -v '\.sha256$')

    if [[ ${#archivos[@]} -eq 0 ]]; then
        echo "  [ERROR] No hay archivos en $ruta_svc"
        return 1
    fi

    for i in "${!archivos[@]}"; do
        echo "    $((i + 1))) ${archivos[$i]}"
    done

    local idx_arch
    while true; do
        read -rp "  Selecciona el archivo a descargar [1-${#archivos[@]}]: " idx_arch
        [[ "$idx_arch" =~ ^[0-9]+$ ]] &&
            ((idx_arch >= 1 && idx_arch <= ${#archivos[@]})) && break
        echo "  Opción inválida."
    done
    local archivo="${archivos[$((idx_arch - 1))]}"
    local ruta_arch="$ruta_svc/$archivo"

    # 3. Descargar binario
    local dest_bin="$DOWNLOAD_DIR/$archivo"
    ftp_descargar "$ruta_arch" "$dest_bin" || return 1

    # 4. Descargar .sha256
    local dest_hash="$dest_bin.sha256"
    ftp_descargar "${ruta_arch}.sha256" "$dest_hash" || {
        echo "  [ADVERTENCIA] No se encontró archivo .sha256. Omitiendo verificación."
    }

    # 5. Verificar integridad
    if [[ -f "$dest_hash" ]]; then
        verificar_integridad "$dest_bin" || {
            echo "  [ABORTANDO] Instalación cancelada por fallo de integridad."
            return 1
        }
    fi

    # 6. Instalar
    instalar_paquete "$dest_bin" || return 1

    # 7. Generar index.html igual que install_servicio
    # Detectar nombre del servicio desde el nombre del archivo descargado
    local nombre_servicio
    local version_real
    case "${archivo,,}" in
    apache2*) nombre_servicio="apache2" ;;
    nginx*) nombre_servicio="nginx" ;;
    tomcat10* | tomcat9*) nombre_servicio="${archivo%%_*}" ;;
    vsftpd*) nombre_servicio="vsftpd" ;;
    *) nombre_servicio="${archivo%%_*}" ;;
    esac

    version_real=$(dpkg -l "$nombre_servicio" 2>/dev/null | awk '/^ii/{print $3}')
    if [[ -n "$version_real" ]]; then
        new_index_html "$nombre_servicio" "$version_real" "desde-FTP"
    fi
}
