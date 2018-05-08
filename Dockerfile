FROM ruby:2.5.1

ARG RAILS_ENV
ENV RAILS_ENV production
ENV BACKGROUND_JOB_PROCESSOR sidekiq
ENV DATABASE_ADAPTER postgresql
ENV ADDITIONAL_GEMS ""
ENV LC_ALL C.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV APP_SECRET_TOKEN "docker-secret"
ENV PHANTOM_JS phantomjs-2.1.1-linux-x86_64

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    libssl-dev \
    software-properties-common \
    wget curl git \
    build-essential chrpath libssl-dev libxft-dev -y \
    libfreetype6 libfreetype6-dev -y \
    libfontconfig1 libfontconfig1-dev -y \
  && apt-get install -y postgresql-client \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN wget https://github.com/Medium/phantomjs/releases/download/v2.1.1/$PHANTOM_JS.tar.bz2
RUN tar xvjf $PHANTOM_JS.tar.bz2
RUN mv $PHANTOM_JS /usr/local/share
RUN ln -sf /usr/local/share/$PHANTOM_JS/bin/phantomjs /usr/local/bin
RUN phantomjs --version

COPY . .

RUN gem install bundler \
  && bundle config disable_checksum_validation true \
  && bundle install --path /bundle

RUN bundle exec rake assets:precompile

EXPOSE 80

CMD bundle exec unicorn
