FROM python:3.11-slim

WORKDIR /app

# Copy app code
COPY . .

# Install dependencies including qpdf (for pikepdf, if used)
RUN apt-get update && \
    apt-get install -y tzdata qpdf && \
    ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime && \
    echo "Asia/Kolkata" > /etc/timezone && \
    apt-get clean

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Create default directories for mounting
RUN mkdir -p /data/eml /data/attachments

# Run script
CMD ["python", "app.py"]
