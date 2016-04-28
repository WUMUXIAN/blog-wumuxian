---
title: Getting Started with Mesos on AWS Linux AMI instances with Ansible
date: 2016-04-25 11:45:36
tags: Mesos, Ansible, AWS Linux AMI
category: DevOps, Infrastructure
---

I've been trying to use Mesos for a while since I first heard of it from my friend. As a beginner of using it myself, I hope this article can help those who are new to mesos but interested to get started with it on AWS cloud. I will cover the following two topics in this article.

**1. What's mesos and why use it?**
**2. How to deploy a full mesos cluster on AWS EC2 instance running AWS Linux AMI using Ansible.**

## What's mesos?

{% blockquote Apache Mesos http://mesos.apache.org/ %}
Program against your datacenter like it's a single pool of resources
{% endblockquote %}

The above is how the mesos website describes it. Mesos is all about resource abstraction and isolation, it is a cluster management tool that abstracts CPU, memory, storage and ports and enabling easy building and running of fault-tolerant and elastic distributed systems. There're many features but I think the following 4 are the most important that make it great.
1. Scalability to 10,000s of nodes.
2. High availability.
3. Docker support.
4. API supports for developing new frameworks/applications, an ecosystem is emerging.

The figure below shows the architecture of an full mesos cluster. 

{% asset_img architecture.jpg The mesos cluster architecture %}

Mesos runs with master/slave paradigm, masters act as schedulers and slaves act as executors. Zookeeper is used to do leader election and save the state to achieve fault tolerant and high availablility. 

Mesos works by sending offers to running frameworks. A framework consists of a scheduler that runs on the master to be offered resources and a executor process that is executed on slave nodes to run the framework's tasks. The master will decide how many resources are offered to each framework, the framework's scheduler will decide which of the offered resources to use. When a framework accepts an offer, the tasks will be launched on the corresponding slaves that reported the resouces. I'll go through a typic process step-by-step so that it's easier to understand:

1. Slave N reports to master that it has X CPUS, X GB of memory and so on.
2. The master sends a resource offer describing what is available on slave N to framework A.
3. Framework A's scheduler finds out the offer satisfies the requirement, and it repiles to the master that it accepts the offer and will run 2 tasks on slave N.
4. The master send the tasks to slave N, and allocate appropriate resources to the executor, which in turn launches the two tasks. The slave will now update it's remaining resources and reports to master.
5. Repeat.

Frameworks will reject offers that doesn't match it's requirements. Taking advantage of this, we're about to give some constraints to achieve certain things such as ensure locality.

The above is just a short description about what mesos is trying to give a first impression for beginners, there're still many other advanced features and other run time configurations, to see more concrete documentations you can go http://mesos.apache.org/documentation/latest/.


## Why mesos?

After reading all these about mesos, you might be wondering already, why would I use it? Personally I can only think of the following possible use cases that you might benefit from using Mesos.
1. Run all of your services in the same cluster instead of dedicated clusters for each of them.
2. Run different maturity/version applications in the same cluster with full isolation.
3. Simplify usage of distributed applications via mesos frameworks such as hadoop, spark and elastic search.
4. Act as a mature orchestrator for docker containers.
5. Improve resource utilization efficiency.
6. Preemption: prioritize high priority tasks and kill low priority tasks when resources are needed.
7. Cocolate batch jobs and long-live services in the same cluster.
8. A matching cluster management and scheduling tool for microservices infrastructure paradigm.

As a beginner I haven't personally experienced  all of these benefits yet from mesos but I started to feel the advantages of using it. In my own case, I've put my spark batch jobs and my long live services in the same cluster and share the resources. I've deployed serval microservices on the same cluster with only necessary resource allocation when they're still under POC or staing. Without mesos, I would have to privision additional machines to just test things out, wasting 90% of the resources being idle and not used. Another benefit that I experienced is flexibility, e.g. I can easily run Spark 1.4 and Spark 1.6 on the same mesos cluster cocurrently without a clash, I can do blue green deployment of a service with Marathon to achieve 0 downtime. 

Having listed so many advantages of mesos, there're also some price you have to pay for using it. First of all, if your are not using more than 10 nodes and not running multiple microserives at the same time, you might find mesos useless or overwhelming. Secondly, adopting mesos means you have to spend time getting farmiliar with it, but the documentation of it really sucks. Thirdly, you have to dockerize your application whenever possible to unlock the most of the mesos power, even though mesos can run native processes, it's fragile and cumbersome as all slaves must have the executable and the environment/dependencies configured to run it.

There're also some known problems in mesos, one being that the scaling of services is in the framework level but not node level. Thus a node level scaling mechanism is on demand to scale up nodes when resources of the cluster is being used up and scale down nodes when resources are not being used. Another problem is that Mesos doesn't provide DNS functionality, you have to use your own service discovery tool to exposes services running on mesos. There may be other problems as well but regardless of these, it's still a morden and battle tested technology that becomes more and more popluar.

## Deploy mesos to AWS EC2 running AWS Linux AMI using Ansible

Now let's get our hands dirty. Actually there're many other formal open sourced project that focuses on deploying Mesos to VMs or to the cloud, such as 
- [Mantl.io](http://mantl.io/) for deploying mesos on centos 7.
- [Playa Mesos](https://github.com/mesosphere/playa-mesos) for deploying mesos on ubuntu. 
- [DC/OS](https://dcos.io/) for deploying mesos on coreos.

However, there isn't a tool that caters for AWS Linux AMI. AWS Linux is based on centos 6 but highly customized, optimized and mantained by AWS. Personally I feel it the best within the AWS world, thus it's always my first choice when firing up EC2 instances. So here comes the problem, all the existing tools doesn't work straightforward for it. I chose to do it on my own using [Ansible](https://www.ansible.com/), an IT automation tool that can be used to provision infrasturces.If you don't know about Ansible yet, please check https://www.ansible.com/ and get farmilar with it first， though it's not necessary to get this running. The code for this article is open sourced on github at https://github.com/WUMUXIAN/microservices-infra, and there's no other dependency but git and ansible. Make sure you have them installed on your working machine.

### Let's get started

The first step would be getting the instances up and ready, to fully automate the process, this can actually be done by [Terraform](https://www.terraform.io/) to provision the instances and create dynamic ansible inventory, but here I don't cover that. I assume that you already started the instances within the same subset and they're accessible to each other from all ports (this is a must that all machines are accessible through their private IP address）. In my case, I created 6 instances with 3 masters and 3 slaves, you can decide how many on your own. Now you can get the cluster up in 5 steps:

**Step One:** Check out the code
```bash
git clone https://github.com/WUMUXIAN/microservices-infra.git
cd microservices-infra/aws
```

**Step Two:** Modify the **inventory** file located in the folder according to your instances allocations.
```
[mesos-master]
mesos-master1
mesos-master2
mesos-master3

[mesos-slave]
mesos-slave1
mesos-slave2
mesos-slave3

[all:children]
mesos-master
mesos-slave
```

**Step Three:** Define the host variables in the **host_vars** folder, for each host, copy the private ip from AWS and define it as private_ipv4:
```
private_ipv4: xx.xx.xx.xx
```

**Step Four:** Copy your pem key file to the directory and rename it to **key.pem**.

**Step Five:** Run the deployment:
```bash
ansible-playbook -v mesos.yml
```

**Optional**: Make your working machine access the nodes easier by registering hosts and configure ssh.
```bash
ansible-playbook -v --ask-become-pass -e user_name=$(whoami) local.yml
```

The provisioning will take a few minutes to finish depending on how many machines you're provisioning. When ansible finishes, you will have a full mesos cluster up and running with Marathon and Chronos frameworks installed. Access the web UIs to verify and play with it, note that you have to open these ports in your security group before you can access:
- Mesos: http://mesos-master1:5050
- Marathon: http://mesos-master1:8080

### Reveal the dirty work

#### The mesos.yml playbook
```
---

- hosts: all
  gather_facts: yes
  roles:
    - common
    - docker

- hosts: mesos-master
  vars:
    mesos_mode: master
  roles:
    - zookeeper
    - mesos
    - marathon

- hosts: mesos-slave
  vars:
    mesos_mode: slave
  roles:
    - mesos
```
The ansible playbook scripts are organized by roles, we play the common and docker role on all nodes, play zookeeper, mesos and marathon role on master nodes and play only mesos role on mesos slaves. We also set the variable mesos_mode respective, which will be used within the mesos role to distingish mesos master and mesos slave.

#### The common role
This role does the following things:
1. Configure the system (time, yum timeout, yum repo, firewalls, ulimit and etc)
2. Install necessary softwares (java, supervisor, utilities softwares)
3. Configured syslog for mesos.

#### The docker role
This role installs docker and configure it. Because AWS Linux is based on centos 6, and the docker supports only up to 1.7 on centor 7. I have to use a workaroud to install docker 1.9.0 by replacing the binary. (1.9.0 above is required for some advanced features such as networking)
```
- name: download docker 1.9.0 and replace 1.7.1
  become: yes
  become_method: sudo
  get_url: url=https://get.docker.com/builds/Linux/x86_64/docker-1.9.0 dest=/usr/bin/docker force=yes
  tags:
    - docker
```
#### The zookeeper role
Zookeeper is used to make the cluster HA, Mesos uses it for leader election and state caching. Configure the zookeeper like this:
```
maxClientCnxns=200
tickTime=2000
initLimit=100
syncLimit=5
dataDir=/var/lib/zookeeper
clientPort=2181
{% for host in groups['mesos-master'] %}
server.{{ loop.index }}={{ hostvars[host].private_ipv4 }}:2888:3888
{% endfor %}
```

#### The mesos role
This role installs mesos master or mesos slave on the nodes, depending on the variable mesos_mode, because I have 3 masters, I set the quorum to 2 to have the best HA. For the slaves I do the following things:
1. Add attributes slave-x for future use.
2. Added docker to the containerizers.
3. Customize resoucres to have a wider range of ports

The above is only to highlight some key points of the playbook, I can't go through every insides. You can always look into the source code for details and play with it as you like.

### Conclusion

This articles give a short introduction to Mesos Cluster and aims to provide a workable deployment solution for those who wants to deploy mesos to EC2 instances running with AWS Linux AMI. If you find any errors or you have any recommendations to improve things, please feel free to contact, my email is at the bottom of this page.

