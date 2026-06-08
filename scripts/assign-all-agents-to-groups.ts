import { config } from "dotenv";
import "dotenv/config";
import { dirname, join, resolve } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const envPath = process.env.ZAMMAD_ENV_DIR
  ? join(process.env.ZAMMAD_ENV_DIR, ".env")
  : resolve(__dirname, "../staging/.env");
config({ path: envPath });

const ZAMMAD_URL = process.env.ZAMMAD_URL || "http://localhost:3000";
const ZAMMAD_TOKEN = process.env.ZAMMAD_TOKEN;

if (!ZAMMAD_TOKEN) {
  console.error("ZAMMAD_TOKEN is not set");
  process.exit(1);
}

const headers = {
  Authorization: `Token token=${ZAMMAD_TOKEN}`,
  "Content-Type": "application/json",
};

async function getGroups() {
  const response = await fetch(`${ZAMMAD_URL}/api/v1/groups`, {
    headers,
  });
  if (!response.ok) {
    throw new Error(`Failed to fetch groups: ${response.statusText}`);
  }
  return await response.json();
}

async function listUsers() {
  const response = await fetch(`${ZAMMAD_URL}/api/v1/users`, {
    headers,
  });
  if (!response.ok) {
    throw new Error(`Failed to fetch users: ${response.statusText}`);
  }
  return await response.json();
}

async function updateUser(userId: number, data: any) {
  const response = await fetch(`${ZAMMAD_URL}/api/v1/users/${userId}`, {
    method: "PUT",
    headers,
    body: JSON.stringify(data),
  });
  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Failed to update user: ${response.statusText} - ${error}`);
  }
  return await response.json();
}

async function main() {
  console.log("Fetching groups...");
  const groups = await getGroups();
  const activeGroups = groups.filter((g: any) => g.active);
  const groupIds = activeGroups.map((g: any) => g.id);

  console.log(
    `Found ${activeGroups.length} active groups: ${activeGroups.map((g: any) => g.name).join(", ")}\n`
  );

  const fullGroupIdsObject = Object.fromEntries(
    groupIds.map((id: number) => [id.toString(), ["full"]])
  );

  console.log("Fetching all users...");
  const users = await listUsers();

  // Filter for Admin (role_id: 1), Agent (role_id: 2), and Legal Admin (role_id: 4)
  const targetUsers = users.filter(
    (u: any) =>
      u.active &&
      u.role_ids &&
      (u.role_ids.includes(1) ||
        u.role_ids.includes(2) ||
        u.role_ids.includes(4))
  );

  console.log(
    `Found ${targetUsers.length} active Admin/Agent/Legal Admin users\n`
  );

  let updated = 0;
  let skipped = 0;

  for (const user of targetUsers) {
    const roleNames: string[] = [];
    const isAdmin = user.role_ids.includes(1);
    const isAgent = user.role_ids.includes(2);
    const isLegalAdmin = user.role_ids.includes(4);

    if (isAdmin) roleNames.push("Admin");
    if (isAgent) roleNames.push("Agent");
    if (isLegalAdmin) roleNames.push("Legal Admin");

    const currentGroups = user.group_ids || {};
    const currentGroupCount = Object.keys(currentGroups).length;

    // All roles (Admin, Agent, Legal Admin) should have all groups with FULL permissions
    const hasAllGroupsWithFull =
      groupIds.every((id) => {
        const perms = currentGroups[id.toString()];
        return perms && perms.includes("full");
      }) && currentGroupCount === groupIds.length;

    if (hasAllGroupsWithFull) {
      console.log(
        `  ⏭️  ${user.login} (${roleNames.join(", ")}) - already has all groups with FULL`
      );
      skipped++;
      continue;
    }

    try {
      await updateUser(user.id, {
        group_ids: fullGroupIdsObject,
      });
      console.log(
        `  ✓ ${user.login} (${roleNames.join(", ")}) - assigned to all groups with FULL`
      );
      updated++;
    } catch (error) {
      console.error(
        `  ✗ ${user.login} (${roleNames.join(", ")}) - failed: ${error}`
      );
    }
  }

  console.log(`\nDone!`);
  console.log(`  Updated: ${updated}`);
  console.log(`  Skipped: ${skipped}`);
}

main().catch((error) => {
  console.error("Error:", error);
  process.exit(1);
});
