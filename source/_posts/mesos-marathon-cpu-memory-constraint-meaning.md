---
title: CPU and Memory Resources in Mesos Marathon with Docker
date: 2016-05-24 17:34:18
tags: 
  - Marathon
  - Mesos
  - Docker
category: 
  - Infrastructure
---

I've been using Marathon for some time, running different dockerized apps managed by marathon on Mesos. But I has always been very uncertain about one thing, which is:

***What does the cpu, mem constraint mean in the apps, when you tell marathon to create them, except from telling marathon to pick up offers accordingly from slaves?***

It's very important to understand this in order to make sure that resources are allocated properly. Unfortunately I cannot find any documentation about it anywhere, so I have to investigate it on my own. The following questions are what I want to find out:
1. When you set the cpu constraint for marathon app, what does it do?
2. How do the Docker containers started by marathon on the same slave use the CPU?
3. When you set the mem constraint for marathon app, what does it do?
4. How do the Docker containers started by marathon on the same slave use the memory? 

I already have a Mesos cluster and marathon framework running. So I started two applications and make them run on the same slave by setting the constraints.
```
{
    "cpus": 0.1,
    "mem": 128,
    "instances": 1,
    "constraints": [["id", "CLUSTER", "slave-2"], ["id", "UNIQUE"]]
}
```
Notice that I gave each of them 0.1 cpu and 128m RAM. So theorically each application will only be able to access 0.1 process power of cpu and 128 memory. After the apps are alive, I generated some fake traffic for them using [wrk](https://github.com/wg/wrk), and here's the metric:

![The CPU and Memory Usage](cpu_memory_usage.png)

We can see very clearly that both of the applications exceeded the 10% CPU limitation assigned by marathon. This means that the cpu constraint/setting we specify in marathon does not mean the actually cpu resource the app're limited at. In the mean time, we can see that memory usage is always capped at the limit, which is co-related to the mem constraint set in marathon. This means that the mem constraint/setting we specify in marathon does reflect the memory resource the app're limited at.

### The cpu constraint/settings
Now if the cpu constraint doesn't mean what it seems to, what is it? We need to see what happens when an app is created. When creating an app, Marathon accpets an offer from a mesos slave, and then mesos asks the mesos slave to run a docker container of the app. Mesos now converts the cpu constraint/setting into a value for Docker's "--cpu-shares" setting according to mesos source code at https://github.com/apache/mesos/blob/master/src/docker/docker.cpp:
```C++
if (resources.isSome()) {
    Option<double> cpus = resources.get().cpus();
    if (cpus.isSome()) {
      uint64_t cpuShare =
        std::max((uint64_t) (CPU_SHARES_PER_CPU * cpus.get()), MIN_CPU_SHARES);
      argv.push_back("--cpu-shares");
      argv.push_back(stringify(cpuShare));
    }
  }
```
We can verify by checking the docker process running or we can using docker inspect to inspect the property of the container:
```
docker -H unix:///var/run/weave/weave.sock run --cpu-shares 102
```
So, what is cpu-share option in docker run? According to [Docker's documentation](https://docs.docker.com/engine/reference/run/#cpu-share-constraint), it's only a weight value defining the cpu share priority among all the running containers. e.g. if container A has a priority of 0.2 and B has a priority of 0.1, and now all of them are trying to use 100% of the CPU at the same time, then A will receive 66% and B will receive 33% of the CPU time. In our case, each of the application's container receives a CPU share of 1024*0.1=102.

Another usage of cpu constraint is more obvious -- to "eat up" the slave's cpu resource so that only limited number of applications can be run on the same slave. If an app that takes 0.1 cpu is running on slave A, which has 1 cpu in total, then it has only 0.9 left over to offer, if you now want to run another app with a constraint of 1 cpu, you won't be able to run it on slave A.

Here we should be able to answer the first two questions:
1. The cpu constraint is used to set the cpu share weight/priority for the application on the slave, it defines how the apps(containers) will share the cpu time.
2. The cpu constraint is used to "select" offers from slaves and "reserve" the resource on selected slave.

### The mem constraint/settings
Again look at the [mesos source code](https://github.com/apache/mesos/blob/master/src/docker/docker.cpp):
```C++
Option<Bytes> mem = resources.get().mem();
    if (mem.isSome()) {
      Bytes memLimit = std::max(mem.get(), MIN_MEMORY);
      argv.push_back("--memory");
      argv.push_back(stringify(memLimit.bytes()));
    }
```
We can see that the mem constraint/settings is converted to "--memory" setting of Docker run. I can verify it by showing the docker run processes:
```
docker -H unix:///var/run/weave/weave.sock run --memory 134217728
```
and 134217728 byte is equal to 128 MB. According to [Docker's documentation](https://docs.docker.com/engine/reference/run/#user-memory-constraints), it defines the memory the container can use up to. Different from cpu, mem constraint means exactly what it seems to mean.

Other than this, the same as cpu, this constraint is also used to "eat up" slave's resouce so that only limited number of applications can be run on the same slave. If an app that takes 128MB RAM is running on slave A, which has 1G available in total, then it has only 896MB RAM left, if you now want to run another app with a contraint of 1GB RAM, you won't be able to run it on slave A.

So we should be able to answer the last two questions:
1. The mem constraint is used to set the max memory the application can use on the slave.
2. The mem constraint is used to "select" offers from slaves and "reserve" the resource on selected slave.

### Conclusion

The mem constraint is quite straightforward, just plan it carefully and make sure that your application will not use more memory than you planned.

On the contrary, the cpu constraint is very misleading, it should be called the cpu-weight instead as it's only a priority of cpu share rather than really constraining your to use only a percentage of the CPU. Knowing what exactly it does, I soon realized that setting the right cpu value becomes very tricky:
* If you set the value very low, like 0.1 cpu for example. You risk over-allocating resources on the slaves. You can end up having many tasks running on the same slave, but all of them suffering from low CPU time.
* If you set the value very high, like 2 cpu for example. You risk under-allocating resources on the slaves. You may end up having only 1 or 2 tasks running on the same slave, but the CPU is most of the time IDLE. It can become even worse: you can't find resources to run new tasks because two many of the CPUs are already "reserved".

Anyway, after the research I'm able to answer the questions I had in my mind, but the funny thing is that now here come a even bigger problem: how to find a way to set the constraints properly in order to achieve the best resource allocation?

