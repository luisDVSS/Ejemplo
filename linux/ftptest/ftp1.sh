source ./ftp2.sh
if ! dpkg -l | grep -q vsftpd;  then
	sudo apt-get install vsftpd
fi

sudo cp /etc/vsftpd.conf /etc/vsftpd.conf.og

choice=""
user=""
##VERIFICAR Y CREAR CARPETA GENERAL Y DE GRUPOS
if [[ ! -d /srv/ftp/General ]] then
	sudo mkdir /srv/ftp/General
	sudo chmod 777 /srv/ftp/General
	sudo mkdir /srv/ftp/Anonymous
	sudo mkdir /srv/ftp/Anonymous/General
	sudo mount --bind /srv/ftp/General /srv/ftp/Anonymous/General
	sudo chmod 755 /srv/ftp/Anonymous/General
fi

grupos

##SELECCION DEL GRUPO

while true; do
echo "1-Agregar Usuario"
echo "2-Salir"
read choice
    if [[ $choice == "1" ]]; then
        while true; do
            echo "Que grupo desea seleccionar \n 1-Reprobados 2-Recursadores"
            read opc

            if [[ $opc == "1" ]]; then
                grupo="Reprobados"
                break 
            elif [[ $opc == "2" ]]; then 
                grupo="Recursadores"
                break 
        
            else
                echo "OPCION NO VALIDA"
            fi
        done


        while true; do
            echo "Ingrese el nombre de usuario"
            read user
            if ! getent passwd "$user" > /dev/null; then
                CrearUsuario $user $grupo
                break
            else    
                echo "USUARIO YA CREADO"
            fi

        done
    elif [[ $choice == "2" ]]; then 
        break
    else
        echo "opcion no valida"
    fi
done
configurar


firewall


