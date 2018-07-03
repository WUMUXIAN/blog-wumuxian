---
title: >-
  Use Fluentd and Elastic search to monitor your containerized application in
  Kubernetes
date: 2018-06-26 20:42:01
tags:
  - Kubernetes
  - Fluentd
  - Elasticsearch
  - Kibana
category:
  - Infrastructure
  - Logging
  - Monitoring
---

As we all know, the basic units running in a Kubernetes cluster are docker containers, docker has its native logging drivers that can provide basic logging functionality, whether to write to stdout and stderr, or write to json file with rotations.

However, it's not enough for a full logging solution. For example, your API services may have 3 replicas, which in turn will bring up 3 containers on which your logs are distributed across, how do you aggregate all the logs and be able to view them at one place? Another example is if your container crashes, the container will die and will be replaced with another one on the node, or could even gets scheduled on a different node, in this case, the logs of that container could get lost. Due to the above reasons, when it comes to logging, Kubernetes promotes **cluster-level-logging**, it means we need to have a separate backend to store, analyze and query logs, so that the logs are independent of the lifecycle of of any containers, pods or the nodes in the cluster.

Kubernetes does not ship with any logging facility that suffices the **cluster-level-logging** requirement, however there are many open source solutions you can leverage on to implement a full logging service. Among them, fluentd + elasticsearch form a great combination to provide a cluster level logging solution. In this post, I'll introduce how to get it done.

In a nutshell, the ideal is:

- Use fluentd as an agent on each node to scrape all the container logs
- Push the logs to Elasticsearch for storing, analyzing and querying using **logstash-ish** indices.

![Use fluentd as node log agents](Fluentd+Elasticsearch+Kubernetes.jpg)

### Deploy Fluentd

We need to make sure we have a fluentd agent running on each node, and this fits the **DaemonSet** of Kubernetes perfectly. In order to make sure the pods can only access relevant resources in the cluster, we will create a service account and use it to create the DaemonSet later.

```
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fluentd
  namespace: kube-system

---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: fluentd
  namespace: kube-system
rules:
- apiGroups:
  - ""
  resources:
  - pods
  - namespaces
  verbs:
  - get
  - list
  - watch

---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: fluentd
roleRef:
  kind: ClusterRole
  name: fluentd
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: fluentd
  namespace: kube-system

---

```

You can see that we only grant this service account the read access to namespaces and pods, which will be enough.

Now we move on to the DaemonSet definition, fluentd has published a set of images that support logging with Kubernetes meta support, and here we use [fluent/fluentd-kubernetes-daemonset:v0.12-alpine-elasticsearch](https://github.com/fluent/fluentd-kubernetes-daemonset/blob/master/docker-image/v0.12/alpine-elasticsearch/Dockerfile)

By default, you don't need to make any configuration changes, this image will try to collect the following logs if they exists in /var/log/ directory, pack them with kubernetes metadata and push to an elasticsearch backend with logstash-ish indices.

- all your docker containers logs
- kubelet
- kube-api-server
- kube-controller-manager
- kube-scheduler
- kube-proxy
- etcd

In our case, we are only interested in the containerized application logs for our workload but not the system applications, in order to achieve this, we can customize the the fluentd configuration file **kubernetes.conf** to replace the default one. We will only follow the docker container logs that we are interested. Typically you will have different namespaces for your application instead of using _*default *_ and _*kube-system*_.

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-kubernetes-config
  namespace: kube-system
data:
  fluent.conf: |-
    @include kubernetes.conf

    <match **>
       @type elasticsearch
       @id out_es
       log_level info
       include_tag_key true
       host "#{ENV['FLUENT_ELASTICSEARCH_HOST']}"
       port "#{ENV['FLUENT_ELASTICSEARCH_PORT']}"
       scheme "#{ENV['FLUENT_ELASTICSEARCH_SCHEME'] || 'http'}"
       ssl_verify "#{ENV['FLUENT_ELASTICSEARCH_SSL_VERIFY'] || 'true'}"
       user "#{ENV['FLUENT_ELASTICSEARCH_USER']}"
       password "#{ENV['FLUENT_ELASTICSEARCH_PASSWORD']}"
       reload_connections "#{ENV['FLUENT_ELASTICSEARCH_RELOAD_CONNECTIONS'] || 'true'}"
       logstash_prefix "#{ENV['FLUENT_ELASTICSEARCH_LOGSTASH_PREFIX'] || 'logstash'}"
       logstash_format true
       buffer_chunk_limit 2M
       buffer_queue_limit 32
       flush_interval 5s
       max_retry_wait 30
       disable_retry_limit
       num_threads 8
    </match>
  kubernetes.conf: |-
    <match fluent.**>
      @type null
    </match>

    <source>
      @type tail
      @id in_tail_container_logs
      path /var/log/containers/*tds-*.log
      pos_file /var/log/fluentd-containers.log.pos
      tag kubernetes.*
      read_from_head true
      format json
      time_format %Y-%m-%dT%H:%M:%S.%NZ
    </source>

    <filter kubernetes.**>
      @type kubernetes_metadata
      @id filter_kube_metadata
    </filter>

---

apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: fluentd
  namespace: kube-system
  labels:
    k8s-app: fluentd-logging
    version: v1
    kubernetes.io/cluster-service: "true"
spec:
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        k8s-app: fluentd-logging
        version: v1
        kubernetes.io/cluster-service: "true"
    spec:
      serviceAccount: fluentd
      serviceAccountName: fluentd
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      containers:
      - name: fluentd
        image: fluent/fluentd-kubernetes-daemonset:v0.12-alpine-elasticsearch
        env:
          - name:  FLUENT_ELASTICSEARCH_HOST
            value: "elasticsearch"
          - name:  FLUENT_ELASTICSEARCH_PORT
            value: "9200"
          - name: FLUENT_ELASTICSEARCH_SCHEME
            value: "http"
        resources:
          limits:
            cpu: 100m
            memory: 200Mi
          requests:
            cpu: 100m
            memory: 200Mi
        volumeMounts:
        - name: varlog
          mountPath: /var/log
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
        - name: kubernetesconfig
          mountPath: /fluentd/etc
      terminationGracePeriodSeconds: 30
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
      - name: kubernetesconfig
        configMap:
          name: fluentd-kubernetes-config

```
