from __future__ import annotations

import argparse
import concurrent.futures
import json
import time
import urllib.request


def request(url: str) -> float:
    started = time.perf_counter()
    with urllib.request.urlopen(url, timeout=5) as response:
        if response.status != 200 or json.load(response).get("status") != "ready":
            raise RuntimeError("readiness response was invalid")
    return time.perf_counter() - started


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://127.0.0.1:8000/api/v1/health/ready")
    parser.add_argument("--requests", type=int, default=200)
    parser.add_argument("--workers", type=int, default=20)
    args = parser.parse_args()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        durations = list(pool.map(request, [args.url] * args.requests))
    durations.sort()
    p95 = durations[int(len(durations) * 0.95) - 1]
    print(json.dumps({"requests": len(durations), "p95_ms": round(p95 * 1000, 2)}))
    if p95 > 1.0:
        raise SystemExit("p95 exceeded 1000 ms")


if __name__ == "__main__":
    main()
