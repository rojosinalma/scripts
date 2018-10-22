kill "$(pgrep -fu "$(whoami)" "JackettConsole.exe")"

sleep 2

screen -dmS jackett && screen -S jackett -p 0 -X stuff "export TMPDIR=$HOME/tmp; ~/bin/mono --debug ~/.jackett/JackettConsole.exe^M"
