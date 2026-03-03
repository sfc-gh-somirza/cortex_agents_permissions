-- cleanup.sql
-- Clean up all demo objects for Caller's Rights vs Owner's Rights Demo

USE ROLE ACCOUNTADMIN;

-- Drop agent first
DROP AGENT IF EXISTS DEV_DB.PUBLIC.RIGHTS_TEST_AGENT;

-- Drop procedures as TEST_ROLE (the owner)
USE ROLE TEST_ROLE;
DROP PROCEDURE IF EXISTS DEV_DB.PUBLIC.UPDATE_TABLE_CALLER_RIGHTS(STRING, INT, FLOAT);
DROP PROCEDURE IF EXISTS DEV_DB.PUBLIC.UPDATE_TABLE_OWNER_RIGHTS(STRING, INT, FLOAT);

-- Switch back to ACCOUNTADMIN for remaining cleanup
USE ROLE ACCOUNTADMIN;

-- Drop databases (this also drops any remaining procedures)
DROP DATABASE IF EXISTS DEV_DB;
DROP DATABASE IF EXISTS PROD_DB;

-- Drop roles
DROP ROLE IF EXISTS TEST_ROLE;
DROP ROLE IF EXISTS TEST_ROLE_DEV_ONLY;

SELECT 'Cleanup complete - all demo objects removed' as STATUS;
