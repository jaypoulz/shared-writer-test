FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Copy application code
COPY app.py /app/

# Make the script executable
RUN chmod +x /app/app.py

# Create mount point
RUN mkdir -p /mnt/shared

# Run the application with unbuffered output
CMD ["python3", "-u", "/app/app.py"]
