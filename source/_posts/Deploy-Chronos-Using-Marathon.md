---
title: Deploy Chronos using Marathon to achieve HA
date: 2016-04-28 22:10:18
tags: Chronos, Marathon, Mesos, Docker, Multi-Host Container Networking
category: DevOps, Infrastructure 
---

Chronos is a a mesos framework, which considered a distributed version of cron. It's a fault tolerant job scheduler that supports chained jobs (job dependent on another job/jobs), it supports ISO8601 based schedules.

![The chronos architecture](chronos_architecture.png)

To achieve HA, you can install chronos on every mesos master and connect them to zookeeper server for leader election and state caching. However, there're a few advantages to deploy Chronos through docker container using Marathon other than to install the package on the master nodes.

1. It's more flexible, you can deploy different version by just starting the Marathon app with a different docker image.
2. Marathon natively makes it highly available and resilient. It can survive machine failure and be kept "always" running.

But it's not natively possible to make it work. For a chronos framework to be functional, the chronos containers must be accessible from each other through the IP address, and must be accessible by all the master nodes. But let's say we deploy a 3-instance chronos application across 3 slave nodes, 1 instance per node, to achieve HA:
- Chronos instance A on slave 1
- Chronos instance B on slave 2
- Chronos instance C on slave 3

Now because they have seperated docker network, so it's impossible for them to access each other and because they're deployed on slaves, it's impossible for the masters to access them.

It calls for a multi-host container networking enabled setup of the mesos cluster. There're some technology to achieve it:
1. [Open vSwitch](http://openvswitch.org/)
2. [Calico](https://github.com/projectcalico/calico)
3. [Flannel](https://github.com/coreos/flannel)
3. [Weave](https://github.com/weaveworks/weave)
4. [Docker Overlay Network](https://docs.docker.com/engine/userguide/networking/get-started-overlay/)

This blog has a long series introducing Calio, Flannel, Weave and Docker Overlay Network and comparing them based on features and performances. The following table is the conclusion of the comparation, to read the details, go to [Battlefield: Calico, Flannel, Weave and Docker Overlay Network](http://chunqi.li/2015/11/15/Battlefield-Calico-Flannel-Weave-and-Docker-Overlay-Network/)

|                                     |          Calico         |        Flannel       |             Weave             |       Docker Overlay Network      |
|-------------------------------------|:-----------------------:|:--------------------:|:-----------------------------:|:---------------------------------:|
| Network Model                       | Pure Layer-3 Solution   | VxLAN or UDP Channel | VxLAN or UDP Channel          |               VxLAN               |
| Application Isolation               |      Profile Schema     |      CIDR Schema     |          CIDR Schema          |            CIDR Schema            |
| Protocol Support                    | TCP, UDP, ICMP & ICMPv6 |          ALL         |              ALL              |                ALL                |
| Distributed Storage Requirements    |           Yes           |          Yes         |               No              |                Yes                |
| Encryption Channel                  |            No           |          TLS         |          NaCl Library         |                 No                |
| Partially Connected Network Support |            No           |          No          |              Yes              |                 No                |
|     Separate vNIC for Container     |            No           |          No          |              Yes              |                Yes                |
|          IP Overlap Support         |            No           |         Maybe        |             Maybe             |               Maybe               |
| Container Subnet Restriction        |            No           |          No          | Yes, configurable after start | Yes, not configurable after start |

Personally I have tried to use Calico and Weave, I failed to get Calico work and succeed with Weave. According to the table, Weave has the best features 
