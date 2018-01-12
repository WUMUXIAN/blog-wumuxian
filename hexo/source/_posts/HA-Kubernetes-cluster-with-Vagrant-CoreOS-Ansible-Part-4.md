---
title: 'HA Kubernetes cluster with Vagrant+CoreOS+Ansible, Part 4'
date: 2018-01-12 17:39:38
tags:
 - Kubernetes
 - Docker
 - Vagrant
 - CoreOS
category:
 - DevOps
---

In the [last part](http://blog.wumuxian1988.com/2018/01/12/HA-Kubernetes-cluster-with-Vagrant-CoreOS-Ansible-Part-3/), we installed kubelet on all nodes. In this part, we're gonna bootstrap the three key components of a kubernetes cluster
- API Server
- Scheduler
- Controller Manager

We take advantage of `bootkube` to serve the purpose. `bootkube` introduces the concept of `self-hosted control panel`. It means that Kubernetes runs all required and optional components of a Kubernetes cluster on top of Kubernetes itself, the detailed introduction can be found [here](https://github.com/kubernetes/community/blob/master/contributors/design-proposals/cluster-lifecycle/self-hosted-kubernetes.md). In a nutshell, `bootkube` provides a temporary Kubernetes control plane that tells a kubelet to execute all of the components necessary to run a full blown Kubernetes control plane.
