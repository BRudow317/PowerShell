function start_sqlplus {
param(
    [string]$env = "homelab",
    [ValidateSet("Auto", "Service", "SID")]
    [string]$ConnectBy = "Auto"
)

$requestedConnectBy = $ConnectBy

# Resolve the secrets file path from SECRETS_ENV
if ($env:SECRETS_ENV) {
    $envFile = (Resolve-Path $env:SECRETS_ENV).Path
}

if (-not (Test-Path $envFile)) {
    Write-Error "Environment file not found: $envFile"
    return
}

# Parse the .env.md file
$envContent = Get-Content $envFile -Raw

function Get-EnvValue {
    param(
        [string]$Content,
        [string]$Key
    )

    $pattern = "(?m)^" + [regex]::Escape($Key) + "\s*=\s*(.+)$"
    $match = [regex]::Match($Content, $pattern)
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }
    return $null
}

# Extract credentials for the specified environment
$user = Get-EnvValue -Content $envContent -Key "ORACLE_${env}_USER"
$pass = Get-EnvValue -Content $envContent -Key "ORACLE_${env}_PWD"
$role = Get-EnvValue -Content $envContent -Key "ORACLE_${env}_ROLE"
$dbHost = Get-EnvValue -Content $envContent -Key "ORACLE_${env}_HOST"
$port = Get-EnvValue -Content $envContent -Key "ORACLE_${env}_PORT"
$service = Get-EnvValue -Content $envContent -Key "ORACLE_${env}_SERVICE"
if (-not $service) {
    $service = Get-EnvValue -Content $envContent -Key "ORACLE_${env}_SERVICE"
}
$sid = Get-EnvValue -Content $envContent -Key "ORACLE_${env}_SID"

if (-not $user -or -not $pass -or -not $dbHost -or -not $port) {
    Write-Error "Missing required keys for environment '$env'. Required: ORACLE_${env}_USER, ORACLE_${env}_PASS, ORACLE_${env}_HOST, ORACLE_${env}_PORT"
    return
}

if ($ConnectBy -eq "Service" -and -not $service) {
    Write-Error "ConnectBy=Service requires ORACLE_${env}_SERVICE"
    return
}

if ($ConnectBy -eq "SID" -and -not $sid) {
    Write-Error "ConnectBy=SID requires ORACLE_${env}_SID"
    return
}

if ($ConnectBy -eq "Auto") {
    if ($service) {
        $ConnectBy = "Service"
    }
    elseif ($sid) {
        $ConnectBy = "SID"
    }
    else {
        Write-Error "No Oracle connect identifier found. Add ORACLE_${env}_SERVICE (or ORACLE_${env}_SERVICE) or ORACLE_${env}_SID"
        return
    }
}

if ($ConnectBy -eq "Service") {
    # EZConnect with service name
    $connectDescriptor = "//${dbHost}:${port}/${service}"
    $env:ORACLE_SID = $service
}
else {
    # Explicit descriptor with SID for DBs not registered by service
    $connectDescriptor = "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${dbHost})(PORT=${port}))(CONNECT_DATA=(SID=${sid})))"
    $env:ORACLE_SID = $sid
}

# SQL*Plus treats '@' as the connect-identifier separator, so quote passwords
# to support special characters like '@'.
$escapedUser = $user.Replace('"', '""')
$escapedPass = $pass.Replace('"', '""')
$connectionString = '"' + $escapedUser + '"/"' + $escapedPass + '"@' + $connectDescriptor
$roleArg = $null
if ($role -and $role.Trim() -and $role.ToLowerInvariant() -ne "default") {
    $roleArg = $role.Trim().ToUpperInvariant()
}
# Set ORACLE_HOME if not already set
if (-not $env:ORACLE_HOME) {
    $env:ORACLE_HOME = "C:\ORACLEHOME\WINDOWS.X64_193000_db_home"
}

# Find sqlplus
$sqlplusPath = Join-Path $env:ORACLE_HOME "bin\sqlplus.exe"
if (-not (Test-Path $sqlplusPath)) {
    Write-Error "sqlplus not found at $env:ORACLE_HOME\bin\sqlplus.exe"
    Write-Error "Please verify ORACLE_HOME is set correctly"
    return
}

# In Auto mode, prefer service name but transparently fallback to SID on ORA-12514.
if ($requestedConnectBy -eq "Auto" -and $ConnectBy -eq "Service" -and $sid) {
    $serviceConnectionString = $connectionString
    if ($roleArg) {
        $probeOutput = (
            "exit" | & $sqlplusPath -L -S $serviceConnectionString "AS" $roleArg 2>&1 | Out-String
        )
    }
    else {
        $probeOutput = (
            "exit" | & $sqlplusPath -L -S $serviceConnectionString 2>&1 | Out-String
        )
    }

    if ($probeOutput -match "ORA-12514") {
        Write-Warning "Service '$service' is not registered with listener; retrying with SID '$sid'."
        $ConnectBy = "SID"
        $connectDescriptor = "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${dbHost})(PORT=${port}))(CONNECT_DATA=(SID=${sid})))"
        $connectionString = '"' + $escapedUser + '"/"' + $escapedPass + '"@' + $connectDescriptor
        $env:ORACLE_SID = $sid

        # Probe the SID connection before attempting to launch interactive sqlplus
        if ($roleArg) {
            $sidProbeOutput = (
                "exit" | & $sqlplusPath -L -S $connectionString "AS" $roleArg 2>&1 | Out-String
            )
        }
        else {
            $sidProbeOutput = (
                "exit" | & $sqlplusPath -L -S $connectionString 2>&1 | Out-String
            )
        }
        $sidExitCode = $LASTEXITCODE
        if ($sidProbeOutput -match "ORA-12505" -or ($sidExitCode -ne 0 -and $sidProbeOutput -match "ORA-")) {
            Write-Error "SID '$sid' is not registered with the listener at ${dbHost}:${port}. Run 'lsnrctl status' on the server to see registered instances."
            return
        }
        if ($sidProbeOutput -match "ORA-(\d+)" -or $sidExitCode -ne 0) {
            Write-Error "SID fallback failed (exit $sidExitCode). Output: $sidProbeOutput"
            return
        }
    }
}

# Start sqlplus with the connection string
Write-Host "Connecting to ${dbHost}:$port using $ConnectBy"
if ($roleArg) {
    & $sqlplusPath -L $connectionString "AS" $roleArg
}
else {
    & $sqlplusPath -L $connectionString
}
}
