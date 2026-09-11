Шаг 1: Создать папку сайта
bash
cd ~/Документы/projects/Multsites
cp -r sites/starscy.ru sites/newsite.ru
Шаг 2: Создать базу данных
bash
docker exec -it multi_db psql -U laravel -c "CREATE DATABASE newsite_db;"
Шаг 3: Настроить .env
bash
cd sites/newsite.ru

# Изменить APP_NAME
sed -i 's/APP_NAME=.*/APP_NAME="Новый сайт"/' .env

# Изменить APP_URL
sed -i 's/APP_URL=.*/APP_URL=http:\/\/127.0.0.1:8000/' .env

# Изменить БД
sed -i 's/DB_DATABASE=.*/DB_DATABASE=newsite_db/' .env

# Изменить почту (опционально)
sed -i 's/MAIL_FROM_ADDRESS=.*/MAIL_FROM_ADDRESS=newsite@mail.ru/' .env
Шаг 4: Создать конфиг Nginx
bash
cd ~/Документы/projects/Multsites

# Скопировать шаблон
cp docker/nginx/site-template.conf docker/nginx/newsite.ru.conf

-----------------------------------------------------------------------

# 1. Создать БД
docker exec -it multi_db psql -U laravel -c "CREATE DATABASE client_db;"

# 2. Скопировать проект
cp -r sites/starscy.ru sites/client-site

# 3. Настроить .env
cd sites/client-site
sed -i 's/APP_NAME=.*/APP_NAME="Client Site"/' .env
sed -i 's/APP_URL=.*/APP_URL=http:\/\/127.0.0.1:8001/' .env
sed -i 's/DB_DATABASE=.*/DB_DATABASE=client_db/' .env

# 4. Создать конфиг nginx
cp docker/nginx/starscy.ru.conf docker/nginx/client-site.conf
sed -i 's/starscy.ru/client-site/g' docker/nginx/client-site.conf

# 5. Запустить миграции
docker exec -it multi_app bash -c "cd /var/www/html/sites/client-site && php artisan migrate --force"

# 6. Перезапустить nginx
docker exec -it multi_app nginx -s reload

# Заменить {SITE_NAME} на имя сайта
sed -i 's/{SITE_NAME}/newsite.ru/g' docker/nginx/newsite.ru.conf
Шаг 5: Запустить миграции
bash
docker exec -it multi_app bash -c "
cd /var/www/html/sites/newsite.ru && \
php artisan key:generate && \
php artisan storage:link && \
php artisan migrate --force && \
php artisan config:clear && \
php artisan cache:clear
"
Шаг 6: Перезапустить Nginx
bash
docker exec -it multi_app nginx -s reload
Шаг 7: Добавить домен в hosts (локально)
bash
echo "127.0.0.1 newsite.ru www.newsite.ru" | sudo tee -a /etc/hosts
Шаг 8: Проверить
bash
curl -I http://127.0.0.1:8000
# или
curl -I http://newsite.ru:8000

..........................

1. Правите в landing-engine/
2. git commit + push (для истории)
3. cd ~/Документы/projects/Multsites
   ./deploy/build-local.sh --site=starscy.ru

   Что делает build-local.sh:
    - npm run build в landing-engine/  (ASSET_URL из sites.conf)
    - rsync landing-engine/ → сервер:sites/starscy.ru/
      (исключая .env, storage, vendor, node_modules, .git)
    - scp public/build → сервер → docker cp в контейнер
    - ssh → deploy/deploy-server.sh --site=starscy.ru

4. deploy-server.sh на сервере:
    - распаковка public/build
    - composer install (если надо)
    - php artisan migrate --force
    - chown www-data
    - storage:link (если нет)
    - optimize:clear
    - nginx -s reload
