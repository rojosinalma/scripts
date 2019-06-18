#!/bin/bash

echo "INFO -- : Starting Radarr"
screen -dmS radarr \
/bin/bash -c 'export TMPDIR=~/tmp; ~/bin/mono --debug Radarr/Radarr.exe'"
