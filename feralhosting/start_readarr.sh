#!/bin/bash

echo "INFO -- : Starting Readarr"
screen -dmS readarr \
/bin/bash -c 'export TMPDIR=~/tmp; . /$HOME/Readarr/Readarr'
