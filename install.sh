#!/bin/bash

set -e

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Проверка root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Запустите скрипт от root${NC}"
    exit 1
fi

# Получение IP сервера
SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || hostname -I | awk '{print $1}')

# Получение домена
DOMAIN=""
if [ -n "$1" ]; then
    DOMAIN=$1
else
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Установка trojan-go с WebSocket${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${YELLOW}IP вашего сервера: ${SERVER_IP}${NC}"
    echo ""
    echo -e "${YELLOW}Важно: Домен должен указывать на этот IP!${NC}"
    echo ""
    read -p "Введите домен (например, makrelbka.online): " DOMAIN
    echo ""
fi

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Домен не может быть пустым!${NC}"
    exit 1
fi

EMAIL="admin@${DOMAIN}"

echo -e "${GREEN}Начинаю установку trojan-go для домена: ${DOMAIN}${NC}"
echo -e "${YELLOW}Убедитесь, что DNS записи для ${DOMAIN} указывают на IP: ${SERVER_IP}${NC}"
echo ""
read -p "Продолжить установку? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Установка отменена${NC}"
    exit 1
fi

# Обновление системы
echo -e "${YELLOW}Обновление системы...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update
apt upgrade -y

# Установка зависимостей
echo -e "${YELLOW}Установка зависимостей...${NC}"
apt install -y curl wget unzip python3 python3-pip nginx certbot python3-certbot-nginx ufw

# Установка trojan-go
echo -e "${YELLOW}Установка trojan-go...${NC}"
cd /tmp
wget -q https://github.com/p4gefau1t/trojan-go/releases/latest/download/trojan-go-linux-amd64.zip
unzip -q trojan-go-linux-amd64.zip
mv trojan-go /usr/local/bin/
chmod +x /usr/local/bin/trojan-go
rm trojan-go-linux-amd64.zip

# Создание директорий
mkdir -p /usr/local/etc/trojan-go
mkdir -p /var/www/html

# Получение SSL сертификата
echo -e "${YELLOW}Получение SSL сертификата...${NC}"
systemctl stop nginx
certbot certonly --standalone -d ${DOMAIN} -d www.${DOMAIN} --non-interactive --agree-tos --email ${EMAIL}

# Генерация пароля
PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# Создание конфига trojan-go
echo -e "${YELLOW}Создание конфига trojan-go...${NC}"
cat > /usr/local/etc/trojan-go/config.json << EOF
{
    "run_type": "server",
    "local_addr": "127.0.0.1",
    "local_port": 8443,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [
        "${PASSWORD}"
    ],
    "ssl": {
        "cert": "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem",
        "key": "/etc/letsencrypt/live/${DOMAIN}/privkey.pem",
        "sni": "${DOMAIN}",
        "strict_cipher": false
    },
    "websocket": {
        "enabled": true,
        "path": "/ws",
        "host": "${DOMAIN}"
    },
    "router": {
        "enabled": false
    }
}
EOF

# Создание systemd сервиса для trojan-go
echo -e "${YELLOW}Создание systemd сервиса...${NC}"
cat > /etc/systemd/system/trojan-go.service << EOF
[Unit]
Description=trojan-go
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/trojan-go -config /usr/local/etc/trojan-go/config.json
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# Настройка nginx
echo -e "${YELLOW}Настройка nginx...${NC}"
cat > /etc/nginx/sites-available/${DOMAIN} << EOF
# HTTP -> HTTPS редирект
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS сервер
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${DOMAIN} www.${DOMAIN};
    
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;
    
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    location /ws {
        proxy_pass https://127.0.0.1:8443;
        proxy_ssl_verify off;
        proxy_ssl_server_name on;
        proxy_ssl_name ${DOMAIN};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host ${DOMAIN};
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_connect_timeout 86400;
        proxy_buffering off;
    }
    
    location / {
        root /var/www/html;
        index index.html index.htm;
        try_files \$uri \$uri/ =404;
    }
    
    access_log /var/log/nginx/${DOMAIN}.access.log;
    error_log /var/log/nginx/${DOMAIN}.error.log;
}
EOF

# Создание простой HTML страницы
cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>${DOMAIN}</title>
    <meta charset="UTF-8">
</head>
<body>
    <h1>Welcome to ${DOMAIN}</h1>
    <p>Site under construction</p>
</body>
</html>
EOF

# Активация сайта nginx
ln -sf /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Проверка конфига nginx
nginx -t

# Запуск сервисов
echo -e "${YELLOW}Запуск сервисов...${NC}"
systemctl daemon-reload
systemctl enable trojan-go
systemctl start trojan-go
systemctl enable nginx
systemctl start nginx

# Настройка файрвола
echo -e "${YELLOW}Настройка файрвола...${NC}"
ufw --force enable
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp

# Создание скрипта для управления клиентами
echo -e "${YELLOW}Создание скрипта для управления клиентами...${NC}"
cat > /usr/local/bin/trojan-client << SCRIPT_EOF
#!/bin/bash

CONFIG_FILE="/usr/local/etc/trojan-go/config.json"
DOMAIN="${DOMAIN}"
PORT=443

# Функция добавления клиента
add_client() {
    if [ -z "\$1" ]; then
        echo "Использование: \$0 add <пароль>"
        exit 1
    fi
    
    password=\$1
    cp "\$CONFIG_FILE" "\${CONFIG_FILE}.bak.\$(date +%s)"
    
    result=\$(python3 << PYEOF
import json
import sys
try:
    with open('\$CONFIG_FILE', 'r') as f:
        config = json.load(f)
    if '\$password' not in config.get('password', []):
        config.setdefault('password', []).append('\$password')
        with open('\$CONFIG_FILE', 'w') as f:
            json.dump(config, f, indent=4)
        print("OK")
    else:
        print("EXISTS")
        sys.exit(1)
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
PYEOF
)
    
    if [ "\$result" = "OK" ]; then
        systemctl restart trojan-go
        echo "✓ Клиент добавлен"
        echo "trojan://\${password}@\${DOMAIN}:\${PORT}?allowInsecure=1&sni=\${DOMAIN}&type=ws&path=/ws&host=\${DOMAIN}#\${DOMAIN}"
    else
        echo "Ошибка: пароль уже существует"
        exit 1
    fi
}

# Функция удаления клиента
remove_client() {
    if [ -z "\$1" ]; then
        echo "Использование: \$0 remove <пароль>"
        exit 1
    fi
    
    password=\$1
    cp "\$CONFIG_FILE" "\${CONFIG_FILE}.bak.\$(date +%s)"
    
    result=\$(python3 << PYEOF
import json
import sys
try:
    with open('\$CONFIG_FILE', 'r') as f:
        config = json.load(f)
    if 'password' in config and '\$password' in config['password']:
        config['password'].remove('\$password')
        with open('\$CONFIG_FILE', 'w') as f:
            json.dump(config, f, indent=4)
        print("OK")
    else:
        print("NOT_FOUND")
        sys.exit(1)
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
PYEOF
)
    
    if [ "\$result" = "OK" ]; then
        systemctl restart trojan-go
        echo "✓ Клиент удален"
    else
        echo "Ошибка: пароль не найден"
        exit 1
    fi
}

# Функция списка клиентов
list_clients() {
    python3 << PYEOF
import json
try:
    with open('\$CONFIG_FILE', 'r') as f:
        config = json.load(f)
    passwords = config.get('password', [])
    if passwords:
        domain = "\${DOMAIN}"
        port = \${PORT}
        print("Список клиентов:\\n")
        for i, pwd in enumerate(passwords, 1):
            link = f"trojan://{pwd}@{domain}:{port}?allowInsecure=1&sni={domain}&type=ws&path=/ws&host={domain}#{domain}"
            print(f"{i}. Пароль: {pwd}")
            print(f"   Ссылка: {link}\\n")
    else:
        print("Клиенты не найдены")
except Exception as e:
    print(f"Ошибка: {e}")
PYEOF
}

# Главное меню
case "\$1" in
    add)
        add_client "\$2"
        ;;
    remove|del)
        remove_client "\$2"
        ;;
    list|ls)
        list_clients
        ;;
    *)
        echo "Использование: \$0 {add|remove|list} [пароль]"
        echo ""
        echo "Команды:"
        echo "  add <пароль>     - Добавить клиента"
        echo "  remove <пароль>  - Удалить клиента"
        echo "  list             - Список всех клиентов с ссылками"
        echo ""
        echo "Примеры:"
        echo "  \$0 add mypassword123"
        echo "  \$0 remove mypassword123"
        echo "  \$0 list"
        exit 1
        ;;
esac
SCRIPT_EOF

chmod +x /usr/local/bin/trojan-client

# Вывод результата
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Установка завершена!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Домен: ${DOMAIN}"
echo "IP сервера: ${SERVER_IP}"
echo "Пароль первого клиента: ${PASSWORD}"
echo ""
echo "Ссылка для подключения:"
echo "trojan://${PASSWORD}@${DOMAIN}:443?allowInsecure=1&sni=${DOMAIN}&type=ws&path=/ws&host=${DOMAIN}#${DOMAIN}"
echo ""
echo "Управление клиентами:"
echo "  trojan-client add <пароль>     - Добавить клиента"
echo "  trojan-client remove <пароль>  - Удалить клиента"
echo "  trojan-client list             - Список всех клиентов"
echo ""
echo -e "${YELLOW}Важно: Убедитесь, что DNS записи для ${DOMAIN} указывают на IP: ${SERVER_IP}${NC}"
echo ""
