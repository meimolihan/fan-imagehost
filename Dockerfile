# fan-imagehost - 简单图床
# 单容器部署：Apache + PHP 8.0，内置图床所需扩展。
#
# 说明：PHP 8.0 的官方镜像基于 Debian bullseye，而 bullseye 已于 2026-08 结束 LTS，
# 官方源不再提供 bullseye 软件包。为保证构建长期可复现，此处将 apt 源指向
# Debian 归档站 archive.debian.org（bullseye 的最终快照）。
FROM php:8.0-apache

LABEL org.opencontainers.image.title="fan-imagehost" \
      org.opencontainers.image.description="fan-imagehost - 简单图床（无数据库 PHP 图床）" \
      org.opencontainers.image.url="https://github.com/meimolihan/fan-imagehost" \
      org.opencontainers.image.source="https://github.com/meimolihan/fan-imagehost"

# 安装 PHP 扩展（gd/zip/exif；curl/mbstring/fileinfo/iconv/openssl 基础镜像已内置）
RUN set -eux; \
    printf 'deb http://archive.debian.org/debian bullseye main\ndeb http://archive.debian.org/debian-security bullseye-security main\n' > /etc/apt/sources.list; \
    printf 'Acquire::Check-Valid-Until "false";\nAcquire::AllowInsecureRepositories "true";\n' > /etc/apt/apt.conf.d/99archive; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libpng-dev \
        libjpeg-dev \
        libfreetype6-dev \
        libwebp-dev \
        libzip-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(nproc)" gd zip exif; \
    a2enmod rewrite headers expires; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# 图床运行所需的 php.ini 调整
RUN { \
        echo 'upload_max_filesize = 64M'; \
        echo 'post_max_size = 64M'; \
        echo 'memory_limit = 512M'; \
        echo 'max_execution_time = 300'; \
        echo 'date.timezone = Asia/Shanghai'; \
    } > /usr/local/etc/php/conf.d/fan-imagehost.ini

RUN echo 'ServerName localhost' >> /etc/apache2/apache2.conf

WORKDIR /var/www/html

# 复制程序文件（含 config/ 与 i/ 的默认副本，用于容器首次启动初始化数据卷）
COPY . /var/www/html/

COPY docker/entrypoint.sh /usr/local/bin/fan-imagehost-entrypoint
RUN chmod +x /usr/local/bin/fan-imagehost-entrypoint \
    && chown -R www-data:www-data /var/www/html

# 数据目录（config + 上传图片），建议挂载持久化
ENV FAN_IMAGEHOST_DATA_DIR=/var/lib/fan-imagehost
VOLUME ["/var/lib/fan-imagehost"]

EXPOSE 80

ENTRYPOINT ["fan-imagehost-entrypoint"]
CMD ["apache2-foreground"]
