# cred-broker

An HTTP proxy on `127.0.0.1` that puts the real credentials into the requests
of sandboxed agents, which only hold placeholders. A token inside a sandbox
could be sent anywhere by a prompt-injected agent; a token in this process
cannot. Its client is [pi-safe](../pi-safe), which starts it on demand.

```
sandbox: HTTPS_PROXY=127.0.0.1:18080 ──▶ cred-broker (VM)
  GitHub hosts          token of the project's org (gopass, git-credential-multiaccount)
  Jira                  PAT from gopass
  Copilot, Anthropic    pi's real auth.json; pi refreshes it
  token exchanges       blocked (403)
  everything else       tunnelled, not decrypted
```

## Usage

```sh
cred-broker start     # in the background, unless it runs (pi-safe does this)
cred-broker stop      # its tokens are dropped from memory
cred-broker restart   # after editing the config, or reinstalling
cred-broker status    # pid and file paths; exit 1 if not running
cred-broker status --json   # the same for clients (pi-safe)
cred-broker serve     # in the foreground, e.g. to watch its errors
```

Config: `~/.config/cred-broker/config.toml` (`config/cred-broker` in the
dotfiles): the port, which credential goes to which host, and where it is read
from. No secrets in it. It is read at start only.

## How it works

A sandbox sends `CONNECT api.github.com:443` with the project's org as the
proxy username (`HTTPS_PROXY=http://<org>:pi-safe@127.0.0.1:18080`).

- **A host without a rule** is tunnelled: bytes are copied both ways, its TLS
  is never opened.
- **A host with a rule** is intercepted: the broker answers the TLS with a
  certificate for that host, signed by its own CA (`ca.pem` in the state dir,
  created once; pi-safe adds it to the sandbox's CA bundle). It then reads
  each request, replaces the placeholder with the real credential and sends
  it to the real host. The response streams back unchanged.

Credentials:

- **GitHub**: the token of the project's org (`~/repos/<org>/...`), else
  `default`, for every GitHub request - also ones about another org's repos.
- **pi's logins** stay in the real `auth.json`. The broker uses the stored
  token; when it has under 5 minutes left (Copilot ~24h, Anthropic ~8h), it
  runs `pi auth print-bearer-token`, so pi refreshes and saves it under its
  own lock - one login for plain pi and the broker. Copilot credits, and
  Copilot's quota info (`/copilot_internal/user`), always come from this
  login, whatever the project's GitHub token.
- Secrets are read once and kept in memory; a 401 drops them, so a rotated
  one is read again.

It prevents token *theft*, not *use*: an agent can still do what the tokens
allow, through the broker. Keep them narrow.

## Files

In `~/.local/state/cred-broker/`:

- `requests.jsonl` - one line per brokered request: rule, org, method, host,
  path, status. Never headers, bodies or query strings.
  `tail -f ~/.local/state/cred-broker/requests.jsonl | jq -c .`
- `broker.log` - its own errors, e.g. a client that rejects its certificate.
- `ca.pem`, `ca-key.pem` (0600) - the CA.

## Code

`src/`, in the order a request meets it: `proxy.rs` (CONNECT, tunnel or
intercept, forward), `config.rs` (config.toml, and which rule a request falls
under), `secrets.rs` (gopass, pi, env), `ca.rs` (the certificates),
`daemon.rs` (start, stop, status), `main.rs` (the CLI).

Tests: `cargo test -p cred-broker` - the rules, the secret sources, the CA,
and a proxy that intercepts TLS end to end. Against the real hosts:
`pi-safe --check`.
