#!/bin/bash
# deploy/lib/common.sh
# ==========================================
# Общие функции для деплой-скриптов
# ==========================================

set -e

# Цвета
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export RED='\033[0;31m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export NC='\033[0m'

# Пути
: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
: "${PROJECT_DIR:=$(cd "$SCRIPT_DIR/.." && pwd)}"
: "${SITES_CONF:=$SCRIPT_DIR/sites.conf}"

# Логирование
LOG_TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
export LOG_FILE="${SCRIPT_DIR}/logs/deploy_${LOG_TIMESTAMP}.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo -e "$@" | tee -a "$LOG_FILE"
}

die() {
    log "${RED}❌ $*${NC}"
    exit 1
}

# ==========================================
# Парсинг sites.conf
# ==========================================
get_all_sites() {
    grep -v '^\s*#' "$SITES_CONF" | grep -v '^\s*$'
}

get_site_config() {
    local domain="$1"
    get_all_sites | grep "^${domain}|" || true
}

get_site_field() {
    local domain="$1"
    local field="$2"   # 1=domain, 2=engine, 3=asset_url, 4=db_name
    get_site_config "$domain" | cut -d'|' -f"$field"
}

site_exists() {
    [ -n "$(get_site_config "$1")" ]
}

# ==========================================
# Выбор сайтов
# ==========================================
select_sites() {
    local selected=()

    for arg in "$@"; do
        case "$arg" in
            --all)
                while IFS='|' read -r domain _; do
                    selected+=("$domain")
                done < <(get_all_sites)
                ;;
            --engine=*)
                local engine="${arg#--engine=}"
                while IFS='|' read -r domain eng _; do
                    [ "$eng" = "$engine" ] && selected+=("$domain")
                done < <(get_all_sites)
                ;;
            --site=*)
                selected+=("${arg#--site=}")
                ;;
        esac
    done

    if [ ${#selected[@]} -eq 0 ]; then
        log "${YELLOW}Выберите сайты для деплоя:${NC}"
        local i=1
        local domains=()
        while IFS='|' read -r domain eng _; do
            domains+=("$domain")
            log "  $i) $domain ${BLUE}[$eng]${NC}"
            ((i++))
        done < <(get_all_sites)

        log ""
        read -rp "Номера через пробел (или 'all'): " choice

        if [ "$choice" = "all" ]; then
            selected=("${domains[@]}")
        else
            for n in $choice; do
                selected+=("${domains[$((n-1))]}")
            done
        fi
    fi

    for site in "${selected[@]}"; do
        site_exists "$site" || die "Сайт '$site' не найден в $SITES_CONF"
    done

    SELECTED_SITES=("${selected[@]}")
    log "${GREEN}Сайты: ${SELECTED_SITES[*]}${NC}"
    log ""
}
