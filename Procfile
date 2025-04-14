web: bundle exec puma -C config/puma_heroku.rb
worker: bin/solid_queue
clock: bundle exec clockwork clock.rb
release: bundle exec rails db:migrate 