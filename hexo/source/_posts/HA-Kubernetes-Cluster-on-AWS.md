---
title: HA Kubernetes Cluster on AWS
date: 2018-06-12 15:31:44
tags:
 - Kubernetes
 - Docker
category:
 - DevOps
---

By using Kubernetes, we basically delegate the responsibilities to achieve high availability and scalability to Kubernetes, Thus having a HA Kubernetes cluster running is the first step to begin with and the foundation of the whole backend.

Since our workload is running on AWS and AWS EKS is still quite primitive and not production tested enough, we'll go with deploying and managing a K8S cluster on our own using popular open source tools. The advantages of doing this is:

* The installation process is fully automated.
* The community is big and active.
* We have full control over the cluster we created.
* Since it's open source, we can figure out what exactly is going on and have a better understanding of the Cluster.
* Since it's open source, we can customise our deployment based on our own requirements.

Compared to commercial managed Kubernetes cluster, the shortage is also quite obvious:

* The maintenance effort will be higher.

## Installing K8S cluster using kops

To cut the story short, we're using [_**kops**_](https://github.com/kubernetes/kops),  a popular installation tool open sourced on github. It has official step-to-step guides on it's github page, but it's too primitive. The purpose of this article is to show how we used kops with customizations to deploy our K8S cluster.

To check the version matrix and install your desired kops and kubectl for your OS, please follow the official documentation. You will also need to install terraform, the versions we used is:

| software | version |
| :---: | :---: |
| kops | 1.9.0 |
| kubectl | 1.9.7 |
| k8s | 1.9.3 |
| terraform | 0.11.7 |

I assume you have required tools installed already on your machine by now.


#### IAM Permissions

Since kops deploys K8S cluster on AWS, you need to prepare an AWS IAM account with the following access right:

```
AmazonEC2FullAccess
AmazonRoute53FullAccess
AmazonS3FullAccess
IAMFullAccess
AmazonVPCFullAccess
```

In order to be able to give any developers the ability to do it, I'll create a group called kops that has the above access rights. In case we want to give other developers to ability to play with K8S cluster, just add new IAM users to the group.

I assume you will use Terraform to manage AWS resources, the following is the detail .tf configurations:

```
resource "aws_iam_group" "kops" {
  name = "kops"
}

resource "aws_iam_group_policy_attachment" "kops-ec2" {
  group      = "${aws_iam_group.kops.name}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_group_policy_attachment" "kops-route53" {
  group      = "${aws_iam_group.kops.name}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonRoute53FullAccess"
}

resource "aws_iam_group_policy_attachment" "kops-s3" {
  group      = "${aws_iam_group.kops.name}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_group_policy_attachment" "kops-iam" {
  group      = "${aws_iam_group.kops.name}"
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}

resource "aws_iam_group_policy_attachment" "kops-vpc" {
  group      = "${aws_iam_group.kops.name}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonVPCFullAccess"
}
```

#### DNS

We'll create a gossip-based cluster, so we don't have to configure any DNS, the only requirement to trigger this is to have the cluster name end with **.k8s.local**. In our case, we name our K8S cluster as _**mx-cluster.k8s.local**_.

#### State Store

The state store required is a S3 bucket, it's used to store all the states and representations of the K8S cluster you created. The bucket we created is _**mx-k8s-state**_ in the us-east-1 region, in which our K8S is located.

The same as the IAM group, we use Terraform to do this and you can find the code in the same file:

```
resource "aws_s3_bucket" "mx-k8s-state" {
    bucket = "mx-k8s-state"
    acl = "private"
    versioning {
        enabled = true
    }
    tags {
        Name                                = "mx-k8s-state"
        KubernetesCluster                   = "mx-cluster.k8s.local"
    }
}
```

#### VPC, Subnets, Route tables and NAT gateway

It's not compulsory to create VPC, subnets and NAT gateway on our own, we only choose to do this before hand because if we leverage kops to do it, it always creates 1 NAT gateway per AZ, which is a waste of resources and money. We only need 1 NAT gateway and let all private subnets share it. And the key to do this correctly is to create the required resources and tag them the way kops will tag it properly, then when we create the cluster using kops, we can specify.

The .tf configuration is as follows:

```
resource "aws_vpc" "mx-cluster-k8s-local" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    KubernetesCluster                             = "mx-cluster.k8s.local"
    Name                                          = "mx-cluster.k8s.local"
    "kubernetes.io/cluster/mx-cluster.k8s.local" = "owned"
  }
}

resource "aws_vpc_dhcp_options" "mx-cluster-k8s-local" {
  domain_name         = "ec2.internal"
  domain_name_servers = ["AmazonProvidedDNS"]

  tags = {
    KubernetesCluster                             = "mx-cluster.k8s.local"
    Name                                          = "mx-cluster.k8s.local"
    "kubernetes.io/cluster/mx-cluster.k8s.local" = "owned"
  }
}

resource "aws_vpc_dhcp_options_association" "mx-cluster-k8s-local" {
  vpc_id          = "${aws_vpc.mx-cluster-k8s-local.id}"
  dhcp_options_id = "${aws_vpc_dhcp_options.mx-cluster-k8s-local.id}"
}

resource "aws_subnet" "us-east-1a-mx-cluster-k8s-local" {
  vpc_id            = "${aws_vpc.mx-cluster-k8s-local.id}"
  cidr_block        = "10.1.32.0/19"
  availability_zone = "us-east-1a"

  tags = {
    KubernetesCluster                             = "mx-cluster.k8s.local"
    Name                                          = "us-east-1a.mx-cluster.k8s.local"
    SubnetType                                    = "Private"
    "kubernetes.io/cluster/mx-cluster.k8s.local" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

resource "aws_subnet" "us-east-1b-mx-cluster-k8s-local" {
  vpc_id            = "${aws_vpc.mx-cluster-k8s-local.id}"
  cidr_block        = "10.1.64.0/19"
  availability_zone = "us-east-1b"

  tags = {
    KubernetesCluster                             = "mx-cluster.k8s.local"
    Name                                          = "us-east-1b.mx-cluster.k8s.local"
    SubnetType                                    = "Private"
    "kubernetes.io/cluster/mx-cluster.k8s.local" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

resource "aws_subnet" "us-east-1c-mx-cluster-k8s-local" {
  vpc_id            = "${aws_vpc.mx-cluster-k8s-local.id}"
  cidr_block        = "10.1.96.0/19"
  availability_zone = "us-east-1c"

  tags = {
    KubernetesCluster                             = "mx-cluster.k8s.local"
    Name                                          = "us-east-1c.mx-cluster.k8s.local"
    SubnetType                                    = "Private"
    "kubernetes.io/cluster/mx-cluster.k8s.local" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

resource "aws_subnet" "utility-us-east-1a-mx-cluster-k8s-local" {
  vpc_id            = "${aws_vpc.mx-cluster-k8s-local.id}"
  cidr_block        = "10.1.0.0/22"
  availability_zone = "us-east-1a"

  tags = {
    KubernetesCluster                             = "mx-cluster.k8s.local"
    Name                                          = "utility-us-east-1a.mx-cluster.k8s.local"
    SubnetType                                    = "Utility"
    "kubernetes.io/cluster/mx-cluster.k8s.local" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }
}

resource "aws_subnet" "utility-us-east-1b-mx-cluster-k8s-local" {
  vpc_id            = "${aws_vpc.mx-cluster-k8s-local.id}"
  cidr_block        = "10.1.4.0/22"
  availability_zone = "us-east-1b"

  tags = {
    KubernetesCluster                             = "mx-cluster.k8s.local"
    Name                                          = "utility-us-east-1b.mx-cluster.k8s.local"
    SubnetType                                    = "Utility"
    "kubernetes.io/cluster/mx-cluster.k8s.local" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }
}

resource "aws_subnet" "utility-us-east-1c-mx-cluster-k8s-local" {
  vpc_id            = "${aws_vpc.mx-cluster-k8s-local.id}"
  cidr_block        = "10.1.8.0/22"
  availability_zone = "us-east-1c"

  tags = {
    KubernetesCluster                             = "mx-cluster.k8s.local"
    Name                                          = "utility-us-east-1c.mx-cluster.k8s.local"
    SubnetType                                    = "Utility"
    "kubernetes.io/cluster/mx-cluster.k8s.local" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }
}

resource "aws_eip" "us-east-1a-mx-cluster-k8s-local" {
  vpc      = true
  tags {
    KubernetesCluster                             = "mx-cluster.k8s.local"
    Name                                          = "us-east-1a.mx-cluster.k8s.local"
    "kubernetes.io/cluster/mx-cluster.k8s.local" = "shared"
  }
}

resource "aws_nat_gateway" "us-east-1a-mx-cluster-k8s-local" {
  subnet_id = "${aws_subnet.utility-us-east-1a-mx-cluster-k8s-local.id}"
  allocation_id = "${aws_eip.us-east-1a-mx-cluster-k8s-local.id}"

  tags {
    KubernetesCluster                             = "mx-cluster.k8s.local"
    Name                                          = "us-east-1a.mx-cluster.k8s.local"
    "kubernetes.io/cluster/mx-cluster.k8s.local" = "shared"
  }
}

resource "aws_internet_gateway" "mx-cluster-k8s-local" {
  vpc_id = "${aws_vpc.mx-cluster-k8s-local.id}"

  tags = {
    KubernetesCluster                            = "mx-cluster.k8s.local"
    Name                                         = "mx-cluster.k8s.local"
    "kubernetes.io/cluster/mx-cluster.k8s.local" = "owned"
  }
}

resource "aws_route" "mx-cluster-k8s-local" {
  route_table_id         = "${aws_route_table.mx-cluster-k8s-local.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.mx-cluster-k8s-local.id}"
}

resource "aws_route" "private-us-east-1a-mx-cluster-k8s-local" {
  route_table_id         = "${aws_route_table.private-us-east-1a-mx-cluster-k8s-local.id}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${aws_nat_gateway.us-east-1a-mx-cluster-k8s-local.id}"
}

resource "aws_route" "private-us-east-1b-mx-cluster-k8s-local" {
  route_table_id         = "${aws_route_table.private-us-east-1b-mx-cluster-k8s-local.id}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${aws_nat_gateway.us-east-1a-mx-cluster-k8s-local.id}"
}

resource "aws_route" "private-us-east-1c-mx-cluster-k8s-local" {
  route_table_id         = "${aws_route_table.private-us-east-1c-mx-cluster-k8s-local.id}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${aws_nat_gateway.us-east-1a-mx-cluster-k8s-local.id}"
}

resource "aws_route_table" "private-us-east-1a-mx-cluster-k8s-local" {
  vpc_id = "${aws_vpc.mx-cluster-k8s-local.id}"

  route {
     cidr_block             = "0.0.0.0/0"
     nat_gateway_id         = "${aws_nat_gateway.us-east-1a-mx-cluster-k8s-local.id}"
  }

  tags = {
    KubernetesCluster                             = "mx-cluster.k8s.local"
    Name                                          = "private-us-east-1a.mx-cluster.k8s.local"
    AssociatedNatgateway                          = "${aws_nat_gateway.us-east-1a-mx-cluster-k8s-local.id}"
    "kubernetes.io/cluster/mx-cluster.k8s.local" = "owned"
    "kubernetes.io/kops/role"                     = "private-us-east-1a"
  }
}

resource "aws_route_table" "private-us-east-1b-mx-cluster-k8s-local" {
  vpc_id = "${aws_vpc.mx-cluster-k8s-local.id}"

  route {
     cidr_block             = "0.0.0.0/0"
     nat_gateway_id         = "${aws_nat_gateway.us-east-1a-mx-cluster-k8s-local.id}"
  }

  tags = {
    KubernetesCluster                             = "mx-cluster.k8s.local"
    Name                                          = "private-us-east-1b.mx-cluster.k8s.local"
    AssociatedNatgateway                          = "${aws_nat_gateway.us-east-1a-mx-cluster-k8s-local.id}"
    "kubernetes.io/cluster/mx-cluster.k8s.local" = "owned"
    "kubernetes.io/kops/role"                     = "private-us-east-1b"
  }
}

resource "aws_route_table" "private-us-east-1c-mx-cluster-k8s-local" {
  vpc_id = "${aws_vpc.mx-cluster-k8s-local.id}"

  route {
     cidr_block             = "0.0.0.0/0"
     nat_gateway_id         = "${aws_nat_gateway.us-east-1a-mx-cluster-k8s-local.id}"
  }

  tags = {
    KubernetesCluster                             = "mx-cluster.k8s.local"
    Name                                          = "private-us-east-1c.mx-cluster.k8s.local"
    AssociatedNatgateway                          = "${aws_nat_gateway.us-east-1a-mx-cluster-k8s-local.id}"
    "kubernetes.io/cluster/mx-cluster.k8s.local" = "owned"
    "kubernetes.io/kops/role"                     = "private-us-east-1c"
  }
}

resource "aws_route_table" "mx-cluster-k8s-local" {
  vpc_id = "${aws_vpc.mx-cluster-k8s-local.id}"

  route {
     cidr_block             = "0.0.0.0/0"
     gateway_id             = "${aws_internet_gateway.mx-cluster-k8s-local.id}"
  }

  tags = {
    KubernetesCluster                             = "mx-cluster.k8s.local"
    Name                                          = "mx-cluster.k8s.local"
    "kubernetes.io/cluster/mx-cluster.k8s.local" = "owned"
    "kubernetes.io/kops/role"                     = "public"
  }
}

resource "aws_route_table_association" "private-us-east-1a-mx-cluster-k8s-local" {
  subnet_id      = "${aws_subnet.us-east-1a-mx-cluster-k8s-local.id}"
  route_table_id = "${aws_route_table.private-us-east-1a-mx-cluster-k8s-local.id}"
}

resource "aws_route_table_association" "private-us-east-1b-mx-cluster-k8s-local" {
  subnet_id      = "${aws_subnet.us-east-1b-mx-cluster-k8s-local.id}"
  route_table_id = "${aws_route_table.private-us-east-1b-mx-cluster-k8s-local.id}"
}

resource "aws_route_table_association" "private-us-east-1c-mx-cluster-k8s-local" {
  subnet_id      = "${aws_subnet.us-east-1c-mx-cluster-k8s-local.id}"
  route_table_id = "${aws_route_table.private-us-east-1c-mx-cluster-k8s-local.id}"
}

resource "aws_route_table_association" "utility-us-east-1a-mx-cluster-k8s-local" {
  subnet_id      = "${aws_subnet.utility-us-east-1a-mx-cluster-k8s-local.id}"
  route_table_id = "${aws_route_table.mx-cluster-k8s-local.id}"
}

resource "aws_route_table_association" "utility-us-east-1b-mx-cluster-k8s-local" {
  subnet_id      = "${aws_subnet.utility-us-east-1b-mx-cluster-k8s-local.id}"
  route_table_id = "${aws_route_table.mx-cluster-k8s-local.id}"
}

resource "aws_route_table_association" "utility-us-east-1c-mx-cluster-k8s-local" {
  subnet_id      = "${aws_subnet.utility-us-east-1c-mx-cluster-k8s-local.id}"
  route_table_id = "${aws_route_table.mx-cluster-k8s-local.id}"
}
```

#### Create our cluster configuration

With the above AWS resources created, we can now carry on to create the K8S cluster. Before we create it for real, we can do a dry-run and output the configuration to yaml for review. Now let's do it.

First of all, we are able to get the private subnets and utility subnets by output your terraform state.

```
terraform output
private_subnet_ids = subnet-438b456d,subnet-4ee27204,subnet-9a38f5c6
utility_subnet_ids = subnet-4f894761,subnet-91e070db,subnet-7749842b
vpc_id = vpc-d92424a2

```

Then proceed with the kops creation command, with the vpc and subnets specified.

```
cd ../
kops create cluster --name=mx-cluster.k8s.local \
  --state=s3://mx-k8s-state \
  --vpc="vpc-d92424a2" \
  --subnets="subnet-438b456d,subnet-4ee27204,subnet-9a38f5c6" \
  --utility-subnets="subnet-4f894761,subnet-91e070db,subnet-7749842b" \
  --zones="us-east-1a,us-east-1b,us-east-1c" \
  --node-count=1 \
  --node-size=m5.large \
  --associate-public-ip=false \
  --master-zones="us-east-1a,us-east-1b,us-east-1c" \
  --master-size=m5.large \
  --topology=private \
  --networking=flannel-vxlan \
  --bastion=false \
  --network-cidr="10.1.0.0/16" \
  --image="kope.io/k8s-1.9-debian-stretch-amd64-hvm-ebs-2018-03-11" \
  --admin-access="your.ip.address.topen/32" \
  --dry-run -oyaml
```

Let me explain the other parameters I passed into the command:

| parameter | purpose |
| :---: | :---: |
| name | we specify our cluster name |
| state | we specify our s3 bucket as the state store |
| zones | we make sure the work nodes are distributed in 3 AZs to achieve HA |
| node-count | we only specify 1 work node as bootstrap |
| node-size | we use m5.large instance \(2 cores, 8GB RAM\) |
| associate-public-ip | we don't allow the nodes to reachable from outside world |
| master-zones | we let the master nodes spread across 3 AZs to achieve HA |
| master-size | we use m5.large instance \(2 cores, 8GB RAM\) |
| topology | the cluster will stay in private subnets, and the API will be exposed via ELB |
| networking | we'll use flannel-vxlan CNI |
| bastion | we'll not create the bastion instance here |
| network-cidr | a new VPC will be created using this cidr |
| image | we use debian stretch for compatibility of k8s 1.9.x |
| admin-access | for security group to allow access from our office |

You should see the output like this:

```
apiVersion: kops/v1alpha2
kind: Cluster
metadata:
  creationTimestamp: null
  name: mx-cluster.k8s.local
spec:
  api:
    loadBalancer:
      type: Public
  authorization:
    rbac: {}
  channel: stable
  cloudProvider: aws
  configBase: s3://mx-k8s-state/mx-cluster.k8s.local
  etcdClusters:
  - etcdMembers:
    - instanceGroup: master-us-east-1a
      name: a
    - instanceGroup: master-us-east-1b
      name: b
    - instanceGroup: master-us-east-1c
      name: c
    name: main
  - etcdMembers:
    - instanceGroup: master-us-east-1a
      name: a
    - instanceGroup: master-us-east-1b
      name: b
    - instanceGroup: master-us-east-1c
      name: c
    name: events
  iam:
    allowContainerRegistry: true
    legacy: false
  kubernetesApiAccess:
  - your.ip.address.topen/32
  kubernetesVersion: 1.9.3
  masterPublicName: api.mx-cluster.k8s.local
  networkCIDR: 10.1.0.0/16
  networkID: vpc-d92424a2
  networking:
    flannel:
      backend: vxlan
  nonMasqueradeCIDR: 100.64.0.0/10
  sshAccess:
  - your.ip.address.topen/32
  subnets:
  - cidr: 10.1.32.0/19
    id: subnet-438b456d
    name: us-east-1a
    type: Private
    zone: us-east-1a
  - cidr: 10.1.64.0/19
    id: subnet-4ee27204
    name: us-east-1b
    type: Private
    zone: us-east-1b
  - cidr: 10.1.96.0/19
    id: subnet-9a38f5c6
    name: us-east-1c
    type: Private
    zone: us-east-1c
  - cidr: 10.1.0.0/22
    id: subnet-4f894761
    name: utility-us-east-1a
    type: Utility
    zone: us-east-1a
  - cidr: 10.1.4.0/22
    id: subnet-91e070db
    name: utility-us-east-1b
    type: Utility
    zone: us-east-1b
  - cidr: 10.1.8.0/22
    id: subnet-7749842b
    name: utility-us-east-1c
    type: Utility
    zone: us-east-1c
  topology:
    dns:
      type: Public
    masters: private
    nodes: private

---

apiVersion: kops/v1alpha2
kind: InstanceGroup
metadata:
  creationTimestamp: null
  labels:
    kops.k8s.io/cluster: mx-cluster.k8s.local
  name: master-us-east-1a
spec:
  associatePublicIp: false
  image: kope.io/k8s-1.9-debian-stretch-amd64-hvm-ebs-2018-03-11
  machineType: m5.large
  maxSize: 1
  minSize: 1
  nodeLabels:
    kops.k8s.io/instancegroup: master-us-east-1a
  role: Master
  subnets:
  - us-east-1a

---

apiVersion: kops/v1alpha2
kind: InstanceGroup
metadata:
  creationTimestamp: null
  labels:
    kops.k8s.io/cluster: mx-cluster.k8s.local
  name: master-us-east-1b
spec:
  associatePublicIp: false
  image: kope.io/k8s-1.9-debian-stretch-amd64-hvm-ebs-2018-03-11
  machineType: m5.large
  maxSize: 1
  minSize: 1
  nodeLabels:
    kops.k8s.io/instancegroup: master-us-east-1b
  role: Master
  subnets:
  - us-east-1b

---

apiVersion: kops/v1alpha2
kind: InstanceGroup
metadata:
  creationTimestamp: null
  labels:
    kops.k8s.io/cluster: mx-cluster.k8s.local
  name: master-us-east-1c
spec:
  associatePublicIp: false
  image: kope.io/k8s-1.9-debian-stretch-amd64-hvm-ebs-2018-03-11
  machineType: m5.large
  maxSize: 1
  minSize: 1
  nodeLabels:
    kops.k8s.io/instancegroup: master-us-east-1c
  role: Master
  subnets:
  - us-east-1c

---

apiVersion: kops/v1alpha2
kind: InstanceGroup
metadata:
  creationTimestamp: null
  labels:
    kops.k8s.io/cluster: mx-cluster.k8s.local
  name: nodes
spec:
  associatePublicIp: false
  image: kope.io/k8s-1.9-debian-stretch-amd64-hvm-ebs-2018-03-11
  machineType: m5.large
  maxSize: 1
  minSize: 1
  nodeLabels:
    kops.k8s.io/instancegroup: nodes
  role: Node
  subnets:
  - us-east-1a
  - us-east-1b
  - us-east-1c
```

Read the configuration and cross-reference your 3 private subnets and public utility subnets around the 3 AZs, make sure things are correct. Check the instance groups as well \(they are actually AutoScaling Groups\).

Once we're sure that things are good, we can carry out the cluster provisioning for real. We still leverage Terraform to do it. kops can output Terraform configuration files so it makes our life easy.

Now let's create the cluster for real! As we've been using Terraform to manage our AWS resources, luckily here we can use Terraform too as kops is able to generate Terraform configuration files. Run the following command:

```
kops create cluster --name=mx-cluster.k8s.local \
  --state=s3://mx-k8s-state \
  --zones "us-east-1a,us-east-1b,us-east-1c" \
  --node-count=1 \
  --node-size=m5.large \
  --associate-public-ip=false \
  --master-zones "us-east-1a,us-east-1b,us-east-1c" \
  --master-size=m5.large \
  --topology=private \
  --networking=flannel-vxlan \
  --bastion=false \
  --network-cidr="10.1.0.0/16" \
  --image="kope.io/k8s-1.9-debian-stretch-amd64-hvm-ebs-2018-03-11" \
  --admin-access="your.ip.address.topen/32" \
  --out=. \
  --target=terraform
```

You should see the kubernetes.tf file and a data folder generated in the current directory.

Here before we apply the configuration, we need to make a customization, if you notice the above yaml, the sshAccess defines whom to open the 22 for sshAccess. Because our nodes are in private subnets and we'll use a VPN connection, we need to adjust this value to the following:

```
kops edit cluster --name=mx-cluster.k8s.local --state=s3://mx-k8s-state

// update this value
// sshAccess:
// from your.ip.address.topen/32 to 10.1.0.0/16
// This means allow any 22 traffic from the instances with in the VPC.
```

After making this change, we re-generate the terraform configurations by running:

```
kops update cluster --name=mx-cluster.k8s.local \
  --state=s3://mx-k8s-state \
  --out=. \
  --target=terraform
```

Apply the configuration to create the cluster:

```
terraform init
terraform plan -out plan
terraform apply "plan"
```

Once this command is done, all the required AWS resources will be already created, and K8S clusters will be bootstrapping on the master and worker nodes. You can check whether your cluster is up and running by:

```
kops validate cluster mx-cluster.k8s.local --state=s3://mx-k8s-state
Validating cluster mx-cluster.k8s.local

INSTANCE GROUPS
NAME			ROLE	MACHINETYPE	MIN	MAX	SUBNETS
master-us-east-1a	Master	m5.large	1	1	us-east-1a
master-us-east-1b	Master	m5.large	1	1	us-east-1b
master-us-east-1c	Master	m5.large	1	1	us-east-1c
nodes			Node	m5.large	1	1	us-east-1a,us-east-1b,us-east-1c

NODE STATUS
NAME				ROLE	READY
ip-10-1-121-175.ec2.internal	master	True
ip-10-1-39-127.ec2.internal	master	True
ip-10-1-47-176.ec2.internal	node	True
ip-10-1-86-18.ec2.internal	master	True

Your cluster mx-cluster.k8s.local is ready
```

To make yourself life easier, you can set environment variables for name and state so that you don't have to repeat yourself every time.

```
export NAME=mx-cluster.k8s.local
export KOPS_STATE_STORE=s3://mx-k8s-state

kops validate cluster                                                                                                                                                                                            ✔  10008  13:05:34
Using cluster from kubectl context: mx-cluster.k8s.local

Validating cluster mx-cluster.k8s.local

INSTANCE GROUPS
NAME			ROLE	MACHINETYPE	MIN	MAX	SUBNETS
master-us-east-1a	Master	m5.large	1	1	us-east-1a
master-us-east-1b	Master	m5.large	1	1	us-east-1b
master-us-east-1c	Master	m5.large	1	1	us-east-1c
nodes			Node	m5.large	1	1	us-east-1a,us-east-1b,us-east-1c

NODE STATUS
NAME				ROLE	READY
ip-10-1-121-175.ec2.internal	master	True
ip-10-1-39-127.ec2.internal	master	True
ip-10-1-47-176.ec2.internal	node	True
ip-10-1-86-18.ec2.internal	master	True

Your cluster mx-cluster.k8s.local is ready
```

Up to this point, the k8s cluster is up and running, in order to make it usable for us, we need to do some additional work: add some add-ons to it. Proceed to next section for instructions.

## Deploy required add-ons for Kubernetes Cluster on AWS

After the bare-metal k8s cluster is up and running, We still need to deploy some add-ons onto the cluster to make it usable.

### Dashboard

We might want to have a nice web-based UI to check the status of our cluster, here comes in the dashboard.

```
kubectl create -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/kubernetes-dashboard/v1.8.3.yaml
```

Now visit the dashboard at:

https://your-api-elb/ui

You will be prompt to input login credentials, the user name will be **admin**, the password can be get by running:

```
kubectl config view --minify
```

The dashboard is integrated with RBAC of k8s, so in order to view all resources, you need to grant the default user as a cluster admin.

```
vi kube-system-rbac-role-binding.yml

# Input the following configurations.

apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: system:default-sa
subjects:
  - kind: ServiceAccount
    name: default
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io

kubectl create -f kube-system-rbac-role-binding.yml
```

Get the login token by running:

```
kubectl -n kube-system describe $(kubectl -n kube-system get secret -o name | grep 'default-token') | awk '/token:/ {print $2}'
```

### Heapster

We also want to have some basic monitoring regarding the usage of CPU and RAM of the nodes in the cluster. We can deploy heapster to do it:

```
kubectl create -f https://github.com/kubernetes/kops/blob/master/addons/monitoring-standalone/v1.7.0.yaml
```

After heapster is up and running, we will start to get graphs about CPU and RAM usage in the dashboard.

### Ingress Controller

Exposing all services running inside the cluster using **LoadBalancer** is not a real good idea, because for each service that you specify a LoadBalancer, the k8s cluster will create an AWS ELB for you, that means if you have 5 services, you will created 5 ELBs, which is obviously not ideal. To solve this problem, we can deploy a ingress controller add-on. The one we use will be the nginx ingress controller, which is able to do TLS termination, HTTP to HTTPs redirection and domain based routing.

In order to make this to work, we need create a few more AWS resources to support it:

* An Ingress AWS ELB
* An Security Group to be used by this AWS ELB which allows traffic from 80 and 443
* An Security Group Rule for the nodes to allow traffic from the Ingress ELB.
* Attach the nodes to the Ingress AWS ELB

We will continue to use Terraform to create these resources, modify the kubernetes.tf file generated previously and add in the following configurations:

```
resource "aws_security_group" "ingress-mx-cluster-k8s-local" {
  name        = "ingress.mx-cluster.k8s.local"
  vpc_id      = "vpc-d92424a2"
  description = "Security group for nginx ingress ELB"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3
    to_port     = 4
    protocol    = "ICMP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = {
    KubernetesCluster                             = "mx-cluster.k8s.local"
    Name                                          = "ingress.mx-cluster.k8s.local"
    "kubernetes.io/cluster/mx-cluster.k8s.local" = "owned"
  }
}

resource "aws_security_group_rule" "all-node-to-ingress" {
  type                     = "ingress"
  security_group_id        = "${aws_security_group.nodes-mx-cluster-k8s-local.id}"
  source_security_group_id = "${aws_security_group.ingress-mx-cluster-k8s-local.id}"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
}

resource "aws_elb" "ingress-mx-cluster-k8s-local" {
  name = "ingress-mx-cluster-k8s-local"

  listener = {
    instance_port     = 30275
    instance_protocol = "TCP"
    lb_port           = 443
    lb_protocol       = "TCP"
  }

  listener = {
    instance_port     = 31982
    instance_protocol = "TCP"
    lb_port           = 80
    lb_protocol       = "TCP"
  }

  cross_zone_load_balancing = true

  security_groups = ["${aws_security_group.ingress-mx-cluster-k8s-local.id}"]
  subnets         = ["subnet-4f894761", "subnet-7749842b", "subnet-91e070db"]

  health_check = {
    target              = "TCP:31982"
    healthy_threshold   = 2
    unhealthy_threshold = 6
    interval            = 10
    timeout             = 5
  }

  idle_timeout = 60

  tags = {
    KubernetesCluster                             = "mx-cluster.k8s.local"
    "kubernetes.io/service-name"                  = "kube-ingress/ingress-nginx"
    "kubernetes.io/cluster/mx-cluster.k8s.local" = "owned"
  }
}

resource "aws_autoscaling_attachment" "nodes-mx-cluster-k8s-local" {
  elb                    = "${aws_elb.ingress-mx-cluster-k8s-local.id}"
  autoscaling_group_name = "${aws_autoscaling_group.nodes-mx-cluster-k8s-local.id}"
}

resource "aws_load_balancer_policy" "proxy-protocol" {
  load_balancer_name = "${aws_elb.ingress-mx-cluster-k8s-local.name}"
  policy_name        = "k8s-proxyprotocol-enabled"
  policy_type_name   = "ProxyProtocolPolicyType"

  policy_attribute = {
    name  = "ProxyProtocol"
    value = "true"
  }
}

resource "aws_load_balancer_backend_server_policy" "proxy-protocol-80" {
  load_balancer_name = "${aws_elb.ingress-mx-cluster-k8s-local.name}"
  instance_port = 31982

  policy_names = [
    "${aws_load_balancer_policy.proxy-protocol.policy_name}",
  ]
}

resource "aws_load_balancer_backend_server_policy" "proxy-protocol-443" {
  load_balancer_name = "${aws_elb.ingress-mx-cluster-k8s-local.name}"
  instance_port = 30275

  policy_names = [
    "${aws_load_balancer_policy.proxy-protocol.policy_name}",
  ]
}
```

Plan and review the changes and apply when you're confirmed:

```
terraform plan -out plan
terraform apply "plan"
```

We now have the AWS infrastructure ready for the ingress controller, let's deploy the ingress controller:

```
vi nginx-ingress-controller.yml

# Add the following configurations

apiVersion: v1
kind: Namespace
metadata:
  name: kube-ingress
  labels:
    k8s-addon: ingress-nginx.addons.k8s.io

---

apiVersion: v1
kind: ServiceAccount
metadata:
  name: nginx-ingress-controller
  namespace: kube-ingress
  labels:
    k8s-addon: ingress-nginx.addons.k8s.io

---

apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  labels:
    k8s-addon: ingress-nginx.addons.k8s.io
  name: nginx-ingress-controller
  namespace: kube-ingress
rules:
  - apiGroups:
      - ""
    resources:
      - configmaps
      - endpoints
      - nodes
      - pods
      - secrets
    verbs:
      - list
      - watch
  - apiGroups:
      - ""
    resources:
      - nodes
    verbs:
      - get
  - apiGroups:
      - ""
    resources:
      - services
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - "extensions"
    resources:
      - ingresses
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - ""
    resources:
        - events
    verbs:
        - create
        - patch
  - apiGroups:
      - "extensions"
    resources:
      - ingresses/status
    verbs:
      - update

---

apiVersion: rbac.authorization.k8s.io/v1beta1
kind: Role
metadata:
  labels:
    k8s-addon: ingress-nginx.addons.k8s.io
  name: nginx-ingress-controller
  namespace: kube-ingress
rules:
  - apiGroups:
      - ""
    resources:
      - configmaps
      - pods
      - secrets
    verbs:
      - get
  - apiGroups:
      - ""
    resources:
      - configmaps
    resourceNames:
      # Defaults to "<election-id>-<ingress-class>"
      # Here: "<ingress-controller-leader>-<nginx>"
      # This has to be adapted if you change either parameter
      # when launching the nginx-ingress-controller.
      - "ingress-controller-leader-nginx"
    verbs:
      - get
      - update
  - apiGroups:
      - ""
    resources:
      - configmaps
    verbs:
      - create
  - apiGroups:
      - ""
    resources:
      - endpoints
    verbs:
      - get
      - create
      - update

---

apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  labels:
    k8s-addon: ingress-nginx.addons.k8s.io
  name: nginx-ingress-controller
  namespace: kube-ingress
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: nginx-ingress-controller
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: system:serviceaccount:kube-ingress:nginx-ingress-controller

---

apiVersion: rbac.authorization.k8s.io/v1beta1
kind: RoleBinding
metadata:
  labels:
    k8s-addon: ingress-nginx.addons.k8s.io
  name: nginx-ingress-controller
  namespace: kube-ingress
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: nginx-ingress-controller
subjects:
  - kind: ServiceAccount
    name: nginx-ingress-controller
    namespace: kube-ingress

---

kind: Service
apiVersion: v1
metadata:
  name: nginx-default-backend
  namespace: kube-ingress
  labels:
    k8s-app: default-http-backend
    k8s-addon: ingress-nginx.addons.k8s.io
spec:
  ports:
  - port: 80
    targetPort: http
  selector:
    app: nginx-default-backend

---

kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: nginx-default-backend
  namespace: kube-ingress
  labels:
    k8s-app: default-http-backend
    k8s-addon: ingress-nginx.addons.k8s.io
spec:
  replicas: 1
  revisionHistoryLimit: 10
  template:
    metadata:
      labels:
        k8s-app: default-http-backend
        k8s-addon: ingress-nginx.addons.k8s.io
        app: nginx-default-backend
    spec:
      terminationGracePeriodSeconds: 60
      containers:
      - name: default-http-backend
        image: k8s.gcr.io/defaultbackend:1.3
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 30
          timeoutSeconds: 5
        resources:
          limits:
            cpu: 10m
            memory: 20Mi
          requests:
            cpu: 10m
            memory: 20Mi
        ports:
        - name: http
          containerPort: 8080
          protocol: TCP

---

kind: ConfigMap
apiVersion: v1
metadata:
  name: ingress-nginx
  namespace: kube-ingress
  labels:
    k8s-addon: ingress-nginx.addons.k8s.io
data:
  use-proxy-protocol: "true"

---

kind: Service
apiVersion: v1
metadata:
  name: ingress-nginx
  namespace: kube-ingress
  labels:
    k8s-addon: ingress-nginx.addons.k8s.io
spec:
  type: NodePort
  selector:
    app: ingress-nginx
  ports:
  - name: http
    nodePort: 31982
    port: 80
    protocol: TCP
    targetPort: http
  - name: https
    nodePort: 30275
    port: 443
    protocol: TCP
    targetPort: https

---

kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: ingress-nginx
  namespace: kube-ingress
  labels:
    k8s-app: nginx-ingress-controller
    k8s-addon: ingress-nginx.addons.k8s.io
spec:
  replicas: 3
  template:
    metadata:
      labels:
        app: ingress-nginx
        k8s-app: nginx-ingress-controller
        k8s-addon: ingress-nginx.addons.k8s.io
      annotations:
        prometheus.io/port: '10254'
        prometheus.io/scrape: 'true'
    spec:
      terminationGracePeriodSeconds: 60
      serviceAccountName: nginx-ingress-controller
      containers:
      - image: quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.12.0
        name: nginx-ingress-controller
        imagePullPolicy: Always
        ports:
          - name: http
            containerPort: 80
            protocol: TCP
          - name: https
            containerPort: 443
            protocol: TCP
        readinessProbe:
          httpGet:
            path: /healthz
            port: 10254
            scheme: HTTP
        livenessProbe:
          httpGet:
            path: /healthz
            port: 10254
            scheme: HTTP
          initialDelaySeconds: 30
          timeoutSeconds: 5
        env:
          - name: POD_NAME
            valueFrom:
              fieldRef:
                fieldPath: metadata.name
          - name: POD_NAMESPACE
            valueFrom:
              fieldRef:
                fieldPath: metadata.namespace
        args:
        - /nginx-ingress-controller
        - --default-backend-service=$(POD_NAMESPACE)/nginx-default-backend
        - --configmap=$(POD_NAMESPACE)/ingress-nginx
        - --publish-service=$(POD_NAMESPACE)/ingress-nginx
        - --annotations-prefix=ingress.kubernetes.io


kubectl create -f nginx-ingress-controller.yml
```

Now go to the ingress ELB and wait for a while, you should see the active instance becomes 1, this means the ingress has been successfully setup.

Up to this point, your cluster is ready for you to deploy your workload!

![Nodes](k8s-workload.jpg)
