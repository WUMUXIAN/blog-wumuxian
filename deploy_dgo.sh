#!/bin/bash
# This deployment script deploy the image using Kubernetes
version=`cat currentVersion`
ansible -i "188.166.184.10," all -u root -m shell -a "docker rm -f blog"
ansible -i "188.166.184.10," all -u root -m shell -a "docker run --restart always -d -p 8080 --name blog -l traefik.frontend.rule=Host:www.wumuxian1988.com,blog.wumuxian1988.com --network=traefik_default wumuxian/blog:v${version}"
