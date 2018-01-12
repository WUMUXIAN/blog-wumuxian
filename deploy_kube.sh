#!/bin/bash
# This deployment script deploy the image using Kubernetes
version=`cat currentVersion`
kubectl set image deployment/my-blog my-blog=wumuxian/blog:v${version}
