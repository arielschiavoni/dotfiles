# aws-session

How much time is left on the current AWS login. Called by
`functions/aws_login.fish`, replacing a Python script of the same shape.

```
aws-session <role_arn> <sso_role_name> <sso_session>   # args may be empty
```

Two clocks have to agree before an AWS call succeeds, and they expire at
different times:

- `~/.aws/sso/cache` — the SSO access token (~8h), matched by `sso_start_url`
- `~/.aws/cli/cache` — the assumed-role credentials (1–4h), matched by role

Exit 0 means logged in, with the remaining time on stdout. Exit 1 means the SSO
token is missing or expired and the caller should run `aws sso login`.
`aws_login.fish` branches on both.

Every parse failure is skipped rather than reported: these caches are written
by the AWS CLI in an undocumented format, so an unreadable entry means "no
usable session", not "this tool is broken".

## Log

One key=value line per invocation, appended to
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

Roles are logged by name rather than ARN, so no account ID reaches the file. A
log that cannot be written is ignored — it must never change what `aws_login`
is told.

`cargo test -p aws-session` covers it against scratch cache directories.
