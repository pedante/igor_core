FROM nextcloud:fpm-alpine

# Install system dependencies for Previews & Metadata
RUN apk update && \
    apk add --no-cache \
        ffmpeg \
        imagemagick \
        ghostscript \
        perl-image-exiftool \
        libzip-dev \
        libpng-dev \
        jpeg-dev \
        freetype-dev \
        gnu-libiconv

# Enable SVG/PDF support in ImageMagick
RUN sed -i 's/policy domain="coder" rights="none" pattern="PDF"/policy domain="coder" rights="read|write" pattern="PDF"/' /etc/ImageMagick-7/policy.xml

# Fix user ID to match your host ID (1004)
RUN deluser www-data && \
    addgroup -g 1004 -S www-data && \
    adduser -u 1004 -D -S -G www-data www-data

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
