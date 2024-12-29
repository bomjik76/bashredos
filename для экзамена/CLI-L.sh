#!/bin/bash

set -e

HOSTNAME="cli-l.firma.rtk."
# Задать имя хоста
hostnamectl set-hostname $HOSTNAME

#Настройка CUPS
SERVER_IP="172.16.220.6"  # Укажите IP-адрес CUPS
PRINTER_NAME="Virtual_PDF_Printer"

#Настройка часового пояса
TIMEZONE="Europe/Moscow"

# Переменные
NFS_SERVER="192.168.1.1"  # IP адрес сервера NFS
NFS_EXPORT="/obmen/nfs"  # Экспортированная папка на сервере
MOUNT_DIR="/mnt/nfs"     # Точка монтирования на клиенте

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

# Устанавливаем необходимые пакеты
dnf install -y nfs-utils
# Создаем точку монтирования
mkdir -p $MOUNT_DIR
# Добавляем запись в /etc/fstab для автомонтирования
if ! grep -q "$NFS_SERVER:$NFS_EXPORT" /etc/fstab; then
    echo "$NFS_SERVER:$NFS_EXPORT $MOUNT_DIR nfs defaults 0 0" >> /etc/fstab
fi
# Монтируем экспортированную папку
mount -a
# Проверяем статус монтирования
if mountpoint -q $MOUNT_DIR; then
    echo "NFS успешно смонтирован в $MOUNT_DIR."
else
    echo "Ошибка монтирования NFS. Проверьте настройки."
    exit 1
fi

echo "Подключение к принт-серверу $SERVER_IP..."
# Установка клиента CUPS
yum install -y cups-client
# Настройка подключения к принтеру
lpadmin -p "$PRINTER_NAME" -E -v ipp://$SERVER_IP:631/printers/$PRINTER_NAME
lpadmin -d "$PRINTER_NAME"
echo "Принтер $PRINTER_NAME настроен как принтер по умолчанию."

echo "настройка timezone"
timedatectl set-timezone $TIMEZONE

echo "тык тык пошел нахуя яндекс браузер"
dnf install yandex-browser-stable

echo "Настройка завершена."