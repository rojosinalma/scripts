#!/bin/bash

echo "INFO -- : Killing Radarr"
screen -XS radarr kill
sleep 2
pkill -9 -fu "$(whoami)" 'Radarr'
