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
  http://cred-broker/aws/<profile>   AWS credentials of a read-only profile (see below)
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

Placeholders, each replaced only in its own field:

| Placeholder  | Field                    | Replaced with                                                                                       |
| ------------ | ------------------------ | --------------------------------------------------------------------------------------------------- |
| `{org}`      | `[github] token_command` | the project's org (the sandbox sends it as the proxy username: `~/repos/<org>/...`), else `default` |
| `{provider}` | `[oauth] token_command`  | the pi login: `github-copilot`, `anthropic`                                                         |
| `{secret}`   | `[[header]] value`       | the rule's secret, from `secret_command` (stdout) or `secret_env`                                   |

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

It prevents token _theft_, not _use_: an agent can still do what the tokens
allow, through the broker. Keep them narrow.

## AWS

AWS clients sign every request themselves (SigV4), so the sandbox holds real
credentials: the short-lived role credentials of the profiles in `[aws]
profiles` (`*.agent`: read-only roles, 1h each). The SSO token they are made
from stays in the broker's environment - it makes credentials for every
profile, admin ones included.

```
sandbox aws ──▶ credential_process (pi-safe __aws-credentials)
            ──▶ GET http://cred-broker/aws/renderer.dev.agent
                  not in [aws] profiles        403
                  cached, > 5 min left         those
                  aws-session credentials      renews silently while the SSO session lasts
                  exit 1: SSO session ended    aws-session login --device-code --notify,
                                               waits for the approval, then credentials
```

- pi-safe writes the sandbox's `~/.aws/config` with the served profiles
  (`aws_profiles` in `status --json`: `[aws] profiles` found in
  `~/.aws/config`), each with the broker as its `credential_process`. The
  AWS CLI asks again whenever its credentials are about to expire, so a
  session outlives the 1h.
- The login is the device code flow: the Mac's browser opens on the approval
  page (devbox-bridge's `xdg-open`) and tmux shows the code to compare. The
  sandbox's request waits for it, up to 5 minutes. It needs the broker to
  have been started from inside tmux or with tmux on its `PATH`.
- One fetch at a time: parallel requests wait and find the cache filled, so
  one login serves them all. After a login that was not approved, the next
  one starts 5 minutes later (the error says when); `aws_login` outside the
  sandbox makes credentials available right away.
- Anything in a sandbox can trigger a login prompt this way, and each one
  takes your approval: approve the ones you started.

requests.jsonl gets `"rule":"aws"` lines with the profile and `via`: `cache`,
`command` or `login`. The commands are in `[aws]` of the config, with
`{profile}` as the placeholder.

## Adding a credential (example: an MCP server)

The pattern: the tool reads the secret from an env var; inside the sandbox
that var holds a placeholder, and a `[[header]]` rule puts the real value into
the request. Example: an API key for the context7 MCP server.

1. **Store the secret** in gopass:

   ```sh
   gopass insert personal/dotfiles/context7/API_KEY
   ```

2. **Reference it as an env var** in `~/.pi/agent/mcp.json`, never as a value:

   ```json
   "context7": {
     "url": "https://mcp.context7.com/mcp",
     "headers": { "Authorization": "Bearer ${CONTEXT7_API_KEY}" }
   }
   ```

   The sandbox can read `mcp.json` (it is mounted read-only), so a literal key
   there would leak; a `!gopass ...` command would run inside the sandbox,
   where there is no gopass.

3. **Give the sandbox a placeholder** for it, in
   `~/.config/pi-safe/config.toml` (the list replaces the default, so keep its
   entries):

   ```toml
   [broker]
   placeholder_env = ["GITHUB_TOKEN", "JIRA_PAT_TOKEN", "CONTEXT7_API_KEY"]
   ```

   The sandbox starts from an empty environment, so without this the
   variable is unset there and pi sends no header.

4. **Add the rule** to `~/.config/cred-broker/config.toml`. It replaces the
   header, whatever the sandbox sent in it:

   ```toml
   [[header]]
   name = "context7"
   host = "mcp.context7.com"
   path = "/"
   header = "Authorization"
   value = "Bearer {secret}"
   secret_command = ["gopass", "show", "--password", "personal/dotfiles/context7/API_KEY"]
   ```

   The host of a rule is decrypted from now on; every other host stays
   tunnelled.

   **Or take the secret from the broker's environment** instead of a command:

   ```toml
   [[header]]
   name = "context7"
   host = "mcp.context7.com"
   path = "/"
   header = "Authorization"
   value = "Bearer {secret}"
   secret_env = "CONTEXT7_API_KEY"   # read from cred-broker's own env, on the VM
   ```

   That is the environment of whatever started the broker: your shell for
   `cred-broker start`/`restart`, or the shell you ran `pi-safe` in when
   pi-safe starts it. So the variable must be set there, e.g.
   `CONTEXT7_API_KEY=... cred-broker restart`, or exported by fish. It is read
   on first use and kept: after changing it, `cred-broker restart`. Unset or
   empty, requests to the host get a 502 naming the rule. With both set,
   `secret_command` wins.

5. **Restart and check**: `cred-broker restart`, start a sandbox and use the
   server. `requests.jsonl` should show `"rule":"context7"` with status 200.
   A `502` carries the reason in its body (e.g. the gopass error).

Notes:

- Plain pi does not use the broker: it needs the real `CONTEXT7_API_KEY` in
  its environment (e.g. exported by fish from gopass).
- A stdio server (`command` + `env`) works the same way if the process makes
  its HTTPS calls through `HTTPS_PROXY` (curl, Go, Python, Node with
  `NODE_USE_ENV_PROXY=1`, which pi-safe sets). Make the rule match the API
  host it calls, not the MCP server.
- Keep `mcp-auth.json` empty: it holds tokens of MCP OAuth logins, and those
  are not brokered. Configure servers with headers and env vars instead.

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
under), `secrets.rs` (gopass, pi, env), `aws.rs` (AWS credentials, logins),
`ca.rs` (the certificates),
`daemon.rs` (start, stop, status), `main.rs` (the CLI).

Tests: `cargo test -p cred-broker` - the rules, the secret sources, the CA,
and a proxy that intercepts TLS end to end. Against the real hosts:
`pi-safe --check`.
