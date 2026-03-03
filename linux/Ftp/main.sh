#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib_func.sh"
source "$SCRIPT_DIR/ftp_funciones.sh"
registrarUsuarios() {
	echo "Configurando vsftpd.conf...."
	setFtpConf
	echo "Creando grupos..."
	if [[ ! -d /srv/ftp/General ]]; then
		sudo mkdir /srv/ftp/General
		sudo chmod 777 /srv/ftp/General
		sudo mkdir /srv/ftp/Anonymous
		sudo mkdir /srv/ftp/Anonymous/General
		sudo mount --bind /srv/ftp/General /srv/ftp/Anonymous/General
		sudo chmod 755 /srv/ftp/Anonymous/General
	fi
	setGrupos
	#validacion la existencia de los grupos

	read -p "Cuantos usuarios registraras" num_users
	for ((i = 1; i <= num_users; i++)); do

		while :; do
			read -p "Ingresa nombre del usuario: $i" user
			if id "$user" &>/dev/null; then
				echo "ese nombre: $user ya existe."
			else
				break
			fi
		done

		while :; do
			read -p "¿A que grupo pertenece? Reprobados=1 || Recursadores=2" gpo
			if [[ "$gpo" == "1" ]]; then
				crearUser "$user" Reprobados
				break
			else
				if [[ "$gpo" == "2" ]]; then
					crearUser "$user" Recursadores
					break
				else
					echo "opcion invalida"
					continue
				fi
			fi
		done
	done

}

#setFtpConfiguration() {
#}
while :; do
	echo "Menu de Ftp"
	echo "---------------"
	echo "1) Ver estado del servicio FTP"
	echo "2) Instalar 'vsftpd'"
	echo "3) Registrar usuarios"
	echo "4) Cambiar de grupo un usuario"
	echo "0) Salir"
	read opc

	case "$opc" in
	1)
		isInstalled vsftpd
		;;
	2)
		if ! isInstalled vsftpd; then
			read -p "Quieres proceder con la instalacion?[s/n]" opcInst
			while :; do
				case "$opcInst" in
				s)

					echo "Procediendo con la instalacion..."
					if getService vsftpd; then
						echo "Instalacion exitosa"
						sudo cp /etc/vsftpd.conf /etc/vsftpd.conf.og
						break
					else
						echo "Hubo un fallo en la instalacion"
					fi
					;;
				n)
					echo "No se instalara vsftpd..."
					break
					;;

				esac
			done
		fi
		;;
	3)
		echo "--------Modulo de registro de usuarios----------"
		registrarUsuarios
		;;
	4)
		echo "------Cambio de grupo de un usuario------"
		read -p "Ingresa el nombre del usuario" usu
		cambiarGrupo "$usu"

		;;
	0)
		echo "saliendo.."
		break
		;;
	*)
		echo "Opcion Invalida"

		;;

	esac
done
