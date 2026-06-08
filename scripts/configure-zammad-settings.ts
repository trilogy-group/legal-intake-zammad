/**
 * Apply declarative Zammad system settings via REST API (same mechanism as Zammad Admin UI).
 *
 * This is intentionally NOT a Supabase SQL migration: `supabase/migrations/*.sql` only
 * affects Postgres. Zammad is a separate service; configure it with this script or CI step.
 *
 * Prerequisites:
 *   - ZAMMAD_URL — base URL (no trailing path), e.g. https://zammad.example.com
 *   - ZAMMAD_TOKEN — admin HTTP API token with permission to change each setting
 *   - JSON file listing desired `{ "settings": { "<setting_name>": <value> } }`
 *
 * Usage:
 *   ZAMMAD_URL=... ZAMMAD_TOKEN=... npx tsx supabase/scripts/configure-zammad-settings.ts [path/to/settings.json]
 *
 * Default config path: `supabase/scripts/zammad-settings.json` (copy from zammad-settings.example.json).
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

const desiredFileSchema = z.object({
  settings: z.record(z.string(), z.unknown()),
});

type ZammadSettingRow = {
  id: number;
  name: string;
  state_current?: { value?: unknown };
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

  if (!zammadUrl || !token) {
    console.error("Set ZAMMAD_URL and ZAMMAD_TOKEN in the environment.");
    process.exit(1);
  }

  const configPathArg = process.argv[2];
  const defaultConfigDir =
    process.env.ZAMMAD_CONFIG_DIR || join(__dirname, "../config");
  const configPath = configPathArg
    ? resolve(process.cwd(), configPathArg)
    : join(defaultConfigDir, "zammad-settings.json");

  let raw: string;
  try {
    raw = readFileSync(configPath, "utf8");
  } catch {
    console.error(
      `Cannot read config: ${configPath}\n` +
        `Copy supabase/scripts/zammad-settings.example.json to zammad-settings.json or pass a path.`
    );
    process.exit(1);
  }

  const parsed = desiredFileSchema.safeParse(JSON.parse(raw));
  if (!parsed.success) {
    console.error("Invalid config JSON:", parsed.error.flatten());
    process.exit(1);
  }

  const desired = parsed.data.settings;
  const names = Object.keys(desired);
  if (names.length === 0) {
    console.log("No settings in config; nothing to do.");
    return;
  }

  const list = await fetchJson<ZammadSettingRow[]>(
    `${zammadUrl}/api/v1/settings`,
    { headers: authHeaders(token) },
    "GET /api/v1/settings"
  );

  const byName = new Map(list.map((s) => [s.name, s]));

  for (const name of names) {
    const row = byName.get(name);
    if (!row) {
      console.error(
        `Unknown or not visible setting: ${name} (check API permissions / list)`
      );
      process.exit(1);
    }

    const current = row.state_current?.value;
    const next = desired[name];

    if (sameValue(current, next)) {
      console.log(`  ${name}: unchanged (${JSON.stringify(next)})`);
      continue;
    }

    await fetchJson<ZammadSettingRow>(
      `${zammadUrl}/api/v1/settings/${row.id}`,
      {
        method: "PUT",
        headers: authHeaders(token),
        body: JSON.stringify({
          id: row.id,
          state_current: { value: next },
        }),
      },
      `PUT /api/v1/settings/${row.id} (${name})`
    );

    console.log(
      `  ${name}: updated ${JSON.stringify(current)} → ${JSON.stringify(next)}`
    );
  }

  console.log("Done.");
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
