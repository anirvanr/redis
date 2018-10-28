#!/bin/bash

### Install HAProxy ###
yum install haproxy -y
cd /etc
cp haproxy.cfg haproxy.cfg.bkp

### Configure HAProxy ###
cat > haproxy.cfg << EOF
global
    log         127.0.0.1 local2
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon
    stats socket /var/lib/haproxy/stats

listen stats :1947
    mode http
    stats enable
    timeout connect 10s
    timeout server 1m
    timeout client 1m
    stats hide-version
    stats realm Haproxy\ Statistics
    stats uri /
    stats auth admin:admin

defaults REDIS
    mode tcp
    timeout connect 3s
    timeout server 6s
    timeout client 6s

frontend redis_frontend
    bind *:5000 name redis
    default_backend redis_servers
    maxconn 1024

backend redis_servers
    option tcp-check
    tcp-check connect
    tcp-check send PING\r\n
    tcp-check expect string +PONG
    tcp-check send info\ replication\r\n
    tcp-check expect string role:master
    tcp-check send QUIT\r\n
    tcp-check expect string +OK
EOF

while [ $# -ne 0 ]
  do
  echo "    server node_$(cut -d':' -f1 <<< "$1") "$1" check inter 1s"
  shift
done | tee -a haproxy.cfg >/dev/null

### Start HAProxy Service ###
service haproxy start
chkconfig haproxy on
