**1. Creating a Redis Cluster using the create-cluster script**
```
wget http://download.redis.io/releases/redis-5.0.0.tar.gz
tar xzf redis-5.0.0.tar.gz
cd redis-5.0.0
make
cd utils/create-cluster
```
By default, this utility will create 6 nodes with 1 replica and will start creating nodes on port 30000. 
```
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
**3. Redis cluster behind HAProxy**
```
./haproxy.sh host1:7000 host1:7001 host2:7000 host2:7001 host3:7000 host3:7001
```
Access HAProxy Stats:

URL: http://<haproxy_server_ip>:1947

Login user: admin

Login password: admin

```
./redis-cli -c -h <haproxy_server_ip> -p 5000 get mykey
```
```
Redis sharded data automatically into the servers.
Redis has a concept hash slot in order to split data. All the data are divided into slots.
There are 16384 slots. These slots are divided by the number of servers.
If there are 3 servers; A, B and C then
Node A contains hash slots from 0 to 5500.
Node B contains hash slots from 5501 to 11000.
Node C contains hash slots from 11001 to 16383.
In our example cluster with nodes A, B, C, if node B fails the cluster is not able to continue, 
since we no longer have a way to serve hash slots in the range 5501–11000.
However when the cluster is created we add a slave node to every master, so that the final cluster is composed of A, B, C that are masters nodes, 
and A1, B1, C1 that are slaves nodes, the system is able to continue if node B fails.
Node B1 replicates B, and B fails, the cluster will promote node B1 as the new master and will continue to operate correctly.
```

Links

https://codeflex.co/configuring-redis-cluster-on-linux/

http://pingredis.blogspot.com/2016/09/redis-cluster-how-to-create-cluster.html

https://redis.io/topics/cluster-tutorial

https://docs.bitnami.com/installer/apps/diaspora/administration/create-cluster/

https://community.pivotal.io/s/article/How-to-setup-HAProxy-and-Redis-Sentinel-for-automatic-failover-between-Redis-Master-and-Slave-servers

https://alex.dzyoba.com/blog/redis-cluster/

https://willwarren.com/2017/10/redis-cluster-cheatsheet/
