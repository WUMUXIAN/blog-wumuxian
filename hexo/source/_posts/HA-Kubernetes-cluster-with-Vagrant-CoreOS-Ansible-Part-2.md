---
title: 'HA Kubernetes cluster with Vagrant+CoreOS+Ansible, Part 2'
date: 2018-01-10 10:17:01
tags:
 - Kubernetes
 - Docker
 - Vagrant
 - CoreOS
category:
 - DevOps
---

In [part 1](http://blog.wumuxian1988.com/2017/12/21/HA-Kubernetes-cluster-with-Vagrant-CoreOS-Ansible-Part-1/) we have created 3 masters running coreos using Vagrant and installed necessary components on the coreos for Ansible to work. In this part, we're going to configure another key component of Kubernetes cluster:

- etcd

#### etcd

`etcd` is a distributed key-value store, which is the heart of a Kubernetes cluster as it holds the state of the cluster. The number one rule of high availability is to protect the data, so we have to cluster etcd to make it redundant and reliable.

The official site [here](https://coreos.com/etcd/docs/latest/op-guide/clustering.html) gives a very detailed instruction of how to setting up a clustered etcd, we just need to convert this into an Ansible role.

We want to establish a SSL protected cluster so the first step would be generate the necessary certs and keys. We do it using ruby code inside the VagrantFile, what we need to generate are:
- Root CA cert and key
- Server cert and key signed by the root CA
- Client cert and key signed by the root CA
- Peer cert and key for each master signed by the root CA.

Once we have all these in place, we use an Ansible role to setup the etcd cluster

```yml
########################
# Install etcd cluster #
########################

- name: Make sure the configuration directory is present
  file:
    path: "{{ dropin_directory }}"
    state: directory

- name: Make sure the ssl directory is present
  file:
    path: "{{ ssl_directory }}"
    state: directory

- name: Copy over the certs and keys
  copy:
    src: "{{ item }}"
    dest: "{{ ssl_directory }}/{{ item }}"
  with_items:
    - ca.crt
    - server.crt
    - server.key
    - etcd-client.crt
    - etcd-client.key
  notify: Restart etcd

- name: Copy over the peers certs and keys
  copy:
    src: "{{ item }}"
    dest: "{{ ssl_directory }}/{{ item }}"
  with_items:
    - "{{ inventory_hostname }}.crt"
    - "{{ inventory_hostname }}.key"
  notify: Restart etcd

- name: Create the etcd configuration there
  template:
    src: "{{ dropin_file }}.j2"
    dest: "{{ dropin_directory }}/{{ dropin_file }}"
  notify: Restart etcd

- name: Start and enable etcd service
  systemd:
    name: etcd-member
    state: started
    enabled: yes
    daemon_reload: yes
```
The content of the dropin file `40-cluster-ips.conf.j2` configures the etcd cluster
```
[Service]
Environment=ETCD_NAME={{ inventory_hostname }}
Environment=ETCD_INITIAL_ADVERTISE_PEER_URLS="https://{{ hostvars[inventory_hostname]['private_ipv4'] }}:2380"
Environment=ETCD_LISTEN_PEER_URLS="https://{{ hostvars[inventory_hostname]['private_ipv4'] }}:2380"
Environment=ETCD_LISTEN_CLIENT_URLS="https://{{ hostvars[inventory_hostname]['private_ipv4'] }}:2379,https://127.0.0.1:2379,https://127.0.0.1:4001"
Environment=ETCD_ADVERTISE_CLIENT_URLS="https://{{ hostvars[inventory_hostname]['private_ipv4'] }}:2379"
Environment=ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster-1
Environment=ETCD_INITIAL_CLUSTER="{% for host in groups['role=master'] %}{{ host }}=https://{{ hostvars[host]['private_ipv4'] }}:2380{% if not loop.last %},{% endif %}{% endfor %}"
Environment=ETCD_INITIAL_CLUSTER_STATE=new
Environment=ETCD_STRICT_RECONFIG_CHECK=true
Environment=ETCD_SSL_DIR=/etc/ssl/etcd
Environment=ETCD_CLIENT_CERT_AUTH=true
Environment=ETCD_TRUSTED_CA_FILE=/etc/ssl/certs/ca.crt
Environment=ETCD_CERT_FILE=/etc/ssl/certs/server.crt
Environment=ETCD_KEY_FILE=/etc/ssl/certs/server.key
Environment=ETCD_PEER_CLIENT_CERT_AUTH=true
Environment=ETCD_PEER_TRUSTED_CA_FILE=/etc/ssl/certs/ca.crt
Environment=ETCD_PEER_CERT_FILE=/etc/ssl/certs/{{ inventory_hostname }}.crt
Environment=ETCD_PEER_KEY_FILE=/etc/ssl/certs/{{ inventory_hostname }}.key
```

The key is to set the etcd cluster ips, certs and keys correctly, here we goes with the static configuration method because we can use Ansible to get all masters' IP easily. The full source code for the role can be found at [etcd](https://github.com/WUMUXIAN/ha-kubernetes-cluster-vagrant/tree/master/provisioning/roles/etcd)

After having the role, update the playbook and add the following section.

```yml
########################
# Install etcd cluster #
########################

- name: etcd
  hosts: role=master
  become: true
  gather_facts: True
  roles:
    - etcd
```

Now use vagrant and Ansible to apply the changes to the masters.

```bash
vagrant up --provision

PLAY [master] ******************************************************************

TASK [Gathering Facts] *********************************************************
ok: [master01]
ok: [master03]
ok: [master02]

TASK [etcd : Make sure the configuration directory is present] *****************
ok: [master02]
ok: [master03]
ok: [master01]

TASK [etcd : Make sure the ssl directory is present] ***************************
ok: [master01]
ok: [master02]
ok: [master03]

TASK [etcd : Copy over the certs and keys] *************************************
changed: [master01] => (item=ca.crt)
changed: [master03] => (item=ca.crt)
changed: [master02] => (item=ca.crt)
changed: [master01] => (item=server.crt)
changed: [master03] => (item=server.crt)
changed: [master02] => (item=server.crt)
changed: [master01] => (item=server.key)
changed: [master02] => (item=server.key)
changed: [master03] => (item=server.key)
changed: [master01] => (item=etcd-client.crt)
changed: [master03] => (item=etcd-client.crt)
changed: [master02] => (item=etcd-client.crt)
changed: [master01] => (item=etcd-client.key)
changed: [master02] => (item=etcd-client.key)
changed: [master03] => (item=etcd-client.key)

TASK [etcd : Copy over the peers certs and keys] *******************************
changed: [master01] => (item=master01.crt)
changed: [master02] => (item=master02.crt)
changed: [master03] => (item=master03.crt)
changed: [master01] => (item=master01.key)
changed: [master02] => (item=master02.key)
changed: [master03] => (item=master03.key)

TASK [etcd : Create the etcd configuration there] ******************************
ok: [master01]
ok: [master02]
ok: [master03]

TASK [etcd : Start and enable etcd service] ************************************
ok: [master03]
ok: [master01]
ok: [master02]

RUNNING HANDLER [etcd : Restart etcd] ******************************************
changed: [master03]
changed: [master02]
changed: [master01]

PLAY RECAP *********************************************************************
master01                   : ok=10   changed=4    unreachable=0    failed=0
master02                   : ok=10   changed=4    unreachable=0    failed=0
master03                   : ok=10   changed=4    unreachable=0    failed=0
```

After this is done, ssh into any of the master machine and check the etcd cluster healthiness and member list.

```bash
core@master03 ~ $ etcdctl --ca-file /etc/ssl/etcd/ca.crt --cert-file /etc/ssl/etcd/etcd-client.crt --key-file /etc/ssl/etcd/etcd-client.key --endpoints https://127.0.0.1:2379 cluster-health
member df080e92bbe6d38 is healthy: got healthy result from https://172.17.5.102:2379
member 5d348d2925ee35eb is healthy: got healthy result from https://172.17.5.101:2379
member b25cf09cad535601 is healthy: got healthy result from https://172.17.5.103:2379
cluster is healthy

core@master03 ~ $ etcdctl --ca-file /etc/ssl/etcd/ca.crt --cert-file /etc/ssl/etcd/etcd-client.crt --key-file /etc/ssl/etcd/etcd-client.key --endpoints https://127.0.0.1:2379 member list
df080e92bbe6d38: name=master02 peerURLs=https://172.17.5.102:2380 clientURLs=https://172.17.5.102:2379 isLeader=false
5d348d2925ee35eb: name=master01 peerURLs=https://172.17.5.101:2380 clientURLs=https://172.17.5.101:2379 isLeader=true
b25cf09cad535601: name=master03 peerURLs=https://172.17.5.103:2380 clientURLs=https://172.17.5.103:2379 isLeader=false
```

By now the etcd cluster is up and running. In the [next part](http://blog.wumuxian1988.com/2018/01/12/HA-Kubernetes-cluster-with-Vagrant-CoreOS-Ansible-Part-3/), we'll write an Ansible role to configure and run `kubelet` on all nodes.
