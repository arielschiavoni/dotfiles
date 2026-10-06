# pi-safe

Runs the [pi](https://pi.dev) coding agent inside a sandbox on the devbox VM,
so it can work on one project without reaching your secrets, Docker or the
rest of the machine. Your normal shell keeps full access.

```
devbox VM
├── your shell            full access
└── pi-safe → pasta → bwrap → pi
    ├── project/          read-write (.git read-only: no commits, no hooks)
    ├── ~/repos, ~/share  invisible; read-only with --context
    ├── .env files        empty (project, and ~/repos + ~/share with --context)
    ├── /usr, /etc, mise  read-only
    ├── ~/.pi/agent       shared with plain pi: settings, trust, sessions
    │                     read-write; extensions, packages, mcp.json read-only;
    │                     auth.json is a copy without tokens (broker)
    ├── ~/.ssh ~/.aws ~/.gnupg ~/.docker ...      invisible
    ├── /run (docker.sock, ssh/gpg agent, bus)    invisible
    ├── tmux socket, other processes, secret env  invisible
    └── network           internet yes, the VM's localhost no (unless allowed)
                          via the credential broker (127.0.0.1:18080)
```

## Usage

```sh
pi-safe                       # pi, sandboxed, in the current git repo
pi-safe --context             # also ~/repos and ~/share, read-only
pi-safe -p "explain src/"     # anything after the options goes to pi
pi-safe -- --help             # pi's own help
pi-safe --port 5432           # also allow the VM's localhost:5432
pi-safe --publish 3000        # expose a dev server started inside on the VM
pi-safe --shell               # bash in the same sandbox, to look around
pi-safe --check               # leak tests inside the sandbox (exit 1 on a leak)
pi-safe --dry-run             # print the plan and the full command
pi-safe --broker status       # credential broker: start|stop|restart|status
```

tmux: `prefix o s` opens it in a split, `prefix o S` with `--context`
(`prefix o p` is the unsandboxed pi). To add context mid-session, quit and
resume with `pi-safe --context -c` (pi's continue-last-session).

Exit codes: pi's own; `1` for a refused directory or a failed `--check`; `2`
when pi-safe itself fails.

## Config

`~/.config/pi-safe/config.toml`, stowed from `config/pi-safe/`. That file
documents every key with its default; the important ones:

| key | purpose |
|---|---|
| `network.mode` | `pasta` (default), `host` (unsafe), `none` |
| `network.host_ports` | VM localhost ports reachable from inside |
| `network.publish_ports` | sandbox ports published on the VM |
| `filesystem.read_only` / `read_write` | extra visible trees |
| `filesystem.context` | trees added read-only by `--context` (`~/repos`, `~/share`) |
| `filesystem.hidden` | paths or globs shown empty (default: every `.env` in `~/repos`, `~/share`) |
| `filesystem.project_read_only` | project paths kept read-only (`.git`) |
| `pi.shared` / `pi.local` | agent-dir entries shared with, or kept from, the real pi |
| `env.pass` / `env.set` | the environment allowlist |
| `deny_projects` | dirs that may never be the writable project |
| `broker.enabled` | route the sandbox through the credential broker |
| `broker.providers` | pi logins the broker serves (`github-copilot`, `anthropic`) |
| `broker.placeholder_env` | variables set to the placeholder (`GITHUB_TOKEN`, `JIRA_PAT_TOKEN`) |

The broker's rules - which credential goes to which host - are in
`~/.config/pi-safe/broker.toml`, next to the config.

Config is never read from the project: a cloned repo must not be able to
widen its own sandbox.

The dotfiles repo is a project like any other: writable when it is the
project, read-only otherwise. That includes this config and pi's agent dir,
which are stowed symlinks into its working tree - an edit there is live on
the next run, so review `git diff` before starting pi-safe again.

## How it works

pi-safe only builds the plan; the isolation is done by two external tools it
`exec`s: [pasta](https://passt.top) (user-mode networking) wrapping
[bubblewrap](https://github.com/containers/bubblewrap) (namespaces + mounts).

Why not a Rust crate such as `hakoniwa`? Ubuntu 26.04 sets
`kernel.apparmor_restrict_unprivileged_userns=1`: a normal binary cannot
create a usable user namespace (`unshare -Urm` fails). bwrap and pasta ship
with AppArmor profiles that allow it. An in-process sandbox would need either
that sysctl turned off VM-wide or a profile granting the permission to a
user-writable `~/.cargo/bin/pi-safe` - both weaker. There is no mature Rust
replacement for pasta at all (hakoniwa itself shells out to it).

The mount order is the security model; see the comment at the top of
`src/sandbox.rs`. In short: system dirs read-only, a sandbox-only `$HOME`
(`~/.local/state/pi-safe/home`), configured trees, pi's agent dir, the project,
then empty files and dirs over hidden paths.

Things to know:

- A mount needs an exact path, so `hidden` globs are resolved by a walk on
  every start (~0.1s; node_modules and .git skipped). Files created while
  the sandbox runs are not hidden.
- `/tmp` is a fresh tmpfs, except `/tmp/jiti` and `/tmp/node-compile-cache`,
  which persist in `~/.local/state/pi-safe/tmp-cache`. Without the jiti
  cache pi re-transpiles its TypeScript extensions on every start (~2.2s
  instead of ~0.5s). They are never shared with the host's `/tmp`, so plain
  pi never loads code compiled inside the sandbox.
- Only files named exactly `.env` are hidden by default; `.env.aws.dev`,
  `.npmrc` tokens etc. stay readable unless you add globs for them.
- One pi config for both: `/settings`, `/model` and `/trust` inside the
  sandbox write the same files plain pi reads (`/login` too, with the broker
  off). That also means a
  prompt-injected agent in *any* project could add a package to
  `settings.json` or trust a repo, and plain pi would act on it next start.
- With the broker off, `auth.json` (pi's provider logins) is readable inside
  the sandbox, and `gh`, private git fetches and the Jira skill do not work.
- Private npm installs do not work (`.npmrc` tokens are not brokered).
- The Mac stays reachable through the VM's gateway; only the VM's own
  localhost is blocked.

## Credential broker

A token in the sandbox could be sent anywhere by a prompt-injected agent. So
the sandbox holds placeholders (`GITHUB_TOKEN=pi-safe-broker`, an `auth.json`
without tokens), and a [mitmproxy](https://mitmproxy.org) on the VM puts the
real credential into each request on the way out:

```
sandbox: HTTPS_PROXY=127.0.0.1:18080 ──▶ mitmdump -s broker/broker.py (VM)
  GitHub hosts          token per org (gopass, via git-credential-multiaccount)
  Jira                  PAT from gopass
  Copilot, Anthropic    pi's real auth.json; pi refreshes it
  token exchanges       blocked (403)
  everything else       tunnelled, not decrypted
```

Rules and token sources: `~/.config/pi-safe/broker.toml`.

- **One broker for all sandboxes**, started by pi-safe when none answers on
  the port; it outlives the pane. It reads `broker.py` and `broker.toml` at
  start, so after editing either: `pi-safe --broker restart`. `broker.py`
  runs from the dotfiles working tree - review `git diff` before a restart
  (a sandbox on the dotfiles repo can edit it).
- **GitHub token by project:** the token of the project's org
  (`~/repos/<org>/...`), else `default` - for every GitHub request, also
  ones about another org's repos.
- **pi's logins** stay in the real `auth.json`, hidden from the sandbox. The
  broker uses the token stored there; when it has under 5 minutes left
  (Copilot lasts ~24h, Anthropic ~8h), it runs
  `pi auth print-bearer-token`, so pi refreshes and saves it under its own
  lock - one login for plain pi and the broker. `/login` only works in plain
  pi. Copilot credits always come from this login, whichever org's GitHub
  token the project uses; so does Copilot's quota info (`/copilot_internal/user`).
- **Logs** (`pi-safe --broker status`): `requests.jsonl` - rule, org,
  method, host, path, status, never headers or bodies; `mitmdump.log`.
- The broker prevents token *theft*, not *use*: the agent can still do what
  the tokens allow. Keep them narrow.
- Tests: `pi-safe --check` end to end; the addon's with
  `"$(dirname "$(readlink -f "$(mise which mitmdump)")")/python" -m unittest
  tools/crates/pi-safe/broker/broker_test.py`.
