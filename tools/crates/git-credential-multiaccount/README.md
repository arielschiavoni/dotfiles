# git-credential-multiaccount

Git credential helper that picks a personal access token by the remote URL's
org/group segment, so different orgs on the same host can use different
accounts without SSH.

## Setup

Already wired into `config/git/.config/git/config` as git's only credential
helper, for every host:

```gitconfig
[credential]
        helper = multiaccount
        useHttpPath = true
```

Tokens live in gopass at `personal/dotfiles/github-tokens/<org>`, falling back
to `personal/dotfiles/github-tokens/default` when an org has no dedicated
secret. Resolved tokens are cached at `~/.cache/gopass/github-token-<key>`;
`fish_reload` clears that cache.

This replaces `git-credential-cache` entirely, so a host with no gopass entry
at all gets no caching: `store`/`erase` are no-ops, meaning a manually
entered credential for such a host is never remembered and git prompts again
next time.

## Usage

Git invokes `get`/`store`/`erase` automatically (the
[credential helper protocol](https://git-scm.com/docs/gitcredentials)).

`config/fish/.config/fish/conf.d/35-github-token.fish` calls the same
resolution logic directly, to export `$GITHUB_TOKEN` for tools that read it
from the shell (`gh`, scripts, opencode):

```sh
git-credential-multiaccount token <org>
```

## Log

Every request is appended to `$XDG_STATE_HOME/git-credential-multiaccount.log`
(default `~/.local/state/...`) - org requested, cache hit/miss, which secret
answered, and errors. Never the token itself.

```
[2026-01-03 09:12:44] get org=ASG-SONG cache=hit
[2026-01-03 09:13:01] get org=oneaudi cache=miss source=org
[2026-01-03 09:13:20] token org=default cache=miss source=default
[2026-01-03 09:14:05] get org=some-new-org cache=miss error=no-token
[2026-01-03 09:14:10] store noop
```

Works unchanged on the devbox guest (Ubuntu) since it's XDG-based rather than
a macOS-only path like `~/Library/Logs`.
