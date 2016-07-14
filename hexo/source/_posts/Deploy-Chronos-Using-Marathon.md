---
title: Deploy Chronos using Marathon to achieve HA
date: 2016-04-28 22:10:18
tags: 
  - Chronos
  - Marathon
  - Mesos
  - Docker
  - Multi-Host Container Networking
category: 
  - DevOps
---

Chronos is a a mesos framework, which considered a distributed version of cron. It's a fault tolerant job scheduler that supports chained jobs (job dependent on another job/jobs), it supports ISO8601 based schedules.

![The chronos architecture](chronos_architecture.png)

To achieve HA, you can install chronos on every mesos master and connect them to zookeeper server for leader election and state caching. However, there're a few advantages to deploy Chronos through docker container using Marathon other than to install the package on the master nodes.

1. It's more flexible, you can deploy different version by just starting the Marathon app with a different docker image.
2. Marathon natively makes it highly available and resilient. It can survive machine failure and be kept "always" running.

But it's not natively possible to make it work. For a chronos framework to be functional, the chronos nodes must be accessible from each other through the IP address, and must be accessible by all the master nodes. Now let's say we deploy a 3-instance chronos application across 3 slave nodes, 1 instance per node, to achieve HA:
- Chronos instance A on slave 1
- Chronos instance B on slave 2
- Chronos instance C on slave 3

As each node has their seperated docker network, so it's impossible for slave 1's chronos instance A to access other instances B and C on slave 2 and 3, and vice versa. In this case, even the chronos application is running, the chronos framework won't be registered successfully with mesos. I believe I am not the first and only person who encountered this problem, and luckily there's solution for it.

To solve the problem, a multi-host container networking enabled setup of the mesos cluster is required, in which case the docker containers will be in the same **virtual network**, thus even they're on different hosts, they can be accessed by each other. There're a few existing technologies to enable multi-host container networking:
1. [Open vSwitch](http://openvswitch.org/)
2. [Calico](https://github.com/projectcalico/calico)
3. [Flannel](https://github.com/coreos/flannel)
3. [Weave](https://github.com/weaveworks/weave)
4. [Docker Overlay Network](https://docs.docker.com/engine/userguide/networking/get-started-overlay/)

There is a blog writing a long series introducing Calio, Flannel, Weave and Docker Overlay Network and comparing them based on features and performances. The following table is the conclusion of the comparation, to read the details, you can go to the original blog at [Battlefield: Calico, Flannel, Weave and Docker Overlay Network](http://chunqi.li/2015/11/15/Battlefield-Calico-Flannel-Weave-and-Docker-Overlay-Network/)

|                                     |          Calico         |        Flannel       |             Weave             |       Docker Overlay Network      |
|-------------------------------------|:-----------------------:|:--------------------:|:-----------------------------:|:---------------------------------:|
|            Network Model            | Pure Layer-3 Solution   | VxLAN or UDP Channel |     VxLAN or UDP Channel      |               VxLAN               |
|        Application Isolation        |      Profile Schema     |      CIDR Schema     |          CIDR Schema          |            CIDR Schema            |
|          Protocol Support           | TCP, UDP, ICMP & ICMPv6 |          ALL         |              ALL              |                ALL                |
|   Distributed Storage Requirements  |           Yes           |          Yes         |               No              |                Yes                |
|         Encryption Channel          |            No           |          TLS         |          NaCl Library         |                 No                |
| Partially Connected Network Support |            No           |          No          |              Yes              |                 No                |
|     Separate vNIC for Container     |            No           |          No          |              Yes              |                Yes                |
|          IP Overlap Support         |            No           |         Maybe        |             Maybe             |               Maybe               |
|    Container Subnet Restriction     |            No           |          No          | Yes, configurable after start | Yes, not configurable after start |

Personally I have tried to use Calico and Weave before. The first choice of mine is Calico, as [Cisco Mantl](http://mantl.io/) selects it as their multi-host container networking solution. However, after a 2 days experimentation, I failed to get it to work properly. And that's when I started to look for other solutions and found the above information. Apparently weave holds at list two advantages over Calico:
1. Weave doesn't have any dependencies, but Calico requires a distributed K/V store like etcd
2. Weave is the richer in features than Calico

The following graph shows how weave network looks like
![](weave_network.png)

I switch to weave and was able to get it working in a shorter time, it's much cleaner and simpler compared to Calico.

## Set up Weave Net on your mesos cluster

I have open sourced the scripts on my github, download the code and run the following code to install weave net:
```shell
git clone https://github.com/WUMUXIAN/microservices-infra.git
cd microservices-infra/aws
ansible-playbook -v weave.yml
```
**Note: this assumes that you already set up your key.pem and modified the inventory file, refer to my previous [post](http://blog.wumuxian1988.com/2016/04/25/Deploy-Mesos-Cluster-on-AWS-Linux-using-Ansible/) for details**

They following are some key configurations you have to do with weave and your system to get it working properly:

1. Enable packet forwarding on the nodes to allow weave net to work:
```
- name: enable kernel packet forwarding
  become: yes
  become_method: sudo
  sysctl:
    name: net.ipv4.ip_forward
    value: 1
    state: present
    reload: yes
  tags:
    - weave
```

2. Specify peers when starting weave:
```
WEAVE_PEERS="{%- for host in groups['mesos'] -%}{%- if host != inventory_hostname -%}{{ hostvars[host].private_ipv4 }} {% if loop.last %}
        
{% endif %}
{%- endif -%}
{%- endfor -%}"
```

3. Dont use weave proxy for docker by default:
```
WEAVEPROXY_OPTIONS="--rewrite-inspect --no-default-ipalloc"
```

4. You have to configure your mesos slaves to use weave's docker socket.
Weave works for docker by proxying docker's socket using it's own. In order to let marathon deployed apps on mesos slave use weave's socket instead of the default one, you have to pass the following paramenter to mesos slave when starting it:
```
--docker_socket=/var/run/weave/weave.sock
```

After the installation and configuration, on each node you should see that weave and weave proxy are running:
```shell
ps aux | grep weave

root     28108  0.1  1.0 396860 41864 ?        Ssl  Apr28   2:40 /home/weave/weaver --port 6783 --name 42:28:7a:03:42:bb --nickname xx-xx-xx-xx-xx --datapath datapath --ipalloc-range 10.32.0.0/12 --dns-effective-listen-address 172.17.42.1 --no-dns --http-addr 127.0.0.1:6784 --no-dns xx.xx.xx.xxx xx.xx.xx.xxx xx.xx.xx.xxx xx.xx.xx.xxx xx.xx.xx.xxx
root     28933  0.0  0.1  11316  6384 ?        Ssl  Apr28   0:59 /home/weave/weaveproxy --rewrite-inspect --no-default-ipalloc -H unix:///var/run/weave/weave.sock
```

## Deploy Chronos using Marathon
Now you can try deploying Chronos again by marathon, in this case, 3 instances and unique on each node.
```
{
    "id": "chronos",
    "instances": 3,
    "cpus": 0.1,
    "mem": 256,
    "container": {
        "type": "DOCKER",
        "docker": {
            "image": "{{ chronos_image_name }}:{{ chronos_image_tag }}",
            "network": "BRIDGE",
            "portMappings": [
                {"containerPort":{{ chronos_port }}, "hostPort": 0, "servicePort": 0, "protocol":"tcp"}
            ]
        }
    },
    "constraints": [["hostname", "UNIQUE"]],
    "cmd": "/usr/bin/chronos run_jar --master zk://{% for host in groups['mesos-master'] %}{{ hostvars[host].private_ipv4 }}:2181{% if not loop.last %},{% endif %}{% endfor %}/mesos --zk_hosts {% for host in groups['mesos-master'] %}{{ hostvars[host].private_ipv4 }}:2181{% if not loop.last %},{% endif %}{% endfor %} --http_port {{ chronos_port }} --hostname $(hostname -i)",
    "env": {
      "WEAVE_CIDR": "net:10.32.1.0/24"
    },
    "healthChecks": [
      {
        "protocol": "HTTP",
        "portIndex": 0,
        "path": "/ping",
        "gracePeriodSeconds": 5,
        "intervalSeconds": 20,
        "maxConsecutiveFailures": 3
      }
    ]
}

```
As said above, we applied a configuration to not enable weave for containers by default, because most services won't require this feature. So to explicitly enable weave, you have to set the following environment variable in the marathon app:
```
"WEAVE_CIDR": "net:10.32.1.0/24"
```
For now you already made the chronos docker containers in the same virtual network and accessible from each other. In addition, you have to enable the master nodes to access the chronos instances, to achieve it you have to expose the CIDR you specified to the master nodes by running:
```shell
weave expose net:10.32.1.0/24
```

## Verify chronos is running and the framework is registered properly.
![](mesos_task_chronos.png)
![](mesos_framework_chronos.png)

## Restart Marathon managed Chronos framework properly
To do a simple restart, you only need to destroy the marathon app and restart it after, in this way the framework and all the jobs you created in chronos will remain the same. However, sometime things may screw up and you want to purge the framework as well as the jobs, in this case, you'll have to tell mesos to teardown the framework and tell zookeeper to remove all chronos records.

To cut the story short, the following is the script I wrote to restart chronos framework.
```bash
#!/bin/bash

cd ..
if [[ $# == 0 ]]; then
    echo "Usage:
            . restart_chronos.sh --maintain                Restart chronos with the jobs maintained
            . restart_chronos.sh --purge framework_id      Restart chronos as a new framework with the jobs purged"
else
    ansible mesos-master1 -m pip -b -a "executable=/usr/local/bin/pip name=httplib2 state=present"
    ansible mesos-master1 -m uri -b -a "url=http://localhost:8080/v2/apps/chronos method=DELETE HEADER_Content-Type='application/json'"
    if [[ $# == 2 ]] && [[ "$1" == "--purge" ]]; then
	    postBody=`echo frameworkId=$2`
	    echo $postBody
        ansible mesos-master1 -m command -b -a "/usr/lib/zookeeper/bin/zkCli.sh rmr /chronos"
        ansible mesos-master1 -m uri -b -a "body='$postBody' method=POST url=http://leader.mesos.service.consul:5050/master/teardown"
    fi
	ansible-playbook -vv infra.yml --tags "chronos"
fi
cd bin
```
So you run with maintain mode to restart it without affecting anything
```bash
cd bin/
. restart_chronos.sh --maintain
```

or you run with purge mode to purge everything and start freshly
```bash
cd bin/
. restart_chronos.sh --purge framework_id
```

## What's next
Now we're able to deploy chronos through Marathon by enabling multi-host container networking on the mesos cluster using Weave, but it's not the end of the story yet. You will find out that you can't access chronos by the host name displayed in the framework page, because it's an internal address in the weave's virtual network. Also each chronos container is exposed on a different port, which is dynamic, it's very troublesome to access. Actually this exposes a general problem faced by any apps deployed through Marathon: you have a persistent domain to access the apps and be able to load balance the traffic, and this calls for a reverse proxy and load balancing tool to sit in the front. 

There's some existing technologies to achieve the goal, such as HAProxy and Traefik. In next post I will introduce how to deploy Treafik to expose the marathon deployed apps to external world in details.