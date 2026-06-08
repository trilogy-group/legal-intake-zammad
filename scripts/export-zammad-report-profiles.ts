#!/usr/bin/env tsx
/**
 * Export Report Profiles from Zammad UI to local JSON file.
 * Report Profiles define which reports roles can access.
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

interface ReportProfile {
  id: number;
  name: string;
  active: boolean;
  condition: Record<string, unknown>;
  role_ids: number[];
  created_by_id: number;
  updated_by_id: number;
  created_at: string;
  updated_at: string;
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
        "zammad-report-profiles.json"
      );

  console.log("Fetching Report Profiles from Zammad...");

  const profiles = await fetchJson<ReportProfile[]>(
    `${zammadUrl}/api/v1/report_profiles`,
    { headers: authHeaders(token) },
    "GET /api/v1/report_profiles"
  );

  // Clean up - remove IDs and timestamps
  const cleanedProfiles = profiles.map((profile) => {
    const {
      id,
      created_by_id,
      updated_by_id,
      created_at,
      updated_at,
      ...clean
    } = profile;
    return clean;
  });

  const config = {
    report_profiles: cleanedProfiles,
  };

  writeFileSync(outputPath, JSON.stringify(config, null, 2) + "\n", "utf8");

  console.log(
    `✓ Exported ${cleanedProfiles.length} report profiles to: ${outputPath}`
  );
  cleanedProfiles.forEach((profile) => {
    console.log(
      `  - "${profile.name}" (active: ${profile.active}, roles: ${profile.role_ids.join(", ")})`
    );
  });
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
