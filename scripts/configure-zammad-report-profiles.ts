#!/usr/bin/env tsx
/**
 * Configure Report Profiles in Zammad from local JSON file.
 * Report Profiles define which reports roles can access.
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

interface ReportProfile {
  id?: number;
  name: string;
  active: boolean;
  condition: Record<string, unknown>;
  role_ids: number[];
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
    "zammad-report-profiles.json"
  );
  const configFile = JSON.parse(readFileSync(configPath, "utf8"));
  const profiles = configFile.report_profiles as ReportProfile[];

  console.log("Configuring Report Profiles in Zammad...");
  console.log(`Found ${profiles.length} profiles to configure\n`);

  // Fetch existing profiles
  const existing = await fetchJson<ReportProfile[]>(
    `${zammadUrl}/api/v1/report_profiles`,
    { headers: authHeaders(token) },
    "GET /api/v1/report_profiles"
  );

  const existingMap = new Map(existing.map((p) => [p.name, p.id!]));

  let created = 0;
  let updated = 0;
  let unchanged = 0;

  for (const profile of profiles) {
    const existingId = existingMap.get(profile.name);

    try {
      if (existingId) {
        // Update existing profile
        await fetchJson(
          `${zammadUrl}/api/v1/report_profiles/${existingId}`,
          {
            method: "PUT",
            headers: authHeaders(token),
            body: JSON.stringify(profile),
          },
          `PUT /api/v1/report_profiles/${existingId} (${profile.name})`
        );
        console.log(`  ✓ ${profile.name}: updated`);
        updated++;
      } else {
        // Create new profile
        await fetchJson(
          `${zammadUrl}/api/v1/report_profiles`,
          {
            method: "POST",
            headers: authHeaders(token),
            body: JSON.stringify(profile),
          },
          `POST /api/v1/report_profiles (${profile.name})`
        );
        console.log(`  ✓ ${profile.name}: created`);
        created++;
      }
    } catch (error: any) {
      if (error.message.includes("unchanged")) {
        console.log(`  - ${profile.name}: unchanged`);
        unchanged++;
      } else {
        console.error(`  ✗ ${profile.name}: ${error.message}`);
      }
    }
  }

  console.log("\n" + "=".repeat(60));
  console.log(`✅ Report Profiles Configuration Complete`);
  console.log(`   Created: ${created}`);
  console.log(`   Updated: ${updated}`);
  console.log(`   Unchanged: ${unchanged}`);
  console.log("=".repeat(60));
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
