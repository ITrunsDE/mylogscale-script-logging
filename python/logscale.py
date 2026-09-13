# Copy these functions into your script, or import from this file.
# Named logscale.py so it does not shadow the stdlib logging module.
# Standard library only. Minimum: Python 3.8.

from __future__ import annotations

import json
import math
import os
import re
import ssl
import sys
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Optional
from urllib.parse import urlparse

_SCRIPT_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$")
_FIELD_NAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")
_RESERVED = frozenset({"timestamp", "level", "message", "script_name", "run_id"})
_LEVELS = frozenset({"INFO", "WARN", "ERROR"})


class LogScaleLogger:
    __slots__ = (
        "script_name",
        "run_id",
        "direct_enabled",
        "local_enabled",
        "endpoint",
        "token",
        "timeout_seconds",
        "log_directory",
    )

    def __init__(self) -> None:
        self.script_name = ""
        self.run_id = ""
        self.direct_enabled = False
        self.local_enabled = False
        self.endpoint: Optional[str] = None
        self.token: Optional[str] = None
        self.timeout_seconds = 5
        self.log_directory: Optional[Path] = None


def _warn(message: str) -> None:
    print(f"WARNING: {message}", file=sys.stderr)


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _fmt_ts(now: datetime) -> str:
    return now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{int(now.microsecond / 1000):03d}Z"


def _as_int(value: Any, minimum: int, maximum: int) -> int:
    # json.load may yield int; some editors save whole numbers as floats.
    if isinstance(value, bool):
        raise ValueError("bool")
    if isinstance(value, int):
        number = value
    elif isinstance(value, float) and value.is_integer():
        number = int(value)
    else:
        raise ValueError("type")
    if number < minimum or number > maximum:
        raise ValueError("range")
    return number


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ANN001
        raise urllib.error.HTTPError(req.full_url, code, "redirect rejected", headers, fp)


def _ssl_context() -> ssl.SSLContext:
    # python.org macOS installs often point at a missing openssl cafile; curl still works
    # via the system store. Prefer an existing bundle so direct HTTPS matches Bash/curl.
    candidates = [
        os.environ.get("SSL_CERT_FILE"),
        ssl.get_default_verify_paths().cafile,
        ssl.get_default_verify_paths().openssl_cafile,
        "/etc/ssl/cert.pem",
        "/etc/ssl/certs/ca-certificates.crt",
        "/etc/pki/tls/certs/ca-bundle.crt",
        "/opt/homebrew/etc/openssl@3/cert.pem",
        "/usr/local/etc/openssl@3/cert.pem",
    ]
    for candidate in candidates:
        if candidate and os.path.isfile(candidate):
            return ssl.create_default_context(cafile=candidate)
    return ssl.create_default_context()


def _post_structured(endpoint: str, token: str, body: bytes, timeout: int) -> None:
    # urllib honors http(s)_proxy like curl; http.client does not.
    request = urllib.request.Request(
        endpoint,
        data=body,
        headers={
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    opener = urllib.request.build_opener(
        _NoRedirect,
        urllib.request.HTTPSHandler(context=_ssl_context()),
    )
    with opener.open(request, timeout=timeout) as response:
        response.read()
        status = getattr(response, "status", None) or response.getcode()
        if status < 200 or status >= 300:
            raise urllib.error.HTTPError(endpoint, status, "bad status", response.headers, None)


def initialize_logscale(config_path: str, script_name: str) -> Optional[LogScaleLogger]:
    logger = LogScaleLogger()
    try:
        if not _SCRIPT_NAME_RE.fullmatch(script_name):
            raise ValueError("script name")
        path = Path(config_path).expanduser()
        if not path.is_file():
            raise FileNotFoundError(config_path)
        path = path.resolve()
        with path.open("r", encoding="utf-8") as handle:
            config = json.load(handle)
        if not isinstance(config.get("direct_logging_enabled"), bool) or not isinstance(
            config.get("local_logging_enabled"), bool
        ):
            raise ValueError("booleans")
        logger.script_name = script_name
        logger.run_id = str(uuid.uuid4())
    except Exception:
        _warn("LogScale initialization failed. Check the JSON file and script name; logging is disabled.")
        return None

    if config["direct_logging_enabled"]:
        try:
            url = config.get("url")
            token = config.get("ingest_token")
            timeout = _as_int(config.get("timeout_seconds"), 1, 60)
            if not isinstance(url, str) or not isinstance(token, str) or not token.strip() or " " in token.strip():
                raise ValueError("url/token")
            parsed = urlparse(url)
            if (
                parsed.scheme != "https"
                or parsed.username
                or parsed.password
                or parsed.query
                or parsed.fragment
                or parsed.path not in ("", "/")
                or not parsed.netloc
                or "@" in parsed.netloc
            ):
                raise ValueError("origin")
            origin = f"https://{parsed.netloc}"
            logger.endpoint = origin + "/api/v1/ingest/humio-structured"
            logger.token = token.strip()
            logger.timeout_seconds = timeout
            logger.direct_enabled = True
        except Exception:
            _warn(
                "LogScale direct logging disabled. Check the HTTPS origin, ingest token and timeout_seconds (1-60)."
            )

    if config["local_logging_enabled"]:
        retention = None
        try:
            retention = _as_int(config.get("retention_days"), 1, 36500)
            directory = config.get("log_directory")
            if not isinstance(directory, str) or not directory.strip():
                raise ValueError("directory")
            log_dir = Path(directory)
            if not log_dir.is_absolute():
                log_dir = path.parent / log_dir
            log_dir = log_dir.resolve()
            log_dir.mkdir(parents=True, exist_ok=True)
            if log_dir.is_symlink() or not log_dir.is_dir():
                raise ValueError("symlink")
            logger.log_directory = log_dir
            logger.local_enabled = True
        except Exception:
            _warn(
                "LogScale local logging disabled. Check log_directory permissions and retention_days (1-36500)."
            )

        if logger.local_enabled and retention is not None and logger.log_directory is not None:
            try:
                # Keep today and the previous retention_days - 1 UTC dates. Never recurse.
                oldest = _utc_now().date() - timedelta(days=retention - 1)
                prefix = logger.script_name + "-"
                suffix = ".jsonl"
                for entry in logger.log_directory.iterdir():
                    try:
                        if entry.is_symlink() or not entry.is_file():
                            continue
                        name = entry.name
                        if not (name.startswith(prefix) and name.endswith(suffix)):
                            continue
                        date_part = name[len(prefix) : -len(suffix)]
                        day = datetime.strptime(date_part, "%Y-%m-%d").date()
                        if day < oldest:
                            try:
                                entry.unlink()
                            except OSError:
                                _warn("LogScale could not delete an expired log file; continuing.")
                    except Exception:
                        continue
            except Exception:
                _warn("LogScale startup cleanup failed; logging will continue.")

    return logger


def write_logscale(
    logger: Optional[LogScaleLogger],
    level: str,
    message: str,
    fields: Optional[Dict[str, Any]] = None,
) -> None:
    if logger is None or (not logger.direct_enabled and not logger.local_enabled):
        return
    try:
        if level not in _LEVELS or not isinstance(message, str) or not message.strip():
            raise ValueError("level/message")
        now = _utc_now()
        event: Dict[str, Any] = {
            "timestamp": _fmt_ts(now),
            "level": level,
            "message": message,
            "script_name": logger.script_name,
            "run_id": logger.run_id,
        }
        if fields is None:
            fields = {}
        if not isinstance(fields, dict):
            raise ValueError("fields")
        for key, value in fields.items():
            if not isinstance(key, str) or not _FIELD_NAME_RE.fullmatch(key) or key.lower() in _RESERVED:
                raise ValueError("field name")
            if value is not None and not isinstance(value, (str, bool, int, float)):
                raise ValueError("field type")
            if isinstance(value, bool) or value is None or isinstance(value, str):
                event[key] = value
            elif isinstance(value, int) and not isinstance(value, bool):
                event[key] = value
            elif isinstance(value, float):
                if math.isnan(value) or math.isinf(value):
                    raise ValueError("number")
                event[key] = value
            else:
                raise ValueError("field type")
        payload = json.dumps(event, ensure_ascii=False, separators=(",", ":"))
    except Exception:
        _warn(
            "LogScale event rejected. Check level, message and scalar extra fields; do not overwrite reserved fields."
        )
        return

    if logger.local_enabled and logger.log_directory is not None:
        try:
            file_path = logger.log_directory / f"{logger.script_name}-{now.date().isoformat()}.jsonl"
            if file_path.exists() and (file_path.is_symlink() or not file_path.is_file()):
                raise OSError("linked file")
            # ponytail: one writer per script/path; use per-run files if overlapping runs are needed.
            with file_path.open("a", encoding="utf-8", newline="\n") as handle:
                handle.write(payload + "\n")
        except Exception:
            _warn(
                "LogScale local write failed. Check the log directory, permissions and free space; continuing."
            )

    if logger.direct_enabled and logger.endpoint and logger.token:
        try:
            body = json.dumps(
                [{"events": [{"timestamp": event["timestamp"], "attributes": event}]}],
                ensure_ascii=False,
                separators=(",", ":"),
            ).encode("utf-8")
            _post_structured(logger.endpoint, logger.token, body, logger.timeout_seconds)
        except Exception as exc:
            # Do not echo server responses, URLs, or exception text: they can contain secrets.
            if isinstance(exc, urllib.error.HTTPError):
                detail = f"HTTPError {exc.code}"
            elif isinstance(exc, urllib.error.URLError):
                reason = exc.reason
                if isinstance(reason, BaseException):
                    detail = f"URLError/{type(reason).__name__}"
                else:
                    detail = "URLError"
            else:
                detail = type(exc).__name__
            _warn(
                "LogScale HTTP delivery failed"
                f" ({detail}). Check connectivity, TLS, the Cloud URL and ingest token; event not retried."
            )
