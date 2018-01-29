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

And we're gonna deploy other key add-ons using the kubenertes cluster
- heapster
- kubernetes-dashboard
- kube-dns
- kube-flannel
- kube-proxy
- pod-checkpointer
- ingress-controller

In additional, we'll add a custom namespace for deploying my workload, to isolate them from the kube-system apps.

We take advantage of `bootkube` to serve the purpose. `bootkube` introduces the concept of `self-hosted control panel for kubernetes`. It means that Kubernetes runs all required and optional components of a Kubernetes cluster on top of Kubernetes itself, the detailed introduction can be found [here](https://github.com/kubernetes/community/blob/master/contributors/design-proposals/cluster-lifecycle/self-hosted-kubernetes.md). In a nutshell, `bootkube` provides a temporary Kubernetes control plane that tells a kubelet to execute all of the components necessary to run a full blown Kubernetes control plane.

To make `bootkube` run with `bootkbe start`, we have to prepare the specs in a folder structures like this:
- auth
  * kubeconfig
- bootstrap-manifests
  * bootstrap-apiserver.yaml
  * bootstrap-controller-manager.yaml
  * bootstrap-scheduler.ymal
- manifests
  * default-backend.yaml
  * heapster.yaml
  * ingress-controller.yaml
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

The `bootkube` service is defined as follows:

```bash
[Unit]
Description=Bootstrap a Kubernetes cluster
ConditionPathExists=!/opt/bootkube/init_bootkube.done
[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=/opt/bootkube
User=root
Group=root
ExecStart=/usr/bin/bash /opt/bootkube/bootkube.sh
ExecStartPost=/bin/touch /opt/bootkube/init_bootkube.done
[Install]
WantedBy=multi-user.target
```

It defines a one-shot service that runs only once as it's name indicates, let's take a look at the shell script it's running:

```bash
#!/bin/bash

# start bootkube to bootstrap kubernetes
/usr/bin/rkt run \
  --trust-keys-from-https \
  --volume assets,kind=host,source="$(pwd)"/assets \
  --mount volume=assets,target=/assets \
  --volume etc-kubernetes,kind=host,source=/etc/kubernetes \
  --mount volume=etc-kubernetes,target=/etc/kubernetes \
  "quay.io/coreos/bootkube:v0.6.2" \
  --net=host \
  --dns=host \
  --exec=/bootkube -- start --asset-dir=/assets
```

This starts the `bootkube` process on the above prepared assets, and it will go through the following stages:

1. `tls` folder and `bootstrap-manifests` folder will be copied to /etc/kubenetes/ as `bootstrap-secrets` and `manifests`
2. By define the `kubelet` agent will pick of the manifests and run the pods defined there, which will give us the temporary control panel
3. It will then run through the `manifests` folder and create all the objects defined inside.
4. Once the new control panel components are up and running, bootkube will destroy the temporary control panel and remove the temporary assets.
5. Up to this point, the final Kubernetes cluster is up and running.

> Tips:
> 1. In the final api server definition, you'll have to set the --apiserver-count to 3 in order to kubenertes services to pick up 3 endpoints.
> 2. There are many certs and keys to set for TLS security, be careful as if wrong files are used, thing will break.
> 3. There're a few services defines at the same time, since we've reserved an IP for DNS service, we'll have to pre-define the cluster IP for all other services being bootstrapped here so that they won't occupy the cluster IP for the DNS service if they get created first.

Let's have a brief introduction for the add-ons we'll deploy:

- flannel: provides cluster level container networking, it enables containers on different nodes to reach each other.

- proxy: provides in-cluster traffic proxying and load balancing for services, to be specific, it routes traffic to a service to its underlying pods.

- dns: provides in-cluster DNS resolution for services. e.g. a service can be found at service-name.namespace.svc.cluster-dns-name, a pod can be found at pod-ip-address.namespace.pod.cluster-dns-name

- heapster: provides nodes resource usage analysis and monitoring.

- pod-checkpointer: provides disaster recovery, it ensures that existing local pod state can be recovered in the absence of an api-server.

- dashboard: provides the information of you cluster and enables you to manipulate your cluster.

- ingress-controller: provides entry points for the Internet to use the services inside the cluster.

Other resources that gets created:

- role-binding: Kubernetes supports Role Based Access Control (RBAC), this binds the default service account in the kube-system namespace to the cluster-admin role, which grants applications under this service account full access to the cluster resources.

- namespace: creates a new namespace called tds-cloud, you can change it to whatever you like.

To view all the assets, click here [bootkube](https://github.com/WUMUXIAN/ha-kubernetes-cluster-vagrant/tree/master/provisioning/roles/bootkube)

The [VagrantFile](https://github.com/WUMUXIAN/ha-kubernetes-cluster-vagrant/blob/master/Vagrantfile) is also used to generate the relevant tls resources and secrets referred to by the specs.

```ruby
if recreated_required || !File.directory?("provisioning/roles/bootkube/files/tls")
      FileUtils::mkdir_p 'provisioning/roles/bootkube/files/tls'
      FileUtils::mkdir_p 'provisioning/roles/bootkube/templates/manifests'

      kube_cert_raw = File.read("provisioning/roles/kubelet/files/tls/ca.crt")
      kube_cert = OpenSSL::X509::Certificate.new(kube_cert_raw)
      kube_key_raw = File.read("provisioning/roles/kubelet/files/tls/ca.key")
      kube_key = OpenSSL::PKey::RSA.new(kube_key_raw)

      etcd_cert_raw = File.read("provisioning/roles/etcd/files/tls/ca.crt")
      etcd_cert = OpenSSL::X509::Certificate.new(etcd_cert_raw)
      etcd_client_cert_raw = File.read("provisioning/roles/etcd/files/tls/etcd-client.crt")
      etcd_client_cert = OpenSSL::X509::Certificate.new(etcd_client_cert_raw)
      etcd_client_key_raw = File.read("provisioning/roles/etcd/files/tls/etcd-client.key")
      etcd_client_key = OpenSSL::PKey::RSA.new(etcd_client_key_raw)

      # START APISERVER
      apiserver_key = OpenSSL::PKey::RSA.new(2048)
      apiserver_public_key = apiserver_key.public_key

      apiserver_cert = signTLS(is_ca:              false,
                               subject:            "/C=SG/ST=Singapore/L=Singapore/O=kube-master/OU=IT/CN=kube-apiserver",
                               issuer_subject:     "/C=SG/ST=Singapore/L=Singapore/O=bootkube/OU=IT/CN=kube-ca",
                               issuer_cert:        kube_cert,
                               public_key:         apiserver_public_key,
                               ca_private_key:     kube_key,
                               key_usage:          "digitalSignature,keyEncipherment",
                               extended_key_usage: "serverAuth,clientAuth",
                               san:                "DNS:kubernetes,DNS:kubernetes.default,DNS:kubernetes.default.svc,DNS:kubernetes.default.svc.cluster.local,#{IPs.join(',')},IP:10.3.0.1")

      apiserver_file_tls = File.new("provisioning/roles/bootkube/files/tls/apiserver.crt", "wb")
      apiserver_file_tls.syswrite(apiserver_cert.to_pem)
      apiserver_file_tls.close
      apiserver_key_file= File.new("provisioning/roles/bootkube/files/tls/apiserver.key", "wb")
      apiserver_key_file.syswrite(apiserver_key.to_pem)
      apiserver_key_file.close
      # END APISERVER

      # START SERVICE ACCOUNT
      service_account_key = OpenSSL::PKey::RSA.new(2048)
      service_account_pubkey = service_account_key.public_key

      service_account_key_file= File.new("provisioning/roles/bootkube/files/tls/service-account.key", "wb")
      service_account_key_file.syswrite(service_account_key.to_pem)
      service_account_key_file.close
      service_account_pubkey_file= File.new("provisioning/roles/bootkube/files/tls/service-account.pub", "wb")
      service_account_pubkey_file.syswrite(service_account_pubkey.to_pem)
      service_account_pubkey_file.close
      # END SERVICE ACCOUNT

      # START BOOTKUBE MANIFESTS
      data = File.read("provisioning/roles/bootkube/files/kube-apiserver-secret.tmpl")
      data = data.gsub("{{CA_CRT}}", Base64.strict_encode64(kube_cert.to_pem))
      data = data.gsub("{{APISERVER_CRT}}", Base64.strict_encode64(apiserver_cert.to_pem))
      data = data.gsub("{{APISERVER_KEY}}", Base64.strict_encode64(apiserver_key.to_pem))
      data = data.gsub("{{SERVICE_ACCOUNT_PUB}}", Base64.strict_encode64(service_account_pubkey.to_pem))
      data = data.gsub("{{ETCD_CA_CRT}}", Base64.strict_encode64(etcd_cert.to_pem))
      data = data.gsub("{{ETCD_CLIENT_CRT}}", Base64.strict_encode64(etcd_client_cert.to_pem))
      data = data.gsub("{{ETCD_CLIENT_KEY}}", Base64.strict_encode64(etcd_client_key.to_pem))

      kubeconfig_file_etc = File.new("provisioning/roles/bootkube/templates/manifests/kube-apiserver-secret.yaml.j2", "wb")
      kubeconfig_file_etc.syswrite(data)
      kubeconfig_file_etc.close

      data = File.read("provisioning/roles/bootkube/files/kube-controller-manager-secret.tmpl")
      data = data.gsub("{{CA_CRT}}", Base64.strict_encode64(kube_cert.to_pem))
      data = data.gsub("{{SERVICE_ACCOUNT_KEY}}", Base64.strict_encode64(service_account_key.to_pem))


      kubeconfig_file_etc = File.new("provisioning/roles/bootkube/templates/manifests/kube-controller-manager-secret.yaml.j2", "wb")
      kubeconfig_file_etc.syswrite(data)
      kubeconfig_file_etc.close
      # END BOOTKUBE MANIFESTS
    end
```

> Tips: You have to specify the domains and IP you pre-defined for your api server in the san field in your api server server.crt to make TLS work properly.

Now let's take a look at the tasks in the bootkube role:

```yaml
########################################
# Bootstrap kubernetes using bootkube  #
########################################

- name: Make sure the bootkube directory exists
  run_once: true
  file:
    path: "{{ bootkube_directory }}/{{ item }}"
    state: directory
  with_items:
    - assets/tls
    - assets/manifests
    - assets/auth
    - assets/bootstrap-manifests

- name: Repalce the kubeconfig file
  run_once: true
  copy:
    remote_src: true
    src: "/etc/kubernetes/kubeconfig"
    dest: "{{ bootkube_directory }}/assets/auth/kubeconfig"

- name: Copy over the certs and keys
  run_once: true
  copy:
    src: "./{{ item }}"
    dest: "{{ bootkube_directory }}/assets/{{ item }}"
  with_items:
    - tls/apiserver.crt
    - tls/apiserver.key
    - tls/service-account.key
    - tls/service-account.pub

- name: Copy over the certs and keys from remote
  run_once: true
  copy:
    remote_src: true
    src: "{{ item.0 }}"
    dest: "{{ bootkube_directory }}/assets/tls/{{ item.1 }}"
  with_together:
    - ["/etc/ssl/etcd/ca.crt","/etc/ssl/etcd/etcd-client.key","/etc/ssl/etcd/etcd-client.crt","/etc/kubernetes/ca.crt","/etc/kubernetes/ca.key"]
    - ["etcd-client-ca.crt","etcd-client.key","etcd-client.crt","ca.crt","ca.key"]

- name: Generate kubelet.key and kubelet.crt
  run_once: true
  shell: "grep '{{ item.0 }}' /etc/kubernetes/kubeconfig | awk '{print $2}' | base64 -d > {{ bootkube_directory }}/assets/tls/{{ item.1 }}"
  with_together:
    - ["client-key-data", "client-certificate-data"]
    - ["kubelet.key", "kubelet.crt"]

- name: Copy bootstrap-manifests
  run_once: true
  template:
    src: "./bootstrap-manifests/{{ item }}.j2"
    dest: "{{ bootkube_directory }}/assets/bootstrap-manifests/{{ item }}"
  with_items:
    - bootstrap-apiserver.yaml
    - bootstrap-controller-manager.yaml
    - bootstrap-scheduler.yaml

- name: Copy manifests
  run_once: true
  template:
    src: "./manifests/{{ item }}.j2"
    dest: "{{ bootkube_directory }}/assets/manifests/{{ item }}"
  with_items:
    - kube-apiserver-secret.yaml
    - kube-apiserver.yaml
    - kube-controller-manager-disruption.yaml
    - kube-controller-manager-secret.yaml
    - kube-controller-manager.yaml
    - kube-dns.yaml
    - kube-flannel.yaml
    - kube-proxy.yaml
    - kube-scheduler-disruption.yaml
    - kube-scheduler.yaml
    - kube-system-rbac-role-binding.yaml
    - pod-checkpointer.yaml
    - heapster.yaml
    - kube-dashboard.yaml
    - namespace.yaml
    - default-backend.yaml
    - ingress-controller.yaml

- name: Copy over the bootkube.sh
  run_once: true
  template:
    src: bootkube.sh.j2
    dest: "{{ bootkube_directory }}/bootkube.sh"
    mode: u+x

- name: Create the bootkube service
  run_once: true
  copy:
    src: bootkube.service
    dest: /etc/systemd/system/bootkube.service

- name: Enable and start bootkube service
  run_once: true
  systemd:
    no_block: yes
    name: bootkube
    state: started
    daemon_reload: yes

- name: Download the kubectl command line tool
  get_url:
    url: https://storage.googleapis.com/kubernetes-release/release/v1.7.0/bin/linux/amd64/kubectl
    dest: ./kubectl
    mode: "u+x"

```

Add the bootkube role into the playbook.yaml

```yaml
################################
# Bootstrap kubernetes cluster #
################################

- name: bootkube
  hosts: master03
  become: true
  gather_facts: True
  roles:
    - bootkube
```

Note that it has to run on one of the master once only to bootstrap the cluster, here we select `master03`.

Run the provisioning to bring the cluster up:

```bash
vagrant up --provision
.....
.....
.....
.....

master03: Kubernetes is starting. As a progress check, the list of running pods
master03:  will be periodically printed.
master03: NOTE: this may take 20 minutes or more depending on Internet throughput.
master03: ~1GB of data will be downloaded.

.....
.....
.....
.....

master03: NAME                                           READY     STATUS    RESTARTS   AGE
master03: heapster-2916422426-5qdsn                      2/2       Running   2          3d
master03: kube-apiserver-qqlk9                           1/1       Running   1          3d
master03: kube-apiserver-t5n11                           1/1       Running   1          3d
master03: kube-apiserver-xrrdx                           1/1       Running   1          3d
master03: kube-controller-manager-2058582590-5htg3       1/1       Running   1          3d
master03: kube-dns-2425598031-9w0nv                      3/3       Running   3          3d
master03: kube-flannel-1x8n1                             2/2       Running   4          3d
master03: kube-flannel-2s893                             2/2       Running   3          3d
master03: kube-flannel-wctf8                             2/2       Running   3          3d
master03: kube-flannel-z5dps                             2/2       Running   3          3d
master03: kube-proxy-8gzb8                               1/1       Running   1          3d
master03: kube-proxy-g8z33                               1/1       Running   1          3d
master03: kube-proxy-ql4mp                               1/1       Running   1          3d
master03: kube-proxy-t6bjw                               1/1       Running   1          3d
master03: kube-scheduler-2957171631-8ltmz                1/1       Running   1          3d
master03: kubernetes-dashboard-331296467-2vd4f           1/1       Running   1          3d
master03: pod-checkpointer-0s0d1                         1/1       Running   1          3d
master03: pod-checkpointer-0s0d1-master03.tdskubes.com   1/1       Running   1          3d
master03: pod-checkpointer-68wkg                         1/1       Running   1          3d
master03: pod-checkpointer-68wkg-master01.tdskubes.com   1/1       Running   1          3d
master03: pod-checkpointer-d2j8b                         1/1       Running   1          3d
master03: pod-checkpointer-d2j8b-master02.tdskubes.com   1/1       Running   1          3d
master03: Kubernetes has started successfully!
master03:
master03: Setup your local kubelet, after your configure it properly and set the context to vagrant, you can login to the dashboard by running
master03:
master03:   kubelet proxy
master03:
master03:   Dashboard address: http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/
master03:
master03:   The login token is:
master03:   xxxxxxxxxxxx
```

To take a look at your cluster, you should configure your kubectl to use the kubeconfig secrets and run

```bash
kubeclt proxy
```

Once the proxy is running, you can access your cluster using the dashboard URL locally from your browser `http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/`

Choose the toke from outputted from the above to authenticate yourself and once you login you'll find your workload for kube-system as follows:

![Dashboard](dashboard-ui.jpg)

Up to this point, your Kubenertes cluster with 3 masters and 1 worker is up and running. In [part 5](http://blog.wumuxian1988.com/2018/01/12/HA-Kubernetes-cluster-with-Vagrant-CoreOS-Ansible-Part-5/), we'll deploy some services on the cluster and expose the services using `Ingress`.
