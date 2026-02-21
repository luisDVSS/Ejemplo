#!/usr/bin/env bash
source ./funciones_ssh.sh
if ! isRoot; then
    echo "[OJITO] Debes ejectuar este script en modo ROOT"
    exit 1
fi
echo "Script de configuracion de SSH"
if ! validacion_servicio openssh-client; then
    if getService openssh-client; then
        systemctl enable ssh
        systemctl start ssh
    fi
fi
conecTo luisd 192.168.99.10
