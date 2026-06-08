/**
 * Apply the local @legal-agent triggers to your local Zammad Rails server.
 *
 * Usage:
 *   ZAMMAD_URL=http://localhost:<port> ZAMMAD_TOKEN=<local-admin-token> \
 *     npx tsx zammad/local/scripts/configure-zammad-triggers.ts
 *
 * Or via npm script:
 *   npm run zammad:local:configure-triggers
 *   (set ZAMMAD_URL and ZAMMAD_TOKEN in .env.local or export them first)
 *
 * Before running, edit zammad/local/config/zammad-triggers.json and replace:
 *   LEGAL_AGENT_BOT_USER_ID  → Admin → Users → find "Legal Agent" bot → note the ID
 *   LEGAL_AGENT_WEBHOOK_ID   → Admin → Integrations → Webhooks → find the webhook
 *                              pointing to http://localhost:3000/api/webhooks/zammad → note the ID
 *
 * This script ONLY touches your local Zammad instance.
 * Staging and prod configs are entirely separate.
 */
import { config } from "dotenv";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

// Load .env from zammad-config/local/ (credential file for local env)
const envPath = process.env.ZAMMAD_ENV_DIR
  ? join(process.env.ZAMMAD_ENV_DIR, ".env")
  : resolve(__dirname, "../zammad-config/local/.env");
config({ path: envPath });

const ZAMMAD_URL = (
  process.env.ZAMMAD_LOCAL_URL ??
  process.env.ZAMMAD_URL ??
  ""
).replace(/\/$/, "");
const ZAMMAD_TOKEN =
  process.env.ZAMMAD_LOCAL_TOKEN ?? process.env.ZAMMAD_TOKEN ?? "";

if (!ZAMMAD_URL || !ZAMMAD_TOKEN) {
  console.error(
    "Error: ZAMMAD_LOCAL_URL (or ZAMMAD_URL) and ZAMMAD_LOCAL_TOKEN (or ZAMMAD_TOKEN) must be set."
  );
  console.error("Example:");
  console.error(
    "  ZAMMAD_LOCAL_URL=http://localhost:3000 ZAMMAD_LOCAL_TOKEN=<admin-token> npm run zammad:local:configure-triggers"
  );
  process.exit(1);
}

const configPath = process.env.ZAMMAD_CONFIG_DIR
  ? join(process.env.ZAMMAD_CONFIG_DIR, "zammad-triggers.json")
  : join(__dirname, "../zammad-config/local/zammad-triggers.json");
const raw = JSON.parse(readFileSync(configPath, "utf8")) as {
  triggers: Record<string, unknown>[];
};

const headers: HeadersInit = {
  Authorization: `Token token=${ZAMMAD_TOKEN}`,
  "Content-Type": "application/json",
  Accept: "application/json",
};

async function listExistingTriggers(): Promise<
  Array<{ id: number; name: string }>
> {
  const res = await fetch(`${ZAMMAD_URL}/api/v1/triggers`, { headers });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(
      `Failed to list triggers (${res.status}): ${t.slice(0, 300)}`
    );
  }
  return (await res.json()) as Array<{ id: number; name: string }>;
}

async function upsertTrigger(
  trigger: Record<string, unknown>,
  existing: Array<{ id: number; name: string }>
): Promise<void> {
  const found = existing.find((e) => e.name === trigger.name);

  if (found) {
    console.log(
      `  Updating existing trigger: "${trigger.name}" (id=${found.id})`
    );
    const res = await fetch(`${ZAMMAD_URL}/api/v1/triggers/${found.id}`, {
      method: "PUT",
      headers,
      body: JSON.stringify(trigger),
    });
    if (!res.ok) {
      const t = await res.text();
      throw new Error(
        `Failed to update trigger "${trigger.name}" (${res.status}): ${t.slice(0, 400)}`
      );
    }
  } else {
    console.log(`  Creating new trigger: "${trigger.name}"`);
    const res = await fetch(`${ZAMMAD_URL}/api/v1/triggers`, {
      method: "POST",
      headers,
      body: JSON.stringify(trigger),
    });
    if (!res.ok) {
      const t = await res.text();
      throw new Error(
        `Failed to create trigger "${trigger.name}" (${res.status}): ${t.slice(0, 400)}`
      );
    }
  }
}

async function deleteTrigger(id: number, name: string): Promise<void> {
  const res = await fetch(`${ZAMMAD_URL}/api/v1/triggers/${id}`, {
    method: "DELETE",
    headers,
  });
  if (!res.ok && res.status !== 404) {
    const t = await res.text();
    throw new Error(
      `Failed to delete trigger "${name}" id=${id} (${res.status}): ${t.slice(0, 400)}`
    );
  }
  console.log(`  Deleted default trigger: "${name}" (id=${id})`);
}

async function main(): Promise<void> {
  const placeholder = raw.triggers.find(
    (t) =>
      JSON.stringify(t).includes("LEGAL_AGENT_BOT_USER_ID") ||
      JSON.stringify(t).includes("LEGAL_AGENT_WEBHOOK_ID")
  );

  if (placeholder) {
    console.warn(
      "\n⚠  WARNING: zammad/local/config/zammad-triggers.json still contains placeholder values."
    );
    console.warn(
      "   Replace LEGAL_AGENT_BOT_USER_ID and LEGAL_AGENT_WEBHOOK_ID"
    );
    console.warn(
      "   with real IDs from your local Zammad instance before running this script.\n"
    );
    process.exit(1);
  }

  console.log(
    `Applying @legal-agent triggers to LOCAL Zammad at ${ZAMMAD_URL}`
  );

  const existing = await listExistingTriggers();
  console.log(`Found ${existing.length} existing trigger(s)`);

  // Delete any triggers not in our config — removes Zammad's default seeded triggers
  // that don't exist in prod (e.g. "auto reply (on new tickets)").
  const configuredNames = new Set(raw.triggers.map((t) => t.name as string));
  const toDelete = existing.filter((e) => !configuredNames.has(e.name));
  for (const trigger of toDelete) {
    await deleteTrigger(trigger.id, trigger.name);
  }

  for (const trigger of raw.triggers) {
    await upsertTrigger(trigger, existing);
  }

  console.log(
    `\nDone — ${raw.triggers.length} trigger(s) applied to ${ZAMMAD_URL}`
  );
  console.log("Staging and prod are NOT affected.");
}

main().catch((err) => {
  console.error("Error:", err instanceof Error ? err.message : String(err));
  process.exit(1);
});
