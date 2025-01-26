#!/bin/bash

set -e

HOSTNAME="isp"
# Задать имя хоста
hostnamectl set-hostname $HOSTNAME

# Настройка сетевых интерфейсов
echo "Настройка сетевых интерфейсов..."
INTERFACE_1="enp0s3"      # Интерфейс в сторону магистрального провайдера
INTERFACE_2="enp0s8"  # Интерфейс в сторону офиса Left
INTERFACE_3="enp0s9"  # Интерфейс в сторону офиса Right
IP2="172.16.4.1/28"
IP3="172.16.5.1/28"

#Настройка часового пояса
TIMEZONE="Europe/Moscow"


# Настройка интерфейсов для офисов
nmcli con mod $INTERFACE_2 ipv4.address $IP2
nmcli con mod $INTERFACE_2 ipv4.method manual
nmcli con mod $INTERFACE_3 ipv4.address $IP3
nmcli con mod $INTERFACE_3 ipv4.method manual

# Настройка маршрутов по умолчанию
ip route add default via 172.16.4.1 dev $INTERFACE_2
ip route add default via 172.16.5.1 dev $INTERFACE_3

# Настройка nftables
dnf install -y nftables

# Настройка nftables
echo "Настройка nftables..."

# Создаем файл конфигурации и записываем правила
CONFIG_FILE1="/etc/nftables/isp.nft"
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
sed -i "s/oifname /oifname $INTERFACE_1 /" $CONFIG_FILE1
# Добавляем строку include в файл /etc/sysconfig/nftables.conf
CONFIG_FILE2="/etc/sysconfig/nftables.conf"
INCLUDE_LINE='include "/etc/nftables/isp.nft"'

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

# Включение пересылки пакетов
echo "Включение IP-перенаправления..."
echo net.ipv4.ip_forward=1 > /etc/sysctl.conf
sysctl -p

echo "Настройка timezone"
timedatectl set-timezone $TIMEZONE

echo "Настройка завершена."