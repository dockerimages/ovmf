#!/bin/bash
#######
# Direkt SPEED / Frank Lemanschik / B8G Datentechnik
# In File Docker Build executor hook Open Virtual Machine Formart! ovmf executor
# !!!!!!! IMPORTENT TECHNOLOGY SPEARD THE WORD !!!!!!!!!!!!!!!!!!
######

## This works becaus docker ignores 
#not known commands ;) and bash only gives some errors
##

#docker build -t data-store data-store && \
#docker build -t site-db site-db && \
#docker build -t web-machine web-machine
#REPOS=$(docker ps -notrunc -a -q)
#echo Removing
#echo $REPOS
#echo ---
#docker rm `docker ps -notrunc -a -q` > /dev/null 2>&1
#docker ps -a

docker build -t data-store - << DATASTORE
######## data-store
FROM dockerimages/ubuntu-core:14.04
MAINTAINER Frank Lemanschik <frank@dspeed.eu>
ENV DOCKER_RUN docker run -name my-data-store data-store true
RUN apt-get update \
 && apt-get -y upgrade \
 && apt-get -y install curl unzip \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Create /data volume
VOLUME ["/data"]

# Create data directories
RUN mkdir -p /data/mysql /data/www

# Fill it With Joomla
RUN curl -G -o /data/joomla.zip http://joomlacode.org/gf/download/frsrelease/19239/158104/Joomla_3.2.3-Stable-Full_Package.zip \
 && unzip /data/joomla.zip -d /data/www \
 && rm /data/joomla.zip
CMD ["/bin/sh" "echo" "done"]
DATASTORE

docker build -t site-db - <<'SITEDB'
FROM dockerimages/ubuntu-core:14.04
MAINTAINER Frank Lemanschik
ENV DOCKER_RUN docker run -d -volumes-from my-data-store -name my-site-db site-db

RUN apt-get update \
 && apt-get upgrade -y \
 &&	apt-get -y -q install wget logrotate

# Ensure UTF-8
RUN apt-get update \
 && locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8

# Install Mysql
RUN apt-get update \
 && apt-get install -y mysql-server

# Decouple our data from our container.
#VOLUME ["/data"]

# Configure the database to use our data dir.
RUN sed -i -e 's/^datadir\s*=.*/datadir = \/data\/mysql/' /etc/mysql/my.cnf

# Configure MariaDB to listen on any address.
RUN sed -i -e 's/^bind-address/#bind-address/' /etc/mysql/my.cnf
EXPOSE 3306
#ADD site-db/start.sh /start.sh
RUN echo '#!/bin/bash \n\
\n\
# Starts up MariaDB within the container. \n\
\n\
# Stop on error \n\
set -e \n\
\n\
DATADIR="/data/mysql" \n\
\n\
/etc/init.d/mysql stop \n\
\n\
# test if DATADIR has content \n\
if [ ! "$(ls -A $DATADIR)" ]; then \n\
  echo "Initializing MariaDB at $DATADIR" \n\
\n\
  # Copy the data that we generated within the container to the empty DATADIR. \n\
  cp -R /var/lib/mysql/* $DATADIR \n\
fi \n\
\n\
# Ensure mysql owns the DATADIR \n\
chown -R mysql $DATADIR \n\
chown root $DATADIR/debian*.flag \n\
\n\
# The password for "debian-sys-maint"@"localhost" is auto generated. \n\
# The database inside of DATADIR may not have been generated with this password. \n\
# So, we need to set this for our database to be portable. \n\
echo "Setting password for the \"debian-sys-maint\"@\"localhost\" user" \n\
\n\
/etc/init.d/mysql start \n\
\n\
sleep 1 \n\
\n\
DB_MAINT_PASS=$(cat /etc/mysql/debian.cnf |grep -m 1 "password\s*=\s*"| sed "s/^password\s*=\s*//") \n\
\n\
mysql -u root -e \ \n\
  "GRANT ALL PRIVILEGES ON *.* TO "debian-sys-maint"@"localhost" IDENTIFIED BY "$DB_MAINT_PASS";" \n\
\n\
# Create the superuser named "docker". \n\
mysql -u root -e \ \n\
  "DELETE FROM mysql.user WHERE user=docker; CREATE USER docker@localhost IDENTIFIED BY docker; GRANT ALL PRIVILEGES ON *.* TO docker@localhost WITH GRANT OPTION; CREATE USER docker@% IDENTIFIED BY docker; GRANT ALL PRIVILEGES ON *.* TO docker@% WITH GRANT OPTION;" && \ \n\
  /etc/init.d/mysql stop \n\
\n\
# Start MariaDB' > /start.sh
RUN chmod +x /start.sh
ENTRYPOINT ["/start.sh"]
SITEDB


docker build -t web-machine - <<WEB
FROM dockerimages/ubuntu-core:14.04
MAINTAINER Frank Lemanschik

# Install all that’s needed
RUN apt-get update \
 &&	apt-get -y upgrade \
 && apt-get -y install \
 	mysql-client apache2 libapache2-mod-php5 pwgen python-setuptools vim-tiny php5-mysql openssh-server sudo php5-ldap unzip \
 && apt-get clean \
 &&	rm -rf /var/lib/apt/lists/* \
 && easy_install supervisor

# Create! --Add-- all config and start files
RUN echo "#!/bin/bash \n\
# Alternate method change user id of www-data to match file owner! \n\
chown -R www-data:www-data /data/www \n\
supervisord -n" > /start.sh

RUN echo '# /etc/supervisord.conf \n\
[unix_http_server] \n\
file=/tmp/supervisor.sock                       ; path to your socket file \n\
\n\
[supervisord] \n\
logfile=/var/log/supervisord/supervisord.log    ; supervisord log file \n\
logfile_maxbytes=50MB                           ; maximum size of logfile before rotation \n\
logfile_backups=10                              ; number of backed up logfiles \n\
loglevel=error                                  ; info, debug, warn, trace \n\
pidfile=/var/run/supervisord.pid                ; pidfile location \n\
nodaemon=false                                  ; run supervisord as a daemon \n\
minfds=1024                                     ; number of startup file descriptors \n\
minprocs=200                                    ; number of process descriptors \n\
user=root                                       ; default user \n\
childlogdir=/var/log/supervisord/               ; where child log files will live \n\
\n\
[rpcinterface:supervisor] \n\
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface \n\
\n\
[supervisorctl] \n\
serverurl=unix:///tmp/supervisor.sock         ; use a unix:// URL  for a unix socket \n\
\n\
[program:httpd] \n\
command=/etc/apache2/foreground.sh \n\
stopsignal=6 \n\
\n\
;sshd \n\
[program:sshd] \n\
command=/usr/sbin/sshd -D \n\
stdout_logfile=/var/log/supervisord/%(program_name)s.log \n\
stderr_logfile=/var/log/supervisord/%(program_name)s.log \n\
autorestart=true' > /etc/supervisord.conf \
 && echo '#!/bin/bash \n\
read pid cmd state ppid pgrp session tty_nr tpgid rest < /proc/self/stat \n\
trap "kill -TERM -$pgrp; exit" EXIT TERM KILL SIGKILL SIGTERM SIGQUIT \n\
source /etc/apache2/envvars \n\
apache2 -D FOREGROUND' > /etc/apache2/foreground.sh

RUN mkdir -p /var/log/supervisord /var/run/sshd
RUN chmod 755 /start.sh && chmod 755 /etc/apache2/foreground.sh

# Set Apache user and log
ENV APACHE_RUN_USER www-data
ENV APACHE_RUN_GROUP www-data
ENV APACHE_LOG_DIR /var/log/apache2
ENV DOCKER_RUN "docker run -d -name my-web-machine -p 80:80 -p 9000:22 -link my-site-db:mysql -volumes-from my-data-store web-machine"
ENV HAPROXY_DOMAIN "joomla3"
VOLUME ["/data"]

# Add site to apache
RUN echo "<VirtualHost *:80> \n\
ServerAdmin webmaster@localhost \n\
DocumentRoot /data/www \n\
<Directory /> \n\
Options FollowSymLinks \n\
AllowOverride None \n\
</Directory> \n\
<Directory /data/www/> \n\
Options Indexes FollowSymLinks MultiViews \n\
AllowOverride None \n\
Order allow,deny \n\
allow from all \n\
</Directory> \n\
ErrorLog ${APACHE_LOG_DIR}/error.log \n\
# Possible values include: debug, info, notice, warn, error, crit, \n\
# alert, emerg. \n\
LogLevel warn \n\
CustomLog ${APACHE_LOG_DIR}/access.log combined \n\
</VirtualHost>" > /etc/apache2/sites-available/joomla.conf

#RUN ls -ao /etc/apache2/sites-available/ && cat /etc/apache2/sites-available/joomla


RUN a2ensite joomla
RUN a2dissite 000-default

# Set root password to access through ssh
RUN echo "root:desdemona" | chpasswd

# Expose web and ssh
EXPOSE 80
EXPOSE 22

CMD ["/bin/bash", "/start.sh"]
WEB
