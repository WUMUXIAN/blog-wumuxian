---
title: Create VPC environment using Terraform on AWS 
date: 2016-05-31 21:56:57
tags: VPC, Terraform, AWS, Subnet, Internet Gateway, NAT Gateway, Route Table, Security Group
category: Infrastructure, Security
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
For security reason, you should not explicitly put your AWS credentials in your Terraform script, instead you can let Terraform read from your aws configuration located at "~/.aws/credentials". You can manually create the file and put in your credentials as follows:
```bash
hahaha
```
Or you can use [aws-cli](https://aws.amazon.com/cli/) to set it up for you. To install aws-cli, make sure that you have python and pip installed and then run the following command:
```bash
sudo pip install aws-cli
```
Now run the following command and fill in your credentials to set up the aws profile:
```bash
aws configure --profile your_profile
```
