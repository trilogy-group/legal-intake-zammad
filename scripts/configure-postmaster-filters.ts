/**
 * Apply Zammad Postmaster Filters declaratively via REST — config-as-code.
 *
 * Primary use: mark the redline reviewer's inbound email replies as INTERNAL.
 * When the external reviewer replies to the redline packet, Zammad ingests it
 * as a normal inbound *customer* email, which defaults to PUBLIC. A postmaster
 * filter matching mail addressed To the dedicated redline mailbox sets
 * `x-zammad-article-internal: true` at ingestion, so the redline reply lands as
 * an internal note (matching the old API-era behaviour where our code posted
 * the redline as an internal article).
 *
 * Fully idempotent CRUD (unlike the email channel, postmaster filters have a
 * real REST create/update/delete):
 *   - create  a filter present in JSON but absent in Zammad
 *   - update  a filter whose match/perform/active drifted from JSON
 *   - (never deletes unlisted filters — non-destructive, mirroring
 *      ci-apply-all-config.sh which never sets DELETE_UNLISTED_*)
 *
 * Filters are matched/keyed by `name` (stable identifier).
 *
 * Reads zammad-config/<env>/zammad-postmaster-filters.json:
 *   {
 *     "postmaster_filters": [
 *       {
 *         "name": "Redline replies are internal",
 *         "active": true,
 *         "match": { "to": { "operator": "contains", "value": "redline-inbound" } },
 *         "perform": { "x-zammad-article-internal": { "value": "true" } }
 *       }
 *     ]
 *   }
 *
 * Usage (via run-zammad-script.sh):
 *   bash scripts/run-zammad-script.sh <env> configure-postmaster-filters.ts
 */
import { config } from "dotenv";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";

const __dirname = dirname(fileURLToPath(import.meta.url));
const envPath = process.env.ZAMMAD_ENV_DIR
  ? join(process.env.ZAMMAD_ENV_DIR, ".env")
  : resolve(__dirname, "../zammad-config/local/.env");
config({ path: envPath });

const matchRuleSchema = z.object({
  operator: z.string().min(1),
  value: z.string().min(1),
});
const performRuleSchema = z.object({
  value: z.string().min(1),
});
const filterSchema = z.object({
  name: z.string().min(1),
  active: z.boolean().default(true),
  match: z.record(z.string(), matchRuleSchema),
  perform: z.record(z.string(), performRuleSchema),
  note: z.string().optional(),
});
const configSchema = z.object({
  postmaster_filters: z.array(filterSchema),
});

type DesiredFilter = z.infer<typeof filterSchema>;

function authHeaders(token: string): HeadersInit {
  return {
    Authorization: `Token token=${token}`,
    "Content-Type": "application/json",
    Accept: "application/json",
  };
}

interface ZammadFilter {
  id: number;
  name: string;
  active: boolean;
  channel: string;
  match: Record<string, { operator: string; value: string }>;
  perform: Record<string, { value: string }>;
  note?: string | null;
}

// Deep-compare desired match/perform against the live filter (ignoring ordering
// and any extra server-managed keys we don't declare).
function matchesDesired(live: ZammadFilter, want: DesiredFilter): boolean {
  if (live.active !== want.active) return false;

  const cmp = (
    a: Record<string, { operator?: string; value: string }>,
    b: Record<string, { operator?: string; value: string }>
  ): boolean => {
    const ak = Object.keys(a).sort();
    const bk = Object.keys(b).sort();
    if (ak.length !== bk.length || ak.some((k, i) => k !== bk[i])) return false;
    return ak.every(
      (k) =>
        (a[k].operator ?? "") === (b[k].operator ?? "") &&
        a[k].value === b[k].value
    );
  };

  return cmp(live.match, want.match) && cmp(live.perform, want.perform);
}

async function main(): Promise<void> {
  const zammadUrl = (process.env.ZAMMAD_URL ?? "").replace(/\/+$/, "");
  const token = process.env.ZAMMAD_TOKEN ?? "";
  if (!zammadUrl || !token) {
    throw new Error("Set ZAMMAD_URL and ZAMMAD_TOKEN environment variables");
  }

  const configDir =
    process.env.ZAMMAD_CONFIG_DIR ?? resolve(__dirname, "../zammad-config/local");
  const configPath = join(configDir, "zammad-postmaster-filters.json");

  let raw: string;
  try {
    raw = readFileSync(configPath, "utf-8");
  } catch {
    console.log(
      `No zammad-postmaster-filters.json in ${configDir} — nothing to do.`
    );
    return;
  }
  const desired = configSchema.parse(JSON.parse(raw));

  const headers = authHeaders(token);

  const listRes = await fetch(`${zammadUrl}/api/v1/postmaster_filters`, {
    headers,
  });
  if (!listRes.ok) {
    throw new Error(`GET postmaster_filters failed: HTTP ${listRes.status}`);
  }
  const existing = (await listRes.json()) as ZammadFilter[];

  let created = 0;
  let updated = 0;
  let unchanged = 0;

  for (const want of desired.postmaster_filters) {
    const live = existing.find((f) => f.name === want.name);
    const body = JSON.stringify({
      name: want.name,
      channel: "email",
      active: want.active,
      match: want.match,
      perform: want.perform,
      note: want.note ?? "",
    });

    if (!live) {
      const res = await fetch(`${zammadUrl}/api/v1/postmaster_filters`, {
        method: "POST",
        headers,
        body,
      });
      if (!res.ok) {
        throw new Error(
          `create filter '${want.name}' failed: HTTP ${res.status} ${await res.text()}`
        );
      }
      console.log(`created: ${want.name}`);
      created++;
      continue;
    }

    if (matchesDesired(live, want)) {
      console.log(`unchanged: ${want.name}`);
      unchanged++;
      continue;
    }

    const res = await fetch(
      `${zammadUrl}/api/v1/postmaster_filters/${live.id}`,
      { method: "PUT", headers, body }
    );
    if (!res.ok) {
      throw new Error(
        `update filter '${want.name}' failed: HTTP ${res.status} ${await res.text()}`
      );
    }
    console.log(`updated: ${want.name}`);
    updated++;
  }

  console.log(
    `\nDone. ${created} created, ${updated} updated, ${unchanged} unchanged.`
  );
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
