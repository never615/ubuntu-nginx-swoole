#!/bin/bash

#echo '-------- run laravel sail scripts start  ----------'
#
# if [ ! -z "$WWWUSER" ]; then
#     usermod -u $WWWUSER sail
# fi
#
#if [ ! -d /.composer ]; then
#    mkdir /.composer
#fi
#
#chmod -R ugo+rw /.composer
#
#echo '-------- run laravel sail scripts end  ----------'




echo '-------- run start scripts start  ----------'

# Disable Strict Host checking for non interactive git clones

#mkdir -p -m 0700 /root/.ssh
## Prevent config files from being filled to infinity by force of stop and restart the container
#echo "" > /root/.ssh/config
#echo -e "Host *\n\tStrictHostKeyChecking no\n" >> /root/.ssh/config
#
#if [ ! -z "$SSH_KEY" ]; then
# echo $SSH_KEY > /root/.ssh/id_rsa.base64
# base64 -d /root/.ssh/id_rsa.base64 > /root/.ssh/id_rsa
# chmod 600 /root/.ssh/id_rsa
#fi
#
#
## Set custom webroot
#if [ ! -z "$WEBROOT" ]; then
# sed -i "s#root /var/www/html;#root ${WEBROOT};#g" /etc/nginx/sites-available/default.conf
#else
# webroot=/var/www/html
#fi

# Enables 404 pages through php index
if [ ! -z "$PHP_CATCHALL" ]; then
 sed -i 's#try_files $uri $uri/ =404;#try_files $uri $uri/ /index.php?$args;#g' /etc/nginx/conf.d/default.conf
fi

# Enable custom nginx config files if they exist
if [ -f /var/www/html/conf/nginx/nginx.conf ]; then
  cp /var/www/html/conf/nginx/nginx.conf /etc/nginx/nginx.conf
fi

if [ -f /var/www/html/conf/nginx/nginx-site.conf ]; then
  cp /var/www/html/conf/nginx/nginx-site.conf /etc/nginx/conf.d/default.conf
fi

# Display errors in docker logs
if [ ! -z "$PHP_ERRORS_STDERR" ]; then
  echo "log_errors = On" >> ${php_vars}
  echo "error_log = /dev/stderr" >> ${php_vars}
fi


# Pass real-ip to logs when behind ELB, etc
if [[ "$REAL_IP_HEADER" == "1" ]] ; then
 sed -i "s/#real_ip_header X-Forwarded-For;/real_ip_header X-Forwarded-For;/" /etc/nginx/conf.d/default.conf
 sed -i "s/#set_real_ip_from/set_real_ip_from/" /etc/nginx/conf.d/default.conf
 if [ ! -z "$REAL_IP_FROM" ]; then
  sed -i "s#172.16.0.0/12#$REAL_IP_FROM#" /etc/nginx/conf.d/default.conf
 fi
fi

if [ ! -z "$PUID" ]; then
  if [ -z "$PGID" ]; then
    PGID=${PUID}
  fi
  deluser www-data
  addgroup -g ${PGID} www-data
  adduser -D -S -h /var/cache/www-data -s /sbin/nologin -G www-data -u ${PUID} www-data
else
  if [ -z "$SKIP_CHOWN" ]; then
    chown -Rf www-data.www-data /var/www/html
  fi
fi

echo '-------- run laravel scripts ----------'
pwd

# supervisor
echo '-------- supervisor ----------'

# touch /var/www/html/storage/logs/worker.log
touch /var/www/html/storage/logs/horizon.log

#cp /var/www/html/conf/supervisor/* /etc/supervisor/conf.d

# crontab
# echo '-------- crontab ----------'
# sed -i '$a * * * * * nginx nginx /var/www/html/artisan schedule:run >> /dev/null 2>&1'  /etc/crontab

echo '-------- Make dirs ----------'
mkdir /var/www/html/storage/framework/cache/data

# Make writable dirs
echo '-------- Make writable dirs ----------'
chown -R www-data /var/www/html/storage
chgrp -R www-data /var/www/html/storage
chmod -R 777 /var/www/html/storage


echo '-------- laravel command ----------'

# Execute artisan view:cache
php artisan view:cache

# Execute artisan config:cache
php artisan config:cache

# Execute artisan optimize
php artisan optimize

echo '-------- Make writable dirs2 ----------'
chown -R www-data /var/www/html/storage
chgrp -R www-data /var/www/html/storage
chmod -R 777 /var/www/html/storage

# migrate
php artisan migrate --force

php artisan storage:link

#opcache
#/usr/local/bin/cachetool opcache:reset

echo '-------- run laravel scripts end  ----------'

# Run custom scripts
if [[ "$RUN_SCRIPTS" == "1" ]] ; then
  scripts_dir="${SCRIPTS_DIR:-/var/www/html/scripts}"
  if [ -d "$scripts_dir" ]; then
    if [ -z "$SKIP_CHMOD" ]; then
      # make scripts executable incase they aren't
      chmod -Rf 750 $scripts_dir; sync;
    fi
    # run scripts in number order
    for i in `ls $scripts_dir`; do $scripts_dir/$i ; done
  else
    echo "Can't find script directory"
  fi
fi


if [ -z "$SKIP_COMPOSER" ]; then
    # Try auto install for composer
    if [ -f "/var/www/html/composer.lock" ]; then
        if [ "$APPLICATION_ENV" == "development" ]; then
            composer global require hirak/prestissimo
            composer install --working-dir=/var/www/html
        else
            composer global require hirak/prestissimo
            composer install --no-dev --working-dir=/var/www/html
        fi
    fi
fi

echo '-------- run start scripts end  ----------'


# Start supervisord and services
supervisord -n -c /etc/supervisor/supervisord.conf
