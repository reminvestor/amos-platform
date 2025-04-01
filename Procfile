web: bundle exec puma -C config/puma_heroku.rb
worker: bundle exec rails runner "Solid::Queue::Process.supervise(name: 'ContactsProcessor', dispatcher_count: 2, dispatcher_opts: { concurrency: 5 })"
clock: bundle exec clockwork clock.rb
release: bundle exec rails db:migrate 