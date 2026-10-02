#!/bin/bash
# ==========================================
# Создание нового клиентского сайта
# Использование: ./create-client.sh <slug> "<Название>" [sector]
# Пример: ./create-client.sh ulybka "Стоматология Улыбка" medical
# ==========================================

set -e

# --- Аргументы ---
CLIENT_SLUG=$1
CLIENT_NAME=${2:-$1}
CLIENT_SECTOR=${3:-business}

# --- Валидация ---
if [ -z "$CLIENT_SLUG" ]; then
    echo "❌ Использование: ./create-client.sh <slug> \"<Название>\" [sector]"
    echo "   Пример: ./create-client.sh ulybka \"Стоматология Улыбка\" medical"
    exit 1
fi

# --- Пути ---
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITES_DIR="$PROJECT_ROOT/sites"
TEMPLATE="starscy.ru"
CLIENT_DIR="$SITES_DIR/${CLIENT_SLUG}.starscy.ru"
CLIENT_DB="${CLIENT_SLUG}_db"
CLIENT_DOMAIN="${CLIENT_SLUG}.starscy.ru"
SUPERVISOR_CONF="$PROJECT_ROOT/docker/supervisord-worker.conf"

# --- Проверки ---
if [ -d "$CLIENT_DIR" ]; then
    echo "❌ Сайт $CLIENT_DOMAIN уже существует!"
    echo "   Удалить: rm -rf $CLIENT_DIR"
    exit 1
fi

if [ ! -d "$SITES_DIR/$TEMPLATE" ]; then
    echo "❌ Шаблон $TEMPLATE не найден в $SITES_DIR!"
    exit 1
fi

if [ ! -f "$SUPERVISOR_CONF" ]; then
    echo "❌ Файл $SUPERVISOR_CONF не найден!"
    echo "   Создайте его: touch docker/supervisord-worker.conf"
    exit 1
fi

echo "🚀 Создаём сайт для: $CLIENT_NAME"
echo "   Slug:   $CLIENT_SLUG"
echo "   Домен:  $CLIENT_DOMAIN"
echo "   Сфера:  $CLIENT_SECTOR"
echo "   БД:     $CLIENT_DB"
echo ""

# ==========================================
# ШАГ 1: Копирование шаблона
# ==========================================
echo "📦 [1/8] Копируем шаблон..."
cp -r "$SITES_DIR/$TEMPLATE" "$CLIENT_DIR"

# ==========================================
# ШАГ 2: Создание БД
# ==========================================
echo "🗄️  [2/8] Создаём базу данных $CLIENT_DB..."

if docker exec multi_db psql -U laravel -lqt | cut -d \| -f 1 | grep -qw "$CLIENT_DB"; then
    echo "   ⚠️  БД $CLIENT_DB уже существует — пропускаем"
else
    docker exec multi_db psql -U laravel -c "CREATE DATABASE $CLIENT_DB;"
    echo "   ✅ БД создана"
fi

# ==========================================
# ШАГ 3: Настройка .env
# ==========================================
echo "⚙️  [3/8] Настраиваем .env..."
cd "$CLIENT_DIR"

# Основные
sed -i "s|^APP_NAME=.*|APP_NAME=\"${CLIENT_NAME}\"|" .env
sed -i "s|^APP_URL=.*|APP_URL=https://${CLIENT_DOMAIN}|" .env
sed -i "s|^ASSET_URL=.*|ASSET_URL=https://${CLIENT_DOMAIN}|" .env

# БД
sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${CLIENT_DB}|" .env

# Очереди
sed -i "s|^REDIS_QUEUE=.*|REDIS_QUEUE=${CLIENT_SLUG}|" .env
grep -q "^REDIS_QUEUE=" .env || echo "REDIS_QUEUE=${CLIENT_SLUG}" >> .env

# Префикс
sed -i "s|^REDIS_PREFIX=.*|REDIS_PREFIX=${CLIENT_SLUG}_|" .env
grep -q "^REDIS_PREFIX=" .env || echo "REDIS_PREFIX=${CLIENT_SLUG}_" >> .env

# Почта
sed -i "s|^MAIL_FORM_RECIPIENT=.*|MAIL_FORM_RECIPIENT=info@${CLIENT_DOMAIN}|" .env

# Telegram — отключить
sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=|" .env
sed -i "s|^TELEGRAM_CHAT_ID=.*|TELEGRAM_CHAT_ID=|" .env

# ==========================================
# ШАГ 4: Nginx-конфиг
# ==========================================
echo "🌐 [4/8] Создаём Nginx-конфиг..."

cat > "$PROJECT_ROOT/docker/nginx/${CLIENT_DOMAIN}.conf" <<EOF
server {
    listen 80;
    server_name ${CLIENT_DOMAIN} www.${CLIENT_DOMAIN};
    root /var/www/html/sites/${CLIENT_DOMAIN}/public;
    index index.php index.html;

    client_max_body_size 100M;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/json image/svg+xml;

    location ~* \.(jpg|jpeg|png|gif|ico|webp|svg|css|js|woff|woff2|ttf|eot|mp4|webm|zip)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;

        fastcgi_read_timeout 300s;
        fastcgi_send_timeout 300s;
    }

    location ~ /\. {
        deny all;
    }

    location ~ /\.env {
        deny all;
        return 404;
    }
}
EOF

# ==========================================
# ШАГ 5: Инициализация Laravel
# ==========================================
echo "🔑 [5/8] Инициализируем Laravel..."

docker exec multi_app bash -c "cd /var/www/html/sites/${CLIENT_DOMAIN} && php artisan key:generate --force"
docker exec multi_app bash -c "cd /var/www/html/sites/${CLIENT_DOMAIN} && php artisan migrate --force"

# ==========================================
# ШАГ 6: Сиды
# ==========================================
echo "🌱 [6/8] Заполняем базовые данные..."

docker exec multi_app bash -c "cd /var/www/html/sites/${CLIENT_DOMAIN} && php artisan db:seed --force" || {
    echo "   ⚠️  Сидер не отработал — пропускаем"
}

# ==========================================
# ШАГ 7: Воркер в Supervisor
# ==========================================
echo "👷 [7/8] Добавляем воркер..."

if ! grep -q "\[program:worker-${CLIENT_SLUG}\]" "$SUPERVISOR_CONF" 2>/dev/null; then
    cat >> "$SUPERVISOR_CONF" <<EOF

[program:worker-${CLIENT_SLUG}]
command=php /var/www/html/sites/${CLIENT_DOMAIN}/artisan queue:work redis --queue=${CLIENT_SLUG} --sleep=3 --tries=3 --max-time=3600
directory=/var/www/html/sites/${CLIENT_DOMAIN}
autostart=true
autorestart=true
user=www-data
redirect_stderr=true
stdout_logfile=/var/log/supervisor/worker-${CLIENT_SLUG}.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=3
EOF
    echo "   ✅ Воркер добавлен в Supervisor"
else
    echo "   ⚠️  Воркер уже есть"
fi

# ==========================================
# ШАГ 8: Перезапуск сервисов
# ==========================================
echo "🔄 [8/8] Перезапускаем сервисы..."

docker exec multi_app nginx -s reload 2>/dev/null || echo "   ⚠️  Nginx не перезагрузился"

if docker ps --format '{{.Names}}' | grep -q '^multi_worker$'; then
    docker exec multi_worker supervisorctl reread 2>/dev/null || true
    docker exec multi_worker supervisorctl update 2>/dev/null || true
    docker exec multi_worker supervisorctl start worker-${CLIENT_SLUG} 2>/dev/null || true
fi

# ==========================================
# Создаём маркер инициализации
# ==========================================
touch "$CLIENT_DIR/.initialized"

# ==========================================
# ФИНАЛ
# ==========================================
echo ""
echo "✅ Сайт создан: https://${CLIENT_DOMAIN}"
echo ""
echo "📋 Следующие шаги:"
echo "   1. DNS: A-запись ${CLIENT_DOMAIN} → IP сервера"
echo "   2. SSL:  certbot --nginx -d ${CLIENT_DOMAIN}"
echo "   3. Контент: php artisan theme:load --site=${CLIENT_SLUG}"
echo ""
echo "🔐 Админка: https://${CLIENT_DOMAIN}/admin"
echo "   Создать админа:"
echo "   docker exec -it multi_app bash -c \"cd /var/www/html/sites/${CLIENT_DOMAIN} && php artisan make:filament-user\""
echo ""
