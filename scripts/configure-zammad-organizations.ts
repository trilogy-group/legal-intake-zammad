/**
 * Apply declarative Zammad organizations via REST API.
 *
 * Prerequisites:
 *   - ZAMMAD_URL, ZAMMAD_TOKEN (admin token with admin.organization permission)
 *
 * Usage:
 *   npm run zammad:configure-organizations
 *
 * Options:
 *   DELETE_UNLISTED_ORGANIZATIONS=1 — Delete organizations not in config (dangerous!)
 */
import { config } from "dotenv";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";

config({ path: resolve(dirname(fileURLToPath(import.meta.url)), "../.env") });

const __dirname = dirname(fileURLToPath(import.meta.url));

const organizationSchema = z.object({
  name: z.string(),
  shared: z.boolean().optional(),
  domain: z.string().optional(),
  domain_assignment: z.boolean().optional(),
  active: z.boolean(),
  vip: z.boolean().optional(),
  note: z.string().optional(),
});

const configSchema = z.object({
  organizations: z.array(organizationSchema),
});

type Organization = z.infer<typeof organizationSchema>;
type ZammadOrganization = Organization & { id: number };

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

function differs(existing: ZammadOrganization, desired: Organization): boolean {
  const keys: (keyof Organization)[] = Object.keys(
    desired
  ) as (keyof Organization)[];
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
  const deleteUnlisted = process.env.DELETE_UNLISTED_ORGANIZATIONS === "1";

  if (!zammadUrl || !token) {
    console.error("Set ZAMMAD_URL and ZAMMAD_TOKEN.");
    process.exit(1);
  }

  const configPath = process.argv[2]
    ? resolve(process.cwd(), process.argv[2])
    : join(
        process.env.ZAMMAD_CONFIG_DIR || join(__dirname, "../config"),
        "zammad-organizations.json"
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

  const desired = parsed.data.organizations;

  const existing = await fetchJson<ZammadOrganization[]>(
    `${zammadUrl}/api/v1/organizations`,
    { headers: authHeaders(token) },
    "GET /api/v1/organizations"
  );

  const byName = new Map(existing.map((o) => [o.name.toLowerCase(), o]));
  const processedIds = new Set<number>();

  for (const org of desired) {
    const existingOrg = byName.get(org.name.toLowerCase());

    if (!existingOrg) {
      const created = await fetchJson<ZammadOrganization>(
        `${zammadUrl}/api/v1/organizations`,
        {
          method: "POST",
          headers: authHeaders(token),
          body: JSON.stringify(org),
        },
        `POST /api/v1/organizations (${org.name})`
      );
      console.log(`  ${org.name}: created (id=${created.id})`);
      processedIds.add(created.id);
      continue;
    }

    processedIds.add(existingOrg.id);

    if (!differs(existingOrg, org)) {
      console.log(`  ${org.name}: unchanged`);
      continue;
    }

    await fetchJson<ZammadOrganization>(
      `${zammadUrl}/api/v1/organizations/${existingOrg.id}`,
      {
        method: "PUT",
        headers: authHeaders(token),
        body: JSON.stringify({ id: existingOrg.id, ...org }),
      },
      `PUT /api/v1/organizations/${existingOrg.id} (${org.name})`
    );
    console.log(`  ${org.name}: updated`);
  }

  if (deleteUnlisted) {
    for (const org of existing) {
      if (!processedIds.has(org.id)) {
        await fetchJson<void>(
          `${zammadUrl}/api/v1/organizations/${org.id}`,
          { method: "DELETE", headers: authHeaders(token) },
          `DELETE /api/v1/organizations/${org.id} (${org.name})`
        );
        console.log(`  ${org.name}: deleted (not in config)`);
      }
    }
  }

  console.log("Done.");
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
