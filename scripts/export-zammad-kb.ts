/**
 * Export Knowledge Base configuration from Zammad UI to local JSON file.
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
        "zammad-kb.json"
      );

  console.log("Fetching Knowledge Base from Zammad...");

  try {
    // Fetch the KB (ID 1)
    const kb = await fetchJson<any>(
      `${zammadUrl}/api/v1/knowledge_bases/1`,
      { headers: authHeaders(token) },
      "GET /api/v1/knowledge_bases/1"
    );

    // Clean up timestamps and IDs we don't want to store
    const {
      id,
      created_at,
      updated_at,
      created_by_id,
      updated_by_id,
      translation_ids,
      kb_locale_ids,
      category_ids,
      answer_ids,
      ...rest
    } = kb;

    const config = {
      knowledge_base: rest,
      kb_id: id,
      note: "This configuration represents the Knowledge Base settings. The KB must be initialized in Zammad UI before applying this config.",
    };

    writeFileSync(outputPath, JSON.stringify(config, null, 2) + "\n", "utf8");
    console.log(`✓ Exported Knowledge Base (ID: ${id}) to: ${outputPath}`);
    console.log(`  Active: ${rest.active}`);
    console.log(`  Layout: ${rest.homepage_layout}`);
    console.log(`  Color: ${rest.color_highlight}`);
  } catch (error: any) {
    if (error.message.includes("404")) {
      console.log(
        "❌ Knowledge Base not found. It may not be initialized yet."
      );
      console.log(
        "   To initialize: Go to Admin → Knowledge Base in Zammad UI"
      );
    } else {
      throw error;
    }
  }
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
