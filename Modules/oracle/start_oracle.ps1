function start_oracle {
# Usage:
#     start_oracle -env homelab
[CmdletBinding()]
Param([string]$env = "homelab")

$config_path  = "Q:/.secrets/.env"
$Sqlplus      = "C:\ORACLEHOME\WINDOWS.X64_193000_db_home\bin\sqlplus.exe"
$Config       = @{}
Get-Content $config_path | ForEach-Object {
    if ($_ -match "oracle_${env}_(\w+)=(.*)") { $Config[$Matches[1]] = $Matches[2].Trim() }
}

$env:ORACLE_HOME       = "C:\ORACLEHOME\WINDOWS.X64_193000_db_home"
$env:JDK_JAVA_OPTIONS  = "--enable-native-access=ALL-UNNAMED"

# Find and start the Oracle Windows service
$oracleService = Get-Service -Name "OracleService*" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $oracleService) { throw "No OracleService* Windows service found." }

$env:ORACLE_SID = $oracleService.Name -replace '^OracleService', ''
Write-Host "Using ORACLE_SID: $env:ORACLE_SID"

if ($oracleService.Status -ne "Running") {
    Write-Host "Starting $($oracleService.Name)..."
    try {
        Start-Service -Name $oracleService.Name -ErrorAction Stop
    }
    catch {
        Start-Process "sc.exe" -Verb RunAs -ArgumentList "start", $oracleService.Name -Wait
    }
    $oracleService.Refresh()
    if ($oracleService.Status -ne "Running") {
        throw "Failed to start $($oracleService.Name). Service did not reach Running state."
    }
}

# Start listener if not already up
if ((lsnrctl status 2>&1) -notmatch "The command completed successfully") {
    Start-Process lsnrctl -ArgumentList "start" -Verb RunAs -Wait
}

# Start database and open all pluggable databases
@"
STARTUP;
ALTER PLUGGABLE DATABASE ALL OPEN;
ALTER SYSTEM REGISTER;
EXIT;
"@ | & $Sqlplus "/ as sysdba"

$global:LASTEXITCODE = 0
}
