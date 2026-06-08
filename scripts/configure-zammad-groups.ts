/**
 * Apply declarative Zammad groups via REST API.
 *
 * Prerequisites:
 *   - ZAMMAD_URL, ZAMMAD_TOKEN (admin token with admin.group permission)
 *
 * Usage:
 *   npm run zammad:configure-groups
 *   or: ZAMMAD_URL=... ZAMMAD_TOKEN=... npx tsx supabase/scripts/configure-zammad-groups.ts
 *
 * Options:
 *   DELETE_UNLISTED_GROUPS=1 — Delete groups not in config (dangerous!)
 */
import { config } from "dotenv";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";

config({ path: resolve(dirname(fileURLToPath(import.meta.url)), "../.env") });

const __dirname = dirname(fileURLToPath(import.meta.url));

const groupSchema = z.object({
  name: z.string(),
  signature_id: z.number().nullable().optional(),
  email_address_id: z.number().nullable().optional(),
  parent_id: z.number().nullable().optional(),
  assignment_timeout: z.number().nullable().optional(),
  follow_up_possible: z.string().optional(),
  reopen_time_in_days: z.number().nullable().optional(),
  follow_up_assignment: z.boolean().optional(),
  active: z.boolean(),
  shared_drafts: z.boolean().optional(),
  note: z.string().optional(),
});

const configSchema = z.object({
  groups: z.array(groupSchema),
});

type Group = z.infer<typeof groupSchema>;
type ZammadGroup = Group & { id: number };

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

function differs(existing: ZammadGroup, desired: Group): boolean {
  const keys: (keyof Group)[] = Object.keys(desired) as (keyof Group)[];
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
  const deleteUnlisted = process.env.DELETE_UNLISTED_GROUPS === "1";

  if (!zammadUrl || !token) {
    console.error("Set ZAMMAD_URL and ZAMMAD_TOKEN.");
    process.exit(1);
  }

  const configPath = process.argv[2]
    ? resolve(process.cwd(), process.argv[2])
    : join(
        process.env.ZAMMAD_CONFIG_DIR || join(__dirname, "../config"),
        "zammad-groups.json"
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

  const desired = parsed.data.groups;

  const existing = await fetchJson<ZammadGroup[]>(
    `${zammadUrl}/api/v1/groups`,
    { headers: authHeaders(token) },
    "GET /api/v1/groups"
  );

  const byName = new Map(existing.map((g) => [g.name.toLowerCase(), g]));
  const processedIds = new Set<number>();

  for (const group of desired) {
    const existingGroup = byName.get(group.name.toLowerCase());

    if (!existingGroup) {
      const created = await fetchJson<ZammadGroup>(
        `${zammadUrl}/api/v1/groups`,
        {
          method: "POST",
          headers: authHeaders(token),
          body: JSON.stringify(group),
        },
        `POST /api/v1/groups (${group.name})`
      );
      console.log(`  ${group.name}: created (id=${created.id})`);
      processedIds.add(created.id);
      continue;
    }

    processedIds.add(existingGroup.id);

    if (!differs(existingGroup, group)) {
      console.log(`  ${group.name}: unchanged`);
      continue;
    }

    await fetchJson<ZammadGroup>(
      `${zammadUrl}/api/v1/groups/${existingGroup.id}`,
      {
        method: "PUT",
        headers: authHeaders(token),
        body: JSON.stringify({ id: existingGroup.id, ...group }),
      },
      `PUT /api/v1/groups/${existingGroup.id} (${group.name})`
    );
    console.log(`  ${group.name}: updated`);
  }

  if (deleteUnlisted) {
    for (const group of existing) {
      if (!processedIds.has(group.id)) {
        await fetchJson<void>(
          `${zammadUrl}/api/v1/groups/${group.id}`,
          { method: "DELETE", headers: authHeaders(token) },
          `DELETE /api/v1/groups/${group.id} (${group.name})`
        );
        console.log(`  ${group.name}: deleted (not in config)`);
      }
    }
  }

  console.log("Done.");
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
