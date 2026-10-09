"""Validated contact endpoint for the static BUHAJ DESIGN website."""

from __future__ import annotations

import base64
import binascii
import html
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request


MAX_BODY_BYTES = 20_000
EMAIL_PATTERN = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
SUPPORTED_LOCALES = {"pl", "en", "uk"}
RECAPTCHA_ACTION = "contact"


def _configured_values(name: str) -> set[str]:
    return {item.strip() for item in os.getenv(name, "").split(",") if item.strip()}


def _header(event: dict, name: str) -> str:
    headers = event.get("headers") or {}
    target = name.lower()
    for key, value in headers.items():
        if key.lower() == target:
            return str(value)
    return ""


def _response(status: int, code: str | None = None, message: str | None = None, origin: str = "") -> dict:
    headers = {
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "no-store",
    }
    if origin and origin in _configured_values("ALLOWED_ORIGINS"):
        headers.update({"Access-Control-Allow-Origin": origin, "Vary": "Origin"})

    body = {"ok": status == 200}
    if code:
        body["error"] = {"code": code, "message": message or "Request failed."}
    return {"statusCode": status, "headers": headers, "body": json.dumps(body, ensure_ascii=False)}


def _parse_body(event: dict) -> dict:
    raw = event.get("body") or ""
    if not isinstance(raw, str):
        raise ValueError("invalid body")
    if event.get("isBase64Encoded"):
        raw_bytes = base64.b64decode(raw, validate=True)
    else:
        raw_bytes = raw.encode("utf-8")
    if len(raw_bytes) > MAX_BODY_BYTES:
        raise OverflowError("body too large")
    payload = json.loads(raw_bytes.decode("utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("invalid body")
    return payload


def _text(payload: dict, key: str, maximum: int, required: bool = False) -> str:
    value = payload.get(key, "")
    if not isinstance(value, str):
        raise ValueError(key)
    value = value.strip()
    if (required and not value) or len(value) > maximum:
        raise ValueError(key)
    return value


def _validate(payload: dict) -> dict:
    if _text(payload, "company", 200) or _text(payload, "honeypot", 200):
        raise PermissionError("honeypot")

    cleaned = {
        "name": _text(payload, "name", 120, required=True),
        "email": _text(payload, "email", 254, required=True),
        "phone": _text(payload, "phone", 40),
        "projectType": _text(payload, "projectType", 80, required=True),
        "message": _text(payload, "message", 4_000, required=True),
        "locale": _text(payload, "locale", 2, required=True),
        "projectId": _text(payload, "projectId", 80),
        "recaptchaToken": _text(payload, "recaptchaToken", 4_096, required=True),
    }
    if not EMAIL_PATTERN.fullmatch(cleaned["email"]):
        raise ValueError("email")
    if cleaned["locale"] not in SUPPORTED_LOCALES:
        raise ValueError("locale")
    if payload.get("consent") is not True:
        raise ValueError("consent")
    return cleaned


def _verify_recaptcha(token: str, remote_ip: str) -> tuple[bool, str]:
    secret = os.getenv("RECAPTCHA_SECRET_KEY", "").strip()
    expected_hosts = {host.lower().rstrip(".") for host in _configured_values("RECAPTCHA_EXPECTED_HOSTNAMES")}
    try:
        minimum_score = float(os.getenv("RECAPTCHA_MIN_SCORE", "0.5"))
    except ValueError:
        return False, "configuration"
    expected_action = os.getenv("RECAPTCHA_EXPECTED_ACTION", RECAPTCHA_ACTION).strip()
    if not secret or not expected_hosts or not expected_action or not 0 <= minimum_score <= 1:
        return False, "configuration"

    fields = {"secret": secret, "response": token}
    if remote_ip:
        fields["remoteip"] = remote_ip
    request = urllib.request.Request(
        "https://www.google.com/recaptcha/api/siteverify",
        data=urllib.parse.urlencode(fields).encode("ascii"),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=4) as response:
            result = json.loads(response.read(16_384).decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, ValueError, json.JSONDecodeError):
        return False, "unavailable"

    hostname = str(result.get("hostname", "")).lower().rstrip(".")
    action = str(result.get("action", ""))
    try:
        score = float(result.get("score", -1))
    except (TypeError, ValueError):
        score = -1
    if result.get("success") is True and hostname in expected_hosts and action == expected_action and score >= minimum_score:
        return True, "ok"
    return False, "invalid"


def _email_bodies(payload: dict) -> tuple[str, str]:
    labels = {
        "name": "Name",
        "email": "Email",
        "phone": "Phone",
        "projectType": "Project type",
        "projectId": "Project ID",
        "locale": "Locale",
        "message": "Message",
    }
    text_lines = [f"{labels[key]}: {payload[key]}" for key in labels]
    rows = "".join(
        f"<tr><th style='text-align:left;vertical-align:top;padding:6px 12px 6px 0'>{html.escape(labels[key])}</th>"
        f"<td style='padding:6px 0;white-space:pre-wrap'>{html.escape(payload[key])}</td></tr>"
        for key in labels
    )
    return "\n".join(text_lines), f"<h1>BUHAJ DESIGN contact enquiry</h1><table>{rows}</table>"


def _send_email(payload: dict) -> None:
    sender = os.getenv("SES_FROM_EMAIL", "").strip()
    recipient = os.getenv("SES_TO_EMAIL", "").strip()
    region = os.getenv("AWS_REGION_NAME", "").strip()
    if not sender or not recipient or not region:
        raise RuntimeError("configuration")

    import boto3

    text_body, html_body = _email_bodies(payload)
    client = boto3.client("ses", region_name=region)
    client.send_email(
        Source=sender,
        Destination={"ToAddresses": [recipient]},
        ReplyToAddresses=[payload["email"]],
        Message={
            "Subject": {"Data": f"BUHAJ DESIGN enquiry — {payload['projectType']}", "Charset": "UTF-8"},
            "Body": {
                "Text": {"Data": text_body, "Charset": "UTF-8"},
                "Html": {"Data": html_body, "Charset": "UTF-8"},
            },
        },
    )


def handler(event, context):
    del context
    event = event or {}
    origin = _header(event, "origin").rstrip("/")
    allowed_origins = _configured_values("ALLOWED_ORIGINS")
    if not allowed_origins:
        return _response(500, "CONFIGURATION_ERROR", "Contact service is not configured.")
    if not origin or origin not in allowed_origins:
        return _response(403, "ORIGIN_NOT_ALLOWED", "Request origin is not allowed.")

    method = str((event.get("requestContext") or {}).get("http", {}).get("method", "POST")).upper()
    if method != "POST":
        return _response(405, "METHOD_NOT_ALLOWED", "Only POST is accepted.", origin)
    if not _header(event, "content-type").lower().startswith("application/json"):
        return _response(400, "INVALID_CONTENT_TYPE", "A JSON request is required.", origin)

    try:
        payload = _validate(_parse_body(event))
    except OverflowError:
        return _response(400, "PAYLOAD_TOO_LARGE", "The request is too large.", origin)
    except PermissionError:
        return _response(400, "INVALID_REQUEST", "The request could not be accepted.", origin)
    except (ValueError, TypeError, json.JSONDecodeError, binascii.Error):
        return _response(400, "VALIDATION_ERROR", "Please check the submitted fields.", origin)

    source_ip = str((event.get("requestContext") or {}).get("http", {}).get("sourceIp", ""))
    captcha_ok, captcha_reason = _verify_recaptcha(payload["recaptchaToken"], source_ip)
    if not captcha_ok:
        if captcha_reason == "configuration":
            return _response(500, "CONFIGURATION_ERROR", "Contact service is not configured.", origin)
        if captcha_reason == "unavailable":
            return _response(503, "CAPTCHA_UNAVAILABLE", "Anti-spam verification is temporarily unavailable.", origin)
        return _response(403, "CAPTCHA_FAILED", "Anti-spam verification failed.", origin)

    try:
        _send_email(payload)
    except Exception:
        return _response(503, "DELIVERY_FAILED", "The message could not be delivered.", origin)
    return _response(200, origin=origin)
