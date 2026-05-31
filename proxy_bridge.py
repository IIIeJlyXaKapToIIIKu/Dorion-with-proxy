#!/usr/bin/env python3
import argparse
import base64
import os
import select
import socket
import socketserver
import sys
from urllib.parse import unquote, urlsplit


BUFFER_SIZE = 65536
HEADER_LIMIT = 131072


class ProxySettings:
    def __init__(self, upstream_url: str):
        parsed = urlsplit(upstream_url)
        if parsed.scheme.lower() != "http":
            raise ValueError("Only http:// upstream proxies are supported")
        if not parsed.hostname:
            raise ValueError("Upstream proxy host is missing")

        self.host = parsed.hostname
        self.port = parsed.port or 80
        self.auth_header = None

        if parsed.username is not None or parsed.password is not None:
            username = unquote(parsed.username or "")
            password = unquote(parsed.password or "")
            token = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
            self.auth_header = f"Proxy-Authorization: Basic {token}"


def parse_listen(value: str) -> tuple[str, int]:
    if ":" not in value:
        return value, 18080
    host, port = value.rsplit(":", 1)
    return host, int(port)


def read_headers(sock: socket.socket) -> tuple[bytes, bytes]:
    data = bytearray()
    while b"\r\n\r\n" not in data:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data.extend(chunk)
        if len(data) > HEADER_LIMIT:
            raise ValueError("HTTP headers are too large")

    marker = data.find(b"\r\n\r\n")
    if marker == -1:
        return bytes(data), b""

    end = marker + 4
    return bytes(data[:end]), bytes(data[end:])


def rewrite_request(header: bytes, auth_header: str | None) -> bytes:
    text = header.decode("iso-8859-1")
    lines = text.split("\r\n")
    if not lines or not lines[0]:
        raise ValueError("Empty request")

    rewritten = [lines[0]]
    has_host = False

    for line in lines[1:]:
        if not line:
            continue
        name = line.split(":", 1)[0].strip().lower()
        if name == "host":
            has_host = True
        if name in {"proxy-authorization", "proxy-connection"}:
            continue
        rewritten.append(line)

    if auth_header:
        rewritten.append(auth_header)
    if not any(line.lower().startswith("proxy-connection:") for line in rewritten):
        rewritten.append("Proxy-Connection: Keep-Alive")

    if not has_host:
        parts = lines[0].split(" ")
        if len(parts) >= 2:
            rewritten.append(f"Host: {parts[1]}")

    return ("\r\n".join(rewritten) + "\r\n\r\n").encode("iso-8859-1")


def relay(left: socket.socket, right: socket.socket) -> None:
    sockets = [left, right]
    while True:
        readable, _, _ = select.select(sockets, [], [], 300)
        if not readable:
            return

        for source in readable:
            target = right if source is left else left
            try:
                data = source.recv(BUFFER_SIZE)
            except OSError:
                return

            if not data:
                return

            try:
                target.sendall(data)
            except OSError:
                return


class ProxyHandler(socketserver.BaseRequestHandler):
    settings: ProxySettings

    def handle(self) -> None:
        upstream = None
        try:
            header, remainder = read_headers(self.request)
            if not header:
                return

            first_line = header.split(b"\r\n", 1)[0].decode("iso-8859-1", "replace")
            parts = first_line.split(" ")
            if len(parts) < 3:
                self.send_error(400, "Bad Request")
                return

            upstream = socket.create_connection(
                (self.settings.host, self.settings.port),
                timeout=30,
            )
            upstream.settimeout(None)

            upstream.sendall(rewrite_request(header, self.settings.auth_header))
            if remainder:
                upstream.sendall(remainder)

            relay(self.request, upstream)
        except Exception as exc:
            self.send_error(502, f"Proxy bridge error: {exc}")
        finally:
            if upstream is not None:
                try:
                    upstream.close()
                except OSError:
                    pass

    def send_error(self, status: int, message: str) -> None:
        body = message.encode("utf-8", "replace")
        response = (
            f"HTTP/1.1 {status} Error\r\n"
            f"Content-Length: {len(body)}\r\n"
            "Content-Type: text/plain; charset=utf-8\r\n"
            "Connection: close\r\n"
            "\r\n"
        ).encode("ascii") + body
        try:
            self.request.sendall(response)
        except OSError:
            pass


class ThreadingProxy(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Local unauthenticated proxy that forwards through an authenticated HTTP proxy."
    )
    parser.add_argument(
        "--listen",
        default="127.0.0.1:18080",
        help="Local listen address, default: 127.0.0.1:18080",
    )
    parser.add_argument(
        "--upstream",
        default=os.environ.get("DORION_UPSTREAM_PROXY", ""),
        help="Upstream proxy URL, e.g. http://user:pass@host:port",
    )
    args = parser.parse_args()

    if not args.upstream:
        print("Missing upstream proxy. Set DORION_UPSTREAM_PROXY or pass --upstream.", file=sys.stderr)
        return 2

    settings = ProxySettings(args.upstream)
    ProxyHandler.settings = settings

    host, port = parse_listen(args.listen)
    with ThreadingProxy((host, port), ProxyHandler) as server:
        print(f"Proxy bridge listening on http://{host}:{port}", flush=True)
        server.serve_forever()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
