#!/bin/bash

plex_count=$(ps ux | fgrep "/Plex Media Server" | wc -l)

if [ $plex_count -lt 3 ]; then
  . kill_plex.sh
fi
