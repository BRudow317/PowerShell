# Oracle 19c DBA Cheat Sheet
[sql path](C:\ORACLEHOME\WINDOWS.X64_193000_db_home\sqldeveloper\sqldeveloper\bin\sql.exe)
## Connection & Formatting
```shell
# Connect locally as SYSDBA
sqlplus / as sysdba
# Remote EZConnect
sqlplus system/password@//localhost:1521/oracledb
# Formatting (Linesize/Pagesize)
SET LINESIZE 200 PAGESIZE 100;
```

## Instance & Listener
```shell
# Check Instance status
SELECT instance_name, status, open_mode FROM v$instance, v$database;
# Startup (Immediate)
STARTUP;
# Shutdown (Immediate)
SHUTDOWN IMMEDIATE;
# Check Listener status
lsnrctl status
# Start Listener
lsnrctl start
```

## Multitenant (CDB/PDB)
```shell
# Show all PDBs
show pdbs;
# Open specific PDB
alter pluggable database homelab open;
# Open ALL PDBs
alter pluggable database all open;
# Switch to PDB container
alter session set container=homelab;
# Switch to Root container
alter session set container=CDB$ROOT;
# Save PDB state (keeps PDB open after CDB restart)
alter pluggable database homelab save state;
```

## Health & User Management
```shell
# List all users
select username, account_status from dba_users;
# Check tablespace usage
SELECT tablespace_name, used_space, tablespace_size FROM dba_tablespace_usage_metrics;
# List datafiles
SELECT file_name, tablespace_name, bytes/1024/1024 MB FROM dba_data_files;
# Active sessions
SELECT sid, serial#, username, status FROM v$session WHERE status = 'ACTIVE';
```