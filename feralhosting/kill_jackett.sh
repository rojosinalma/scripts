#!/bin/bash

echo "INFO -- : Killing Jackett"
screen -XS jackett kill
sleep 2
pkill -9 -fu "$(whoami)" 'jackett'
