#!/bin/bash

echo "INFO -- : Starting Prowlarr"
screen -dmS prowlarr \
/bin/bash -c 'export TMPDIR=~/tmp; /media/sdd1/elfenars/Prowlarr/Prowlarr' 
