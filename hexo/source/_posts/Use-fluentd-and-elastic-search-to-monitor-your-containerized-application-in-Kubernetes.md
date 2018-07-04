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

We can create a config map that contains fluentd.conf and kubernetes.conf and mount it to the /fluentd/etc path in the fluentd pods. The configuration file is shown as follows.

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

> You might wonder why the host path /var/lib/docker/containers is also mounted as volume. It's because the docker container logs in /var/log/ are actually symbol links which points to /var/lib/docker/containers/(container_id)/*******.log. If you don't mount /var/lib/docker/container, fluentd won't be able to read the actually log files.

Wait for the Daemonset to be deployed, you should find the pods count equals your node count.

![](fluentd_daemonset.jpg)

You might notice that we set the *FLUENT_ELASTICSEARCH_HOST* to *elasticsearch*, this actually implicates that we should have an elasticsearch service running within the cluster itself. If you are using some external elasticsearch service, you can just set the three environment variables accordingly to point to your elasticsearch service and you will be all set:

- FLUENT_ELASTICSEARCH_HOST
- FLUENT_ELASTICSEARCH_PORT
- FLUENT_ELASTICSEARCH_SCHEME

You should start to receive logstash-ish logs in your elasticsearch cluster once you have the DaemonSet up and running.

```
curl -X GET 'http://your_elastic_service_url:9200/_cat/indices?v='

health status index               uuid                   pri rep docs.count docs.deleted store.size pri.store.size
green  open   logstash-2018.07.04 bRiQJCnrTZqOQQI4ol1mfw   5   1      16744            0     24.4mb         12.1mb
green  open   .kibana             6UUqrS5_RUSS5Ozy2tSYTg   1   1         19            1      115kb         57.5kb

```

If you want to use an in-cluster elasticsearch cluster, obviously you need to deploy one, please continue reading.

### Deploy Elasticsearch

> This part is assuming that your Kubernetes cluster is running on AWS EC2 instances across different availability zones to achieve HA. However even if it's not, it can also provide a reference for you.

Here we'll deploy a minimum HA elasticsearch cluster which consists:

- 3 master nodes
- 2 data nodes

The 3 master nodes manage the cluster and opens API access to clients. 1 of the 3 at all times will be elected as the leader, so that we have an active-passive HA master cluster.

In order not to put the masters under pressure, we separate the data nodes from master nodes. The 2 dedicated data nodes are used to perform resources heavy data operations such as CURD, search and etc. We use 2 nodes to make sure that for each index we have at least a replica on a different node, so if one node is offline, the cluster is still able to function.

#### Use Kubernetes Persistent Volume

In Kubernetes, usually your applications are stateless, which means it does not matter where the pods running them are deployed and how many times they are restarted, you don't reply on any storage which outlives the life time of the pods. However, it is clearly the opposite case for elasticsearch cluster, as it provides a data service, you don't want to lose your data when one or two pods running elasticsearch application get restarted.

And this is where *Persistent Volume (PV)* comes in to play. A *PV* in Kubernetes is a storage resource in the cluster just like a node is a computing resource in the cluster. The lifecycle of a *PV* is independent to any pods that use it.

A pod uses *PV* via *Persistent Volume Claim (PVC)*, which translates to: I want to claim X size of storage with Y access mode from the cluster. So *PVCs* are like pods, as *PVCs* uses *PV* resource while pods use node resource.

##### Dynamic Provisioning Of PV

When a pod requests *PV* using *PVC* and the cluster can't find a matching *PV* for it, it will try to dynamically provision a *PV* and bind it with the *PVC*. This is called dynamic provisioning. To enable dynamic provisioning, the API server must have been configured to support it, the *PVC* also needs to specify a *StorageClass* because that's what the cluster will refer to when it provisions the *PV*.

#### AWSElasticBlockStore StorageClass and PV

Since the Kuberentes cluster is deployed on AWS EC2 instances, it's nature to use EBS PV. To achieve HA, I assume that you have your node distributed across multiple zones, in this example, let's say we have us-east-1a, us-east-1b and us-east-1c. The first thing to do is to create a *StorageClass* for each zone.

```yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: gp2-us-east-1a
  labels:
    failure-domain.beta.kubernetes.io/region: us-east-1
    failure-domain.beta.kubernetes.io/zone: us-east-1a
    k8s-addon: storage-aws.addons.k8s.io
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp2
  zone: us-east-1a

---

kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: gp2-us-east-1b
  labels:
    failure-domain.beta.kubernetes.io/region: us-east-1
    failure-domain.beta.kubernetes.io/zone: us-east-1b
    k8s-addon: storage-aws.addons.k8s.io
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp2
  zone: us-east-1b

---

kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: gp2-us-east-1c
  labels:
    failure-domain.beta.kubernetes.io/region: us-east-1
    failure-domain.beta.kubernetes.io/zone: us-east-1c
    k8s-addon: storage-aws.addons.k8s.io
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp2
  zone: us-east-1c
```

> Notes: You can specify one StorageClass with zones: us-east-1a,us-east-1b,us-east-1c, however, when you claim volume using this StorageClass, you can't guarantee which zone the EBS volumes the cluster creates lies in, and it's every likely that the EBS volume created lies in a different zone from the node where the pod gets scheduled on, thus the binding can never be successfully. This is the reason why we create multiple StorageClass objects and point each of them to a specific zone.

#### Deploy data nodes using Kubernetes StatefulSet

StatefulSet, on the contrast of Deployment, is used for stateful applications. The major differences between StatefulSet and Deployment are StatefulSet:

- Maintenance a sticky identity of pods.
- Have stable network ID. (with the help of a headless service)
- Have stable and persistent storage.

It makes perfect sense to use StatefulSet to deploy the elasticsearch data nodes, because we want the nodes to be across different zones and we want the persistent EBS volumes to be dynamically created, we need to create two StatefulSet, 1 per zone.

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch-data
  namespace: kube-system
  labels:
    component: elasticsearch
    role: data
spec:
  selector:
    component: elasticsearch
    role: data
  ports:
  - name: transport
    port: 9300
    protocol: TCP
  clusterIP: None

---

apiVersion: apps/v1beta1
kind: StatefulSet
metadata:
  name: es-data-us-east-1a
  namespace: kube-system
  labels:
    component: elasticsearch
    role: data
spec:
  updateStrategy:
    type: RollingUpdate
  serviceName: elasticsearch-data
  replicas: 1
  template:
    metadata:
      labels:
        component: elasticsearch
        role: data
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: failure-domain.beta.kubernetes.io/zone
                operator: In
                values:
                - us-east-1a
      initContainers:
      - name: init-sysctl
        image: busybox:1.27.2
        command:
        - sysctl
        - -w
        - vm.max_map_count=262144
        securityContext:
          privileged: true
      - name: update-volume-permission
        image: busybox:1.27.2
        command:
        - chown
        - -R
        - 1000:1000
        - /data
        volumeMounts:
        - name: storage
          mountPath: /data
        securityContext:
          privileged: true
      containers:
      - name: es-data
        image: docker.elastic.co/elasticsearch/elasticsearch:6.3.0
        env:
        - name: node.name
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: cluster.name
          value: tds-es-db
        - name: discovery.zen.ping.unicast.hosts
          value: "elasticsearch-discovery"
        - name: discovery.zen.minimum_master_nodes
          value: "2"
        - name: node.master
          value: "false"
        - name: node.ingest
          value: "false"
        - name: node.data
          value: "true"
        - name: xpack.ml.enabled
          value: "false"
        - name: xpack.security.enabled
          value: "false"
        - name: xpack.watcher.enabled
          value: "false"
        - name: xpack.graph.enabled
          value: "false"
        - name: xpack.logstash.enabled
          value: "false"
        - name: node.master
          value: "false"
        - name: node.ingest
          value: "false"
        - name: node.data
          value: "true"
        - name: http.enabled
          value: "false"
        - name: ES_JAVA_OPTS
          value: "-Xms2g -Xmx2g"
        - name: network.host
          value: _eth0:ipv4_
        - name: path.data
          value: /data
        resources:
          limits:
            cpu: 0.5
        ports:
        - containerPort: 9300
          name: transport
        livenessProbe:
          tcpSocket:
            port: transport
          initialDelaySeconds: 60
          periodSeconds: 10
        volumeMounts:
        - name: storage
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: storage
    spec:
      storageClassName: gp2-us-east-1a
      accessModes: [ ReadWriteOnce ]
      resources:
        requests:
          storage: 150Gi

---

apiVersion: apps/v1beta1
kind: StatefulSet
metadata:
  name: es-data-us-east-1c
  namespace: kube-system
  labels:
    component: elasticsearch
    role: data
spec:
  updateStrategy:
    type: RollingUpdate
  serviceName: elasticsearch-data
  replicas: 1
  template:
    metadata:
      labels:
        component: elasticsearch
        role: data
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: failure-domain.beta.kubernetes.io/zone
                operator: In
                values:
                - us-east-1c
      initContainers:
      - name: init-sysctl
        image: busybox:1.27.2
        command:
        - sysctl
        - -w
        - vm.max_map_count=262144
        securityContext:
          privileged: true
      - name: update-volume-permission
        image: busybox:1.27.2
        command:
        - chown
        - -R
        - 1000:1000
        - /data
        volumeMounts:
        - name: storage
          mountPath: /data
        securityContext:
          privileged: true
      containers:
      - name: es-data
        image: docker.elastic.co/elasticsearch/elasticsearch:6.3.0
        env:
        - name: node.name
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: cluster.name
          value: tds-es-db
        - name: discovery.zen.ping.unicast.hosts
          value: "elasticsearch-discovery"
        - name: discovery.zen.minimum_master_nodes
          value: "2"
        - name: node.master
          value: "false"
        - name: node.ingest
          value: "false"
        - name: node.data
          value: "true"
        - name: xpack.ml.enabled
          value: "false"
        - name: xpack.security.enabled
          value: "false"
        - name: xpack.watcher.enabled
          value: "false"
        - name: xpack.graph.enabled
          value: "false"
        - name: xpack.logstash.enabled
          value: "false"
        - name: node.master
          value: "false"
        - name: node.ingest
          value: "false"
        - name: node.data
          value: "true"
        - name: http.enabled
          value: "false"
        - name: ES_JAVA_OPTS
          value: "-Xms2g -Xmx2g"
        - name: network.host
          value: _eth0:ipv4_
        - name: path.data
          value: /data
        resources:
          limits:
            cpu: 0.5
        ports:
        - containerPort: 9300
          name: transport
        livenessProbe:
          tcpSocket:
            port: transport
          initialDelaySeconds: 60
          periodSeconds: 10
        volumeMounts:
        - name: storage
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: storage
    spec:
      storageClassName: gp2-us-east-1c
      accessModes: [ ReadWriteOnce ]
      resources:
        requests:
          storage: 150Gi
```

A few highlights in the above configuration file:

- A headless service is created and points to the pods.

- Each StatefulSet is restricted to deploy pods on only 1 zone, with the *PVC* pointing to the StorageClass for that zone.

- We turn off *node.master* so that they are dedicated data nodes.

- In order to let elasticsearch user access to mounted volume, we added a initial container to grant the access to the data path.


#### Deploy master nodes using Kubernetes Deployment

Deploying the master nodes are much easier than data nodes as they don't need persistent storage. We use Deployment to manage that. In order to let the clients access the API, we need to expose the service as well, in my case, I use ingress to expose it.

```yaml
---

apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: elasticsearch-ingress
  namespace: kube-system
  annotations:
    kubernetes.io/ingress.class: "nginx"    
spec:
  rules:
  - host: xxx.xxx.com
    http:
      paths:
      - backend:
          serviceName: elasticsearch
          servicePort: 9200

---

apiVersion: v1
kind: Service
metadata:
  name: elasticsearch-discovery
  namespace: kube-system
  labels:
    component: elasticsearch
    role: master
spec:
  selector:
    component: elasticsearch
    role: master
  ports:
  - name: transport
    port: 9300
    protocol: TCP
  clusterIP: None

---

apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
  namespace: kube-system
  labels:
    component: elasticsearch
    role: master
spec:
  selector:
    component: elasticsearch
    role: master
  type: ClusterIP
  ports:
  - name: http
    protocol: TCP
    port: 9200
    targetPort: 9200

---

apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: es-master
  namespace: kube-system
  labels:
    component: elasticsearch
    role: master
spec:
  replicas: 3
  template:
    metadata:
      labels:
        component: elasticsearch
        role: master
    spec:
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      initContainers:
      - name: init-sysctl
        image: busybox:1.27.2
        command:
        - sysctl
        - -w
        - vm.max_map_count=262144
        securityContext:
          privileged: true
      containers:
      - name: es-master
        image: docker.elastic.co/elasticsearch/elasticsearch:6.3.0
        env:
        - name: node.name
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: cluster.name
          value: tds-es-db
        - name: discovery.zen.ping.unicast.hosts
          value: "elasticsearch-discovery"
        - name: discovery.zen.minimum_master_nodes
          value: "2"
        - name: xpack.ml.enabled
          value: "false"
        - name: xpack.security.enabled
          value: "false"
        - name: xpack.watcher.enabled
          value: "false"
        - name: xpack.graph.enabled
          value: "false"
        - name: xpack.logstash.enabled
          value: "false"
        - name: node.master
          value: "true"
        - name: node.ingest
          value: "false"
        - name: node.data
          value: "false"
        - name: http.enabled
          value: "true"
        - name: ES_JAVA_OPTS
          value: "-Xms512m -Xmx512m"
        - name: network.host
          value: _eth0:ipv4_
        resources:
          limits:
            cpu: 0.5
        ports:
        - containerPort: 9200
          name: http
        - containerPort: 9300
          name: transport
        livenessProbe:
          tcpSocket:
            port: transport
          initialDelaySeconds: 60
        readinessProbe:
          httpGet:
            path: /_cluster/health
            port: http
          initialDelaySeconds: 60
          timeoutSeconds: 5
        volumeMounts:
        - name: storage
          mountPath: /data
      volumes:
          - emptyDir:
              medium: ""
            name: "storage"
```

Some highlights in the above configuration:

- *node.master* is enabled and *node.data* is disabled

- A 60 seconds waiting time are set to allow the pods become alive and to able to health checked

> Notes: when you kubectl apply to deploy the data nodes, you might encounter timeout for binding the EBS volumes, don't panic, just do it again. It's because it takes time for AWS to provision the volume and make it become available to mount.

#### Deploy Kibana to visualise your elasticsearch data

Your fluentd + elasticsearch cluster combination should be working fine now, check the status by running:

```bash
curl -X GET \
  'http://your.exposed.elasticsearch.domain/_cluster/health?pretty='

{
    "cluster_name": "xx-xx-xxx",
    "status": "green",
    "timed_out": false,
    "number_of_nodes": 5,
    "number_of_data_nodes": 2,
    "active_primary_shards": 46,
    "active_shards": 92,
    "relocating_shards": 0,
    "initializing_shards": 0,
    "unassigned_shards": 0,
    "delayed_unassigned_shards": 0,
    "number_of_pending_tasks": 0,
    "number_of_in_flight_fetch": 0,
    "task_max_waiting_in_queue_millis": 0,
    "active_shards_percent_as_number": 100
}
```

Now to play with your data, you might want to install Kibana, it's quite straightforward, we just need to deploy 1 instance of Kibana using Deployment, and we also expose the service using Ingress so that we can access it.

```yaml
---

apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: kibana-ingress
  namespace: kube-system
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
  - host: xxx.xxx.xxx
    http:
      paths:
      - backend:
          serviceName: kibana
          servicePort: 80
---

apiVersion: v1
kind: Service
metadata:
  name: kibana
  namespace: kube-system
  labels:
    component: kibana
spec:
  selector:
    component: kibana
  ports:
  - name: http
    port: 80
    targetPort: http
---

apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: kibana
  namespace: kube-system
  labels:
    component: kibana
spec:
  replicas: 1
  selector:
    matchLabels:
     component: kibana
  template:
    metadata:
      labels:
        component: kibana
    spec:
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      containers:
      - name: kibana
        image: docker.elastic.co/kibana/kibana:6.3.0
        env:
        - name: ELASTICSEARCH_URL
          value: "http://elasticsearch:9200"
        - name: CLUSTER_NAME
          value: tds-es-db
        - name: XPACK_SECURITY_ENABLED
          value: "false"
        - name : XPACK_GRAPH_ENABLED
          value: "false"
        - name : XPACK_REPORTING_ENABLED
          value: "false"
        - name : XPACK_ML_ENABLED
          value: "false"
        resources:
          limits:
            cpu: 200m
          requests:
            cpu: 100m
        ports:
        - containerPort: 5601
          name: http

```

Go to your Kibana website and create an index pattern like **logstash-***, you should see all the available fields extracted from your applications' logs and the kubernetes meta data.

![](kibana_index.jpg)

You can now use the Kibana's Discover to monitor and query all of your application logs, happy monitoring!

![](kibana_monitoring_in_action.jpg)
