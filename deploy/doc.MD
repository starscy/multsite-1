# Локально, в landing-engine/
./deploy/build-local.sh --site=starscy.ru
./deploy/build-local.sh --site=demo.starscy.ru
./deploy/build-local.sh --site=wedding.starscy.ru

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

после деплоя на сервере запустить:

docker exec multi_app bash -c "
cd /var/www/html/sites/wedding.starscy.ru
rm -f bootstrap/cache/packages.php bootstrap/cache/services.php bootstrap/cache/config.php
php artisan package:discover --ansi
"

