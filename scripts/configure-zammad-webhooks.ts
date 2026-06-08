/**
 * Apply declarative Zammad webhooks via REST API.
 *
 * Matches webhooks by name. Creates new ones and updates existing ones.
 * Does NOT delete webhooks not present in config (to avoid accidentally
 * removing manually-created webhooks). Set DELETE_UNLISTED_WEBHOOKS=1 to
 * enable deletion of unlisted webhooks (use with caution).
 *
 * Sensitive fields injected at apply-time from env vars:
 *   ZAMMAD_WEBHOOK_SECRET         — HMAC signature_token (same as app's ZAMMAD_WEBHOOK_SECRET)
 *   ZAMMAD_WEBHOOK_BEARER_TOKEN   — bearer_token for Authorization header (optional)
 *
 * Usage (via run-zammad-script.sh):
 *   bash zammad/staging/scripts/run-zammad-script.sh configure-zammad-webhooks.ts
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

const webhookSchema = z.object({
  name: z.string(),
  endpoint: z.string().url(),
  http_method: z
    .enum(["post", "get", "put", "patch", "delete"])
    .default("post"),
  ssl_verify: z.boolean().default(true),
  active: z.boolean().default(true),
  note: z.string().nullable().optional(),
  pre_defined_webhook_type: z.string().nullable().optional(),
  customized_payload: z.boolean().default(false),
  custom_payload: z.string().nullable().optional(),
  basic_auth_username: z.string().nullable().optional(),
  preferences: z.record(z.unknown()).default({}),
});

const configSchema = z.object({
  webhooks: z.array(webhookSchema),
});

type WebhookConfig = z.infer<typeof webhookSchema>;
type ZammadWebhook = WebhookConfig & {
  id: number;
  signature_token?: string;
  bearer_token?: string;
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
  const signatureToken = process.env.ZAMMAD_WEBHOOK_SECRET?.trim() ?? "";
  const bearerToken = process.env.ZAMMAD_WEBHOOK_BEARER_TOKEN?.trim() ?? "";

  if (!zammadUrl || !token) {
    console.error("Set ZAMMAD_URL and ZAMMAD_TOKEN.");
    process.exit(1);
  }

  if (!signatureToken) {
    console.warn(
      "⚠  ZAMMAD_WEBHOOK_SECRET is not set — webhooks will have no signature_token."
    );
  }

  const configPath = process.argv[2]
    ? resolve(process.cwd(), process.argv[2])
    : join(
        process.env.ZAMMAD_CONFIG_DIR || join(__dirname, "../config"),
        "zammad-webhooks.json"
      );

  console.log(`Loading webhook config from: ${configPath}`);
  const rawConfig = JSON.parse(readFileSync(configPath, "utf8"));
  const { webhooks: desired } = configSchema.parse(rawConfig);
  console.log(`Found ${desired.length} desired webhook(s) in config.\n`);

  // Fetch current webhooks
  const existing = await fetchJson<ZammadWebhook[]>(
    `${zammadUrl}/api/v1/webhooks`,
    { headers: authHeaders(token) },
    "GET /api/v1/webhooks"
  );

  const existingByName = new Map(existing.map((w) => [w.name, w]));
  const processedNames = new Set<string>();

  let created = 0;
  let updated = 0;
  let skipped = 0;

  for (const webhook of desired) {
    processedNames.add(webhook.name);

    // Inject sensitive fields from env at apply-time
    const payload: Record<string, unknown> = {
      ...webhook,
      ...(signatureToken ? { signature_token: signatureToken } : {}),
      ...(bearerToken ? { bearer_token: bearerToken } : {}),
    };

    const existing_ = existingByName.get(webhook.name);

    if (existing_) {
      console.log(`  Updating  : ${webhook.name} (id=${existing_.id})`);
      await fetchJson(
        `${zammadUrl}/api/v1/webhooks/${existing_.id}`,
        {
          method: "PUT",
          headers: authHeaders(token),
          body: JSON.stringify(payload),
        },
        `PUT /api/v1/webhooks/${existing_.id}`
      );
      updated++;
    } else {
      console.log(`  Creating  : ${webhook.name}`);
      await fetchJson(
        `${zammadUrl}/api/v1/webhooks`,
        {
          method: "POST",
          headers: authHeaders(token),
          body: JSON.stringify(payload),
        },
        "POST /api/v1/webhooks"
      );
      created++;
    }
  }

  // Optionally delete webhooks not in config
  if (process.env.DELETE_UNLISTED_WEBHOOKS === "1") {
    for (const w of existing) {
      if (!processedNames.has(w.name)) {
        console.log(`  Deleting  : ${w.name} (id=${w.id}) — not in config`);
        await fetchJson(
          `${zammadUrl}/api/v1/webhooks/${w.id}`,
          { method: "DELETE", headers: authHeaders(token) },
          `DELETE /api/v1/webhooks/${w.id}`
        );
      }
    }
  } else {
    const unlisted = existing.filter((w) => !processedNames.has(w.name));
    if (unlisted.length > 0) {
      console.log(
        `\n  ℹ Skipped ${unlisted.length} webhook(s) not in config (set DELETE_UNLISTED_WEBHOOKS=1 to remove):`
      );
      unlisted.forEach((w) => console.log(`    - ${w.name} (id=${w.id})`));
      skipped = unlisted.length;
    }
  }

  console.log(
    `\n✓ Done — created: ${created}, updated: ${updated}, skipped: ${skipped}`
  );
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
