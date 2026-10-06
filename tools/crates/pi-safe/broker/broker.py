"""pi-safe credential broker: a mitmproxy addon (run by `mitmdump -s`).

The sandbox holds placeholder tokens only and sends its traffic here
(HTTPS_PROXY). For the hosts named in broker.toml the broker opens the TLS
connection, puts the real credential into the request header and forwards
it; every other host is tunnelled untouched. Real tokens live only in this
process.

  github   GitHub token of the sandbox's project org (~/repos/<org>/...),
           else `default`: the gopass keys git and fish use
  oauth    pi's logins (Copilot, Anthropic) from the real auth.json; pi
           itself refreshes them (`pi auth print-bearer-token`)
  header   a static header for host + path prefix (Jira PAT)
  block    requests the sandbox may never make (token exchanges)

pi-safe starts and stops it (`pi-safe --broker ...`) and passes the paths as
`--set pi_safe_*=...`. broker.toml is read at start only.
"""

# No `from __future__ import annotations`: mitmproxy loads scripts under a
# module name missing from sys.modules, which breaks dataclasses with it.
# Python 3.14 (mitmproxy's) evaluates annotations lazily anyway.
import asyncio
import base64
import json
import os
import subprocess
import threading
import time
import urllib.parse
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Self

import tomllib
from mitmproxy import ctx, http, tls

# Host of the broker's own endpoints (pi-safe's health check). Answered here,
# never forwarded.
BROKER_HOST = "pi-safe-broker"
# What the sandbox holds instead of a token; pi-safe sets the same string.
PLACEHOLDER = "pi-safe-broker"
# A login token from auth.json is used while it has this much time left;
# after that pi is asked for a fresh one (pi refreshes at the same point).
MIN_VALIDITY_MS = 5 * 60_000

# --------------------------------------------------------------------------
# Small helpers, unit-tested in broker_test.py
# --------------------------------------------------------------------------


def proxy_user(header: str) -> str | None:
    """Username of a `Proxy-Authorization: Basic ...` header. pi-safe puts the
    project org there (HTTPS_PROXY=http://<org>:pi-safe@...); it is a hint,
    not a credential."""
    scheme, _, value = header.partition(" ")
    if scheme.lower() != "basic":
        return None
    try:
        user = base64.b64decode(value.strip()).decode().partition(":")[0]
    except ValueError:
        return None
    return urllib.parse.unquote(user) or None


def path_matches(path: str, prefix: str) -> bool:
    """`/jira/x` and `/jira` match `/jira/`; `/jiralike` does not."""
    return (
        (prefix or "/") == "/" or path == prefix.rstrip("/") or path.startswith(prefix)
    )


# --------------------------------------------------------------------------
# broker.toml
# --------------------------------------------------------------------------


@dataclass
class HeaderRule:
    name: str
    host: str
    path: str
    header: str
    value: str  # with {secret} where the secret goes
    secret_env: str | None = None
    secret_command: list[str] | None = None


@dataclass
class BlockRule:
    host: str
    path: str


@dataclass
class Rules:
    github_hosts: dict[str, str] = field(default_factory=dict)  # host -> bearer|basic
    github_token_command: list[str] = field(default_factory=list)  # {org}
    oauth_token_command: list[str] = field(default_factory=list)  # {provider}
    headers: list[HeaderRule] = field(default_factory=list)
    blocks: list[BlockRule] = field(default_factory=list)

    @classmethod
    def load(cls, path: Path) -> Self:
        doc = tomllib.loads(path.read_text())
        gh = doc.get("github", {})
        return cls(
            github_hosts=dict(gh.get("hosts", {})),
            github_token_command=list(gh.get("token_command", [])),
            oauth_token_command=list(doc.get("oauth", {}).get("token_command", [])),
            headers=[HeaderRule(**h) for h in doc.get("header", [])],
            blocks=[
                BlockRule(b["host"], b.get("path", "/")) for b in doc.get("block", [])
            ],
        )


# --------------------------------------------------------------------------
# Secrets: commands, pi's logins
# --------------------------------------------------------------------------


def run(cmd: list[str]) -> str:
    """stdout of a secret command (gopass, pi, ...). Runs in $HOME so that it
    never picks up the config of the project the broker was started from."""
    if not cmd:
        raise LookupError("no command configured in broker.toml")
    out = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=60,
        stdin=subprocess.DEVNULL,
        cwd=Path.home(),
        check=False,
    )
    if out.returncode != 0:
        # last stderr line, for the 502 the sandbox sees (no secret in it)
        why = (out.stderr.strip().splitlines() or [""])[-1][:200]
        raise RuntimeError(f"{cmd[0]} exited {out.returncode}: {why}")
    return out.stdout.strip()


# provider in auth.json -> the hosts its token is for
OAUTH_HOSTS = {
    "github-copilot": lambda host: host.endswith(".githubcopilot.com"),
    "anthropic": lambda host: host == "api.anthropic.com",
}


class PiLogins:
    """Tokens of pi's OAuth logins, with the real auth.json as the store
    shared with plain pi. Nothing is cached here: the file is read on every
    request (it is tiny), so a refresh by plain pi is seen at once."""

    def __init__(self, auth: Path):
        self.auth = auth
        self._lock = threading.Lock()  # concurrent requests: one pi refresh

    def token(self, provider: str, command: list[str]) -> str:
        with self._lock:
            # fast path: the stored token still has time left
            try:
                entry = json.loads(self.auth.read_text() or "{}").get(provider)
            except FileNotFoundError:
                entry = None
            now = time.time() * 1000
            if (
                isinstance(entry, dict)
                and entry.get("type") == "oauth"
                and entry.get("expires", 0) > now + MIN_VALIDITY_MS
            ):
                return entry["access"]
            # about to expire (every few hours): pi refreshes it under its own
            # lock, saves it to auth.json and prints it. Not logged in: pi
            # fails, and its message ends up in the 502.
            token = run([a.replace("{provider}", provider) for a in command])
            log_event({"event": "refresh", "provider": provider})
            return token

    def copilot_github_token(self) -> str:
        """The GitHub OAuth token of pi's Copilot login (`refresh`; it does not
        expire): the account whose subscription the model requests use."""
        try:
            entry = json.loads(self.auth.read_text() or "{}").get("github-copilot")
        except FileNotFoundError:
            entry = None
        if not (isinstance(entry, dict) and entry.get("refresh")):
            raise LookupError("no github-copilot login in auth.json - /login in pi")
        return entry["refresh"]


# --------------------------------------------------------------------------
# Log: requests.jsonl in the state dir, one line per brokered request
# --------------------------------------------------------------------------

LOG_PATH: Path | None = None


def log_event(record: dict) -> None:
    if LOG_PATH is None:
        return
    record = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), **record}
    with LOG_PATH.open("a") as f:
        f.write(json.dumps(record) + "\n")


# --------------------------------------------------------------------------
# The addon: mitmproxy calls these methods (hooks) for every connection and
# request; see https://docs.mitmproxy.org/stable/api/events.html
# --------------------------------------------------------------------------


class Broker:
    def __init__(self) -> None:
        self.rules = Rules()
        self.logins: PiLogins | None = None
        self.started = time.time()
        self._tokens: dict[str, str] = {}  # "github:<key>" / "header:<name>" -> secret
        self._hints: dict[str, str] = {}  # client connection id -> project org

    # -- options: pi-safe passes them as `--set pi_safe_*=...` ----------------

    def load(self, loader: Any) -> None:
        loader.add_option("pi_safe_rules", str, "", "broker rules file (TOML)")
        loader.add_option("pi_safe_auth", str, "", "pi's real auth.json")
        loader.add_option("pi_safe_state", str, "", "broker state dir (log)")

    def configure(self, updated: set[str]) -> None:
        global LOG_PATH
        if "pi_safe_rules" in updated and ctx.options.pi_safe_rules:
            self.rules = Rules.load(Path(ctx.options.pi_safe_rules))
        if "pi_safe_auth" in updated and ctx.options.pi_safe_auth:
            self.logins = PiLogins(Path(ctx.options.pi_safe_auth))
        if "pi_safe_state" in updated and ctx.options.pi_safe_state:
            LOG_PATH = Path(ctx.options.pi_safe_state) / "requests.jsonl"

    # -- 1. TLS: decrypt only the hosts with a rule ---------------------------

    def intercepted(self, host: str) -> bool:
        r = self.rules
        return (
            host in r.github_hosts
            or any(h.host == host for h in r.headers)
            or any(b.host == host for b in r.blocks)
            or any(match(host) for match in OAUTH_HOSTS.values())
        )

    def tls_clienthello(self, data: tls.ClientHelloData) -> None:
        # Called when the client starts TLS inside the CONNECT tunnel. Any
        # other host is passed through encrypted: its certificate is the real
        # one, and the broker never sees its traffic.
        host = data.client_hello.sni or (data.context.server.address or ("",))[0]
        if not self.intercepted(host):
            data.ignore_connection = True

    # -- 2. CONNECT: remember the project org of the connection ---------------

    def http_connect(self, flow: http.HTTPFlow) -> None:
        # The proxy username comes with the CONNECT only; the requests inside
        # the tunnel share its client connection, so it is keyed by that.
        if user := proxy_user(flow.request.headers.get("Proxy-Authorization", "")):
            self._hints[flow.client_conn.id] = user

    def client_disconnected(self, client: Any) -> None:
        self._hints.pop(client.id, None)

    # -- 3. requests: answer, block, or add the credential --------------------

    async def request(self, flow: http.HTTPFlow) -> None:
        # async: token lookups run commands, and must not stall the proxy
        req = flow.request
        hint = self._hints.get(flow.client_conn.id)
        # plain-HTTP requests carry the proxy header themselves; never forward it
        if auth := req.headers.pop("Proxy-Authorization", None):
            hint = proxy_user(auth) or hint
        host = req.pretty_host

        if host == BROKER_HOST:
            flow.response = self.own_endpoint(req.path)
            return
        for b in self.rules.blocks:
            if b.host == host and path_matches(req.path, b.path):
                flow.metadata["pi_safe"] = {"rule": "block"}
                flow.response = deny(
                    403, f"blocked by the pi-safe broker ({host}{b.path})"
                )
                return
        if req.scheme != "https":  # never put a token on a plaintext connection
            return

        try:
            await self.inject(flow, host, hint)
        except Exception as e:  # noqa: BLE001 - no token: tell the client why
            flow.response = deny(502, f"pi-safe broker: {e}")

    async def inject(self, flow: http.HTTPFlow, host: str, hint: str | None) -> None:
        """Replaces the auth header (the sandbox sent a placeholder, or none)
        with the real credential of the first rule matching the request."""
        req = flow.request

        # pi's logins (model requests)
        for provider, match in OAUTH_HOSTS.items():
            if match(host) and self.logins:
                token = await asyncio.to_thread(
                    self.logins.token, provider, self.rules.oauth_token_command
                )
                req.headers["Authorization"] = f"Bearer {token}"
                req.headers.pop("x-api-key", None)
                flow.metadata["pi_safe"] = {"rule": provider}
                return

        # Copilot plan and quotas (/copilot_internal/user, pi-quotas): the
        # account of pi's Copilot login, which the model requests above are
        # charged to - not the project's GitHub token, which may belong to
        # another Copilot account. (The token exchange there is blocked.)
        if (
            host == "api.github.com"
            and path_matches(req.path, "/copilot_internal/")
            and self.logins
        ):
            token = await asyncio.to_thread(self.logins.copilot_github_token)
            req.headers["Authorization"] = f"Bearer {token}"
            flow.metadata["pi_safe"] = {"rule": "github-copilot", "key": "login"}
            return

        # GitHub: the token of the project's org. An org without a token of
        # its own gets `default` from the token command (gopass fallback).
        if scheme := self.rules.github_hosts.get(host):
            key = hint or "default"
            token = await asyncio.to_thread(self.github_token, key)
            if scheme == "basic":  # git over HTTPS
                basic = base64.b64encode(f"x-access-token:{token}".encode()).decode()
                req.headers["Authorization"] = f"Basic {basic}"
            else:
                req.headers["Authorization"] = f"Bearer {token}"
            flow.metadata["pi_safe"] = {
                "rule": "github",
                "key": key,
                "cache": f"github:{key}",
            }
            return

        # static headers (Jira, ...)
        for h in self.rules.headers:
            if h.host == host and path_matches(req.path, h.path):
                secret = await asyncio.to_thread(self.header_secret, h)
                req.headers[h.header] = h.value.replace("{secret}", secret)
                flow.metadata["pi_safe"] = {"rule": h.name, "cache": f"header:{h.name}"}
                return

    def own_endpoint(self, path: str) -> http.Response:
        if path.startswith("/health"):  # pi-safe: is a broker running, which pid
            body = {
                "pid": os.getpid(),
                "started": int(self.started),
                "rules": ctx.options.pi_safe_rules,
            }
            return http.Response.make(
                200, json.dumps(body), {"Content-Type": "application/json"}
            )
        return deny(404, "unknown pi-safe broker endpoint")

    # -- secrets: read once, then kept in memory ------------------------------

    def github_token(self, key: str) -> str:
        cache = f"github:{key}"
        if cache not in self._tokens:
            cmd = [a.replace("{org}", key) for a in self.rules.github_token_command]
            value = run(cmd)
            if not value:
                raise LookupError(f"empty token from {cmd[0]} for '{key}'")
            self._tokens[cache] = value
        return self._tokens[cache]

    def header_secret(self, h: HeaderRule) -> str:
        cache = f"header:{h.name}"
        if cache not in self._tokens:
            if h.secret_command:
                value = run(h.secret_command)
            else:
                value = os.environ.get(h.secret_env or "", "")
            # the placeholder: the broker was started from inside a sandbox
            if not value or value == PLACEHOLDER:
                src = h.secret_env or " ".join(h.secret_command or [])
                raise LookupError(
                    f"no secret for rule '{h.name}' ({src}) - "
                    "restart the broker from a shell that has it"
                )
            self._tokens[cache] = value
        return self._tokens[cache]

    # -- 4. responses: passed on as they come, only logged --------------------

    def responseheaders(self, flow: http.HTTPFlow) -> None:
        # Stream every body instead of buffering it: model output arrives
        # token by token, and nothing here reads the body anyway.
        flow.response.stream = True

    def response(self, flow: http.HTTPFlow) -> None:
        meta = flow.metadata.get("pi_safe")
        if not meta:
            return
        # 401: the token may have been rotated; read it again next time
        if flow.response.status_code == 401 and (cache := meta.get("cache")):
            self._tokens.pop(cache, None)
        self.log(flow, flow.response.status_code)

    def error(self, flow: http.HTTPFlow) -> None:
        if flow.metadata.get("pi_safe"):
            self.log(flow, None, str(flow.error))

    def log(
        self, flow: http.HTTPFlow, status: int | None, error: str | None = None
    ) -> None:
        """No headers, bodies or query strings: they may carry secrets."""
        meta = flow.metadata.get("pi_safe", {})
        record = {
            "rule": meta.get("rule"),
            "key": meta.get("key"),
            "method": flow.request.method,
            "host": flow.request.pretty_host,
            "path": flow.request.path.split("?", 1)[0],
            "status": status,
        }
        if error:
            record["error"] = error
        log_event(record)


def deny(status: int, message: str) -> http.Response:
    return http.Response.make(
        status, json.dumps({"message": message}), {"Content-Type": "application/json"}
    )


addons = [Broker()]
