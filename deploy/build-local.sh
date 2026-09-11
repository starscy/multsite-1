#!/bin/bash
# deploy/build-local.sh
# ==========================================
# ЛОКАЛЬНАЯ СБОРКА И ДЕПЛОЙ
# Запускать из Multsites/
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib/common.sh"

# Настройки
REMOTE="${REMOTE:-root@31.77.133.240}"
REMOTE_DIR="${REMOTE_DIR:-/var/www/multisites-1}"
CONTAINER="${CONTAINER:-multi_app}"

# Парсинг аргументов
select_sites "$@"

log "${GREEN}🚀 Локальная сборка и деплой${NC}"
log "${BLUE}📄 Лог: $LOG_FILE${NC}"
log ""

# ==========================================
# Сборка для каждого сайта
# ==========================================
declare -A BUILT_URLS

for site in "${SELECTED_SITES[@]}"; do
    ENGINE=$(get_site_field "$site" 2)
    ASSET_URL=$(get_site_field "$site" 3)

    if [ "$ENGINE" != "landing-engine" ]; then
        log "${YELLOW}⏭  $site — не landing-engine, пропускаем сборку${NC}"
        continue
    fi

    [ -z "$ASSET_URL" ] && die "ASSET_URL пуст для $site"

    SITE_DIR="$PROJECT_DIR/sites/$site"
    [ -d "$SITE_DIR" ] || die "Папка $SITE_DIR не найдена"

    if [ -n "${BUILT_URLS[$ASSET_URL]:-}" ]; then
        log "${CYAN}♻️  $site использует уже собранный ASSET_URL=$ASSET_URL${NC}"
        continue
    fi

    log "${YELLOW}🔨 Сборка для $site (ASSET_URL=$ASSET_URL)${NC}"

    cd "$SITE_DIR"
    rm -rf public/build public/hot

    if ! NODE_ENV=production ASSET_URL="$ASSET_URL" npm run build 2>&1 | tee -a "$LOG_FILE"; then
        die "npm run build упал для $site"
    fi

    # Проверка
    if grep -rl "127.0.0.1" public/build/ > /dev/null 2>&1; then
        die "⚠️ В билде найден 127.0.0.1 для $site"
    fi

    BUILT_URLS[$ASSET_URL]="$site"
    log "${GREEN}✅ Сборка OK для $site${NC}"
    log ""
done

# ==========================================
# Заливка кода и билда
# ==========================================
for site in "${SELECTED_SITES[@]}"; do
    ENGINE=$(get_site_field "$site" 2)
    SITE_DIR="$PROJECT_DIR/sites/$site"

    log "${YELLOW}📤 Заливка $site на сервер${NC}"

    # 1. rsync кода (исключая .env, storage, vendor, node_modules)
    rsync -avz --delete \
        --exclude='.git' \
        --exclude='node_modules' \
        --exclude='vendor' \
        --exclude='.env' \
        --exclude='storage' \
        --exclude='public/storage' \
        --exclude='public/build' \
        --exclude='public/hot' \
        --exclude='.idea' \
        --exclude='build.tar.gz' \
        --exclude='.initialized' \
        "$SITE_DIR/" \
        "$REMOTE:$REMOTE_DIR/sites/$site/" 2>&1 | tee -a "$LOG_FILE"

    # 2. Билд — если landing-engine
    if [ "$ENGINE" = "landing-engine" ] && [ -d "$SITE_DIR/public/build" ]; then
        log "${YELLOW}  → упаковка билда${NC}"
        tar -czf /tmp/build.tar.gz -C "$SITE_DIR" public/build

        log "${YELLOW}  → заливка билда${NC}"
        scp /tmp/build.tar.gz "$REMOTE:/tmp/build.tar.gz" 2>&1 | tee -a "$LOG_FILE"
        ssh "$REMOTE" "docker cp /tmp/build.tar.gz $CONTAINER:/tmp/build.tar.gz && rm /tmp/build.tar.gz"
        rm -f /tmp/build.tar.gz
    fi

    log "${GREEN}  ✅ $site залит${NC}"
done

# ==========================================
# Серверный деплой
# ==========================================
log ""
log "${YELLOW}🔧 Серверный деплой${NC}"

SITE_ARGS=""
for site in "${SELECTED_SITES[@]}"; do
    SITE_ARGS="$SITE_ARGS --site=$site"
done

ssh "$REMOTE" "cd $REMOTE_DIR && ./deploy/deploy-server.sh $SITE_ARGS"

log ""
log "${GREEN}===========================================${NC}"
log "${GREEN}✅ Деплой завершён${NC}"
log "${GREEN}===========================================${NC}"
log ""
log "Сайты: ${SELECTED_SITES[*]}"
log "Лог: $LOG_FILE"
