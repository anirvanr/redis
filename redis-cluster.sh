#!/bin/bash

### CentOS Linux 7 x86_64

### Script parameters ###
REDIS_MASTER_PORT="7000"
REDIS_SLAVE_PORT="7001"

### Basic system tuning ###
echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf
/sbin/sysctl -p /etc/sysctl.conf
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo "echo never > /sys/kernel/mm/transparent_hugepage/enabled" >> /etc/rc.local
echo "sysctl -w net.core.somaxconn=65535" >> /etc/rc.local

### Installing redis server ###
yum -y install wget telnet gcc make tcl vim
wget http://download.redis.io/redis-stable.tar.gz
tar xvzf redis-stable.tar.gz
cd redis-stable
make && make install

### Create all essentials directories and copy files to the correct locations ###
cp src/redis-cli src/redis-server /usr/local/sbin/
mkdir /{etc,var}/redis
mkdir /var/redis/{${REDIS_MASTER_PORT},${REDIS_SLAVE_PORT}}
cp utils/redis_init_script /etc/init.d/redis_${REDIS_MASTER_PORT}
cp utils/redis_init_script /etc/init.d/redis_${REDIS_SLAVE_PORT}
sed -i -- "s/6379/${REDIS_MASTER_PORT}/g" /etc/init.d/redis_${REDIS_MASTER_PORT}
sed -i -- "s/6379/${REDIS_SLAVE_PORT}/g" /etc/init.d/redis_${REDIS_SLAVE_PORT}
chkconfig --add redis_${REDIS_MASTER_PORT}
chkconfig --add redis_${REDIS_SLAVE_PORT}

### Redis configuration file ###
for i in {${REDIS_MASTER_PORT},${REDIS_SLAVE_PORT}} ; do
    cat <<- EOF > /etc/redis/$i.conf
    port $i
    bind 0.0.0.0
    protected-mode no
    cluster-enabled yes
    cluster-config-file nodes.conf
    cluster-node-timeout 5000
    appendonly yes
    daemonize yes
    logfile /var/log/redis_$i.log
    loglevel notice
    pidfile /var/run/redis_$i.pid
    save 900 1
    save 300 10
    save 60 10000
    stop-writes-on-bgsave-error yes
    rdbchecksum yes
    dbfilename dump.rdb
    dir /var/redis/$i
EOF
done

### Reboot ###
systemctl reboot
