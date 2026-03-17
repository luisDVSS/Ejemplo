#!/usr/bin/env bash
# ============================================================
#  main.sh  –  Práctica 7: Orquestador principal (Linux)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/http_funciones.sh"
source "$SCRIPT_DIR/ftp_funciones.sh"
source "$SCRIPT_DIR/ssl_funciones.sh"
source "$SCRIPT_DIR/ftp_cliente.sh"

if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Ejecuta como root: sudo bash main.sh"
    exit 1
fi

# ─────────────────────────────────────────────────────────────
# Verificar si un servicio está instalado
# ─────────────────────────────────────────────────────────────
servicio_instalado() {
    local svc="$1"
    dpkg -l "$svc" 2>/dev/null | grep -q "^ii"
}

# ─────────────────────────────────────────────────────────────
# Instalar servicio HTTP desde WEB o FTP
# ─────────────────────────────────────────────────────────────
instalar_http() {
    local servicio="$1"

    echo ""
    echo "======================================================"
    echo "  INSTALACIÓN DE: $servicio"
    echo "======================================================"
    echo "  Origen:"
    echo "    1) WEB  – apt (repositorios oficiales)"
    echo "    2) FTP  – repositorio privado"
    read -rp "  Elige [1/2]: " origen

    case "$origen" in
    1)
        echo "  [WEB] Instalando $servicio via apt ..."

        # Tomcat: detectar paquete disponible
        if [[ "$servicio" == "tomcat" ]]; then
            mapfile -t pkgs < <(apt-cache search "^tomcat[0-9]" 2>/dev/null | awk '{print $1}' | sort -rV)
            if [[ ${#pkgs[@]} -eq 0 ]]; then
                echo "  [ERROR] No se encontraron paquetes de Tomcat."
                return 1
            fi
            echo "  Paquetes Tomcat disponibles:"
            for i in "${!pkgs[@]}"; do echo "    $((i + 1))) ${pkgs[$i]}"; done
            read -rp "  Selecciona [1-${#pkgs[@]}]: " idx
            servicio="${pkgs[$((idx - 1))]}"
        fi

        mapfile -t versiones < <(get_versiones "$servicio")
        select_version "$servicio" "${versiones[@]}" || return 1

        local default_port=80
        [[ "$servicio" == tomcat* ]] && default_port=8080
        read_puerto $default_port

        install_servicio "$servicio" "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO"
        ;;
    2)
        instalar_desde_ftp || return 1

        # Después de instalar desde .deb, completar dependencias
        echo "  Completando dependencias ..."
        apt-get install -f -y -q
        ;;
    *)
        echo "  Opción inválida."
        return 1
        ;;
    esac

    # ── Verificar que quedó instalado antes de preguntar SSL ──
    local pkg_check="$servicio"
    [[ "$servicio" == "tomcat" ]] && pkg_check="tomcat*"

    if ! dpkg -l $pkg_check 2>/dev/null | grep -q "^ii"; then
        echo ""
        echo "  [ADVERTENCIA] $servicio no quedó instalado correctamente."
        echo "  Omitiendo configuración SSL."
        return 1
    fi

    # ── SSL ───────────────────────────────────────────────────
    echo ""
    read -rp "  ¿Activar SSL en $servicio? [S/N]: " activar_ssl
    if [[ "${activar_ssl,,}" == "s" ]]; then
        [[ ! -f "$CERT_FILE" ]] && generar_certificado
        case "$servicio" in
        apache2) ssl_apache2 ;;
        nginx) ssl_nginx ;;
        tomcat*) ssl_tomcat ;;
        esac
    fi
}

# ─────────────────────────────────────────────────────────────
# Configurar vsftpd
# ─────────────────────────────────────────────────────────────
instalar_ftp_linux() {
    echo ""
    echo "======================================================"
    echo "  CONFIGURACIÓN vsftpd"
    echo "======================================================"

    if ! servicio_instalado vsftpd; then
        echo "  Instalando vsftpd ..."
        apt-get update -q && apt-get install -y vsftpd
    else
        echo "  vsftpd ya está instalado."
    fi

    read -rp "  ¿Aplicar configuración base de Práctica 5? [S/N]: " aplicar
    if [[ "${aplicar,,}" == "s" ]]; then
        setFtpConf
        setGrupos
    fi

    read -rp "  ¿Activar FTPS (SSL) en vsftpd? [S/N]: " activar_ssl
    if [[ "${activar_ssl,,}" == "s" ]]; then
        [[ ! -f "$CERT_FILE" ]] && generar_certificado
        ssl_vsftpd
    fi
}

# ─────────────────────────────────────────────────────────────
# MENÚ PRINCIPAL
# ─────────────────────────────────────────────────────────────
while true; do
    echo ""
    echo "======================================================"
    echo "   PRÁCTICA 7 – Orquestador Linux  [reprobados.com]"
    echo "======================================================"
    echo "  INSTALACIÓN"
    echo "  1) Apache2"
    echo "  2) Nginx"
    echo "  3) Tomcat"
    echo "  4) vsftpd (FTP)"
    echo ""
    echo "  SSL / SEGURIDAD"
    echo "  5) Generar certificado SSL"
    echo "  6) Activar SSL → Apache2"
    echo "  7) Activar SSL → Nginx"
    echo "  8) Activar SSL → Tomcat"
    echo "  9) Activar FTPS → vsftpd"
    echo ""
    echo "  VERIFICACIÓN"
    echo "  10) Resumen SSL (todos los servicios)"
    echo "  11) Verificar integridad de archivo descargado"
    echo ""
    echo "  0) Salir"
    echo "------------------------------------------------------"
    read -rp "  Opción: " opc

    case "$opc" in
    1) instalar_http "apache2" ;;
    2) instalar_http "nginx" ;;
    3) instalar_http "tomcat" ;;
    4) instalar_ftp_linux ;;

    5) generar_certificado ;;
    6) ssl_apache2 ;;
    7) ssl_nginx ;;
    8) ssl_tomcat ;;
    9) ssl_vsftpd ;;

    10) resumen_ssl ;;
    11)
        read -rp "  Ruta del archivo: " arch
        verificar_integridad "$arch"
        ;;
    0)
        echo "  Saliendo..."
        break
        ;;
    *)
        echo "  Opción inválida."
        ;;
    esac
done
