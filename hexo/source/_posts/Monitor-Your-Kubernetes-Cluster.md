---
title: Monitor Your Kubernetes Cluster
date: 2018-07-04 18:37:18
tags:
  - Kubernetes  
  - Prometheus
category:
  - Infrastructure  
  - Monitoring
---

At any scale, an end-to-end monitoring solution for your infrastructure and workload is essential because:

1. You need to make sure your resources are well used and know when to scale up/down.
2. You need to make sure the applications are running in good health and are performant.
3. You need to know any system hiccups and be able to take actions when disaster happens.

When in comes to Kubernetes, monitoring is very different from traditional infrastructure and a lot more complicated:

![](evolution of monitoring.jpeg)Kubernetes has brought up the era of **Orchestrated Containerized Infrastructure**, but it also means we have more components to monitor:

* The nodes on which Kubernetes and its workload are running.
* The containers
* The containerized applications
* The Orchestration tool \(Kubernetes\) itself.

## Where are metrics coming from

As discussed in above section, we have 4 components to monitor and for each of them we need to know where can we get the metric for them.

### Our Solution: Prometheus Operator

It would be nice if we can use some existing tool other than hand-making a monitoring system from scratch, and luckily we have **Prometheus Operator** by CoreOS. Prometheus operator creates, configures, and manages Prometheus monitoring instances and automatically generates monitoring target configurations based on Kubernetes label queries.

![](prometheus_operator.png)

The above graph shows a desired state of a prometheus deployment, the service monitor defines what services to monitor by prometheus using label selectors, the same way as a service defines what pods to expose by label selectors.

#### The host/nodes metrics

Prometheus uses **node_exporter** to collect nodes CPU, memory and disk usage and much more, we deploy **node_exporter** as deamonset so it runs on each nodes in the cluster.

#### The containers

The containers metrics are collected from **kubelet**, which is the Kubernetes component that manages pods and containers.

#### The containerized applications

To monitor your application data, there are two ways of doing it

* pull - you instrument your application using Prometheus's client and provide metrics endpoints for Prometheus's to scrape.
* push - you use **Prometheus Pushgateway** to push metrics to an intermediary job which Prometheus can scrape.

All metrics data for your applications can be monitored via **ServiceMonitor**, you just need to make sure you define the right path and port.

#### The Kubernetes cluster

Metrics about the cluster state are exposed using **kube-state-metrics**, which is a simple service that listens to the Kubernetes API server and generates metrics about the state of the objects, e.g. deployments, pods, nodes and etc.

## Deploy the Prometheus Operator

You can find a ready-to-go prometheus operator deployment [here](https://github.com/kubernetes/kops/tree/master/addons/prometheus-operator).

In this post, I'll go through the important pieces of the puzzle.


Give your cluster sometime to create all the required resources and check the status of these pods using kuberctl

```
kubectl get -n monitoring pods                                                                                                                                                                ✔  10242  17:18:30
NAME                                   READY     STATUS    RESTARTS   AGE
alertmanager-main-0                    2/2       Running   0          3d
alertmanager-main-1                    2/2       Running   0          3d
alertmanager-main-2                    2/2       Running   0          3d
grafana-6fc9dff66-g8jf4                1/1       Running   0          3d
kube-state-metrics-697b8b58fb-5svg9    4/4       Running   0          3d
node-exporter-85cmz                    2/2       Running   0          3d
node-exporter-9498f                    2/2       Running   0          3d
node-exporter-hx6fw                    2/2       Running   0          3d
node-exporter-swbpq                    2/2       Running   0          3d
node-exporter-zd2ts                    2/2       Running   0          3d
prometheus-k8s-0                       2/2       Running   1          3d
prometheus-k8s-1                       2/2       Running   1          3d
prometheus-operator-7dd7b4f478-hvd9s   1/1       Running   0          3d
```

## Dashboards

After your Prometheus cluster is up and running, we can view your cluster/nodes/pods status using **Grafana**, the user name and password is both **admin**.

After you login, we can check different dashboards that were already created and linked with Prometheus data source, you can create new dashboard as well.

![](grafana_default_dashboards.png)

![](grafana.png)
