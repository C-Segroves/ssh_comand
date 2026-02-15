# Use a slim Python base image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Copy application files
COPY app.py .
COPY templates/ templates/

# Install dependencies
RUN pip install --no-cache-dir \
    flask \
    flask-socketio \
    paramiko

# Expose port
EXPOSE 5000

# Run the application
CMD ["python", "app.py"]