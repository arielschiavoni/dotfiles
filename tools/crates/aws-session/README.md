# aws-session

AWS SSO logins: pick a profile, check how long its login lasts, log in when
it has ended, and print its credentials. It reads `~/.aws/config` itself, in
microseconds (`aws configure get` starts Python, ~0.3s per key). Used by `functions/aws_login.fish` (interactively) and by
[cred-broker](../cred-broker) (in the background, for pi-safe sandboxes).

```
aws-session pick [--filter GLOB]    # fzf over ~/.aws/config, prints the profile
aws-session ensure <profile>        # credentials, logging in when needed
aws-session status <profile>        # time left on both clocks
aws-session credentials <profile>   # credential_process JSON
aws-session login <profile>
```

Exit `0` ok, `1` an expected "no" (an SSO login is needed, nothing was
chosen), `2` a failure.

`aws_login.fish` is `pick`, `ensure`, then `set -gx AWS_PROFILE`, which the
shell does itself: only it can set its variables. `aws_login --filter '*.agent'`
narrows the list.

## When a login is needed

Two clocks have to agree before an AWS call succeeds:

- `~/.aws/sso/cache` - the SSO access token (~1h). The CLI renews it silently
  with its refresh token until the SSO session itself ends (~8h, set in IAM
  Identity Center); only then does it take the browser.
- `~/.aws/cli/cache` - the assumed-role credentials (1–4h; 1h for a chained
  role, `source_profile` + `role_arn`), renewed from the SSO token.

So `credentials` and `ensure` ask the CLI first (`aws configure
export-credentials`, which renews both as needed). A login is needed (exit 1)
when that fails and the SSO access token has expired. Any other failure - a
denied role, the network - is reported with the CLI's reason (exit 2).

`ensure` also logs in when the CLI succeeds but the SSO access token has
expired: the CLI then serves role credentials from `~/.aws/cli/cache`, while
the SDKs (a `tsx` script, Terraform) read `~/.aws/sso/cache` only.

`login` runs `aws sso login --sso-session <session>` (or `--profile <root>`
for a legacy SSO profile without one), which opens the browser.

`~/.aws/config` is parsed here (`src/config.rs`): sections, comments, nested
values skipped, and the `source_profile` chain for `sso_session`, `region`
and the root profile. Profiles of `~/.aws/credentials` are listed too, as
`aws configure list-profiles` does; only their names are read.

## Library

cred-broker and pi-safe use the crate as a library: `config::AwsConfig` (the
profiles and their chain), `glob::matches` (`*.agent` - `*` crosses dots) and
`session::sso_valid`.

## Log

`status` (and so `ensure`) appends one key=value line to
`$XDG_STATE_HOME/aws-session.log` (default `~/.local/state/aws-session.log`):

```
sso_session=x sso_entries=1 sso=7h59m role=Admin iam_entries=1 iam=2h30m result=ok
sso_session=x sso_entries=1 sso=expired result=expired
sso_session=x sso_entries=0 sso=expired result=expired
sso_session=x sso=no-start-url result=expired
```

stdout says only "SSO token expired" for every failure, so the log is where the
three causes separate: the `sso-session` name is not in `~/.aws/config`
(`no-start-url`), no cached token matches its start URL (`sso_entries=0`), or a
token is there and out of date (`sso_entries=1`). `iam_entries` does the same
for the role credentials.

Roles are logged by name, which keeps account IDs out of the file. Logging is
best effort: a write error is ignored.

An unreadable cache entry counts as "no usable session": the caches are
written by the AWS CLI in an undocumented format.

`cargo test -p aws-session` covers the config parser, the globs and the
clocks against scratch directories.
