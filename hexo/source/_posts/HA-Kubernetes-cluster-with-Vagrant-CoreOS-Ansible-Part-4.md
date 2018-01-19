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

And we're gonna deploy other add-ons using the kubenertes cluster
- heapster
- kubernetes-dashboard
- kube-dns
- kube-flannel
- kube-proxy
- pod-checkpointer

And add a custom namespace for deploy my apps.

We take advantage of `bootkube` to serve the purpose. `bootkube` introduces the concept of `self-hosted control panel`. It means that Kubernetes runs all required and optional components of a Kubernetes cluster on top of Kubernetes itself, the detailed introduction can be found [here](https://github.com/kubernetes/community/blob/master/contributors/design-proposals/cluster-lifecycle/self-hosted-kubernetes.md). In a nutshell, `bootkube` provides a temporary Kubernetes control plane that tells a kubelet to execute all of the components necessary to run a full blown Kubernetes control plane.

To make `bootkube` run with `bootkbe start`, we have to prepare the specs in a folder structures like this:
- auth
  * kubeconfig
- bootstrap-manifests
  * bootstrap-apiserver.yaml
  * bootstrap-controller-manager.yaml
  * bootstrap-scheduler.ymal
- manifests
  * heapster.yaml
  * kube-apiserver-secret.yaml
  * kube-controller-manager-disruption.yaml
  * kube-controller-manager-secret.yaml
  * kube-controller-manager.yaml
  * kube-dashboard.yaml
  * kube-dns.yaml
  * kube-flannel.yaml
  * kube-proxy.yaml
  * kube-scheduler-disruption.yaml
  * kube-scheduler.yaml
  * kube-system-rbac-role-binding.yaml
  * namespace.yaml
  * pod-checkpointer.yaml
- tls
  * apiserver.crt
  * apiserver.key
  * ca.crt
  * ca.key
  * etcd-client-ca.crt
  * etcd-client.crt
  * etcd-client.key
  * kubelet.crt
  * kubelet.key
  * service-account.key
  * service-account.pub
