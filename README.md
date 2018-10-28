Redis recommendation is to have at least one slave for each master
- Minimum 3 machines
- Minimum 3 Redis master nodes on separate machines (sharding)
- Minimum 3 Redis slaves, 1 slave per master (to allow minimal fail-over mechanism)

Eg below to install a 3 node cluster:
1. Create 3 EC2 instances
2. Copy `redis-cluster.sh` script to all instances and run it
3. On any instance run the below command to create the cluster
```
redis-cli --cluster create [host1]:7000 [host1]:7001 \
[host2]:7000 [host2]:7001 \ 
[host3]:7000 [host3]:7001 \
--cluster-replicas 1
```

Links
https://codeflex.co/configuring-redis-cluster-on-linux/
http://pingredis.blogspot.com/2016/09/redis-cluster-how-to-create-cluster.html
https://redis.io/topics/cluster-tutorial
https://docs.bitnami.com/installer/apps/diaspora/administration/create-cluster/
https://community.pivotal.io/s/article/How-to-setup-HAProxy-and-Redis-Sentinel-for-automatic-failover-between-Redis-Master-and-Slave-servers
https://alex.dzyoba.com/blog/redis-cluster/
