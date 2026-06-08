/**
 * Configure Zammad outbound email (SMTP) settings.
 *
 * This should be run AFTER migration is complete and tested.
 *
 * Prerequisites:
 *   - ZAMMAD_URL, ZAMMAD_TOKEN (admin token)
 *   - SMTP credentials (host, port, user, password)
 *
 * Usage:
 *   npm run zammad:configure-outbound-email -- \
 *     --host smtp.example.com \
 *     --port 587 \
 *     --user noreply@legal-intake.ti.trilogy.com \
 *     --password "your-password" \
 *     --from "Legal Intake <noreply@legal-intake.ti.trilogy.com>"
 */
import { config } from "dotenv";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const envPath = process.env.ZAMMAD_ENV_DIR
  ? join(process.env.ZAMMAD_ENV_DIR, ".env")
  : resolve(__dirname, "../staging/.env");
config({ path: envPath });

interface SMTPConfig {
  host: string;
  port: number;
  user: string;
  password: string;
  from: string;
  tls?: boolean;
}

function parseArgs(): SMTPConfig | null {
  const args = process.argv.slice(2);
  const result: Partial<SMTPConfig> = { tls: true };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--host" && args[i + 1]) {
      result.host = args[++i];
    } else if (arg === "--port" && args[i + 1]) {
      result.port = parseInt(args[++i], 10);
    } else if (arg === "--user" && args[i + 1]) {
      result.user = args[++i];
    } else if (arg === "--password" && args[i + 1]) {
      result.password = args[++i];
    } else if (arg === "--from" && args[i + 1]) {
      result.from = args[++i];
    } else if (arg === "--no-tls") {
      result.tls = false;
    }
  }

  if (
    !result.host ||
    !result.port ||
    !result.user ||
    !result.password ||
    !result.from
  ) {
    return null;
  }

  return result as SMTPConfig;
}

async function configureSMTP(config: SMTPConfig): Promise<void> {
  const zammadUrl = process.env.ZAMMAD_URL?.replace(/\/+$/, "") ?? "";
  const token = process.env.ZAMMAD_TOKEN ?? "";

  if (!zammadUrl || !token) {
    throw new Error("Set ZAMMAD_URL and ZAMMAD_TOKEN environment variables");
  }

  const authHeaders = {
    Authorization: `Token token=${token}`,
    "Content-Type": "application/json",
  };

  // Update notification sender
  console.log("Setting notification sender...");
  await fetch(`${zammadUrl}/api/v1/settings/notification_sender`, {
    method: "PUT",
    headers: authHeaders,
    body: JSON.stringify({
      state_current: { value: config.from },
    }),
  });
  console.log(`  ✅ notification_sender: ${config.from}`);

  // Create or update email channel
  console.log("\nConfiguring SMTP channel...");

  const channelPayload = {
    area: "Email::Notification",
    group_id: null,
    active: true,
    options: {
      outbound: {
        adapter: "smtp",
        host: config.host,
        port: config.port,
        user: config.user,
        password: config.password,
        ssl: config.tls ? "tls" : "off",
      },
      inbound: {},
    },
  };

  // Check if notification channel already exists
  const channelsResponse = await fetch(`${zammadUrl}/api/v1/channels`, {
    headers: authHeaders,
  });
  const channels = await channelsResponse.json();

  const notificationChannel = channels.find(
    (ch: any) => ch.area === "Email::Notification"
  );

  if (notificationChannel) {
    console.log("  Updating existing notification channel...");
    await fetch(`${zammadUrl}/api/v1/channels/${notificationChannel.id}`, {
      method: "PUT",
      headers: authHeaders,
      body: JSON.stringify(channelPayload),
    });
    console.log(`  ✅ Updated channel ID ${notificationChannel.id}`);
  } else {
    console.log("  Creating new notification channel...");
    await fetch(`${zammadUrl}/api/v1/channels`, {
      method: "POST",
      headers: authHeaders,
      body: JSON.stringify(channelPayload),
    });
    console.log("  ✅ Created notification channel");
  }

  console.log("\n✅ Outbound email configured successfully!");
  console.log("\nNext steps:");
  console.log("1. Test email notifications by creating a test ticket");
  console.log("2. Verify triggers are sending emails correctly");
  console.log("3. If everything works, consider disabling password login");
}

async function main(): Promise<void> {
  console.log("\n📧 Zammad Outbound Email Configuration\n");

  const config = parseArgs();

  if (!config) {
    console.error("❌ Missing required parameters\n");
    console.log("Usage:");
    console.log("  npm run zammad:configure-outbound-email -- \\");
    console.log("    --host smtp.example.com \\");
    console.log("    --port 587 \\");
    console.log("    --user noreply@legal-intake.ti.trilogy.com \\");
    console.log('    --password "your-password" \\');
    console.log(
      '    --from "Legal Intake <noreply@legal-intake.ti.trilogy.com>"'
    );
    console.log("\nOptional:");
    console.log("  --no-tls    Disable TLS (not recommended)");
    process.exit(1);
  }

  console.log("Configuration:");
  console.log(`  Host: ${config.host}:${config.port}`);
  console.log(`  User: ${config.user}`);
  console.log(`  From: ${config.from}`);
  console.log(`  TLS:  ${config.tls ? "enabled" : "disabled"}`);
  console.log("");

  await configureSMTP(config);
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
