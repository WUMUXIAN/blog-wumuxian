---
title: 'HA Kubernetes cluster with Vagrant+CoreOS+Ansible, Part 1'
date: 2017-12-21 11:43:17
tags:
 - Kubernetes
 - Docker
 - Vagrant
 - CoreOS
category:
 - DevOps
---

Kubernetes is a production level containers orchestration tool that helps to automating deployment, scaling and manage your containers. The official recommended way of running a local Kubernetes cluster is to use `minikube`, it is the easiest way to get started. However the shortage of this is very obvious.
  1.  You can't emulate a HA cluster as `minikube` setup a single node environment.
  2.  The details of how the Kubernetes cluster runs are pretty much shadowed, you don't get the chance to build it step by step, and understand what are the building blocks and how they work together to form the cluster.

This post tries to build a Kubernetes cluster from scratch to achieve a minimum HA setup with N CoreOS virtual machines.

## What you need before you get started
* Vagrant >= 2.0.1
* VirtualBox >= 5.0.0
* Ansible >= 2.3.0
* container-linux-config-transpiler >= v0.5.0

## Let's rock it.

1. Make a directory to host all your files.
  ```bash
  mkdir ha-kubernetes-cluster-vagrant
  cd ha-kubernetes-cluster-vagrant
  ```

2. Initialise the VagrantFile
  ```bash
  vagrant init
  ```

3. We start with creating the master nodes.
  ```ruby
  # -*- mode: ruby -*-
  # # vi: set ft=ruby :

  Vagrant.require_version ">= 1.9.7"

  # Make sure the vagrant-ignition plugin is installed
  required_plugins = %w(vagrant-ignition)

  plugins_to_install = required_plugins.select { |plugin| not Vagrant.has_plugin? plugin }
  if not plugins_to_install.empty?
    puts "Installing plugins: #{plugins_to_install.join(' ')}"
    if system "vagrant plugin install #{plugins_to_install.join(' ')}"
      exec "vagrant #{ARGV.join(' ')}"
    else
      abort "Installation of one or more plugins has failed. Aborting."
    end
  end

  $master_vm_memory = 2048
  $master_ip_start = "172.17.5.10"

  BOX_VERSION = ENV["BOX_VERSION"] || "1465.3.0"
  MASTER_COUNT = ENV["MASTER_COUNT"] || 3
  IGNITION_PATH = File.expand_path("./provisioning/node.ign")

  Vagrant.configure("2") do |config|
    # always use Vagrant's insecure key
    config.ssh.insert_key = false

    config.vm.box = "container-linux-v#{BOX_VERSION}"
    config.vm.box_url = "https://beta.release.core-os.net/amd64-usr/#{BOX_VERSION}/coreos_production_vagrant_virtualbox.box"

    config.vm.provider :virtualbox do |v|
      # On VirtualBox, we don't have guest additions or a functional vboxsf
      # in CoreOS, so tell Vagrant that so it can be smarter.
      v.check_guest_additions = false
      v.functional_vboxsf     = false
    end

    # plugin conflict
    if Vagrant.has_plugin?("vagrant-vbguest") then
      config.vbguest.auto_update = false
    end

    config.vm.provider :virtualbox do |vb|
      vb.cpus = 1
      vb.gui = false
    end

    hostvars, masters = {}, []

    # Create the master nodes.
    (1..MASTER_COUNT).each do |m|
      # Set the host name and ip
      master_name = "master0#{m}"
      master_ip = $master_ip_start + "#{m}"

      config.vm.define master_name do |master|
        master.vm.hostname = master_name
        master.vm.provider :virtualbox do |vb|
          vb.memory = $master_vm_memory
          master.ignition.enabled = true
        end

        # Set the private ip.
        master.vm.network :private_network, ip: master_ip
        master.ignition.ip = master_ip

        # Set the ignition data.
        master.vm.provider :virtualbox do |vb|
          master.ignition.hostname = "#{master_name}.tdskubes.com"
          master.ignition.drive_root = "provisioning"
          master.ignition.drive_name = "config-master-#{m}"
          master.ignition.path = IGNITION_PATH
        end
        masters << master_name
        master_hostvars = {
          master_name => {
            "ansible_python_interpreter" => "/home/core/bin/python",
            "private_ipv4" => master_ip,
            "public_ipv4" => master_ip,
            "role" => "master",
          }
        }
        hostvars.merge!(master_hostvars)
      end
    end

    # Provision
    config.vm.provision :ansible do |ansible|
      ansible.groups = {
        "role=master": masters,
        "all": masters,
      }
      ansible.host_vars = hostvars
      ansible.playbook = "provisioning/playbook.yml"
    end
  end

  ```

  In order to run this, we need to prepare the ignition file in the specified folder.
  ```bash
  mkdir provisioning
  cat > node.clc <<EOF
  systemd:
  units:
    - name: locksmithd.service
      mask: true
    - name: update-engine.service
      mask: true
  EOF
  ```

  For now we don't do anything but just keep it empty. Convert it into an ignition file so that vagrant ignition plugin can read by running:
  ```bash
  ct -pretty -platform vagrant-virtualbox < node.clc > node.ign
  ```

  This ignition configuration will permanently disable the auto-update and rebooting of the container linux for us.
  Up to this point we are able to create container linux masters, however we can't use Ansible to provision it yet because Ansible requires the target machine to have python installed to work and container linux doesn't come with python natively due to its nature of having only components needed to run containers. In order to solve this problem, we have to install `pypy` first taking advantage of Ansible's `raw` module (module that doesn't require python). Let's create the `playbook.yml`:

  ```
  ####################################
  # ANSIBLE PREREQUISITES FOR COREOS #
  ####################################

  - name: coreos-pypy
    hosts: all
    gather_facts: False
    roles:
      - pypy
  ```

  The the content of the role can be found at [pypy](https://github.com/WUMUXIAN/ha-kubernetes-cluster-vagrant/tree/master/provisioning/roles/pypy).

  Once we have all these in place, we can create the provision the masters using:

  ```
  vagrant up
  ==> master01: Importing base box 'container-linux-v1465.3.0'...
  ==> master01: Configuring Ignition Config Drive
  ==> master01: Matching MAC address for NAT networking...
  ==> master01: Setting the name of the VM: ha-kubernetes-cluster-vagrant_master01_1513847540735_38332
  ==> master01: Clearing any previously set network interfaces...
  ==> master01: Preparing network interfaces based on configuration...
      master01: Adapter 1: nat
      master01: Adapter 2: hostonly
  ==> master01: Forwarding ports...
      master01: 22 (guest) => 2222 (host) (adapter 1)
  ==> master01: Running 'pre-boot' VM customizations...
  ==> master01: Booting VM...
  ==> master01: Waiting for machine to boot. This may take a few minutes...
      master01: SSH address: 127.0.0.1:2222
      master01: SSH username: core
      master01: SSH auth method: private key
  ==> master01: Machine booted and ready!
  ==> master01: Setting hostname...
  ==> master01: Configuring and enabling network interfaces...
  ==> master02: Importing base box 'container-linux-v1465.3.0'...
  ==> master02: Configuring Ignition Config Drive
  ==> master02: Matching MAC address for NAT networking...
  ==> master02: Setting the name of the VM: ha-kubernetes-cluster-vagrant_master02_1513847561163_9756
  ==> master02: Fixed port collision for 22 => 2222. Now on port 2203.
  ==> master02: Clearing any previously set network interfaces...
  ==> master02: Preparing network interfaces based on configuration...
      master02: Adapter 1: nat
      master02: Adapter 2: hostonly
  ==> master02: Forwarding ports...
      master02: 22 (guest) => 2203 (host) (adapter 1)
  ==> master02: Running 'pre-boot' VM customizations...
  ==> master02: Booting VM...
  ==> master02: Waiting for machine to boot. This may take a few minutes...
      master02: SSH address: 127.0.0.1:2203
      master02: SSH username: core
      master02: SSH auth method: private key
      master02: Warning: Remote connection disconnect. Retrying...
  ==> master02: Machine booted and ready!
  ==> master02: Setting hostname...
  ==> master02: Configuring and enabling network interfaces...
  ==> master03: Importing base box 'container-linux-v1465.3.0'...
  ==> master03: Configuring Ignition Config Drive
  ==> master03: Matching MAC address for NAT networking...
  ==> master03: Setting the name of the VM: ha-kubernetes-cluster-vagrant_master03_1513847581255_67290
  ==> master03: Fixed port collision for 22 => 2222. Now on port 2204.
  ==> master03: Clearing any previously set network interfaces...
  ==> master03: Preparing network interfaces based on configuration...
      master03: Adapter 1: nat
      master03: Adapter 2: hostonly
  ==> master03: Forwarding ports...
      master03: 22 (guest) => 2204 (host) (adapter 1)
  ==> master03: Running 'pre-boot' VM customizations...
  ==> master03: Booting VM...
  ==> master03: Waiting for machine to boot. This may take a few minutes...
      master03: SSH address: 127.0.0.1:2204
      master03: SSH username: core
      master03: SSH auth method: private key
  ==> master03: Machine booted and ready!
  ==> master03: Setting hostname...
  ==> master03: Configuring and enabling network interfaces...
  ==> master03: Running provisioner: ansible...
  Vagrant has automatically selected the compatibility mode '2.0'
  according to the Ansible version installed (2.3.2.0).

  Alternatively, the compatibility mode can be specified in your Vagrantfile:
  https://www.vagrantup.com/docs/provisioning/ansible_common.html#compatibility_mode

      master03: Running ansible-playbook...

  PLAY [coreos-pypy] *************************************************************

  TASK [pypy : Check if pypy is installed] ***************************************
  fatal: [master02]: FAILED! => {"changed": true, "failed": true, "rc": 1, "stderr": "Warning: Permanently added '[127.0.0.1]:2203' (ECDSA) to the list of known hosts.\r\nShared connection to 127.0.0.1 closed.\r\n", "stdout": "stat: cannot stat '/home/core/pypy': No such file or directory\r\n", "stdout_lines": ["stat: cannot stat '/home/core/pypy': No such file or directory"]}
  ...ignoring
  fatal: [master01]: FAILED! => {"changed": true, "failed": true, "rc": 1, "stderr": "Warning: Permanently added '[127.0.0.1]:2222' (ECDSA) to the list of known hosts.\r\nShared connection to 127.0.0.1 closed.\r\n", "stdout": "stat: cannot stat '/home/core/pypy': No such file or directory\r\n", "stdout_lines": ["stat: cannot stat '/home/core/pypy': No such file or directory"]}
  ...ignoring
  fatal: [master03]: FAILED! => {"changed": true, "failed": true, "rc": 1, "stderr": "Warning: Permanently added '[127.0.0.1]:2204' (ECDSA) to the list of known hosts.\r\nShared connection to 127.0.0.1 closed.\r\n", "stdout": "stat: cannot stat '/home/core/pypy': No such file or directory\r\n", "stdout_lines": ["stat: cannot stat '/home/core/pypy': No such file or directory"]}
  ...ignoring

  TASK [pypy : Run get-pypy.sh] **************************************************
  changed: [master01]
  changed: [master02]
  changed: [master03]

  TASK [pypy : Check if pip is installed] ****************************************
  fatal: [master01]: FAILED! => {"changed": false, "cmd": "/home/core/bin/python -m pip --version", "delta": "0:00:00.050451", "end": "2017-12-21 09:13:49.555155", "failed": true, "rc": 1, "start": "2017-12-21 09:13:49.504704", "stderr": "/home/core/pypy/bin/pypy: /lib64/libssl.so.1.0.0: no version information available (required by /home/core/pypy/bin/libpypy-c.so)\n/home/core/pypy/bin/pypy: /lib64/libssl.so.1.0.0: no version information available (required by /home/core/pypy/bin/libpypy-c.so)\n/home/core/pypy/bin/pypy: /lib64/libcrypto.so.1.0.0: no version information available (required by /home/core/pypy/bin/libpypy-c.so)\n/home/core/pypy/bin/pypy: No module named pip", "stderr_lines": ["/home/core/pypy/bin/pypy: /lib64/libssl.so.1.0.0: no version information available (required by /home/core/pypy/bin/libpypy-c.so)", "/home/core/pypy/bin/pypy: /lib64/libssl.so.1.0.0: no version information available (required by /home/core/pypy/bin/libpypy-c.so)", "/home/core/pypy/bin/pypy: /lib64/libcrypto.so.1.0.0: no version information available (required by /home/core/pypy/bin/libpypy-c.so)", "/home/core/pypy/bin/pypy: No module named pip"], "stdout": "", "stdout_lines": []}
  ...ignoring
  fatal: [master02]: FAILED! => {"changed": false, "cmd": "/home/core/bin/python -m pip --version", "delta": "0:00:00.049796", "end": "2017-12-21 09:13:49.552675", "failed": true, "rc": 1, "start": "2017-12-21 09:13:49.502879", "stderr": "/home/core/pypy/bin/pypy: /lib64/libssl.so.1.0.0: no version information available (required by /home/core/pypy/bin/libpypy-c.so)\n/home/core/pypy/bin/pypy: /lib64/libssl.so.1.0.0: no version information available (required by /home/core/pypy/bin/libpypy-c.so)\n/home/core/pypy/bin/pypy: /lib64/libcrypto.so.1.0.0: no version information available (required by /home/core/pypy/bin/libpypy-c.so)\n/home/core/pypy/bin/pypy: No module named pip", "stderr_lines": ["/home/core/pypy/bin/pypy: /lib64/libssl.so.1.0.0: no version information available (required by /home/core/pypy/bin/libpypy-c.so)", "/home/core/pypy/bin/pypy: /lib64/libssl.so.1.0.0: no version information available (required by /home/core/pypy/bin/libpypy-c.so)", "/home/core/pypy/bin/pypy: /lib64/libcrypto.so.1.0.0: no version information available (required by /home/core/pypy/bin/libpypy-c.so)", "/home/core/pypy/bin/pypy: No module named pip"], "stdout": "", "stdout_lines": []}
  ...ignoring
  fatal: [master03]: FAILED! => {"changed": false, "cmd": "/home/core/bin/python -m pip --version", "delta": "0:00:00.049563", "end": "2017-12-21 09:13:49.555608", "failed": true, "rc": 1, "start": "2017-12-21 09:13:49.506045", "stderr": "/home/core/pypy/bin/pypy: /lib64/libssl.so.1.0.0: no version information available (required by /home/core/pypy/bin/libpypy-c.so)\n/home/core/pypy/bin/pypy: /lib64/libssl.so.1.0.0: no version information available (required by /home/core/pypy/bin/libpypy-c.so)\n/home/core/pypy/bin/pypy: /lib64/libcrypto.so.1.0.0: no version information available (required by /home/core/pypy/bin/libpypy-c.so)\n/home/core/pypy/bin/pypy: No module named pip", "stderr_lines": ["/home/core/pypy/bin/pypy: /lib64/libssl.so.1.0.0: no version information available (required by /home/core/pypy/bin/libpypy-c.so)", "/home/core/pypy/bin/pypy: /lib64/libssl.so.1.0.0: no version information available (required by /home/core/pypy/bin/libpypy-c.so)", "/home/core/pypy/bin/pypy: /lib64/libcrypto.so.1.0.0: no version information available (required by /home/core/pypy/bin/libpypy-c.so)", "/home/core/pypy/bin/pypy: No module named pip"], "stdout": "", "stdout_lines": []}
  ...ignoring

  TASK [pypy : Copy get-pip.py] **************************************************
  changed: [master01]
  changed: [master03]
  changed: [master02]

  TASK [pypy : Install pip] ******************************************************
  changed: [master01]
  changed: [master02]
  changed: [master03]

  TASK [pypy : Remove get-pip.py] ************************************************
  changed: [master01]
  changed: [master02]
  changed: [master03]

  TASK [pypy : Install pip launcher] *********************************************
  changed: [master01]
  changed: [master02]
  changed: [master03]

  PLAY RECAP *********************************************************************
  master01                   : ok=7    changed=6    unreachable=0    failed=0
  master02                   : ok=7    changed=6    unreachable=0    failed=0
  master03                   : ok=7    changed=6    unreachable=0    failed=0
  ```

By now we've got three master nodes running with python and pip installed. This makes Ansible usable on CoreOS, we will start to use Ansible to provision components on these masters. In [part2](http://blog.wumuxian1988.com/2018/01/10/HA-Kubernetes-cluster-with-Vagrant-CoreOS-Ansible-Part-2/) I'll setup `etcd` and `flannel`.
