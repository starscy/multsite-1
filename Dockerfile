# ==========================================
# ЭТАП 1: Сборка фронтенда (Node.js) - пока отключен
# ==========================================
# FROM node:20-alpine AS frontend

# WORKDIR /var/www/html

# COPY package*.json ./
# RUN npm config set registry https://registry.npmmirror.com
# RUN npm ci

# COPY . .
# RUN npm run build

# ==========================================
# ЭТАП 2: Основной образ (PHP 8.4 + Nginx) НА БАЗЕ DEBIAN
# ==========================================
FROM php:8.4-fpm

# Смена зеркала Debian на Яндекс
RUN sed -i 's/deb.debian.org/mirror.yandex.ru/g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
    sed -i 's/deb.debian.org/mirror.yandex.ru/g' /etc/apt/sources.list

# Установка базовых пакетов
RUN apt-get update && apt-get install -y \
    nginx \
    libpq-dev \
    libonig-dev \
    libzip-dev \
    libicu-dev \
    libssl-dev \
    pkg-config \
    curl \
    unzip \
    supervisor \
    git \
    procps \
    net-tools \
    && docker-php-ext-install -j$(nproc) pdo_pgsql pgsql mbstring zip opcache intl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ==========================================
# NGINX КОНФИГ
# ==========================================
# Удаляем ВСЕ дефолтные конфиги
RUN rm -f /etc/nginx/sites-enabled/default \
    && rm -f /etc/nginx/conf.d/default.conf \
    && rm -f /etc/nginx/sites-available/default

# Копируем наши конфиги
COPY docker/nginx/*.conf /etc/nginx/conf.d/

# ==========================================
# REDIS - ВРЕМЕННО ОТКЛЮЧЕН
# ==========================================
# RUN pecl install redis && docker-php-ext-enable redis

# ==========================================
# МАКСИМАЛЬНЫЕ ЛИМИТЫ ДЛЯ ЗАГРУЗКИ ФАЙЛОВ
# ==========================================
RUN echo "upload_max_filesize = 500M" > /usr/local/etc/php/conf.d/upload.ini \
    && echo "post_max_size = 500M" >> /usr/local/etc/php/conf.d/upload.ini \
    && echo "max_execution_time = 3600" >> /usr/local/etc/php/conf.d/upload.ini \
    && echo "max_input_time = 3600" >> /usr/local/etc/php/conf.d/upload.ini \
    && echo "memory_limit = 1024M" >> /usr/local/etc/php/conf.d/upload.ini \
    && echo "max_file_uploads = 50" >> /usr/local/etc/php/conf.d/upload.ini

# Composer (глобально)
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# ==========================================
# СОЗДАЕМ ВСЕ НЕОБХОДИМЫЕ ПАПКИ С ПРАВИЛЬНЫМИ ПРАВАМИ
# ==========================================
# Папки для Nginx
RUN mkdir -p /run/nginx \
    && chown -R www-data:www-data /run/nginx \
    && chmod -R 755 /run/nginx

RUN mkdir -p /var/lib/nginx/body \
    && chown -R www-data:www-data /var/lib/nginx \
    && chmod -R 755 /var/lib/nginx

RUN mkdir -p /var/log/nginx \
    && chown -R www-data:www-data /var/log/nginx

# Папки для Supervisor
RUN mkdir -p /var/run \
    && chown -R www-data:www-data /var/run \
    && chmod -R 755 /var/run

RUN mkdir -p /var/run/supervisor \
    && chown -R www-data:www-data /var/run/supervisor \
    && chmod -R 755 /var/run/supervisor

RUN mkdir -p /var/log/supervisor \
    && chown -R www-data:www-data /var/log/supervisor

# Папки для PHP
RUN mkdir -p /var/run/php \
    && chown -R www-data:www-data /var/run/php

# Убираем user из основного конфига nginx
RUN sed -i '/^user/d' /etc/nginx/nginx.conf

# ==========================================
# SUPERVISOR КОНФИГ
# ==========================================
RUN mkdir -p /etc/supervisor/conf.d
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# ==========================================
# ENTRYPOINT
# ==========================================
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Проверка конфигов nginx
RUN nginx -t

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
