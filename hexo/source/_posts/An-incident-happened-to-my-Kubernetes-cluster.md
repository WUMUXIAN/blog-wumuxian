---
title: An incident happened to my Kubernetes cluster
date: 2018-09-11 13:33:46
tags:
 - Kubernetes
 - Docker
category:
 - Devops
---

Ever since the first time my Kubernetes is spinned up, it's been running smoothly without problems for 3 months. However yesterday suddenly I find that the `dashboard` endpoint stops working, even though I'm still able to use `kubectl apply` to rolling update my services.

I started the investigation with `kubelet get nodes`, and it tells me this:

```
NAME                            STATUS    ROLES     AGE       VERSION
xxxxxxxxxxxxxxxxxxxxxxxxxxx     Ready     master    103d      v1.9.3
xxxxxxxxxxxxxxxxxxxxxxxxxxx     NotReady  master    103d      v1.9.3
xxxxxxxxxxxxxxxxxxxxxxxxxxx     Ready     node      98d       v1.9.3
xxxxxxxxxxxxxxxxxxxxxxxxxxx     Ready     master    103d      v1.9.3
xxxxxxxxxxxxxxxxxxxxxxxxxxx     Ready     node      84d       v1.9.3
```

It looks that one of the node is out of reach somehow, then I tried to describe the node using:

```
kubectl describe node/node-name
```

It ended up with a timeout, it looks like the node is totally out of reach. I had to ssh to the instance itself to find out more.

### The instance

Once I ssh into the machine, the first thing I notice is that the machine is irresponsive, I checked the CPU and memory usage using `htop`, however CPU and memory looks good. Next suspect is disk, so I ran:

```
df -h

Filesystem      Size  Used Avail Use% Mounted on
udev            3.8G     0  3.8G   0% /dev
tmpfs           770M  3.0M  767M   1% /run
/dev/nvme0n1p2   60G   60G    0G 100% /
tmpfs           3.8G     0  3.8G   0% /dev/shm
tmpfs           5.0M     0  5.0M   0% /run/lock
tmpfs           3.8G     0  3.8G   0% /sys/fs/cgroup
/dev/nvme1n1     20G  388M   19G   3% /mnt/master-vol-07da991119bf41fbd
/dev/nvme2n1     20G  356M   19G   2% /mnt/master-vol-081a442a3b8f53e8b
```

Bingo! That's the murderer, the disk is somehow fully used! And since it's fully used, it's extremely hard to carry out any operations on this machine, head scratched! I immediately checked all other masters and slave nodes, all of them are in good condition where their disk are only used by ~15%, then how come only this master's disk is full? Anyway I started with checking whether there are two many old docker images, which will usually be the case, it might be the easiest thing to do to free out some space:

```
docker system prune -a -f
```

As it will remove all images that are dangling and all docker containers that are not running. However, docker hung and after a few minutes, I received this:

```
http://%2Fvar%2Frun%2Fdocker.sock/v1.27/containers/json: read unix @->/var/run/docker.sock: read: connection reset by peer
```
I tried other docker cli command and all of them ended out with timeout and print the above message. Basically `docker` is dead. I tried `kubectl` commands to list pods and other informations, they all ended up with timeout as long as any of these pods were running on this master.

### Attempts I did

The following section records what I did to bring this instance back to normal.

#### Restart docker daemon.

I tried to restart docker using:

```
systemctl restart docker
```

Docker is stopped and restarted, however it didn't help.

#### Check what used the disk space and remove.

```
du -h /
```

This takes ages to run, in the end I found out that `/var/lib/docker/` is taking really a lot of space, with the same mind set, I figured that I should remove some images and containers first to free space manually, by removing stuff in `/var/lib/docker/overlay/` first. In order to do this, I stopped Docker first.

```
systemctl stop docker
```

However it didn't help at all, after a while docker daemon is alive again, and every single time I stopped it, it went alive automatically again. With a lot of investigation, I found out the reasons:

- The process has been defined as `respawn`
- Another service called `docker-healthcheck` is checking for the reachability of docker and will try to start it again if can't connect to it.

#### Discovered the root cause.

After a lot of painful slow operations, I finally spotted the problem: the following two log files are growing exponentially:

- /var/log/daemon.log
- /var/log/syslog.log

And here are the content that gets repeating consistently for each of them:

```
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: goroutine 2648 [runnable]:
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: syscall.Syscall6(0x101, 0xffffffffffffff9c, 0xc457325700, 0x800c2, 0x180, 0x0, 0x0, 0xc9e, 0x800c2, 0x0)
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/local/go/src/syscall/asm_linux_amd64.s:44 +0x5
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: syscall.openat(0xffffffffffffff9c, 0xc457325680, 0x78, 0x800c2, 0xc400000180, 0x562a7619542f, 0xc457325680, 0x78)
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/local/go/src/syscall/zsyscall_linux_amd64.go:40 +0xcd
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: syscall.Open(0xc457325680, 0x78, 0x800c2, 0xc400000180, 0x562a76193b1f, 0xc4573dfbd8, 0x2)
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/local/go/src/syscall/syscall_linux.go:51 +0x50
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: os.OpenFile(0xc457325680, 0x78, 0xc2, 0xc400000180, 0x78, 0xc4277d4260, 0x1c)
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/local/go/src/os/file_unix.go:97 +0x80
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: io/ioutil.TempFile(0xc4574145b0, 0x5b, 0xc4573dfc50, 0x13, 0xe, 0xc4573dfc50, 0x13)
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/local/go/src/io/ioutil/tempfile.go:55 +0x159
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: github.com/docker/docker/pkg/ioutils.NewAtomicFileWriter(0xc4574145b0, 0x6a, 0x1a4, 0x0, 0x0, 0x0, 0x0)
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/src/docker/.gopath/src/github.com/docker/docker/pkg/ioutils/fswriters.go:14 +0xe2
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: github.com/docker/docker/container.(*Container).ToDisk(0xc42d53fe00, 0x0, 0x0)
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/src/docker/.gopath/src/github.com/docker/docker/container/container.go:155 +0xad
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: github.com/docker/docker/container.(*Container).ToDiskLocking(0xc42d53fe00, 0xc42d53fe00, 0xc43afc2780)
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/src/docker/.gopath/src/github.com/docker/docker/container/container.go:174 +0x3f
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: github.com/docker/docker/daemon.(*Daemon).restore.func1(0xc43afc2780, 0xc420329e00, 0xc43afc2778, 0xc43bb986c0, 0xc43bb98690, 0xc43bb98660, 0xc43afc2776, 0xc42d53fe00)
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/src/docker/.gopath/src/github.com/docker/docker/daemon/daemon.go:198 +0xbe
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: created by github.com/docker/docker/daemon.(*Daemon).restore
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/src/docker/.gopath/src/github.com/docker/docker/daemon/daemon.go:275 +0x78a
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: goroutine 2649 [runnable]:
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: syscall.Syscall6(0x101, 0xffffffffffffff9c, 0xc457325880, 0x800c2, 0x180, 0x0, 0x0, 0xca0, 0x800c2, 0x0)
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/local/go/src/syscall/asm_linux_amd64.s:44 +0x5
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: syscall.openat(0xffffffffffffff9c, 0xc457325800, 0x78, 0x800c2, 0xc400000180, 0x562a7619542f, 0xc457325800, 0x78)
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/local/go/src/syscall/zsyscall_linux_amd64.go:40 +0xcd
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: syscall.Open(0xc457325800, 0x78, 0x800c2, 0xc400000180, 0x562a76193b1f, 0xc4573e0bd8, 0x2)
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/local/go/src/syscall/syscall_linux.go:51 +0x50
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: os.OpenFile(0xc457325800, 0x78, 0xc2, 0xc400000180, 0x78, 0xc4277d4420, 0x1c)
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/local/go/src/os/file_unix.go:97 +0x80
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: io/ioutil.TempFile(0xc457414930, 0x5b, 0xc4573e0c50, 0x13, 0xe, 0xc4573e0c50, 0x13)
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/local/go/src/io/ioutil/tempfile.go:55 +0x159
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: github.com/docker/docker/pkg/ioutils.NewAtomicFileWriter(0xc457414930, 0x6a, 0x1a4, 0x0, 0x0, 0x0, 0x0)
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/src/docker/.gopath/src/github.com/docker/docker/pkg/ioutils/fswriters.go:14 +0xe2
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: github.com/docker/docker/container.(*Container).ToDisk(0xc432ed3800, 0x0, 0x0)
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/src/docker/.gopath/src/github.com/docker/docker/container/container.go:155 +0xad
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: github.com/docker/docker/container.(*Container).ToDiskLocking(0xc432ed3800, 0xc432ed3800, 0xc43afc2780)
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/src/docker/.gopath/src/github.com/docker/docker/container/container.go:174 +0x3f
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: github.com/docker/docker/daemon.(*Daemon).restore.func1(0xc43afc2780, 0xc420329e00, 0xc43afc2778, 0xc43bb986c0, 0xc43bb98690, 0xc43bb98660, 0xc43afc2776, 0xc432ed3800)
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/src/docker/.gopath/src/github.com/docker/docker/daemon/daemon.go:198 +0xbe
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: created by github.com/docker/docker/daemon.(*Daemon).restore
Sep  9 10:02:37 ip-10-18-39-127 dockerd[12436]: #011/usr/src/docker/.gopath/src/github.com/docker/docker/daemon/daemon.go:275 +0x78a
Sep 11 01:24:50 ip-10-18-39-127 systemd[1]: protokube.service: Main process exited, code=exited, status=125/n/a
Sep 11 01:24:50 ip-10-18-39-127 systemd[1]: protokube.service: Unit entered failed state.
Sep 11 01:24:50 ip-10-18-39-127 systemd[1]: protokube.service: Failed with result 'exit-code'.
Sep 11 01:24:52 ip-10-18-39-127 systemd[1]: protokube.service: Service hold-off time over, scheduling restart.
Sep 11 01:24:52 ip-10-18-39-127 systemd[1]: Stopped Kubernetes Protokube Service.
Sep 11 01:24:52 ip-10-18-39-127 systemd[1]: Starting Kubernetes Protokube Service...
Sep 11 01:24:52 ip-10-18-39-127 systemd[1]: Started Kubernetes Protokube Service.
Sep 11 01:24:52 ip-10-18-39-127 docker[29742]: /usr/bin/docker: Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?.
Sep 11 01:24:52 ip-10-18-39-127 docker[29742]: See '/usr/bin/docker run --help'.
Sep 11 01:24:52 ip-10-18-39-127 systemd[1]: protokube.service: Main process exited, code=exited, status=125/n/a
Sep 11 01:24:52 ip-10-18-39-127 systemd[1]: protokube.service: Unit entered failed state.
Sep 11 01:24:52 ip-10-18-39-127 systemd[1]: protokube.service: Failed with result 'exit-code'.
Sep 11 01:24:54 ip-10-18-39-127 systemd[1]: protokube.service: Service hold-off time over, scheduling restart.
Sep 11 01:24:54 ip-10-18-39-127 systemd[1]: Stopped Kubernetes Protokube Service.
Sep 11 01:24:54 ip-10-18-39-127 systemd[1]: Starting Kubernetes Protokube Service...
Sep 11 01:24:54 ip-10-18-39-127 systemd[1]: Started Kubernetes Protokube Service.
Sep 11 01:24:54 ip-10-18-39-127 docker[29756]: /usr/bin/docker: Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?.
Sep 11 01:24:54 ip-10-18-39-127 docker[29756]: See '/usr/bin/docker run --help'.
Sep 11 01:24:03 ip-10-18-39-127 systemd[1]: protokube.service: Service hold-off time over, scheduling restart.
Sep 11 01:24:03 ip-10-18-39-127 systemd[1]: Stopped Kubernetes Protokube Service.
Sep 11 01:24:03 ip-10-18-39-127 systemd[1]: Starting Kubernetes Protokube Service...
Sep 11 01:24:03 ip-10-18-39-127 systemd[1]: Started Kubernetes Protokube Service.
Sep 11 01:24:03 ip-10-18-39-127 docker[29369]: /usr/bin/docker: Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?.
Sep 11 01:24:03 ip-10-18-39-127 docker[29369]: See '/usr/bin/docker run --help'.
Sep 11 01:24:03 ip-10-18-39-127 systemd[1]: protokube.service: Main process exited, code=exited, status=125/n/a
Sep 11 01:24:03 ip-10-18-39-127 systemd[1]: protokube.service: Unit entered failed state.
Sep 11 01:24:03 ip-10-18-39-127 systemd[1]: protokube.service: Failed with result 'exit-code'.
Sep 11 01:24:05 ip-10-18-39-127 systemd[1]: protokube.service: Service hold-off time over, scheduling restart.
Sep 11 01:24:05 ip-10-18-39-127 systemd[1]: Stopped Kubernetes Protokube Service.
Sep 11 01:24:05 ip-10-18-39-127 systemd[1]: Starting Kubernetes Protokube Service...
Sep 11 01:24:05 ip-10-18-39-127 systemd[1]: Started Kubernetes Protokube Service.
Sep 11 01:24:05 ip-10-18-39-127 docker[29380]: /usr/bin/docker: Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?.
Sep 11 01:24:05 ip-10-18-39-127 docker[29380]: See '/usr/bin/docker run --help'.
Sep 11 01:24:05 ip-10-18-39-127 systemd[1]: protokube.service: Main process exited, code=exited, status=125/n/a
Sep 11 01:24:05 ip-10-18-39-127 systemd[1]: protokube.service: Unit entered failed state.
Sep 11 01:24:05 ip-10-18-39-127 systemd[1]: protokube.service: Failed with result 'exit-code'.
Sep 11 01:23:58 ip-10-18-39-127 systemd[1]: protokube.service: Main process exited, code=exited, status=125/n/a
Sep 11 01:23:58 ip-10-18-39-127 systemd[1]: protokube.service: Unit entered failed state.
Sep 11 01:23:58 ip-10-18-39-127 systemd[1]: protokube.service: Failed with result 'exit-code'.
Sep 11 01:24:01 ip-10-18-39-127 systemd[1]: protokube.service: Service hold-off time over, scheduling restart.
Sep 11 01:24:01 ip-10-18-39-127 systemd[1]: Stopped Kubernetes Protokube Service.
Sep 11 01:24:01 ip-10-18-39-127 systemd[1]: Starting Kubernetes Protokube Service...
Sep 11 01:24:01 ip-10-18-39-127 systemd[1]: Started Kubernetes Protokube Service.
Sep 11 01:24:01 ip-10-18-39-127 docker[29354]: /usr/bin/docker: Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?.
Sep 11 01:24:01 ip-10-18-39-127 docker[29354]: See '/usr/bin/docker run --help'.
Sep 11 01:24:01 ip-10-18-39-127 systemd[1]: protokube.service: Main process exited, code=exited, status=125/n/a
Sep 11 01:24:01 ip-10-18-39-127 systemd[1]: protokube.service: Unit entered failed state.
Sep 11 01:24:01 ip-10-18-39-127 systemd[1]: protokube.service: Failed with result 'exit-code'.
Sep 11 01:24:03 ip-10-18-39-127 systemd[1]: protokube.service: Service hold-off time over, scheduling restart.
Sep 11 01:24:03 ip-10-18-39-127 systemd[1]: Stopped Kubernetes Protokube Service.
Sep 11 01:24:03 ip-10-18-39-127 systemd[1]: Starting Kubernetes Protokube Service...
Sep 11 01:24:03 ip-10-18-39-127 systemd[1]: Started Kubernetes Protokube Service.
Sep 11 01:24:03 ip-10-18-39-127 docker[29369]: /usr/bin/docker: Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?.
Sep 11 01:24:03 ip-10-18-39-127 docker[29369]: See '/usr/bin/docker run --help'.
Sep 11 01:24:03 ip-10-18-39-127 systemd[1]: protokube.service: Main process exited, code=exited, status=125/n/a
Sep 11 01:24:03 ip-10-18-39-127 systemd[1]: protokube.service: Unit entered failed state.
Sep 11 01:24:03 ip-10-18-39-127 systemd[1]: protokube.service: Failed with result 'exit-code'.
Sep 11 01:24:05 ip-10-18-39-127 systemd[1]: protokube.service: Service hold-off time over, scheduling restart.
Sep 11 01:24:05 ip-10-18-39-127 systemd[1]: Stopped Kubernetes Protokube Service.
Sep 11 01:24:05 ip-10-18-39-127 systemd[1]: Starting Kubernetes Protokube Service...
Sep 11 01:24:05 ip-10-18-39-127 systemd[1]: Started Kubernetes Protokube Service.
Sep 11 01:24:05 ip-10-18-39-127 docker[29380]: /usr/bin/docker: Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?.
Sep 11 01:24:05 ip-10-18-39-127 docker[29380]: See '/usr/bin/docker run --help'.
Sep 11 01:24:05 ip-10-18-39-127 systemd[1]: protokube.service: Main process exited, code=exited, status=125/n/a
Sep 11 01:24:05 ip-10-18-39-127 systemd[1]: protokube.service: Unit entered failed state.
Sep 11 01:24:05 ip-10-18-39-127 systemd[1]: protokube.service: Failed with result 'exit-code'.
Sep 11 01:24:07 ip-10-18-39-127 systemd[1]: protokube.service: Service hold-off time over, scheduling restart.
Sep 11 01:24:07 ip-10-18-39-127 systemd[1]: Stopped Kubernetes Protokube Service.
Sep 11 01:24:07 ip-10-18-39-127 systemd[1]: Starting Kubernetes Protokube Service...
Sep 11 01:24:07 ip-10-18-39-127 systemd[1]: Started Kubernetes Protokube Service.
Sep 11 01:24:07 ip-10-18-39-127 docker[29393]: /usr/bin/docker: Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?.
Sep 11 01:24:07 ip-10-18-39-127 docker[29393]: See '/usr/bin/docker run --help'.
Sep 11 01:24:07 ip-10-18-39-127 systemd[1]: protokube.service: Main process exited, code=exited, status=125/n/a
Sep 11 01:24:07 ip-10-18-39-127 systemd[1]: protokube.service: Unit entered failed state.
Sep 11 01:24:07 ip-10-18-39-127 systemd[1]: protokube.service: Failed with result 'exit-code'.
Sep 11 01:24:10 ip-10-18-39-127 systemd[1]: protokube.service: Service hold-off time over, scheduling restart.
Sep 11 01:24:10 ip-10-18-39-127 systemd[1]: Stopped Kubernetes Protokube Service.
Sep 11 01:24:10 ip-10-18-39-127 systemd[1]: Starting Kubernetes Protokube Service...
Sep 11 01:24:10 ip-10-18-39-127 systemd[1]: Started Kubernetes Protokube Service.
Sep 11 01:24:10 ip-10-18-39-127 docker[29414]: /usr/bin/docker: Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?.
Sep 11 01:24:10 ip-10-18-39-127 docker[29414]: See '/usr/bin/docker run --help'.
Sep 11 01:24:10 ip-10-18-39-127 systemd[1]: protokube.service: Main process exited, code=exited, status=125/n/a
Sep 11 01:24:10 ip-10-18-39-127 systemd[1]: protokube.service: Unit entered failed state.
Sep 11 01:24:10 ip-10-18-39-127 systemd[1]: protokube.service: Failed with result 'exit-code'.
Sep 11 01:24:12 ip-10-18-39-127 systemd[1]: protokube.service: Service hold-off time over, scheduling restart.
Sep 11 01:24:12 ip-10-18-39-127 systemd[1]: Stopped Kubernetes Protokube Service.
Sep 11 01:24:12 ip-10-18-39-127 systemd[1]: Starting Kubernetes Protokube Service...
Sep 11 01:24:12 ip-10-18-39-127 systemd[1]: Started Kubernetes Protokube Service.
Sep 11 01:24:12 ip-10-18-39-127 docker[29438]: /usr/bin/docker: Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?.
Sep 11 01:24:12 ip-10-18-39-127 docker[29438]: See '/usr/bin/docker run --help'.
Sep 11 01:24:12 ip-10-18-39-127 systemd[1]: protokube.service: Main process exited, code=exited, status=125/n/a
Sep 11 01:24:12 ip-10-18-39-127 systemd[1]: protokube.service: Unit entered failed state.
Sep 11 01:24:12 ip-10-18-39-127 systemd[1]: protokube.service: Failed with result 'exit-code'.
Sep 11 01:24:14 ip-10-18-39-127 systemd[1]: protokube.service: Service hold-off time over, scheduling restart.

```

I guess you might have guessed the reason for this the same as I did. It's a combination of a few things.

- `Docker` has crashed and each time it received any API call, it prints exception logs.
- The `docker-healthcheck` process checks with Docker every 30s, which triggers the log.
- The `kubelet` keeps calling Docker APIs to gather containers status.
- The `protokub` service keeps calling Docker API non-stoping to try to spin up components.

As a result of the above reasons, the log files grows like a bamboo.

### How did I fix it

Taking advantages of the HA deployment, one master instance down didn't affect the overall cluster and all workloads were still healthy too. So I went with the easiest route: replacing the master node.

Since my cluster is deployed with kops (you can find it in my [previous post](http://blog.wumuxian1988.com/2018/06/12/HA-Kubernetes-Cluster-on-AWS/)), it's extremely easy. All I needed to do was to terminate that master instance. The auto scaling group will bring up again master intance, bootstrapping it and join the cluster. After about 5 mins, the cluster is back to its shape again:

```
kubectl get nodes

NAME                            STATUS    ROLES     AGE       VERSION
xxxxxxxxxxxxxxxxxxxxxxxxxxx     Ready     master    103d      v1.9.3
xxxxxxxxxxxxxxxxxxxxxxxxxxx     Ready     master    4h        v1.9.3
xxxxxxxxxxxxxxxxxxxxxxxxxxx     Ready     node      98d       v1.9.3
xxxxxxxxxxxxxxxxxxxxxxxxxxx     Ready     master    103d      v1.9.3
xxxxxxxxxxxxxxxxxxxxxxxxxxx     Ready     node      84d       v1.9.3
```

You can see one of the master is replaced.

### Why docker crashed.

I am also not sure about this. I checked with the forums, it's said that it's the bug for the Docker version that I'm using and it has been fixed in newer versions. For the record, the docker version I'm using is:

```bash
Client:
 Version:      17.03.2-ce
 API version:  1.27
 Go version:   go1.7.5
 Git commit:   f5ec1e2
 Built:        Tue Jun 27 02:31:19 2017
 OS/Arch:      linux/amd64

Server:
 Version:      17.03.2-ce
 API version:  1.27 (minimum version 1.12)
 Go version:   go1.7.5
 Git commit:   f5ec1e2
 Built:        Tue Jun 27 02:31:19 2017
 OS/Arch:      linux/amd64
 Experimental: false
```

Since it's been running very smoothly for 3 months, I'm not that concerned. And it will be auto-fixed next time when I upgrade the whole cluster to newer versions.


## Conclusion

I wrote this post to remind myself of this incident and for those who might also encountered this. What I've learned is that, sometimes `auto-restart` can be a really problem, in this particular case, it can't help with anything but just generating tones of logs which will leads to the crash of the whole system in a real hurry. What could possibly to done are that:

- Set alarms on the storage usages on each machine.
- For `auto-restart` feature, give it an upper limit, don't try to do it forever.
- Set alarms on `Docker` reachability on each machine as it's so critical to the whole ecosystem.
