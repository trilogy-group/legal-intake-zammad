/**
 * Export current Zammad settings from REST API to local JSON file.
 *
 * This fetches the current state from Zammad and writes it to the local config file,
 * allowing you to sync your local configuration with what's currently in Zammad UI.
 *
 * Prerequisites:
 *   - ZAMMAD_URL — base URL (no trailing path), e.g. https://zammad.example.com
 *   - ZAMMAD_TOKEN — admin HTTP API token
 *
 * Usage:
 *   ZAMMAD_URL=... ZAMMAD_TOKEN=... npx tsx zammad/scripts/export-zammad-settings.ts [output/path.json]
 *
 * Default output path: `zammad/config/zammad-settings.json`
 */
import { config } from "dotenv";
import { writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const envPath = process.env.ZAMMAD_ENV_DIR
  ? join(process.env.ZAMMAD_ENV_DIR, ".env")
  : resolve(__dirname, "../.env");
config({ path: envPath });

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

  const outputPathArg = process.argv[2];
  const outputPath = outputPathArg
    ? resolve(process.cwd(), outputPathArg)
    : join(
        process.env.ZAMMAD_CONFIG_DIR || join(__dirname, "../config"),
        "zammad-settings.json"
      );

  console.log("Fetching current settings from Zammad...");
  const list = await fetchJson<ZammadSettingRow[]>(
    `${zammadUrl}/api/v1/settings`,
    { headers: authHeaders(token) },
    "GET /api/v1/settings"
  );

  const settings: Record<string, unknown> = {};
  for (const row of list) {
    settings[row.name] = row.state_current?.value;
  }

  const output = { settings };

  writeFileSync(outputPath, JSON.stringify(output, null, 2) + "\n", "utf8");
  console.log(`✓ Exported ${list.length} settings to: ${outputPath}`);
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
