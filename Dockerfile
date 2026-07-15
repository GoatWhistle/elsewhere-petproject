FROM ruby:3.3.6-slim

RUN apt-get update -qq && apt-get install --no-install-recommends -y build-essential libpq-dev postgresql-client curl git && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY . .
ENTRYPOINT ["./bin/docker-entrypoint"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
