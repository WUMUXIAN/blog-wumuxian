#!/bin/bash
cd hexo
sh publish.sh
cd ..
docker build -t wumuxian/blog .
