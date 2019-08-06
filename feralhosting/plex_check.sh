#!/bin/bash

echo "[$(date)]  INFO -- : Checking if Plex is running"
plexCount=$(ps ux | fgrep "/Plex Media Server" | wc -l)

if [ $plexCount -lt 3 ]; then
  echo "[$(date)]  INFO -- : Plex not running! (Count: $plexCount) Restarting."
  . $HOME/.profile; $HOME/scripts/feralhosting/kill_plex.sh
fi
echo "[$(date)]  INFO -- : Plex is ok, moving on..."
