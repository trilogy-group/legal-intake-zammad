/**
 * Export current Zammad triggers from REST API to local JSON file.
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
    throw new Error(`${label}: HTTP ${res.status} — non-JSON body`);
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
    console.error("Set ZAMMAD_URL and ZAMMAD_TOKEN.");
    process.exit(1);
  }

  const outputPath = process.argv[2]
    ? resolve(process.cwd(), process.argv[2])
    : join(
        process.env.ZAMMAD_CONFIG_DIR || join(__dirname, "../config"),
        "zammad-triggers.json"
      );

  console.log("Fetching current triggers from Zammad...");
  const triggers = await fetchJson<any[]>(
    `${zammadUrl}/api/v1/triggers`,
    { headers: authHeaders(token) },
    "GET /api/v1/triggers"
  );

  const cleaned = triggers.map(
    ({ id, created_at, updated_at, created_by_id, updated_by_id, ...rest }) =>
      rest
  );

  writeFileSync(
    outputPath,
    JSON.stringify({ triggers: cleaned }, null, 2) + "\n",
    "utf8"
  );
  console.log(`✓ Exported ${triggers.length} triggers to: ${outputPath}`);
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
