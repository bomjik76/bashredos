# network_admin
USERNAME="network_admin"
PASSWORD="P@ssw0rd"
USER_ID="1030"


# Имя пользователя и пароль
echo "Создание пользователя $USERNAME"
# Создание пользователя
useradd -m -s /bin/bash -u "$USER_ID" "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
usermod -aG wheel "$USERNAME"
# Настройка sudo без пароля
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
echo "Пользователь $USERNAME создан и настроен для использования sudo без пароля."