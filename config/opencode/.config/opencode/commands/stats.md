---
description: Generate a markdown summary of your OpenCode usage stats
---

You are generating an OpenCode usage report.

> **Note:** The `question` and `stats` tools are both read-only and safe to use in plan mode. Always call them regardless of the current mode.

## Step 1: Determine the period

Get the last three month names:

!`python3 -c "from datetime import date; from calendar import month_name; m=date.today().month; y=date.today().year; months=[(y if m-i>0 else y-1, (m-i-1)%12+1) for i in range(1,4)]; [print(f'{month_name[mo]} {yr}') for yr,mo in months]"`

Use the `question` tool to ask the user which period they want (`multiple: false`), with these options **in this exact order** (replace the month names with the actual output from the command above):

1. **Month to date** → period value: `month to date`
2. **Current week** → period value: `current week`
3. **Last 7 days** → period value: `last 7 days`
4. **{month 1 name}** (previous full month) → period value: `{month 1 name}` (e.g. `April 2026`)
5. **{month 2 name}** → period value: `{month 2 name}`
6. **{month 3 name}** → period value: `{month 3 name}`
7. **Year to date** → period value: `year to date`

If the user selects "Type your own answer" and types a value, **do not treat it as an option number** — regardless of what number they type, always interpret it as a number of days and pass that integer directly as the period (e.g. if they type `2`, pass `2` as the period, not option 2 "Current week").

## Step 2: Collect stats and print the report

Call the `stats` tool with the resolved period:

```
stats({ period: "<period value>" })
```

The tool returns a fully rendered markdown report. Print it **verbatim** — do not summarise, reformat, or omit any section.
