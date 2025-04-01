web: bundle exec puma -C config/puma_heroku.rb
worker: bundle exec rake solid_queue:start["ContactsProcessor"]
clock: bundle exec clockwork clock.rb
release: bundle exec rails db:migrate 