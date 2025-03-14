ARG PHP_IMAGE=docker.io/library/php
ARG PHP_IMAGE_TAG=8.4.5-fpm-bookworm

FROM docker.io/library/composer:2 as composer

FROM ${PHP_IMAGE}:${PHP_IMAGE_TAG} as extension-xdebug

RUN apt-get update \
    && apt-get install -y --no-install-recommends autoconf g++ make \
    && pecl install xdebug  \
    && mkdir -p /extension \
    && cp "$(php -r "echo ini_get ('extension_dir');")/xdebug.so" /extension/

FROM ${PHP_IMAGE}:${PHP_IMAGE_TAG} as extension-redis

RUN apt-get update \
    && apt-get install -y --no-install-recommends autoconf g++ make \
    && pecl install redis \
    && mkdir -p /extension \
    && cp "$(php -r "echo ini_get ('extension_dir');")/redis.so" /extension/

FROM ${PHP_IMAGE}:${PHP_IMAGE_TAG} as extension-opcache

RUN docker-php-ext-install opcache \
    && mkdir -p /extension \
    && cp "$(php -r "echo ini_get ('extension_dir');")/opcache.so" /extension/

FROM ${PHP_IMAGE}:${PHP_IMAGE_TAG} as extension-bcmath

RUN docker-php-ext-install bcmath \
    && mkdir -p /extension \
    && cp "$(php -r "echo ini_get ('extension_dir');")/bcmath.so" /extension/

FROM ${PHP_IMAGE}:${PHP_IMAGE_TAG} as extension-pdo_mysql

RUN docker-php-ext-install pdo_mysql \
    && mkdir -p /extension \
    && cp "$(php -r "echo ini_get ('extension_dir');")/pdo_mysql.so" /extension/

FROM ${PHP_IMAGE}:${PHP_IMAGE_TAG} as extension-intl

RUN apt-get update \
    && apt-get install -y --no-install-recommends libicu-dev \
    && docker-php-ext-install intl \
    && mkdir -p /extension \
    && cp "$(php -r "echo ini_get ('extension_dir');")/intl.so" /extension/

FROM ${PHP_IMAGE}:${PHP_IMAGE_TAG} as extension-new-relic

ENV NEWRELIC_VERSION=11.6.0.19

# this directory needs to exist for the copy command in the production stage to not fail
RUN mkdir -p /extension

RUN set -eux && \
    curl \
      --silent \
      --fail \
      --location \
      --user-agent Dockerfile \
      --url "https://download.newrelic.com/php_agent/archive/$NEWRELIC_VERSION/newrelic-php5-$NEWRELIC_VERSION-linux.tar.gz" \
      --output - \
      | tar --directory /tmp --extract --gzip --file - && \
    export NR_INSTALL_USE_CP_NOT_LN=1 NR_INSTALL_SILENT=1 && \
    /tmp/newrelic-php5-*/newrelic-install install && \
    cp "$(php -r "echo ini_get ('extension_dir');")/newrelic.so" /extension/ && \
    rm -rf /tmp/* ;

FROM ${PHP_IMAGE}:${PHP_IMAGE_TAG} as packages

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      git \
      libzip-dev \
      unzip \
    && docker-php-ext-install zip

COPY composer.* .

ENV COMPOSER_CACHE_DIR=/tmp/composer
ENV COMPOSER_ALLOW_SUPERUSER=1

RUN --mount=type=bind,from=composer,source=/usr/bin/composer,target=/usr/bin/composer \
    --mount=type=cache,target=/tmp/composer \
    COMPOSER_VENDOR_DIR=/app/production-vendor composer install --prefer-dist --no-progress --no-autoloader --ignore-platform-reqs \
    && COMPOSER_VENDOR_DIR=/app/development-vendor composer install --prefer-dist --no-progress --no-autoloader --ignore-platform-reqs \
    && rm composer.*

FROM ${PHP_IMAGE}:${PHP_IMAGE_TAG} as production

ENV TZ="Europe/Amsterdam"
ENV STD_OUT="/proc/1/fd/1"
ENV STD_ERR="/proc/1/fd/2"
ENV APP_ENV="prod"

RUN apt-get update \
    && apt-get install -y --no-install-recommends debsecan \
    && apt-get install -y --no-install-recommends \
      tzdata \
      libicu72 \
    && apt-get install -y --no-install-recommends $(debsecan --suite bookworm --format packages --only-fixed) \
    && apt-get remove -y --purge debsecan \
    && apt-get clean \
    && rm -rf "/var/lib/apt/lists/*"
RUN printf '[Date]\ndate.timezone="%s"\n', $TZ > /usr/local/etc/php/conf.d/tzone.ini

# Use the default production configuration
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

RUN --mount=type=bind,from=extension-opcache,source=/extension,target=/extension/opcache \
    --mount=type=bind,from=extension-pdo_mysql,source=/extension,target=/extension/pdo_mysql \
    --mount=type=bind,from=extension-bcmath,source=/extension,target=/extension/bcmath \
    --mount=type=bind,from=extension-intl,source=/extension,target=/extension/intl \
    cp /extension/opcache/opcache.so $(php -r "echo ini_get ('extension_dir');")/ && \
    cp /extension/bcmath/bcmath.so $(php -r "echo ini_get ('extension_dir');")/ && \
    cp /extension/pdo_mysql/pdo_mysql.so $(php -r "echo ini_get ('extension_dir');")/ && \
    cp /extension/intl/intl.so $(php -r "echo ini_get ('extension_dir');")/ && \
    docker-php-ext-enable opcache && \
    docker-php-ext-enable pdo_mysql && \
    docker-php-ext-enable bcmath && \
    docker-php-ext-enable intl

RUN --mount=type=bind,from=extension-new-relic,source=/extension,target=/extension/newrelic \
    if [ -f /extension/newrelic/newrelic.so ]; then \
      cp /extension/newrelic/newrelic.so $(php -r "echo ini_get ('extension_dir');")/ && \
      docker-php-ext-enable newrelic ; \
    fi

COPY --from=extension-redis /extension /extension/redis

RUN cp /extension/redis/redis.so $(php -r "echo ini_get ('extension_dir');")/ && \
    docker-php-ext-enable redis && \
    rm -rf /extension

COPY docker/php-extra.ini /usr/local/etc/php/conf.d/extra.ini 
USER root

RUN chown www-data:www-data /var/www

USER www-data

WORKDIR /var/www

COPY --from=packages --chown=www-data:www-data /app/production-vendor /var/www/vendor

# digicert to make ssl connection to azure mysql
RUN mkdir -p var/certs \
  && curl -fsS https://cacerts.digicert.com/DigiCertGlobalRootCA.crt.pem > var/certs/DigiCertGlobalRootCA.crt.pem

COPY --chown=www-data:www-data bin bin
COPY --chown=www-data:www-data config config
COPY --chown=www-data:www-data public public
COPY --chown=www-data:www-data src src

COPY --chown=www-data:www-data composer.json .env ./

RUN --mount=type=bind,source=composer.json,target=composer.json \
    --mount=type=bind,from=composer,source=/usr/bin/composer,target=/usr/bin/composer \
    composer check-platform-reqs && \
    composer dump-autoload --classmap-authoritative && \
    php bin/console cache:warm

USER www-data

FROM production as development

ENV APP_ENV="dev"

USER root

COPY --from=composer /usr/bin/composer /usr/bin/composer

COPY --from=extension-xdebug /extension /extension/xdebug

RUN cp /extension/xdebug/xdebug.so $(php -r "echo ini_get ('extension_dir');")/ && \
    docker-php-ext-enable xdebug && \
    rm -rf /extension

USER www-data

COPY --from=packages --chown=www-data:www-data /app/development-vendor /var/www/vendor

COPY --chown=www-data:www-data composer.* .env .php-cs-fixer.php phpstan* phpunit* ./

RUN composer dump-autoload

FROM production as final

VOLUME ["/var/www"]