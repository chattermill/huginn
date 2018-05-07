FROM ruby:2.3.1

ARG RAILS_ENV
ENV RAILS_ENV production
ENV BACKGROUND_JOB_PROCESSOR sidekiq
ENV DATABASE_ADAPTER postgresql
ENV ADDITIONAL_GEMS ""
ENV LC_ALL C.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV APP_SECRET_TOKEN "docker-secret"

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    libssl-dev \
    software-properties-common \
    wget curl git \
  && apt-get install -y postgresql-client \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY . .

RUN gem install bundler \
  && bundle install --path /bundle

RUN bundle exec rake assets:precompile

EXPOSE 80

CMD bundle exec unicorn
