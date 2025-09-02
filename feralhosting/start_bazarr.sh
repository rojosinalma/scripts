#!/bin/bash

echo "INFO -- : Starting Bazarr"
screen -dmS bazarr /bin/bash -c "source /media/sdd1/elfenars/.profile && LD_PRELOAD=/media/sdd1/elfenars/lib/libsqlite3.so.0 python ~/bazarr/bazarr.py -p 13200"
