#!/bin/bash

HOSTNAME="srv-r.firma.rtk."
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

# Переменные
DISK1="/dev/sdb"
DISK2="/dev/sdc"
RAID_DEVICE="/dev/md0"
MDADM_CONFIG="/etc/mdadm.conf"
MOUNT_DIR="/obmen"
NFS_DIR="/obmen/nfs"
EXPORTS_FILE="/etc/exports"

# Устанавливаем необходимые пакеты
dnf install -y mdadm nfs-utils

# Создаем RAID 1 массив
mdadm --create --verbose $RAID_DEVICE --level=1 --raid-devices=2 $DISK1 $DISK2
if [ $? -ne 0 ]; then
    echo "Ошибка создания RAID массива. Проверьте диски $DISK1 и $DISK2."
    exit 1
fi

# Сохраняем конфигурацию массива в mdadm.conf
mdadm --detail --scan >> $MDADM_CONFIG
# Создаем файловую систему ext4
mkfs.ext4 $RAID_DEVICE
# Создаем точку монтирования и монтируем устройство
mkdir -p $MOUNT_DIR
mount $RAID_DEVICE $MOUNT_DIR
# Обеспечиваем автоматическое монтирование через /etc/fstab
UUID=$(blkid -s UUID -o value $RAID_DEVICE)
echo "UUID=$UUID $MOUNT_DIR ext4 defaults 0 0" >> /etc/fstab
# Настраиваем NFS
mkdir -p $NFS_DIR
chmod 777 $NFS_DIR
# Добавляем запись в /etc/exports
echo "$NFS_DIR *(rw,sync,no_root_squash)" >> $EXPORTS_FILE
# Перезапускаем сервис NFS
systemctl enable nfs-server
systemctl restart nfs-server
# Проверяем статус сервисов
systemctl status nfs-server

echo "Конфигурация завершена. RAID массив смонтирован в $MOUNT_DIR и NFS настроен для $NFS_DIR."

