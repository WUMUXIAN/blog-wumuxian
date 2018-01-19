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
  1.  You can't emulate a HA cluster as `minikube` setups a single node environment.
  2.  The details of how the Kubernetes cluster runs are pretty much shadowed, you don't get the chance to build it step by step, and understand what are the building blocks and how they work together to form the cluster.

This post tries to build a Kubernetes cluster from scratch to achieve a minimum HA setup with 4 CoreOS virtual machines, 3 masters and 1 workers

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

3. We start with creating the nodes with coreOS.
  ```ruby
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

  $vm_memory = 1024
  $master_ip_start = "172.17.5.10"
  $worker_ip_start = "172.17.5.20"

  BOX_VERSION = ENV["BOX_VERSION"] || "1465.3.0"
  MASTER_COUNT = ENV["MASTER_COUNT"] || 3
  WORKER_COUNT = ENV["WORKER_COUNT"] || 1
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

    hostvars, masters, workers = {}, [], []

    # Create the worker nodes.
    (1..WORKER_COUNT).each do |w|
      # Set the host name and ip
      worker_name = "worker0#{w}"
      worker_ip = $worker_ip_start + "#{w}"

      config.vm.define worker_name do |worker|
        worker.vm.hostname = worker_name
        worker.vm.provider :virtualbox do |vb|
          vb.memory = $vm_memory
          worker.ignition.enabled = true
        end

        # Set the private ip.
        worker.vm.network :private_network, ip: worker_ip
        worker.ignition.ip = worker_ip

        # Set the ignition data.
        worker.vm.provider :virtualbox do |vb|
          worker.ignition.hostname = "#{worker_name}.tdskubes.com"
          worker.ignition.drive_root = "provisioning"
          worker.ignition.drive_name = "config-worker-#{w}"
          worker.ignition.path = IGNITION_PATH
        end
        workers << worker_name
        worker_hostvars = {
          worker_name => {
            "ansible_python_interpreter" => "/home/core/bin/python",
            "private_ipv4" => worker_ip,
            "public_ipv4" => worker_ip,
            "role" => "worker",
          }
        }
        hostvars.merge!(worker_hostvars)
      end
    end

    # Create the master nodes.
    (1..MASTER_COUNT).each do |m|
      # Set the host name and ip
      master_name = "master0#{m}"
      master_ip = $master_ip_start + "#{m}"
      last = (m >= MASTER_COUNT)

      config.vm.define master_name, primary: last do |master|
        master.vm.hostname = master_name
        master.vm.provider :virtualbox do |vb|
          vb.memory = $vm_memory
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

        # Provision only when all machines are up and running.
        if last
          config.vm.provision :ansible do |ansible|
            ansible.groups = {
              "role=master": masters,
              "role=worker": workers,
              "all": masters + workers,
            }
            ansible.host_vars = hostvars
            # this will force the provision to happen on all machines to achieve parallel provisioning.
            ansible.limit = "all"
            ansible.playbook = "provisioning/playbook.yml"
          end
        end
      end
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
  ct -pretty -platform vagrant-virtualbox < node.clc > node.ign
  ```

  This ignition configuration will permanently disable the auto-update and rebooting of the container linux for us.
  Up to this point we are able to create container linux masters, however we can't use Ansible to provision it yet because Ansible requires the target machine to have python installed to work and container linux doesn't come with python natively due to its nature of having only components needed to run containers. In order to solve this problem, we have to install `pypy` first, we're able to do it taking advantage of Ansible's `raw` module (module that doesn't require python). Let's create the `playbook.yml`:

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
  ```

By now we've got 3 masters, and 1 worker running on coreos container linux, with python and pip installed. This makes Ansible usable for future provisioning tasks, In [part2](http://blog.wumuxian1988.com/2018/01/10/HA-Kubernetes-cluster-with-Vagrant-CoreOS-Ansible-Part-2/) I'll setup `etcd` on the master nodes.
