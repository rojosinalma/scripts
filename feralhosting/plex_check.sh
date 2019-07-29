#!/bin/bash

echo "[$(date)]  INFO -- : Checking if Plex is running"
plex_count=$(ps ux | fgrep "/Plex Media Server" | wc -l)

if [ $plex_count -lt 3 ]; then
  echo "[$(date)]  INFO -- : Plex not running! ($(plex_count)) Restarting."
  . kill_plex.sh
fi
echo "[$(date)]  INFO -- : Plex is ok, moving on..."
