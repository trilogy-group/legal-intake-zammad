/**
 * Export current Zammad field visibility settings from REST API to local JSON file.
 *
 * This fetches the current custom field visibility settings from Zammad
 * and writes them to the local config file for version control.
 *
 * Prerequisites:
 *   - ZAMMAD_URL — base URL (no trailing path), e.g. https://zammad.example.com
 *   - ZAMMAD_TOKEN — admin HTTP API token
 *
 * Usage:
 *   npm run zammad:export-field-visibility
 *
 * Default output path: `zammad/config/zammad-field-visibility.json`
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

type ObjectAttribute = {
  id: number;
  name: string;
  display: string;
  data_type: string;
  screens: {
    create_middle?: { [key: string]: { shown: boolean } };
    edit?: { [key: string]: { shown: boolean } };
  };
};

type FieldVisibilityConfig = {
  agent_shown: boolean;
  customer_shown: boolean;
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
        "zammad-field-visibility.json"
      );

  console.log("Fetching custom field visibility settings from Zammad...");
  const attributes = await fetchJson<ObjectAttribute[]>(
    `${zammadUrl}/api/v1/object_manager_attributes`,
    { headers: authHeaders(token) },
    "GET /api/v1/object_manager_attributes"
  );

  // Filter for custom fields that start with 'li_'
  const customFields = attributes.filter(
    (attr) => attr.name.startsWith("li_") && attr.data_type !== "active"
  );

  const fields: Record<string, FieldVisibilityConfig> = {};

  for (const field of customFields) {
    const agentShown = field.screens.edit?.["ticket.agent"]?.shown ?? false;
    const customerShown =
      field.screens.edit?.["ticket.customer"]?.shown ?? false;

    fields[field.name] = {
      agent_shown: agentShown,
      customer_shown: customerShown,
    };
  }

  const output = { fields };

  writeFileSync(outputPath, JSON.stringify(output, null, 2) + "\n", "utf8");
  console.log(
    `✓ Exported ${Object.keys(fields).length} field visibility settings to: ${outputPath}`
  );
  console.log(`  Fields: ${Object.keys(fields).join(", ")}`);
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
