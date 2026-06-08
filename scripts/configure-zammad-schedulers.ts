/**
 * Apply declarative Zammad schedulers via REST API.
 *
 * Manages Zammad schedulers (time-based automation) from a JSON configuration file.
 * Supports create, update, and optional delete operations.
 *
 * Prerequisites:
 *   - ZAMMAD_URL — base URL (no trailing path), e.g. https://zammad.example.com
 *   - ZAMMAD_TOKEN — admin HTTP API token with scheduler management permission (admin.scheduler)
 *   - JSON file listing desired schedulers
 *
 * Usage:
 *   npm run zammad:configure-schedulers
 *   or: ZAMMAD_URL=... ZAMMAD_TOKEN=... npx tsx zammad/scripts/configure-zammad-schedulers.ts [path/to/schedulers.json]
 *
 * Options:
 *   DELETE_UNLISTED_SCHEDULERS=1 — Delete schedulers not in config (dangerous!)
 *
 * Default config path: `zammad/config/zammad-schedulers.json`
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

const schedulerSchema = z.object({
  name: z.string(),
  timeplan: z.object({
    days: z.record(z.string(), z.boolean()),
    hours: z.record(z.string(), z.boolean()),
    minutes: z.record(z.string(), z.boolean()),
  }),
  object: z.string(),
  condition: z.record(z.string(), z.any()),
  perform: z.record(z.string(), z.any()),
  disable_notification: z.boolean(),
  localization: z.string().optional(),
  timezone: z.string().optional(),
  note: z.string().optional(),
  active: z.boolean(),
});

const configSchema = z.object({
  schedulers: z.array(schedulerSchema),
});

type Scheduler = z.infer<typeof schedulerSchema>;
type ZammadScheduler = Scheduler & { id: number };

function authHeaders(token: string): HeadersInit {
  return {
    Authorization: `Token token=${token}`,
    "Content-Type": "application/json",
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

function schedulerDiffers(
  existing: ZammadScheduler,
  desired: Scheduler
): boolean {
  const keys: (keyof Scheduler)[] = Object.keys(desired) as (keyof Scheduler)[];
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
      `${label}: HTTP ${res.status} — non-JSON: ${text.slice(0, 200)}`
    );
  }
  if (!res.ok) {
    const err = body as { error?: string } | null;
    throw new Error(
      `${label}: HTTP ${res.status} — ${err?.error ?? text.slice(0, 300)}`
    );
  }
  return body as T;
}

async function main(): Promise<void> {
  const zammadUrl = process.env.ZAMMAD_URL?.replace(/\/+$/, "") ?? "";
  const token = process.env.ZAMMAD_TOKEN ?? "";
  const deleteUnlisted = process.env.DELETE_UNLISTED_SCHEDULERS === "1";

  if (!zammadUrl || !token) {
    console.error("Set ZAMMAD_URL and ZAMMAD_TOKEN in the environment.");
    process.exit(1);
  }

  const configPathArg = process.argv[2];
  const configPath = configPathArg
    ? resolve(process.cwd(), configPathArg)
    : join(
        process.env.ZAMMAD_CONFIG_DIR || join(__dirname, "../config"),
        "zammad-schedulers.json"
      );

  let raw: string;
  try {
    raw = readFileSync(configPath, "utf8");
  } catch {
    console.error(`Cannot read: ${configPath}`);
    process.exit(1);
  }

  const parsed = configSchema.safeParse(JSON.parse(raw));
  if (!parsed.success) {
    console.error("Invalid config:", parsed.error.flatten());
    process.exit(1);
  }

  const desired = parsed.data.schedulers;

  const existing = await fetchJson<ZammadScheduler[]>(
    `${zammadUrl}/api/v1/jobs`,
    { headers: authHeaders(token) },
    "GET /api/v1/jobs"
  );

  const byName = new Map(existing.map((s) => [s.name.toLowerCase(), s]));
  const processedIds = new Set<number>();

  for (const scheduler of desired) {
    const existingScheduler = byName.get(scheduler.name.toLowerCase());

    if (!existingScheduler) {
      const created = await fetchJson<ZammadScheduler>(
        `${zammadUrl}/api/v1/jobs`,
        {
          method: "POST",
          headers: authHeaders(token),
          body: JSON.stringify(scheduler),
        },
        `POST /api/v1/jobs (${scheduler.name})`
      );
      console.log(`  ${scheduler.name}: created (id=${created.id})`);
      processedIds.add(created.id);
      continue;
    }

    processedIds.add(existingScheduler.id);

    if (!schedulerDiffers(existingScheduler, scheduler)) {
      console.log(`  ${scheduler.name}: unchanged`);
      continue;
    }

    await fetchJson<ZammadScheduler>(
      `${zammadUrl}/api/v1/jobs/${existingScheduler.id}`,
      {
        method: "PUT",
        headers: authHeaders(token),
        body: JSON.stringify({ id: existingScheduler.id, ...scheduler }),
      },
      `PUT /api/v1/jobs/${existingScheduler.id} (${scheduler.name})`
    );
    console.log(`  ${scheduler.name}: updated`);
  }

  if (deleteUnlisted) {
    for (const scheduler of existing) {
      if (!processedIds.has(scheduler.id)) {
        await fetchJson<void>(
          `${zammadUrl}/api/v1/jobs/${scheduler.id}`,
          { method: "DELETE", headers: authHeaders(token) },
          `DELETE /api/v1/jobs/${scheduler.id} (${scheduler.name})`
        );
        console.log(`  ${scheduler.name}: deleted (not in config)`);
      }
    }
  }

  console.log("Done.");
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
