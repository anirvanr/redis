**1. Creating a Redis Cluster using the create-cluster script**
```
wget http://download.redis.io/releases/redis-5.0.0.tar.gz
tar xzf redis-5.0.0.tar.gz
cd redis-5.0.0
make
cd utils/create-cluster
./create-cluster start
../../src/redis-cli -p 30001 cluster info
```
It should show the cluster_state as failed, and cluster_slots_assigned as 0
```
./create-cluster create
```
Executing "cluster info" after it shows that cluster state is "ok" and cluster_slots_assigned are 16384


**2. Setting up a multi-host redis-cluster**

Redis recommendation is to have at least one slave for each master
- Minimum 3 machines
- Minimum 3 Redis master nodes on separate machines (sharding)
- Minimum 3 Redis slaves, 1 slave per master (to allow minimal fail-over mechanism)

Eg below to install a 3 node cluster:
1. To create a new cluster from scratch, spin up at least 3 ec2 hosts
2. Copy `redis-cluster.sh` script to all hosts and run it
3. On any host run the below command to create the cluster
```
redis-cli --cluster create [host1]:7000 [host1]:7001 \
[host2]:7000 [host2]:7001 \ 
[host3]:7000 [host3]:7001 \
--cluster-replicas 1
```
Verify Redis Cluster
```
redis-cli -h [host1|host2|host3] -p 7000 cluster info
redis-cli -h [host1|host2|host3] -p 7000 cluster nodes
redis-cli --cluster check [host1|host2|host3]:7000
```

Links

https://codeflex.co/configuring-redis-cluster-on-linux/

http://pingredis.blogspot.com/2016/09/redis-cluster-how-to-create-cluster.html

https://redis.io/topics/cluster-tutorial

https://docs.bitnami.com/installer/apps/diaspora/administration/create-cluster/

https://community.pivotal.io/s/article/How-to-setup-HAProxy-and-Redis-Sentinel-for-automatic-failover-between-Redis-Master-and-Slave-servers

https://alex.dzyoba.com/blog/redis-cluster/

https://willwarren.com/2017/10/redis-cluster-cheatsheet/
