echo "INFO -- : Stopping previous Jackett screen"
screen -X -S jackett kill
sleep 2

echo "INFO -- : Starting Jackett again"
screen -dmS jackett && screen -S jackett -p 0 -X stuff "export TMPDIR=$HOME/tmp; ~/bin/mono --debug ~/Jackett/JackettConsole.exe^M"
