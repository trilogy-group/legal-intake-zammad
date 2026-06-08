# Create Zammad Role Script

A utility to create new Zammad roles programmatically.

## Usage

### Interactive Mode

Run the script and follow the prompts:

```bash
npm run zammad:create-role
```

You'll be asked for:

- **Role name** (required)
- **Description** (optional)
- **Template** to base the role on (agent, admin, customer, legal_admin)
- **Access level** (full, read, change)
- **Group IDs** (comma-separated, default: 2,6,7)

### CLI Mode

Pass all parameters as command-line arguments:

```bash
npm run zammad:create-role -- \
  --name "Legal Viewer" \
  --note "Read-only access for legal team" \
  --template agent \
  --access read \
  --groups "2,6,7" \
  --apply
```

## Parameters

| Parameter    | Description               | Default               | Required |
| ------------ | ------------------------- | --------------------- | -------- |
| `--name`     | Role name                 | -                     | ✅ Yes   |
| `--note`     | Role description          | "Custom role: {name}" | No       |
| `--template` | Base role template        | `agent`               | No       |
| `--access`   | Group access level        | `full`                | No       |
| `--groups`   | Comma-separated group IDs | `2,6,7`               | No       |
| `--apply`    | Auto-apply to Zammad      | `false`               | No       |

## Templates

Templates determine which Zammad permissions the role will have:

- **`agent`** - Can work on tickets, view overviews, manage ticket lifecycle
- **`admin`** - Full system admin access
- **`customer`** - Customer-level access (view own tickets)
- **`legal_admin`** - Same as agent (custom role for legal team)

## Access Levels

Access levels determine what agents can do within assigned groups:

- **`full`** - All permissions (read, write, assign, create)
- **`read`** - View tickets only
- **`change`** - View and edit tickets (no creation)

## Group IDs

Current Legal Intake groups:

- **2** - Existing Vendor Intake
- **6** - Software Development Vendor Intake
- **7** - Property Leases

## Examples

### Example 1: Legal Viewer (Read-Only)

Create a read-only role for viewing tickets:

```bash
npm run zammad:create-role -- \
  --name "Legal Viewer" \
  --note "Read-only access to all legal intake tickets" \
  --template agent \
  --access read \
  --apply
```

### Example 2: External Counsel (Limited Access)

Create a role for external counsel with access to specific groups only:

```bash
npm run zammad:create-role -- \
  --name "External Counsel" \
  --note "External legal counsel with limited access" \
  --template agent \
  --access full \
  --groups "6" \
  --apply
```

### Example 3: Legal Manager (Full Access)

Create a manager role with full access:

```bash
npm run zammad:create-role -- \
  --name "Legal Manager" \
  --note "Legal team manager with full access" \
  --template legal_admin \
  --access full \
  --groups "2,6,7" \
  --apply
```

## Manual Application

If you don't use the `--apply` flag, the role will be added to `zammad/config/zammad-roles.json` but not created in Zammad.

To apply it manually later:

```bash
npm run zammad:configure-roles
```

## Notes

- Role names must be unique
- The script adds the role to your local config file first
- Use `--apply` to automatically push the role to Zammad
- You can always edit the role in `zammad/config/zammad-roles.json` after creation
