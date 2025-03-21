web: bin/rails server -p ${PORT:-5000} -e ${RAILS_ENV:-production}
worker: bundle exec sidekiq -e ${RAILS_ENV:-production} -C config/sidekiq.yml 