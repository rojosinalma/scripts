kill "$(pgrep -fu "$(whoami)" "JackettConsole.exe")"

sleep 2

screen -dmS jackett mono --debug ~/Jackett/JackettConsole.exe && echo -e "\nhttp://$(hostname -f):$(sed -rn 's|(.*)"Port": (.*),|\2|p' ~/.config/Jackett/ServerConfig.json)"
