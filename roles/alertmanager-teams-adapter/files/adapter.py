#!/usr/bin/env python3
"""AlertManager → Power Automate Workflow adapter.

Receives raw AlertManager webhook POSTs, converts each alert into an
Adaptive Card, wraps the cards in the TeamsWebhook trigger's expected
``{"type":"message","attachments":[...]}`` envelope, and forwards the
result to the configured Workflow URL. Plain stdlib only — runs on
``python:3-slim`` without pip installs.
"""
from __future__ import annotations

import json
import logging
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "8080"))
TIMEOUT = int(os.environ.get("TARGET_TIMEOUT", "15"))
TARGET_URL = os.environ.get("TARGET_URL", "").strip()

logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("am-teams-adapter")

if not TARGET_URL:
    log.error("TARGET_URL env var is required")
    sys.exit(2)


def build_adaptive_card(alert: dict) -> dict:
    status = (alert.get("status") or "unknown").upper()
    labels = alert.get("labels") or {}
    annotations = alert.get("annotations") or {}
    color = "attention" if alert.get("status") == "firing" else "good"
    facts = []
    for key in ("instance", "severity", "namespace", "job", "alertname"):
        val = labels.get(key)
        if val:
            facts.append({"title": key, "value": str(val)})
    if alert.get("startsAt"):
        facts.append({"title": "startsAt", "value": str(alert["startsAt"])})
    if alert.get("endsAt") and alert.get("status") == "resolved":
        facts.append({"title": "endsAt", "value": str(alert["endsAt"])})
    body = [
        {
            "type": "TextBlock",
            "size": "Large",
            "weight": "Bolder",
            "color": color,
            "text": f"{status}: {labels.get('alertname', '(no alertname)')}",
        },
    ]
    if facts:
        body.append({"type": "FactSet", "facts": facts})
    if annotations.get("summary"):
        body.append({
            "type": "TextBlock",
            "weight": "Bolder",
            "wrap": True,
            "text": str(annotations["summary"]),
        })
    if annotations.get("description"):
        body.append({
            "type": "TextBlock",
            "wrap": True,
            "text": str(annotations["description"]),
        })
    return {
        "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
        "type": "AdaptiveCard",
        "version": "1.4",
        "body": body,
    }


def forward(payload: dict) -> tuple[int, str]:
    body = json.dumps(payload).encode("utf-8")
    req = Request(
        TARGET_URL,
        data=body,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urlopen(req, timeout=TIMEOUT) as resp:
            return resp.status, resp.read().decode("utf-8", errors="replace")
    except HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", errors="replace")
    except URLError as exc:
        return 502, str(exc)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        log.info("%s - %s", self.client_address[0], fmt % args)

    def _respond(self, code: int, body: bytes = b"") -> None:
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path in ("/healthz", "/ready", "/"):
            self._respond(200, b"ok\n")
        else:
            self._respond(404)

    def do_POST(self) -> None:
        try:
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length) if length else b""
            data = json.loads(raw.decode("utf-8")) if raw else {}
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            log.warning("bad request body: %s", exc)
            self._respond(400, b"bad json\n")
            return

        alerts = data.get("alerts") or []
        if not alerts:
            log.info("no alerts in payload (status=%s) — 204", data.get("status"))
            self._respond(204)
            return

        attachments = [
            {
                "contentType": "application/vnd.microsoft.card.adaptive",
                "content": build_adaptive_card(alert),
            }
            for alert in alerts
        ]
        outbound = {"type": "message", "attachments": attachments}
        status, resp_body = forward(outbound)
        log.info(
            "forwarded %d alert(s) status=%s (upstream=%d)",
            len(alerts),
            data.get("status"),
            status,
        )
        if 200 <= status < 300:
            self._respond(202, b"accepted\n")
        else:
            log.warning("upstream rejected: %d %s", status, resp_body[:200])
            self._respond(502, f"upstream={status}\n".encode())


def main() -> None:
    server = ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler)
    log.info(
        "AlertManager → Teams adapter listening on :%d → %s",
        LISTEN_PORT,
        TARGET_URL[:48] + "..." if len(TARGET_URL) > 48 else TARGET_URL,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("shutting down")


if __name__ == "__main__":
    main()
