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

Redis sharded data automatically into the servers.
Redis has a concept hash slot in order to split data. All the data are divided into slots.
There are 16384 slots. These slots are divided by the number of servers.
If there are 3 servers; A, B and C then
Node A contains hash slots from 0 to 5500.
Node B contains hash slots from 5501 to 11000.
Node C contains hash slots from 11001 to 16383.
In our example cluster with nodes A, B, C, if node B fails the cluster is not able to continue, 
since we no longer have a way to serve hash slots in the range 5501–11000.

However when the cluster is created we add a slave node to every master, 
so that the final cluster is composed of A, B, C that are masters nodes, 
and A1, B1, C1 that are slaves nodes, the system is able to continue if node B fails.

Node B1 replicates B, and B fails, the cluster will promote node B1 as the new master and will continue to operate correctly.

Every Redis Cluster node requires two TCP connections open. The normal Redis
TCP port used to serve clients, for example 6379, plus the port obtained by
adding 10000 to the data port, so 16379 in the example.

This second *high* port is used for the Cluster bus, that is a node-to-node
communication channel using a binary protocol. The Cluster bus is used by
nodes for failure detection, configuration update, failover authorization
and so forth. Clients should never try to communicate with the cluster bus
port, but always with the normal Redis command port, however make sure you
open both ports in your firewall, otherwise Redis cluster nodes will be
not able to communicate.

The command port and cluster bus port offset is fixed and is always 10000.

Note that for a Redis Cluster to work properly you need, for each node:

1. The normal client communication port (usually 6379) used to communicate with clients to be open to all the clients that need to reach the cluster, plus all the other cluster nodes (that use the client port for keys migrations).
2. The cluster bus port (the client port + 10000) must be reachable from all the other cluster nodes.

If you don't open both TCP ports, your cluster will not work as expected.

The cluster bus uses a different, binary protocol, for node to node data
exchange, which is more suited to exchange information between nodes using
little bandwidth and processing time.


The directive `cluster-enabled` is used to determine whether Redis will run in cluster mode or not. 
But by default, it is no. You need to change it to yes to enable cluster mode.

Redis Cluster requires a configuration file path to store changes that happen to the cluster. 
This file path should not be created or edited by humans. The directive that sets this 
file path is `cluster-config-file`. Redis is responsible for creating this file with 
all of the cluster information, such as all the nodes in a cluster, their state, and persistence variables. 
This file is rewritten whenever there is any change in the cluster.
The maximum amount of time for which a node can be unavailable without being considered as failing is specified by the directive `cluster-node-timeout` (this value is in milliseconds). 
If a node is not reachable for the specified amount of time by the majority of master nodes, it will be considered as failing. If that node is a master, a failover to one of its slaves will occur. 
If it is a slave, it will stop accepting queries.Sometimes, network failures happen, and when they happen, 
it is always a good idea to minimize problems. If network issues are happening and nodes cannot communicate well, 
it is possible that the majority of nodes think that a given master is down and so a failover procedure should start. 
If the network only had a hiccup, the failover procedure might have been unnecessary. 
There is a configuration directive that helps minimize these kinds of problems. 
The directive is `cluster-slave-validity-factor`, and it expects a factor. 
By default, the factor is 10. If there is a network issue and a master node cannot communicate well 
with other nodes for a certain amount of time (cluster-node-timeout multiplied by cluster-slave-validity-factor), 
no slaves will be promoted to replace that master. When the connection issues go away and the master node is able to communicate well with others again, if it becomes unreachable a failover will happen.

Redis Cluster data sharding
---

Redis Cluster does not use consistent hashing, but a different form of sharding
where every key is conceptually part of what we call an **hash slot**.

There are 16384 hash slots in Redis Cluster, and to compute what is the hash
slot of a given key, we simply take the CRC16 of the key modulo
16384.

Every node in a Redis Cluster is responsible for a subset of the hash slots,
so for example you may have a cluster with 3 nodes, where:

* Node A contains hash slots from 0 to 5500.
* Node B contains hash slots from 5501 to 11000.
* Node C contains hash slots from 11001 to 16383.

This allows to add and remove nodes in the cluster easily. For example if
I want to add a new node D, I need to move some hash slot from nodes A, B, C
to D. Similarly if I want to remove node A from the cluster I can just
move the hash slots served by A to B and C. When the node A will be empty
I can remove it from the cluster completely.

Because moving hash slots from a node to another does not require to stop
operations, adding and removing nodes, or changing the percentage of hash
slots hold by nodes, does not require any downtime.

Redis Cluster supports multiple key operations as long as all the keys involved
into a single command execution (or whole transaction, or Lua script
execution) all belong to the same hash slot. The user can force multiple keys
to be part of the same hash slot by using a concept called *hash tags*.

Hash tags are documented in the Redis Cluster specification, but the gist is
that if there is a substring between {} brackets in a key, only what is
inside the string is hashed, so for example `this{foo}key` and `another{foo}key`
are guaranteed to be in the same hash slot, and can be used together in a
command with multiple keys as arguments.

Redis Cluster consistency guarantees
---

Redis Cluster is not able to guarantee **strong consistency**. In practical
terms this means that under certain conditions it is possible that Redis
Cluster will lose writes that were acknowledged by the system to the client.

The first reason why Redis Cluster can lose writes is because it uses
asynchronous replication. This means that during writes the following
happens:

* Your client writes to the master B.
* The master B replies OK to your client.
* The master B propagates the write to its slaves B1, B2 and B3.

As you can see B does not wait for an acknowledge from B1, B2, B3 before
replying to the client, since this would be a prohibitive latency penalty
for Redis, so if your client writes something, B acknowledges the write,
but crashes before being able to send the write to its slaves, one of the
slaves (that did not receive the write) can be promoted to master, losing
the write forever.

This is **very similar to what happens** with most databases that are
configured to flush data to disk every second, so it is a scenario you
are already able to reason about because of past experiences with traditional
database systems not involving distributed systems. Similarly you can
improve consistency by forcing the database to flush data on disk before
replying to the client, but this usually results into prohibitively low
performance. That would be the equivalent of synchronous replication in
the case of Redis Cluster.

Basically there is a trade-off to take between performance and consistency.

Redis Cluster has support for synchronous writes when absolutely needed,
implemented via the `WAIT` command, this makes losing writes a lot less
likely, however note that Redis Cluster does not implement strong consistency
even when synchronous replication is used: it is always possible under more
complex failure scenarios that a slave that was not able to receive the write
is elected as master.

There is another notable scenario where Redis Cluster will lose writes, that
happens during a network partition where a client is isolated with a minority
of instances including at least a master.

Take as an example our 6 nodes cluster composed of A, B, C, A1, B1, C1,
with 3 masters and 3 slaves. There is also a client, that we will call Z1.

After a partition occurs, it is possible that in one side of the
partition we have A, C, A1, B1, C1, and in the other side we have B and Z1.

Z1 is still able to write to B, that will accept its writes. If the
partition heals in a very short time, the cluster will continue normally.
However if the partition lasts enough time for B1 to be promoted to master
in the majority side of the partition, the writes that Z1 is sending to B
will be lost.

Note that there is a **maximum window** to the amount of writes Z1 will be able
to send to B: if enough time has elapsed for the majority side of the
partition to elect a slave as master, every master node in the minority
side stops accepting writes.

This amount of time is a very important configuration directive of Redis
Cluster, and is called the **node timeout**.

After node timeout has elapsed, a master node is considered to be failing,
and can be replaced by one of its replicas.
Similarly after node timeout has elapsed without a master node to be able
to sense the majority of the other master nodes, it enters an error state
and stops accepting writes.

## Creating a new cluster 
wget http://download.redis.io/redis-stable.tar.gz
tar xvzf redis-stable.tar.gz
cd redis-stable
make
make install
cd /root/redis-stable/utils/create-cluster
./create-cluster start
./create-cluster create
```
>>> Performing hash slots allocation on 6 nodes...
Master[0] -> Slots 0 - 5460
Master[1] -> Slots 5461 - 10922
Master[2] -> Slots 10923 - 16383
Adding replica 127.0.0.1:30005 to 127.0.0.1:30001
Adding replica 127.0.0.1:30006 to 127.0.0.1:30002
Adding replica 127.0.0.1:30004 to 127.0.0.1:30003
>>> Trying to optimize slaves allocation for anti-affinity
[WARNING] Some slaves are in the same host as their master
M: 1552eb85bfede2e0cea00a06d1934aa54610b13d 127.0.0.1:30001
   slots:[0-5460] (5461 slots) master
M: 4f78390a5259048c18257f553b001617d6d6ef58 127.0.0.1:30002
   slots:[5461-10922] (5462 slots) master
M: 7a3bd800f4145bddefdd293ab0ea5789d6d16700 127.0.0.1:30003
   slots:[10923-16383] (5461 slots) master
S: 35cbb2635ea17d40ea4c6b16842f191b014ef9f9 127.0.0.1:30004
   replicates 7a3bd800f4145bddefdd293ab0ea5789d6d16700
S: 556a95431cb2eb84431b884c67e80d5edabee8e2 127.0.0.1:30005
   replicates 1552eb85bfede2e0cea00a06d1934aa54610b13d
S: 91a2b4fc132cb0f4f134d33b2482cf34c71346f7 127.0.0.1:30006
   replicates 4f78390a5259048c18257f553b001617d6d6ef58
   ```

redis-cli -p 30001 cluster slots
```
1) 1) (integer) 10923
   2) (integer) 16383
   3) 1) "127.0.0.1"
      2) (integer) 30003
      3) "7a3bd800f4145bddefdd293ab0ea5789d6d16700"
   4) 1) "127.0.0.1"
      2) (integer) 30004
      3) "35cbb2635ea17d40ea4c6b16842f191b014ef9f9"
2) 1) (integer) 5461
   2) (integer) 10922
   3) 1) "127.0.0.1"
      2) (integer) 30002
      3) "4f78390a5259048c18257f553b001617d6d6ef58"
   4) 1) "127.0.0.1"
      2) (integer) 30006
      3) "91a2b4fc132cb0f4f134d33b2482cf34c71346f7"
3) 1) (integer) 0
   2) (integer) 5460
   3) 1) "127.0.0.1"
      2) (integer) 30001
      3) "1552eb85bfede2e0cea00a06d1934aa54610b13d"
   4) 1) "127.0.0.1"
      2) (integer) 30005
      3) "556a95431cb2eb84431b884c67e80d5edabee8e2"
   ```
 
 The `redis-cli` utility in the unstable branch of the Redis repository at GitHub implements a very basic cluster support when started with the `-c` switch
   
redis-cli -c -h localhost -p 30001
```
localhost:30001> SET hello world
OK
localhost:30001> SET foo bar
-> Redirected to slot [12182] located at 127.0.0.1:30003
OK
127.0.0.1:30003>
127.0.0.1:30003> GET foo
"bar"
127.0.0.1:30003> GET hello
-> Redirected to slot [866] located at 127.0.0.1:30001
"world"
127.0.0.1:30001>
```
localhost:30001> CLUSTER NODES
```
7a3bd800f4145bddefdd293ab0ea5789d6d16700 127.0.0.1:30003@40003 master - 0 1554361697988 3 connected 10923-16383
4f78390a5259048c18257f553b001617d6d6ef58 127.0.0.1:30002@40002 master - 0 1554361697087 2 connected 5461-10922
556a95431cb2eb84431b884c67e80d5edabee8e2 127.0.0.1:30005@40005 slave 1552eb85bfede2e0cea00a06d1934aa54610b13d 0 1554361697388 5 connected
91a2b4fc132cb0f4f134d33b2482cf34c71346f7 127.0.0.1:30006@40006 slave 4f78390a5259048c18257f553b001617d6d6ef58 0 1554361697087 6 connected
35cbb2635ea17d40ea4c6b16842f191b014ef9f9 127.0.0.1:30004@40004 slave 7a3bd800f4145bddefdd293ab0ea5789d6d16700 0 1554361697000 4 connected
1552eb85bfede2e0cea00a06d1934aa54610b13d 127.0.0.1:30001@40001 myself,master - 0 1554361696000 1 connected 0-5460
```
## Manual failover

Sometimes it is useful to force a failover without actually causing any problem on a master. That must be executed in one of the **slaves** of the master you want to failover.

redis-cli -h localhost -p 30005
```
localhost:30005> CLUSTER FAILOVER
OK
localhost:30005> CLUSTER NODES
35cbb2635ea17d40ea4c6b16842f191b014ef9f9 127.0.0.1:30004@40004 slave 7a3bd800f4145bddefdd293ab0ea5789d6d16700 0 1554362622379 4 connected
7a3bd800f4145bddefdd293ab0ea5789d6d16700 127.0.0.1:30003@40003 master - 0 1554362622079 3 connected 10923-16383
556a95431cb2eb84431b884c67e80d5edabee8e2 127.0.0.1:30005@40005 myself,master - 0 1554362622000 7 connected 0-5460
4f78390a5259048c18257f553b001617d6d6ef58 127.0.0.1:30002@40002 master - 0 1554362622079 2 connected 5461-10922
91a2b4fc132cb0f4f134d33b2482cf34c71346f7 127.0.0.1:30006@40006 slave 4f78390a5259048c18257f553b001617d6d6ef58 0 1554362622079 6 connected
1552eb85bfede2e0cea00a06d1934aa54610b13d 127.0.0.1:30001@40001 slave 556a95431cb2eb84431b884c67e80d5edabee8e2 0 1554362622079 7 connected
```
## Removing a node to an existing Cluster
`CLUSTER FORGET` is used in order to remove a node, specified via its node ID.
Make sure to send CLUSTER FORGET to every single node in the cluster.
`CLUSTER FORGET 35cbb2635ea17d40ea4c6b16842f191b014ef9f9`


Links

https://codeflex.co/configuring-redis-cluster-on-linux/

http://pingredis.blogspot.com/2016/09/redis-cluster-how-to-create-cluster.html

https://redis.io/topics/cluster-tutorial

https://docs.bitnami.com/installer/apps/diaspora/administration/create-cluster/

https://community.pivotal.io/s/article/How-to-setup-HAProxy-and-Redis-Sentinel-for-automatic-failover-between-Redis-Master-and-Slave-servers

https://alex.dzyoba.com/blog/redis-cluster/

https://willwarren.com/2017/10/redis-cluster-cheatsheet/
