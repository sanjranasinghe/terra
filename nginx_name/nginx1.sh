#!/bin/bash

apt update
mv /home/admin/id_rsa /root/.ssh/
chown 400 /root/.ssh/id_rsa
cd /usr/local/src/
git clone git@github.com:sanjranasinghe/nginx-new.git
cd nginx-new
docker build -t nginx:latest .
docker run -dp 80:8000 nginx:latest
