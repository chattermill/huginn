FROM ruby:2.3.1

ARG RAILS_ENV
ENV RAILS_ENV production
ENV BACKGROUND_JOB_PROCESSOR sidekiq
ENV DATABASE_ADAPTER postgresql
ENV ADDITIONAL_GEMS

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
