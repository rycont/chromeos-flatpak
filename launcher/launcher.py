#!/usr/bin/env python3
"""Serve one desktop-file-backed PWA and launch that desktop file."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import html
import json
import mimetypes
import os
from pathlib import Path
import shlex
import signal
import subprocess
import sys
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, quote, urlparse


DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 39393
DESKTOP_FIELD_CODES = {"%f", "%F", "%u", "%U", "%i", "%c", "%k"}


@dataclass(frozen=True)
class DesktopEntry:
    path: Path
    name: str
    icon: str
    command: list[str]


def parse_desktop_file(filename: str) -> DesktopEntry:
    path = Path(filename)
    if not path.is_absolute():
        raise ValueError("desktop must be an absolute path")
    if path.suffix != ".desktop":
        raise ValueError("desktop must point to a .desktop file")
    try:
        path = path.resolve(strict=True)
        lines = path.read_text(encoding="utf-8-sig").splitlines()
    except (OSError, UnicodeError) as error:
        raise ValueError(f"cannot read desktop file: {path}") from error
    if not path.is_file():
        raise ValueError(f"desktop is not a regular file: {path}")

    values: dict[str, str] = {}
    in_entry = False
    for line in lines:
        line = line.strip()
        if line == "[Desktop Entry]":
            in_entry = True
            continue
        if line.startswith("["):
            in_entry = False
            continue
        if not in_entry or not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key in {"Name", "Icon", "Type", "Exec"}:
            values.setdefault(key, value)

    if values.get("Type", "Application") != "Application":
        raise ValueError("desktop file is not an application")
    try:
        command = shlex.split(values["Exec"], comments=False, posix=True)
    except (KeyError, ValueError) as error:
        raise ValueError(f"desktop file has an invalid Exec entry: {path}") from error
    if not command:
        raise ValueError(f"desktop file has an empty Exec entry: {path}")

    cleaned_command: list[str] = []
    in_file_forwarding = False
    for argument in command:
        if argument == "--file-forwarding":
            continue
        if argument == "@@":
            in_file_forwarding = not in_file_forwarding
            continue
        if in_file_forwarding:
            continue
        if argument in DESKTOP_FIELD_CODES:
            continue
        if "%" in argument:
            if argument == "%%":
                cleaned_command.append("%")
                continue
            raise ValueError("desktop Exec contains a file or URL argument")
        cleaned_command.append(argument)
    if not cleaned_command:
        raise ValueError(f"desktop file has no launch command: {path}")

    return DesktopEntry(
        path=path,
        name=values.get("Name") or path.stem,
        icon=values.get("Icon", ""),
        command=cleaned_command,
    )


def icon_candidates(entry: DesktopEntry) -> list[Path]:
    icon = Path(entry.icon)
    candidates: list[Path] = []
    if icon.is_absolute():
        candidates.append(icon)

    # Flatpak exports icons beside the exported desktop file. The remaining
    # roots cover the same layout after the package has been installed system-wide.
    roots = [
        entry.path.parent.parent / "icons",
        Path("/usr/local/var/lib/flatpak-user/exports/share/icons"),
        Path("/usr/local/var/lib/flatpak/exports/share/icons"),
        Path("/usr/local/share/icons"),
        Path("/usr/share/icons"),
    ]
    icon_names = [icon.name] if icon.name else [entry.path.stem]
    if icon.name and not icon.name.lower().endswith((".png", ".svg")):
        icon_names.extend((f"{icon.name}.png", f"{icon.name}.svg"))
    for root in roots:
        for size in ("512x512", "256x256", "128x128", "96x96", "64x64", "48x48", "scalable"):
            for icon_name in icon_names:
                candidates.append(root / "hicolor" / size / "apps" / icon_name)
    return candidates


def find_icon(entry: DesktopEntry) -> Path | None:
    for candidate in icon_candidates(entry):
        if candidate.is_file():
            return candidate
    return None


def fallback_icon(entry: DesktopEntry) -> bytes:
    label = html.escape(entry.name[:1].upper() or "?")
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <rect width="512" height="512" rx="112" fill="#2563eb"/>
  <text x="256" y="330" text-anchor="middle" font-family="sans-serif" font-size="250" font-weight="700" fill="white">{label}</text>
</svg>'''.encode("utf-8")


def query_desktop(request_path: str) -> str:
    values = parse_qs(urlparse(request_path).query, keep_blank_values=True)
    desktop = values.get("desktop", [""])[0]
    if not desktop:
        raise ValueError("desktop query parameter is required")
    return desktop


class Launcher:
    def __init__(self, web_root: Path):
        self.web_root = web_root

    @staticmethod
    def environment() -> dict[str, str]:
        env = os.environ.copy()
        env["PATH"] = "/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/bin"
        env.setdefault("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
        env.setdefault("FLATPAK_SYSTEM_DIR", "/usr/local/var/lib/flatpak")
        env.setdefault("FLATPAK_USER_DIR", "/usr/local/var/lib/flatpak-user")
        env.setdefault("XDG_RUNTIME_DIR", "/run/chrome")
        env.setdefault("WAYLAND_DISPLAY", "wayland-0")
        return env

    def launch(self, desktop: str) -> int:
        entry = parse_desktop_file(desktop)
        command = list(entry.command)
        if command[0] == "/usr/bin/flatpak" and Path("/usr/local/bin/flatpak").is_file():
            command[0] = "/usr/local/bin/flatpak"
        if len(command) > 1 and command[1] == "run" and command[0].endswith("/flatpak"):
            command.insert(2, "--no-documents-portal")
            if "--command=anki" in command:
                command.insert(2, "--env=QTWEBENGINE_CHROMIUM_FLAGS=--no-sandbox")
            if "--command=code" in command:
                command.insert(2, "--env=ELECTRON_DISABLE_SANDBOX=1")
        process = subprocess.Popen(
            command,
            env=self.environment(),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=None,
            start_new_session=True,
        )
        return process.pid


class Handler(BaseHTTPRequestHandler):
    server: "LauncherServer"

    def send_bytes(self, body: bytes, content_type: str, status: int = HTTPStatus.OK) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def send_json(self, value: object, status: int = HTTPStatus.OK) -> None:
        self.send_bytes(
            json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8"),
            "application/json; charset=utf-8",
            status,
        )

    def send_error_text(self, message: str, status: int) -> None:
        self.send_bytes(message.encode("utf-8"), "text/plain; charset=utf-8", status)

    def desktop(self) -> DesktopEntry:
        return parse_desktop_file(query_desktop(self.path))

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path.startswith("/static/"):
            filename = path.removeprefix("/static/")
            if filename in {"app.js", "styles.css"}:
                content_type = "text/css; charset=utf-8" if filename.endswith(".css") else "text/javascript; charset=utf-8"
                self.send_bytes((self.server.web_root / filename).read_bytes(), content_type)
                return

        if path == "/":
            try:
                entry = self.desktop()
            except ValueError as error:
                self.send_error_text(str(error), HTTPStatus.BAD_REQUEST)
                return
            desktop_query = quote(str(entry.path), safe="")
            body = (self.server.web_root / "app.html").read_text(encoding="utf-8")
            replacements = {
                "__APP_NAME__": html.escape(entry.name, quote=True),
                "__APP_DESCRIPTION__": html.escape(f"Launch {entry.name} on ChromeOS", quote=True),
                "__MANIFEST_URL__": f"/manifest.webmanifest?desktop={desktop_query}",
                "__ICON_URL__": f"/icon?desktop={desktop_query}",
            }
            for key, value in replacements.items():
                body = body.replace(key, value)
            self.send_bytes(body.encode("utf-8"), "text/html; charset=utf-8")
            return

        if path == "/manifest.webmanifest":
            try:
                entry = self.desktop()
            except ValueError as error:
                self.send_error_text(str(error), HTTPStatus.BAD_REQUEST)
                return
            desktop_query = quote(str(entry.path), safe="")
            start_url = f"/?desktop={desktop_query}"
            icon = find_icon(entry)
            manifest_icon = {
                "src": f"/icon?desktop={desktop_query}",
                "sizes": "any",
                "type": mimetypes.guess_type(icon.name)[0] if icon else "image/svg+xml",
                "purpose": "any maskable",
            }
            self.send_json(
                {
                    "id": start_url,
                    "name": entry.name,
                    "short_name": entry.name,
                    "start_url": start_url,
                    "scope": "/",
                    "display": "standalone",
                    "theme_color": "#111827",
                    "background_color": "#111827",
                    "icons": [manifest_icon],
                }
            )
            return

        if path == "/icon":
            try:
                entry = self.desktop()
            except ValueError as error:
                self.send_error_text(str(error), HTTPStatus.BAD_REQUEST)
                return
            icon = find_icon(entry)
            if icon is not None:
                self.send_bytes(icon.read_bytes(), mimetypes.guess_type(icon.name)[0] or "application/octet-stream")
            else:
                self.send_bytes(fallback_icon(entry), "image/svg+xml")
            return

        self.send_error_text("not found", HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:
        if urlparse(self.path).path != "/launch":
            self.send_error_text("not found", HTTPStatus.NOT_FOUND)
            return
        try:
            desktop = query_desktop(self.path)
            self.server.launcher.launch(desktop)
        except (OSError, ValueError) as error:
            self.send_error_text(str(error), HTTPStatus.BAD_GATEWAY)
            return
        self.send_bytes(b"", "text/plain; charset=utf-8", HTTPStatus.ACCEPTED)

    def log_message(self, format: str, *args: object) -> None:
        sys.stderr.write(f"chromeos-flatpak-launcher: {format % args}\n")


class LauncherServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], launcher: Launcher):
        self.launcher = launcher
        self.web_root = launcher.web_root
        super().__init__(address, Handler)


def run_daemon(host: str, port: int, pid_file: Path | None) -> int:
    web_root = Path(__file__).resolve().parent / "web"
    if not web_root.is_dir():
        raise RuntimeError(f"web assets are missing: {web_root}")
    server = LauncherServer((host, port), Launcher(web_root))
    if pid_file is not None:
        pid_file.parent.mkdir(parents=True, exist_ok=True)
        pid_file.write_text(f"{os.getpid()}\n", encoding="ascii")

    def stop(_signum: int, _frame: object) -> None:
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    sys.stderr.write(f"chromeos-flatpak-launcher: listening on http://localhost:{port}/\n")
    try:
        server.serve_forever()
    finally:
        server.server_close()
        if pid_file is not None:
            try:
                if pid_file.read_text(encoding="ascii").strip() == str(os.getpid()):
                    pid_file.unlink()
            except FileNotFoundError:
                pass
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--pid-file", type=Path)
    args = parser.parse_args()
    return run_daemon(args.host, args.port, args.pid_file)


if __name__ == "__main__":
    raise SystemExit(main())
