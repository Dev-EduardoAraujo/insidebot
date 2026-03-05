#!/usr/bin/env python3
"""
InsideBot License Server

Compatible with InsideBot.mq5 license validation flow:
POST /api/v1/license/validate
"""

import argparse
import json
import logging
import mimetypes
import os
import secrets
import sqlite3
import threading
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def to_iso_utc(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_bool(value, default=False) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"1", "true", "yes", "y", "on"}:
            return True
        if normalized in {"0", "false", "no", "n", "off"}:
            return False
    return default


def parse_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        items = [str(x).strip() for x in value]
    else:
        text = str(value).replace("\n", ",").replace(";", ",")
        items = [x.strip() for x in text.split(",")]
    out = []
    seen = set()
    for item in items:
        if not item:
            continue
        key = item.lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(item)
    return out


def parse_expiry_utc(value) -> datetime:
    if value is None:
        raise ValueError("expires_at is required")

    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(float(value), tz=timezone.utc)

    text = str(value).strip()
    if not text:
        raise ValueError("expires_at is empty")

    if text.isdigit():
        return datetime.fromtimestamp(float(text), tz=timezone.utc)

    iso_text = text.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(iso_text)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except ValueError:
        pass

    datetime_formats = [
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d %H:%M:%S",
        "%Y.%m.%d %H:%M:%S",
        "%Y-%m-%d",
        "%Y.%m.%d",
    ]
    for fmt in datetime_formats:
        try:
            parsed = datetime.strptime(text, fmt)
            if fmt in {"%Y-%m-%d", "%Y.%m.%d"}:
                parsed = parsed.replace(hour=23, minute=59, second=59)
            return parsed.replace(tzinfo=timezone.utc)
        except ValueError:
            continue

    raise ValueError(f"unsupported expires_at format: {text}")


class LicenseStore:
    def __init__(self, db_path: Path):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._write_lock = threading.Lock()
        self._init_db()

    def _connect(self):
        conn = sqlite3.connect(str(self.db_path), timeout=30)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_db(self):
        with self._connect() as conn:
            conn.execute("PRAGMA journal_mode=WAL")
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS licenses (
                    token TEXT PRIMARY KEY,
                    customer_name TEXT NOT NULL,
                    expires_at TEXT NOT NULL,
                    revoked INTEGER NOT NULL DEFAULT 0,
                    active INTEGER NOT NULL DEFAULT 1,
                    allowed_logins TEXT NOT NULL DEFAULT '[]',
                    allowed_servers TEXT NOT NULL DEFAULT '[]',
                    notes TEXT NOT NULL DEFAULT '',
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    last_seen_at TEXT,
                    last_login TEXT,
                    last_server TEXT,
                    last_program TEXT,
                    last_build TEXT,
                    last_remote_ip TEXT,
                    bound_at TEXT,
                    bound_login TEXT,
                    bound_server TEXT,
                    bound_ip TEXT
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS validation_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    token TEXT NOT NULL,
                    event_time TEXT NOT NULL,
                    login TEXT,
                    server TEXT,
                    company TEXT,
                    account_name TEXT,
                    program TEXT,
                    build TEXT,
                    allowed INTEGER NOT NULL,
                    revoked INTEGER NOT NULL,
                    status TEXT NOT NULL,
                    message TEXT NOT NULL,
                    remote_ip TEXT,
                    payload_json TEXT NOT NULL
                )
                """
            )
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_validation_events_token_time ON validation_events(token, event_time DESC)"
            )
            self._ensure_column(conn, "licenses", "last_remote_ip TEXT")
            self._ensure_column(conn, "licenses", "bound_at TEXT")
            self._ensure_column(conn, "licenses", "bound_login TEXT")
            self._ensure_column(conn, "licenses", "bound_server TEXT")
            self._ensure_column(conn, "licenses", "bound_ip TEXT")
            conn.commit()

    @staticmethod
    def _ensure_column(conn, table_name: str, column_def: str):
        column_name = str(column_def).split()[0].strip()
        if not column_name:
            return
        rows = conn.execute(f"PRAGMA table_info({table_name})").fetchall()
        existing = {str(r["name"]).strip().lower() for r in rows}
        if column_name.lower() in existing:
            return
        conn.execute(f"ALTER TABLE {table_name} ADD COLUMN {column_def}")

    @staticmethod
    def _row_to_license(row):
        if row is None:
            return None
        allowed_logins = json.loads(row["allowed_logins"]) if row["allowed_logins"] else []
        allowed_servers = json.loads(row["allowed_servers"]) if row["allowed_servers"] else []
        return {
            "token": row["token"],
            "customer_name": row["customer_name"],
            "expires_at": row["expires_at"],
            "revoked": bool(row["revoked"]),
            "active": bool(row["active"]),
            "allowed_logins": allowed_logins,
            "allowed_servers": allowed_servers,
            "notes": row["notes"],
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
            "last_seen_at": row["last_seen_at"],
            "last_login": row["last_login"],
            "last_server": row["last_server"],
            "last_program": row["last_program"],
            "last_build": row["last_build"],
            "last_remote_ip": row["last_remote_ip"],
            "bound_at": row["bound_at"],
            "bound_login": row["bound_login"],
            "bound_server": row["bound_server"],
            "bound_ip": row["bound_ip"],
        }

    def get_license(self, token: str):
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM licenses WHERE token = ?", (token,)).fetchone()
            return self._row_to_license(row)

    def upsert_license(self, payload: dict):
        token = str(payload.get("token", "")).strip()
        if not token:
            raise ValueError("token is required")

        customer_name = str(payload.get("customer_name", "")).strip() or "Cliente InsideBot"
        expires_at = parse_expiry_utc(payload.get("expires_at"))
        allowed_logins = parse_list(payload.get("allowed_logins"))
        allowed_servers = [x.lower() for x in parse_list(payload.get("allowed_servers"))]
        revoked = parse_bool(payload.get("revoked"), False)
        active = parse_bool(payload.get("active"), True)
        notes = str(payload.get("notes", "")).strip()
        now = to_iso_utc(utc_now())

        with self._write_lock, self._connect() as conn:
            conn.execute(
                """
                INSERT INTO licenses(
                    token, customer_name, expires_at, revoked, active,
                    allowed_logins, allowed_servers, notes,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(token) DO UPDATE SET
                    customer_name = excluded.customer_name,
                    expires_at = excluded.expires_at,
                    revoked = excluded.revoked,
                    active = excluded.active,
                    allowed_logins = excluded.allowed_logins,
                    allowed_servers = excluded.allowed_servers,
                    notes = excluded.notes,
                    updated_at = excluded.updated_at
                """,
                (
                    token,
                    customer_name,
                    to_iso_utc(expires_at),
                    1 if revoked else 0,
                    1 if active else 0,
                    json.dumps(allowed_logins, separators=(",", ":")),
                    json.dumps(allowed_servers, separators=(",", ":")),
                    notes,
                    now,
                    now,
                ),
            )
            conn.commit()

        return self.get_license(token)

    def revoke_license(self, token: str, revoked: bool = True):
        token = str(token).strip()
        if not token:
            raise ValueError("token is required")
        with self._write_lock, self._connect() as conn:
            cursor = conn.execute(
                "UPDATE licenses SET revoked = ?, updated_at = ? WHERE token = ?",
                (1 if revoked else 0, to_iso_utc(utc_now()), token),
            )
            conn.commit()
            if cursor.rowcount == 0:
                raise ValueError("token not found")
        return self.get_license(token)

    def extend_license(self, token: str, days=None, expires_at=None):
        token = str(token).strip()
        if not token:
            raise ValueError("token is required")

        current = self.get_license(token)
        if current is None:
            raise ValueError("token not found")

        if expires_at is not None:
            new_expiry = parse_expiry_utc(expires_at)
        else:
            if days is None:
                raise ValueError("days or expires_at is required")
            try:
                add_days = int(days)
            except (TypeError, ValueError):
                raise ValueError("days must be integer")
            if add_days == 0:
                raise ValueError("days must be non-zero")
            base = parse_expiry_utc(current["expires_at"])
            now = utc_now()
            if base < now:
                base = now
            new_expiry = base + timedelta(days=add_days)

        with self._write_lock, self._connect() as conn:
            conn.execute(
                "UPDATE licenses SET expires_at = ?, updated_at = ? WHERE token = ?",
                (to_iso_utc(new_expiry), to_iso_utc(utc_now()), token),
            )
            conn.commit()

        return self.get_license(token)

    def delete_license(self, token: str, delete_events: bool = False):
        token = str(token).strip()
        if not token:
            raise ValueError("token is required")

        deleted_events = 0
        with self._write_lock, self._connect() as conn:
            cursor = conn.execute("DELETE FROM licenses WHERE token = ?", (token,))
            if cursor.rowcount == 0:
                raise ValueError("token not found")
            if delete_events:
                ev_cursor = conn.execute("DELETE FROM validation_events WHERE token = ?", (token,))
                deleted_events = int(ev_cursor.rowcount or 0)
            conn.commit()

        return {
            "token": token,
            "deleted": True,
            "deleted_events": deleted_events,
        }

    def list_licenses(self, limit=200, offset=0, token=None):
        limit = max(1, min(int(limit), 1000))
        offset = max(0, int(offset))
        params = []
        where = ""
        if token:
            where = "WHERE token LIKE ?"
            params.append(f"%{token}%")
        with self._connect() as conn:
            total = conn.execute(f"SELECT COUNT(*) AS c FROM licenses {where}", params).fetchone()["c"]
            rows = conn.execute(
                f"SELECT * FROM licenses {where} ORDER BY updated_at DESC LIMIT ? OFFSET ?",
                (*params, limit, offset),
            ).fetchall()
            items = [self._row_to_license(row) for row in rows]
        return {"total": int(total), "items": items}

    def list_events(self, limit=200, offset=0, token=None):
        limit = max(1, min(int(limit), 1000))
        offset = max(0, int(offset))
        params = []
        where = ""
        if token:
            where = "WHERE token LIKE ?"
            params.append(f"%{token}%")

        with self._connect() as conn:
            total = conn.execute(f"SELECT COUNT(*) AS c FROM validation_events {where}", params).fetchone()["c"]
            rows = conn.execute(
                f"""
                SELECT id, token, event_time, login, server, company, account_name, program, build,
                       allowed, revoked, status, message, remote_ip
                FROM validation_events
                {where}
                ORDER BY id DESC
                LIMIT ? OFFSET ?
                """,
                (*params, limit, offset),
            ).fetchall()
        items = []
        for row in rows:
            items.append(
                {
                    "id": row["id"],
                    "token": row["token"],
                    "event_time": row["event_time"],
                    "login": row["login"],
                    "server": row["server"],
                    "company": row["company"],
                    "account_name": row["account_name"],
                    "program": row["program"],
                    "build": row["build"],
                    "allowed": bool(row["allowed"]),
                    "revoked": bool(row["revoked"]),
                    "status": row["status"],
                    "message": row["message"],
                    "remote_ip": row["remote_ip"],
                }
            )
        return {"total": int(total), "items": items}

    def _record_event(self, payload: dict, response: dict, remote_ip: str):
        login = str(payload.get("login", "")).strip()
        server = str(payload.get("server", "")).strip()
        company = str(payload.get("company", "")).strip()
        account_name = str(payload.get("name", "")).strip()
        program = str(payload.get("program", "")).strip()
        build = str(payload.get("build", "")).strip()
        token = str(payload.get("token", "")).strip()

        with self._write_lock, self._connect() as conn:
            conn.execute(
                """
                INSERT INTO validation_events(
                    token, event_time, login, server, company, account_name, program, build,
                    allowed, revoked, status, message, remote_ip, payload_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    token,
                    to_iso_utc(utc_now()),
                    login,
                    server,
                    company,
                    account_name,
                    program,
                    build,
                    1 if response.get("allowed") else 0,
                    1 if response.get("revoked") else 0,
                    response.get("status", ""),
                    response.get("message", ""),
                    remote_ip,
                    json.dumps(payload, ensure_ascii=True),
                ),
            )
            conn.commit()

    def validate(self, payload: dict, remote_ip: str, lock_first_activation: bool = True):
        token = str(payload.get("token", "")).strip()
        login = str(payload.get("login", "")).strip()
        server_name = str(payload.get("server", "")).strip()
        normalized_server = server_name.lower()

        response = {
            "allowed": False,
            "revoked": False,
            "customer_name": "",
            "expires_at": "",
            "message": "",
            "status": "DENIED",
        }

        if not token:
            response["message"] = "token_missing"
            response["status"] = "TOKEN_MISSING"
            self._record_event(payload, response, remote_ip)
            return response

        license_row = self.get_license(token)
        if license_row is None:
            response["message"] = "token_not_found"
            response["status"] = "TOKEN_NOT_FOUND"
            self._record_event(payload, response, remote_ip)
            return response

        response["customer_name"] = license_row["customer_name"]
        response["expires_at"] = license_row["expires_at"]

        if not license_row["active"]:
            response["message"] = "license_disabled"
            response["status"] = "DISABLED"
            self._record_event(payload, response, remote_ip)
            return response

        if license_row["revoked"]:
            response["revoked"] = True
            response["message"] = "license_revoked"
            response["status"] = "REVOKED"
            self._record_event(payload, response, remote_ip)
            return response

        expiry_dt = parse_expiry_utc(license_row["expires_at"])
        if utc_now() > expiry_dt:
            response["message"] = "license_expired"
            response["status"] = "EXPIRED"
            self._record_event(payload, response, remote_ip)
            return response

        bound_login = str(license_row.get("bound_login") or "").strip()
        bound_server = str(license_row.get("bound_server") or "").strip().lower()
        if bound_login:
            if login == "" or login != bound_login:
                response["message"] = "login_not_allowed"
                response["status"] = "LOGIN_NOT_ALLOWED"
                self._record_event(payload, response, remote_ip)
                return response

        if bound_server:
            if normalized_server == "" or normalized_server != bound_server:
                response["message"] = "server_not_allowed"
                response["status"] = "SERVER_NOT_ALLOWED"
                self._record_event(payload, response, remote_ip)
                return response

        if license_row["allowed_logins"]:
            if login == "" or login not in [str(x) for x in license_row["allowed_logins"]]:
                response["message"] = "login_not_allowed"
                response["status"] = "LOGIN_NOT_ALLOWED"
                self._record_event(payload, response, remote_ip)
                return response

        if license_row["allowed_servers"]:
            allowed_servers = [str(x).lower() for x in license_row["allowed_servers"]]
            if normalized_server == "" or normalized_server not in allowed_servers:
                response["message"] = "server_not_allowed"
                response["status"] = "SERVER_NOT_ALLOWED"
                self._record_event(payload, response, remote_ip)
                return response

        if lock_first_activation:
            needs_bind_login = not bound_login
            needs_bind_server = not bound_server
            if needs_bind_login or needs_bind_server:
                if login == "" or normalized_server == "":
                    response["message"] = "bind_missing_login_or_server"
                    response["status"] = "BIND_MISSING_LOGIN_OR_SERVER"
                    self._record_event(payload, response, remote_ip)
                    return response
                now_iso = to_iso_utc(utc_now())
                new_bound_login = bound_login or login
                new_bound_server = bound_server or normalized_server
                with self._write_lock, self._connect() as conn:
                    conn.execute(
                        """
                        UPDATE licenses
                        SET bound_login = ?,
                            bound_server = ?,
                            bound_ip = COALESCE(bound_ip, ?),
                            bound_at = COALESCE(bound_at, ?),
                            updated_at = ?
                        WHERE token = ?
                        """,
                        (
                            new_bound_login,
                            new_bound_server,
                            remote_ip,
                            now_iso,
                            now_iso,
                            token,
                        ),
                    )
                    conn.commit()
                bound_login = new_bound_login
                bound_server = new_bound_server

        with self._write_lock, self._connect() as conn:
            conn.execute(
                """
                UPDATE licenses
                SET last_seen_at = ?, last_login = ?, last_server = ?, last_program = ?, last_build = ?, last_remote_ip = ?, updated_at = ?
                WHERE token = ?
                """,
                (
                    to_iso_utc(utc_now()),
                    login,
                    server_name,
                    str(payload.get("program", "")).strip(),
                    str(payload.get("build", "")).strip(),
                    remote_ip,
                    to_iso_utc(utc_now()),
                    token,
                ),
            )
            conn.commit()

        response["allowed"] = True
        response["message"] = "ok"
        response["status"] = "VALID"
        self._record_event(payload, response, remote_ip)
        return response


class LicenseHTTPServer(ThreadingHTTPServer):
    def __init__(
        self,
        server_address,
        handler_class,
        store: LicenseStore,
        admin_key: str,
        admin_username: str,
        admin_password: str,
        session_ttl_seconds: int,
        lock_first_activation: bool,
    ):
        super().__init__(server_address, handler_class)
        self.store = store
        self.admin_key = admin_key
        self.admin_username = admin_username
        self.admin_password = admin_password
        self.session_ttl_seconds = max(300, int(session_ttl_seconds))
        self.lock_first_activation = bool(lock_first_activation)
        self._sessions = {}
        self._session_lock = threading.Lock()

    def create_session(self, username: str):
        token = secrets.token_urlsafe(32)
        expires_at = utc_now() + timedelta(seconds=self.session_ttl_seconds)
        with self._session_lock:
            self._sessions[token] = {
                "username": username,
                "expires_at": expires_at,
            }
        return token, expires_at

    def validate_session(self, token: str):
        if not token:
            return None
        with self._session_lock:
            entry = self._sessions.get(token)
            if entry is None:
                return None
            if utc_now() > entry["expires_at"]:
                del self._sessions[token]
                return None
            return entry["username"]

    def revoke_session(self, token: str):
        if not token:
            return
        with self._session_lock:
            self._sessions.pop(token, None)


class LicenseHandler(BaseHTTPRequestHandler):
    server_version = "InsideBotLicenseServer/1.0"

    def log_message(self, fmt, *args):
        logging.info("%s - %s", self.address_string(), fmt % args)

    def _send_json(self, code: int, payload: dict):
        body = json.dumps(payload, ensure_ascii=True).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Admin-Key, Authorization")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()
        self.wfile.write(body)

    def _send_text(self, code: int, content: str, content_type: str = "text/plain; charset=utf-8"):
        body = content.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_binary(self, code: int, data: bytes, content_type: str):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    @staticmethod
    def _static_root_candidates():
        script_dir = Path(__file__).resolve().parent
        return [
            script_dir / "tools" / "license_admin",  # runtime in /opt/insidebot-license
            script_dir / "license_admin",            # local fallback
        ]

    def _find_static_root(self):
        for candidate in self._static_root_candidates():
            if candidate.exists() and candidate.is_dir():
                return candidate
        return None

    def _serve_static(self, path: str):
        static_root = self._find_static_root()
        if static_root is None:
            self._send_text(404, "admin_frontend_not_found")
            return

        normalized = path.split("?", 1)[0]
        if normalized in {"/admin", "/admin/"}:
            target = static_root / "index.html"
        elif normalized.startswith("/admin/"):
            relative = normalized[len("/admin/"):].lstrip("/")
            if not relative:
                relative = "index.html"
            target = (static_root / relative).resolve()
            if static_root.resolve() not in target.parents and target != static_root.resolve():
                self._send_json(403, {"ok": False, "error": "forbidden"})
                return
        else:
            self._send_json(404, {"ok": False, "error": "not_found"})
            return

        if not target.exists() or not target.is_file():
            self._send_json(404, {"ok": False, "error": "not_found"})
            return

        content_type, _ = mimetypes.guess_type(str(target))
        if not content_type:
            content_type = "application/octet-stream"

        data = target.read_bytes()
        self._send_binary(200, data, content_type)

    def _read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        try:
            return json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            raise ValueError("invalid_json")

    def _read_login_payload(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        ctype = self.headers.get("Content-Type", "").lower()
        text = raw.decode("utf-8", errors="ignore")
        if "application/json" in ctype:
            try:
                return json.loads(text) if text.strip() else {}
            except json.JSONDecodeError:
                raise ValueError("invalid_json")
        if "application/x-www-form-urlencoded" in ctype:
            parsed = parse_qs(text, keep_blank_values=True)
            return {k: (v[0] if isinstance(v, list) and v else "") for k, v in parsed.items()}
        # fallback: try JSON first, then querystring style
        try:
            return json.loads(text) if text.strip() else {}
        except json.JSONDecodeError:
            parsed = parse_qs(text, keep_blank_values=True)
            if parsed:
                return {k: (v[0] if isinstance(v, list) and v else "") for k, v in parsed.items()}
        return {}

    def _get_bearer_token(self):
        auth = self.headers.get("Authorization", "").strip()
        if not auth.lower().startswith("bearer "):
            return ""
        return auth[7:].strip()

    def _get_remote_ip(self):
        xff = self.headers.get("X-Forwarded-For", "").strip()
        if xff:
            first = xff.split(",")[0].strip()
            if first:
                return first
        xreal = self.headers.get("X-Real-IP", "").strip()
        if xreal:
            return xreal
        if self.client_address:
            return str(self.client_address[0])
        return ""

    def _has_admin_access(self):
        admin_key = getattr(self.server, "admin_key", "")
        sent_key = self.headers.get("X-Admin-Key", "").strip()
        if admin_key and sent_key and sent_key == admin_key:
            return True

        bearer = self._get_bearer_token()
        if bearer and self.server.validate_session(bearer):
            return True
        return False

    def _require_admin(self):
        admin_key = getattr(self.server, "admin_key", "")
        if not admin_key:
            self._send_json(500, {"ok": False, "error": "admin_key_not_configured"})
            return False
        if not self._has_admin_access():
            self._send_json(401, {"ok": False, "error": "unauthorized"})
            return False
        return True

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Admin-Key, Authorization")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)

        if path in {"/", "/admin", "/admin/"} or path.startswith("/admin/"):
            if path == "/":
                self.send_response(302)
                self.send_header("Location", "/admin")
                self.end_headers()
                return
            self._serve_static(path)
            return

        if path in {"/api/health", "/api/v1/health"}:
            self._send_json(
                200,
                {
                    "ok": True,
                    "service": "insidebot-license-server",
                    "time_utc": to_iso_utc(utc_now()),
                },
            )
            return

        if path == "/api/v1/admin/licenses":
            if not self._require_admin():
                return
            limit = int(query.get("limit", ["200"])[0])
            offset = int(query.get("offset", ["0"])[0])
            token = query.get("token", [""])[0].strip() or None
            result = self.server.store.list_licenses(limit=limit, offset=offset, token=token)
            self._send_json(200, {"ok": True, **result})
            return

        if path == "/api/v1/admin/events":
            if not self._require_admin():
                return
            limit = int(query.get("limit", ["200"])[0])
            offset = int(query.get("offset", ["0"])[0])
            token = query.get("token", [""])[0].strip() or None
            result = self.server.store.list_events(limit=limit, offset=offset, token=token)
            self._send_json(200, {"ok": True, **result})
            return

        if path == "/api/v1/admin/auth/check":
            if not self._require_admin():
                return
            self._send_json(200, {"ok": True, "authenticated": True})
            return

        self._send_json(404, {"ok": False, "error": "not_found"})

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/api/v1/admin/auth/login":
            try:
                payload = self._read_login_payload()
            except ValueError:
                self._send_json(400, {"ok": False, "error": "invalid_json"})
                return
            username = str(payload.get("username", "")).strip()
            password = str(payload.get("password", "")).strip()
            expected_user = getattr(self.server, "admin_username", "admin")
            expected_pass = getattr(self.server, "admin_password", "")
            if not expected_pass:
                self._send_json(500, {"ok": False, "error": "admin_password_not_configured"})
                return
            if not username:
                username = expected_user
            user_ok = username.lower() == str(expected_user).strip().lower()
            pass_ok = password == str(expected_pass)
            if not user_ok or not pass_ok:
                logging.warning(
                    "admin login denied user=%s payload_keys=%s ip=%s",
                    username,
                    ",".join(sorted([str(k) for k in payload.keys()])),
                    self._get_remote_ip(),
                )
                self._send_json(401, {"ok": False, "error": "invalid_credentials"})
                return
            token, expires_at = self.server.create_session(username)
            self._send_json(
                200,
                {
                    "ok": True,
                    "token": token,
                    "username": username,
                    "expires_at": to_iso_utc(expires_at),
                },
            )
            return

        if path == "/api/v1/admin/auth/logout":
            token = self._get_bearer_token()
            if token:
                self.server.revoke_session(token)
            self._send_json(200, {"ok": True})
            return

        if path == "/api/v1/license/validate":
            try:
                payload = self._read_json()
            except ValueError:
                self._send_json(400, {"allowed": False, "revoked": False, "message": "invalid_json", "status": "BAD_JSON"})
                return
            remote_ip = self._get_remote_ip()
            result = self.server.store.validate(
                payload,
                remote_ip,
                lock_first_activation=getattr(self.server, "lock_first_activation", True),
            )
            self._send_json(200, result)
            return

        if path == "/api/v1/admin/license/upsert":
            if not self._require_admin():
                return
            try:
                payload = self._read_json()
                row = self.server.store.upsert_license(payload)
                self._send_json(200, {"ok": True, "license": row})
            except ValueError as exc:
                self._send_json(400, {"ok": False, "error": str(exc)})
            return

        if path == "/api/v1/admin/license/revoke":
            if not self._require_admin():
                return
            try:
                payload = self._read_json()
                token = str(payload.get("token", "")).strip()
                revoked = parse_bool(payload.get("revoked"), True)
                row = self.server.store.revoke_license(token, revoked=revoked)
                self._send_json(200, {"ok": True, "license": row})
            except ValueError as exc:
                self._send_json(400, {"ok": False, "error": str(exc)})
            return

        if path == "/api/v1/admin/license/extend":
            if not self._require_admin():
                return
            try:
                payload = self._read_json()
                token = str(payload.get("token", "")).strip()
                days = payload.get("days")
                expires_at = payload.get("expires_at")
                row = self.server.store.extend_license(token, days=days, expires_at=expires_at)
                self._send_json(200, {"ok": True, "license": row})
            except ValueError as exc:
                self._send_json(400, {"ok": False, "error": str(exc)})
            return

        if path == "/api/v1/admin/license/delete":
            if not self._require_admin():
                return
            try:
                payload = self._read_json()
                token = str(payload.get("token", "")).strip()
                delete_events = parse_bool(payload.get("delete_events"), False)
                result = self.server.store.delete_license(token, delete_events=delete_events)
                self._send_json(200, {"ok": True, "result": result})
            except ValueError as exc:
                self._send_json(400, {"ok": False, "error": str(exc)})
            return

        self._send_json(404, {"ok": False, "error": "not_found"})


def main():
    parser = argparse.ArgumentParser(description="InsideBot license server")
    parser.add_argument("--host", default=os.getenv("INSIDEBOT_LICENSE_HOST", "0.0.0.0"))
    parser.add_argument("--port", type=int, default=int(os.getenv("INSIDEBOT_LICENSE_PORT", "8090")))
    parser.add_argument(
        "--db-path",
        default=os.getenv("INSIDEBOT_LICENSE_DB", str(Path("tools") / "license_data" / "licenses.db")),
    )
    parser.add_argument("--admin-key", default=os.getenv("INSIDEBOT_LICENSE_ADMIN_KEY", ""))
    parser.add_argument("--admin-username", default=os.getenv("INSIDEBOT_ADMIN_USERNAME", "admin"))
    parser.add_argument("--admin-password", default=os.getenv("INSIDEBOT_ADMIN_PASSWORD", "F82615225b"))
    parser.add_argument("--lock-first-activation", default=os.getenv("INSIDEBOT_LICENSE_LOCK_FIRST_ACTIVATION", "true"))
    parser.add_argument(
        "--session-ttl-seconds",
        type=int,
        default=int(os.getenv("INSIDEBOT_ADMIN_SESSION_TTL_SECONDS", "43200")),
    )
    parser.add_argument("--log-level", default=os.getenv("INSIDEBOT_LICENSE_LOG_LEVEL", "INFO"))
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, str(args.log_level).upper(), logging.INFO),
        format="%(asctime)s [%(levelname)s] %(message)s",
    )

    db_path = Path(args.db_path)
    store = LicenseStore(db_path)
    server = LicenseHTTPServer(
        (args.host, args.port),
        LicenseHandler,
        store,
        admin_key=args.admin_key,
        admin_username=args.admin_username,
        admin_password=args.admin_password,
        session_ttl_seconds=args.session_ttl_seconds,
        lock_first_activation=parse_bool(args.lock_first_activation, True),
    )

    if not args.admin_key:
        logging.warning("INSIDEBOT_LICENSE_ADMIN_KEY not set. Admin endpoints will return unauthorized.")
    if args.admin_username == "admin" and args.admin_password == "F82615225b":
        logging.warning("Using default admin login credentials. Change INSIDEBOT_ADMIN_PASSWORD in production.")

    logging.info("InsideBot license server listening on %s:%s", args.host, args.port)
    logging.info("DB: %s", db_path.resolve())
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logging.info("Shutdown requested")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
