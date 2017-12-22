FROM node:4.8.7-alpine
MAINTAINER Wu Muxian <mw@tectusdreamlab.com>

ADD public/ /home/node/public/
ADD server.js /home/node/server.js
ADD package.json /home/node/package.json

WORKDIR /home/node

RUN npm install

EXPOSE 8080

CMD ["node", "server.js"]
