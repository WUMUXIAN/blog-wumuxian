#!/bin/bash
# This deployment script deploy the image using Kubernetes
# get the current version.
current_version=$(git tag -l "releases/*" --sort=-v:refname | head -n 1)
current_version=${current_version#"releases/v"}

command="docker run --restart always -d -p 8080 \
	-l 'traefik.enable=true' \
	-l 'traefik.http.routers.route0.rule=Host:(\\\`blog.wumuxian1988.com\\\`)' \
	-l 'traefik.http.routers.route1.rule=Host:(\\\`www.wumuxian1988.com\\\`)' \
	--name blog wumuxian/blog:v${current_version}"

echo $command

ansible -i "165.232.173.38," all -u root -m shell -a "docker rm -f blog"
ansible -i "165.232.173.38," all -u root -m shell -a "$command"
