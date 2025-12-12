FROM python:3.12-slim

WORKDIR /app

# Install deps first for better layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source
COPY . .

EXPOSE 5000

# Create and use a non-root user
RUN useradd -m appuser
USER appuser

# Run with gunicorn for production-style serving
CMD ["gunicorn", "-b", "0.0.0.0:5000", "app:app"]
