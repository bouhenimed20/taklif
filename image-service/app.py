import os
from flask import Flask, request, jsonify
import boto3
from botocore.exceptions import ClientError
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)

# ----- Env (aligned with k8s image-secrets) -----
S3_ENDPOINT = os.getenv("S3_ENDPOINT", "http://minio.prod-storage.svc.cluster.local:9000")
S3_ACCESS_KEY = os.getenv("S3_ACCESS_KEY", "minioadmin")
S3_SECRET_KEY = os.getenv("S3_SECRET_KEY", "minioadmin")
S3_BUCKET = os.getenv("S3_BUCKET", "images")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

s3_client = boto3.client(
    "s3",
    endpoint_url=S3_ENDPOINT,
    aws_access_key_id=S3_ACCESS_KEY,
    aws_secret_access_key=S3_SECRET_KEY,
    region_name=AWS_REGION,
)

# ----- Prometheus metrics -----
REQUEST_COUNT = Counter(
    "image_service_requests_total",
    "Total requests to image-service",
    ["method", "endpoint", "status"]
)

REQUEST_LATENCY = Histogram(
    "image_service_request_latency_seconds",
    "Request latency for image-service",
    ["endpoint"]
)

@app.before_request
def _start_timer():
    request._prom_start_time = REQUEST_LATENCY.labels(request.path).time()

@app.after_request
def _record_metrics(response):
    try:
        if hasattr(request, "_prom_start_time"):
            request._prom_start_time.observe_duration()
        REQUEST_COUNT.labels(request.method, request.path, response.status_code).inc()
    except Exception:
        pass
    return response

@app.get("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}

# ----- Health endpoints -----
@app.get("/health")
def health():
    return jsonify({"status": "ok", "service": "image-service"})

@app.get("/health/live")
def health_live():
    return jsonify({"status": "live"})

@app.get("/health/ready")
def health_ready():
    # Optional: check bucket exists
    try:
        s3_client.head_bucket(Bucket=S3_BUCKET)
        return jsonify({"status": "ready"})
    except Exception as e:
        return jsonify({"status": "not-ready", "error": str(e)}), 503

# ----- Routes -----
@app.post("/images/upload")
def upload_image():
    try:
        if "file" not in request.files:
            return jsonify({"error": "No file provided"}), 400

        file = request.files["file"]
        if file.filename == "":
            return jsonify({"error": "Empty filename"}), 400

        key = f"uploads/{file.filename}"

        s3_client.upload_fileobj(
            file,
            S3_BUCKET,
            key,
            ExtraArgs={"ContentType": file.content_type},
        )

        return jsonify({
            "message": "Upload successful",
            "key": key,
            "bucket": S3_BUCKET
        }), 201

    except ClientError as e:
        return jsonify({"error": str(e)}), 500

@app.get("/images/<path:image_id>")
def get_image(image_id):
    try:
        response = s3_client.get_object(Bucket=S3_BUCKET, Key=image_id)
        return jsonify({
            "key": image_id,
            "size": response["ContentLength"],
            "content_type": response["ContentType"],
        })
    except s3_client.exceptions.NoSuchKey:
        return jsonify({"error": "Image not found"}), 404
    except ClientError as e:
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=False)
