#!/bin/bash
# This deployment script deploy the image using Kubernetes
version=`cat currentVersion`
ansible -i "139.59.247.115," all -u root -m shell -a "docker rm -f blog"
ansible -i "139.59.247.115," all -u root -m shell -a "docker run -d -p 80:8080 --name blog  wumuxian/blog:v${version}"
