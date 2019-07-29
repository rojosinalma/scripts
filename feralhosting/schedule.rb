set :job_template, nil
set :chronic_options, hours24: true
set :output, "$HOME/cron.log"

every 1.day, at: '22:00' do
  command ". $HOME/.profile; ruby $HOME/scripts/feralhosting/plex_update.rb"
end

every 30.minutes do
  command ". %HOME/.profile; $HOME/scripts/feralhosting/plex_check.sh"
end
