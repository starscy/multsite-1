#!/bin/bash
set -e

echo "🚀 Multi-site initialization..."

# Создаём все необходимые папки
mkdir -p /run/nginx /var/run /var/run/supervisor /var/log/supervisor \
         /var/lib/nginx/body /var/log/nginx /var/run/php
chown -R www-data:www-data /run/nginx /var/run /var/run/supervisor \
                            /var/log/supervisor /var/lib/nginx /var/log/nginx /var/run/php
chmod -R 755 /run/nginx /var/run /var/run/supervisor /var/log/supervisor \
              /var/lib/nginx /var/log/nginx /var/run/php

if [ ! -d "/var/www/html/sites" ]; then
    echo "❌ /var/www/html/sites не найден, создаём..."
    mkdir -p /var/www/html/sites
fi

echo "📂 Сайты:"
ls -la /var/www/html/sites/

# Перебираем все сайты
for site_dir in /var/www/html/sites/*/; do
    [ -d "$site_dir" ] || continue

    site_name=$(basename "$site_dir")

    # Пропускаем шаблон (если он есть)
    if [ "$site_name" = "_template" ]; then
        echo "⏭️ Пропускаем шаблон: $site_name"
        continue
    fi

    echo "📦 Обработка: $site_name"

    if [ ! -f "$site_dir/.env" ]; then
        echo "❌ Нет .env для $site_name — пропускаем"
        continue
    fi

    # Если уже инициализирован — пропускаем
    if [ -f "$site_dir/.initialized" ]; then
        echo "⏭️ $site_name уже инициализирован"
        continue
    fi

    echo "🔧 Инициализация $site_name..."
    cd "$site_dir"

    # Composer install (только если vendor отсутствует)
    if [ -f "composer.json" ] && [ ! -d "vendor" ]; then
        echo "📦 Устанавливаем composer..."
        composer install --optimize-autoloader --no-interaction --no-scripts || true
    fi

    # APP_KEY
    if ! grep -q "^APP_KEY=base64:" .env; then
        echo "🔑 Генерируем APP_KEY..."
        php artisan key:generate --force || true
    fi

    # storage:link
    if [ ! -L "public/storage" ]; then
        php artisan storage:link || true
    fi

    # Миграции
    echo "📊 Миграции..."
    php artisan migrate --force || true

    # Кэш
    php artisan config:clear
    php artisan cache:clear
    php artisan view:clear
    php artisan route:clear

    composer dump-autoload --optimize || true

    # Маркер
    touch "$site_dir/.initialized"
    echo "✅ $site_name готов"
done

echo "✅ Все сайты инициализированы"

# Запуск Supervisor
echo "🚀 Запуск Supervisor..."
exec supervisord -n -c /etc/supervisor/conf.d/supervisord.conf
