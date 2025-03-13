FROM composer:2 AS composer

FROM php:8.4-fpm-bookworm AS base

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends libicu-dev \
      linux-libc-dev  \
      libsqlite3-0 \
      libnghttp2-14 libc-bin curl autoconf dpkg-dev dpkg file g++ gcc libc-dev make pkg-config re2c libxml2-dev \
      zlib1g-dev libzip-dev unzip \
      "$(debsecan --suite bookworm --format packages --only-fixed)" \
    && pecl install \
      apcu \
    && docker-php-ext-enable \
      apcu \
    && docker-php-ext-configure intl \
    && docker-php-ext-install -j "$(nproc)" \
      intl \
      opcache \
      bcmath \
      zip \
    && apt-get remove -y --purge debsecan \
    && apt-get clean \
    && rm -rf "/var/lib/apt/lists/*"

RUN mkdir /var/www/var && \
    chown www-data:www-data /var/www/var

FROM base AS extension-new-relic

ENV NEWRELIC_VERSION=11.6.0.19

# this directory needs to exist for the copy command in the production stage to not fail
RUN mkdir -p /extension

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
RUN set -eux ; \
    curl \
      --silent \
      --fail \
      --location \
      --user-agent Dockerfile \
      --url "https://download.newrelic.com/php_agent/archive/$NEWRELIC_VERSION/newrelic-php5-$NEWRELIC_VERSION-linux.tar.gz" \
      --output - \
      | tar --directory /tmp --extract --gzip --file - ; \
    export NR_INSTALL_USE_CP_NOT_LN=1 NR_INSTALL_SILENT=1 ; \
    "/tmp/newrelic-php5-$NEWRELIC_VERSION-linux/newrelic-install" install ; \
    cp "$(php -r "echo ini_get ('extension_dir');")/newrelic.so" /extension/ ; \
    rm -rf /tmp/*

FROM base AS production

ENV STD_OUT="/proc/1/fd/1"
ENV STD_ERR="/proc/1/fd/2"

RUN pecl clear cache

# Use the default production configuration
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

WORKDIR /var/www
RUN mkdir /var/www/vendor && chown www-data:www-data /var/www/vendor

USER www-data

COPY --chown=www-data:www-data HelloQuery.php HelloQuery.php
COPY --chown=www-data:www-data index.php index.php
COPY --chown=www-data:www-data composer.json composer.json
COPY --chown=www-data:www-data composer.lock composer.lock

COPY --chown=www-data:www-data --from=composer /usr/bin/composer /usr/bin/composer

COPY --from=extension-new-relic /extension /extension/newrelic
COPY --from=extension-new-relic /usr/bin/newrelic-daemon /usr/bin/newrelic-daemon
COPY newrelic.ini /usr/local/etc/php/conf.d/newrelic.ini

RUN  composer install --prefer-dist --no-dev --no-progress --classmap-authoritative --optimize-autoloader

USER root

RUN rm -rf \
    composer.lock \
    /usr/bin/composer

RUN cp /extension/newrelic/newrelic.so "$(php -r "echo ini_get ('extension_dir');")"/ ; \
    docker-php-ext-enable newrelic ; \
    rm -rf /extension ;

USER www-data
