import { config } from "dotenv";
import * as fs from "fs";
import * as path from "path";
import { dirname } from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const envPath = process.env.ZAMMAD_ENV_DIR
  ? path.join(process.env.ZAMMAD_ENV_DIR, ".env")
  : path.join(__dirname, "..", "staging", ".env");
config({ path: envPath });

const ZAMMAD_URL = process.env.ZAMMAD_URL;
const ZAMMAD_TOKEN = process.env.ZAMMAD_TOKEN;
const CONFIG_FILE = process.env.ZAMMAD_CONFIG_DIR
  ? path.join(process.env.ZAMMAD_CONFIG_DIR, "zammad-field-visibility.json")
  : path.join(
      __dirname,
      "..",
      "staging",
      "config",
      "zammad-field-visibility.json"
    );

interface FieldVisibilityConfig {
  name: string;
  agent_shown: boolean;
  customer_shown: boolean;
}

async function configureFieldVisibility() {
  try {
    console.log("[dotenv@17.3.1] injecting env (2) from zammad/.env");
    console.log("Configuring field visibility...\n");

    // Read config file
    const configData = fs.readFileSync(CONFIG_FILE, "utf-8");
    const config = JSON.parse(configData);
    const fieldsConfig = config.fields || {};

    // Fetch all attributes
    const response = await fetch(
      `${ZAMMAD_URL}/api/v1/object_manager_attributes`,
      {
        headers: {
          Authorization: `Bearer ${ZAMMAD_TOKEN}`,
          "Content-Type": "application/json",
        },
      }
    );

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const attributes = await response.json();

    let updated = 0;
    let unchanged = 0;

    for (const [fieldName, fieldConfig] of Object.entries(fieldsConfig)) {
      const attr = attributes.find(
        (a: any) => a.object === "Ticket" && a.name === fieldName
      );

      if (!attr) {
        console.log(`  ${fieldName}: not found`);
        continue;
      }

      // Check if update is needed
      const currentAgentShown =
        attr.screens?.edit?.["ticket.agent"]?.shown || false;
      const currentCustomerShown =
        attr.screens?.edit?.["ticket.customer"]?.shown || false;

      if (
        currentAgentShown === (fieldConfig as any).agent_shown &&
        currentCustomerShown === (fieldConfig as any).customer_shown
      ) {
        console.log(`  ${attr.display}: unchanged`);
        unchanged++;
        continue;
      }

      // Update visibility
      if (!attr.screens) attr.screens = {};
      if (!attr.screens.edit) attr.screens.edit = {};
      if (!attr.screens.edit["ticket.agent"])
        attr.screens.edit["ticket.agent"] = {};
      if (!attr.screens.edit["ticket.customer"])
        attr.screens.edit["ticket.customer"] = {};

      attr.screens.edit["ticket.agent"].shown = (
        fieldConfig as any
      ).agent_shown;
      attr.screens.edit["ticket.customer"].shown = (
        fieldConfig as any
      ).customer_shown;

      const updateResponse = await fetch(
        `${ZAMMAD_URL}/api/v1/object_manager_attributes/${attr.id}`,
        {
          method: "PUT",
          headers: {
            Authorization: `Bearer ${ZAMMAD_TOKEN}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(attr),
        }
      );

      if (updateResponse.ok) {
        console.log(`  ${attr.display}: updated`);
        updated++;
      } else {
        console.log(`  ${attr.display}: update failed`);
      }

      await new Promise((resolve) => setTimeout(resolve, 200));
    }

    if (updated > 0) {
      console.log("\nExecuting migrations...");
      const migrateResponse = await fetch(
        `${ZAMMAD_URL}/api/v1/object_manager_attributes_execute_migrations`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${ZAMMAD_TOKEN}`,
            "Content-Type": "application/json",
          },
        }
      );

      if (migrateResponse.ok) {
        console.log("✓ Migrations executed");
      }
    }

    console.log(`\nDone. Updated: ${updated}, Unchanged: ${unchanged}`);
  } catch (error) {
    console.error("Error:", error);
    process.exit(1);
  }
}

configureFieldVisibility();
