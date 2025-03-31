web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq -e ${RAILS_ENV:-production} -C config/sidekiq.yml || echo "Sidekiq not available, skipping worker process"
clock: bundle exec clockwork clock.rb
release: bundle exec rails db:migrate 