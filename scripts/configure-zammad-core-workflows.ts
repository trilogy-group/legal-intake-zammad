import { config } from "dotenv";
import * as fs from "fs";
import * as path from "path";
import { dirname, join, resolve } from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const envPath = process.env.ZAMMAD_ENV_DIR
  ? join(process.env.ZAMMAD_ENV_DIR, ".env")
  : resolve(__dirname, "../.env");
config({ path: envPath });

const ZAMMAD_URL = process.env.ZAMMAD_URL;
const ZAMMAD_TOKEN = process.env.ZAMMAD_TOKEN;
const CONFIG_FILE = path.join(
  process.env.ZAMMAD_CONFIG_DIR || path.join(__dirname, "../config"),
  "zammad-core-workflows.json"
);

interface CoreWorkflow {
  name: string;
  object: string;
  condition_selected: any;
  condition_saved: any;
  perform: any;
  active: boolean;
  stop_after_match: boolean;
  priority: number;
}

function authHeaders(): HeadersInit {
  return {
    Authorization: `Token token=${ZAMMAD_TOKEN}`,
    "Content-Type": "application/json",
    Accept: "application/json",
  };
}

async function configureCoreWorkflows() {
  if (!ZAMMAD_URL || !ZAMMAD_TOKEN) {
    console.error("Set ZAMMAD_URL and ZAMMAD_TOKEN.");
    process.exit(1);
  }

  try {
    const configData = fs.readFileSync(CONFIG_FILE, "utf-8");
    const configJson = JSON.parse(configData);
    const desiredWorkflows: CoreWorkflow[] = configJson.core_workflows || [];

    console.log(`Configuring Core Workflows in Zammad...`);
    console.log(`Found ${desiredWorkflows.length} workflows to configure\n`);

    // Fetch existing workflows
    const response = await fetch(`${ZAMMAD_URL}/api/v1/core_workflows`, {
      headers: authHeaders(),
    });

    if (!response.ok) {
      throw new Error(`Failed to fetch workflows: HTTP ${response.status}`);
    }

    const existingWorkflows = await response.json();

    let created = 0;
    let updated = 0;

    // Process each desired workflow
    for (const desiredWorkflow of desiredWorkflows) {
      const existing = existingWorkflows.find(
        (w: any) => w.name === desiredWorkflow.name
      );

      if (existing) {
        const updateResponse = await fetch(
          `${ZAMMAD_URL}/api/v1/core_workflows/${existing.id}`,
          {
            method: "PUT",
            headers: authHeaders(),
            body: JSON.stringify(desiredWorkflow),
          }
        );

        if (updateResponse.ok) {
          console.log(`  ✓ ${desiredWorkflow.name}: updated`);
          updated++;
        } else {
          const text = await updateResponse.text();
          console.error(
            `  ✗ ${desiredWorkflow.name}: update failed — ${text.slice(0, 200)}`
          );
        }
      } else {
        const createResponse = await fetch(
          `${ZAMMAD_URL}/api/v1/core_workflows`,
          {
            method: "POST",
            headers: authHeaders(),
            body: JSON.stringify(desiredWorkflow),
          }
        );

        if (createResponse.ok) {
          const createdWf = await createResponse.json();
          console.log(
            `  ✓ ${desiredWorkflow.name}: created (id=${createdWf.id})`
          );
          created++;
        } else {
          const text = await createResponse.text();
          console.error(
            `  ✗ ${desiredWorkflow.name}: creation failed — ${text.slice(0, 200)}`
          );
        }
      }
    }

    console.log(`\nDone. Created: ${created}, Updated: ${updated}`);
  } catch (error) {
    console.error("Error configuring Core Workflows:", error);
    process.exit(1);
  }
}

configureCoreWorkflows();
