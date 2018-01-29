---
title: 'HA Kubernetes cluster with Vagrant+CoreOS+Ansible, Part 3'
date: 2018-01-12 14:17:01
tags:
 - Kubernetes
 - Docker
 - Vagrant
 - CoreOS
category:
 - DevOps
---

In [part 2](http://blog.wumuxian1988.com/2018/01/10/HA-Kubernetes-cluster-with-Vagrant-CoreOS-Ansible-Part-2/) we have installed etcd clusters on the 3 master machines, which is the foundation of the Kubernetes cluster. In this part, we're gonna configure and run `kubelet` on each nodes. `kubelet` is the primary node agent that manages pods on each nodes and talks to the Kubernetes api server to coordinate the whole system.

#### Prepare the certs and keys for kubelet
The first thing we do is to prepare the certs and keys required by kubelet for authentication and authorisation and generate a kubeconfig file to be passed in as parameter.

Add the following code in the VagrantFile behind the `ETCD` part, the full content VagrantFile can be found at [here](https://github.com/WUMUXIAN/ha-kubernetes-cluster-vagrant/blob/master/Vagrantfile).

```ruby
# If the tls files for Kubernetes does not exist, create them
if !File.directory?("provisioning/roles/kubelet/files/tls")
  FileUtils::mkdir_p 'provisioning/roles/kubelet/files/tls'
  recreated_required = true
  # BEGIN KUBE CA
  kube_key = OpenSSL::PKey::RSA.new(2048)
  kube_public_key = kube_key.public_key
  kube_cert = signTLS(is_ca:          true,
                      subject:        "/C=SG/ST=Singapore/L=Singapore/O=bootkube/OU=IT/CN=kube-ca",
                      public_key:     kube_public_key,
                      ca_private_key: kube_key,
                      key_usage:      "digitalSignature,keyEncipherment,keyCertSign")

  kube_file_tls = File.new("provisioning/roles/kubelet/files/tls/ca.crt", "wb")
  kube_file_tls.syswrite(kube_cert.to_pem)
  kube_file_tls.close
  kube_key_file= File.new("provisioning/roles/kubelet/files/tls/ca.key", "wb")
  kube_key_file.syswrite(kube_key.to_pem)
  kube_key_file.close
  # END KUBE CA

  # BEGIN KUBE CLIENT (KUBELET)
  client_key = OpenSSL::PKey::RSA.new(2048)
  client_public_key = client_key.public_key

  client_cert = signTLS(is_ca:              false,
                        subject:            "/C=SG/ST=Singapore/L=Singapore/O=system:masters/OU=IT/CN=kubelet",
                        issuer_subject:     "/C=SG/ST=Singapore/L=Singapore/O=bootkube/OU=IT/CN=kube-ca",
                        issuer_cert:        kube_cert,
                        public_key:         client_public_key,
                        ca_private_key:     kube_key,
                        key_usage:          "digitalSignature,keyEncipherment",
                        extended_key_usage: "serverAuth,clientAuth")

  client_file_tls = File.new("provisioning/roles/kubelet/files/tls/kubelet.crt", "wb")
  client_file_tls.syswrite(client_cert.to_pem)
  client_file_tls.close
  client_key_file= File.new("provisioning/roles/kubelet/files/tls/kubelet.key", "wb")
  client_key_file.syswrite(client_key.to_pem)
  client_key_file.close
  # END CLIENT

  # START KUBECONFIG
  data = File.read("provisioning/roles/kubelet/templates/kubeconfig.tmpl")
  data = data.gsub("{{CA_CERT}}", Base64.strict_encode64(kube_cert.to_pem))
  data = data.gsub("{{CLIENT_CERT}}", Base64.strict_encode64(client_cert.to_pem))
  data = data.gsub("{{CLIENT_KEY}}", Base64.strict_encode64(client_key.to_pem))

  kubeconfig_file = File.new("provisioning/roles/kubelet/templates/kubeconfig.j2", "wb")
  kubeconfig_file.syswrite(data)
  kubeconfig_file.close
  # END KUBECONFIG
end
```

This generates a CA, a client cert and key, and put them into the configuration file. The content of the kubeconfig.tmpl is:

```
apiVersion: v1
kind: Config
clusters:
- name: vagrant
  cluster:
    server: https://{{ hostvars[groups['role=master'].2]['private_ipv4'] }}:443
    certificate-authority-data: {{CA_CERT}}
users:
- name: kubelet
  user:
    client-certificate-data: {{CLIENT_CERT}}
    client-key-data: {{CLIENT_KEY}}
contexts:
- context:
    cluster: vagrant
    user: kubelet
```

> Note: You have to keep the subject and issuer_subject consistent.

#### Create kubelet as a service

To make sure kubelet runs on all nodes and be able to survive system restarts, we make it as a system service and enable it. Create the following template file containing the service definition for kubelet

```bash
[Unit]
Description=Kubelet via Hyperkube ACI
Wants=systemd-resolved.service
[Service]
Environment="RKT_RUN_ARGS=--uuid-file-save=/var/run/kubelet-pod.uuid \
  --volume resolv,kind=host,source=/etc/resolv.conf \
  --mount volume=resolv,target=/etc/resolv.conf \
  --volume var-lib-cni,kind=host,source=/var/lib/cni \
  --mount volume=var-lib-cni,target=/var/lib/cni \
  --volume var-log,kind=host,source=/var/log \
  --mount volume=var-log,target=/var/log"
Environment=KUBELET_IMAGE_URL="quay.io/coreos/hyperkube"
Environment=KUBELET_IMAGE_TAG="v1.7.5_coreos.1"
ExecStartPre=/bin/sh -c 'while ! /usr/bin/grep '^[^#[:space:]]' /etc/resolv.conf > /dev/null; do sleep 1; done'
ExecStartPre=/bin/mkdir -p /etc/kubernetes/manifests
ExecStartPre=/bin/mkdir -p /etc/kubernetes/cni/net.d
ExecStartPre=/bin/mkdir -p /etc/kubernetes/checkpoint-secrets
ExecStartPre=/bin/mkdir -p /etc/kubernetes/inactive-manifests
ExecStartPre=/bin/mkdir -p /var/lib/cni
ExecStartPre=-/usr/bin/rkt rm --uuid-file=/var/run/kubelet-pod.uuid
ExecStart=/usr/lib/coreos/kubelet-wrapper \
  --kubeconfig=/etc/kubernetes/kubeconfig \
  --require-kubeconfig \
  --client-ca-file=/etc/kubernetes/ca.crt \
  --anonymous-auth=false \
  --cni-conf-dir=/etc/kubernetes/cni/net.d \
  --network-plugin=cni \
  --lock-file=/var/run/lock/kubelet.lock \
  --exit-on-lock-contention \
  --pod-manifest-path=/etc/kubernetes/manifests \
  --allow-privileged \
  --node-labels=node-role.kubernetes.io/{{ hostvars[inventory_hostname]['role'] }} \
  --node-ip={{ hostvars[inventory_hostname]['private_ipv4'] }} \
  {% if hostvars[inventory_hostname]['role'] == "master" %}--register-with-taints=node-role.kubernetes.io/{{ hostvars[inventory_hostname]['role'] }}=:NoSchedule \
  {% endif %}--cluster-dns=10.3.0.10 \
  --cluster-domain=cluster.local
ExecStop=-/usr/bin/rkt stop --uuid-file=/var/run/kubelet-pod.uuid
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
```

> Tips:
> 1. Before starting kubelet, make sure systemd-resolved.service is running already and the resolv.conf on the host is generated.
> 2. Label the nodes properly to distinguish masters and workers.
> 3. Taint the masters with 'NoSchedule' so pods will not by default scheduled on master unless tolerations are specified otherwise.

Now we create the task to copy over the files and enable the service:

```yml
###################
# Install kubelet #
###################

- name: Make sure the kubernetes directory is present
  file:
    path: "/etc/kubernetes"
    state: directory

- name: Copy over the ca.crt and ca.key
  copy:
    src: "tls/{{ item }}"
    dest: /etc/kubernetes/{{ item }}
  with_items:
    - ca.crt
    - ca.key

- name: Copy over the kubeconfig file
  template:
    src: "kubeconfig.j2"
    dest: /etc/kubernetes/kubeconfig
  notify: Restart kubelet

- name: Copy over the service definition file
  template:
    src: "kubelet.service.j2"
    dest: /etc/systemd/system/kubelet.service
  notify: Restart kubelet

- name: Start and enable kubelet service
  systemd:
    name: kubelet
    state: started
    enabled: yes
    daemon_reload: yes

- meta: flush_handlers
```

Update the playbook and add the following content to provision `kubelet` using the role.

```yml
################################
# Install kubelet on all nodes #
################################

- name: kubelet
  hosts: all
  become: true
  gather_facts: True
  roles:
    - kubelet
```

```bash
vagrant up --provision
```

The full code of the role can be found at [kubelet](https://github.com/WUMUXIAN/ha-kubernetes-cluster-vagrant/tree/master/provisioning/roles/kubelet).

After the provision is finished successfully, we can verify kubelet is running on each node:

```bash
core@master03 ~ $ ps aux | grep kubelet
root      2630  5.9  5.2 493408 106772 ?       Ssl  09:05   0:25 /kubelet --kubeconfig=/etc/kubernetes/kubeconfig --require-kubeconfig --client-ca-file=/etc/kubernetes/ca.crt --anonymous-auth=false --cni-conf-dir=/etc/kubernetes/cni/net.d --network-plugin=cni --lock-file=/var/run/lock/kubelet.lock --exit-on-lock-contention --pod-manifest-path=/etc/kubernetes/manifests --allow-privileged --node-labels=node-role.kubernetes.io/master --register-with-taints=node-role.kubernetes.io/master=:NoSchedule --cluster_dns=10.3.0.10 --cluster_domain=cluster.local

core@worker01 ~ $ ps aux | grep kubelet
root      1454  1.6  7.3 812000 74636 ?        Ssl  01:30   8:04 /kubelet --kubeconfig=/etc/kubernetes/kubeconfig --require-kubeconfig --client-ca-file=/etc/kubernetes/ca.crt --anonymous-auth=false --cni-conf-dir=/etc/kubernetes/cni/net.d --network-plugin=cni --lock-file=/var/run/lock/kubelet.lock --exit-on-lock-contention --pod-manifest-path=/etc/kubernetes/manifests --allow-privileged --node-labels=node-role.kubernetes.io/worker --node-ip=172.17.5.201 --cluster-dns=10.3.0.10 --cluster-domain=cluster.local
```

[Next](http://blog.wumuxian1988.com/2018/01/12/HA-Kubernetes-cluster-with-Vagrant-CoreOS-Ansible-Part-4/), we'll boot up the key components of Kubernetes, the API server, scheduler and controller manager using bootkube as well as running all the add-ons using Kubernetes itself.
