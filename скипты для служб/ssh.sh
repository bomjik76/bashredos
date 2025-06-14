#!/bin/bash

# Имя пользователя и пароль
USERNAMESSH="server_admin"
PASSWORDSSH="P@ssw0rd"
USER_ID="1010"
PORT="2020"
TIME="6m"       #Ограничение по времени
POPITKA="3"     #Ограничение количества попыток входа

# Создание пользователя
echo "Создание пользователя $USERNAMESSH"
useradd -m -s /bin/bash -u "$USER_ID" "$USERNAMESSH"
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
