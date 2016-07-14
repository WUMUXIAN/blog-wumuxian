---
title: Create VPC environment using Terraform on AWS 
date: 2016-05-31 21:56:57
tags: 
  - VPC
  - Terraform
  - AWS
  - Subnet
  - Internet Gateway
  - NAT Gateway
  - Route Table
  - Security Group
category: 
  - Infrastructure
---

It's a common practice to create a VPC to provide logically isolated section of the cloud and the freedom of creating IP address range, subnets, route tables and network gateways. It brings flexibility of access control and multiple layers of security. But it's a non-trivial task to create the VPC environment using the AWS Web Interface, you have to click here and there, jumping from page to page, and it's not replayable and portable, e.g. if you want to replicate one setup, or you want to have the same configuration in another AWS account, you gotta have to re-do it all over again. 

AWS has opened APIs and provided a CLI tool to manage all its services, we can write shell scripts to programatically do the process and make it replayable. But there're a lot of other tools developed to make life even easier, and one of the best is [Terraform](https://www.terraform.io/intro/index.html).

Terraform treats the provisioning of infrastructure as programming. To create the resources, you write scripts, validate them and use them to build, change, and version the infrastructure. Terraform supports existing popular service providers such as AWS, GCE, Open Stack, Digital Ocean and etc. This post shows you how to provision a VPC environment using Terraform on AWS.

## Getting Started
Let's getting started, first of all, download Terraform and install. This post assumes that you're using MacOS.
```bash
cd the_folder_you_want_to_put_terraform
wget https://releases.hashicorp.com/terraform/0.6.16/terraform_0.6.16_darwin_amd64.zip -O temp.zip; unzip temp.zip; rm temp.zip
export PATH=the_folder_you_put_terraform:$PATH
echo "export PATH=the_folder_you_put_terraform:$PATH" >> ~/.bash_profile
```
Now you can verify it by typing:
```bash
terraform help
usage: terraform [--version] [--help] <command> [<args>]

Available commands are:
    apply       Builds or changes infrastructure
    destroy     Destroy Terraform-managed infrastructure
    fmt         Rewrites config files to canonical format
    get         Download and install modules for the configuration
    graph       Create a visual graph of Terraform resources
    init        Initializes Terraform configuration from a module
    output      Read an output from a state file
    plan        Generate and show an execution plan
    push        Upload this Terraform module to Atlas to run
    refresh     Update local state file against real resources
    remote      Configure remote state storage
    show        Inspect Terraform state or plan
    taint       Manually mark a resource for recreation
    untaint     Manually unmark a resource as tainted
    validate    Validates the Terraform files
    version     Prints the Terraform version
```
For security reason, you should not explicitly put your AWS credentials in your Terraform script, instead you can let Terraform read from your aws configuration located at "~/.aws/credentials". You can manually create the file and put in your credentials, or you can use [aws-cli](https://aws.amazon.com/cli/) to set it up for you. To install aws-cli, make sure that you have python and pip installed and then run the following command:
```bash
sudo pip install aws-cli
```
Now run the following command and fill in your credentials to set up the aws profile:
```bash
aws configure --profile your_profile
```
And when this is done, you can find your credentials save at "~/.aws/credentials"
```bash
[default]
aws_access_key_id = XXXXXXXXXXXX
aws_secret_access_key = XXXXXXXXXXXXXXXXXXXXXXXX
[profile1]
aws_access_key_id = XXXXXXXXXXXX
aws_secret_access_key = XXXXXXXXXXXXXXXXXXXXXXXX
```

## Writing Terraform Script
First of all, create a folder and name it as "terraform/aws"
```bash
mkdir -p terraform/aws
cd terraform/aws
```
We're going to take advantage of terraform's module function, name the module "vpc" and we assume that "region" is a required parameter to pass to the module:
```bash
vi aws.tf
...
provider "aws" {
  profile = "your_aws_profile"
  region = "${var.region}"
}
module "vpc" {
    source = "./vpc"
    region = "${var.region}"
}
```
Now create the module folder and the code to create the vpc.
```bash
mkdir vpc
vi vpc/main.tf 
```
In the script, I will create the following resources:
1. One VPC
2. One public subnet with one route table associated, which routes to the internet gateway.
3. One Elastic IP address and one NAT gateway
4. One private subnet associated with one route table associated, which routes to the NAT gateway.

#### Specify the variables
```bash
variable "region" {}
variable "availability_zones"  {
  default = "d" 
}

variable "vpc_long_name" {default = "test_vpc"}
variable "vpc_cidr" {default = "10.11.0.0/16"}
variable "internet_gateway_name" {default = "test_igw"}

variable "cidr_blocks" {
  default = {
    private = "10.11.30.0/24"
    public = "10.11.0.0/24"
  }
}

variable "route_table_names" {
  default = {
    private = "Private"
    public = "Public"
  }
}
variable "subnet_names" {
  default = {
    private = "private subnet"
    public = "public subnet"
  }
}
```

#### VPC
```bash
resource "aws_vpc" "main" {
  cidr_block = "${var.vpc_cidr}"
  instance_tenancy = "default"
  enable_dns_hostnames = true
  tags {
    Name = "${var.vpc_long_name}"
  }
}
```

#### Internet gateway
```bash
resource "aws_internet_gateway" "main" {
  vpc_id = "${aws_vpc.main.id}"
  tags {
    Name = "${var.internet_gateway_name}"
  }
}
```

#### Public subnet
```bash
resource "aws_subnet" "public" {
  vpc_id = "${aws_vpc.main.id}"
  cidr_block = "${lookup(var.cidr_blocks, "public")}"
  availability_zone = "${var.region}${element(split(",", var.availability_zones), 0)}"
  tags {
    Name = "${lookup(var.subnet_names, "public")}"
  }
}
```

#### Route table for public subnet
```bash
resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.main.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.main.id}"
  }
  tags {
    Name = "${lookup(var.route_table_names, "public")}"
  }
}
```

#### Associate the public subnet with the route table
```bash
resource "aws_route_table_association" "public" {
  subnet_id = "${aws_subnet.public.id}"
  route_table_id = "${aws_route_table.public.id}"
}
```

#### Create the elastics IP address
```bash
resource "aws_nat_gateway" "main" {
  subnet_id = "${aws_subnet.public.id}"
  allocation_id = "${aws_eip.main.id}"
  depends_on = ["aws_internet_gateway.main"]
}
```

#### Create the NAT gateway with the elastic IP address and the public subnet
```bash
resource "aws_nat_gateway" "main" {
  subnet_id = "${aws_subnet.public.id}"
  allocation_id = "${aws_eip.main.id}"
  depends_on = ["aws_internet_gateway.main"]
}
```

#### Create the private subnet
```bash
resource "aws_subnet" "private" {
  vpc_id = "${aws_vpc.main.id}"
  cidr_block = "${lookup(var.cidr_blocks, "private")}"
  availability_zone = "${var.region}${element(split(",", var.availability_zones), 0)}"
  tags {
    Name = "${lookup(var.subnet_names, "private")}"
  }
}
```

#### Create the route table for the private subnet
```bash
resource "aws_route_table" "private" {
  vpc_id = "${aws_vpc.main.id}"
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = "${aws_nat_gateway.main.id}"
  }
  tags {
    Name = "${lookup(var.route_table_names, "private")}"
  }
} 
```

#### Associate the private subnet with the route table
```bash
resource "aws_route_table_association" "private" {
  subnet_id = "${aws_subnet.private.id}"
  route_table_id = "${aws_route_table.private.id}"
}
```

## Run terraform
Before you run the script, you can actually run "terraform plan" to check whether the behaviour is intended, if everything is fine, then apply and create the resources:
```bash
terraform get
terraform plan
terraform apply
```
If it sucessfully runs, go to your AWS console and check, your VPC environment should be there already. Use "terraform show" to see the current state of terraform, and make some little changes to the script and use "terraform plan" to how terraform recognize the difference.

The complete script can be found at https://github.com/WUMUXIAN/Terraform-Samples/tree/master/aws/sample

