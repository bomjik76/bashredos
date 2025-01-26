#!/bin/bash

set -e

HOSTNAME="srv-l.firma.rtk."
# Задать имя хоста
hostnamectl set-hostname $HOSTNAME

#Настройка часового пояса
TIMEZONE="Europe/Moscow"

# admin
USERNAME="admin"
PASSWORD="P@ssw0rd"
USER_ID="1010"

# Создание пользователя ssh_user
USERNAME_SSH="ssh_user"
PASSWORD_SSH="P@ssw0rd"
USER_ID_SSH="1030"

# Создание пользователя
useradd -m -s /bin/bash -u "$USER_ID_SSH" "$USERNAME_SSH"
echo "$USERNAME_SSH:$PASSWORD_SSH" | chpasswd
usermod -aG wheel "$USERNAME_SSH"
# Настройка sudo без пароля
echo "$USERNAME_SSH ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME_SSH"

# Настройка безопасного удаленного доступа
PORT_SSH=2222
POPITKA=3
BANNER_PATH="/etc/ssh-banner"
echo "Authorized access only" > $BANNER_PATH

# Настройка порта SSH
semanage port -a -t ssh_port_t -p tcp $PORT_SSH
setenforce 0
sed -i "20 a Port $PORT_SSH" /etc/ssh/sshd_config
# Разрешение подключения только пользователю $USERNAME_SSH
sed -i "21 a PermitRootLogin no" /etc/ssh/sshd_config
sed -i "22 a AllowUsers $USERNAME_SSH" /etc/ssh/sshd_config
# Ограничение количества попыток входа
sed -i "23 a MaxAuthTries $POPITKA" /etc/ssh/sshd_config
# Настройка баннера SSH
sed -i "24 a Banner $BANNER_PATH" /etc/ssh/sshd_config

# Перезапуск службы SSH для применения изменений
systemctl restart sshd

echo "Создание пользователя $USERNAME"
# Создание пользователя
useradd -m -s /bin/bash -u "$USER_ID" "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
usermod -aG wheel "$USERNAME"
echo "Пользователь $USERNAME создан."

echo "настройка timezone"
timedatectl set-timezone $TIMEZONE

echo "Настройка завершена."

# Установка и настройка BIND

dnf install -y bind bind-utils

# Настройка файла named.conf
cat <<EOL > /etc/named.conf
options {
    directory "/var/named";
    forwarders {
        77.88.8.8; // Primary IPv4 DNS Яндекса
    };
    allow-query { any; };
};

zone "demo.rtk" IN {
    type master;
    file "/var/named/demo.rtk.zone";
};

zone "11.11.11.in-addr.arpa" IN {
    type master;
    file "/var/named/11.11.11.zone";
};
EOL

# Настройка зоны прямого разрешения
cat <<EOL > /var/named/demo.rtk.zone
$TTL 86400
@   IN  SOA hq-srv.demo.rtk. root.demo.rtk. (
        2023101001 ; Serial
        3600       ; Refresh
        1800       ; Retry
        604800     ; Expire
        86400 )    ; Minimum

    IN  NS  hq-srv.demo.rtk.
hq-rtr  IN  A   11.11.11.1
br-rtr  IN  A   11.11.11.2
hq-srv  IN  A   11.11.11.3
hq-cli  IN  A   11.11.11.4
br-srv  IN  A   11.11.11.5
cloud   IN  CNAME hq-rtr.demo.rtk.
doc     IN  CNAME hq-rtr.demo.rtk.
EOL

# Настройка зоны обратного разрешения
cat <<EOL > /var/named/11.11.11.zone
$TTL 86400
@   IN  SOA hq-srv.demo.rtk. root.demo.rtk. (
        2023101001 ; Serial
        3600       ; Refresh
        1800       ; Retry
        604800     ; Expire
        86400 )    ; Minimum

    IN  NS  hq-srv.demo.rtk.
1   IN  PTR hq-rtr.demo.rtk.
2   IN  PTR br-rtr.demo.rtk.
3   IN  PTR hq-srv.demo.rtk.
4   IN  PTR hq-cli.demo.rtk.
5   IN  PTR br-srv.demo.rtk.
EOL

# Запуск и добавление BIND в автозагрузку
systemctl enable --now named