#!/bin/bash

echo "INFO -- : Restarting Nginx"
/usr/sbin/nginx -s reload -c ~/.nginx/nginx.conf
