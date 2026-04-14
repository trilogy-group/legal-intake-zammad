# Ticket Sharing Feature — Implementation Document

## Overview

This feature allows Zammad customers to share tickets with other customers **across organizations**, granting them read and comment access with full notification support. It integrates organically into Zammad's existing authorization, notification, and UI patterns.

**Commits:** `f663f6ef01`, `b2d44cdf02`
**Files changed:** 25 (668 insertions, 6 deletions)

---

## Architecture

### Data Model

**New table:** `ticket_shared_accesses`

| Column | Type | Description |
|---|---|---|
| `ticket_id` | FK → tickets | The shared ticket |
| `user_id` | FK → users | The customer receiving access |
| `created_by_id` | FK → users | Who initiated the share |
| `updated_by_id` | FK → users | Last updater |

Unique index on `(ticket_id, user_id)`. Migration: `db/migrate/20260413120000_create_ticket_shared_accesses.rb`.

**New model:** `Ticket::SharedAccess` (`app/models/ticket/shared_access.rb`)
- Class methods: `share!`, `unshare!`, `shared_with?`
- `after_create` callbacks: sends `OnlineNotification` to the shared user and touches the parent ticket for cache invalidation.

**Ticket model** (`app/models/ticket.rb`):
```ruby
has_many :shared_accesses,     class_name: 'Ticket::SharedAccess', dependent: :destroy
has_many :shared_access_users, through: :shared_accesses, source: :user
```

### Authorization

Three layers were updated to recognize shared access:

1. **Record-level policy** (`app/policies/ticket_policy.rb`):
   - `customer_access?` now returns `customer_field_scope` when `shared_access?` is true, granting the same read/update permissions as the ticket owner.

2. **Scope (list queries)** (`app/policies/ticket_policy/base_scope.rb`):
   - Added `tickets.id IN (SELECT ticket_id FROM ticket_shared_accesses WHERE user_id = ?)` to the customer SQL scope so shared tickets appear in lists.

3. **Field-level UI access** (`app/models/object_manager/element/ticket.rb`):
   - `customer_record_access?` returns `true` for shared users.

### API Endpoints

**REST** (`app/controllers/ticket_shared_accesses_controller.rb`, route: `config/routes/ticket_shared_access.rb`):
- `GET /api/v1/ticket_shared_accesses?ticket_id=:id` — list shared users
- `POST /api/v1/ticket_shared_accesses` — share (`ticket_id`, `user_id`)
- `DELETE /api/v1/ticket_shared_accesses/:id` — unshare

**GraphQL** (`app/graphql/gql/mutations/ticket/shared_access/`):
- `ticketShareWithCustomer(ticketId, userId)`
- `ticketSharedAccessUnshare(ticketId, userId)`

**Controller policy** (`app/policies/controllers/ticket_shared_accesses_controller_policy.rb`):
- Agents, the ticket customer, and existing shared users can share.
- Agents, the ticket customer, and the user being unshared can remove access.

### Notifications

**Initial notification** — handled by `Ticket::SharedAccess#notify_shared_user` callback, which creates an `OnlineNotification` at share time.

**Ongoing notifications** (`app/models/transaction/notification.rb`):
- New `add_shared_access_recipients` method adds all shared users to the notification recipients with both `online` and `email` channels enabled, so they receive updates on every ticket change.

**Notification list filtering** (`app/models/online_notification.rb`):
- `OnlineNotification.list` was updated to join `ticket_shared_accesses` and include notifications for tickets where the user is the customer or a shared access user (previously only checked group access).

### Customer UI (Legacy CoffeeScript)

1. **Notification bell** (`app/assets/javascripts/app/controllers/_plugin/navigation.coffee`):
   - Enabled for `ticket.customer` permission (was agent-only).

2. **Notification widget** (`app/assets/javascripts/app/controllers/widget/online_notification.coffee`):
   - Added initial `fetch()` on widget creation so existing notifications load immediately.

3. **Share button** (`app/assets/javascripts/app/controllers/ticket_zoom/sidebar_ticket.coffee`):
   - Added "Share" action to the ticket sidebar for both agent and customer views.

4. **Share modal** (`app/assets/javascripts/app/controllers/ticket_shared_access.coffee`):
   - New controller with user autocomplete, current shared users list, and remove functionality. Calls the REST API.

5. **Comment/reply form** (`app/assets/javascripts/app/models/ticket.coffee`):
   - `editableByCustomer()` now checks `shared_access_user_ids` so shared customers see the reply form.

### Customer Overview

**"Shared with me" overview** (`db/seeds/overviews.rb`):
- New overview for the Customer role using condition `ticket.shared_access_user_ids = current_user.id`.

**SQL selector support** (`lib/selector/sql.rb`):
- Added handling for `shared_access_user_ids` attribute, generating `LEFT JOIN ticket_shared_accesses` queries (mirrors the existing `mention_user_ids` pattern).

**Overview scope** (`app/models/ticket/overviews.rb`):
- Updated to use `read` scope (instead of `overview`) when the overview condition includes `ticket.shared_access_user_ids`.

### Tests

| File | Coverage |
|---|---|
| `spec/models/ticket/shared_access_spec.rb` | Model: share/unshare/uniqueness |
| `spec/policies/ticket_policy/shared_access_spec.rb` | Policy: show/update for shared users |
| `spec/policies/ticket_policy/shared_access_scope_spec.rb` | Scope: shared tickets in list queries |
| `spec/models/transaction/notification_shared_access_spec.rb` | Notifications: shared user receives updates |

---

## Production Notes

- Run `rails db:migrate` to create the `ticket_shared_accesses` table.
- The "Shared with me" overview is created via seeds. For existing production instances, either re-seed or create it manually via Admin → Overviews.
- No configuration flags needed — the feature is active once deployed.
- Rollback: drop the `ticket_shared_accesses` table and revert the code; no existing data is modified.
