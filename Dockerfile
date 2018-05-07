FROM ruby:2.3.1:latest

ARG RAILS_ENV
ENV RAILS_ENV production

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
