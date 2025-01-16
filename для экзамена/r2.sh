#!/bin/bash

# Задать имя хоста и часовой пояс
HOSTMAME="r-right.firma.rtk."
hostnamectl set-hostname $HOSTMAME
TIMEZONE="Europe/Moscow"

# Сетевые параметры
INTERFACE_TOISP="enp0s3"
INTERFACE_Right="enp0s8"
IP="22.22.22.1/25"

# Параметры туннеля
LOCAL_IP="172.16.5.2"
REMOTE_IP="172.16.4.2" 
TUNNEL_LOCAL_IP="10.10.10.2/30"
TUNNEL_REMOTE_IP="10.10.10.1"
TUNNEL_NAME="gre-tunnel0"
NETWORK_Left="11.11.11.0/26"
NETWORK_Right="22.22.22.0/25"
NETWORK_TUNNEL="10.10.10.0/30"

# Пользователи
USERNAME="admin"
PASSWORD="P@ssw0rd"
USER_ID="1010"
USERNAMESSH="network_admin"
PASSWORDSSH="P@ssw0rd"
USER1_ID="1030"
PORT="2022"
TIME="5m"
POPITKA="3"

# Настройка сети
nmcli con modify $INTERFACE_Right ipv4.address $IP ipv4.method static
systemctl restart NetworkManager

# Включение IP-форвардинга
echo net.ipv4.ip_forward=1 > /etc/sysctl.conf && sysctl -p

# Настройка nftables
dnf install -y nftables
CONFIG_FILE1="/etc/nftables/r-right.nft"
cat > $CONFIG_FILE1 << EOF
table inet nat {
    chain POSTROUTING {
        type nat hook postrouting priority srcnat;
        oifname $INTERFACE_TOISP masquerade
    }
}
EOF

echo 'include "/etc/nftables/r-right.nft"' >> /etc/sysconfig/nftables.conf
systemctl enable --now nftables

# Создание GRE туннеля
nmcli con add type ip-tunnel ip-tunnel.mode gre con-name $TUNNEL_NAME ifname $TUNNEL_NAME remote $REMOTE_IP local $LOCAL_IP
nmcli con mod $TUNNEL_NAME ipv4.addresses $TUNNEL_LOCAL_IP ipv4.method manual +ipv4.routes "$NETWORK_Left $TUNNEL_REMOTE_IP" ip-tunnel.ttl 64
nmcli con up $TUNNEL_NAME

# Настройка FRR
dnf install -y frr
sed -i 's/ospfd=no/ospfd=yes/; s/ospf6d=no/ospf6d=yes/' /etc/frr/daemons
systemctl enable --now frr

cat > /etc/frr/frr.conf << EOF
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
EOF
systemctl restart frr

# Создание пользователей
useradd -m -s /bin/bash -u "$USER_ID" "$USERNAME" && echo "$USERNAME:$PASSWORD" | chpasswd && usermod -aG wheel "$USERNAME"
useradd -m -s /bin/bash -u "$USER1_ID" "$USERNAMESSH" && echo "$USERNAMESSH:$PASSWORDSSH" | chpasswd && usermod -aG wheel "$USERNAMESSH"
echo "$USERNAMESSH ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAMESSH"

# Настройка SSH
semanage port -a -t ssh_port_t -p tcp $PORT
setenforce 0
echo "Добро пожаловать $USERNAMESSH!" > /etc/ssh-banner
sed -i "20 a Port $PORT\nPermitRootLogin no\nAllowUsers $USERNAMESSH\nMaxAuthTries $POPITKA\nLoginGraceTime $TIME\nBanner /etc/ssh-banner" /etc/ssh/sshd_config
systemctl restart sshd