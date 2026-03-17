#!/usr/bin/env bash
# ============================================================
#  ssl_funciones.sh  –  Práctica 7
#  Generación y configuración de SSL/TLS para:
#    HTTP : Apache2, Nginx, Tomcat
#    FTP  : vsftpd  (FTPS)
# ============================================================

DOMAIN="reprobados.com"
CERT_DIR="/etc/ssl/reprobados"
CERT_FILE="$CERT_DIR/reprobados.crt"
KEY_FILE="$CERT_DIR/reprobados.key"

# ── Generar certificado autofirmado (compartido) ─────────────
generar_certificado() {
    echo ""
    echo "[SSL] Generando certificado autofirmado para $DOMAIN ..."
    sudo mkdir -p "$CERT_DIR"

    sudo openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE" \
        -subj "/C=MX/ST=Sinaloa/L=LosMochis/O=Reprobados/CN=$DOMAIN" \
        2>/dev/null

    if [[ $? -eq 0 ]]; then
        echo "[OK] Certificado generado:"
        echo "     CRT : $CERT_FILE"
        echo "     KEY : $KEY_FILE"
    else
        echo "[ERROR] Falló la generación del certificado."
        return 1
    fi
}

# ── Apache2 SSL ───────────────────────────────────────────────
ssl_apache2() {
    echo ""
    echo "[SSL] Configurando SSL en Apache2 ..."

    sudo a2enmod ssl rewrite >/dev/null 2>&1

    # VirtualHost HTTPS
    sudo tee /etc/apache2/sites-available/reprobados-ssl.conf >/dev/null <<EOF
<VirtualHost *:443>
    ServerName $DOMAIN
    DocumentRoot /var/www/apache2

    SSLEngine on
    SSLCertificateFile    $CERT_FILE
    SSLCertificateKeyFile $KEY_FILE

    <Directory /var/www/apache2>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

    # Redirección HTTP → HTTPS en el VirtualHost por defecto
    local default_conf="/etc/apache2/sites-available/000-default.conf"
    if ! grep -q "Redirect" "$default_conf" 2>/dev/null; then
        sudo sed -i '/<\/VirtualHost>/i \    Redirect permanent / https://'"$DOMAIN"'/' "$default_conf"
    fi

    sudo a2ensite reprobados-ssl.conf >/dev/null 2>&1

    # Asegurar que el puerto 443 esté en ports.conf
    if ! grep -q "Listen 443" /etc/apache2/ports.conf; then
        echo "Listen 443" | sudo tee -a /etc/apache2/ports.conf >/dev/null
    fi

    sudo systemctl restart apache2
    echo "[OK] Apache2 SSL activo en puerto 443."
}

# ── Nginx SSL ─────────────────────────────────────────────────
ssl_nginx() {
    echo ""
    echo "[SSL] Configurando SSL en Nginx (puerto 444) ..."

    # Deshabilitar config default para evitar conflicto con Apache2
    sudo rm -f /etc/nginx/sites-enabled/default 2>/dev/null

    sudo tee /etc/nginx/sites-available/reprobados-ssl >/dev/null <<EOF
server {
    listen 444 ssl;
    server_name $DOMAIN;
    root /var/www/nginx;

    ssl_certificate     $CERT_FILE;
    ssl_certificate_key $KEY_FILE;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    add_header Strict-Transport-Security "max-age=31536000" always;

    location / {
        index index.html;
    }
}

server {
    listen 8080;
    server_name $DOMAIN;
    return 301 https://\$host:444\$request_uri;
}
EOF

    sudo ln -sf /etc/nginx/sites-available/reprobados-ssl \
        /etc/nginx/sites-enabled/reprobados-ssl 2>/dev/null

    sudo systemctl restart nginx
    echo "[OK] Nginx SSL activo en puerto 444."
}

# ── Tomcat SSL ────────────────────────────────────────────────
ssl_tomcat() {
    echo ""
    echo "[SSL] Configurando SSL en Tomcat ..."

    local p12="$CERT_DIR/reprobados.p12"
    local pass="reprobados123"

    sudo openssl pkcs12 -export \
        -in "$CERT_FILE" \
        -inkey "$KEY_FILE" \
        -out "$p12" \
        -name reprobados \
        -passout pass:"$pass" 2>/dev/null

    local server_xml
    server_xml=$(find /etc/tomcat* /opt/tomcat* -name "server.xml" 2>/dev/null | head -1)

    if [[ -z "$server_xml" ]]; then
        echo "[ERROR] No se encontró server.xml de Tomcat."
        return 1
    fi

    sudo cp "$server_xml" "${server_xml}.bak"
    echo "  Backup: ${server_xml}.bak"

    # Eliminar bloque comentado del conector 8443 default y agregar el nuestro
    sudo python3 <<PYEOF
import re

server_xml = "$server_xml"
p12        = "$p12"
passwd     = "$pass"

with open(server_xml, 'r') as f:
    content = f.read()

# Eliminar bloque de comentario que contiene la config SSL default
content = re.sub(r'<!--\s*Define an SSL.*?-->', '', content, flags=re.DOTALL)

new_connector = """
    <!-- Conector SSL Practica 7 -->
    <Connector port="8443"
               protocol="org.apache.coyote.http11.Http11NioProtocol"
               maxThreads="150" SSLEnabled="true"
               maxParameterCount="1000">
        <SSLHostConfig>
            <Certificate certificateKeystoreFile="{p12}"
                         certificateKeystorePassword="{passwd}"
                         type="RSA" />
        </SSLHostConfig>
    </Connector>
""".format(p12=p12, passwd=passwd)

if 'Conector SSL Practica 7' not in content:
    content = content.replace('</Service>', new_connector + '\n</Service>')

with open(server_xml, 'w') as f:
    f.write(content)

print("[OK] server.xml modificado: " + server_xml)
PYEOF

    local tomcat_user
    tomcat_user=$(ps aux | grep -i tomcat | grep -v grep | awk '{print $1}' | head -1)
    [[ -z "$tomcat_user" ]] && tomcat_user="tomcat"
    sudo chown "$tomcat_user" "$p12" 2>/dev/null
    sudo chmod 640 "$p12" 2>/dev/null

    local svc
    svc=$(systemctl list-units --type=service 2>/dev/null | grep -i tomcat | awk '{print $1}' | head -1)
    if [[ -n "$svc" ]]; then
        sudo systemctl restart "$svc"
        sleep 3
        if systemctl is-active --quiet "$svc"; then
            echo "[OK] Tomcat SSL activo en puerto 8443."
        else
            echo "[ERROR] Tomcat no arrancó. Revisa: journalctl -u $svc"
        fi
    fi
}

# ── vsftpd FTPS ───────────────────────────────────────────────
ssl_vsftpd() {
    echo ""
    echo "[SSL] Configurando FTPS en vsftpd ..."

    # Añadir/reemplazar bloque SSL en vsftpd.conf
    sudo sed -i 's/ssl_enable=NO/ssl_enable=YES/' /etc/vsftpd.conf

    # Eliminar líneas SSL previas para no duplicar
    sudo sed -i '/^rsa_cert_file/d;/^rsa_private_key_file/d;/^ssl_tlsv1/d;/^ssl_sslv2/d;/^ssl_sslv3/d;/^force_local_data_ssl/d;/^force_local_logins_ssl/d;/^require_ssl_reuse/d;/^ssl_ciphers/d' /etc/vsftpd.conf

    sudo tee -a /etc/vsftpd.conf >/dev/null <<EOF

# ── SSL/TLS (Práctica 7) ──────────────────────────────────────
ssl_enable=YES
rsa_cert_file=$CERT_FILE
rsa_private_key_file=$KEY_FILE
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
force_local_data_ssl=YES
force_local_logins_ssl=YES
require_ssl_reuse=NO
ssl_ciphers=HIGH
EOF

    sudo service vsftpd restart
    echo "[OK] vsftpd FTPS activo (canal de control y datos cifrados)."
}

# ── Verificación de un servicio ───────────────────────────────
verificar_ssl() {
    local servicio="$1"
    local host="${2:-127.0.0.1}"
    local puerto="$3"

    echo ""
    echo "--- Verificando SSL: $servicio (puerto $puerto) ---"

    local resultado
    resultado=$(echo | sudo openssl s_client -connect "$host:$puerto" \
        -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null)

    if [[ -n "$resultado" ]]; then
        echo "[OK] $servicio responde con certificado SSL:"
        echo "$resultado" | sed 's/^/     /'
        return 0
    else
        echo "[FAIL] $servicio NO responde por SSL en puerto $puerto."
        return 1
    fi
}

# ── Resumen global SSL ────────────────────────────────────────
resumen_ssl() {
    echo ""
    echo "======================================================"
    echo "           RESUMEN DE VERIFICACIÓN SSL/TLS            "
    echo "======================================================"

    local pass=0 fail=0

    _chk() {
        local nombre="$1" puerto="$2"
        if verificar_ssl "$nombre" "127.0.0.1" "$puerto" >/dev/null 2>&1; then
            printf "  %-20s puerto %-6s  [OK]\n" "$nombre" "$puerto"
            ((pass++))
        else
            printf "  %-20s puerto %-6s  [FAIL]\n" "$nombre" "$puerto"
            ((fail++))
        fi
    }

    systemctl is-active --quiet apache2 && _chk "Apache2" 443
    systemctl is-active --quiet nginx && _chk "Nginx" 443
    systemctl is-active --quiet tomcat* 2>/dev/null ||
        systemctl is-active --quiet tomcat9 2>/dev/null ||
        systemctl is-active --quiet tomcat10 2>/dev/null && _chk "Tomcat" 8443
    systemctl is-active --quiet vsftpd && _chk "vsftpd (FTPS)" 21

    echo "------------------------------------------------------"
    echo "  Exitosos : $pass   Fallidos : $fail"
    echo "======================================================"
}
