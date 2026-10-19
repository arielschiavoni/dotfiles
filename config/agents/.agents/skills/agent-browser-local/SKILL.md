---
name: agent-browser-local
description: Read together with the agent-browser skill, before the first agent-browser or lighthouse command. Local setup - where screenshots, HAR files, logs and reports go (.browser/ in the repo), workarounds for this machine, Lighthouse audits, and how to report results.
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
