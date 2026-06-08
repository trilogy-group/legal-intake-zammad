/**
 * Export current Zammad webhooks from REST API to local JSON file.
 *
 * Sensitive fields (signature_token, bearer_token, basic_auth_password) are
 * redacted in the exported file and must be supplied at apply-time via env vars:
 *   ZAMMAD_WEBHOOK_SECRET     — HMAC signature token (same value used by the app)
 *   ZAMMAD_WEBHOOK_BEARER_TOKEN — bearer token sent in the Authorization header
 *
 * Usage (via run-zammad-script.sh):
 *   bash zammad/staging/scripts/run-zammad-script.sh export-zammad-webhooks.ts
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

interface ZammadWebhook {
  id: number;
  name: string;
  endpoint: string;
  http_method: string;
  ssl_verify: boolean;
  active: boolean;
  note: string | null;
  pre_defined_webhook_type: string | null;
  customized_payload: boolean;
  custom_payload: string | null;
  preferences: Record<string, unknown>;
  signature_token?: string;
  bearer_token?: string;
  basic_auth_username?: string | null;
  basic_auth_password?: string;
  created_at?: string;
  updated_at?: string;
  created_by_id?: number;
  updated_by_id?: number;
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
        "zammad-webhooks.json"
      );

  console.log("Fetching current webhooks from Zammad...");
  const webhooks = await fetchJson<ZammadWebhook[]>(
    `${zammadUrl}/api/v1/webhooks`,
    { headers: authHeaders(token) },
    "GET /api/v1/webhooks"
  );

  // Strip volatile/sensitive fields. Sensitive tokens are env-var-driven at
  // apply time; storing them in the config JSON would risk committing secrets.
  const cleaned = webhooks.map(
    ({
      id,
      created_at,
      updated_at,
      created_by_id,
      updated_by_id,
      signature_token,
      bearer_token,
      basic_auth_password,
      ...rest
    }) => rest
  );

  writeFileSync(
    outputPath,
    JSON.stringify({ webhooks: cleaned }, null, 2) + "\n",
    "utf8"
  );
  console.log(`✓ Exported ${webhooks.length} webhook(s) to: ${outputPath}`);
  console.log(
    "  Note: signature_token, bearer_token and basic_auth_password are redacted."
  );
  console.log(
    "  Supply them at apply-time via ZAMMAD_WEBHOOK_SECRET / ZAMMAD_WEBHOOK_BEARER_TOKEN."
  );
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
