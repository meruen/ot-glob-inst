#!/bin/sh

# Server name
TIBIA_SERVER_NAME="ServerForge"
# Server external IP
TIBIA_SERVER_IP="192.168.112.132"
# IP address who will install MyAAC
TIBIA_AAC_INSTALLER_IP="192.168.112.1"
# Apache virtual hostname
TIBIA_REMOTE_HOSTNAME='tibia.serverforge.com.br'

# Mysql root password
MYSQL_ROOT_PASSWORD="12345678"
# Mysql database name
MYSQL_DATABASE="tibia"

# Service name
TIBIA_SERVICE_NAME="tibia-server"

# Phpmyadmin apache folder name
WWW_PHPMYADMIN_FOLDER_NAME="phpmyadmin"
# MyAAC apache folder name
WWW_MYAAC_FOLDER_NAME="myaac"

RDIR=$(pwd)
CANARY_DIR=$RDIR/canary

success() {
    echo "\e[32m$1\e[0m"
}

warn() {
    echo "\e[33m$1\e[0m"
}

error() {
    echo "\e[31m$1\e[0m"
}

echo "[INFO] Adding non-free options to /etc/apt/sources.list"

if ! grep -q "^# patched by tibia installer" /etc/apt/sources.list; then
    sed -i 's/\bmain\b/main non-free/g' /etc/apt/sources.list
    sed -i '1i # patched by tibia installer' /etc/apt/sources.list
    wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
    success "[INFO] /etc/apt/sources.list patched!"
else
    warn "[INFO] /etc/apt/sources.list already patched!"
fi

if ! grep -q "^ClientAliveInterval 3600" /etc/ssh/sshd_config && ! grep -q "^ClientAliveCountMax 3" /etc/ssh/sshd_config; then
    sed -i 's/^ClientAliveInterval.*/#&/' /etc/ssh/sshd_config
    sed -i 's/^ClientAliveCountMax.*/#&/' /etc/ssh/sshd_config
    
    echo "ClientAliveInterval 3600" >> /etc/ssh/sshd_config
    echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config
    success "[INFO] SSH configuration has been successfully applied."

    systemctl restart sshd
    success "[INFO] SSH service has been restarted."
else
    warn "[INFO] SSH configuration has already been applied previously. No action taken."
fi

apt-get -y update
apt-get -y upgrade
apt-get -y install vim acl git cmake build-essential autoconf libtool ca-certificates curl zip unzip tar pkg-config ninja-build ccache linux-headers-$(uname -r) mariadb-server mariadb-client software-properties-common apt-transport-https lsb-release
apt-get -y remove --purge cmake
hash -r
apt-get -y install snapd
snap install cmake --classic

## Mariadb
systemctl enable mariadb
systemctl start mariadb

mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';"
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "DELETE FROM mysql.user WHERE User='';"
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS test;"
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';"
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"
systemctl restart mariadb

success "[INFO] MySQL secure installation tasks have been completed."

if ! echo "$PATH" | grep -q "/snap/bin"; then
    export PATH=$PATH:/snap/bin
    success "[INFO] Path enhanced with snap!"
fi

success "[INFO] $(cmake --version)"
success "[INFO] All dependencies installed!"

mkdir -p vcpkg
git clone https://github.com/microsoft/vcpkg
cd vcpkg
./bootstrap-vcpkg.sh
cd ..
success "[INFO] VCPKG installed!"


# Canary
git clone --depth 1 https://github.com/opentibiabr/canary.git
setfacl -R -m g:www-data:rx ./canary
chmod -R 755 ./canary
cd canary
sed -i 's/static constexpr auto CLIENT_VERSION = [0-9]\{4\};/static constexpr auto CLIENT_VERSION = 1336;/' ./src/core.hpp
mkdir -p build
cd build
cmake -DCMAKE_TOOLCHAIN_FILE=$RDIR/vcpkg/scripts/buildsystems/vcpkg.cmake .. --preset linux-release
cmake --build linux-release
cp linux-release/bin/canary ../canary
cd ..
chmod +x canary

# config.lua
rm -f config.lua
cp config.lua.dist config.lua
sed -i "s/^ip = \"127.0.0.1\"$/ip = \"$TIBIA_SERVER_IP\"/" config.lua
sed -i "s/^serverName = \"OTServBR-Global\"$/serverName = \"$TIBIA_SERVER_NAME\"/" config.lua
sed -i "s/^mysqlPass = \"root\"$/mysqlPass = \"$MYSQL_ROOT_PASSWORD\"/" config.lua
sed -i "s/^mysqlDatabase = \"otservbr-global\"$/mysqlDatabase = \"$MYSQL_DATABASE\"/" config.lua

# MySQL schema
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS $MYSQL_DATABASE;"
mysql -u root -p"$MYSQL_ROOT_PASSWORD" $MYSQL_DATABASE < schema.sql
systemctl restart mariadb

# php
apt-get -y install php8.2 php8.2-cli php8.2-curl php8.2-fpm php8.2-gd php8.2-mysql php8.2-xml php8.2-zip php8.2-bcmath php8.2-mbstring php8.2-calendar apache2 apache2-utils libapache2-mod-php8.2
php8.2 -v
systemctl start php8.2-fpm
systemctl enable php8.2-fpm
systemctl status php8.2-fpm

# phpmyadmin
rm -rf /var/www/html/$WWW_PHPMYADMIN_FOLDER_NAME
cd $RDIR
wget https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-all-languages.zip -O phpmyadmin.zip
unzip phpmyadmin.zip
mv phpMyAdmin-*-all-languages /var/www/html/$WWW_PHPMYADMIN_FOLDER_NAME
rm phpmyadmin.zip
chown -R www-data:www-data /var/www/html/$WWW_PHPMYADMIN_FOLDER_NAME
chmod -R 755 /var/www/html/$WWW_PHPMYADMIN_FOLDER_NAME
blowfish_secret=$(openssl rand -base64 24 | sed 's/[\/&]/\\&/g')
cp /var/www/html/$WWW_PHPMYADMIN_FOLDER_NAME/config.sample.inc.php /var/www/html/$WWW_PHPMYADMIN_FOLDER_NAME/config.inc.php
sed -i "s#\$cfg\['blowfish_secret'\] = '';#\$cfg\['blowfish_secret'\] = '$blowfish_secret';#" /var/www/html/$WWW_PHPMYADMIN_FOLDER_NAME/config.inc.php

# MyAAC
rm -rf /var/www/html/$WWW_MYAAC_FOLDER_NAME
cd $RDIR
git clone https://github.com/opentibiabr/myaac.git
mkdir -p /var/www/html/$WWW_MYAAC_FOLDER_NAME
mv myaac/* /var/www/html/$WWW_MYAAC_FOLDER_NAME
rm -rf myaac
echo $TIBIA_AAC_INSTALLER_IP > /var/www/html/$WWW_MYAAC_FOLDER_NAME/install/ip.txt
chown -R www-data.www-data /var/www/html
chmod 755 -R /var/www/html

# apache
cp -fv ./virtualhost.conf /etc/apache2/sites-available/$TIBIA_REMOTE_HOSTNAME.conf
sed -i "s/\$REMOTE_HOSTNAME/$TIBIA_REMOTE_HOSTNAME/g" /etc/apache2/sites-available/$TIBIA_REMOTE_HOSTNAME.conf
sed -i "s/\$WWW_MYAAC_FOLDER_NAME/$WWW_MYAAC_FOLDER_NAME/g" /etc/apache2/sites-available/$TIBIA_REMOTE_HOSTNAME.conf
/usr/sbin/a2enmod proxy_fcgi
/usr/sbin/a2enmod php8.2
/usr/sbin/a2ensite $TIBIA_REMOTE_HOSTNAME.conf
systemctl reload apache2

# tibia service
cd $RDIR
cp -fv ./template.service /etc/systemd/system/$TIBIA_SERVICE_NAME.service
echo sed -i "s#\$CANARY_DIR#$CANARY_DIR#g" /etc/systemd/system/$TIBIA_SERVICE_NAME.service
sed -i "s#\$CANARY_DIR#$CANARY_DIR#g" /etc/systemd/system/$TIBIA_SERVICE_NAME.service
systemctl daemon-reload
systemctl stop $TIBIA_SERVICE_NAME.service
systemctl disable $TIBIA_SERVICE_NAME.service
systemctl enable $TIBIA_SERVICE_NAME.service
systemctl start $TIBIA_SERVICE_NAME.service
sleep 5
systemctl status $TIBIA_SERVICE_NAME.service

# crazy +x permissions
currentPath=""
for dir in $(echo "$CANARY_DIR" | tr '/' ' '); do
    if [ -n "$dir" ]; then
        currentPath="$currentPath/$dir"
        echo chmod +x "$currentPath"
        chmod +x "$currentPath"
    fi
done

success "[INFO] Everything done! Now go to http://$TIBIA_SERVER_IP/$WWW_MYAAC_FOLDER_NAME/install to install MyACC!"
success "[INFO] Provide the following data when asked:"
success " Server Path   : $CANARY_DIR"
success " Client Version: 13.30"
