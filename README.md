# Personal Blog Powered by Hexo and Disqus

[![Build Status](https://travis-ci.org/WUMUXIAN/blog-wumuxian.svg?branch=master)](https://travis-ci.org/WUMUXIAN/blog-wumuxian)

## Get Started

### Install hexo-cli
If you are setting up the environment on a new machine, please do the following:
```bash
./install_hexo.sh
```
If you have a problem finding nvm, probably you are using zsh, copy the following content to your .zshrc:
```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
```
Once you have installed hexo-cli, you are able to create new posts.

### Install dependencies
```bash
npm install
cd hexo
LIBSASS_EXT="no" npm install
```

### Run server locally.
```bash
cd hexo
hexo server
```

## Write a new post
```bash
hexo new post "Your Post Name"
```

## Build and deploy
```bash
./build.sh
./deploy_dgo.sh
```
