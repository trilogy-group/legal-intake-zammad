#!/usr/bin/env tsx
/**
 * Export Object Manager Attributes (custom fields) from Zammad UI to local JSON file.
 * This includes all custom attributes for Ticket, User, and Organization objects.
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

interface ObjectAttribute {
  id: number;
  name: string;
  display: string;
  data_type: string;
  data_option: Record<string, unknown>;
  data_option_new: Record<string, unknown>;
  editable: boolean;
  internal: boolean;
  active: boolean;
  screens: Record<string, unknown>;
  to_create: boolean;
  to_migrate: boolean;
  to_delete: boolean;
  to_config: boolean;
  position: number;
  created_by_id: number;
  updated_by_id: number;
  created_at: string;
  updated_at: string;
  object: string;
  deletable: boolean;
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
        "zammad-object-attributes.json"
      );

  console.log("Fetching Object Manager Attributes from Zammad...");

  const allAttributes = await fetchJson<ObjectAttribute[]>(
    `${zammadUrl}/api/v1/object_manager_attributes`,
    { headers: authHeaders(token) },
    "GET /api/v1/object_manager_attributes"
  );

  // Filter to only custom attributes (created by users, not system defaults)
  // System attributes have to_create=false and are usually not editable
  const customAttributes = allAttributes.filter(
    (attr) => attr.name.startsWith("li_") || attr.to_create || attr.to_migrate
  );

  // Clean up attributes - remove IDs and timestamps that shouldn't be in config
  const cleanedAttributes = customAttributes.map((attr) => {
    const {
      id,
      created_by_id,
      updated_by_id,
      created_at,
      updated_at,
      to_create,
      to_migrate,
      to_delete,
      to_config,
      ...clean
    } = attr;
    return clean;
  });

  // Group by object type
  const byObject: Record<string, typeof cleanedAttributes> = {};
  for (const attr of cleanedAttributes) {
    if (!byObject[attr.object]) {
      byObject[attr.object] = [];
    }
    byObject[attr.object].push(attr);
  }

  const config = {
    attributes: cleanedAttributes,
    by_object: byObject,
    metadata: {
      total_custom_attributes: cleanedAttributes.length,
      objects: Object.keys(byObject),
      exported_at: new Date().toISOString(),
    },
  };

  writeFileSync(outputPath, JSON.stringify(config, null, 2) + "\n", "utf8");

  console.log(
    `✓ Exported ${cleanedAttributes.length} custom attributes to: ${outputPath}`
  );

  // Show breakdown by object type
  for (const [objType, attrs] of Object.entries(byObject)) {
    console.log(`  ${objType}: ${attrs.length} attributes`);
    attrs.forEach((attr) => {
      console.log(`    - ${attr.name} (${attr.display})`);
    });
  }
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
