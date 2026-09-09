#!/bin/bash
set -e

echo "🚀 Starting multi-site initialization..."

# Создаем все необходимые папки с правильными правами
mkdir -p /run/nginx
chown -R www-data:www-data /run/nginx
chmod -R 755 /run/nginx

mkdir -p /var/run
chown -R www-data:www-data /var/run
chmod -R 755 /var/run

mkdir -p /var/run/supervisor
chown -R www-data:www-data /var/run/supervisor
chmod -R 755 /var/run/supervisor

mkdir -p /var/log/supervisor
chown -R www-data:www-data /var/log/supervisor

mkdir -p /var/lib/nginx/body
chown -R www-data:www-data /var/lib/nginx
chmod -R 755 /var/lib/nginx

mkdir -p /var/log/nginx
chown -R www-data:www-data /var/log/nginx

mkdir -p /var/run/php
chown -R www-data:www-data /var/run/php

# Проверяем папку sites
if [ ! -d "/var/www/html/sites" ]; then
    echo "❌ Directory /var/www/html/sites not found!"
    mkdir -p /var/www/html/sites
fi

echo "📂 Sites directory contents:"
ls -la /var/www/html/sites/

# Перебираем все папки в /var/www/html/sites
for site_dir in /var/www/html/sites/*/; do
    [ -d "$site_dir" ] || continue

    site_name=$(basename "$site_dir")
    echo "📦 Processing site: $site_name"

    if [ -f "$site_dir/.env" ]; then
        echo "✅ Found .env for $site_name"

        if [ ! -f "$site_dir/.initialized" ]; then
            echo "🔧 Initializing $site_name..."

            cd "$site_dir"

            if [ -f "composer.json" ]; then
                echo "📦 Installing composer dependencies..."
                composer install --optimize-autoloader --no-interaction --no-scripts || true
            fi

            if ! grep -q "APP_KEY=" .env || grep -q "APP_KEY=$" .env; then
                echo "🔑 Generating APP_KEY..."
                php artisan key:generate || true
            fi

            if [ ! -L "public/storage" ]; then
                php artisan storage:link || true
            fi

            echo "📊 Running migrations..."
            php artisan migrate --force || true

            php artisan config:clear
            php artisan cache:clear
            php artisan view:clear
            php artisan route:clear

            composer dump-autoload --optimize || true

            touch "$site_dir/.initialized"
        else
            echo "⏭️ $site_name already initialized"
        fi
    else
        echo "❌ No .env found for $site_name, skipping..."
    fi
done

echo "✅ Multi-site initialization completed!"

# Запускаем supervisor
echo "🚀 Starting supervisor..."
exec supervisord -n -c /etc/supervisor/conf.d/supervisord.conf
