---
title: Get Familiar with Yum
date: 2016-07-15 18:26:15
tags:
  - Centos
  - Redhat
  - Enterprise Linux
category:
  - DevOps
---

This post records some useful operations regarding repo and package management of the redhat, centos, and enterprise linux like system.

1. List all the available repositories
	```bash
	yum repolist

	Loaded plugins: priorities, update-motd, upgrade-helper
	amzn-updates/latest/primary_db                                                                                                                                                                                                                        | 675 kB     00:00
	repo id                                                                                                                    repo name                                                                                                                                   status
	!amzn-main/latest                                                                                                          amzn-main-Base                                                                                                                              5541
	!amzn-updates/latest                                                                                                       amzn-updates-Base                                                                                                                            845
	!mesosphere/x86_64                                                                                                         Mesosphere Packages for EL 6 - x86_64                                                                                                         76
	!mesosphere-noarch                                                                                                         Mesosphere Packages for EL 6 - noarch                                                                                                          5
	repolist: 6467
	```

2. List available packages from selected repository
	```bash
	yum --disablerepo="*" --enablerepo="mesosphere-noarch" list available

	Loaded plugins: priorities, update-motd, upgrade-helper
	Available Packages
	mesosphere.noarch                                                                                                                0.1.0-0.el6                                                                                                                mesosphere-noarch
	```

3. Search package by name
	```bash
	yum list mesos

	Installed Packages
	mesos.x86_64                                                                                                                0.28.2-2.0.27.centos65                                                                                                                @mesosphere
	```

4. Search package when you don't know the exact name
	```bash
	yum provides ntp

	ntp-4.2.6p5-36.29.amzn1.x86_64 : The NTP daemon and utilities
	Repo        : amzn-main



	ntp-4.2.6p5-40.30.amzn1.x86_64 : The NTP daemon and utilities
	Repo        : amzn-updates



	ntp-4.2.6p5-40.30.amzn1.x86_64 : The NTP daemon and utilities
	Repo        : @amzn-updates
	```

5. Display package info
	```bash
	yum info mesos

	Loaded plugins: priorities, update-motd, upgrade-helper
	Installed Packages
	Name        : mesos
	Arch        : x86_64
	Version     : 0.28.2
	Release     : 2.0.27.centos65
	Size        : 88 M
	Repo        : installed
	From repo   : mesosphere
	Summary     : Cluster resource manager with efficient resource isolation
	URL         : https://mesos.apache.org/
	License     : Apache-2.0
	Description : Cluster resource manager with efficient resource isolation
	            : Apache Mesos is a cluster manager that offers efficient resource isolation
	            : and sharing across distributed applications, or frameworks. It can run
	            : Hadoop, MPI, Hypertable, Spark (a new framework for low-latency interactive
	            : and iterative jobs), and other applications.
	```

6. List Files Contained in a Package
	```bash
	repoquery --list marathon

	/etc/init/marathon.conf
	/usr/bin/marathon
	```

7. Remove yum repository and yum package
	```bash
	# repo
	rpm -qf /etc/yum.repos.d/REPONAME.repo
	# package
	yum remove PACKAGENAME
	```

8. Clean yum cache
	```bash
	yum clean all
	```



