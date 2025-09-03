#!/bin/bash

echo "INFO -- : Starting Sonarr"
screen -dmS sonarr \
/bin/bash -c 'export TMPDIR=~/tmp; $HOME/Sonarr/Sonarr'
