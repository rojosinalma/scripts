set :job_template, nil
set :chronic_options, hours24: true
set :output, "$HOME/cron_log.log"

every 1.day, at: '22:00' do
  command ". $HOME/.profile; ruby $HOME/scripts/feralhosting/plex_update.rb"
end

every 1.day, at: '3:00' do
  command ". $HOME/.profile; $HOME/scripts/feralhosting/restart_jackett.sh"
end
