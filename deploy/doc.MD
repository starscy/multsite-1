# Локально, в landing-engine/
./deploy/build-local.sh --site=starscy.ru

# Деплой нескольких
./deploy/build-local.sh --site=starscy.ru --site=site2.ru

# Все движковые
./deploy/build-local.sh --engine=landing-engine

# Все сайты
./deploy/build-local.sh --all

# Интерактивный режим
./deploy/build-local.sh

# Только серверный деплой (без сборки)
# На сервере
cd /var/www/multisites-1
./deploy/deploy-server.sh --site=starscy.ru
