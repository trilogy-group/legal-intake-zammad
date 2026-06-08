/**
 * Disable password login in Zammad (force OAuth only).
 *
 * This should be run AFTER:
 * 1. All data migration is complete
 * 2. Google OAuth is tested and working
 * 3. All users have successfully logged in via OAuth at least once
 *
 * Prerequisites:
 *   - ZAMMAD_URL, ZAMMAD_TOKEN (admin token)
 *
 * Usage:
 *   npm run zammad:disable-password-login
 *
 * To re-enable password login:
 *   npm run zammad:disable-password-login -- --enable
 */
import { config } from "dotenv";
import { execSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

config({ path: resolve(dirname(fileURLToPath(import.meta.url)), "../.env") });

const __dirname = dirname(fileURLToPath(import.meta.url));

async function main(): Promise<void> {
  const enable = process.argv.includes("--enable");
  const action = enable ? "ENABLE" : "DISABLE";
  const newValue = !enable; // user_show_password_login: false = disabled

  console.log(`\n🔒 ${action} Password Login\n`);

  if (!enable) {
    console.log(
      "⚠️  WARNING: This will force all users to use Google OAuth only."
    );
    console.log("");
    console.log("Before proceeding, ensure:");
    console.log("  ✅ Google OAuth is enabled and tested");
    console.log("  ✅ All users have logged in via OAuth at least once");
    console.log("  ✅ You have a backup admin account with OAuth access");
    console.log("");
  }

  // Read settings config
  const configPath = join(
    process.env.ZAMMAD_CONFIG_DIR || join(__dirname, "../config"),
    "zammad-settings.json"
  );
  const raw = readFileSync(configPath, "utf8");
  const settingsConfig = JSON.parse(raw);

  // Update user_show_password_login
  const oldValue = settingsConfig.settings.user_show_password_login;
  settingsConfig.settings.user_show_password_login = newValue;

  // Write back to file
  writeFileSync(
    configPath,
    JSON.stringify(settingsConfig, null, 2) + "\n",
    "utf8"
  );

  console.log(`Updated zammad-settings.json:`);
  console.log(`  user_show_password_login: ${oldValue} → ${newValue}`);
  console.log("");

  // Apply to Zammad
  console.log("Applying configuration to Zammad...\n");
  try {
    execSync("npm run zammad:configure-settings", {
      cwd: resolve(__dirname, "../.."),
      stdio: "inherit",
    });

    console.log(`\n✅ Password login ${action}D successfully!`);

    if (!enable) {
      console.log("\n⚠️  Users can now ONLY log in via Google OAuth.");
      console.log("To re-enable password login:");
      console.log("  npm run zammad:disable-password-login -- --enable");
    } else {
      console.log("\n✅ Users can now log in with password or OAuth.");
    }
  } catch (error) {
    console.error("\n❌ Failed to apply configuration");
    // Revert the file change
    settingsConfig.settings.user_show_password_login = oldValue;
    writeFileSync(
      configPath,
      JSON.stringify(settingsConfig, null, 2) + "\n",
      "utf8"
    );
    console.log("Reverted configuration file");
    process.exit(1);
  }
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
