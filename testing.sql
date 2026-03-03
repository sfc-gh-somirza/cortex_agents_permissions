-- testing.sql
-- Caller's Rights vs Owner's Rights Demo - Complete Setup and Testing
-- This script sets up databases, roles, procedures, and agent, then runs all tests

-- =============================================================================
-- PART 1: SETUP (Run as ACCOUNTADMIN)
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- 1.1 Create Databases and Tables
-- -----------------------------------------------------------------------------

CREATE DATABASE IF NOT EXISTS DEV_DB;
CREATE SCHEMA IF NOT EXISTS DEV_DB.PUBLIC;
CREATE OR REPLACE TABLE DEV_DB.PUBLIC.TEST_TABLE (
    ID INT,
    NAME VARCHAR(100),
    VALUE NUMBER(10,2),
    UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_BY VARCHAR(100)
);

INSERT INTO DEV_DB.PUBLIC.TEST_TABLE (ID, NAME, VALUE)
VALUES (1, 'Item A', 100.00), (2, 'Item B', 200.00), (3, 'Item C', 300.00);

CREATE DATABASE IF NOT EXISTS PROD_DB;
CREATE SCHEMA IF NOT EXISTS PROD_DB.PUBLIC;
CREATE OR REPLACE TABLE PROD_DB.PUBLIC.TEST_TABLE (
    ID INT,
    NAME VARCHAR(100),
    VALUE NUMBER(10,2),
    UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_BY VARCHAR(100)
);

INSERT INTO PROD_DB.PUBLIC.TEST_TABLE (ID, NAME, VALUE)
VALUES (1, 'Prod Item A', 1000.00), (2, 'Prod Item B', 2000.00), (3, 'Prod Item C', 3000.00);

-- -----------------------------------------------------------------------------
-- 1.2 Create TEST_ROLE (Full DEV_DB, SELECT-only PROD_DB)
-- -----------------------------------------------------------------------------

CREATE ROLE IF NOT EXISTS TEST_ROLE;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE TEST_ROLE;

GRANT USAGE ON DATABASE DEV_DB TO ROLE TEST_ROLE;
GRANT USAGE ON SCHEMA DEV_DB.PUBLIC TO ROLE TEST_ROLE;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA DEV_DB.PUBLIC TO ROLE TEST_ROLE;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA DEV_DB.PUBLIC TO ROLE TEST_ROLE;
GRANT CREATE PROCEDURE ON SCHEMA DEV_DB.PUBLIC TO ROLE TEST_ROLE;

GRANT USAGE ON DATABASE PROD_DB TO ROLE TEST_ROLE;
GRANT USAGE ON SCHEMA PROD_DB.PUBLIC TO ROLE TEST_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA PROD_DB.PUBLIC TO ROLE TEST_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA PROD_DB.PUBLIC TO ROLE TEST_ROLE;

GRANT ROLE TEST_ROLE TO USER SOMIRZA;

-- -----------------------------------------------------------------------------
-- 1.3 Create TEST_ROLE_DEV_ONLY (Full DEV_DB, NO PROD_DB access)
-- -----------------------------------------------------------------------------

CREATE ROLE IF NOT EXISTS TEST_ROLE_DEV_ONLY;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE TEST_ROLE_DEV_ONLY;

GRANT USAGE ON DATABASE DEV_DB TO ROLE TEST_ROLE_DEV_ONLY;
GRANT USAGE ON SCHEMA DEV_DB.PUBLIC TO ROLE TEST_ROLE_DEV_ONLY;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA DEV_DB.PUBLIC TO ROLE TEST_ROLE_DEV_ONLY;

GRANT ROLE TEST_ROLE_DEV_ONLY TO USER SOMIRZA;

-- -----------------------------------------------------------------------------
-- 1.4 Create V2 Procedures (Owned by TEST_ROLE)
-- -----------------------------------------------------------------------------

USE ROLE TEST_ROLE;
USE SECONDARY ROLES NONE;

CREATE OR REPLACE PROCEDURE DEV_DB.PUBLIC.UPDATE_TABLE_CALLER_RIGHTS_V2(
    TARGET_DB STRING,
    ID_TO_UPDATE INT,
    NEW_VALUE FLOAT
)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
EXECUTE AS CALLER
AS
'
import snowflake.snowpark as snowpark

def main(session: snowpark.Session, target_db: str, id_to_update: int, new_value: float) -> str:
    try:
        sql = f"""UPDATE {target_db}.PUBLIC.TEST_TABLE 
                  SET VALUE = {new_value}, 
                      UPDATED_AT = CURRENT_TIMESTAMP(), 
                      UPDATED_BY = CURRENT_USER() 
                  WHERE ID = {id_to_update}"""
        session.sql(sql).collect()
        return f"SUCCESS: Updated ID {id_to_update} in {target_db}.PUBLIC.TEST_TABLE to value {new_value} (Caller Rights V2 - owner: TEST_ROLE)"
    except Exception as e:
        return f"ERROR: {str(e)} (Caller Rights V2 - owner: TEST_ROLE)"
';

CREATE OR REPLACE PROCEDURE DEV_DB.PUBLIC.UPDATE_TABLE_OWNER_RIGHTS_V2(
    TARGET_DB STRING,
    ID_TO_UPDATE INT,
    NEW_VALUE FLOAT
)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
EXECUTE AS OWNER
AS
'
import snowflake.snowpark as snowpark

def main(session: snowpark.Session, target_db: str, id_to_update: int, new_value: float) -> str:
    try:
        sql = f"""UPDATE {target_db}.PUBLIC.TEST_TABLE 
                  SET VALUE = {new_value}, 
                      UPDATED_AT = CURRENT_TIMESTAMP(), 
                      UPDATED_BY = ''OWNER_RIGHTS_V2_PROC'' 
                  WHERE ID = {id_to_update}"""
        session.sql(sql).collect()
        return f"SUCCESS: Updated ID {id_to_update} in {target_db}.PUBLIC.TEST_TABLE to value {new_value} (Owner Rights V2 - owner: TEST_ROLE)"
    except Exception as e:
        return f"ERROR: {str(e)} (Owner Rights V2 - owner: TEST_ROLE)"
';

GRANT USAGE ON PROCEDURE DEV_DB.PUBLIC.UPDATE_TABLE_CALLER_RIGHTS_V2(STRING, INT, FLOAT) TO ROLE TEST_ROLE_DEV_ONLY;
GRANT USAGE ON PROCEDURE DEV_DB.PUBLIC.UPDATE_TABLE_OWNER_RIGHTS_V2(STRING, INT, FLOAT) TO ROLE TEST_ROLE_DEV_ONLY;

-- -----------------------------------------------------------------------------
-- 1.5 Create Agent (Owned by ACCOUNTADMIN, uses V2 procedures)
-- -----------------------------------------------------------------------------

USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE AGENT DEV_DB.PUBLIC.RIGHTS_TEST_AGENT
  COMMENT = 'Agent to demonstrate caller rights vs owner rights stored procedures (V2 - procedures owned by TEST_ROLE)'
  FROM SPECIFICATION $$
{
  "models": {
    "orchestration": "claude-4-sonnet"
  },
  "instructions": {
    "orchestration": "You help test stored procedures. When the user asks you to update data, you MUST use the appropriate tool. You have access to update_caller_rights and update_owner_rights tools. Always call the tool when asked and report the exact result.",
    "response": "Report the operation result clearly - whether it succeeded or failed, and include any error message."
  },
  "tools": [
    {
      "tool_spec": {
        "type": "generic",
        "name": "update_caller_rights",
        "description": "Updates TEST_TABLE using CALLER rights. Runs with the privileges of the calling user.",
        "input_schema": {
          "type": "object",
          "properties": {
            "TARGET_DB": {
              "type": "string",
              "description": "Target database (DEV_DB or PROD_DB)"
            },
            "ID_TO_UPDATE": {
              "type": "integer",
              "description": "Record ID to update"
            },
            "NEW_VALUE": {
              "type": "number",
              "description": "New value"
            }
          },
          "required": ["TARGET_DB", "ID_TO_UPDATE", "NEW_VALUE"]
        }
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "update_owner_rights",
        "description": "Updates TEST_TABLE using OWNER rights. Runs with TEST_ROLE privileges (procedure owner).",
        "input_schema": {
          "type": "object",
          "properties": {
            "TARGET_DB": {
              "type": "string",
              "description": "Target database (DEV_DB or PROD_DB)"
            },
            "ID_TO_UPDATE": {
              "type": "integer",
              "description": "Record ID to update"
            },
            "NEW_VALUE": {
              "type": "number",
              "description": "New value"
            }
          },
          "required": ["TARGET_DB", "ID_TO_UPDATE", "NEW_VALUE"]
        }
      }
    }
  ],
  "tool_resources": {
    "update_caller_rights": {
      "type": "procedure",
      "identifier": "DEV_DB.PUBLIC.UPDATE_TABLE_CALLER_RIGHTS_V2",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "COMPUTE_WH",
        "query_timeout": 60
      }
    },
    "update_owner_rights": {
      "type": "procedure",
      "identifier": "DEV_DB.PUBLIC.UPDATE_TABLE_OWNER_RIGHTS_V2",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "COMPUTE_WH",
        "query_timeout": 60
      }
    }
  }
}
$$;

GRANT USAGE ON AGENT DEV_DB.PUBLIC.RIGHTS_TEST_AGENT TO ROLE TEST_ROLE;
GRANT USAGE ON AGENT DEV_DB.PUBLIC.RIGHTS_TEST_AGENT TO ROLE TEST_ROLE_DEV_ONLY;

SELECT 'SETUP COMPLETE' as STATUS;

-- =============================================================================
-- PART 2: VERIFY SETUP
-- =============================================================================

SELECT '=== PROCEDURE OWNERSHIP ===' as INFO;
SELECT PROCEDURE_NAME, PROCEDURE_OWNER 
FROM DEV_DB.INFORMATION_SCHEMA.PROCEDURES 
WHERE PROCEDURE_NAME LIKE '%V2';

SELECT '=== ROLE PERMISSIONS SUMMARY ===' as INFO;
SELECT 'TEST_ROLE' as ROLE, 'DEV_DB' as DATABASE, 'SELECT,INSERT,UPDATE,DELETE' as PRIVILEGES
UNION ALL
SELECT 'TEST_ROLE', 'PROD_DB', 'SELECT only'
UNION ALL  
SELECT 'TEST_ROLE_DEV_ONLY', 'DEV_DB', 'SELECT,INSERT,UPDATE,DELETE'
UNION ALL
SELECT 'TEST_ROLE_DEV_ONLY', 'PROD_DB', 'NO ACCESS';

-- =============================================================================
-- PART 3: DIRECT SQL TESTS
-- =============================================================================

USE ROLE ACCOUNTADMIN;

TRUNCATE TABLE DEV_DB.PUBLIC.TEST_TABLE;
INSERT INTO DEV_DB.PUBLIC.TEST_TABLE (ID, NAME, VALUE) VALUES (1, 'Item A', 100.00), (2, 'Item B', 200.00), (3, 'Item C', 300.00);
TRUNCATE TABLE PROD_DB.PUBLIC.TEST_TABLE;
INSERT INTO PROD_DB.PUBLIC.TEST_TABLE (ID, NAME, VALUE) VALUES (1, 'Prod Item A', 1000.00), (2, 'Prod Item B', 2000.00), (3, 'Prod Item C', 3000.00);

SELECT '========================================' as DIVIDER;
SELECT 'CALLER RIGHTS vs OWNER RIGHTS DEMO' as TITLE;
SELECT 'Procedures owned by TEST_ROLE' as INFO;
SELECT '========================================' as DIVIDER;

-- -----------------------------------------------------------------------------
-- 3.1 TEST_ROLE Tests (Full DEV_DB access, SELECT only PROD_DB)
-- -----------------------------------------------------------------------------

SELECT '========================================' as DIVIDER;
SELECT 'TESTING WITH TEST_ROLE' as TITLE;
SELECT 'DEV_DB: Full access | PROD_DB: SELECT only' as PERMISSIONS;
SELECT '========================================' as DIVIDER;

USE ROLE TEST_ROLE;
USE SECONDARY ROLES NONE;

SELECT 'TEST 1: Caller Rights + DEV_DB' as TEST;
SELECT 'Expected: SUCCESS (caller has UPDATE on DEV_DB)' as EXPECTED;
CALL DEV_DB.PUBLIC.UPDATE_TABLE_CALLER_RIGHTS_V2('DEV_DB', 1, 111.11);

SELECT 'TEST 2: Caller Rights + PROD_DB' as TEST;
SELECT 'Expected: FAIL (caller only has SELECT on PROD_DB)' as EXPECTED;
CALL DEV_DB.PUBLIC.UPDATE_TABLE_CALLER_RIGHTS_V2('PROD_DB', 1, 222.22);

SELECT 'TEST 3: Owner Rights + DEV_DB' as TEST;
SELECT 'Expected: SUCCESS (owner TEST_ROLE has UPDATE on DEV_DB)' as EXPECTED;
CALL DEV_DB.PUBLIC.UPDATE_TABLE_OWNER_RIGHTS_V2('DEV_DB', 1, 333.33);

SELECT 'TEST 4: Owner Rights + PROD_DB' as TEST;
SELECT 'Expected: FAIL (owner TEST_ROLE only has SELECT on PROD_DB)' as EXPECTED;
CALL DEV_DB.PUBLIC.UPDATE_TABLE_OWNER_RIGHTS_V2('PROD_DB', 1, 444.44);

-- -----------------------------------------------------------------------------
-- 3.2 TEST_ROLE_DEV_ONLY Tests (Full DEV_DB access, NO PROD_DB access)
-- -----------------------------------------------------------------------------

SELECT '========================================' as DIVIDER;
SELECT 'TESTING WITH TEST_ROLE_DEV_ONLY' as TITLE;
SELECT 'DEV_DB: Full access | PROD_DB: NO ACCESS' as PERMISSIONS;
SELECT '========================================' as DIVIDER;

USE ROLE TEST_ROLE_DEV_ONLY;
USE SECONDARY ROLES NONE;

SELECT 'TEST 5: Caller Rights + DEV_DB' as TEST;
SELECT 'Expected: SUCCESS (caller has UPDATE on DEV_DB)' as EXPECTED;
CALL DEV_DB.PUBLIC.UPDATE_TABLE_CALLER_RIGHTS_V2('DEV_DB', 2, 555.55);

SELECT 'TEST 6: Caller Rights + PROD_DB' as TEST;
SELECT 'Expected: FAIL (caller has NO access to PROD_DB)' as EXPECTED;
CALL DEV_DB.PUBLIC.UPDATE_TABLE_CALLER_RIGHTS_V2('PROD_DB', 2, 666.66);

SELECT 'TEST 7: Owner Rights + DEV_DB' as TEST;
SELECT 'Expected: SUCCESS (owner TEST_ROLE has UPDATE on DEV_DB)' as EXPECTED;
CALL DEV_DB.PUBLIC.UPDATE_TABLE_OWNER_RIGHTS_V2('DEV_DB', 2, 777.77);

SELECT 'TEST 8: Owner Rights + PROD_DB' as TEST;
SELECT 'Expected: FAIL (owner TEST_ROLE only has SELECT - NO PRIVILEGE ESCALATION)' as EXPECTED;
CALL DEV_DB.PUBLIC.UPDATE_TABLE_OWNER_RIGHTS_V2('PROD_DB', 2, 888.88);

-- -----------------------------------------------------------------------------
-- 3.3 Final State
-- -----------------------------------------------------------------------------

USE ROLE ACCOUNTADMIN;
SELECT '========================================' as DIVIDER;
SELECT 'FINAL TABLE STATE' as TITLE;
SELECT '========================================' as DIVIDER;
SELECT 'DEV_DB' as DB, * FROM DEV_DB.PUBLIC.TEST_TABLE ORDER BY ID;
SELECT 'PROD_DB' as DB, * FROM PROD_DB.PUBLIC.TEST_TABLE ORDER BY ID;

-- =============================================================================
-- PART 4: AGENT TESTING (via Snowsight UI)
-- =============================================================================
-- To test via the Cortex Agent UI in Snowsight:
--
-- Step 1: Set your role in a SQL worksheet:
--   USE ROLE TEST_ROLE;           -- or TEST_ROLE_DEV_ONLY
--   USE SECONDARY ROLES NONE;
--
-- Step 2: Navigate to AI & ML → Cortex AI → Agents → RIGHTS_TEST_AGENT
--
-- Step 3: Use these prompts:
--
-- TEST_ROLE Tests:
--   Test 1: Update ID 1 in DEV_DB to value 111.11 using caller rights    (Expected: SUCCESS)
--   Test 2: Update ID 1 in PROD_DB to value 222.22 using caller rights   (Expected: FAIL)
--   Test 3: Update ID 1 in DEV_DB to value 333.33 using owner rights     (Expected: SUCCESS)
--   Test 4: Update ID 1 in PROD_DB to value 444.44 using owner rights    (Expected: FAIL)
--
-- TEST_ROLE_DEV_ONLY Tests:
--   Test 5: Update ID 2 in DEV_DB to value 555.55 using caller rights    (Expected: SUCCESS)
--   Test 6: Update ID 2 in PROD_DB to value 666.66 using caller rights   (Expected: FAIL)
--   Test 7: Update ID 2 in DEV_DB to value 777.77 using owner rights     (Expected: SUCCESS)
--   Test 8: Update ID 2 in PROD_DB to value 888.88 using owner rights    (Expected: FAIL)
--
-- Step 4: Verify results:
--   SELECT * FROM DEV_DB.PUBLIC.TEST_TABLE ORDER BY ID;
--   SELECT * FROM PROD_DB.PUBLIC.TEST_TABLE ORDER BY ID;
-- =============================================================================
