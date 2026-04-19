function start_oracle {
# Usage:
#     start_oracle -env homelab
[CmdletBinding()]
Param([string]$env = "homelab")

$config_path = "Q:/.secrets/.env"
$Sqlplus = "C:\ORACLEHOME\WINDOWS.X64_193000_db_home\bin\sqlplus.exe"
$Config = @{}
Get-Content $config_path | ForEach-Object { if ($_ -match "oracle_${env}_(\w+)=(.*)") { $Config[$Matches[1]] = $Matches[2].Trim() } }

function Get-AvailableOracleEnvs {
    param([string]$ConfigPath)

    if (-not (Test-Path $ConfigPath)) {
        return @()
    }

    $names = New-Object System.Collections.Generic.List[string]
    Get-Content $ConfigPath | ForEach-Object {
        if ($_ -match '^oracle_([^_]+)_(user|pass|host|port|sid|service_name|role|pdb|pdb_name)=') {
            if (-not $names.Contains($Matches[1])) {
                [void]$names.Add($Matches[1])
            }
        }
    }

    return @($names | Sort-Object)
}

function Assert-OracleConfig {
    param(
        [string]$EnvName,
        [hashtable]$Config,
        [string]$ConfigPath
    )

    if (-not (Test-Path $ConfigPath)) {
        throw "Oracle config file not found: $ConfigPath"
    }

    if (-not $EnvName) {
        $available = Get-AvailableOracleEnvs -ConfigPath $ConfigPath
        $suffix = if ($available.Count -gt 0) { " Available values: $($available -join ', ')" } else { "" }
        throw "Missing -env. Usage: .\start.ps1 -env <name>.$suffix"
    }

    $requiredKeys = @('user', 'pass', 'host', 'port', 'service_name')
    $missingKeys = @($requiredKeys | Where-Object { -not $Config.ContainsKey($_) -or [string]::IsNullOrWhiteSpace($Config[$_]) })
    if ($missingKeys.Count -gt 0) {
        throw "Oracle config for env '$EnvName' is missing required keys: $($missingKeys -join ', ')"
    }
}

function Get-PdbTarget {
    param([hashtable]$Config)

    foreach ($key in @('pdb_name', 'pdb', 'service_name')) {
        if ($Config.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace($Config[$key])) {
            return $Config[$key]
        }
    }

    return $null
}

function Get-EzConnectString {
    param([hashtable]$Config)

    return "//{0}:{1}/{2}" -f $Config.host, $Config.port, $Config.service_name
}

Assert-OracleConfig -EnvName $env -Config $Config -ConfigPath $config_path

function Resolve-OracleServiceName {
    param([hashtable]$Config)

    if ($Config.ContainsKey("sid") -and $Config.sid) {
        $candidate = "OracleService$($Config.sid)"
        if (Get-Service -Name $candidate -ErrorAction SilentlyContinue) {
            return $candidate
        }
    }

    if ($Config.ContainsKey("service_name") -and $Config.service_name) {
        $candidate = "OracleService$($Config.service_name)"
        if (Get-Service -Name $candidate -ErrorAction SilentlyContinue) {
            return $candidate
        }
    }

    $all = Get-Service -Name "OracleService*" -ErrorAction SilentlyContinue
    if ($all.Count -eq 1) {
        return $all[0].Name
    }

    return $null
}

function Start-ServiceElevatedIfNeeded {
    param([string]$Name)

    if (-not $Name) {
        return
    }

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $service -or $service.Status -eq "Running") {
        return
    }

    try {
        Start-Service -Name $Name -ErrorAction Stop
    }
    catch {
        Start-Process powershell -Verb RunAs -ArgumentList @(
            "-NoProfile",
            "-Command",
            "Start-Service -Name '$Name'"
        ) -Wait
    }

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne "Running") {
        throw "Failed to start service '$Name'. Run this script in an elevated PowerShell session."
    }
}

$env:ORACLE_HOME = "C:\ORACLEHOME\WINDOWS.X64_193000_db_home"
$env:JDK_JAVA_OPTIONS = "--enable-native-access=ALL-UNNAMED"

$oracleService = Resolve-OracleServiceName -Config $Config
if ($oracleService) {
    Write-Host "Starting Oracle service: $oracleService"
    # Derive SID from the Windows service name — this is the ground truth
    $LocalOracleSid = $oracleService -replace '^OracleService', ''
}
else {
    Write-Warning "No OracleService* match found from config; STARTUP may fail."
    # Fall back to config values
    $LocalOracleSid = if ($Config.ContainsKey('sid') -and $Config.sid) { $Config.sid } elseif ($Config.ContainsKey('service_name') -and $Config.service_name) { $Config.service_name } else { 'ORACLEDB' }
}
Start-ServiceElevatedIfNeeded -Name $oracleService

$env:ORACLE_SID = $LocalOracleSid
Write-Host "Using ORACLE_SID: $env:ORACLE_SID"

$pdbTarget = Get-PdbTarget -Config $Config
$pdbOpenSql = if ($pdbTarget) {
    "ALTER PLUGGABLE DATABASE $pdbTarget OPEN;"
}
else {
    "ALTER PLUGGABLE DATABASE ALL OPEN;"
}

# Start Listener - only elevate if not already running (lsnrctl status needs no admin)
$lsnrUp = (lsnrctl status 2>&1) -match "The command completed successfully"
if (-not $lsnrUp) {
    Start-Process lsnrctl -ArgumentList "start" -Verb RunAs -Wait
}

$fraPath = "$env:ORACLE_HOME\fra"
if (-not (Test-Path $fraPath)) {
    New-Item -ItemType Directory -Path $fraPath -Force | Out-Null
    Write-Host "Created Fast Recovery Area directory: $fraPath"
}

$spfilePath    = "$env:ORACLE_HOME\database\SPFILE${LocalOracleSid}.ORA"
$fraPathFwd    = $fraPath -replace '\\', '/'
$spfilePathFwd = $spfilePath -replace '\\', '/'

# Probe STARTUP NOMOUNT to detect a bad db_recovery_file_dest before committing.
# Binary spfile parsing is unreliable; probing the actual error is definitive.
$probeOutput = "STARTUP NOMOUNT;`nSHUTDOWN ABORT;`nEXIT;" | & $Sqlplus "/ as sysdba" 2>&1 | Out-String

if ($probeOutput -match "ORA-01261|ORA-01263") {
    Write-Host "Detected invalid db_recovery_file_dest in spfile. Repairing..."
    Write-Host "Repairing spfile db_recovery_file_dest -> $fraPath"

    $pfileBootstrap = "$env:ORACLE_HOME\database\init_bootstrap.ora"
    $pfileExport    = "$env:ORACLE_HOME\database\init_${LocalOracleSid}_export.ora"
    "DB_NAME=$LocalOracleSid" | Set-Content $pfileBootstrap -Encoding ASCII

    # Phase 1: reach NOMOUNT via minimal pfile, export full spfile to text
    $p1 = @"
WHENEVER SQLERROR EXIT FAILURE;
STARTUP NOMOUNT PFILE='$($pfileBootstrap -replace '\\', '/')';
CREATE PFILE='$($pfileExport -replace '\\', '/')' FROM SPFILE='$spfilePathFwd';
SHUTDOWN ABORT;
EXIT;
"@ | & $Sqlplus "/ as sysdba" 2>&1
    Write-Host $p1
    if ($LASTEXITCODE -ne 0) { throw "Spfile export failed (exit $LASTEXITCODE): $p1" }

    # Phase 2: patch db_recovery_file_dest in the exported text pfile
    (Get-Content $pfileExport) |
        ForEach-Object { $_ -replace "(?i)\*\.db_recovery_file_dest\s*=\s*'[^']*'", "*\.db_recovery_file_dest='$fraPathFwd'" } |
        Set-Content $pfileExport -Encoding ASCII

    # Phase 3: recreate spfile from fixed pfile, then do a full open
    $startupOutput = @"
WHENEVER SQLERROR EXIT FAILURE;
STARTUP NOMOUNT PFILE='$($pfileExport -replace '\\', '/')';
CREATE SPFILE='$spfilePathFwd' FROM PFILE='$($pfileExport -replace '\\', '/')';
STARTUP FORCE;
$pdbOpenSql
ALTER SYSTEM REGISTER;
EXIT SUCCESS;
"@ | & $Sqlplus "/ as sysdba" 2>&1
}
else {
    $startupOutput = @"
WHENEVER SQLERROR EXIT FAILURE;
STARTUP;
$pdbOpenSql
ALTER SYSTEM REGISTER;
EXIT SUCCESS;
"@ | & $Sqlplus "/ as sysdba" 2>&1
}

Write-Host $startupOutput
if ($LASTEXITCODE -ne 0) {
    throw "SQL*Plus startup failed with exit code $LASTEXITCODE. Check ORACLE_SID='$env:ORACLE_SID' and that OracleService$env:ORACLE_SID is running."
}

# Run post-start SQL without SQLcl/JDK dependency.
& $Sqlplus "$($Config.user)/$($Config.pass)@$(Get-EzConnectString -Config $Config)" "@$PSScriptRoot\sql_startup.sql"
if ($LASTEXITCODE -ne 0) {
    throw "Post-start SQL failed with exit code $LASTEXITCODE"
}

$global:LASTEXITCODE = 0
}
