#!/bin/bash

echo "INFO -- : Starting Ombi"
screen -dmS ombi "cd ~/opt/Ombi; ./Ombi --host http://*:13300"
