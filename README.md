# Caller's Rights vs Owner's Rights: Cortex Agent Security Demo

## Quick Start

### 1. Setup and Run Tests (SQL)

```bash
# Run setup and all tests
snow sql -f testing.sql

# Cleanup when done
snow sql -f cleanup.sql
```

### 2. Test via Snowsight UI

After running `testing.sql`, test the agent in Snowsight:

1. Open a SQL worksheet and set your role:
   ```sql
   USE ROLE TEST_ROLE;
   USE SECONDARY ROLES NONE;
   ```

2. Navigate to **AI & ML → Cortex AI → Agents → RIGHTS_TEST_AGENT**

3. Try these prompts:
   - `Update ID 1 in DEV_DB to value 111.11 using caller rights` → SUCCESS
   - `Update ID 1 in PROD_DB to value 222.22 using caller rights` → FAIL
   - `Update ID 1 in DEV_DB to value 333.33 using owner rights` → SUCCESS
   - `Update ID 1 in PROD_DB to value 444.44 using owner rights` → FAIL ✓ (No privilege escalation!)

### Requirements

- Snowflake account with Cortex Agent access
- `snow` CLI installed
- User with ability to create roles, databases, and agents

---

## Purpose

This demonstration explores a critical security question when using stored procedures as tools in Snowflake Cortex Agents:

> **Can an agent, through owner's rights stored procedures, access or modify data that neither the calling user nor the procedure owner should be able to access?**

### Key Concepts

| Concept | Description |
|---------|-------------|
| **Caller's Rights** (`EXECUTE AS CALLER`) | Procedure runs with the privileges of the user who calls it |
| **Owner's Rights** (`EXECUTE AS OWNER`) | Procedure runs with the privileges of the role that created/owns it |
| **Secondary Roles** | Additional roles that can grant inherited privileges; must be disabled for accurate testing |

### Solution Demonstrated

By creating procedures with a **least-privileged role** (TEST_ROLE) as the owner, privilege escalation is prevented. This demo proves that owner's rights procedures cannot exceed the owner role's actual permissions.

---

## Role Permissions

### TEST_ROLE (Procedure Owner)

| Resource | Privileges |
|----------|------------|
| DEV_DB | USAGE |
| DEV_DB.PUBLIC | USAGE |
| DEV_DB.PUBLIC.TEST_TABLE | SELECT, INSERT, UPDATE, DELETE |
| PROD_DB | USAGE |
| PROD_DB.PUBLIC | USAGE |
| PROD_DB.PUBLIC.TEST_TABLE | **SELECT only** |
| COMPUTE_WH | USAGE |
| RIGHTS_TEST_AGENT | USAGE |

**Summary:** Full CRUD on DEV_DB, **read-only** on PROD_DB

### TEST_ROLE_DEV_ONLY

| Resource | Privileges |
|----------|------------|
| DEV_DB | USAGE |
| DEV_DB.PUBLIC | USAGE |
| DEV_DB.PUBLIC.TEST_TABLE | SELECT, INSERT, UPDATE, DELETE |
| PROD_DB | **NO ACCESS** |
| PROD_DB.PUBLIC | **NO ACCESS** |
| PROD_DB.PUBLIC.TEST_TABLE | **NO ACCESS** |
| COMPUTE_WH | USAGE |
| RIGHTS_TEST_AGENT | USAGE |

**Summary:** Full CRUD on DEV_DB, **zero access** to PROD_DB

### Comparison

| Resource | TEST_ROLE | TEST_ROLE_DEV_ONLY |
|----------|-----------|-------------------|
| DEV_DB.PUBLIC.TEST_TABLE | Full CRUD ✓ | Full CRUD ✓ |
| PROD_DB.PUBLIC.TEST_TABLE | SELECT only | ❌ No access |

---

## Stored Procedures (Owned by TEST_ROLE)

### UPDATE_TABLE_CALLER_RIGHTS

| Property | Value |
|----------|-------|
| **Full Name** | `DEV_DB.PUBLIC.UPDATE_TABLE_CALLER_RIGHTS(VARCHAR, NUMBER, FLOAT)` |
| **Owner** | **TEST_ROLE** |
| **Execution Mode** | `EXECUTE AS CALLER` |
| **Language** | Python |

**What it does:** Updates a record in `TEST_TABLE` within the specified database. The operation runs with the **caller's privileges**.

**Security Behavior:** If the caller lacks UPDATE privilege on the target table, the operation **fails**.

### UPDATE_TABLE_OWNER_RIGHTS

| Property | Value |
|----------|-------|
| **Full Name** | `DEV_DB.PUBLIC.UPDATE_TABLE_OWNER_RIGHTS(VARCHAR, NUMBER, FLOAT)` |
| **Owner** | **TEST_ROLE** |
| **Execution Mode** | `EXECUTE AS OWNER` |
| **Language** | Python |

**What it does:** Updates a record in `TEST_TABLE` within the specified database. The operation runs with the **owner's privileges** (TEST_ROLE).

**Security Behavior:** Since TEST_ROLE only has SELECT on PROD_DB, this procedure **cannot update PROD_DB** even with owner's rights—**privilege escalation is prevented**.

### Parameters (Both Procedures)

| Parameter | Type | Description |
|-----------|------|-------------|
| TARGET_DB | VARCHAR | Target database (`DEV_DB` or `PROD_DB`) |
| ID_TO_UPDATE | NUMBER | Record ID to update (1, 2, or 3) |
| NEW_VALUE | FLOAT | New value to set |

### Why TEST_ROLE Ownership?

The procedures were created **while using TEST_ROLE**, making TEST_ROLE the owner:

```sql
USE ROLE TEST_ROLE;
USE SECONDARY ROLES NONE;
CREATE OR REPLACE PROCEDURE DEV_DB.PUBLIC.UPDATE_TABLE_CALLER_RIGHTS(...)
CREATE OR REPLACE PROCEDURE DEV_DB.PUBLIC.UPDATE_TABLE_OWNER_RIGHTS(...)
```

This ensures owner's rights cannot exceed TEST_ROLE's permissions.

---

## Tests Performed

### Test Matrix

Eight tests were performed across two roles and two procedure types:

| Test # | Role | Procedure | Target DB | Purpose |
|--------|------|-----------|-----------|---------|
| 1 | TEST_ROLE | Caller Rights | DEV_DB | Verify caller can update where they have privileges |
| 2 | TEST_ROLE | Caller Rights | PROD_DB | Verify caller cannot update where they lack UPDATE |
| 3 | TEST_ROLE | Owner Rights | DEV_DB | Verify owner rights works on accessible data |
| 4 | TEST_ROLE | Owner Rights | PROD_DB | **Verify NO privilege escalation** |
| 5 | TEST_ROLE_DEV_ONLY | Caller Rights | DEV_DB | Verify caller can update where they have privileges |
| 6 | TEST_ROLE_DEV_ONLY | Caller Rights | PROD_DB | Verify caller cannot update with no access |
| 7 | TEST_ROLE_DEV_ONLY | Owner Rights | DEV_DB | Verify owner rights works on accessible data |
| 8 | TEST_ROLE_DEV_ONLY | Owner Rights | PROD_DB | **Verify NO privilege escalation** |

### Test Setup

```sql
-- Before each test batch
USE ROLE <role_name>;
USE SECONDARY ROLES NONE;  -- Critical for accurate testing
USE WAREHOUSE COMPUTE_WH;
```

---

## Expected Outputs

### With TEST_ROLE-Owned Procedures

| Test # | Role | Procedure | Target | Expected | Reason |
|--------|------|-----------|--------|----------|--------|
| 1 | TEST_ROLE | Caller Rights | DEV_DB | SUCCESS | Caller has UPDATE on DEV_DB |
| 2 | TEST_ROLE | Caller Rights | PROD_DB | FAIL | Caller only has SELECT on PROD_DB |
| 3 | TEST_ROLE | Owner Rights | DEV_DB | SUCCESS | Owner (TEST_ROLE) has UPDATE on DEV_DB |
| 4 | TEST_ROLE | Owner Rights | PROD_DB | **FAIL** ✓ | Owner (TEST_ROLE) only has SELECT on PROD_DB |
| 5 | TEST_ROLE_DEV_ONLY | Caller Rights | DEV_DB | SUCCESS | Caller has UPDATE on DEV_DB |
| 6 | TEST_ROLE_DEV_ONLY | Caller Rights | PROD_DB | FAIL | Caller has NO access to PROD_DB |
| 7 | TEST_ROLE_DEV_ONLY | Owner Rights | DEV_DB | SUCCESS | Owner (TEST_ROLE) has UPDATE on DEV_DB |
| 8 | TEST_ROLE_DEV_ONLY | Owner Rights | PROD_DB | **FAIL** ✓ | Owner (TEST_ROLE) only has SELECT on PROD_DB |

**✓ Security Success:** Tests 4 and 8 correctly FAIL because the procedure owner (TEST_ROLE) lacks UPDATE privileges on PROD_DB. **No privilege escalation occurs.**

---

## Actual Outputs

### Direct SQL Execution Results

Tests executed via `snow sql -f testing.sql`

| Test # | Role | Procedure | Target | Expected | Actual | Match |
|--------|------|-----------|--------|----------|--------|-------|
| 1 | TEST_ROLE | Caller Rights | DEV_DB | SUCCESS | `SUCCESS: Updated ID 1 in DEV_DB.PUBLIC.TEST_TABLE to value 111.11 (Caller Rights - owner: TEST_ROLE)` | ✓ |
| 2 | TEST_ROLE | Caller Rights | PROD_DB | FAIL | `ERROR: SQL access control error: Insufficient privileges to operate on table 'TEST_TABLE'. (Caller Rights - owner: TEST_ROLE)` | ✓ |
| 3 | TEST_ROLE | Owner Rights | DEV_DB | SUCCESS | `SUCCESS: Updated ID 1 in DEV_DB.PUBLIC.TEST_TABLE to value 333.33 (Owner Rights - owner: TEST_ROLE)` | ✓ |
| 4 | TEST_ROLE | Owner Rights | PROD_DB | FAIL | `ERROR: SQL access control error: Insufficient privileges to operate on table 'TEST_TABLE'. (Owner Rights - owner: TEST_ROLE)` | ✓ |
| 5 | TEST_ROLE_DEV_ONLY | Caller Rights | DEV_DB | SUCCESS | `SUCCESS: Updated ID 2 in DEV_DB.PUBLIC.TEST_TABLE to value 555.55 (Caller Rights - owner: TEST_ROLE)` | ✓ |
| 6 | TEST_ROLE_DEV_ONLY | Caller Rights | PROD_DB | FAIL | `ERROR: Database 'PROD_DB' does not exist or not authorized. (Caller Rights - owner: TEST_ROLE)` | ✓ |
| 7 | TEST_ROLE_DEV_ONLY | Owner Rights | DEV_DB | SUCCESS | `SUCCESS: Updated ID 2 in DEV_DB.PUBLIC.TEST_TABLE to value 777.77 (Owner Rights - owner: TEST_ROLE)` | ✓ |
| 8 | TEST_ROLE_DEV_ONLY | Owner Rights | PROD_DB | FAIL | `ERROR: SQL access control error: Insufficient privileges to operate on table 'TEST_TABLE'. (Owner Rights - owner: TEST_ROLE)` | ✓ |

### Agent Execution Results

The Cortex Agent (`DEV_DB.PUBLIC.RIGHTS_TEST_AGENT`) was tested through the Snowsight UI with the following results:

#### TEST_ROLE Tests (has SELECT on PROD_DB)

| Test | Prompt | Expected | Actual | Match |
|------|--------|----------|--------|-------|
| 1 | `Update ID 1 in DEV_DB to value 111.11 using caller rights` | SUCCESS | SUCCESS - ID 1 updated to 111.11 using caller rights | ✓ |
| 2 | `Update ID 1 in PROD_DB to value 222.22 using caller rights` | FAIL | FAIL - SQL access control error: Insufficient privileges to operate on table 'TEST_TABLE' | ✓ |
| 3 | `Update ID 1 in DEV_DB to value 333.33 using owner rights` | SUCCESS | SUCCESS - ID 1 updated to 333.33 using owner rights | ✓ |
| 4 | `Update ID 1 in PROD_DB to value 444.44 using owner rights` | FAIL | FAIL - SQL access control error: Insufficient privileges to operate on table 'TEST_TABLE' | ✓ |

#### TEST_ROLE_DEV_ONLY Tests (NO access to PROD_DB)

| Test | Prompt | Expected | Actual | Match |
|------|--------|----------|--------|-------|
| 5 | `Update ID 2 in DEV_DB to value 555.55 using caller rights` | SUCCESS | SUCCESS - ID 2 updated to 555.55 using caller rights | ✓ |
| 6 | `Update ID 2 in PROD_DB to value 666.66 using caller rights` | FAIL | FAIL - Database 'PROD_DB' does not exist or not authorized | ✓ |
| 7 | `Update ID 2 in DEV_DB to value 777.77 using owner rights` | SUCCESS | SUCCESS - ID 2 updated to 777.77 using owner rights | ✓ |
| 8 | `Update ID 2 in PROD_DB to value 888.88 using owner rights` | FAIL | FAIL - SQL access control error: Insufficient privileges to operate on table 'TEST_TABLE' | ✓ |

**Agent Test Result: 8/8 tests passed (100% match)**

**Key Observations:**
- Tests 4 and 8 confirm **no privilege escalation** occurs—even with owner's rights, the agent cannot update PROD_DB because TEST_ROLE (the procedure owner) only has SELECT on PROD_DB
- Test 6 shows TEST_ROLE_DEV_ONLY cannot even see PROD_DB exists, while Test 8 shows the owner's rights procedure can see it but still cannot update

---

## Results Comparison

### Summary Table

| Test | Expected | SQL Actual | Agent Actual | Match | Security Implication |
|------|----------|------------|--------------|-------|---------------------|
| 1 | SUCCESS | SUCCESS | SUCCESS | ✓ | Caller has UPDATE on DEV_DB |
| 2 | FAIL | FAIL | FAIL | ✓ | Caller lacks UPDATE on PROD_DB |
| 3 | SUCCESS | SUCCESS | SUCCESS | ✓ | Owner (TEST_ROLE) has UPDATE on DEV_DB |
| 4 | FAIL | FAIL | FAIL | ✓ | **No privilege escalation** - owner lacks UPDATE on PROD_DB |
| 5 | SUCCESS | SUCCESS | SUCCESS | ✓ | Caller has UPDATE on DEV_DB |
| 6 | FAIL | FAIL | FAIL | ✓ | Caller has NO access to PROD_DB |
| 7 | SUCCESS | SUCCESS | SUCCESS | ✓ | Owner (TEST_ROLE) has UPDATE on DEV_DB |
| 8 | FAIL | FAIL | FAIL | ✓ | **No privilege escalation** - owner lacks UPDATE on PROD_DB |

**Overall Result:** 
- SQL Tests: 8/8 passed (100%)
- Agent Tests: 8/8 passed (100%)
- **Total: 16/16 tests passed**

---

## Key Findings

### 1. Procedure Ownership Determines Security Boundary

When TEST_ROLE owns the procedures, owner's rights are limited to TEST_ROLE's permissions. This prevents privilege escalation.

### 2. Privilege Escalation Successfully Prevented

**Tests 4 and 8 are the critical security demonstrations:**

- **Test 4:** TEST_ROLE (has SELECT on PROD_DB) calls owner's rights → **FAILS** because owner (TEST_ROLE) only has SELECT
- **Test 8:** TEST_ROLE_DEV_ONLY (has NO access to PROD_DB) calls owner's rights → **FAILS** because owner (TEST_ROLE) only has SELECT

**Conclusion:** Even with `EXECUTE AS OWNER`, the procedure cannot exceed the owner role's actual permissions.

### 3. Different Error Messages Reveal Access Levels

| Role | Error on PROD_DB |
|------|------------------|
| TEST_ROLE | `Insufficient privileges to operate on table` (can see table, can't update) |
| TEST_ROLE_DEV_ONLY | `Database 'PROD_DB' does not exist or not authorized` (can't even see it) |

### 4. Secondary Roles Must Be Disabled

Always disable secondary roles when testing:
```sql
USE SECONDARY ROLES NONE;
```
Otherwise, inherited privileges from other roles can mask permission issues.

---

## Security Recommendations

1. **Create procedures with a least-privileged role** as owner
2. **Create a dedicated service role** with only the permissions needed for agent operations
3. **Prefer Caller's Rights** (`EXECUTE AS CALLER`) unless controlled privilege elevation is specifically required
4. **Audit all Owner's Rights procedures** to ensure the owner role has appropriate (minimal) permissions
5. **Test with secondary roles disabled** to accurately simulate restricted users
6. **Document procedure ownership** and review during security audits

---

## Files

| File | Description |
|------|-------------|
| `DEMO_SUMMARY.md` | This file - complete documentation |
| `testing.sql` | Complete setup + all 8 tests |
| `cleanup.sql` | Removes all demo objects |

---

## Verification Commands

```sql
-- Check table contents
SELECT * FROM DEV_DB.PUBLIC.TEST_TABLE ORDER BY ID;
SELECT * FROM PROD_DB.PUBLIC.TEST_TABLE ORDER BY ID;

-- Check procedure ownership (should show TEST_ROLE)
SELECT PROCEDURE_NAME, PROCEDURE_OWNER 
FROM DEV_DB.INFORMATION_SCHEMA.PROCEDURES;

-- Check role permissions
SHOW GRANTS TO ROLE TEST_ROLE;
SHOW GRANTS TO ROLE TEST_ROLE_DEV_ONLY;

-- Describe agent
DESCRIBE AGENT DEV_DB.PUBLIC.RIGHTS_TEST_AGENT;
```

---

## Conclusion

This demonstration proves that **proper procedure ownership prevents privilege escalation** in Cortex Agent tools. By ensuring stored procedures are owned by a least-privileged role (TEST_ROLE), owner's rights procedures cannot access or modify data beyond what that role can access—even when called by users with different permission levels.
