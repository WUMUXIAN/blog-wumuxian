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

### Node exporter

Node exporter runs on each node, thus we can deploy them via DaemonSet.

```yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-exporter
rules:
- apiGroups:
  - authentication.k8s.io
  resources:
  - tokenreviews
  verbs:
  - create
- apiGroups:
  - authorization.k8s.io
  resources:
  - subjectaccessreviews
  verbs:
  - create
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: node-exporter
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: node-exporter
subjects:
- kind: ServiceAccount
  name: node-exporter
  namespace: monitoring
---
apiVersion: apps/v1beta2
kind: DaemonSet
metadata:
  labels:
    app: node-exporter
  name: node-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      containers:
      - args:
        - --web.listen-address=127.0.0.1:9101
        - --path.procfs=/host/proc
        - --path.sysfs=/host/sys
        image: quay.io/prometheus/node-exporter:v0.15.2
        name: node-exporter
        resources:
          limits:
            cpu: 102m
            memory: 180Mi
          requests:
            cpu: 102m
            memory: 180Mi
        volumeMounts:
        - mountPath: /host/proc
          name: proc
          readOnly: false
        - mountPath: /host/sys
          name: sys
          readOnly: false
      - args:
        - --secure-listen-address=:9100
        - --upstream=http://127.0.0.1:9101/
        image: quay.io/coreos/kube-rbac-proxy:v0.3.0
        name: kube-rbac-proxy
        ports:
        - containerPort: 9100
          name: https
        resources:
          limits:
            cpu: 20m
            memory: 40Mi
          requests:
            cpu: 10m
            memory: 20Mi
      nodeSelector:
        beta.kubernetes.io/os: linux
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
      serviceAccountName: node-exporter
      tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/master
      volumes:
      - hostPath:
          path: /proc
        name: proc
      - hostPath:
          path: /sys
        name: sys
---
apiVersion: v1
kind: Service
metadata:
  labels:
    k8s-app: node-exporter
  name: node-exporter
  namespace: monitoring
spec:
  clusterIP: None
  ports:
  - name: https
    port: 9100
    targetPort: https
  selector:
    app: node-exporter
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: node-exporter
  namespace: monitoring
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  labels:
    k8s-app: node-exporter
  name: node-exporter
  namespace: monitoring
spec:
  endpoints:
  - bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
    interval: 30s
    port: https
    scheme: https
    tlsConfig:
      insecureSkipVerify: true
  jobLabel: k8s-app
  namespaceSelector:
    matchNames:
    - monitoring
  selector:
    matchLabels:
      k8s-app: node-exporter
```

In the above yaml file, we specified a service account for node exporter and bind it with a cluster role with the permission to create tokenreviews. We then deploy the node exporter pods via DaemonSet and expose a headless service for these pods and specify a **ServiceMonitor**, which will scrape the metrics from the service and send to prometheus.

### kube-state-metrics

We can collect Kubernetes cluster metrics via **kube-state-metrics**, which is the new official tool that outputs prometheus format of metrics provided by the Kubernetes community for monitoring purpose. Different from node exporter, we don't need to have

```yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kube-state-metrics
rules:
- apiGroups:
  - ""
  resources:
  - configmaps
  - secrets
  - nodes
  - pods
  - services
  - resourcequotas
  - replicationcontrollers
  - limitranges
  - persistentvolumeclaims
  - persistentvolumes
  - namespaces
  - endpoints
  verbs:
  - list
  - watch
- apiGroups:
  - extensions
  resources:
  - daemonsets
  - deployments
  - replicasets
  verbs:
  - list
  - watch
- apiGroups:
  - apps
  resources:
  - statefulsets
  verbs:
  - list
  - watch
- apiGroups:
  - batch
  resources:
  - cronjobs
  - jobs
  verbs:
  - list
  - watch
- apiGroups:
  - autoscaling
  resources:
  - horizontalpodautoscalers
  verbs:
  - list
  - watch
- apiGroups:
  - authentication.k8s.io
  resources:
  - tokenreviews
  verbs:
  - create
- apiGroups:
  - authorization.k8s.io
  resources:
  - subjectaccessreviews
  verbs:
  - create
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kube-state-metrics
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kube-state-metrics
subjects:
- kind: ServiceAccount
  name: kube-state-metrics
  namespace: monitoring
---
apiVersion: apps/v1beta2
kind: Deployment
metadata:
  labels:
    app: kube-state-metrics
  name: kube-state-metrics
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kube-state-metrics
  template:
    metadata:
      labels:
        app: kube-state-metrics
    spec:
      containers:
      - args:
        - --secure-listen-address=:8443
        - --upstream=http://127.0.0.1:8081/
        image: quay.io/coreos/kube-rbac-proxy:v0.3.0
        name: kube-rbac-proxy-main
        ports:
        - containerPort: 8443
          name: https-main
        resources:
          limits:
            cpu: 20m
            memory: 40Mi
          requests:
            cpu: 10m
            memory: 20Mi
      - args:
        - --secure-listen-address=:9443
        - --upstream=http://127.0.0.1:8082/
        image: quay.io/coreos/kube-rbac-proxy:v0.3.0
        name: kube-rbac-proxy-self
        ports:
        - containerPort: 9443
          name: https-self
        resources:
          limits:
            cpu: 20m
            memory: 40Mi
          requests:
            cpu: 10m
            memory: 20Mi
      - args:
        - --host=127.0.0.1
        - --port=8081
        - --telemetry-host=127.0.0.1
        - --telemetry-port=8082
        image: quay.io/coreos/kube-state-metrics:v1.3.0
        name: kube-state-metrics
        resources:
          limits:
            cpu: 102m
            memory: 180Mi
          requests:
            cpu: 102m
            memory: 180Mi
      - command:
        - /pod_nanny
        - --container=kube-state-metrics
        - --cpu=100m
        - --extra-cpu=2m
        - --memory=150Mi
        - --extra-memory=30Mi
        - --threshold=5
        - --deployment=kube-state-metrics
        env:
        - name: MY_POD_NAME
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.name
        - name: MY_POD_NAMESPACE
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.namespace
        image: quay.io/coreos/addon-resizer:1.0
        name: addon-resizer
        resources:
          limits:
            cpu: 10m
            memory: 30Mi
          requests:
            cpu: 10m
            memory: 30Mi
      nodeSelector:
        beta.kubernetes.io/os: linux
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
      serviceAccountName: kube-state-metrics
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: kube-state-metrics
  namespace: monitoring
rules:
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
- apiGroups:
  - extensions
  resourceNames:
  - kube-state-metrics
  resources:
  - deployments
  verbs:
  - get
  - update
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: kube-state-metrics
  namespace: monitoring
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: kube-state-metrics
subjects:
- kind: ServiceAccount
  name: kube-state-metrics
---
apiVersion: v1
kind: Service
metadata:
  labels:
    k8s-app: kube-state-metrics
  name: kube-state-metrics
  namespace: monitoring
spec:
  clusterIP: None
  ports:
  - name: https-main
    port: 8443
    targetPort: https-main
  - name: https-self
    port: 9443
    targetPort: https-self
  selector:
    app: kube-state-metrics
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kube-state-metrics
  namespace: monitoring
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  labels:
    k8s-app: kube-state-metrics
  name: kube-state-metrics
  namespace: monitoring
spec:
  endpoints:
  - bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
    honorLabels: true
    interval: 30s
    port: https-main
    scheme: https
    tlsConfig:
      insecureSkipVerify: true
  - bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
    interval: 30s
    port: https-self
    scheme: https
    tlsConfig:
      insecureSkipVerify: true
  jobLabel: k8s-app
  namespaceSelector:
    matchNames:
    - monitoring
  selector:
    matchLabels:
      k8s-app: kube-state-metrics
```

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
