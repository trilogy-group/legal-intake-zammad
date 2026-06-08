# Zammad Migration Script Organization

This document explains the order in which Zammad configuration scripts should be run during a migration.

## Migration Phases

### Phase 1: Pre-Migration (Infrastructure Setup)

**Run BEFORE migrating users, organizations, or tickets**

These scripts set up the foundational infrastructure that must exist before any data is migrated.

| Order | Script                                 | Purpose                                                       | Why Pre-Migration                                 |
| ----- | -------------------------------------- | ------------------------------------------------------------- | ------------------------------------------------- |
| 1     | `configure-zammad-settings.ts`         | Basic system configuration (branding, timezone, auth)         | System must be configured before anything else    |
| 2     | `configure-zammad-roles.ts`            | Create user roles (Admin, Agent, Legal Admin, Customer)       | Roles must exist before creating users            |
| 3     | `configure-zammad-groups.ts`           | Create ticket groups (Existing Vendor, Property Leases, etc.) | Groups must exist before tickets                  |
| 4     | `configure-zammad-ticket-states.ts`    | Define ticket states (open, closed, under review, etc.)       | States must exist before tickets                  |
| 5     | `configure-zammad-core-workflows.ts`   | Set up workflows (hide fields, make read-only, etc.)          | Workflows should be active when tickets arrive    |
| 6     | `configure-zammad-field-visibility.ts` | Configure custom field visibility                             | Fields must be configured before tickets use them |
| 7     | `configure-zammad-overviews.ts`        | Set up ticket list views for agents/customers                 | Views should be ready when users log in           |
| 8     | `configure-zammad-text-modules.ts`     | Pre-configured response templates                             | Templates ready for agents to use                 |

### Phase 2: Data Migration

**Migrate actual data**

The Legal Intake app automatically syncs users, organizations, and tickets to Zammad via API. No manual import scripts needed.

| Order | Task                               | How                                                                     |
| ----- | ---------------------------------- | ----------------------------------------------------------------------- |
| 1     | **Run Legal Intake App Migration** | The app syncs users, organizations, and tickets to Zammad automatically |

**Note**: `configure-zammad-organizations.ts` and `configure-zammad-users.ts` are NOT used during migration. They exist for troubleshooting/manual operations only.

### Phase 3: Post-Migration (Automation & Security)

**Run AFTER all data is migrated**

These scripts configure automation and security that should only be enabled after the system is fully populated and tested.

| Order | Script                           | Purpose                                       | Why Post-Migration                                          |
| ----- | -------------------------------- | --------------------------------------------- | ----------------------------------------------------------- |
| 1     | `configure-zammad-triggers.ts`   | Email notifications on ticket events          | Avoid sending emails during test migrations                 |
| 2     | `configure-zammad-schedulers.ts` | Time-based automation (reminders, auto-close) | Avoid acting on migrated tickets during testing             |
| 3     | `configure-outbound-email.ts`    | Set up SMTP/email delivery                    | Only enable after system is tested and ready for production |
| 4     | `disable-password-login.ts`      | Force Google OAuth only                       | Only after OAuth is tested and working                      |
| 5     | `update-article-translations.ts` | Update translations for articles              | Final polish after all content is migrated                  |

---

## Quick Start Commands

### Pre-Migration (Run All)

```bash
cd /Users/dhairya-07/Desktop/Trilogy/legal-intake

# Phase 1: Infrastructure
npm run zammad:configure-settings
npm run zammad:configure-roles
npm run zammad:configure-groups
npm run zammad:configure-ticket-states
npm run zammad:configure-core-workflows
npm run zammad:configure-field-visibility
npm run zammad:configure-overviews
npm run zammad:configure-text-modules
```

**Settings for Pre-Migration** (in `zammad-settings.json`):

```json
{
  "auth_google_oauth2": true,
  "user_show_password_login": true,
  "user_create_account": true,
  "auth_third_party_no_create_user": true
}
```

### Data Migration

```bash
# Phase 2: Data
# Run Legal Intake app migration - it automatically syncs:
# - Organizations
# - Users
# - Tickets
# No manual Zammad scripts needed!
```

### Post-Migration (Run All)

````bash
# Phase 3: Automation
npm run zammad:configure-triggers
npm run zammad:configure-schedulers
npm run zammad:update-translations

```bash
npm run zammad:configure-outbound-email -- \
  --host email-smtp.us-east-1.amazonaws.com \
  --port 587 \
  --user "YOUR_AWS_ACCESS_KEY_ID" \
  --password "YOUR_AWS_SES_SMTP_PASSWORD" \
  --from "Legal Intake's email"
````

**Settings for Post-Migration** (in `zammad-settings.json`):

```json
{
  "user_create_account": false,
  "user_show_password_login": false
}
```

**Note**: Get SMTP password from AWS Console → Amazon SES → SMTP Settings → Create SMTP Credentials (NOT your AWS secret key).

---

## Configuration Files

All configuration is stored in `zammad/config/` directory:

| File                           | Purpose                              | Migration Phase |
| ------------------------------ | ------------------------------------ | --------------- |
| `zammad-settings.json`         | System-wide settings                 | Pre             |
| `zammad-roles.json`            | User roles                           | Pre             |
| `zammad-groups.json`           | Ticket groups                        | Pre             |
| `zammad-ticket-states.json`    | Ticket states                        | Pre             |
| `zammad-core-workflows.json`   | Conditional workflows                | Pre             |
| `zammad-field-visibility.json` | Custom field setup                   | Pre             |
| `zammad-overviews.json`        | Ticket list views                    | Pre             |
| `zammad-text-modules.json`     | Response templates                   | Pre             |
| `zammad-organizations.json`    | Organizations (not used - app syncs) | N/A             |
| `zammad-users.json`            | Users (not used - app syncs)         | N/A             |
| `zammad-triggers.json`         | Event-based email notifications      | Post            |
| `zammad-schedulers.json`       | Time-based automation                | Post            |

---

## Rollback Strategy

If you need to roll back a migration:

1. Export current state:

```bash
 npm run zammad:export-all
```

2. Restore previous configuration:

```bash
 # Revert config files from git
 git checkout HEAD -- zammad/config/

 # Re-apply configuration
 npm run zammad:configure-all
```

---

## Testing Checklist

### Pre-Migration Tests

- Admin can log in
- Groups are visible
- Roles are configured
- Google OAuth works for test user

### Post-Migration Tests

- Email notifications work
- Schedulers run correctly
- OAuth-only login works

---

## Notes

- Always run `npm run zammad:export-all` after making UI changes to sync config files
- Config files are the source of truth - changes in UI should be exported to files
- Use version control to track configuration changes
