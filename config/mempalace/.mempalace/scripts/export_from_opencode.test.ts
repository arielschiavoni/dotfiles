import { describe, expect, test } from "bun:test";
import {
  formatDate,
  isAgentExcluded,
  isDirectoryExcluded,
  projectLabel,
  sessionToMarkdown,
  type SessionMessage,
  type SessionRow,
} from "./export_from_opencode";

// ── fixtures ─────────────────────────────────────────────────────────────────

const FIXTURE_SESSION: SessionRow = {
  id: "ses_test000000000000000000000",
  title: "Fix authentication bug",
  directory: "/home/user/repos/myorg/myproject",
  time_created: 1780418305558,
};

const FIXTURE_MESSAGES: SessionMessage[] = [
  {
    role: "user",
    agent: "plan",
    textParts: ["Can you help me fix the authentication bug in the login flow?"],
  },
  {
    role: "assistant",
    agent: "plan",
    textParts: ["Sure, let me look at the login flow and identify the issue."],
  },
  {
    role: "user",
    agent: "plan",
    textParts: [], // edge case: user message with no text parts
  },
  {
    role: "assistant",
    agent: "plan",
    textParts: [], // edge case: assistant message with no text parts (e.g. error-only)
  },
];

// ── projectLabel ─────────────────────────────────────────────────────────────

describe("projectLabel", () => {
  test("takes last 2 path segments joined by __", () => {
    expect(projectLabel("/home/user/repos/myorg/myproject")).toBe("myorg__myproject");
  });

  test("single segment path", () => {
    expect(projectLabel("/myproject")).toBe("myproject");
  });

  test("sanitizes spaces to underscores", () => {
    expect(projectLabel("/repos/my org/my project")).toBe("my_org__my_project");
  });

  test("handles trailing slash", () => {
    expect(projectLabel("/repos/myorg/myproject/")).toBe("myorg__myproject");
  });

  test("preserves hyphens and dots", () => {
    expect(projectLabel("/repos/my-org/fix-delivery-destination")).toBe(
      "my-org__fix-delivery-destination"
    );
  });
});

// ── formatDate ───────────────────────────────────────────────────────────────

describe("formatDate", () => {
  test("formats epoch ms to YYYY-MM-DD HH:MM UTC", () => {
    expect(formatDate(1780418305558)).toBe("2026-06-02 16:38 UTC");
  });

  test("formats epoch 0 to unix epoch", () => {
    expect(formatDate(0)).toBe("1970-01-01 00:00 UTC");
  });
});

// ── isDirectoryExcluded ───────────────────────────────────────────────────────

describe("isDirectoryExcluded", () => {
  const excludeDirs = [
    "/home/user/Documents/notes",
    "/home/user/.aws",
  ];

  test("excludes exact match", () => {
    expect(isDirectoryExcluded("/home/user/Documents/notes", excludeDirs)).toBe(true);
  });

  test("excludes subdirectory of excluded prefix", () => {
    expect(isDirectoryExcluded("/home/user/.aws/config", excludeDirs)).toBe(true);
  });

  test("does not exclude unrelated directory", () => {
    expect(isDirectoryExcluded("/home/user/repos/myorg/myproject", excludeDirs)).toBe(false);
  });

  test("does not exclude partial prefix match", () => {
    // /home/user/.aws-extra should NOT be excluded by /home/user/.aws
    expect(isDirectoryExcluded("/home/user/.aws-extra", excludeDirs)).toBe(false);
  });

  test("returns false when excludeDirs is empty", () => {
    expect(isDirectoryExcluded("/home/user/Documents/notes", [])).toBe(false);
  });
});

// ── isAgentExcluded ───────────────────────────────────────────────────────────

describe("isAgentExcluded", () => {
  const translateMessages: SessionMessage[] = [
    { role: "user", agent: "translate", textParts: ["Wie geht es dir?"] },
    { role: "assistant", agent: "translate", textParts: ["Mir geht es gut."] },
  ];

  const mixedMessages: SessionMessage[] = [
    { role: "user", agent: "plan", textParts: ["Help me refactor this."] },
    { role: "assistant", agent: "translate", textParts: ["Here is the translation."] },
  ];

  test("excludes session where all messages are from excluded agent", () => {
    expect(isAgentExcluded(translateMessages, ["translate"])).toBe(true);
  });

  test("does not exclude session with mixed agents", () => {
    expect(isAgentExcluded(mixedMessages, ["translate"])).toBe(false);
  });

  test("does not exclude session with no matching agent", () => {
    expect(isAgentExcluded(FIXTURE_MESSAGES, ["translate"])).toBe(false);
  });

  test("returns false for empty messages", () => {
    expect(isAgentExcluded([], ["translate"])).toBe(false);
  });

  test("returns false when excludeAgents is empty", () => {
    expect(isAgentExcluded(translateMessages, [])).toBe(false);
  });

  test("excludes session when agent is in a multi-item exclude list", () => {
    const chromeSessions: SessionMessage[] = [
      { role: "user", agent: "chrome", textParts: ["Open the browser."] },
    ];
    expect(isAgentExcluded(chromeSessions, ["translate", "chrome"])).toBe(true);
  });
});

// ── sessionToMarkdown ─────────────────────────────────────────────────────────

describe("sessionToMarkdown", () => {
  test("includes session title as h1", () => {
    const md = sessionToMarkdown(FIXTURE_SESSION, FIXTURE_MESSAGES);
    expect(md).toContain("# Fix authentication bug");
  });

  test("includes project directory", () => {
    const md = sessionToMarkdown(FIXTURE_SESSION, FIXTURE_MESSAGES);
    expect(md).toContain("**project:** /home/user/repos/myorg/myproject");
  });

  test("includes formatted date", () => {
    const md = sessionToMarkdown(FIXTURE_SESSION, FIXTURE_MESSAGES);
    expect(md).toContain("**date:** 2026-06-02 16:38 UTC");
  });

  test("includes session id", () => {
    const md = sessionToMarkdown(FIXTURE_SESSION, FIXTURE_MESSAGES);
    expect(md).toContain("**session:** ses_test000000000000000000000");
  });

  test("user message with text content is rendered", () => {
    const md = sessionToMarkdown(FIXTURE_SESSION, FIXTURE_MESSAGES);
    expect(md).toContain("## User");
    expect(md).toContain("Can you help me fix the authentication bug in the login flow?");
  });

  test("assistant message with text content is rendered", () => {
    const md = sessionToMarkdown(FIXTURE_SESSION, FIXTURE_MESSAGES);
    expect(md).toContain("## Assistant");
    expect(md).toContain("Sure, let me look at the login flow and identify the issue.");
  });

  test("messages with no text parts emit placeholder", () => {
    const md = sessionToMarkdown(FIXTURE_SESSION, FIXTURE_MESSAGES);
    expect(md.match(/\*\(no text content\)\*/g)?.length).toBe(2);
  });

  test("no redacted markers in output", () => {
    const md = sessionToMarkdown(FIXTURE_SESSION, FIXTURE_MESSAGES);
    expect(md).not.toMatch(/\[redacted:/);
  });

  test("multiple text parts are joined by blank line", () => {
    const messages: SessionMessage[] = [
      { role: "user", textParts: ["First part.", "Second part."] },
    ];
    const md = sessionToMarkdown(FIXTURE_SESSION, messages);
    expect(md).toContain("First part.\n\nSecond part.");
  });

  test("empty messages array produces header only", () => {
    const md = sessionToMarkdown(FIXTURE_SESSION, []);
    expect(md).toContain("# Fix authentication bug");
    expect(md).not.toContain("## User");
    expect(md).not.toContain("## Assistant");
  });
});
