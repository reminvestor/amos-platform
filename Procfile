web: bundle exec puma -C config/puma_heroku.rb
worker: bundle exec rake solid_queue:start PROCESS_NAME=ContactProcessor-${DYNO:-$(hostname)}
clock: bundle exec clockwork clock.rb
release: bundle exec rails db:migrate 