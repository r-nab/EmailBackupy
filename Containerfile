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
ENV PUID=99
ENV PGID=100
ENV UMASK=000

# Run as non-root user with configurable UID/GID
RUN groupadd -g ${PGID} appgroup && \
    useradd -u ${PUID} -g appgroup -m appuser && \
    chown -R appuser:appgroup /app /data

# Create s6 script for user modification
RUN mkdir -p /etc/cont-init.d
COPY <<'EOF' /etc/cont-init.d/10-adduser
#!/bin/bash
PUID=${PUID:-99}
PGID=${PGID:-100}
UMASK=${UMASK:-000}

groupmod -o -g "$PGID" appgroup
usermod -o -u "$PUID" appuser

echo "
-----------------------------
GID/UID
-----------------------------
User uid:    $(id -u appuser)
User gid:    $(id -g appuser)
-----------------------------
"
chown -R appuser:appgroup /app /data
umask $UMASK
EOF

RUN chmod +x /etc/cont-init.d/10-adduser

USER appuser

# Run script
CMD ["python", "app.py"]
