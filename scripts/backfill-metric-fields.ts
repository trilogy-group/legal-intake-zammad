#!/usr/bin/env tsx
/**
 * Backfill metric custom fields for historical Zammad tickets.
 *
 * Fields backfilled:
 *   li_ready_for_signature_at — earliest timestamp when ticket entered state 18
 *   li_owner_assigned_at      — timestamp when owner was first assigned in submitted_to_legal state
 *   li_owner_assigned         — set to true when li_owner_assigned_at is set
 *
 * Usage (via run-zammad-script.sh):
 *   bash zammad/staging/scripts/run-zammad-script.sh backfill-metric-fields.ts
 *
 * Optional env:
 *   DRY_RUN=1            — log what would be updated without writing
 *   START_TICKET_ID=1    — resume from a specific ticket ID
 *   BATCH_SIZE=40        — tickets fetched per page (default 100)
 *   BATCH_PAUSE_MS=60000 — ms to wait between batches (default 0)
 */
import { config } from "dotenv";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const envPath = process.env.ZAMMAD_ENV_DIR
  ? join(process.env.ZAMMAD_ENV_DIR, ".env")
  : resolve(__dirname, "../.env");
config({ path: envPath });

const DRY_RUN = process.env.DRY_RUN === "1";
const START_TICKET_ID = parseInt(process.env.START_TICKET_ID ?? "1", 10);
const PAGE_SIZE = parseInt(process.env.BATCH_SIZE ?? "100", 10);
const BATCH_PAUSE_MS = parseInt(process.env.BATCH_PAUSE_MS ?? "0", 10);


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

interface ZammadTicket {
  id: number;
  state_id: number;
  li_ready_for_signature_at: string | null;
  li_owner_assigned_at: string | null;
  li_owner_assigned: boolean | null;
}

interface ZammadHistoryEntry {
  id: number;
  attribute: string;
  value_from: string;
  value_to: string;
  created_at: string;
}

async function getTicketHistory(
  zammadUrl: string,
  token: string,
  ticketId: number
): Promise<ZammadHistoryEntry[]> {
  const data = await fetchJson<{ history: ZammadHistoryEntry[] }>(
    `${zammadUrl}/api/v1/ticket_history/${ticketId}`,
    { headers: authHeaders(token) },
    `GET /api/v1/ticket_history/${ticketId}`
  );
  return data.history ?? [];
}

async function updateTicket(
  zammadUrl: string,
  token: string,
  ticketId: number,
  fields: Record<string, string>
): Promise<void> {
  if (DRY_RUN) {
    console.log(`  [DRY RUN] Would update ticket ${ticketId}:`, fields);
    return;
  }
  await fetchJson(
    `${zammadUrl}/api/v1/tickets/${ticketId}`,
    {
      method: "PUT",
      headers: authHeaders(token),
      body: JSON.stringify(fields),
    },
    `PUT /api/v1/tickets/${ticketId}`
  );
}

async function main(): Promise<void> {
  const zammadUrl = process.env.ZAMMAD_URL?.replace(/\/+$/, "") ?? "";
  const token = process.env.ZAMMAD_TOKEN ?? "";

  if (!zammadUrl || !token) {
    console.error("Set ZAMMAD_URL and ZAMMAD_TOKEN.");
    process.exit(1);
  }

  if (DRY_RUN) {
    console.log("⚠️  DRY RUN mode — no writes will be made\n");
  }

  console.log("=".repeat(60));
  console.log("Backfilling li_ready_for_signature_at and li_owner_assigned_at");
  console.log(`Starting from ticket ID >= ${START_TICKET_ID}`);
  console.log("=".repeat(60));

  let page = 1;
  let totalProcessed = 0;
  let updatedReadyForSig = 0;
  let updatedOwnerAssigned = 0;
  let skipped = 0;
  let errors = 0;

  while (true) {
    const tickets = await fetchJson<ZammadTicket[]>(
      `${zammadUrl}/api/v1/tickets?page=${page}&per_page=${PAGE_SIZE}&sort_by=id&order_by=asc`,
      { headers: authHeaders(token) },
      `GET /api/v1/tickets page ${page}`
    );

    if (!tickets || tickets.length === 0) break;

    const eligible = tickets.filter((t) => t.id >= START_TICKET_ID);

    for (const ticket of eligible) {
      totalProcessed++;
      const updates: Record<string, string> = {};

      const needsReadyForSig = !ticket.li_ready_for_signature_at;
      const needsOwnerAssigned = !ticket.li_owner_assigned_at;

      if (needsReadyForSig || needsOwnerAssigned) {
        let history: ZammadHistoryEntry[] = [];
        try {
          history = await getTicketHistory(zammadUrl, token, ticket.id);
        } catch (err: any) {
          console.error(`  ✗ Ticket ${ticket.id} history error: ${err.message}`);
          errors++;
        }

        // ── li_ready_for_signature_at ──────────────────────────────────────
        // Earliest timestamp when this ticket entered state 18 (ready_for_signature)
        if (needsReadyForSig && history.length > 0) {
          const stateEntries = history
            .filter(
              (h) =>
                h.attribute === "state" &&
                h.value_to === "ready_for_signature"
            )
            .sort(
              (a, b) =>
                new Date(a.created_at).getTime() -
                new Date(b.created_at).getTime()
            );

          if (stateEntries.length > 0) {
            updates.li_ready_for_signature_at = stateEntries[0].created_at;
          }
        }

        // ── li_owner_assigned_at ──────────────────────────────────────────
        // First time an owner was assigned. Two cases:
        // 1. Normal tickets: attribute="owner", value_from="-", value_to=<name>
        // 2. Migrated tickets: no "owner" history entry at creation — fall back to
        //    the first "last_owner_update_at" entry where value_from="" (first ever set).
        if (needsOwnerAssigned && history.length > 0) {
          const ownerAssignEntries = history
            .filter(
              (h) =>
                h.attribute === "owner" &&
                h.value_from === "-" &&
                h.value_to !== "" &&
                h.value_to !== "-"
            )
            .sort(
              (a, b) =>
                new Date(a.created_at).getTime() -
                new Date(b.created_at).getTime()
            );

          const firstOwnerUpdateEntries = history
            .filter(
              (h) =>
                h.attribute === "last_owner_update_at" &&
                h.value_from === ""
            )
            .sort(
              (a, b) =>
                new Date(a.created_at).getTime() -
                new Date(b.created_at).getTime()
            );

          const firstAssignment =
            ownerAssignEntries[0] ?? firstOwnerUpdateEntries[0];

          if (firstAssignment) {
            updates.li_owner_assigned_at = firstAssignment.created_at;
            updates.li_owner_assigned = "true";
          }
        }
      }

      // ── Apply updates ─────────────────────────────────────────────────────
      if (Object.keys(updates).length === 0) {
        skipped++;
        continue;
      }

      try {
        await updateTicket(zammadUrl, token, ticket.id, updates);
        if (updates.li_ready_for_signature_at) updatedReadyForSig++;
        if (updates.li_owner_assigned_at) updatedOwnerAssigned++;
        console.log(
          `  ✓ Ticket ${ticket.id}: ${Object.keys(updates).join(", ")}`
        );
      } catch (err: any) {
        console.error(`  ✗ Ticket ${ticket.id} update error: ${err.message}`);
        errors++;
      }

      // Small delay to avoid hammering the API
      await new Promise((r) => setTimeout(r, 100));
    }

    if (tickets.length < PAGE_SIZE) break;
    page++;

    if (BATCH_PAUSE_MS > 0) {
      console.log(`\n⏸  Batch ${page - 1} done — pausing ${BATCH_PAUSE_MS / 1000}s before next batch...\n`);
      await new Promise((r) => setTimeout(r, BATCH_PAUSE_MS));
    }
  }

  console.log("\n" + "=".repeat(60));
  console.log("✅ Backfill Complete");
  console.log(`   Tickets processed          : ${totalProcessed}`);
  console.log(`   li_ready_for_signature_at  : ${updatedReadyForSig}`);
  console.log(`   li_owner_assigned_at       : ${updatedOwnerAssigned}`);
  console.log(`   Skipped (no data / already set): ${skipped}`);
  console.log(`   Errors                     : ${errors}`);
  console.log("=".repeat(60));

  if (errors > 0) {
    console.log(
      "\n⚠️  Some tickets failed. Re-run with START_TICKET_ID=<last_id> to resume."
    );
    process.exit(1);
  }
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
