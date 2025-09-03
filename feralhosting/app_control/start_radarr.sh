#!/bin/bash

echo "INFO -- : Starting Radarr"
screen -dmS radarr \
/bin/bash -c 'export TMPDIR=~/.config/Radarr/tmp;/$HOME/Radarr/Radarr -nobrowser'
