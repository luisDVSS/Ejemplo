#!/usr/bin/env bash
# ============================================================
#  prep_repo.sh  –  Práctica 7
#  Descarga los .deb REALES y genera sus .sha256
#  Ejecutar UNA VEZ en la misma VM antes de correr main.sh
# ============================================================

REPO_BASE="/srv/ftp/repo"
WORK_DIR="/tmp/deb_downloads"

if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Ejecuta como root: sudo bash prep_repo.sh"
    exit 1
fi

echo "======================================================"
echo "  Preparando repositorio FTP para Práctica 7"
echo "======================================================"

# ── Verificar/instalar vsftpd ─────────────────────────────────
if ! dpkg -l vsftpd 2>/dev/null | grep -q "^ii"; then
    echo "  vsftpd no está instalado. Instalando ..."
    apt-get update -q && apt-get install -y vsftpd
else
    echo "  [OK] vsftpd ya está instalado."
fi

# ── Crear usuario repo si no existe ──────────────────────────
echo ""
echo "  Verificando usuario 'repo' ..."
if id "repo" &>/dev/null; then
    echo "  [OK] Usuario repo ya existe."
else
    echo "  Creando usuario repo ..."
    mkdir -p "$REPO_BASE"
    useradd repo -d "$REPO_BASE" -s /bin/false
    echo "  Asigna una contraseña al usuario repo:"
    passwd repo
    echo "  [OK] Usuario repo creado correctamente."
fi

# ── Siempre verificar /bin/false en /etc/shells ───────────────
# (PAM de vsftpd lo requiere para usuarios con shell /bin/false)
if ! grep -q "^/bin/false$" /etc/shells; then
    echo "/bin/false" >>/etc/shells
    echo "  [OK] /bin/false agregado a /etc/shells"
else
    echo "  [OK] /bin/false ya está en /etc/shells"
fi

# ── Siempre verificar repo en chroot_list ────────────────────
# (para que pueda navegar fuera de su directorio home)
if [[ -f /etc/vsftpd.chroot_list ]]; then
    if ! grep -q "^repo$" /etc/vsftpd.chroot_list; then
        echo "repo" >>/etc/vsftpd.chroot_list
        echo "  [OK] repo agregado a vsftpd.chroot_list"
    else
        echo "  [OK] repo ya está en vsftpd.chroot_list"
    fi
else
    echo "repo" >/etc/vsftpd.chroot_list
    echo "  [OK] vsftpd.chroot_list creado con usuario repo"
fi

service vsftpd restart 2>/dev/null
echo "  [OK] vsftpd reiniciado."

# ── Crear estructura de directorios ──────────────────────────
echo ""
echo "  Creando estructura de directorios ..."
for d in \
    "$REPO_BASE/http/Linux/Apache" \
    "$REPO_BASE/http/Linux/Nginx" \
    "$REPO_BASE/http/Linux/Tomcat" \
    "$REPO_BASE/http/Linux/vsftpd"; do
    mkdir -p "$d"
    echo "  [OK] $d"
done

mkdir -p "$WORK_DIR"
cd "$WORK_DIR" || exit 1

apt-get update -q

# ── Función: descargar .deb real y mover al repo ─────────────
descargar_paquete() {
    local paquete="$1"
    local destino_dir="$2"

    echo ""
    echo "  Descargando $paquete ..."

    rm -f ${paquete}_*.deb 2>/dev/null

    apt-get download "$paquete" 2>/dev/null
    local deb
    deb=$(ls ${paquete}_*.deb 2>/dev/null | head -1)

    if [[ -z "$deb" ]]; then
        echo "  [ERROR] No se pudo descargar $paquete"
        return 1
    fi

    rm -f "$destino_dir"/${paquete}_*.deb "$destino_dir"/${paquete}_*.deb.sha256 2>/dev/null
    mv "$deb" "$destino_dir/"

    local archivo_final="$destino_dir/$deb"
    sha256sum "$archivo_final" | awk '{print $1}' >"${archivo_final}.sha256"

    echo "  [OK] $deb"
    echo "  [OK] $deb.sha256  →  $(cat "${archivo_final}.sha256")"
}

descargar_paquete "apache2" "$REPO_BASE/http/Linux/Apache"
descargar_paquete "nginx" "$REPO_BASE/http/Linux/Nginx"

# Tomcat: intentar tomcat10, luego tomcat9 (paquete principal exacto)
TOMCAT_PKG=""
for pkg in tomcat10 tomcat9; do
    if apt-cache show "$pkg" &>/dev/null; then
        TOMCAT_PKG="$pkg"
        break
    fi
done

if [[ -n "$TOMCAT_PKG" ]]; then
    descargar_paquete "$TOMCAT_PKG" "$REPO_BASE/http/Linux/Tomcat"
else
    echo "  [ADVERTENCIA] No se encontró tomcat10 ni tomcat9."
fi

descargar_paquete "vsftpd" "$REPO_BASE/http/Linux/vsftpd"

# ── Permisos para usuario repo ────────────────────────────────
chown -R repo:repo "$REPO_BASE" 2>/dev/null
chmod -R 755 "$REPO_BASE"

echo ""
echo "======================================================"
echo "  Repositorio listo en: $REPO_BASE"
echo "  Archivos:"
find "$REPO_BASE" -type f | sed "s|$REPO_BASE||" | sort | sed 's/^/    /'
echo "======================================================"
