#!/bin/bash

echo "INFO -- : Starting Jackett"
screen -dmS jackett \
/bin/bash -c 'export TMPDIR=$HOME/tmp; ~/Jackett/jackett | tee $HOME/Jackett/screen.log'
