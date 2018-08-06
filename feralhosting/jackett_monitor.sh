#!/bin/bash
thedate=$(date +"%m/%d/%Y %H:%M:%S")
echo "${thedate} -- Running Jackett Process Check!"

jackettproc=`pgrep -fu "$(whoami)" "SCREEN -dmS jackett"`

if [ "${jackettproc:-null}" = null ]; then
  echo "${thedate} ---- Starting Jackett"
  screen -dmS jackett mono --debug ~/Jackett/JackettConsole.exe
else
  echo "${thedate} ---- Didn't start Jackett"
fi
