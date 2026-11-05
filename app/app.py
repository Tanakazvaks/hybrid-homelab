"""homelab-web: tiny JSON web service used to demo the CI/CD pipeline."""
import json
import os
import socket
from http.server import BaseHTTPRequestHandler, HTTPServer

VERSION = os.environ.get("APP_VERSION", "dev")


def build_response(path):
    """Return (status_code, body) for a request path. Kept separate so it can be unit tested."""
    if path == "/health":
        return 200, {"status": "ok"}
    if path == "/":
        return 200, {"app": "homelab-web", "version": VERSION, "pod": socket.gethostname()}
    return 404, {"error": "not found"}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        code, body = build_response(self.path)
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        pass  # keep pod logs quiet (health checks hit every few seconds)


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8001), Handler).serve_forever()
