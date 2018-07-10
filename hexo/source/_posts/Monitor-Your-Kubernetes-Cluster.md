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

### The node_exporter for nodes metrics

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

### The kube-state-metrics for Kubernetes Cluster metrics

We can collect Kubernetes cluster metrics via **kube-state-metrics**, which is the new official tool provided by the Kubernetes community that outputs prometheus format of metrics for monitoring purpose. The **kube-state-metrics** talks to kube-api-server to generate metrics about the state of objects, so different from node exporter, we don't run it on every node as DaemonSet, instead we only deploy it as a deployment with 1 replicaset.

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

In the above yaml definition, the same as the node exporter, we create roles with the minimum access requirement and bind them to the service account we created specifically for the **kube-state-metrics** service. We will then deploy it via Deployment, expose a headless service and define a ServiceMonitor to scape the metrics and send to Prometheus.

### Scrape containers metrics from kubelet

```
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  labels:
    k8s-app: kubelet
  name: kubelet
  namespace: monitoring
spec:
  endpoints:
  - bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
    interval: 30s
    port: https-metrics
    scheme: https
    tlsConfig:
      insecureSkipVerify: true
  - bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
    honorLabels: true
    interval: 30s
    path: /metrics/cadvisor
    port: https-metrics
    scheme: https
    tlsConfig:
      insecureSkipVerify: true
  jobLabel: k8s-app
  namespaceSelector:
    matchNames:
    - kube-system
  selector:
    matchLabels:
      k8s-app: kubelet
```

The **kubelet** exports prometheus format metrics at the endpoint **/metrics/cadvisor**. Please note that the kubelet is not self-hosted by Kubernetes, thus there's actually no such service to select by the selector for the ServiceMonitor. Therefore the Prometheus Operator implements a functionality to synchronize the kubelets into an Endpoints object. To make use of that functionality the --kubelet-service argument must be passed to the Prometheus Operator when running it, it will then emulate as it there's a kubelet service running inside the Kubernetes cluster.

```
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  labels:
    k8s-app: prometheus-operator
  name: prometheus-operator
spec:
  replicas: 1
  template:
    metadata:
      labels:
        k8s-app: prometheus-operator
    spec:
      containers:
      - args:
        - --kubelet-service=kube-system/kubelet
        - --config-reloader-image=quay.io/coreos/configmap-reload:v0.0.1
        image: quay.io/coreos/prometheus-operator:v0.17.0
        name: prometheus-operator
        ports:
        - containerPort: 8080
          name: http
        resources:
          limits:
            cpu: 200m
            memory: 100Mi
          requests:
            cpu: 100m
            memory: 50Mi
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
      serviceAccountName: prometheus-operator
```

### Monitor other Kubernetes components

Aside from **kubelet**, the other Kubernetes components are self-hosted mostly. Thus to collect metrics from them, we simply need to expose them with a headless service and define ServiceMonitors for them. Please note that for API server, a **kubernetes** service is already exposed in the default namespace, so there is no extra action to take to discover the API server.

```
apiVersion: v1
kind: Service
metadata:
  namespace: kube-system
  name: kube-scheduler-prometheus-discovery
  labels:
    k8s-app: kube-scheduler
spec:
  selector:
    k8s-app: kube-scheduler
  type: ClusterIP
  clusterIP: None
  ports:
  - name: http-metrics
    port: 10251
    targetPort: 10251
    protocol: TCP

apiVersion: v1
kind: Service
metadata:
  namespace: kube-system
  name: kube-controller-manager-prometheus-discovery
  labels:
    k8s-app: kube-controller-manager
spec:
  selector:
    k8s-app: kube-controller-manager
  type: ClusterIP
  clusterIP: None
  ports:
  - name: http-metrics
    port: 10252
    targetPort: 10252
    protocol: TCP

---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  labels:
    k8s-app: kube-controller-manager
  name: kube-controller-manager
  namespace: monitoring
spec:
  endpoints:
  - interval: 30s
    port: http-metrics
  jobLabel: k8s-app
  namespaceSelector:
    matchNames:
    - kube-system
  selector:
    matchLabels:
      k8s-app: kube-controller-manager
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  labels:
    k8s-app: kube-scheduler
  name: kube-scheduler
  namespace: monitoring
spec:
  endpoints:
  - interval: 30s
    port: http-metrics
  jobLabel: k8s-app
  namespaceSelector:
    matchNames:
    - kube-system
  selector:
    matchLabels:
      k8s-app: kube-scheduler

---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  labels:
    k8s-app: apiserver
  name: kube-apiserver
  namespace: monitoring
spec:
  endpoints:
  - bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
    interval: 30s
    port: https
    scheme: https
    tlsConfig:
      caFile: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      serverName: kubernetes
  jobLabel: component
  namespaceSelector:
    matchNames:
    - default
  selector:
    matchLabels:
      component: apiserver
      provider: kubernetes
```

### Metrics for your containerized applications

Up to this point, I think you should already understand how promethus works. In order to monitor a application, you need to export an endpoint at a defined path, using which the ServiceMonitor can scape prometheus format metrics. You will then need to export the service for the application and define a ServiceMonitor to do the scraping job.

## How it looks for Prometheus Operator deployment

After you deploy Prometheus Operator, give the system sometime to create the objects, if you encounter an error for the first, just re-run `kubelet apply` again.
We can check the status of the deployment by running:

```
kubectl get -n monitoring pods

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

You should have alertmanager, grafana, node-exporter, promethus and prometheus-operator running as expected.

## Predefined Dashboards

After your Prometheus cluster is up and running, you can notice that a pod of **Grafana** is up and running, the user name and password is both **admin**.

Using datasource from the Prometheus cluster, there are a few pre-defined dashboards already showing your cluster/nodes/pods status.

![](grafana_default_dashboards.png)

![](grafana.png)

## Summary

Prometheus Operator provides an easy end-to-end monitoring system for you Kubernetes cluster. It does most of the heavy lift and has a lot of pre-defined metrics for different components, as well the dashboards to visualize the mtrics and the alarms on abnormality. To extend it for monitoring any of your containerized application metrics, as a user, the majority of your work will be:

- Write code using Prometheus SDK in your application to expose your desired metrics via an endpoint.
- Expose your application with a Service, you can make the Service headless if you don't want it to be accessible from out of the Cluster.
- Define ServiceMonitor to scape the your metrics from the service.
- Define Grafana dashboard to visualize your metrics from promethus datasource.
- Define Alarms for your metrics.
