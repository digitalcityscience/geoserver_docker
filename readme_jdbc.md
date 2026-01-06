# JDBC-backed GeoServer Setup

(Security + Configuration, now living in PostgreSQL)

What this setup actually does (important context)

This GeoServer setup uses PostgreSQL as the source of truth for two different things:

1️⃣ Security (users & roles)
• Users
• Groups
• Roles
• User ↔ Role relations

➡️ Stored in a dedicated security schema
Example (our system):

gs_auth_role_schema

2️⃣ GeoServer configuration (workspaces, layers, stores, styles)
• Workspaces
• Datastores / Coveragestores
• Layers
• Layer groups
• Styles
• Services
• Global & workspace settings

➡️ Stored via JDBCConfig

> JDBCStore is not implemented yet

➡️ In a separate schema, intentionally
Example (our system):

gs_jdbcconfig_schema

⚠️ Security schema and JDBCConfig schema must NOT be the same.

They serve different purposes, have different lifecycles, and mixing them will eventually hurt you.

Our system is set up correctly:
• ✅ Security → gs_auth_role_schema
• ✅ GeoServer config → gs_jdbcconfig_schema

⸻

#### Why this matters

Because after this setup:
• GeoServer users & roles are no longer file-based
• GeoServer workspaces, layers, stores are no longer file-based
• Restarting containers does not reset configuration
• PostgreSQL becomes the single persistent backend

This is what makes the setup production-grade (AWS / on-prem / Docker).

⸻

## JDBC Security Setup – The “Test Connection” Reality Guide

(aka: things GeoServer does that are not your fault)

This document explains the mandatory manual steps required to activate JDBC-based security in GeoServer.

Yes, everything is configured correctly.
Yes, you still need to click things in the UI.
No, this is not optional.

⸻

#### Context (What we did before you arrived here)

• We disabled GeoServer’s default file-based login service
• We enabled:
• JDBC User/Group Service
• JDBC Role Service
• Users and roles now live in PostgreSQL
• JDBCConfig / JDBCStore is enabled for GeoServer configuration
• Database schemas are separated and persistent
• Containers are running

Except: GeoServer still needs to be convinced via the UI.

⸻

#### Step 1 – JDBC Login Service

1. Go to:
   Security → User Group Services → jdbc_login
1. Open the Settings tab.
1. ⚠️ You may notice that Driver Class Name is empty.
   This is normal.
   Why? Don’t ask GeoServer.
1. Click on the “Users” tab.
1. Click back to “Settings”.
1. 🎉 Suddenly, the Driver Class Name appears.
1. Click Test Connection
   • You must see a green success message
1. Click Save
   • Yes, this matters
   • No, Test Connection alone is not enough

⸻

#### Step 2 – JDBC Role Service (same ritual, slightly different vibes)

1. Go to:
   Security → Role Services → jdbc_role
2. Driver Class Name is usually visible immediately
   (why it behaves differently than Step 1 is unknown)
3. Click Test Connection
4. If you see a red error:
   • Click any other menu
   • Return to Role Services
   • Try again
5. Once you see a green success message, click Save

⸻

#### Step 3 – Invisible admin roles (very important)

Even though these roles are defined in XML and DB:
• ADMIN
• GROUP_ADMIN

They may not appear selected in the UI.

GeoServer UI does not automatically map XML-defined roles.

What you must do: 1. Stay in Role Services → jdbc_role 2. Manually set:
• Administrator role → ADMIN
• Group administrator role → GROUP_ADMIN 3. Click Save 4. Leave the page 5. Come back and verify they are still selected

⸻

#### Step 4 – Restart prompt (this is expected)

After saving Role Services:
• You will see a restart prompt in the terminal
• This is intentional

Do this:
• Press y
• Let the GeoServer container restart

This restart is required so:
• The new security chain becomes active
• JDBC-backed users can actually log in

⸻

#### Final result

After restart:
• File-based login is disabled
• JDBC-based security is active
• JDBCConfig / JDBCStore is active
• Users, roles, workspaces, layers, styles are stored in PostgreSQL
• GeoServer behaves consistently across restarts

⸻

#### Appendix – What data lives in which tables?

Security schema (gs_auth_role_schema)

You can access:
• users → usernames, encrypted passwords, enabled flag
• roles → role definitions
• user_roles → user ↔ role mapping
• groups, group_roles, group_members → group-based auth
• user_props, role_props → extensible metadata

👉 Use cases:
• Auditing users
• External user provisioning
• Role inspection
• Integration with Django / IAM systems

⸻

JDBCConfig schema (gs_jdbcconfig_schema)

You can access:
• workspace
• datastore, coveragestore
• featuretype, coverage
• layer, layergroup
• style, layer_style
• service, settings, global

👉 Use cases:
• Backup GeoServer config via SQL
• Inspect layer metadata programmatically
• CI/CD-style GeoServer deployments
• Disaster recovery without data-dir restores

⚠️ Editing these tables manually is possible but not recommended unless you fully understand GeoServer’s internal model.

⸻

One-line summary

We moved security and configuration out of files
and into PostgreSQL —
the UI steps are the toll you pay for that power.
