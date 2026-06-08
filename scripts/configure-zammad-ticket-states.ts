/**
 * Apply declarative Zammad ticket states via REST API.
 *
 * Prerequisites:
 *   - ZAMMAD_URL, ZAMMAD_TOKEN (admin token with admin permission)
 *
 * Usage:
 *   npm run zammad:configure-ticket-states
 *
 * Note: States are matched by name (case-sensitive).
 */
import { config } from "dotenv";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";

const __dirname = dirname(fileURLToPath(import.meta.url));
const envPath = process.env.ZAMMAD_ENV_DIR
  ? join(process.env.ZAMMAD_ENV_DIR, ".env")
  : resolve(__dirname, "../.env");
config({ path: envPath });

const ticketStateSchema = z.object({
  name: z.string(),
  state_type_id: z.number(),
  next_state_id: z.number().nullable(),
  ignore_escalation: z.boolean().optional(),
  default_create: z.boolean().optional(),
  default_follow_up: z.boolean().optional(),
  note: z.string().nullable().optional(),
  active: z.boolean(),
});

const configSchema = z.object({
  ticket_states: z.array(ticketStateSchema),
});

type TicketState = z.infer<typeof ticketStateSchema>;
type ZammadTicketState = TicketState & { id: number };

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

function differs(existing: ZammadTicketState, desired: TicketState): boolean {
  const keys: (keyof TicketState)[] = Object.keys(
    desired
  ) as (keyof TicketState)[];
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

  if (!zammadUrl || !token) {
    console.error("Set ZAMMAD_URL and ZAMMAD_TOKEN.");
    process.exit(1);
  }

  const configPath = process.argv[2]
    ? resolve(process.cwd(), process.argv[2])
    : join(
        process.env.ZAMMAD_CONFIG_DIR || join(__dirname, "../config"),
        "zammad-ticket-states.json"
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

  const desired = parsed.data.ticket_states;

  const existing = await fetchJson<ZammadTicketState[]>(
    `${zammadUrl}/api/v1/ticket_states`,
    { headers: authHeaders(token) },
    "GET /api/v1/ticket_states"
  );

  const byName = new Map(existing.map((s) => [s.name, s]));
  const processedIds = new Set<number>();

  for (const state of desired) {
    const existingState = byName.get(state.name);

    if (!existingState) {
      const created = await fetchJson<ZammadTicketState>(
        `${zammadUrl}/api/v1/ticket_states`,
        {
          method: "POST",
          headers: authHeaders(token),
          body: JSON.stringify(state),
        },
        `POST /api/v1/ticket_states (${state.name})`
      );
      console.log(`  ${state.name}: created (id=${created.id})`);
      processedIds.add(created.id);
      continue;
    }

    processedIds.add(existingState.id);

    if (!differs(existingState, state)) {
      console.log(`  ${state.name}: unchanged`);
      continue;
    }

    await fetchJson<ZammadTicketState>(
      `${zammadUrl}/api/v1/ticket_states/${existingState.id}`,
      {
        method: "PUT",
        headers: authHeaders(token),
        body: JSON.stringify({ id: existingState.id, ...state }),
      },
      `PUT /api/v1/ticket_states/${existingState.id} (${state.name})`
    );
    console.log(`  ${state.name}: updated`);
  }

  console.log("Done.");
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
