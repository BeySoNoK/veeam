#!/bin/bash

# Объединённый скрипт установки Samba и настройки пользователя veeam
# Требует прав root (запускать через sudo)

set -e  # Прерывать выполнение при ошибке

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo "Этот скрипт должен выполняться с правами root (используйте sudo)." 
   exit 1
fi

# Автоматические ответы для iptables-persistent (сохранять правила IPv4 и IPv6)
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections

echo "=== 1. Обновление пакетов ==="
apt update && apt upgrade -y

echo "=== 2. Установка необходимых пакетов ==="
apt install -y mc samba smbclient cifs-utils iptables-persistent

echo "=== 3. Настройка Samba ==="
# Резервное копирование оригинального конфига
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
echo "Резервная копия: /etc/samba/smb.conf.bak"

# Изменяем workgroup на BSN (регистронезависимо)
sed -i 's/^[[:space:]]*workgroup[[:space:]]*=[[:space:]]*WORKGROUP/workgroup = BSN/i' /etc/samba/smb.conf

# Добавляем общую папку [obmen]
cat >> /etc/samba/smb.conf << 'EOF'

[obmen]
    comment = Ubuntu File Server Share
    path = /home/obmen
    guest ok = yes
    browsable = yes
    read only = no
    create mask = 0777
    directory mask = 0777
    force create mode = 0777
    force directory mode = 0777
EOF

# Создаём общую папку и выставляем права
mkdir -p /home/obmen
chown nobody:nogroup /home/obmen
chmod 777 -R /home/obmen

systemctl restart smbd

echo "=== 4. Настройка iptables для Samba ==="
# Добавляем правила, если их ещё нет
iptables -C INPUT -p tcp --dport 445 -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport 445 -j ACCEPT
iptables -C INPUT -p tcp --dport 139 -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport 139 -j ACCEPT
iptables -C INPUT -p udp --dport 137:138 -j ACCEPT 2>/dev/null || iptables -A INPUT -p udp --dport 137:138 -j ACCEPT

echo "=== 5. Сохранение правил iptables ==="
netfilter-persistent save

echo "=== 6. Создание пользователя veeam с заданным паролем ==="
PASSWORD="Asdf1234"  # пароль можно изменить при необходимости
if id "veeam" &>/dev/null; then
    echo "Пользователь veeam уже существует. Пароль будет обновлён."
else
    useradd veeam --create-home -s /bin/bash
fi

echo "veeam:$PASSWORD" | chpasswd
echo "Пароль для veeam установлен: $PASSWORD"

usermod -a -G sudo veeam
echo "Пользователь veeam добавлен в группу sudo."

echo "=== 8. Настройка прав на домашний каталог и создание /home/rs ==="
chown veeam:veeam /home/veeam
chmod 755 /home/veeam

mkdir -p /home/rs
chown veeam:veeam /home/rs
chmod 755 /home/rs

echo "=== Готово! ==="
echo "Samba настроена и запущена. Общая папка доступна по адресу: //<IP-сервера>/obmen"
echo "Пользователь veeam создан (пароль: $PASSWORD) и добавлен в sudo."
echo "Каталоги: /home/veeam и /home/rs созданы с соответствующими правами."
echo "Правила iptables добавлены и сохранены."