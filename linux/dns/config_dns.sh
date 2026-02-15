#!/bin/bash
. Funciones.sh
setConfigDns() {
    echo "Configurando dns.."
    while :; do
        read -p "Ingresa el nombre del dominio: " dominio
        if ! isDomName "$dominio"; then
            echo "nombre de dominio no valido"
            continue
        fi

        if grep -qi "zone \"$dominio\"" /etc/bind/named.conf.local; then
            echo "Este dominio ya esta agregado"
            continue
        else
            break
        fi
    done
    while :; do
        read -p "Ingresa la ip: " ip_add
        if ! isHostIp "$ip_add"; then
            echo "Ip no valida"
            continue
        else
            dominio_inverso="$(getZonaInversa "$ip_add")"
            if grep -qi "zone \"$dominio_inverso.in-addr.arpa\"" /etc/bind/named.conf.local; then
                echo "ya se encuentra esta ip"
                continue
            fi
        fi
        break
    done
    setConf_files "$dominio" "$ip_add" "$dominio_inverso"
    resetBind
}

setConf_files() {
    local dominio="$1"
    local ip_add="$2"
    local dominio_inverso="$3"
    #Adicion de las dos zonnas de una, inversa y nombre de dom
    cat <<EOF >>/etc/bind/named.conf.local
zone "$dominio" {
    type master;
    file "/etc/bind/db.$dominio";
};
EOF

    #Adicion de las dos zonnas de una, inversa y nombre de dom
    cat <<EOF >>/etc/bind/named.conf.local
zone "$dominio_inverso.in-addr.arpa" {
    type master;
    file "/etc/bind/db.$dominio_inverso";
};
EOF
    #Registro de dominio
    cat <<EOF >/etc/bind/db."$dominio"
\$TTL 604800
@   IN  SOA ns1.$dominio. admin.$dominio. (
        2         ; Serial
        604800    ; Refresh
        86400     ; Retry
        2419200   ; Expire
        604800 )  ; Negative Cache TTL

@       IN  NS  ns1.$dominio.
@       IN  A   $ip_add
ns1     IN  A   $ip_add
www     IN  A   $ip_add
EOF

    #Registro de dominio inverso
    ultimo_octeto="$(getOcteto "$ip_add" 4)"
    cat <<EOF >/etc/bind/db."$dominio_inverso"
\$TTL 604800
@   IN  SOA ns1.$dominio. admin.$dominio. (
        2         ; Serial
        604800    ; Refresh
        86400     ; Retry
        2419200   ; Expire
        604800 )  ; Negative Cache TTL

@       IN  NS  ns1.$dominio.
$ultimo_octeto     IN  PTR   ns1.$dominio.
EOF

}
