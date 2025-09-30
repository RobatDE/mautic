# Production Dockerfile for Mautic 6.0.2 (web-only)
# - Based on the KISS Dockerfile patterns, but without any database installation
# - Installs Apache2 + PHP-FPM 8.3 + required PHP extensions + mariadb-client (for mariadb-check)
# - Bakes Mautic 6.0.2 into the image
# - Default MAUTIC_RUN_INSTALLER=false (installer not triggered by default)

ARG BASE_OS=debian
ARG OS_VERSION=12-slim
FROM ${BASE_OS}:${OS_VERSION}

LABEL org.opencontainers.image.source="https://github.com/expona-ai/mautic" \
      org.opencontainers.image.title="Mautic Web Service" \
      org.opencontainers.image.description="Production web-only image for Mautic 6.0.2 (Apache + PHP-FPM)"

ARG DEBIAN_FRONTEND=noninteractive

# Versions
ARG PHP_VER=8.3
ARG MAUTIC_VER=6.0.2

# Runtime defaults
ENV MAUTIC_RUN_INSTALLER=false \
    MAUTIC_DB_DRIVER=pdo_mysql \
    MAUTIC_DB_PORT=3306

###--------------------------------###
###  Prepare and add repositories   ###
###--------------------------------###
RUN apt update && apt upgrade -y && \
    apt-get install -y wget curl gnupg2 lsb-release ca-certificates apt-transport-https \
                       software-properties-common ssl-cert unzip nano supervisor imagemagick graphicsmagick && \
    rm -rf /var/lib/apt/lists/*

# PHP repository
RUN wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg && \
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list

# Update and install stack components (web-only) + mariadb-client for mariadb-check
RUN apt update && apt upgrade -y && \
    apt install -y apache2 libapache2-mod-fcgid \
                   php-bcmath php-curl php-igbinary php-intl php-mbstring php-xml \
                   php${PHP_VER}-fpm php${PHP_VER}-imap php${PHP_VER}-bcmath php${PHP_VER}-bz2 php${PHP_VER}-cli \
                   php${PHP_VER}-common php${PHP_VER}-curl php${PHP_VER}-gd php${PHP_VER}-gmp php${PHP_VER}-igbinary \
                   php${PHP_VER}-intl php${PHP_VER}-mbstring php${PHP_VER}-mysql php${PHP_VER}-readline php${PHP_VER}-phpdbg \
                   php${PHP_VER}-xml php${PHP_VER}-zip php${PHP_VER}-soap php${PHP_VER}-xmlrpc php${PHP_VER}-tidy \
                   mariadb-client && \
    update-alternatives --set php /usr/bin/php${PHP_VER}

# Enable Apache modules and PHP-FPM conf
RUN a2enmod proxy_fcgi setenvif rewrite expires headers http2 ssl actions alias && \
    a2enconf php8.3-fpm

###--------------------------------###
###     Configuration and tweaks    ###
###--------------------------------###
# Note: For production determinism, consider vendoring these configs locally.
RUN wget -O  /etc/apache2/apache2.conf https://raw.github.com/Martech-WorkShop/toolBelt/Prod/Mautic/conf/apache/apache2.conf && \
    wget -O /etc/apache2/mods-enabled/mpm_event.conf https://raw.github.com/Martech-WorkShop/toolBelt/Prod/Mautic/conf/apache/mpm_event.conf && \
    wget -O /etc/apache2/sites-available/000-default.conf https://raw.github.com/Martech-WorkShop/toolBelt/Prod/Mautic/conf/apache/000-default-fpm-8.3.conf && \
    wget -O /etc/php/8.3/fpm/pool.d/www.conf https://raw.github.com/Martech-WorkShop/toolBelt/Prod/Mautic/conf/fpm/www.conf-8.3 && \
    wget -O /etc/php/8.3/fpm/php.ini https://raw.github.com/Martech-WorkShop/toolBelt/Prod/Mautic/conf/php/php.ini && \
    cp /etc/php/8.3/fpm/php.ini /etc/php/8.3/cli/php.ini

# Ensure PHP-FPM socket path exists
RUN mkdir -p /run/php && touch /run/php/php8.3-fpm.sock && chown -R www-data:www-data /run/php

EXPOSE 80

###--------------------------------###
###   Download and install Mautic   ###
###--------------------------------###
WORKDIR /var/www/html
RUN wget https://github.com/mautic/mautic/releases/download/${MAUTIC_VER}/${MAUTIC_VER}.zip && \
    unzip ${MAUTIC_VER}.zip && \
    rm ${MAUTIC_VER}.zip && \
    chown -R www-data:www-data /var/www/html && \
    find /var/www/html -type d -exec chmod 755 {} + && \
    find /var/www/html -type f -exec chmod 644 {} +

# Copy helper scripts
COPY scripts/install_mautic.sh /usr/local/bin/install_mautic.sh
COPY scripts/check_mautic_install.sh /usr/local/bin/check_mautic_install.sh
COPY scripts/entrypoint-web.sh /entrypoint-web.sh
COPY scripts/local.php.template /usr/local/share/mautic/local.php.template
RUN chmod +x /usr/local/bin/install_mautic.sh /usr/local/bin/check_mautic_install.sh /entrypoint-web.sh

# Mirror full scripts directory under /home/scripts/
COPY scripts/ /home/scripts/
RUN chmod +x /home/scripts/*.sh || true

# Place the 6.0.2 SQL dump alongside scripts for operational use
COPY KISSMauticDKR/assets/6.0.2/mautic-6.0.2.sql /home/scripts/mautic-6.0.2.sql
RUN chmod 644 /home/scripts/mautic-6.0.2.sql || true

# Optional volumes for persistence when not mounting /var/www/html entirely
VOLUME /var/www/html/app/config
VOLUME /var/www/html/var/logs
VOLUME /var/www/html/media

# Lightweight healthcheck (web-only)
HEALTHCHECK --interval=60s --timeout=20s --retries=3 CMD \
  service apache2 status && \
  service php8.3-fpm status && \
  curl -f http://localhost || exit 1

CMD ["/entrypoint-web.sh"]
