hexo clean
hexo generate
rm -rf ../public
cp -rf public ../
rm -rf public
