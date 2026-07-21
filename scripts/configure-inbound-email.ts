/**
 * Apply declarative settings for the inbound redline email channel
 * (Email::Account) via REST — the MUTABLE-settings half of the inbound-email
 * config-as-code story.
 *
 * Channel CREATION is a one-time bootstrap (scripts/
 * bootstrap-inbound-email-channel.rb via Rails runner — REST cannot create an
 * inbound-only channel without a live SMTP round-trip). This script manages
 * the settings that change over time, idempotently:
 *   - active (enable/disable polling)
 *   - group  (which group tickets from unmatched mail land in)
 *
 * Reads zammad-config/<env>/zammad-email-channels.json:
 *   { "email_channels": [ { "user": "...", "active": true, "group": "Users" } ] }
 *
 * NOTE on local: zammad-config/local/zammad-email-channels.json deliberately
 * sets active=false — all environments share ONE WorkMail inbox and fetching
 * DELETES mail (keep_on_server=false), so an active local channel would steal
 * staging's replies. Flip it on locally only while testing inbound, then off.
 *
 * Matching is by inbound user (the mailbox address). A channel not found in
 * Zammad is reported and SKIPPED (run the bootstrap first) — this script never
 * creates or deletes channels.
 *
 * Usage (via run-zammad-script.sh):
 *   bash scripts/run-zammad-script.sh <env> configure-inbound-email.ts
 */
import { config } from "dotenv";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";

const __dirname = dirname(fileURLToPath(import.meta.url));
const envPath = process.env.ZAMMAD_ENV_DIR
  ? join(process.env.ZAMMAD_ENV_DIR, ".env")
  : resolve(__dirname, "../zammad-config/local/.env");
config({ path: envPath });

const channelSchema = z.object({
  user: z.string().min(1),
  active: z.boolean().default(true),
  group: z.string().min(1),
});
const configSchema = z.object({
  email_channels: z.array(channelSchema),
});

function authHeaders(token: string): HeadersInit {
  return {
    Authorization: `Token token=${token}`,
    "Content-Type": "application/json",
    Accept: "application/json",
  };
}

interface ZammadChannel {
  id: number;
  area: string;
  active: boolean;
  group_id: number | null;
  options?: {
    inbound?: { options?: { user?: string } };
  };
}

interface ZammadGroup {
  id: number;
  name: string;
}

async function main(): Promise<void> {
  const zammadUrl = (process.env.ZAMMAD_URL ?? "").replace(/\/+$/, "");
  const token = process.env.ZAMMAD_TOKEN ?? "";
  if (!zammadUrl || !token) {
    throw new Error("Set ZAMMAD_URL and ZAMMAD_TOKEN environment variables");
  }

  const configDir =
    process.env.ZAMMAD_CONFIG_DIR ?? resolve(__dirname, "../zammad-config/local");
  const configPath = join(configDir, "zammad-email-channels.json");

  let raw: string;
  try {
    raw = readFileSync(configPath, "utf-8");
  } catch {
    console.log(`No zammad-email-channels.json in ${configDir} — nothing to do.`);
    return;
  }
  const desired = configSchema.parse(JSON.parse(raw));

  const headers = authHeaders(token);

  // channels_email returns { assets: { Channel: { id: {...} } } }
  const channelsRes = await fetch(`${zammadUrl}/api/v1/channels_email`, {
    headers,
  });
  if (!channelsRes.ok) {
    throw new Error(`GET channels_email failed: HTTP ${channelsRes.status}`);
  }
  const channelsBody = (await channelsRes.json()) as {
    assets?: { Channel?: Record<string, ZammadChannel> };
  };
  const channels = Object.values(channelsBody.assets?.Channel ?? {}).filter(
    (c) => c.area === "Email::Account"
  );

  const groupsRes = await fetch(`${zammadUrl}/api/v1/groups?per_page=200`, {
    headers,
  });
  if (!groupsRes.ok) {
    throw new Error(`GET groups failed: HTTP ${groupsRes.status}`);
  }
  const groups = (await groupsRes.json()) as ZammadGroup[];

  let unchanged = 0;
  let updated = 0;
  let missing = 0;

  for (const want of desired.email_channels) {
    const channel = channels.find(
      (c) => c.options?.inbound?.options?.user === want.user
    );
    if (!channel) {
      console.log(
        `MISSING: no Email::Account channel for ${want.user} — run the bootstrap (scripts/bootstrap-inbound-email-channel.rb) first.`
      );
      missing++;
      continue;
    }

    const group = groups.find((g) => g.name === want.group);
    if (!group) {
      throw new Error(`Group '${want.group}' not found in Zammad`);
    }

    const needsActiveFlip = channel.active !== want.active;
    const needsGroupChange = channel.group_id !== group.id;

    if (!needsActiveFlip && !needsGroupChange) {
      console.log(`unchanged: ${want.user} (active=${want.active}, group=${want.group})`);
      unchanged++;
      continue;
    }

    if (needsGroupChange) {
      const res = await fetch(
        `${zammadUrl}/api/v1/channels_email_group/${channel.id}`,
        {
          method: "POST",
          headers,
          body: JSON.stringify({ group_id: group.id }),
        }
      );
      if (!res.ok) {
        throw new Error(
          `set group for channel ${channel.id} failed: HTTP ${res.status}`
        );
      }
      console.log(`updated: ${want.user} group → ${want.group}`);
    }

    if (needsActiveFlip) {
      const verb = want.active ? "enable" : "disable";
      const res = await fetch(`${zammadUrl}/api/v1/channels_email_${verb}`, {
        method: "POST",
        headers,
        body: JSON.stringify({ id: channel.id }),
      });
      if (!res.ok) {
        throw new Error(
          `${verb} channel ${channel.id} failed: HTTP ${res.status}`
        );
      }
      console.log(`updated: ${want.user} active → ${want.active}`);
    }
    updated++;
  }

  console.log(
    `\nDone. ${updated} updated, ${unchanged} unchanged, ${missing} missing (need bootstrap).`
  );
  if (missing > 0) {
    // Missing channels are a soft failure: config intent is not fully applied,
    // but we don't hard-fail CI — the bootstrap is a deliberate one-time step.
    process.exitCode = 0;
  }
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
