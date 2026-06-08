#!/usr/bin/env tsx
/**
 * Backfill li_invoice_reference for historical Zammad tickets.
 *
 * The field is derived entirely from data already on each ticket:
 *   ticket.id      — Zammad's internal ticket ID
 *   li_business_unit
 *   li_product
 *
 * Format: {ticketId} – {BU} – {Product}
 * Missing segments are omitted: e.g. "24 – APAC" when product is absent.
 *
 * Usage (via run-zammad-script.sh):
 *   bash zammad/staging/scripts/run-zammad-script.sh backfill-invoice-reference.ts
 *
 * Optional env:
 *   DRY_RUN=1            — log what would be updated without writing
 *   START_TICKET_ID=1    — resume from a specific ticket ID
 *   BATCH_SIZE=100       — tickets fetched per page (default 100)
 *   BATCH_PAUSE_MS=0     — ms to wait between batches (default 0)
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
  number: string;
  li_business_unit: string | null;
  li_product: string | null;
  li_invoice_reference: string | null;
}

function buildInvoiceReference(ticket: ZammadTicket): string {
  const ticketNumberStr = String(ticket.id);

  return [
    ticketNumberStr,
    ticket.li_business_unit?.trim() || null,
    ticket.li_product?.trim() || null,
  ]
    .filter(Boolean)
    .join(" \u2013 ");
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
  console.log("Backfilling li_invoice_reference");
  console.log(`Starting from ticket ID >= ${START_TICKET_ID}`);
  console.log("=".repeat(60));

  let page = 1;
  let totalProcessed = 0;
  let updated = 0;
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

      if (ticket.li_invoice_reference?.trim()) {
        skipped++;
        continue;
      }

      const value = buildInvoiceReference(ticket);

      try {
        await updateTicket(zammadUrl, token, ticket.id, {
          li_invoice_reference: value,
        });
        updated++;
        console.log(`  ✓ Ticket ${ticket.id} (${ticket.number}): "${value}"`);
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);
        console.error(`  ✗ Ticket ${ticket.id} update error: ${msg}`);
        errors++;
      }

      // Small delay to avoid hammering the API
      await new Promise((r) => setTimeout(r, 100));
    }

    if (tickets.length < PAGE_SIZE) break;
    page++;

    if (BATCH_PAUSE_MS > 0) {
      console.log(
        `\n⏸  Batch ${page - 1} done — pausing ${BATCH_PAUSE_MS / 1000}s before next batch...\n`
      );
      await new Promise((r) => setTimeout(r, BATCH_PAUSE_MS));
    }
  }

  console.log("\n" + "=".repeat(60));
  console.log("✅ Backfill Complete");
  console.log(`   Tickets processed : ${totalProcessed}`);
  console.log(`   Updated           : ${updated}`);
  console.log(`   Skipped (already set): ${skipped}`);
  console.log(`   Errors            : ${errors}`);
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
