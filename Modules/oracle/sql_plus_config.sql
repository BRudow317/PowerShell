-- SQLcl Startup Customization (Auto-executed by start_homelab.ps1)
SET LINESIZE 200
SET PAGESIZE 100
SET FEEDBACK ON
SET ECHO OFF

-- Custom Prompt: USER@SERVICE >
-- SET SQLPROMPT "_USER'@'_CONNECT_IDENTIFIER > "

-- Add any additional session startup commands here
-- ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS';

-- PROMPT SQLcl environment configured. Ready for SQL commands.

select distinct table_name from all_tab_columns where lower('owner') = 'brudow';

EXIT;
