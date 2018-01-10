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

The official site [here](https://coreos.com/etcd/docs/latest/op-guide/clustering.html) gives a very detailed instruction of how to seting up a clustered etcd, we just need to convert this into an Ansible role.

```yml
########################
# Install etcd cluster #
########################

- name: Make sure the configuration directory is present
  file:
    path: "{{ dropin_directory }}"
    state: directory

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

```
[Service]
Environment=ETCD_NAME={{ inventory_hostname }}
Environment=ETCD_INITIAL_ADVERTISE_PEER_URLS="http://{{ hostvars[inventory_hostname]['private_ipv4'] }}:2380"
Environment=ETCD_LISTEN_PEER_URLS="http://{{ hostvars[inventory_hostname]['private_ipv4'] }}:2380"
Environment=ETCD_LISTEN_CLIENT_URLS="http://{{ hostvars[inventory_hostname]['private_ipv4'] }}:2379,http://127.0.0.1:2379"
Environment=ETCD_ADVERTISE_CLIENT_URLS="http://{{ hostvars[inventory_hostname]['private_ipv4'] }}:2379"
Environment=ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster
Environment=ETCD_INITIAL_CLUSTER="{% for host in groups['role=master'] %}{{ host }}=http://{{ hostvars[host]['private_ipv4'] }}:2380{% if not loop.last %},{% endif %}{% endfor %}"
Environment=ETCD_INITIAL_CLUSTER_STATE=new
```

The key is to set the etcd cluster ips correctly, here we goes with the static configuration method because we can use Ansible to get all masters' IP easily. The full source code for the role can be found at [etcd](https://github.com/WUMUXIAN/ha-kubernetes-cluster-vagrant/tree/master/provisioning/roles/etcd)

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

PLAY [etcd] ********************************************************************

TASK [Gathering Facts] *********************************************************
ok: [master03]
ok: [master01]
ok: [master02]

TASK [etcd : Make sure the configuration directory is present] *****************
changed: [master01]
changed: [master02]
changed: [master03]

TASK [etcd : Create the etcd configuration there] ******************************
changed: [master01]
changed: [master02]
changed: [master03]

TASK [etcd : Start and enable etcd service] ************************************
changed: [master02]
changed: [master03]
changed: [master01]

RUNNING HANDLER [etcd : Restart etcd] ******************************************
changed: [master01]
changed: [master03]
changed: [master02]
```

After this is done, ssh into any of the master machine and check the etcd cluster healthiness and member list.

```bash
core@master01 ~ $ etcdctl cluster-health
member 21daa41562d65154 is healthy: got healthy result from http://172.17.5.101:2379
member 33c71e7a8b6ae2b0 is healthy: got healthy result from http://172.17.5.102:2379
member 48af1949bfc3b0ad is healthy: got healthy result from http://172.17.5.103:2379
cluster is healthy
core@master01 ~ $ etcdctl member list
21daa41562d65154: name=master01 peerURLs=http://172.17.5.101:2380 clientURLs=http://172.17.5.101:2379 isLeader=false
33c71e7a8b6ae2b0: name=master02 peerURLs=http://172.17.5.102:2380 clientURLs=http://172.17.5.102:2379 isLeader=true
48af1949bfc3b0ad: name=master03 peerURLs=http://172.17.5.103:2380 clientURLs=http://172.17.5.103:2379 isLeader=false
```

By now the etcd cluster is up and running, now let's move to run flannel.
