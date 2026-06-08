/**
 * Export current Zammad ticket states from REST API to local JSON file.
 *
 * This fetches the current state from Zammad and writes it to the local config file,
 * allowing you to sync your local configuration with what's currently in Zammad UI.
 *
 * Prerequisites:
 *   - ZAMMAD_URL — base URL (no trailing path), e.g. https://zammad.example.com
 *   - ZAMMAD_TOKEN — admin HTTP API token
 *
 * Usage:
 *   npm run zammad:export-ticket-states
 *
 * Default output path: `zammad/config/zammad-ticket-states.json`
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

type TicketState = {
  id: number;
  name: string;
  state_type_id: number;
  next_state_id: number | null;
  ignore_escalation: boolean;
  default_create: boolean;
  default_follow_up: boolean;
  note: string | null;
  active: boolean;
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
        "zammad-ticket-states.json"
      );

  console.log("Fetching current ticket states from Zammad...");
  const states = await fetchJson<TicketState[]>(
    `${zammadUrl}/api/v1/ticket_states`,
    { headers: authHeaders(token) },
    "GET /api/v1/ticket_states"
  );

  // Remove id field for config (will be assigned by Zammad)
  const cleanedStates = states.map((state) => {
    const {
      name,
      state_type_id,
      next_state_id,
      ignore_escalation,
      default_create,
      default_follow_up,
      note,
      active,
    } = state;

    return {
      name,
      state_type_id,
      next_state_id,
      ignore_escalation,
      default_create,
      default_follow_up,
      note,
      active,
    };
  });

  const output = { ticket_states: cleanedStates };

  writeFileSync(outputPath, JSON.stringify(output, null, 2) + "\n", "utf8");
  console.log(`✓ Exported ${states.length} ticket states to: ${outputPath}`);
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
