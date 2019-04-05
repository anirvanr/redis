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

## Creating a Redis Cluster using the create-cluster script
```bash
wget http://download.redis.io/redis-stable.tar.gz
tar xvzf redis-stable.tar.gz
cd redis-stable
make
make install
cd /root/redis-stable/utils/create-cluster
./create-cluster start
./create-cluster create

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

$ redis-cli -p 30001 cluster slots
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
   
$ redis-cli -c -h localhost -p 30001
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
localhost:30001> CLUSTER NODES

7a3bd800f4145bddefdd293ab0ea5789d6d16700 127.0.0.1:30003@40003 master - 0 1554361697988 3 connected 10923-16383
4f78390a5259048c18257f553b001617d6d6ef58 127.0.0.1:30002@40002 master - 0 1554361697087 2 connected 5461-10922
556a95431cb2eb84431b884c67e80d5edabee8e2 127.0.0.1:30005@40005 slave 1552eb85bfede2e0cea00a06d1934aa54610b13d 0 1554361697388 5 connected
91a2b4fc132cb0f4f134d33b2482cf34c71346f7 127.0.0.1:30006@40006 slave 4f78390a5259048c18257f553b001617d6d6ef58 0 1554361697087 6 connected
35cbb2635ea17d40ea4c6b16842f191b014ef9f9 127.0.0.1:30004@40004 slave 7a3bd800f4145bddefdd293ab0ea5789d6d16700 0 1554361697000 4 connected
1552eb85bfede2e0cea00a06d1934aa54610b13d 127.0.0.1:30001@40001 myself,master - 0 1554361696000 1 connected 0-5460
```
### Creating a Redis Cluster manually
In this section, a cluster with three masters will be created.
```
$ redis-server --port 5000 --cluster-enabled yes --cluster-config-file nodes-5000.conf --cluster-node-timeout 2000 --cluster-slave-validity-factor 10 --cluster-migration-barrier 1 --cluster-require-full-coverage yes --dbfilename dump-5000.rdb --daemonize yes

$ redis-server --port 5001 --cluster-enabled yes --cluster-config-file nodes-5001.conf --cluster-node-timeout 2000 --cluster-slave-validity-factor 10 --cluster-migration-barrier 1 --cluster-require-full-coverage yes --dbfilename dump-5001.rdb --daemonize yes

$ redis-server --port 5002 --cluster-enabled yes --cluster-config-file nodes-5002.conf --cluster-node-timeout 2000 --cluster-slave-validity-factor 10 --cluster-migration-barrier 1 --cluster-require-full-coverage yes --dbfilename dump-5002.rdb --daemonize yes
```
The cluster is not ready to run yet. We can check the cluster's health with the CLUSTER INFO command.
```
$ redis-cli -c -p 5000 CLUSTER INFO
cluster_state:fail
cluster_slots_assigned:0
cluster_slots_ok:0
cluster_slots_pfail:0
cluster_slots_fail:0
cluster_known_nodes:1
cluster_size:0
cluster_current_epoch:0
cluster_my_epoch:0
cluster_stats_messages_sent:0
cluster_stats_messages_received:0
```
The output of CLUSTER INFO tells us that the cluster only knows about one node (the connected node), no slots are assigned to any of the nodes, and the cluster state is fail.When the cluster is in the fail state, it cannot process any queries.

Next, the 16,384 hash slots are distributed evenly across the three instances. The configuration cluster-require-full-coverage is set to yes, which means that the cluster can process queries only if all hash slots are assigned to running instances:
```
$ redis-cli -c -p 5000 CLUSTER ADDSLOTS {0..5460}
$ redis-cli -c -p 5001 CLUSTER ADDSLOTS {5461..10922}
$ redis-cli -c -p 5002 CLUSTER ADDSLOTS {10923..16383}
```

Next, we are going to make all the nodes aware of each other. We will do this using the command CLUSTER MEET:
```
$ redis-cli -c -p 5000 CLUSTER MEET 127.0.0.1 5001
$ redis-cli -c -p 5000 CLUSTER MEET 127.0.0.1 5002
```
Run the command CLUSTER INFO to see that the cluster is up and running.
```
$ redis-cli -c -p 5000 CLUSTER NODES
b022a1de8d70f02b486a6f337dedb2f286b201ba 127.0.0.1:5002 master - 0 1554371348856 0 connected 10923-16383
a384db79274d15c6b4185070e3b96c55ce6e2c78 127.0.0.1:5001 master - 0 1554371348856 2 connected 5461-10922
956802b140f0e1789db2c521854c5dfb068bde62 127.0.0.1:5000 myself,master - 0 0 1 connected 0-5460

$ redis-cli -c -p 5000
127.0.0.1:5000> SET hello world
OK
127.0.0.1:5000> SET foo bar
-> Redirected to slot [12182] located at 127.0.0.1:5002
OK
```
Adding slaves/replicas:

There are three master nodes but no slaves. Thus, no data is replicated anywhere. This is not very safe. Data can be lost, and if any master has issues, the entire cluster will be unavailable (cluster-require-full-coverage is set to yes).
```
$ redis-server --port 5003 --cluster-enabled yes --cluster-config-file nodes-5003.conf --cluster-node-timeout 2000 --cluster-slave-validity-factor 10 --cluster-migration-barrier 1 --cluster-require-full-coverage yes --dbfilename dump-5003.rdb --daemonize yes
```

Introduce it to the current cluster using the command CLUSTER MEET:
`$ redis-cli -c -p 5003 CLUSTER MEET 127.0.0.1 5000`

Getting the node ID of the master that will be replicated using the command CLUSTER NODES
```
$ redis-cli -c -p 5003 CLUSTER NODES
b022a1de8d70f02b486a6f337dedb2f286b201ba 127.0.0.1:5002 master - 0 1554439429689 0 connected 10923-16383
a384db79274d15c6b4185070e3b96c55ce6e2c78 127.0.0.1:5001 master - 0 1554439429689 2 connected 5461-10922
956802b140f0e1789db2c521854c5dfb068bde62 127.0.0.1:5000 master - 0 1554439429689 1 connected 0-5460
0aa674dab686c6410ea2638c7e69aab8fbf67c66 127.0.0.1:5003 myself,master - 0 0 3 connected

$ redis-cli -c -p 5003 CLUSTER REPLICATE b022a1de8d70f02b486a6f337dedb2f286b201ba

$ redis-cli -c -p 5003 CLUSTER NODES
b022a1de8d70f02b486a6f337dedb2f286b201ba 127.0.0.1:5002 master - 0 1554439629163 0 connected 10923-16383
a384db79274d15c6b4185070e3b96c55ce6e2c78 127.0.0.1:5001 master - 0 1554439629264 2 connected 5461-10922
956802b140f0e1789db2c521854c5dfb068bde62 127.0.0.1:5000 master - 0 1554439629264 1 connected 0-5460
0aa674dab686c6410ea2638c7e69aab8fbf67c66 127.0.0.1:5003 myself,slave b022a1de8d70f02b486a6f337dedb2f286b201ba 0 0 3 connected
```
### Redis cluster live reshard
Check slot 866 located at 127.0.0.1:5000 before resharding
```
$ redis-cli -c -p 5001
127.0.0.1:5001> get hello
-> Redirected to slot [866] located at 127.0.0.1:5000
"world"
```

Generate 10 random key 
```bash
for i in {1..10} ; do redis-cli -c -p 5000 set key$i `head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo ''` ; done
```

Create a new Redis instance in cluster mode:
```
$ redis-server --port 6000 --cluster-enabled yes --cluster-config-file nodes-6000.conf --cluster-node-timeout 2000 --cluster-slave-validity-factor 10 --cluster-migration-barrier 1 --cluster-require-full-coverage yes --dbfilename dump-6000.rdb --daemonize yes
```

Introduce the node to the cluster:
```
$ redis-cli -c -p 6000 CLUSTER MEET 127.0.0.1 5000
```

Find the node IDs of the new node and the destination node
```
$ redis-cli -c -p 6000 CLUSTER NODES
...
865de4b342b04ed20ae7a6a4e60eb8f8f5f46bd4 127.0.0.1:6000 myself,master - 0 0 4 connected
956802b140f0e1789db2c521854c5dfb068bde62 127.0.0.1:5000 master - 0 1554442600741 1 connected 0-5460
...
```
Suppose you want to reshard some slots from a master node to other master node.  We'll call the node that has the current ownership of the hash slot the source node, and the node where we want to migrate the destination node.
Redis Cluster only supports resharding of one hash slot at a time.
If many hash slots have to be resharded, the following procedure needs to be executed once for each hash slot:

1. Send CLUSTER SETSLOT <slot> IMPORTING <source-node-id> to destination node to set the slot to importing state.
```
$ redis-cli -c -p 6000 CLUSTER SETSLOT 866 IMPORTING 956802b140f0e1789db2c521854c5dfb068bde62
```

2. Send CLUSTER SETSLOT <slot> MIGRATING <destination-node-id> to source node to set the slot to migrating state.
```
$ redis-cli -c -p 5000 CLUSTER SETSLOT 866 MIGRATING 865de4b342b04ed20ae7a6a4e60eb8f8f5f46bd4
```
3. Get keys from the source node with CLUSTER GETKEYSINSLOT command and move them into the destination node using the following MIGRATE command.
MIGRATE target_host target_port key target_database_id timeout

NOTE:
CLUSTER COUNTKEYSINSLOT <slot> returns the number of keys in a given slot.
CLUSTER GETKEYSINSLOT <slot><amount> returns an array with key names that belong to a slot based on the amount specified
```
$ redis-cli -c -p 5000
127.0.0.1:5000> CLUSTER COUNTKEYSINSLOT 866
(integer) 1
127.0.0.1:5000> CLUSTER GETKEYSINSLOT 866 1
1) "hello"
127.0.0.1:5000> MIGRATE 127.0.0.1 6000 hello 0 2000
```
4. Finally, all the nodes are notified about the new owner of the hash slot:
```
$ redis-cli -c -p 5000 CLUSTER SETSLOT 866 NODE 865de4b342b04ed20ae7a6a4e60eb8f8f5f46bd4 
$ redis-cli -c -p 5001 CLUSTER SETSLOT 866 NODE 865de4b342b04ed20ae7a6a4e60eb8f8f5f46bd4
$ redis-cli -c -p 5002 CLUSTER SETSLOT 866 NODE 865de4b342b04ed20ae7a6a4e60eb8f8f5f46bd4
$ redis-cli -c -p 6000 CLUSTER SETSLOT 866 NODE 865de4b342b04ed20ae7a6a4e60eb8f8f5f46bd4
```
The new assignment can be checked with CLUSTER NODES
```
$ redis-cli -c -p 6000 CLUSTER NODES
```

bash script to migrate all hash slots(0-5460) from master on port 5000 to master on port 6000
```bash
#!/bin/bash

for i in `seq 0 5460`; do
    redis-cli -c -p 6000 cluster setslot ${i} importing 956802b140f0e1789db2c521854c5dfb068bde62
    redis-cli -c -p 5000 cluster setslot ${i} migrating 865de4b342b04ed20ae7a6a4e60eb8f8f5f46bd4
    while true; do
        key=`redis-cli -c -p 5000 cluster getkeysinslot ${i} 1`
        if [ "" = "$key" ]; then
            echo "there are no key in this slot ${i}"
            break
        fi
        redis-cli -p 5000 migrate 127.0.0.1 6000 ${key} 0 2000
    done
    redis-cli -c -p 5000 cluster setslot ${i} node 865de4b342b04ed20ae7a6a4e60eb8f8f5f46bd4
    redis-cli -c -p 5001 cluster setslot ${i} node 865de4b342b04ed20ae7a6a4e60eb8f8f5f46bd4
    redis-cli -c -p 5002 cluster setslot ${i} node 865de4b342b04ed20ae7a6a4e60eb8f8f5f46bd4
    redis-cli -c -p 6000 cluster setslot ${i} node 865de4b342b04ed20ae7a6a4e60eb8f8f5f46bd4
done
```
Check slot 866 located at 127.0.0.1:6000 after resharding
```
$ redis-cli -c -p 5001
127.0.0.1:5001> get hello
-> Redirected to slot [866] located at 127.0.0.1:6000
"world"
127.0.0.1:6000>
```

Links

https://codeflex.co/configuring-redis-cluster-on-linux/

http://pingredis.blogspot.com/2016/09/redis-cluster-how-to-create-cluster.html

https://redis.io/topics/cluster-tutorial

https://docs.bitnami.com/installer/apps/diaspora/administration/create-cluster/

https://community.pivotal.io/s/article/How-to-setup-HAProxy-and-Redis-Sentinel-for-automatic-failover-between-Redis-Master-and-Slave-servers

https://alex.dzyoba.com/blog/redis-cluster/

https://willwarren.com/2017/10/redis-cluster-cheatsheet/
