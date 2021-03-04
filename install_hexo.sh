#!/bin/bash

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.37.2/install.sh | bash
# let your terminal pick up the nvm.
source ~/.bash_profile
nvm install stable
npm install -g hexo-cli
