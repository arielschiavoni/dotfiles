---
name: agent-browser-local
description: Read together with the agent-browser skill, before the first agent-browser or lighthouse command. Local setup - where screenshots, HAR files, logs and reports go (.browser/ in the repo), workarounds for this machine, Lighthouse audits, signing in to the AWS console (`*.console.aws.amazon.com` links, e.g. CloudWatch dashboards), and how to report results.
---

# agent-browser-local

Usage comes from `agent-browser skills get core`; this adds the local setup.
agent-browser and Chromium are installed: never run `agent-browser install`
or `npm i -g`.

## Output

Write everything to `.browser/` in the repo root, so the user can open it
(gitignored globally):

```sh
cd "$(git rev-parse --show-toplevel)" && mkdir -p .browser
agent-browser screenshot ./.browser/01-home.png
agent-browser network har stop ./.browser/network.har
agent-browser console > .browser/console.txt
```

- Write paths as `./.browser/...`: a path starting with `.` is read as a CSS
  class selector, and the file lands in a temp dir.
- Number screenshots in the order taken: `01-home.png`, `02-menu-open.png`.
- Save what you inspect - requests, console, errors, `vitals`, `a11y` - as
  files there too, not only in the chat.

## Workarounds

- Start with `agent-browser network har start` or `open <url>`, never a bare
  `open`: it ignores `AGENT_BROWSER_ARGS` and Chromium fails to start.
- After a click that opens a menu or dialog, `wait 1000` before the
  screenshot: it may still be animating.

## AWS console

For a `console.aws.amazon.com` link, sign the browser in with the user's AWS
profile; opened directly, it lands on the AWS login page.

1. Run `aws sts get-caller-identity` (no `--profile`): in pi-safe the user
   picks the profile on the first `aws` command. Check that the account
   matches the link's; if not, ask the user to switch with `/aws-profile`.
2. Open the link with the script; it must start the session, before any
   other `agent-browser` command in it:

   ```sh
   ~/.agents/skills/agent-browser-local/aws-console.ts '<console-url>' --session <name>
   ```

   It starts the dashboard, turns the profile's credentials into a console
   sign-in token and opens the link signed in. It prints the dashboard URL,
   the identity signed in and the page opened - never the credentials or the
   token, so do not hand-roll the federation flow. Exit `1`: it is still at
   the login page; `2`: failure (the message says why).

3. Before any other step, tell the user the script's `Dashboard:`,
   `Signed in:` and `Opened:` lines as they are, so they can follow the
   session in their browser. On exit `1` or `2`, say so and stop.
4. Continue with the same `--session`.

The browser uses a Chromium profile per AWS profile and presets the cookie
consent, so the banner never shows. Dismiss any other first-use popup
(tours, "what's new") once: it stays dismissed in later sessions. The
console session lasts as long as the role credentials (about 1h); to renew,
run the script again in the same session.

## Dashboard

Start it when the user asks to watch the browser (`aws-console.ts` starts
it itself). In pi-safe
(`PI_SAFE_DASHBOARD_PORT` is set) it needs that port, the one published to
the Mac:

```sh
agent-browser dashboard start --port "${PI_SAFE_DASHBOARD_PORT:-4848}"
```

Give the user `http://localhost:<port>`; it opens on the Mac.

## Lighthouse

```sh
lighthouse <url> --quiet --max-wait-for-load=90000 \
  --chrome-flags="--headless=new --no-sandbox" \
  --output=html --output=json --output-path=.browser/lighthouse
jq -r '.categories[] | "\(.title): \(.score*100|round)"' .browser/lighthouse.report.json
```

The machine renders on the CPU: performance scores and vitals are worse than
on real hardware. Compare runs with each other, not with other machines.

## Report

Look at every screenshot with `read` before saying how a page looks. End
with what you checked and saw, console errors, failed requests, scores, and
the files in `.browser/`.
