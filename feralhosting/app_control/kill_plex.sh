#!/bin/bash

echo "INFO -- : Killing Plex"
screen -XS plex kill
sleep 2
pkill -9 -fu "$(whoami)" 'plexmediaserver'; pkill -9 -fu "$(whoami)" 'EAE Service'
