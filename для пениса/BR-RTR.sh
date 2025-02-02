#!/bin/bash

HOSTNAME="br-rtr.demo.rtk"

# Задать имя хоста
hostnamectl set-hostname $HOSTNAME

# Настройка часового пояса
TIMEZONE="Asia/Yekaterinburg"

# Настройка сетевых интерфейсов
echo "Настройка сетевых интерфейсов..."
INTERFACE_TOISP="enp0s3"      # Интерфейс в сторону ISP
INTERFACE_Right="enp0s8"  # Интерфейс в сторону офиса Right
IP="172.16.0.1/24"    # задать ip интерфейсу enp0s8

# Параметры туннеля
LOCAL_IP="11.11.0.2"         # Локальный IP-адрес
REMOTE_IP="22.22.22.2"        # Удалённый IP-адрес
TUNNEL_LOCAL_IP="10.10.10.2/30"     # Локальный IP туннеля
TUNNEL_REMOTE_IP="10.10.10.1"    # Удалённый IP туннеля
TUNNEL_NAME="gre-tunnel0"      # Имя туннеля
NETWORK_Left="192.168.1.0/27"
NETWORK_Right="172.16.0.0/24"
NETWORK_2="192.168.2.0/29"
NETWORK_TUNNEL="10.10.10.0/30"

# Создание пользователя net_user
USERNAME="net_user"
PASSWORD="P@$$word"
USER_ID="1030"

# Создание пользователя
useradd -m -s /bin/bash -u "$USER_ID" "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
usermod -aG wheel "$USERNAME"
# Настройка sudo без пароля
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"

# Настройка динамической маршрутизации средствами FRR
dnf install -y frr
sed -i "s/ospfd=no/ospfd=yes/" /etc/frr/daemons
sed -i "s/ospf6d=no/ospf6d=yes/" /etc/frr/daemons
systemctl enable --now frr

# Запись нового содержимого в файл frr.conf
cat <<EOL > /etc/frr/frr.conf
frr version 10.1
frr defaults traditional
hostname $HOSTNAME
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
network $NETWORK_Right area 0
exit
!
EOL
systemctl restart frr

# Включение пересылки пакетов
echo "Включение IP-перенаправления..."
echo net.ipv4.ip_forward=1 > /etc/sysctl.conf
sysctl -p

# Настройка nftables
dnf install -y nftables
echo "Настройка nftables..."
# Создаем файл конфигурации и записываем правила
CONFIG_FILE1="/etc/nftables/r-right.nft"
echo "Создаем файл конфигурации $CONFIG_FILE1..."
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
INCLUDE_LINE='include "/etc/nftables/r-right.nft"'
echo "Добавляем строку '$INCLUDE_LINE' в файл $CONFIG_FILE2..."
if ! grep -Fxq "$INCLUDE_LINE" "$CONFIG_FILE2"; then
    echo "$INCLUDE_LINE" | sudo tee -a "$CONFIG_FILE2"
    echo "Строка добавлена."
else
    echo "Строка уже существует."
fi

# Запускаем и добавляем nftables в автозагрузку
echo "Запуск сервиса nftables и добавление в автозагрузку..."
systemctl enable --now nftables

# Создание GRE туннеля
echo "Создание GRE туннеля..."

nmcli con add type ip-tunnel ip-tunnel.mode gre con-name $TUNNEL_NAME ifname $TUNNEL_NAME \
remote $REMOTE_IP local $LOCAL_IP
nmcli con mod $TUNNEL_NAME ipv4.addresses $TUNNEL_LOCAL_IP
nmcli con mod $TUNNEL_NAME ipv4.method manual
nmcli con mod $TUNNEL_NAME +ipv4.routes "$NETWORK_Left $TUNNEL_REMOTE_IP"
nmcli con mod $TUNNEL_NAME +ipv4.routes "$NETWORK_2 $TUNNEL_REMOTE_IP"
nmcli connection modify $TUNNEL_NAME ip-tunnel.ttl 64
nmcli con up $TUNNEL_NAME

# Вывод информации о туннеле
echo "Туннель успешно настроен. Информация о туннеле:"
ip addr show $TUNNEL_NAME

echo "Настройка timezone"
timedatectl set-timezone $TIMEZONE

echo "Настройка завершена."
