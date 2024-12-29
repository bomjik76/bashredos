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

# Имя пользователя и пароль
echo "Создание пользователя $USERNAME"
# Создание пользователя
useradd -m -s /bin/bash -u "$USER_ID" "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
usermod -aG wheel "$USERNAME"
echo "Пользователь $USERNAME создан."

echo "настройка timezone"
timedatectl set-timezone $TIMEZONE

echo "Настройка завершена."