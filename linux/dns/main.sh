#!/bin/bash
. Funciones.sh
while :; do
    echo "Selecciona una opcion"
    echo "1) Ver si Bind9 esta intalado"
    echo "2) Instalar Bind9"
    read -r opc
    case "$opc" in
    1)
        if isInstalled bind9 bind9utils bind9-doc; then
            echo "Los servicios de DNS service YA estan intalados."
        else
            echo "Los servicios de DNS NO estan instalado."
        fi

        ;;
    2)
        echo "Validando la instalacion de bind9..."
        if isInstalled bind9 bind9-doc bind9utils; then
            echo "Ya esta intalado"
            read -r -p "¿Deses continuar con la configuracion?"[s/n] cont
            case $cont in
            s)
                echo "Continuando con la configuracion..."
                #llamar setConfig
                ;;
            n)
                echo "saliendo del script.."
                break
                ;;

            esac
            continue
        else
            echo "procediendo con la instalacion de bind9.."
            getService bind9 bind9-doc bind9utils
        fi
        ;;
    *)
        echo "Opcion invalida"
        continue
        ;;

    esac
done
