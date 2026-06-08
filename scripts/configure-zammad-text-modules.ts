/**
 * Apply declarative Zammad text modules via REST API.
 *
 * Prerequisites:
 *   - ZAMMAD_URL, ZAMMAD_TOKEN (admin token with admin.text_module permission)
 *
 * Usage:
 *   npm run zammad:configure-text-modules
 *
 * Options:
 *   DELETE_UNLISTED_TEXT_MODULES=1 — Delete text modules not in config (dangerous!)
 */
import { config } from "dotenv";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";

config({ path: resolve(dirname(fileURLToPath(import.meta.url)), "../.env") });

const __dirname = dirname(fileURLToPath(import.meta.url));

const textModuleSchema = z.object({
  name: z.string(),
  keywords: z.string().optional(),
  content: z.string(),
  note: z.string().optional(),
  active: z.boolean(),
  groups: z.array(z.string()).optional(),
});

const configSchema = z.object({
  text_modules: z.array(textModuleSchema),
});

type TextModule = z.infer<typeof textModuleSchema>;
type ZammadTextModule = TextModule & { id: number };

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

function differs(existing: ZammadTextModule, desired: TextModule): boolean {
  const keys: (keyof TextModule)[] = Object.keys(
    desired
  ) as (keyof TextModule)[];
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
  const deleteUnlisted = process.env.DELETE_UNLISTED_TEXT_MODULES === "1";

  if (!zammadUrl || !token) {
    console.error("Set ZAMMAD_URL and ZAMMAD_TOKEN.");
    process.exit(1);
  }

  const configPath = process.argv[2]
    ? resolve(process.cwd(), process.argv[2])
    : join(
        process.env.ZAMMAD_CONFIG_DIR || join(__dirname, "../config"),
        "zammad-text-modules.json"
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

  const desired = parsed.data.text_modules;

  const existing = await fetchJson<ZammadTextModule[]>(
    `${zammadUrl}/api/v1/text_modules`,
    { headers: authHeaders(token) },
    "GET /api/v1/text_modules"
  );

  const byName = new Map(existing.map((t) => [t.name.toLowerCase(), t]));
  const processedIds = new Set<number>();

  for (const module of desired) {
    const existingModule = byName.get(module.name.toLowerCase());

    if (!existingModule) {
      const created = await fetchJson<ZammadTextModule>(
        `${zammadUrl}/api/v1/text_modules`,
        {
          method: "POST",
          headers: authHeaders(token),
          body: JSON.stringify(module),
        },
        `POST /api/v1/text_modules (${module.name})`
      );
      console.log(`  ${module.name}: created (id=${created.id})`);
      processedIds.add(created.id);
      continue;
    }

    processedIds.add(existingModule.id);

    if (!differs(existingModule, module)) {
      console.log(`  ${module.name}: unchanged`);
      continue;
    }

    await fetchJson<ZammadTextModule>(
      `${zammadUrl}/api/v1/text_modules/${existingModule.id}`,
      {
        method: "PUT",
        headers: authHeaders(token),
        body: JSON.stringify({ id: existingModule.id, ...module }),
      },
      `PUT /api/v1/text_modules/${existingModule.id} (${module.name})`
    );
    console.log(`  ${module.name}: updated`);
  }

  if (deleteUnlisted) {
    for (const module of existing) {
      if (!processedIds.has(module.id)) {
        await fetchJson<void>(
          `${zammadUrl}/api/v1/text_modules/${module.id}`,
          { method: "DELETE", headers: authHeaders(token) },
          `DELETE /api/v1/text_modules/${module.id} (${module.name})`
        );
        console.log(`  ${module.name}: deleted (not in config)`);
      }
    }
  }

  console.log("Done.");
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
