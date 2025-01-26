#!/bin/bash

set -e

HOSTNAME="srv-r.firma.rtk."
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

echo "Пользователь $USERNAME_SSH создан."

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

# Переменные Cups
CUPS_CONF="/etc/cups/cupsd.conf"
PDF_PRINTER_NAME="Virtual_PDF_Printer"

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

#CUPS
# Установка необходимых пакетов
echo "Устанавливаем CUPS и необходимые модули..."
yum install -y cups cups-pdf || {
    echo "Ошибка: Не удалось установить пакеты. Проверьте подключение к репозиторию." >&2
    exit 1
}
# Запуск службы CUPS
echo "Запускаем службу CUPS..."
systemctl enable cups
systemctl start cups
# Настройка виртуального PDF-принтера
echo "Настраиваем виртуальный PDF-принтер..."
lpadmin -p "$PDF_PRINTER_NAME" -E -v cups-pdf:/ -m drv:///sample.drv/generic.ppd || {
    echo "Ошибка: Не удалось добавить принтер." >&2
    exit 1
}
lpadmin -d "$PDF_PRINTER_NAME"
echo "Принтер $PDF_PRINTER_NAME успешно добавлен."
# Настройка веб-интерфейса и удаленного администрирования
echo "Настраиваем веб-интерфейс и удаленное администрирование..."
if grep -q "^Port 631" "$CUPS_CONF"; then
    echo "Веб-интерфейс уже настроен."
else
    sed -i 's/^Listen localhost:631/Port 631/' "$CUPS_CONF" || {
    echo "Ошибка: Не удалось изменить $CUPS_CONF." >&2
    exit 1
}
fi
sed -i 's/<Location \/>/<Location \/>\n  Allow All\n/g' $CUPS_CONF
sed -i 's/<Location \/admin>/<Location \/admin>\n  Allow All\n/g' $CUPS_CONF
sed -i 's/<Location \/admin\/log>/<Location \/admin\/log>\n  Allow All\n/g' $CUPS_CONF
sed -i 's/<Location \/admin\/conf>/<Location \/admin\/conf>\n  Allow All\n/g' $CUPS_CONF
# Перезапуск службы CUPS
echo "Перезапускаем службу CUPS для применения изменений..."
systemctl restart cups
# Проверка статуса
systemctl status cups --no-pager
if [ $? -eq 0 ]; then
    echo "CUPS успешно настроен и запущен."
    echo "Веб-интерфейс доступен по адресу: http://<IP-адрес-сервера>:631"
else
    echo "Ошибка: Не удалось запустить CUPS." >&2
    exit 1
fi

echo "Настройка завершена."