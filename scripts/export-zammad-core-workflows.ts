import { config } from "dotenv";
import * as fs from "fs";
import * as path from "path";
import { dirname } from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load .env from environment-specific directory
const envPath = process.env.ZAMMAD_ENV_DIR
  ? path.join(process.env.ZAMMAD_ENV_DIR, ".env")
  : path.join(__dirname, "..", "staging", ".env");
config({ path: envPath });

const ZAMMAD_URL = process.env.ZAMMAD_URL;
const ZAMMAD_TOKEN = process.env.ZAMMAD_TOKEN;
const CONFIG_DIR =
  process.env.ZAMMAD_CONFIG_DIR ||
  path.join(__dirname, "..", "staging", "config");
const OUTPUT_FILE = path.join(CONFIG_DIR, "zammad-core-workflows.json");

async function exportCoreWorkflows() {
  try {
    console.log("Fetching current Core Workflows from Zammad...");

    const response = await fetch(`${ZAMMAD_URL}/api/v1/core_workflows`, {
      headers: {
        Authorization: `Bearer ${ZAMMAD_TOKEN}`,
        "Content-Type": "application/json",
      },
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${await response.text()}`);
    }

    const workflows = await response.json();

    // Remove internal fields that shouldn't be in config
    const cleanWorkflows = workflows.map((workflow: any) => {
      const {
        id,
        created_at,
        updated_at,
        created_by_id,
        updated_by_id,
        ...cleanWorkflow
      } = workflow;
      return cleanWorkflow;
    });

    // Write to file
    fs.writeFileSync(
      OUTPUT_FILE,
      JSON.stringify({ core_workflows: cleanWorkflows }, null, 2)
    );

    console.log(
      `✓ Exported ${cleanWorkflows.length} Core Workflows to: ${OUTPUT_FILE}`
    );
  } catch (error) {
    console.error("Error exporting Core Workflows:", error);
    process.exit(1);
  }
}

exportCoreWorkflows();
