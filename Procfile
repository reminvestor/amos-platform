web: bundle exec puma -C config/puma_heroku.rb
worker: bundle exec rake solid_queue:work PROCESS_NAME=ContactProcessor-$(hostname)
clock: bundle exec clockwork clock.rb
release: bundle exec rails db:migrate 