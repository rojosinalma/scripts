#!/bin/bash

echo "INFO -- : Starting Lidar"
screen -dmS lidar \
/bin/bash -c 'export TMPDIR=~/tmp; mono --debug Lidarr/Lidarr.exe'
