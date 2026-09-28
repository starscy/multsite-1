# ==========================================
# ЭТАП 1: Сборка фронтенда (Node.js) - пока отключен
# ==========================================
# FROM node:20-alpine AS frontend
# ...

# ==========================================
# ЭТАП 2: Основной образ (PHP 8.4 + Nginx) НА БАЗЕ DEBIAN
# ==========================================
FROM php:8.4-fpm

# Смена зеркала Debian на Яндекс
RUN sed -i 's/deb.debian.org/mirror.yandex.ru/g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
    sed -i 's/deb.debian.org/mirror.yandex.ru/g' /etc/apt/sources.list

# Установка базовых пакетов + gd + exif
RUN apt-get update && apt-get install -y \
    nginx \
    libpq-dev \
    libonig-dev \
    libzip-dev \
    libicu-dev \
    libssl-dev \
    libpng-dev \
    libjpeg62-turbo-dev \
    libfreetype6-dev \
    libwebp-dev \
    pkg-config \
    curl \
    unzip \
    supervisor \
    git \
    procps \
    net-tools \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) pdo_pgsql pgsql mbstring zip opcache intl gd exif \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ==========================================
# REDIS РАСШИРЕНИЕ (через GitHub, не PECL)
# ==========================================
RUN cd /tmp \
    && curl -L -o redis.tar.gz https://github.com/phpredis/phpredis/archive/refs/tags/6.1.0.tar.gz \
    && tar -xzf redis.tar.gz \
    && cd phpredis-6.1.0 \
    && phpize \
    && ./configure \
    && make -j$(nproc) \
    && make install \
    && docker-php-ext-enable redis \
    && rm -rf /tmp/redis.tar.gz /tmp/phpredis-6.1.0

# ==========================================
# NGINX КОНФИГ
# ==========================================
RUN rm -f /etc/nginx/sites-enabled/default \
    && rm -f /etc/nginx/conf.d/default.conf \
    && rm -f /etc/nginx/sites-available/default

COPY docker/nginx/*.conf /etc/nginx/conf.d/

# ==========================================
# МАКСИМАЛЬНЫЕ ЛИМИТЫ ДЛЯ ЗАГРУЗКИ ФАЙЛОВ
# ==========================================
RUN echo "upload_max_filesize = 500M" > /usr/local/etc/php/conf.d/upload.ini \
    && echo "post_max_size = 500M" >> /usr/local/etc/php/conf.d/upload.ini \
    && echo "max_execution_time = 3600" >> /usr/local/etc/php/conf.d/upload.ini \
    && echo "max_input_time = 3600" >> /usr/local/etc/php/conf.d/upload.ini \
    && echo "memory_limit = 1024M" >> /usr/local/etc/php/conf.d/upload.ini \
    && echo "max_file_uploads = 50" >> /usr/local/etc/php/conf.d/upload.ini

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# ==========================================
# СОЗДАЕМ ВСЕ НЕОБХОДИМЫЕ ПАПКИ
# ==========================================
RUN mkdir -p /run/nginx \
    && chown -R www-data:www-data /run/nginx \
    && chmod -R 755 /run/nginx

RUN mkdir -p /var/lib/nginx/body \
    && chown -R www-data:www-data /var/lib/nginx \
    && chmod -R 755 /var/lib/nginx

RUN mkdir -p /var/log/nginx \
    && chown -R www-data:www-data /var/log/nginx

RUN mkdir -p /var/run \
    && chown -R www-data:www-data /var/run \
    && chmod -R 755 /var/run

RUN mkdir -p /var/run/supervisor \
    && chown -R www-data:www-data /var/run/supervisor \
    && chmod -R 755 /var/run/supervisor

RUN mkdir -p /var/log/supervisor \
    && chown -R www-data:www-data /var/log/supervisor

RUN mkdir -p /var/run/php \
    && chown -R www-data:www-data /var/run/php

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

# Проверка конфигов nginx и расширений
RUN nginx -t
RUN php -m | grep -E 'redis|gd' || echo "Extensions missing"

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
