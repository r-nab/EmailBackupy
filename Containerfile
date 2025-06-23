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
# Ensure config.yaml is in /app/configs/config.yaml, fallback to test.config.yaml if not found
RUN if [ -f ./config.yaml ]; then \
      cp ./config.yaml /app/configs/config.yaml; \
    elif [ -f ./test.config.yaml ]; then \
      cp ./test.config.yaml /app/configs/config.yaml; \
    fi

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
RUN cat <<'EOF' > /usr/local/bin/entrypoint.sh
#!/bin/sh
PUID=${PUID:-99}
PGID=${PGID:-100}
UMASK=${UMASK:-000}

if [ ! $(getent group appgroup) ]; then
    groupadd -g $PGID appgroup
fi

if [ ! $(getent passwd appuser) ]; then
    useradd -u $PUID -g appgroup -m appuser
fi

echo "-----------------------------"
echo "GID/UID"
echo "-----------------------------"
echo "User uid:    $(id -u appuser)"
echo "User gid:    $(id -g appgroup)"
echo "-----------------------------"

chown -R appuser:appgroup /app /data
umask $UMASK

exec gosu appuser uvicorn app:app --host 0.0.0.0 --port 8004
EOF
RUN chmod +x /usr/local/bin/entrypoint.sh

# Install gosu for dropping privileges
RUN apt-get update && \
    apt-get install -y --no-install-recommends gosu && \
    rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Run script
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8004"]
