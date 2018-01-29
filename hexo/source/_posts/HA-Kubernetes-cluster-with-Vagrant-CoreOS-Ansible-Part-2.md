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

In [part 1](http://blog.wumuxian1988.com/2017/12/21/HA-Kubernetes-cluster-with-Vagrant-CoreOS-Ansible-Part-1/) we have created 4 nodes running coreos using Vagrant and installed necessary components on the coreos for Ansible to work. In this part, we're going to configure another key component of Kubernetes cluster: *etcd*

## etcd

`etcd` is a distributed key-value store, which is the heart of a Kubernetes cluster as it holds the state of the cluster. The number one rule of high availability is to protect the data, so we have to cluster etcd to make it redundant and reliable.

The official site [here](https://coreos.com/etcd/docs/latest/op-guide/clustering.html) gives a very detailed instruction of how to setting up a clustered etcd, we just need to convert this into an Ansible role to configure and run etcd on the 3 master nodes.

We want to establish a SSL protected cluster so the first step would be generate the necessary certs and keys. We do it using ruby code inside the VagrantFile, what we need to generate are:
- Root CA cert and key for etcd
- Server cert and key signed by the root etcd CA
- Client cert and key signed by the root etcd CA
- Peer cert and key for each master signed by the root etcd CA.

```ruby
def signTLS(is_ca:, subject:, issuer_subject:'', issuer_cert:nil, public_key:, ca_private_key:, key_usage:'', extended_key_usage:'', san:'')
  cert = OpenSSL::X509::Certificate.new
  cert.subject = OpenSSL::X509::Name.parse(subject)
  if (is_ca)
    cert.issuer = OpenSSL::X509::Name.parse(subject)
  else
    cert.issuer = OpenSSL::X509::Name.parse(issuer_subject)
  end
  cert.not_before = Time.now
  cert.not_after = Time.now + 365 * 24 * 60 * 60
  cert.public_key = public_key
  cert.serial = Random.rand(1..65534)
  cert.version = 2

  ef = OpenSSL::X509::ExtensionFactory.new
  ef.subject_certificate = cert
  if (is_ca)
    ef.issuer_certificate = cert
  else
    ef.issuer_certificate = issuer_cert
  end
  if (is_ca)
    cert.extensions = [
      ef.create_extension("keyUsage", "digitalSignature,keyEncipherment,keyCertSign", true),
      ef.create_extension("basicConstraints","CA:TRUE", true),
      ef.create_extension("subjectKeyIdentifier", "hash"),
  ]
  else
    # The ordering of these statements is done the way it is to match the way terraform does it
    cert.extensions = []
    if (key_usage != "")
      cert.extensions += [ef.create_extension("keyUsage", key_usage, true)]
    end
    if (extended_key_usage != "")
      cert.extensions += [ef.create_extension("extendedKeyUsage", extended_key_usage, true)]
    end
    cert.extensions += [ef.create_extension("basicConstraints","CA:FALSE", true)]
    cert.extensions += [ef.create_extension("authorityKeyIdentifier", "keyid,issuer")]
    if (san != "")
      cert.extensions += [ef.create_extension("subjectAltName", san, false)]
    end
  end

  cert.sign ca_private_key, OpenSSL::Digest::SHA256.new
  return cert
end

if ARGV[0] == 'up'
  recreated_required = false

  # If the tls files for ETCD does not exist, create them.
  if !File.directory?("provisioning/roles/etcd/files/tls")
    recreated_required = true
    # BEGIN ETCD CA
    FileUtils::mkdir_p 'provisioning/roles/etcd/files/tls'
    etcd_key = OpenSSL::PKey::RSA.new(2048)
    etcd_public_key = etcd_key.public_key

    etcd_cert = signTLS(is_ca:          true,
                        subject:        "/C=SG/ST=Singapore/L=Singapore/O=Security/OU=IT/CN=etcd-ca",
                        public_key:     etcd_public_key,
                        ca_private_key: etcd_key,
                        key_usage:      "digitalSignature,keyEncipherment,keyCertSign")

    etcd_file = File.new("provisioning/roles/etcd/files/tls/ca.crt", "wb")
    etcd_file.syswrite(etcd_cert.to_pem)
    etcd_file.close
    # END ETCD CA

    IPs = []
    (1..MASTER_COUNT).each do |m|
      IPs << "IP:" + $master_ip_start + "#{m}"
    end

    (1..MASTER_COUNT).each do |m|
      # BEGIN ETCD PEER
      peer_key = OpenSSL::PKey::RSA.new(2048)
      peer_public_key = peer_key.public_key

      peer_cert = signTLS(is_ca:              false,
                          subject:            "/C=SG/ST=Singapore/L=Singapore/O=Security/OU=IT/CN=etcd",
                          issuer_subject:     "/C=SG/ST=Singapore/L=Singapore/O=Security/OU=IT/CN=etcd-ca",
                          issuer_cert:        etcd_cert,
                          public_key:         peer_public_key,
                          ca_private_key:     etcd_key,
                          key_usage:          "keyEncipherment",
                          extended_key_usage: "serverAuth,clientAuth",
                          san:                "DNS:localhost,DNS:*.tdskubes.com,DNS:*.kube-etcd.kube-system.svc.cluster.local,DNS:kube-etcd-client.kube-system.svc.cluster.local,#{IPs.join(',')},IP:10.3.0.15,IP:10.3.0.20")

      peer_file = File.new("provisioning/roles/etcd/files/tls/master0#{m}.crt", "wb")
      peer_file.syswrite(peer_cert.to_pem)
      peer_file.close

      peer_key_file= File.new("provisioning/roles/etcd/files/tls/master0#{m}.key", "wb")
      peer_key_file.syswrite(peer_key.to_pem)
      peer_key_file.close
      # END ETCD PEER
    end

    # BEGIN ETCD SERVER
    server_key = OpenSSL::PKey::RSA.new(2048)
    server_public_key = server_key.public_key

    server_cert = signTLS(is_ca:              false,
                          subject:            "/C=SG/ST=Singapore/L=Singapore/O=Security/OU=IT/CN=etcd",
                          issuer_subject:     "/C=SG/ST=Singapore/L=Singapore/O=Security/OU=IT/CN=etcd-ca",
                          issuer_cert:        etcd_cert,
                          public_key:         server_public_key,
                          ca_private_key:     etcd_key,
                          key_usage:          "keyEncipherment",
                          extended_key_usage: "serverAuth",
                          san:                "DNS:localhost,DNS:*.kube-etcd.kube-system.svc.cluster.local,DNS:kube-etcd-client.kube-system.svc.cluster.local,IP:127.0.0.1,#{IPs.join(',')},IP:10.3.0.15,IP:10.3.0.20")

    server_file = File.new("provisioning/roles/etcd/files/tls/server.crt", "wb")
    server_file.syswrite(server_cert.to_pem)
    server_file.close

    server_key_file= File.new("provisioning/roles/etcd/files/tls/server.key", "wb")
    server_key_file.syswrite(server_key.to_pem)
    server_key_file.close
    # END ETCD SERVER

    # BEGIN ETCD CLIENT
    etcd_client_key = OpenSSL::PKey::RSA.new(2048)
    etcd_client_public_key = etcd_client_key.public_key

    etcd_client_cert = signTLS(is_ca:              false,
                               subject:            "/C=SG/ST=Singapore/L=Singapore/O=Security/OU=IT/CN=etcd",
                               issuer_subject:     "/C=SG/ST=Singapore/L=Singapore/O=Security/OU=IT/CN=etcd-ca",
                               issuer_cert:        etcd_cert,
                               public_key:         etcd_client_public_key,
                               ca_private_key:     etcd_key,
                               key_usage:          "keyEncipherment",
                               extended_key_usage: "clientAuth")

    etcd_client_file_tec = File.new("provisioning/roles/etcd/files/tls/etcd-client.crt", "wb")
    etcd_client_file_tec.syswrite(etcd_client_cert.to_pem)
    etcd_client_file_tec.close

    etcd_client_file_tec = File.new("provisioning/roles/etcd/files/tls/etcd-client.key", "wb")
    etcd_client_file_tec.syswrite(etcd_client_key.to_pem)
    etcd_client_file_tec.close
    # END ETCD CLIENT
  end
end
```

> Tips:
> 1. Be care with the subject and issuer_subject fields, they have to be consistently.
> 2. You have to pass in all the domain names and reachable IP addresses for your etcd nodes in the san when generating the server certificate to make the handshaking work properly.

The full content VagrantFile can be found at [here](https://github.com/WUMUXIAN/ha-kubernetes-cluster-vagrant/blob/master/Vagrantfile). Once we have all these in place, we use an Ansible role to setup the etcd cluster

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
    src: "tls/{{ item }}"
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
    src: "tls/{{ item }}"
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

- meta: flush_handlers
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

The key is to set the etcd cluster ips, certs and keys correctly, here we go with the static configuration method because we can use Ansible to get all masters' IP easily. The full source code for the role can be found at [etcd](https://github.com/WUMUXIAN/ha-kubernetes-cluster-vagrant/tree/master/provisioning/roles/etcd)

After having the role, update the playbook and add the following section.

```yml
################################
# Install etcd on master nodes #
################################

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

By now the etcd cluster is up and running on 3 master nodes, and we have the backbone of a Kubernetes cluster ready. In the [next part](http://blog.wumuxian1988.com/2018/01/12/HA-Kubernetes-cluster-with-Vagrant-CoreOS-Ansible-Part-3/), we'll write an Ansible role to configure and run `kubelet` on all nodes.
