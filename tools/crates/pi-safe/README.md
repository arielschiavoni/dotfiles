# pi-safe

Runs the [pi](https://pi.dev) coding agent inside a sandbox on the devbox VM,
so it can work on one project without reaching your secrets, Docker or the
rest of the machine. Your normal shell keeps full access.

```
devbox VM
├── your shell            full access
└── pi-safe → pasta → bwrap → pi
    ├── project/          read-write (.git read-only: no commits, no hooks)
    ├── ~/repos           read-only, for context from other projects
    ├── ~/share           invisible (may hold sensitive files), except
    │                     screenshots/ and agent/: read-only, for handing files over
    ├── secrets           empty: untracked .env, .env.*, keys, tfvars ... in
    │                     the project and ~/repos (committed ones stay)
    ├── /usr, /etc, mise  read-only
    ├── ~/.pi/agent       shared with plain pi: settings, trust, sessions
    │                     read-write; extensions, packages, mcp.json read-only;
    │                     auth.json is a copy without tokens (broker)
    ├── ~/.ssh ~/.aws ~/.gnupg ~/.docker ...      invisible
    ├── /run (docker.sock, ssh/gpg agent, bus)    invisible
    ├── tmux socket, other processes, secret env  invisible
    └── network           internet yes, the VM's localhost no (unless allowed)
                          via the credential broker, cred-broker (127.0.0.1:18080)
```

## Usage

```sh
pi-safe                       # pi, sandboxed, in the current git repo
pi-safe -p "explain src/"     # anything after the options goes to pi
pi-safe -- --help             # pi's own help
pi-safe --port 5432           # also allow the VM's localhost:5432
pi-safe --publish 3000        # expose a dev server started inside on the VM
pi-safe --shell               # bash in the same sandbox, to look around
pi-safe --check               # leak tests inside the sandbox (exit 1 on a leak)
pi-safe --dry-run             # print the plan and the full command
```

tmux: `prefix o s` opens it in a split (`prefix o p` is the unsandboxed pi);
`prefix o f` picks files in `~/share/screenshots` and `~/share/agent` with fzf
and types them into the prompt as `@mentions` - the
sandbox's stand-in for clipboard image paste; `prefix o r` does the same for a
file from another repo in `~/repos`.

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
| `filesystem.hidden` | paths or globs shown empty (default: env files, keys, Terraform vars/state in `~/repos`; glob matches git tracks stay visible) |
| `filesystem.project_read_only` | project paths kept read-only (`.git`) |
| `pi.shared` / `pi.local` | agent-dir entries shared with, or kept from, the real pi (`mcp-auth.json` is local: MCP logins of plain pi stay outside) |
| `env.pass` / `env.set` | the environment allowlist |
| `deny_projects` | dirs that may never be the writable project |
| `broker.enabled` | route the sandbox through the credential broker (cred-broker) |
| `broker.providers` | pi logins the broker serves (`github-copilot`, `anthropic`) |
| `broker.placeholder_env` | variables set to the placeholder (`GITHUB_TOKEN`, `JIRA_PAT_TOKEN`) |

The broker's own settings - port, which credential goes to which host - are
in `~/.config/cred-broker/config.toml`.

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

- A mount needs an exact path, so `hidden` globs are resolved by a walk of
  ~/repos on every start, one pass for all globs (.git, node_modules and
  build/cache dirs such as target, dist, .venv skipped - see `SKIP_DIRS` in
  `src/hide.rs`, so a secret inside one of them is not hidden), then one
  `git ls-files` per repo with matches. ~25ms over a 12 GB ~/repos. Files
  created while the sandbox runs are not hidden.
- Glob matches git tracks stay visible: their content is in `.git`, which
  the sandbox reads anyway, and committed `.env.aws.dev` or `.env.example`
  files are config the agent needs. Hidden is what git does not track -
  gitignored, or not ignored yet (failing closed).
- `/tmp` is a fresh tmpfs, except `/tmp/jiti` and `/tmp/node-compile-cache`,
  which persist in `~/.local/state/pi-safe/tmp-cache`. Without the jiti
  cache pi re-transpiles its TypeScript extensions on every start (~2.2s
  instead of ~0.5s). They are never shared with the host's `/tmp`, so plain
  pi never loads code compiled inside the sandbox.
- `hidden` is a list of known names, not "everything gitignored" (that
  would also cover build output and node_modules: thousands of mounts).
  Secrets under other names - `.npmrc` tokens, `credentials.json` - stay
  readable unless you add globs for them; `.npmrc` is left out because
  committed ones only configure the registry.
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
without tokens), and [cred-broker](../cred-broker), a proxy on the VM, puts
the real credential into each request on the way out. One broker serves all
sandboxes; pi-safe starts it when it is not running (`cred-broker start`), and
it outlives the pane.

pi-safe's part is the sandbox's side of it:

- `HTTPS_PROXY` & co pointing at the broker, with the project's org as the
  proxy username - it picks the org's GitHub token. git is told to always
  send it (`http.proxyAuthMethod=basic`), and its credential helper is off.
- The broker's CA, added to a copy of the system CA bundle mounted over
  `/etc/ssl/certs/ca-certificates.crt`, so curl, git, gh and node trust it.
- An `auth.json` with placeholder logins that never expire, so pi inside never
  tries to refresh; the real one is hidden. `/login` only works in plain pi.
- The broker's port in the sandbox's localhost allowlist; its port and CA
  come from `cred-broker status --json`.
- AWS, when the broker serves profiles (`[aws]` in its config): a sandbox
  `~/.aws/config` with only those profiles, whose `credential_process` is
  this binary (`/run/pi-safe __aws-credentials <port> <profile>`), asking the
  broker. The real `~/.aws`, with its SSO token, stays outside.
  `PI_SAFE_AWS_PROFILES` lists them for the `aws-profile` pi extension: the
  agent's first `aws` command asks you which profile to use and sets
  `AWS_PROFILE`; `/aws-profile` switches. See
  [cred-broker](../cred-broker#aws) for the logins.

`pi-safe --check` verifies it end to end: no token in env or `auth.json`,
GitHub, Copilot and Anthropic authenticated, the Copilot token exchange
blocked. Manage the broker with `cred-broker start|stop|restart|status`.
