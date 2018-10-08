#!/bin/bash

[[ $(pgrep -fu $(whoami) 'JackettConsole.exe') ]] || ./start_jackett.sh
