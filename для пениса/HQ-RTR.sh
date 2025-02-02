#!/bin/bash

# Задать имя хоста
HOSTMAME="hq-rtr.demo.rtk."
hostnamectl set-hostname $HOSTMAME

#Настройка часового пояса
TIMEZONE="Asia/Yekaterinburg"

# Настройка сетевых интерфейсов
echo "Настройка сетевых интерфейсов..."
INTERFACE_TOISP="enp0s3"      # Интерфейс в сторону ISP
INTERFACE_Left="enp0s8"  # Интерфейс в сторону HQ-SRV
INTERFACE_Right="enp0s9"  # Интерфейс в сторону HQ-CLI
IP="192.168.1.1/27"    # задать ip интерфейсу enp0s8
IP2="192.168.2.1/29"    # задать ip интерфейсу enp0s9

# Настройка DHCP сервера
dhcp_1="192.168.1.0"    #подсеть
dhcp_2="255.255.255.224"    #маска
dhcp_3="192.168.1.2 192.168.1.30"    #пул адресов
dhcp_4="192.168.1.1"    #путь по умолчанию
dhcp_5="192.168.2.2"    #сервер DNS
domain="demo.rtk"    #DNS

# Параметры туннеля
LOCAL_IP="22.22.22.2"         # Локальный IP-адрес
REMOTE_IP="11.11.0.2"        # Удалённый IP-адрес
TUNNEL_LOCAL_IP="10.10.10.1/30"     # Локальный IP туннеля
TUNNEL_REMOTE_IP="10.10.10.2"    # Удалённый IP туннеля
TUNNEL_NAME="gre-tunnel0"      # Имя туннеля
NETWORK_Left="192.168.1.0/27"
NETWORK_Right="172.16.0.0/24"
NETWORK_2="192.168.2.0/29"
NETWORK_TUNNEL="10.10.10.0/30"

# назначение IP-адресов
nmcli con modify $INTERFACE_Left ipv4.address $IP
nmcli con modify $INTERFACE_Left ipv4.method static
nmcli con modify $INTERFACE_Right ipv4.address $IP2
nmcli con modify $INTERFACE_Right ipv4.method static
systemctl restart NetworkManager

# Включение пересылки пакетов
echo "Включение IP-перенаправления..."
echo net.ipv4.ip_forward=1 > /etc/sysctl.conf
sysctl -p

# Настройка DHCP-сервера
dnf install  dhcp-server -y
echo "Настройка DHCP..."
cat <<EOF > /etc/dhcp/dhcpd.conf
default-lease-time 600;
max-lease-time 7200;


subnet $dhcp_1 netmask $dhcp_2 {
    range $dhcp_3;
    option routers $dhcp_4;
    option domain-name-servers $dhcp_5;
    option domain-name "$domain";
}
EOF
systemctl enable --now dhcpd

# Настройка nftables
dnf install -y nftables
echo "Настройка nftables..."
# Создаем файл конфигурации и записываем правила
CONFIG_FILE1="/etc/nftables/r-left.nft"
echo "Создаем файл конфигурации $CONFIG_FILE..."
touch $CONFIG_FILE1
cat > $CONFIG_FILE1 << 'EOF'
table inet nat {
    chain POSTROUTING {
        type nat hook postrouting priority srcnat;
        oifname masquerade
    }
}
EOF
sed -i "s/oifname /oifname $INTERFACE_TOISP /" $CONFIG_FILE1
# Добавляем строку include в файл /etc/sysconfig/nftables.conf
CONFIG_FILE2="/etc/sysconfig/nftables.conf"
INCLUDE_LINE='include "/etc/nftables/r-left.nft"'
echo "Добавляем строку '$INCLUDE_LINE' в файл $CONFIG_FILE..."
if ! grep -Fxq "$INCLUDE_LINE" "$CONFIG_FILE2"; then
    echo "$INCLUDE_LINE" | sudo tee -a "$CONFIG_FILE2"
    echo "Строка добавлена."
else
    echo "Строка уже существует."
fi

# Запускаем и добавляем nftables в автозагрузку
echo "Запуск сервиса nftables и добавление в автозагрузку..."
systemctl enable --now nftables

# Создание пользователя net_user
USERNAME_NET="net_user"
PASSWORD_NET="P@$$word"
USER_ID="1111"

# Создание пользователя
useradd -m -s /bin/bash -u "$USER_ID" "$USERNAME_NET"
echo "$USERNAME_NET:$PASSWORD_NET" | chpasswd
usermod -aG wheel "$USERNAME_NET"
# Настройка sudo без пароля
echo "$USERNAME_NET ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME_NET"

# Настройка GRE туннеля
nmcli con add type ip-tunnel ip-tunnel.mode gre con-name $TUNNEL_NAME ifname $TUNNEL_NAME \
remote $REMOTE_IP local $LOCAL_IP
nmcli con mod $TUNNEL_NAME ipv4.addresses $TUNNEL_LOCAL_IP
nmcli con mod $TUNNEL_NAME ipv4.method manual
nmcli con mod $TUNNEL_NAME +ipv4.routes "$NETWORK_Right $TUNNEL_REMOTE_IP"
nmcli connection modify $TUNNEL_NAME ip-tunnel.ttl 64
nmcli con up $TUNNEL_NAME

# Настройка динамической маршрутизации средствами FRR
dnf install -y frr
sed -i "s/ospfd=no/ospfd=yes/" /etc/frr/daemons
sed -i "s/ospf6d=no/ospf6d=yes/" /etc/frr/daemons
systemctl enable --now frr

# Запись нового содержимого в файл frr.conf
cat <<EOL > /etc/frr/frr.conf
frr version 10.1
frr defaults traditional
hostname $HOSTMAME
no ipv6 forwarding
!
interface $TUNNEL_NAME
ip ospf authentication
ip ospf authentication-key password
no ip ospf passive
exit
!
router ospf
passive-interface default
network $NETWORK_TUNNEL area 0
network $NETWORK_Left area 0
network $NETWORK_2 area 0
exit
!
EOL
systemctl restart frr

echo "Настройка timezone"
timedatectl set-timezone $TIMEZONE

echo "Настройка завершена."
