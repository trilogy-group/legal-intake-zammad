/**
 * Initialize/Configure Knowledge Base in Zammad from local JSON file.
 * This creates the KB if it doesn't exist, or updates it if it does.
 */
import { config } from "dotenv";
import { readFileSync } from "node:fs";
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

async function checkKBExists(
  zammadUrl: string,
  token: string
): Promise<boolean> {
  try {
    await fetchJson(
      `${zammadUrl}/api/v1/knowledge_bases/1`,
      { headers: authHeaders(token) },
      "GET /api/v1/knowledge_bases/1"
    );
    return true;
  } catch (error: any) {
    if (error.message.includes("404")) {
      return false;
    }
    throw error;
  }
}

async function createKB(
  zammadUrl: string,
  token: string,
  kbConfig: any
): Promise<void> {
  console.log("Creating new Knowledge Base...");

  // Create KB with initial locale
  const payload = {
    ...kbConfig,
    kb_locale_attributes: {
      system_locale_id: 1, // en-us
      title: "FAQs",
    },
  };

  const result = await fetchJson(
    `${zammadUrl}/api/v1/knowledge_bases`,
    {
      method: "POST",
      headers: authHeaders(token),
      body: JSON.stringify(payload),
    },
    "POST /api/v1/knowledge_bases"
  );

  console.log("✅ Knowledge Base created successfully");
  console.log("   ID:", (result as any).id);
  console.log("   This also created KB permissions for roles");
}

async function updateKB(
  zammadUrl: string,
  token: string,
  kbConfig: any
): Promise<void> {
  console.log("Updating existing Knowledge Base (ID: 1)...");

  await fetchJson(
    `${zammadUrl}/api/v1/knowledge_bases/1`,
    {
      method: "PUT",
      headers: authHeaders(token),
      body: JSON.stringify(kbConfig),
    },
    "PUT /api/v1/knowledge_bases/1"
  );

  console.log("✅ Knowledge Base updated successfully");
}

async function main(): Promise<void> {
  const zammadUrl = process.env.ZAMMAD_URL?.replace(/\/+$/, "") ?? "";
  const token = process.env.ZAMMAD_TOKEN ?? "";

  if (!zammadUrl || !token) {
    console.error("Set ZAMMAD_URL and ZAMMAD_TOKEN.");
    process.exit(1);
  }

  const configPath = join(
    process.env.ZAMMAD_CONFIG_DIR || join(__dirname, "../config"),
    "zammad-kb.json"
  );
  const configFile = JSON.parse(readFileSync(configPath, "utf8"));
  const kbConfig = configFile.knowledge_base;

  console.log("Checking if Knowledge Base exists...");
  const exists = await checkKBExists(zammadUrl, token);

  if (exists) {
    await updateKB(zammadUrl, token, kbConfig);
  } else {
    await createKB(zammadUrl, token, kbConfig);
  }

  console.log("\n✓ Knowledge Base configuration applied");
  console.log(
    '  Note: Run "npm run zammad:configure-roles" to apply KB permissions to roles'
  );
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
