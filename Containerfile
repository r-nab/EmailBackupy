FROM python:3.11-slim

LABEL org.opencontainers.image.source=https://github.com/r-nab/EmailBackupy
LABEL org.opencontainers.image.description="Email backup tool that downloads emails and attachments from IMAP servers"
LABEL org.opencontainers.image.licenses=MIT

# Unraid specific labels
LABEL maintainer="r-nab"
LABEL net.unraid.docker.managed="docker"
LABEL net.unraid.docker.webui=""

WORKDIR /app

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    tzdata \
    qpdf && \
    ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime && \
    echo "Asia/Kolkata" > /etc/timezone && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy requirements first to leverage Docker cache
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Create default directories for mounting
RUN mkdir -p /data/eml /data/attachments /app/configs

# Copy application code
COPY . .

# Set default config path and data directories
ENV CONFIG_PATH=/app/configs/config.yaml
ENV EML_DIR=/data/eml
ENV ATTACHMENTS_DIR=/data/attachments

# Setup for Unraid compatibility
ARG PUID=99
ARG PGID=100
ENV PUID=${PUID}
ENV PGID=${PGID}
ENV UMASK=000

# Run as non-root user with configurable UID/GID
RUN groupadd -g ${PUID} appgroup && \
    useradd -u ${PGID} -g appgroup -m appuser && \
    mkdir -p /etc/cont-init.d && \
    chown -R appuser:appgroup /app /data

# Create entrypoint script for user modification
RUN echo '#!/bin/sh\n\
PUID=${PUID:-99}\n\
PGID=${PGID:-100}\n\
UMASK=${UMASK:-000}\n\
\n\
if [ ! $(getent group appgroup) ]; then\n\
    groupadd -g $PGID appgroup\n\
fi\n\
\n\
if [ ! $(getent passwd appuser) ]; then\n\
    useradd -u $PUID -g appgroup -m appuser\n\
fi\n\
\n\
echo "-----------------------------"\n\
echo "GID/UID"\n\
echo "-----------------------------"\n\
echo "User uid:    $(id -u appuser)"\n\
echo "User gid:    $(id -g appgroup)"\n\
echo "-----------------------------"\n\
\n\
chown -R appuser:appgroup /app /data\n\
umask $UMASK\n\
\n\
exec su-exec appuser python /app/app.py\n\
' > /usr/local/bin/entrypoint.sh && \
    chmod +x /usr/local/bin/entrypoint.sh

# Install su-exec for dropping privileges
RUN apt-get update && \
    apt-get install -y --no-install-recommends su-exec && \
    rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Run script
CMD ["python", "app.py"]
