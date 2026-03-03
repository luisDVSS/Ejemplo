function IngresarIP() {
  IP=""
  Reg="^((25[0-5])|(2[0-4][0-9])|(1[0-9]{2})|([0]?[0-9]?[0-9]))\.((25[0-5])|(2[0-4][0-9])|(1[0-9]{2})|([0]?[0-9]?[0-9]))\.((25[0-5])|(2[0-4][0-9])|(1[0-9]{2})|([0]?[0-9]?[0-9]))\.((25[0-5])|(2[0-4][0-9])|(1[0-9]{2})|([0]?[0-9]?[0-9]))$"

  romper="True"
  while [[ $romper == "True" ]]; do
    #Ingrese IP
    read IP
    if [[ $IP =~ $Reg ]]; then
      romper="False"
    fi
  done
  echo "${IP}"

}

function Ingresarprefijo() {
  val="false"
  while [[ $val == "false" ]]; do
    #"Ingrese el prefijo de la mascara(24/16/8)"
    read prefijo
    if [[ $prefijo == "24" || $prefijo == "16" || $prefijo == "8" ]]; then
      val="True"
    fi
  done
  echo "$prefijo"
}

function CrearGateway() {
  if [[ $2 == "24" ]]; then
    IPgateway="$3.$4.$5.1"

  elif [[ $2 == "16" ]]; then
    IPgateway="$3.$4.0.1"
  elif [[ $2 == "8" ]]; then
    IPgateway="$3.0.0.1"
  fi
  echo "$IPgateway"
}

function EstablecerIp() {
  echo $1
  echo $2
  echo $3

  sudo tee /etc/netplan/50-cloud-init.yaml >/dev/null <<EOL
network:
    ethernets:
        enp0s3:
            dhcp4: false
            addresses:
              - $2/$1
            routes:
              - to: default
                via: $3
            nameservers:
              addresses:
                - $2
                - 8.8.8.8
    version: 2
EOL

  sudo netplan apply

}

function configurar() {
  sudo tee /etc/vsftpd.conf >/dev/null <<EOL
listen=NO
listen_ipv6=YES
anonymous_enable=YES
anon_root=/srv/ftp/Anonymous
anon_mkdir_write_enable=NO
anon_other_write_enable=NO
no_anon_password=YES
local_enable=YES
write_enable=YES
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
chroot_list_enable=YES
chroot_list_file=/etc/vsftpd.chroot_list
allow_writeable_chroot=YES
user_sub_token=\$USER
local_root=/srv/ftp/\$USER
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
rsa_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
rsa_private_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
ssl_enable=NO


EOL

  sudo mkdir /etc/vsftpd.chroot_list
  sudo tee /etc/vsftpd.chroot_list >/dev/null <<EOL
luvbeen
root
EOL

  sudo service vsftpd restart

}

function firewall() {
  ##FIREWALL
  if sudo ufw status | grep -q "Status: inactive"; then
    sudo ufw enable

    ##ACtivando puertos 20 21 ftp
    sudo ufw allow 20/tcp
    sudo ufw allow 21/tcp
    sudo ufw allow 22/tcp #SSH
    sudo ufw allow 990/tcp

    sudo ufw allow 40000:50000/tcp #PUERTOS PASIVOS
  fi

}

function grupos() {
  ###CREACION DE GRUPOS
  if ! getent group "Reprobaods" >/dev/null; then
    sudo groupadd Reprobados
  fi

  if ! getent group "Recursadores" >/dev/null; then
    sudo groupadd Recursadores
  fi
  if [[ ! -d /srv/ftp/reprobados ]]; then
    sudo mkdir /srv/ftp/Reprobados
    sudo chown :Reprobados /srv/ftp/Reprobados
    sudo chmod 777 /srv/ftp/Reprobados
  fi
  if [[ ! -d /srv/ftp/recursadores ]]; then
    sudo mkdir /srv/ftp/Recursadores
    sudo chown :Recursadores /srv/ftp/Recursadores
    sudo chmod 777 /srv/ftp/Recursadores
  fi
}

function CrearUsuario() {
  sudo useradd $user -d /srv/ftp
  sudo usermod -a -G $grupo $user
  sudo mkdir /srv/ftp/$user
  sudo chown $user:$user /srv/ftp/$user
  sudo mkdir /srv/ftp/$user/$user
  sudo chown $user:$user /srv/ftp/$user/$user
  sudo chmod 700 /srv/ftp/$user
  sudo passwd $user
  sudo mkdir -p /srv/ftp/$user/General
  sudo mount --bind /srv/ftp/General /srv/ftp/$user/General
  sudo chmod 777 /srv/ftp/$user/General
  sudo mkdir -p /srv/ftp/$user/$grupo
  sudo mount --bind /srv/ftp/$grupo /srv/ftp/$user/$grupo
  sudo chmod 777 /srv/ftp/$user/$grupo

}
