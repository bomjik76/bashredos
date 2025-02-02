#!/bin/bash

HOSTNAME="br-srv.demo.rtk."
# Задать имя хоста
hostnamectl set-hostname $HOSTNAME

#Настройка часового пояса
TIMEZONE="Asia/Yekaterinburg"

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

echo "Пользователь $USERNAME_SSH создан."

echo "Создание пользователя $USERNAME"
# Создание пользователя
useradd -m -s /bin/bash -u "$USER_ID" "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
usermod -aG wheel "$USERNAME"
echo "Пользователь $USERNAME создан."

echo "настройка timezone"
timedatectl set-timezone $TIMEZONE



echo "Настройка завершена."