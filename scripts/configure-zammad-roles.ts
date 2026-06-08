/**
 * Apply declarative Zammad roles via REST API.
 *
 * Prerequisites:
 *   - ZAMMAD_URL, ZAMMAD_TOKEN (admin token with admin.role permission)
 *
 * Usage:
 *   npm run zammad:configure-roles
 *
 * Options:
 *   DELETE_UNLISTED_ROLES=1 — Delete roles not in config (dangerous!)
 */
import { config } from "dotenv";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";

config({ path: resolve(dirname(fileURLToPath(import.meta.url)), "../.env") });

const __dirname = dirname(fileURLToPath(import.meta.url));

const roleSchema = z.object({
  name: z.string(),
  active: z.boolean(),
  default_at_signup: z.boolean().optional(),
  note: z.string().optional(),
  permission_ids: z.array(z.number()).optional(),
  knowledge_base_permission_ids: z.array(z.number()).optional(),
  group_ids: z.record(z.array(z.string())).optional(),
  preferences: z.record(z.any()).optional(),
});

const configSchema = z.object({
  roles: z.array(roleSchema),
});

type Role = z.infer<typeof roleSchema>;
type ZammadRole = Role & { id: number };

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

function differs(existing: ZammadRole, desired: Role): boolean {
  const keys: (keyof Role)[] = Object.keys(desired) as (keyof Role)[];
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
  const deleteUnlisted = process.env.DELETE_UNLISTED_ROLES === "1";

  if (!zammadUrl || !token) {
    console.error("Set ZAMMAD_URL and ZAMMAD_TOKEN.");
    process.exit(1);
  }

  const configPath = process.argv[2]
    ? resolve(process.cwd(), process.argv[2])
    : join(
        process.env.ZAMMAD_CONFIG_DIR || join(__dirname, "../config"),
        "zammad-roles.json"
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

  const desired = parsed.data.roles;

  const existing = await fetchJson<ZammadRole[]>(
    `${zammadUrl}/api/v1/roles`,
    { headers: authHeaders(token) },
    "GET /api/v1/roles"
  );

  const byName = new Map(existing.map((r) => [r.name.toLowerCase(), r]));
  const processedIds = new Set<number>();

  for (const role of desired) {
    const existingRole = byName.get(role.name.toLowerCase());

    if (!existingRole) {
      // eslint-disable-next-line @typescript-eslint/no-unused-vars
      const { knowledge_base_permission_ids, ...rolePayload } = role;
      const created = await fetchJson<ZammadRole>(
        `${zammadUrl}/api/v1/roles`,
        {
          method: "POST",
          headers: authHeaders(token),
          body: JSON.stringify(rolePayload),
        },
        `POST /api/v1/roles (${role.name})`
      );
      console.log(`  ${role.name}: created (id=${created.id})`);
      processedIds.add(created.id);
      continue;
    }

    processedIds.add(existingRole.id);

    if (!differs(existingRole, role)) {
      console.log(`  ${role.name}: unchanged`);
      continue;
    }

    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const { knowledge_base_permission_ids, ...rolePayload } = role;
    await fetchJson<ZammadRole>(
      `${zammadUrl}/api/v1/roles/${existingRole.id}`,
      {
        method: "PUT",
        headers: authHeaders(token),
        body: JSON.stringify({ id: existingRole.id, ...rolePayload }),
      },
      `PUT /api/v1/roles/${existingRole.id} (${role.name})`
    );
    console.log(`  ${role.name}: updated`);
  }

  if (deleteUnlisted) {
    for (const role of existing) {
      if (!processedIds.has(role.id)) {
        console.log(
          `  ${role.name}: skipped delete (use DELETE_UNLISTED_ROLES=1 to confirm)`
        );
      }
    }
  }

  console.log("Done.");
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
