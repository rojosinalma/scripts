#!/bin/bash

echo "INFO -- : Starting Jackett"
screen -dmS jackett \
/bin/bash -c 'export TMPDIR=$HOME/tmp; cd $HOME/Jackett;./jackett_launcher.sh --NoUpdates'
