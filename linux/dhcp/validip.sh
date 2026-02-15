#!/bin/bash
valid_ip() {
    local ip="$1"

    # Validar formato general
    if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 1
    fi

    # Separar octetos
    IFS='.' read -r o1 o2 o3 o4 <<<"$ip"

    # Validar rango 0-255 en cada octeto
    for octeto in $o1 $o2 $o3 $o4; do
        if ((octeto < 0 || octeto > 255)); then
            return 1
        fi
    done

    # IPs no permitidas explícitamente
    if [[ "$ip" == "0.0.0.0" ||
        "$ip" == "1.0.0.0" ||
        "$ip" == "127.0.0.0" ||
        "$ip" == "127.0.0.1" ||
        "$ip" == "255.255.255.255" ]]; then
        return 1
    fi

    # Bloquear 0.x.x.x
    if ((o1 == 0)); then
        return 1
    fi

    return 0
}

validar_formato_ip() {
    local ip="$1"

    # Validar estructura básica X.X.X.X
    if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 1
    fi

    # Separar octetos
    IFS='.' read -r o1 o2 o3 o4 <<<"$ip"

    # Validar rango 0-255
    for octeto in "$o1" "$o2" "$o3" "$o4"; do
        if ((octeto < 0 || octeto > 255)); then
            return 1
        fi
    done

    return 0
}
