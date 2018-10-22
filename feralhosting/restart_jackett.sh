screen -X -S jackett kill
sleep 2
screen -dmS jackett && screen -S jackett -p 0 -X stuff "export TMPDIR=$HOME/tmp; ~/bin/mono --debug ~/Jackett/JackettConsole.exe^M"
