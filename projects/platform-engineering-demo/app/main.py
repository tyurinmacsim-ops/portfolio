import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest


REQUEST_COUNT = Counter(
    "demo_api_http_requests_total",
    "Total number of HTTP requests handled by demo-api",
    ["method", "path", "status_code"],
)

REQUEST_LATENCY = Histogram(
    "demo_api_http_request_duration_seconds",
    "Request latency for demo-api",
    ["method", "path"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0),
)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    yield


app = FastAPI(title="demo-api", version="1.0.0", lifespan=lifespan)


@app.middleware("http")
async def metrics_middleware(request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    elapsed = time.perf_counter() - start
    path = request.url.path
    REQUEST_COUNT.labels(
        method=request.method,
        path=path,
        status_code=response.status_code,
    ).inc()
    REQUEST_LATENCY.labels(method=request.method, path=path).observe(elapsed)
    return response


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    return {"ready": True}


@app.get("/api/v1/ping")
def ping():
    return {"message": "pong"}


@app.get("/api/v1/orders/{order_id}")
def get_order(order_id: int):
    simulated_latency = min(0.01 * (order_id % 5 + 1), 0.05)
    time.sleep(simulated_latency)
    return {"order_id": order_id, "state": "processed"}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
