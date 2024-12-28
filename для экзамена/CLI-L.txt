#!/bin/bash

set -e

HOSTNAME="HQ-CLI"
# Задать имя хоста
hostnamectl set-hostname $HOSTNAME

SERVER_IP="172.16.220.6"  # Укажите IP-адрес сервера
PRINTER_NAME="Virtual_PDF_Printer"

#Настройка часового пояса
TIMEZONE="Europe/Moscow"

# Переменные
SERVER_IP="192.168.220.5"  # Укажите IP-адрес NFS-сервера
NFS_L_PATH="/shara-1/nfs-L"  # Путь для офиса 
NFS_R_PATH="/shara-2/nfs-R"  # Путь для офиса 
MOUNT_DIR="/mnt/zz"  # Общая папка для монтирования
CLIENT_NAME=$(hostname)

#файловый сервер
echo "Настройка подключения к файловому серверу"
# Создаем папки для монтирования
echo "Создаем папку $MOUNT_DIR для монтирования"
mkdir -p $MOUNT_DIR

if [[ $CLIENT_NAME == "CLI-L" ]]; then
    TARGET_PATH="$MOUNT_DIR/nfs-L"
    NFS_PATH="$SERVER_IP:$NFS_L_PATH"
elif [[ $CLIENT_NAME == "CLI-R" ]]; then
    TARGET_PATH="$MOUNT_DIR/nfs-R"
    NFS_PATH="$SERVER_IP:$NFS_R_PATH"
else
    echo "Имя хоста ($CLIENT_NAME) не распознано как CLI-L или CLI-R. Проверьте настройки."
    exit 1
fi

# Убедитесь, что nfs-utils установлен
if ! command -v mount.nfs &> /dev/null; then
    echo "Утилита nfs-utils не установлена. Устанавливаем..."
    yum install -y nfs-utils
fi

# Создаем папку для монтирования
echo "Создаем папку $TARGET_PATH"
mkdir -p $TARGET_PATH

# Настраиваем fstab для автоматического монтирования
echo "Настраиваем автоматическое монтирование в /etc/fstab"
echo "$NFS_PATH $TARGET_PATH nfs defaults 0 0" >> /etc/fstab

# Монтируем
echo "Монтируем $NFS_PATH в $TARGET_PATH"
mount -a

# Проверяем монтирование
if mountpoint -q $TARGET_PATH; then
    echo "Монтирование выполнено успешно: $TARGET_PATH"
else
    echo "Ошибка монтирования. Проверьте настройки."
    exit 1
fi

echo "Настройка завершена."

echo "Подключение к принт-серверу $SERVER_IP..."
# Установка клиента CUPS
yum install -y cups-client
# Настройка подключения к принтеру
lpadmin -p "$PRINTER_NAME" -E -v ipp://$SERVER_IP:631/printers/$PRINTER_NAME
lpadmin -d "$PRINTER_NAME"
echo "Принтер $PRINTER_NAME настроен как принтер по умолчанию."

echo "установка chrony"
dnf install chrony
echo "настройка chrony"
timedatectl set-timezone $TIMEZONE
systemctl restart chronyd
systemctl enable --now  chronyd
