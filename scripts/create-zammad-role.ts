/**
 * Create a new Zammad role interactively or via CLI arguments.
 *
 * Prerequisites:
 *   - ZAMMAD_URL, ZAMMAD_TOKEN (admin token with admin.role permission)
 *
 * Usage:
 *   npm run zammad:create-role
 *   or
 *   npm run zammad:create-role -- --name "Legal Viewer" --note "Read-only access for legal team" --template agent --access read
 *
 * Options:
 *   --name <string>        Role name (required)
 *   --note <string>        Role description
 *   --template <string>    Base role to copy from: agent, admin, customer, legal_admin (default: agent)
 *   --access <string>      Group access level: full, read, change (default: full)
 *   --groups <string>      Comma-separated group IDs (default: all intake groups 2,6,7)
 *   --apply                Automatically apply to Zammad after adding to config
 */
import { config } from "dotenv";
import { execSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";

config({ path: resolve(dirname(fileURLToPath(import.meta.url)), "../.env") });

const __dirname = dirname(fileURLToPath(import.meta.url));

const roleSchema = z.object({
  name: z.string(),
  active: z.boolean(),
  default_at_signup: z.boolean().optional(),
  note: z.string().optional(),
  permission_ids: z.array(z.number()).optional(),
  knowledge_base_permission_ids: z.array(z.number()).optional(),
  group_ids: z.record(z.array(z.string())).optional(),
  preferences: z.record(z.any()).optional(),
});

const configSchema = z.object({
  roles: z.array(roleSchema),
});

type Role = z.infer<typeof roleSchema>;

// Template permission IDs
const TEMPLATES: Record<string, number[]> = {
  agent: [57, 59, 62, 65, 67],
  admin: [1, 61, 63, 65, 66, 67],
  customer: [66, 68, 69, 70, 72, 73, 76],
  legal_admin: [57, 59, 62, 65, 67],
};

// Parse CLI arguments
function parseArgs(): {
  name?: string;
  note?: string;
  template: string;
  access: string;
  groups: string;
  apply: boolean;
} {
  const args = process.argv.slice(2);
  const result: any = {
    template: "agent",
    access: "full",
    groups: "2,6,7",
    apply: false,
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--name" && args[i + 1]) {
      result.name = args[++i];
    } else if (arg === "--note" && args[i + 1]) {
      result.note = args[++i];
    } else if (arg === "--template" && args[i + 1]) {
      result.template = args[++i];
    } else if (arg === "--access" && args[i + 1]) {
      result.access = args[++i];
    } else if (arg === "--groups" && args[i + 1]) {
      result.groups = args[++i];
    } else if (arg === "--apply") {
      result.apply = true;
    }
  }

  return result;
}

// Prompt for input if not provided
async function prompt(question: string): Promise<string> {
  process.stdout.write(question);
  return new Promise((resolve) => {
    process.stdin.once("data", (data) => {
      resolve(data.toString().trim());
    });
  });
}

async function main(): Promise<void> {
  const args = parseArgs();

  console.log("\n🎭 Zammad Role Creator\n");

  // Get role name
  let roleName = args.name;
  if (!roleName) {
    roleName = await prompt("Role name: ");
    if (!roleName) {
      console.error("❌ Role name is required");
      process.exit(1);
    }
  }

  // Get role description
  let roleNote = args.note;
  if (!roleNote) {
    roleNote = await prompt(
      "Role description (optional, press Enter to skip): "
    );
  }

  // Get template
  let template = args.template;
  if (!args.name) {
    console.log(
      "\nAvailable templates: agent, admin, customer, legal_admin (default: agent)"
    );
    const templateInput = await prompt("Template to base this role on: ");
    if (templateInput) template = templateInput;
  }

  if (!TEMPLATES[template]) {
    console.error(
      `❌ Invalid template: ${template}. Use: agent, admin, customer, or legal_admin`
    );
    process.exit(1);
  }

  // Get access level
  let accessLevel = args.access;
  if (!args.name) {
    console.log(
      "\nAccess levels: full (all permissions), read (view only), change (view + edit)"
    );
    const accessInput = await prompt("Group access level (default: full): ");
    if (accessInput) accessLevel = accessInput;
  }

  const accessLevels: Record<string, string[]> = {
    full: ["full"],
    read: ["read", "overview"],
    change: ["read", "change", "overview"],
  };

  if (!accessLevels[accessLevel]) {
    console.error(
      `❌ Invalid access level: ${accessLevel}. Use: full, read, or change`
    );
    process.exit(1);
  }

  // Get group IDs
  let groupIds = args.groups;
  if (!args.name) {
    const groupInput = await prompt(
      "Group IDs (comma-separated, default: 2,6,7): "
    );
    if (groupInput) groupIds = groupInput;
  }

  const groupIdArray = groupIds.split(",").map((id) => id.trim());

  // Build group_ids object
  const group_ids: Record<string, string[]> = {};
  for (const groupId of groupIdArray) {
    group_ids[groupId] = accessLevels[accessLevel];
  }

  // Build the new role
  const newRole: Role = {
    name: roleName,
    preferences: {},
    default_at_signup: false,
    active: true,
    note: roleNote || `Custom role: ${roleName}`,
    permission_ids: TEMPLATES[template],
    knowledge_base_permission_ids: [],
    group_ids: group_ids,
  };

  // Read existing roles
  const configPath = join(
    process.env.ZAMMAD_CONFIG_DIR || join(__dirname, "../config"),
    "zammad-roles.json"
  );
  let raw: string;
  try {
    raw = readFileSync(configPath, "utf8");
  } catch {
    console.error(`❌ Cannot read: ${configPath}`);
    process.exit(1);
  }

  const parsed = configSchema.safeParse(JSON.parse(raw));
  if (!parsed.success) {
    console.error("❌ Invalid config:", parsed.error.flatten());
    process.exit(1);
  }

  const config = parsed.data;

  // Check if role already exists
  const existingRole = config.roles.find(
    (r) => r.name.toLowerCase() === roleName.toLowerCase()
  );
  if (existingRole) {
    console.error(`❌ Role "${roleName}" already exists`);
    process.exit(1);
  }

  // Add new role
  config.roles.push(newRole);

  // Write back to file
  writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n", "utf8");

  console.log(`\n✅ Role "${roleName}" added to config`);
  console.log("\nRole details:");
  console.log(`  Name: ${newRole.name}`);
  console.log(`  Note: ${newRole.note}`);
  console.log(`  Template: ${template}`);
  console.log(`  Group Access: ${accessLevel} for groups ${groupIds}`);

  // Apply to Zammad if requested
  if (args.apply) {
    console.log("\n🚀 Applying to Zammad...\n");
    try {
      execSync("npm run zammad:configure-roles", {
        cwd: resolve(__dirname, ".."),
        stdio: "inherit",
      });
      console.log("\n✅ Role created in Zammad");
    } catch (error) {
      console.error("\n❌ Failed to apply role to Zammad");
      process.exit(1);
    }
  } else {
    console.log(
      "\n💡 Run 'npm run zammad:configure-roles' to apply this role to Zammad"
    );
  }

  process.exit(0);
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
