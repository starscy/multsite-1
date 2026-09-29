#!/bin/bash
# deploy/deploy-server.sh
# ==========================================
# СЕРВЕРНЫЙ ДЕПЛОЙ
# Запускать на сервере из multisites-1/
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib/common.sh"

# Настройки
CONTAINER="${CONTAINER:-multi_app}"
SITES_DIR="${SITES_DIR:-/var/www/html/sites}"
SKIP_MIGRATE="${SKIP_MIGRATE:-0}"
SKIP_CACHE="${SKIP_CACHE:-0}"
SKIP_COMPOSER="${SKIP_COMPOSER:-0}"

# Парсинг
select_sites "$@"

log "${GREEN}🚀 Серверный деплой${NC}"
log "${BLUE}📄 Лог: $LOG_FILE${NC}"
log "${CYAN}Контейнер: $CONTAINER${NC}"
log ""

# Проверка контейнера
docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$" || die "Контейнер $CONTAINER не запущен"

# Проверка билда
HAS_BUILD=0
if docker exec "$CONTAINER" test -f /tmp/build.tar.gz 2>/dev/null; then
    HAS_BUILD=1
    log "${YELLOW}📦 Найден билд, раскладываем${NC}"
fi

# ==========================================
# Деплой каждого сайта
# ==========================================
FAILED=()
SUCCESS=()

for site in "${SELECTED_SITES[@]}"; do
    ENGINE=$(get_site_field "$site" 2)
    DB_NAME=$(get_site_field "$site" 4)

    log ""
    log "${CYAN}━━━ $site [engine=$ENGINE, db=$DB_NAME] ━━━${NC}"

    SITE_PATH="$SITES_DIR/$site"

    # Проверки
    docker exec "$CONTAINER" test -d "$SITE_PATH" || {
        log "${RED}❌ Папка $SITE_PATH не найдена${NC}"
        FAILED+=("$site: папка не найдена")
        continue
    }

    docker exec "$CONTAINER" test -f "$SITE_PATH/artisan" || {
        log "${RED}❌ $SITE_PATH/artisan не найден${NC}"
        FAILED+=("$site: не Laravel")
        continue
    }

    # Раскладка билда
    if [ "$HAS_BUILD" = "1" ] && [ "$ENGINE" = "landing-engine" ]; then
        log "${YELLOW}  → раскладка билда${NC}"
        docker exec "$CONTAINER" bash -c "
            cd $SITE_PATH
            rm -rf public/build public/hot
            tar -xzf /tmp/build.tar.gz
            chown -R www-data:www-data public/build
            chmod -R 755 public/build
            find public/build -type f -exec chmod 644 {} \;
        " || {
            FAILED+=("$site: ошибка распаковки")
            continue
        }
    fi

    # ==========================================
    # Сброс bootstrap-кэша (ДО composer install)
    # ==========================================
    log "${YELLOW}  → сброс bootstrap-кэша (перед composer)${NC}"
    docker exec "$CONTAINER" bash -c "
        cd $SITE_PATH
        rm -f bootstrap/cache/packages.php bootstrap/cache/services.php bootstrap/cache/config.php
    " || true

    # Composer install
    if [ "$SKIP_COMPOSER" != "1" ]; then
        log "${YELLOW}  → composer install (проверка)${NC}"
        docker exec "$CONTAINER" bash -c "
            cd $SITE_PATH
            [ -f composer.json ] && \
            [ ! -f vendor/composer/installed.json ] || \
            [ composer.json -nt vendor/composer/installed.json ]
        " 2>/dev/null && {
            log "${YELLOW}  → composer install${NC}"
            docker exec "$CONTAINER" bash -c "
                cd $SITE_PATH
                composer install --no-dev --optimize-autoloader --no-interaction
            " || log "${YELLOW}  ⚠️ composer warning${NC}"
        }
    fi

    # ==========================================
    # Сброс bootstrap-кэша (ПОСЛЕ composer install)
    # ==========================================
    log "${YELLOW}  → сброс bootstrap-кэша (после composer)${NC}"
    docker exec "$CONTAINER" bash -c "
        cd $SITE_PATH
        rm -f bootstrap/cache/packages.php bootstrap/cache/services.php bootstrap/cache/config.php
        php artisan package:discover --ansi 2>&1 | tail -5
    " || log "${YELLOW}  ⚠️ package:discover warning${NC}"

    # Миграции
    if [ "$SKIP_MIGRATE" != "1" ]; then
        log "${YELLOW}  → миграции${NC}"
        docker exec "$CONTAINER" bash -c "
            cd $SITE_PATH
            php artisan migrate --force
        " 2>&1 | tee -a "$LOG_FILE" || {
            FAILED+=("$site: migrate упал")
            continue
        }
    fi

    # Права
    log "${YELLOW}  → права${NC}"
    docker exec "$CONTAINER" bash -c "
        cd $SITE_PATH
        chown -R www-data:www-data storage bootstrap/cache public 2>/dev/null || true
        chmod -R 775 storage bootstrap/cache 2>/dev/null || true
        [ -d public/build ] && {
            chown -R www-data:www-data public/build
            chmod -R 755 public/build
            find public/build -type f -exec chmod 644 {} \;
        } || true
    "

    # Симлинк storage
    log "${YELLOW}  → storage:link${NC}"
    docker exec "$CONTAINER" bash -c "
        cd $SITE_PATH
        [ -L public/storage ] || php artisan storage:link 2>/dev/null || true
    "

    # Кэш
    if [ "$SKIP_CACHE" != "1" ]; then
        log "${YELLOW}  → очистка кэша${NC}"
        docker exec "$CONTAINER" bash -c "
            cd $SITE_PATH
            php artisan view:clear
            php artisan config:clear
            php artisan cache:clear
            php artisan route:clear
            php artisan event:clear
            php artisan optimize:clear
        " > /dev/null 2>&1 || true
    fi

    log "${GREEN}  ✅ $site готов${NC}"
    SUCCESS+=("$site")
done

# Удаляем временный билд
[ "$HAS_BUILD" = "1" ] && docker exec "$CONTAINER" rm -f /tmp/build.tar.gz

# Nginx reload
log ""
log "${YELLOW}🔄 Перезагрузка nginx${NC}"
docker exec "$CONTAINER" nginx -t > /dev/null 2>&1 && \
    docker exec "$CONTAINER" nginx -s reload && \
    log "${GREEN}✅ nginx перезагружен${NC}" || \
    log "${YELLOW}⚠️ nginx reload пропущен${NC}"

# Итог
log ""
log "${GREEN}===========================================${NC}"
log "${GREEN}✅ Деплой завершён${NC}"
log "${GREEN}===========================================${NC}"
log ""
log "${GREEN}Успешно:${NC} ${SUCCESS[*]:-нет}"

if [ ${#FAILED[@]} -gt 0 ]; then
    log "${RED}Провалено:${NC}"
    for f in "${FAILED[@]}"; do
        log "  - $f"
    done
    exit 1
fi

log "Лог: $LOG_FILE"
