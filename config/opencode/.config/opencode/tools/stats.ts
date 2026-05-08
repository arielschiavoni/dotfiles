import { tool } from "@opencode-ai/plugin"
import { Database } from "bun:sqlite"
import { homedir } from "os"
import { join } from "path"

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

export function formatTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`
  return String(n)
}

export function formatCost(n: number): string {
  if (n === 0) return "$0.00"
  if (n < 0.01) return `$${n.toFixed(4)}`
  return `$${n.toFixed(2)}`
}

function formatNum(n: number): string {
  return n.toLocaleString("en-US")
}

// ---------------------------------------------------------------------------
// Period → time cutoff
// ---------------------------------------------------------------------------

const MONTH_NAMES: Record<string, number> = {
  january: 0,
  february: 1,
  march: 2,
  april: 3,
  may: 4,
  june: 5,
  july: 6,
  august: 7,
  september: 8,
  october: 9,
  november: 10,
  december: 11,
}

/**
 * Resolve a human-readable period string to a UTC epoch millisecond cutoff.
 *
 * Accepted values (case-insensitive):
 *   "month to date"      – 1st of current month 00:00 local
 *   "current week"       – most recent Monday 00:00 local (ISO week)
 *   "last 7 days"        – now minus 7 × 24 h
 *   "past month 1"       – previous full calendar month (legacy)
 *   "past month 2"       – two calendar months ago (legacy)
 *   "past month 3"       – three calendar months ago (legacy)
 *   "April 2026"         – any "MonthName YYYY" string
 *   "<integer>"          – now minus N × 24 h
 */
export function resolvePeriod(period: string, _now?: Date): {
  cutoffMs: number
  upperCutoffMs: number
  label: string
  days: number
} {
  const now = _now ?? new Date()
  const p = period.trim().toLowerCase()

  if (p === "month to date") {
    const start = new Date(now.getFullYear(), now.getMonth(), 1, 0, 0, 0, 0)
    const days = Math.ceil((now.getTime() - start.getTime()) / 86_400_000) + 1
    const label = `${start.toLocaleDateString("en-US", { month: "long", day: "numeric" })} – ${now.toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" })}`
    return { cutoffMs: start.getTime(), upperCutoffMs: now.getTime(), label, days }
  }

  if (p === "current week") {
    const jsDay = now.getDay() // 0 = Sun
    const daysBack = jsDay === 0 ? 6 : jsDay - 1
    const monday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - daysBack, 0, 0, 0, 0)
    const days = daysBack + 1
    const label = `${monday.toLocaleDateString("en-US", { month: "long", day: "numeric" })} – ${now.toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" })} (current week)`
    return { cutoffMs: monday.getTime(), upperCutoffMs: now.getTime(), label, days }
  }

  if (p === "last 7 days") {
    const cutoff = now.getTime() - 7 * 86_400_000
    return { cutoffMs: cutoff, upperCutoffMs: now.getTime(), label: "Last 7 days", days: 7 }
  }

  if (p === "year to date") {
    const start = new Date(now.getFullYear(), 0, 1, 0, 0, 0, 0)
    const days = Math.ceil((now.getTime() - start.getTime()) / 86_400_000) + 1
    const label = `January 1 – ${now.toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" })} (year to date)`
    return { cutoffMs: start.getTime(), upperCutoffMs: now.getTime(), label, days }
  }

  // Legacy aliases kept for backward compat
  if (p === "past month 1" || p === "past month 2" || p === "past month 3") {
    const offset = p === "past month 1" ? 1 : p === "past month 2" ? 2 : 3
    return resolveMonthOffset(now, offset)
  }

  // "April 2026", "march 2026", etc.
  const monthMatch = p.match(/^([a-z]+)\s+(\d{4})$/)
  if (monthMatch) {
    const monthIdx = MONTH_NAMES[monthMatch[1]]
    const year = parseInt(monthMatch[2], 10)
    if (monthIdx !== undefined && !isNaN(year)) {
      const start = new Date(year, monthIdx, 1, 0, 0, 0, 0)
      const endExclusive = new Date(year, monthIdx + 1, 1, 0, 0, 0, 0)
      const days = Math.round((endExclusive.getTime() - start.getTime()) / 86_400_000)
      const label = start.toLocaleDateString("en-US", { month: "long", year: "numeric" })
      return { cutoffMs: start.getTime(), upperCutoffMs: endExclusive.getTime(), label, days }
    }
  }

  // Numeric fallback: N days
  const n = parseInt(p, 10)
  if (!isNaN(n) && n > 0) {
    const cutoff = now.getTime() - n * 86_400_000
    return { cutoffMs: cutoff, upperCutoffMs: now.getTime(), label: `Last ${n} days`, days: n }
  }

  throw new Error(
    `Unrecognised period: "${period}". Valid values: "month to date", "current week", "last 7 days", "April 2026" (any month name + year), or a positive integer (number of days).`,
  )
}

function resolveMonthOffset(
  now: Date,
  offset: number,
): { cutoffMs: number; upperCutoffMs: number; label: string; days: number } {
  const startMonth = now.getMonth() - offset
  const start = new Date(now.getFullYear(), startMonth, 1, 0, 0, 0, 0)
  const endExclusive = new Date(now.getFullYear(), startMonth + 1, 1, 0, 0, 0, 0)
  const days = Math.round((endExclusive.getTime() - start.getTime()) / 86_400_000)
  const label = start.toLocaleDateString("en-US", { month: "long", year: "numeric" })
  return { cutoffMs: start.getTime(), upperCutoffMs: endExclusive.getTime(), label, days }
}

// ---------------------------------------------------------------------------
// DB path
// ---------------------------------------------------------------------------

export function dbPath(): string {
  return join(homedir(), ".local", "share", "opencode", "opencode.db")
}

// ---------------------------------------------------------------------------
// Model normalisation
// ---------------------------------------------------------------------------

export function canonicalise(_providerID: string, modelID: string): string {
  let s = modelID
  s = s.replace(/^(eu|us|ap|ca|sa|me|af)\./i, "")
  s = s.replace(/^(anthropic|openai|amazon|meta|google|mistral|cohere)\./i, "")
  s = s.replace(/-\d{8}-v\d+[:\d]*$/, "")
  s = s.replace(/\./g, "-")
  return s.toLowerCase()
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface ModelPricing {
  prompt: number
  completion: number
  input_cache_read: number | null
  input_cache_write: number | null
}

/** Aggregated by canonical model name only — for Calculated Cost Breakdown */
interface AggregatedRow {
  canonical: string
  messages: number
  inputTokens: number
  outputTokens: number
  cacheReadTokens: number
  cacheWriteTokens: number
  pricing: ModelPricing | null
  cost: number | null
}

/** Aggregated by provider + canonical model — for Provider Cost Breakdown (paid only) */
interface ProviderRow {
  providerID: string
  providerName: string
  canonical: string
  messages: number
  inputTokens: number
  outputTokens: number
  cacheReadTokens: number
  cacheWriteTokens: number
  realCost: number
}

function resolveProviderName(providerID: string): string {
  const p = providerID.toLowerCase()
  if (p.includes("amazon") || p.includes("bedrock")) return "Amazon Bedrock"
  if (p.includes("anthropic")) return "Anthropic"
  if (p.includes("openai")) return "OpenAI"
  if (p.includes("github") || p.includes("copilot")) return "GitHub Copilot"
  if (p.includes("google")) return "Google"
  if (p.includes("mistral")) return "Mistral"
  if (p.includes("meta")) return "Meta"
  if (p.includes("cohere")) return "Cohere"
  return providerID
}

// ---------------------------------------------------------------------------
// Markdown rendering
// ---------------------------------------------------------------------------

function renderReport(params: {
  label: string
  days: number
  sessions: number
  messages: number
  totalInput: number
  totalOutput: number
  totalCacheRead: number
  totalCacheWrite: number
  totalTokens: number
  cacheHitRate: number
  grandTotal: number
  totalRealCost: number
  cacheSavings: number
  mostExpensive: { model: string; cost: number | null } | null
  topModels: AggregatedRow[]
  providerModels: ProviderRow[]
  tools: { name: string; calls: number; pct: number }[]
}): string {
  const {
    label, days, sessions, messages,
    totalInput, totalOutput, totalCacheRead, totalCacheWrite, totalTokens, cacheHitRate,
    grandTotal, totalRealCost, cacheSavings, mostExpensive,
    topModels, providerModels, tools,
  } = params

  const pct = (n: number, total: number) =>
    total > 0 ? `${((n / total) * 100).toFixed(1)}%` : "—"

  const mostExpensiveStr = mostExpensive
    ? `${mostExpensive.model} (${formatCost(mostExpensive.cost ?? 0)})`
    : "—"

  // Calculated cost breakdown rows
  const calcRows = topModels.map((m) => {
    const costPct = grandTotal > 0 && m.cost !== null ? pct(m.cost, grandTotal) : "—"
    return `| ${m.canonical} | ${formatNum(m.messages)} | ${formatTokens(m.inputTokens)} | ${formatTokens(m.outputTokens)} | ${formatTokens(m.cacheWriteTokens)} | ${formatTokens(m.cacheReadTokens)} | ${m.cost !== null ? formatCost(m.cost) : "—"} | ${costPct} |`
  }).join("\n")

  const totalMessages = topModels.reduce((s, r) => s + r.messages, 0)

  // Provider cost breakdown rows (paid only, sorted by realCost desc)
  const sortedProviders = [...providerModels].sort((a, b) => b.realCost - a.realCost || b.messages - a.messages)
  const totalProviderMessages = sortedProviders.reduce((s, r) => s + r.messages, 0)
  const totalProviderInput = sortedProviders.reduce((s, r) => s + r.inputTokens, 0)
  const totalProviderOutput = sortedProviders.reduce((s, r) => s + r.outputTokens, 0)
  const totalProviderCacheWrite = sortedProviders.reduce((s, r) => s + r.cacheWriteTokens, 0)
  const totalProviderCacheRead = sortedProviders.reduce((s, r) => s + r.cacheReadTokens, 0)

  const providerRows = sortedProviders.length > 0
    ? sortedProviders.map((m) => {
        const costPct = totalRealCost > 0 ? pct(m.realCost, totalRealCost) : "—"
        return `| ${m.providerName} | ${m.canonical} | ${formatNum(m.messages)} | ${formatTokens(m.inputTokens)} | ${formatTokens(m.outputTokens)} | ${formatTokens(m.cacheWriteTokens)} | ${formatTokens(m.cacheReadTokens)} | ${formatCost(m.realCost)} | ${costPct} |`
      }).join("\n")
    : "| — | No paid usage in this period | — | — | — | — | — | — | — |"

  // Tool rows
  const toolRows = tools.map((t, i) =>
    `| ${i + 1} | ${t.name ?? "—"} | ${formatNum(t.calls)} | ${t.pct}% |`,
  ).join("\n")

  return `# OpenCode Usage Report — ${label}

> Calculated cost = OpenRouter list prices × tokens (all messages, all providers).
> Provider cost = actual DB-recorded charge, paid messages only (cost > $0).

## Summary

| | |
| --- | --- |
| Period | ${label} |
| Sessions / Messages | ${formatNum(sessions)} / ${formatNum(messages)} |
| Total tokens | ${formatTokens(totalTokens)} (cache hit ${cacheHitRate}%) |
| Input / Output | ${formatTokens(totalInput)} / ${formatTokens(totalOutput)} |
| Cache writes / reads | ${formatTokens(totalCacheWrite)} / ${formatTokens(totalCacheRead)} |
| Calculated cost | ${formatCost(grandTotal)} (${formatCost(grandTotal / days)}/day) · saved ${formatCost(cacheSavings)} vs uncached |
| Provider-reported cost | ${formatCost(totalRealCost)} |
| Most expensive model | ${mostExpensiveStr} |

## Calculated Cost Breakdown

> OpenRouter list prices applied to all tokens across all providers. Sorted by cost desc.

| Model | Msgs | Input | Output | Cache Write | Cache Read | Cost | % |
| ----- | ---- | ----- | ------ | ----------- | ---------- | ---- | - |
${calcRows}
| **Total** | **${formatNum(totalMessages)}** | **${formatTokens(totalInput)}** | **${formatTokens(totalOutput)}** | **${formatTokens(totalCacheWrite)}** | **${formatTokens(totalCacheRead)}** | **${formatCost(grandTotal)}** | |

## Provider Cost Breakdown

> Paid messages only (cost > $0). Tokens reflect only those charged requests.

| Provider | Model | Msgs | Input | Output | Cache Write | Cache Read | Cost | % |
| -------- | ----- | ---- | ----- | ------ | ----------- | ---------- | ---- | - |
${providerRows}
| | **Total** | **${formatNum(totalProviderMessages)}** | **${formatTokens(totalProviderInput)}** | **${formatTokens(totalProviderOutput)}** | **${formatTokens(totalProviderCacheWrite)}** | **${formatTokens(totalProviderCacheRead)}** | **${formatCost(totalRealCost)}** | |

---

_Pricing: live from [OpenRouter API](https://openrouter.ai/api/v1/models) at time of report generation._`
}

// ---------------------------------------------------------------------------
// Tool
// ---------------------------------------------------------------------------

export default tool({
  description:
    "[READ-ONLY] Collect OpenCode usage stats for a given period, fetch live model pricing from OpenRouter, aggregate and compute costs, and return a fully rendered markdown report with tables. This tool only reads from a local SQLite database and fetches public pricing data — it makes no changes and is safe to use in plan mode.",
  args: {
    period: tool.schema
      .string()
      .describe(
        'Time period to report on. Accepted values: "month to date", "current week", "last 7 days", "April 2026" (any month name + year), or a positive integer string (number of days, e.g. "14").',
      ),
  },

  async execute({ period }) {
    const { cutoffMs, upperCutoffMs, label, days } = resolvePeriod(period)

    const db = new Database(dbPath(), { readonly: true })

    try {
      const sessionRow = db
        .query<{ sessions: number }, [number, number]>(
          `SELECT COUNT(DISTINCT session_id) as sessions
           FROM message
           WHERE json_extract(data, '$.role') = 'assistant'
             AND time_created >= ?
             AND time_created < ?`,
        )
        .get(cutoffMs, upperCutoffMs)

      const msgRow = db
        .query<{ messages: number }, [number, number]>(
          `SELECT COUNT(*) as messages
           FROM message
           WHERE time_created >= ?
             AND time_created < ?`,
        )
        .get(cutoffMs, upperCutoffMs)

      // All assistant messages with tokens — for Calculated Cost Breakdown
      const modelRows = db
        .query<
          {
            providerID: string
            modelID: string
            messages: number
            input: number
            output: number
            cache_read: number
            cache_write: number
          },
          [number, number]
        >(
          `SELECT
             json_extract(data, '$.providerID')           as providerID,
             json_extract(data, '$.modelID')              as modelID,
             COUNT(*)                                     as messages,
             COALESCE(SUM(json_extract(data, '$.tokens.input')), 0)         as input,
             COALESCE(SUM(json_extract(data, '$.tokens.output')), 0)        as output,
             COALESCE(SUM(json_extract(data, '$.tokens.cache.read')), 0)    as cache_read,
             COALESCE(SUM(json_extract(data, '$.tokens.cache.write')), 0)   as cache_write
           FROM message
           WHERE json_extract(data, '$.role') = 'assistant'
             AND json_extract(data, '$.tokens') IS NOT NULL
             AND time_created >= ?
             AND time_created < ?
           GROUP BY providerID, modelID`,
        )
        .all(cutoffMs, upperCutoffMs)

      // Paid messages only (cost > 0) — for Provider Cost Breakdown
      const paidProviderRows = db
        .query<
          {
            providerID: string
            modelID: string
            messages: number
            input: number
            output: number
            cache_read: number
            cache_write: number
            real_cost: number
          },
          [number, number]
        >(
          `SELECT
             json_extract(data, '$.providerID')           as providerID,
             json_extract(data, '$.modelID')              as modelID,
             COUNT(*)                                     as messages,
             COALESCE(SUM(json_extract(data, '$.tokens.input')), 0)         as input,
             COALESCE(SUM(json_extract(data, '$.tokens.output')), 0)        as output,
             COALESCE(SUM(json_extract(data, '$.tokens.cache.read')), 0)    as cache_read,
             COALESCE(SUM(json_extract(data, '$.tokens.cache.write')), 0)   as cache_write,
             COALESCE(SUM(json_extract(data, '$.cost')), 0)                 as real_cost
           FROM message
           WHERE json_extract(data, '$.role') = 'assistant'
             AND json_extract(data, '$.cost') > 0
             AND time_created >= ?
             AND time_created < ?
           GROUP BY providerID, modelID`,
        )
        .all(cutoffMs, upperCutoffMs)

      const toolRows = db
        .query<{ tool_name: string; calls: number }, [number, number]>(
          `SELECT
             json_extract(p.data, '$.tool') as tool_name,
             COUNT(*) as calls
           FROM part p
           JOIN message m ON p.message_id = m.id
           WHERE json_extract(p.data, '$.type') = 'tool'
             AND m.time_created >= ?
             AND m.time_created < ?
           GROUP BY tool_name
           ORDER BY calls DESC
           LIMIT 10`,
        )
        .all(cutoffMs, upperCutoffMs)

      // Fetch live pricing from OpenRouter
      const res = await fetch("https://openrouter.ai/api/v1/models")
      if (!res.ok) throw new Error(`OpenRouter API error: ${res.status} ${res.statusText}`)
      const orData = (await res.json()) as {
        data: Array<{ id: string; pricing: Record<string, string> }>
      }

      const pricingMap = new Map<string, ModelPricing>()
      for (const m of orData.data) {
        const key = canonicalise("", m.id.includes("/") ? m.id.split("/").pop()! : m.id)
        const p = m.pricing
        pricingMap.set(key, {
          prompt: parseFloat(p.prompt ?? "0"),
          completion: parseFloat(p.completion ?? "0"),
          input_cache_read: p.input_cache_read != null ? parseFloat(p.input_cache_read) : null,
          input_cache_write: p.input_cache_write != null ? parseFloat(p.input_cache_write) : null,
        })
      }

      // --- Calculated Cost Breakdown: aggregate by canonical model (all messages) ---
      const aggMap = new Map<string, AggregatedRow>()
      for (const row of modelRows) {
        if (!row.providerID || !row.modelID) continue
        const canonical = canonicalise(row.providerID, row.modelID)
        const pricing = pricingMap.get(canonical) ?? null
        const existing = aggMap.get(canonical)
        if (existing) {
          existing.messages += row.messages
          existing.inputTokens += row.input
          existing.outputTokens += row.output
          existing.cacheReadTokens += row.cache_read
          existing.cacheWriteTokens += row.cache_write
          if (!existing.pricing && pricing) existing.pricing = pricing
        } else {
          aggMap.set(canonical, {
            canonical,
            messages: row.messages,
            inputTokens: row.input,
            outputTokens: row.output,
            cacheReadTokens: row.cache_read,
            cacheWriteTokens: row.cache_write,
            pricing,
            cost: null,
          })
        }
      }

      // --- Provider Cost Breakdown: aggregate by providerID + canonical (paid only) ---
      const providerAggMap = new Map<string, ProviderRow>()
      for (const row of paidProviderRows) {
        if (!row.providerID || !row.modelID) continue
        const canonical = canonicalise(row.providerID, row.modelID)
        const key = `${row.providerID}|${canonical}`
        const existing = providerAggMap.get(key)
        if (existing) {
          existing.messages += row.messages
          existing.inputTokens += row.input
          existing.outputTokens += row.output
          existing.cacheReadTokens += row.cache_read
          existing.cacheWriteTokens += row.cache_write
          existing.realCost += row.real_cost
        } else {
          providerAggMap.set(key, {
            providerID: row.providerID,
            providerName: resolveProviderName(row.providerID),
            canonical,
            messages: row.messages,
            inputTokens: row.input,
            outputTokens: row.output,
            cacheReadTokens: row.cache_read,
            cacheWriteTokens: row.cache_write,
            realCost: row.real_cost,
          })
        }
      }

      // Compute calculated costs
      let grandTotal = 0
      let cacheSavings = 0
      const aggregated = Array.from(aggMap.values())

      for (const row of aggregated) {
        if (row.pricing) {
          row.cost =
            row.inputTokens * row.pricing.prompt +
            row.outputTokens * row.pricing.completion +
            row.cacheReadTokens * (row.pricing.input_cache_read ?? 0) +
            row.cacheWriteTokens * (row.pricing.input_cache_write ?? 0)
          grandTotal += row.cost
          const savedPerToken = row.pricing.prompt - (row.pricing.input_cache_read ?? 0)
          cacheSavings += row.cacheReadTokens * savedPerToken
        }
      }

      // Token totals (from all messages)
      const totalInput = aggregated.reduce((s, r) => s + r.inputTokens, 0)
      const totalOutput = aggregated.reduce((s, r) => s + r.outputTokens, 0)
      const totalCacheRead = aggregated.reduce((s, r) => s + r.cacheReadTokens, 0)
      const totalCacheWrite = aggregated.reduce((s, r) => s + r.cacheWriteTokens, 0)
      const totalTokens = totalInput + totalOutput + totalCacheRead + totalCacheWrite

      // Real cost from paid-only provider rows
      const providerModels = Array.from(providerAggMap.values())
      const totalRealCost = providerModels.reduce((s, r) => s + r.realCost, 0)

      const cacheHitRate =
        totalInput + totalCacheRead > 0
          ? Math.round((totalCacheRead / (totalInput + totalCacheRead)) * 10000) / 100
          : 0

      // Sort calculated by cost desc
      aggregated.sort((a, b) => {
        const ca = a.cost ?? 0
        const cb = b.cost ?? 0
        if (cb !== ca) return cb - ca
        return b.messages - a.messages
      })
      let topModels = aggregated.slice(0, 8)
      const rest = aggregated.slice(8)
      if (rest.length > 0) {
        topModels = [
          ...topModels,
          {
            canonical: "other",
            messages: rest.reduce((s, r) => s + r.messages, 0),
            inputTokens: rest.reduce((s, r) => s + r.inputTokens, 0),
            outputTokens: rest.reduce((s, r) => s + r.outputTokens, 0),
            cacheReadTokens: rest.reduce((s, r) => s + r.cacheReadTokens, 0),
            cacheWriteTokens: rest.reduce((s, r) => s + r.cacheWriteTokens, 0),
            pricing: null,
            cost: rest.every((r) => r.cost !== null)
              ? rest.reduce((s, r) => s + (r.cost ?? 0), 0)
              : null,
          },
        ]
      }

      const withCost = aggregated.filter((r) => r.cost !== null)
      const mostExpensive =
        withCost.length > 0
          ? withCost.reduce((a, b) => ((a.cost ?? 0) > (b.cost ?? 0) ? a : b))
          : null

      const totalToolCalls = toolRows.reduce((s, t) => s + t.calls, 0)
      const toolsFormatted = toolRows.map((t) => ({
        name: t.tool_name,
        calls: t.calls,
        pct: totalToolCalls > 0 ? Math.round((t.calls / totalToolCalls) * 1000) / 10 : 0,
      }))

      return renderReport({
        label,
        days,
        sessions: sessionRow?.sessions ?? 0,
        messages: msgRow?.messages ?? 0,
        totalInput,
        totalOutput,
        totalCacheRead,
        totalCacheWrite,
        totalTokens,
        cacheHitRate,
        grandTotal,
        totalRealCost,
        cacheSavings,
        mostExpensive: mostExpensive
          ? { model: mostExpensive.canonical, cost: mostExpensive.cost }
          : null,
        topModels,
        providerModels,
        tools: toolsFormatted,
      })
    } finally {
      db.close()
    }
  },
})
