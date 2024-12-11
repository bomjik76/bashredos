#!/bin/bash

# Задать имя хоста
hostnamectl set-hostname SRV-NFS

# Имя пользователя и пароль
echo "Создание пользователя Server_Admin"
USERNAME="Server_Admin"
PASSWORD="P@ssw0rd"
USER_ID=1010
# Создание пользователя
useradd -m -s /bin/bash -u "$USER_ID" "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
usermod -aG wheel "$USERNAME"
# Настройка sudo без пароля
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
echo "Пользователь $USERNAME создан и настроен для использования sudo без пароля."

# Настройка порта SSH
echo "Настройка порта SSH..."
semanage port -a -t ssh_port_t -p tcp 2020
setenforce 0
sed -i 's/^#Port 22/Port 2020/' /etc/ssh/sshd_config

# Разрешение подключения только пользователю Server_Admin
echo "Ограничение входа только для пользователя Server_Admin..."
sed -i '/^#PermitRootLogin /c\PermitRootLogin no' /etc/ssh/sshd_config
sed -i '/^#AllowUsers /d' /etc/ssh/sshd_config
echo "AllowUsers Server_Admin" >> /etc/ssh/sshd_config

# Ограничение количества попыток входа
echo "Ограничение количества попыток входа..."
sed -i '/^#MaxAuthTries 6 /c\MaxAuthTries 3' /etc/ssh/sshd_config

# Настройка баннера SSH
echo "Настройка SSH баннера..."
BANNER_PATH="/etc/ssh-banner"
echo "Добро пожаловать Server_Admin!" > $BANNER_PATH
sed -i '/^#Banner none /c\Banner '"$BANNER_PATH" /etc/ssh/sshd_config

# Перезапуск службы SSH для применения изменений
echo "Перезапуск службы SSH..."
systemctl restart sshd


# Переменные
DISKS="/dev/sdb /dev/sdc /dev/sdd"  # Укажите устройства ваших дополнительных дисков
MD_DEVICE="/dev/md0"
MD_CONF="/etc/mdadm.conf"
PART1_SIZE="50%"  # Размер первого раздела (50% от массива)
PART2_SIZE="50%"  # Остальное место для второго раздела
MOUNT_DIR1="/shara-1"
MOUNT_DIR2="/shara-2"
EXPORT_FILE="/etc/exports"

# Убедитесь, что mdadm установлен
if ! command -v mdadm &> /dev/null; then
    echo "Утилита mdadm не установлена. Установите её командой: sudo yum install mdadm"
    exit 1
fi

# Создаем RAID 0
echo "Создаем RAID 0 из дисков: $DISKS"
mdadm --create --verbose $MD_DEVICE --level=0 --raid-devices=3 $DISKS

# Сохраняем конфигурацию массива
echo "Сохраняем конфигурацию RAID в $MD_CONF"
mdadm --detail --scan >> $MD_CONF

# Создаем разделы
echo "Создаем разделы на $MD_DEVICE"
parted $MD_DEVICE mklabel gpt
parted $MD_DEVICE mkpart primary ext4 0% $PART1_SIZE
parted $MD_DEVICE mkpart primary ext4 $PART1_SIZE 100%

# Форматируем разделы в ext4
echo "Форматируем разделы в ext4"
mkfs.ext4 ${MD_DEVICE}p1
mkfs.ext4 ${MD_DEVICE}p2

# Создаем папки для монтирования
echo "Создаем папки $MOUNT_DIR1 и $MOUNT_DIR2"
mkdir -p $MOUNT_DIR1
mkdir -p $MOUNT_DIR2

# Настраиваем fstab для автоматического монтирования
echo "Настраиваем fstab для автоматического монтирования"
echo "${MD_DEVICE}p1 $MOUNT_DIR1 ext4 defaults 0 0" >> /etc/fstab
echo "${MD_DEVICE}p2 $MOUNT_DIR2 ext4 defaults 0 0" >> /etc/fstab

# Монтируем разделы
echo "Монтируем разделы"
mount -a

# Установка и настройка NFS
echo "Устанавливаем и настраиваем NFS"
if ! command -v nfs-utils &> /dev/null; then
    yum install -y nfs-utils
fi

# Запускаем и включаем NFS-сервер
systemctl enable nfs-server
systemctl start nfs-server

# Создаем подкаталоги для общего доступа
echo "Создаем подкаталоги /shara-1/nfs-L и /shara-2/nfs-R"
mkdir -p $MOUNT_DIR1/nfs-L
mkdir -p $MOUNT_DIR2/nfs-R

# Настраиваем права доступа
echo "Настраиваем права доступа"
chown -R nobody:nogroup $MOUNT_DIR1/nfs-L
chown -R nobody:nogroup $MOUNT_DIR2/nfs-R
chmod -R 0777 $MOUNT_DIR1/nfs-L
chmod -R 0777 $MOUNT_DIR2/nfs-R

# Настраиваем экспорт NFS
echo "Настраиваем экспорт NFS"
echo "$MOUNT_DIR1/nfs-L 192.168.220.0/27(rw,sync,no_subtree_check)" >> $EXPORT_FILE
echo "$MOUNT_DIR2/nfs-R 172.16.220.0/27(rw,sync,no_subtree_check)" >> $EXPORT_FILE

# Перезапускаем службу NFS
echo "Перезапускаем службу NFS"
exportfs -ra
systemctl restart nfs-server

echo "Конфигурация завершена. RAID 0, разделы и NFS настроены."

echo "установка chrony"
dnf install chrony

echo "настройка chrony"
timedatectl set-timezone Europe/Moscow
sed -i 's/server ntp1.vniiftri.ru iburst/server 172.16.220.1 iburst/' /etc/chrony.conf
sed -i 's/server ntp2.vniiftri.ru iburst/#server ntp2.vniiftri.ru iburst/' /etc/chrony.conf
sed -i 's/server ntp3.vniiftri.ru iburst/#server ntp3.vniiftri.ru iburst/' /etc/chrony.conf
sed -i 's/server ntp4.vniiftri.ru iburst/#server ntp4.vniiftri.ru iburst/' /etc/chrony.conf
systemctl enable --now chronyd
systemctl restart chronyd

# Установка Node Exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.5.0/node_exporter-1.5.0.linux-amd64.tar.gz
tar -xvzf node_exporter-1.5.0.linux-amd64.tar.gz
useradd -rs /bin/false nodeusr
mv node_exporter-1.5.0.linux-amd64/node_exporter /usr/bin/
restorecon -v /usr/bin/node_exporter

# Создание systemd-сервиса для Node Exporter
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
After=network.target
[Service]
User=nodeusr
Group=nodeusr
Type=simple
ExecStart=/usr/bin/node_exporter
[Install]
WantedBy=multi-user.target
EOF

# Запуск и включение Node Exporter
systemctl enable node_exporter --now
systemctl status node_exporter

# Сообщение об успешной установке
echo "Установка Node Exporter завершена."
echo "Node Exporter работает на порту 9100."

# Установка Cockpit
echo "Установка Cockpit..."
sudo yum install -y cockpit

# Запуск и включение Cockpit
echo "Запуск и включение Cockpit..."
sudo systemctl enable cockpit
sudo systemctl start cockpit

# Проверка состояния
echo "Проверка состояния Cockpit..."
sudo systemctl status cockpit

# Открытие порта 9090 в брандмауэре
echo "Открытие порта 9090 в брандмауэре..."
sudo firewall-cmd --permanent --add-port=9090/tcp
sudo firewall-cmd --reload

# Сообщение об успешной установке
echo "Установка Cockpit завершена. Интерфейс доступен по адресу http://<ваш_адрес>:9090"