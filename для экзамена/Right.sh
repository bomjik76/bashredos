#!/bin/bash


# Задать имя хоста
HOSTMAME="r-right.firma.rtk."
hostnamectl set-hostname $HOSTMAME

#Настройка часового пояса
TIMEZONE="Europe/Moscow"

# Настройка сетевых интерфейсов
echo "Настройка сетевых интерфейсов..."
INTERFACE_TOISP="enp0s3"      # Интерфейс в сторону ISP
INTERFACE_Right="enp0s8"  # Интерфейс в сторону офиса Right
IP="22.22.22.1/25"    # задать ip интерфейсу enp0s8

# Параметры туннеля
LOCAL_IP="172.16.5.2"         # Локальный IP-адрес
REMOTE_IP="172.16.4.2"        # Удалённый IP-адрес
TUNNEL_LOCAL_IP="10.10.10.2/30"     # Локальный IP туннеля
TUNNEL_REMOTE_IP="10.10.10.1"    # Удалённый IP туннеля
TUNNEL_NAME="gre-tunnel0"      # Имя туннеля
NETWORK_Left="11.11.11.0/26"
NETWORK_Right="22.22.22.0/25"
NETWORK_TUNNEL="10.10.10.0/30"

# admin
USERNAME="admin"
PASSWORD="P@ssw0rd"
USER_ID="1010"

# network_admin
USERNAMESSH="network_admin"
PASSWORDSSH="P@ssw0rd"
USER1_ID="1030"
PORT="2022"
TIME="5m"       #Ограничение по времени
POPITKA="3"     #Ограничение количества попыток входа

# Расчет и назначение IP-адресов
nmcli con modify $INTERFACE_Right ipv4.address $IP
nmcli con modify $INTERFACE_Right ipv4.method static
systemctl restart NetworkManager

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
nmcli connection modify $TUNNEL_NAME ip-tunnel.ttl 64
nmcli con up $TUNNEL_NAME

# Вывод информации о туннеле
echo "Туннель успешно настроен. Информация о туннеле:"
ip addr show $TUNNEL_NAME

#Настройка динамической (внутренней) маршрутизации средствами FRR
echo "Настройка FRR"
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
network $NETWORK_Right area 0
exit
!
EOL
echo "Файл frr.conf успешно обновлен."
systemctl restart frr

# Имя пользователя и пароль
echo "Создание пользователя $USERNAME"
# Создание пользователя
useradd -m -s /bin/bash -u "$USER_ID" "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
usermod -aG wheel "$USERNAME"
echo "Пользователь $USERNAME создан."

# Создание пользователя
echo "Создание пользователя $USERNAMESSH"
useradd -m -s /bin/bash -u "$USER1_ID" "$USERNAMESSH"
echo "$USERNAMESSH:$PASSWORDSSH" | chpasswd
usermod -aG wheel "$USERNAMESSH"
# Настройка sudo без пароля
echo "$USERNAMESSH ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAMESSH"
echo "Пользователь $USERNAMESSH создан и настроен для использования sudo без пароля."

# Настройка порта SSH
echo "Настройка порта SSH..."
semanage port -a -t ssh_port_t -p tcp $PORT
setenforce 0
sed -i "20 a Port $PORT" /etc/ssh/sshd_config
# Разрешение подключения только пользователю $USERNAMESSH
echo "Ограничение входа только для пользователя $USERNAMESSH..."
sed -i "21 a PermitRootLogin no" /etc/ssh/sshd_config
sed -i "22 a AllowUsers $USERNAMESSH" /etc/ssh/sshd_config
# Ограничение количества попыток входа
echo "Ограничение количества попыток входа..."
sed -i "23 a MaxAuthTries $POPITKA" /etc/ssh/sshd_config
# Ограничение по времени аутентификации
sed -i "24 a LoginGraceTime $TIME" /etc/ssh/sshd_config
# Настройка баннера SSH
echo "Настройка SSH баннера..."
BANNER_PATH="/etc/ssh-banner"
echo "Добро пожаловать $USERNAMESSH!" > $BANNER_PATH
sed -i "25 a Banner $BANNER_PATH" /etc/ssh/sshd_config

# Перезапуск службы SSH для применения изменений
echo "Перезапуск службы SSH..."
systemctl restart sshd
echo "Настройка завершена."
