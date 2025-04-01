web: bundle exec puma -C config/puma_heroku.rb
worker: bundle exec rails runner "Solid::Queue::Process.supervise(dispatcher_count: 2, dispatcher_opts: { concurrency: 5 })" || echo "Solid::Queue not available, skipping worker process"
clock: bundle exec clockwork clock.rb
release: bundle exec rails db:migrate 