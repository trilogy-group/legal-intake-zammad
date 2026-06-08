/**
 * Apply declarative Zammad triggers via REST API.
 *
 * Manages Zammad triggers (automation rules) from a JSON configuration file.
 * Supports create, update, and optional delete operations.
 *
 * Prerequisites:
 *   - ZAMMAD_URL — base URL (no trailing path), e.g. https://zammad.example.com
 *   - ZAMMAD_TOKEN — admin HTTP API token with trigger management permission
 *   - JSON file listing desired triggers
 *
 * Usage:
 *   ZAMMAD_URL=... ZAMMAD_TOKEN=... npx tsx supabase/scripts/configure-zammad-triggers.ts [path/to/triggers.json]
 *
 * Options:
 *   DELETE_UNLISTED_TRIGGERS=1 — Delete triggers not in config (dangerous!)
 *
 * Default config path: `supabase/scripts/zammad-triggers.json`
 */
import { config } from "dotenv";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";

const __dirname = dirname(fileURLToPath(import.meta.url));
const envPath = process.env.ZAMMAD_ENV_DIR
  ? join(process.env.ZAMMAD_ENV_DIR, ".env")
  : resolve(__dirname, "../.env");
config({ path: envPath });

const triggerSchema = z.object({
  name: z.string(),
  active: z.boolean(),
  condition: z.record(z.string(), z.any()),
  perform: z.record(z.string(), z.any()),
  disable_notification: z.boolean().optional(),
  localization: z.string().nullable().optional(),
  timezone: z.string().nullable().optional(),
  note: z.string().optional(),
  activator: z.string().optional(),
  execution_condition_mode: z.string().optional(),
});

const configSchema = z.object({
  triggers: z.array(triggerSchema),
});

type Trigger = z.infer<typeof triggerSchema>;
type ZammadTrigger = Trigger & {
  id: number;
  created_at?: string;
  updated_at?: string;
};

function authHeaders(token: string): HeadersInit {
  return {
    Authorization: `Token token=${token}`,
    "Content-Type": "application/json",
    Accept: "application/json",
  };
}

function sameValue(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (
    typeof a === "object" &&
    a !== null &&
    typeof b === "object" &&
    b !== null
  ) {
    try {
      return JSON.stringify(a) === JSON.stringify(b);
    } catch {
      return false;
    }
  }
  return false;
}

function triggerDiffers(existing: ZammadTrigger, desired: Trigger): boolean {
  const keys: (keyof Trigger)[] = [
    "name",
    "active",
    "condition",
    "perform",
    "disable_notification",
    "localization",
    "timezone",
    "note",
    "activator",
    "execution_condition_mode",
  ];

  for (const key of keys) {
    if (!sameValue(existing[key], desired[key])) {
      return true;
    }
  }
  return false;
}

async function fetchJson<T>(
  url: string,
  init: RequestInit,
  label: string
): Promise<T> {
  const res = await fetch(url, init);
  const text = await res.text();
  let body: unknown;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    throw new Error(
      `${label}: HTTP ${res.status} — non-JSON body: ${text.slice(0, 200)}`
    );
  }
  if (!res.ok) {
    const err = body as { error?: string; message?: string } | null;
    const msg = err?.error ?? err?.message ?? text.slice(0, 300);
    throw new Error(`${label}: HTTP ${res.status} — ${msg}`);
  }
  return body as T;
}

async function main(): Promise<void> {
  const zammadUrl = process.env.ZAMMAD_URL?.replace(/\/+$/, "") ?? "";
  const token = process.env.ZAMMAD_TOKEN ?? "";
  const deleteUnlisted = process.env.DELETE_UNLISTED_TRIGGERS === "1";

  if (!zammadUrl || !token) {
    console.error("Set ZAMMAD_URL and ZAMMAD_TOKEN in the environment.");
    process.exit(1);
  }

  const configPathArg = process.argv[2];
  const configPath = configPathArg
    ? resolve(process.cwd(), configPathArg)
    : join(
        process.env.ZAMMAD_CONFIG_DIR || join(__dirname, "../config"),
        "zammad-triggers.json"
      );

  let raw: string;
  try {
    raw = readFileSync(configPath, "utf8");
  } catch {
    console.error(
      `Cannot read config: ${configPath}\n` +
        `Copy supabase/scripts/zammad-triggers.example.json to zammad-triggers.json or pass a path.`
    );
    process.exit(1);
  }

  const parsed = configSchema.safeParse(JSON.parse(raw));
  if (!parsed.success) {
    console.error("Invalid config JSON:", parsed.error.flatten());
    process.exit(1);
  }

  const desired = parsed.data.triggers;
  if (desired.length === 0) {
    console.log("No triggers in config; nothing to do.");
    return;
  }

  const existing = await fetchJson<ZammadTrigger[]>(
    `${zammadUrl}/api/v1/triggers`,
    { headers: authHeaders(token) },
    "GET /api/v1/triggers"
  );

  const byName = new Map(existing.map((t) => [t.name.toLowerCase(), t]));
  const processedIds = new Set<number>();

  for (const trigger of desired) {
    const existingTrigger = byName.get(trigger.name.toLowerCase());

    if (!existingTrigger) {
      const created = await fetchJson<ZammadTrigger>(
        `${zammadUrl}/api/v1/triggers`,
        {
          method: "POST",
          headers: authHeaders(token),
          body: JSON.stringify(trigger),
        },
        `POST /api/v1/triggers (${trigger.name})`
      );
      console.log(`  ${trigger.name}: created (id=${created.id})`);
      processedIds.add(created.id);
      continue;
    }

    processedIds.add(existingTrigger.id);

    if (!triggerDiffers(existingTrigger, trigger)) {
      console.log(`  ${trigger.name}: unchanged`);
      continue;
    }

    await fetchJson<ZammadTrigger>(
      `${zammadUrl}/api/v1/triggers/${existingTrigger.id}`,
      {
        method: "PUT",
        headers: authHeaders(token),
        body: JSON.stringify({ id: existingTrigger.id, ...trigger }),
      },
      `PUT /api/v1/triggers/${existingTrigger.id} (${trigger.name})`
    );
    console.log(`  ${trigger.name}: updated`);
  }

  if (deleteUnlisted) {
    for (const trigger of existing) {
      if (!processedIds.has(trigger.id)) {
        await fetchJson<void>(
          `${zammadUrl}/api/v1/triggers/${trigger.id}`,
          {
            method: "DELETE",
            headers: authHeaders(token),
          },
          `DELETE /api/v1/triggers/${trigger.id} (${trigger.name})`
        );
        console.log(`  ${trigger.name}: deleted (not in config)`);
      }
    }
  }

  console.log("Done.");
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
