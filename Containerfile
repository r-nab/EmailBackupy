FROM python:3.11-slim

LABEL org.opencontainers.image.source=https://github.com/r-nab/EmailBackupy
LABEL org.opencontainers.image.description="Email backup tool that downloads emails and attachments from IMAP servers"
LABEL org.opencontainers.image.licenses=MIT

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
RUN mkdir -p /data/eml /data/attachments

# Copy application code
COPY . .

# Set default config path and data directories
ENV CONFIG_PATH=/app/config.yaml
ENV EML_DIR=/data/eml
ENV ATTACHMENTS_DIR=/data/attachments

# Run as non-root user
RUN useradd -m appuser && \
    chown -R appuser:appuser /app /data

USER appuser

# Run script
CMD ["python", "app.py"]
