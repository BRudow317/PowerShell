function start_sqlcl {
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
$user = Get-EnvValue -Content $envContent -Key "oracle_${env}_user"
$pass = Get-EnvValue -Content $envContent -Key "oracle_${env}_pass"
$dbHost = Get-EnvValue -Content $envContent -Key "oracle_${env}_host"
$port = Get-EnvValue -Content $envContent -Key "oracle_${env}_port"
$service = Get-EnvValue -Content $envContent -Key "oracle_${env}_service_name"
if (-not $service) {
    $service = Get-EnvValue -Content $envContent -Key "oracle_${env}_service"
}
$sid = Get-EnvValue -Content $envContent -Key "oracle_${env}_sid"

if (-not $user -or -not $pass -or -not $dbHost -or -not $port) {
    Write-Error "Missing required keys for environment '$env'. Required: oracle_${env}_user, oracle_${env}_pass, oracle_${env}_host, oracle_${env}_port"
    return
}

if ($ConnectBy -eq "Service" -and -not $service) {
    Write-Error "ConnectBy=Service requires oracle_${env}_service_name (or oracle_${env}_service)"
    return
}

if ($ConnectBy -eq "SID" -and -not $sid) {
    Write-Error "ConnectBy=SID requires oracle_${env}_sid"
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
        Write-Error "No Oracle connect identifier found. Add oracle_${env}_service_name (or oracle_${env}_service) or oracle_${env}_sid"
        return
    }
}

if ($ConnectBy -eq "Service") {
    $connectDescriptor = "//${dbHost}:${port}/${service}"
    $env:ORACLE_SID = $service
}
else {
    $connectDescriptor = "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${dbHost})(PORT=${port}))(CONNECT_DATA=(SID=${sid})))"
    $env:ORACLE_SID = $sid
}

# Build an explicit thin JDBC URL so sqlcl cannot choose OCI8 regardless of
# ORACLE_HOME, PATH, or Windows registry Oracle client detection.
if ($ConnectBy -eq "Service") {
    $thinUrl = "jdbc:oracle:thin:@//${dbHost}:${port}/${service}"
} else {
    $thinUrl = "jdbc:oracle:thin:@${dbHost}:${port}:${sid}"
}
$connectionString = "${user}/${pass}@'${thinUrl}'"

# Find sqlcl
$sqlclPath = "C:\Program Files\sqlcl\bin\sql.exe"
if (-not (Test-Path $sqlclPath)) {
    Write-Error "sqlcl not found at $sqlclPath"
    return
}

# Preflight: ensure a thin JDBC driver jar is present in the sqlcl lib directory.
# sqlcl bundles one, but if it's missing we download ojdbc11 from Maven Central.
$sqlclLibDir = "C:\Program Files\sqlcl\lib"
$ojdbcJar = Get-ChildItem -Path $sqlclLibDir -Filter "ojdbc*.jar" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $ojdbcJar) {
    Write-Warning "No ojdbc jar found in $sqlclLibDir — downloading ojdbc11 from Maven Central..."
    $mavenUrl = "https://repo1.maven.org/maven2/com/oracle/database/jdbc/ojdbc11/23.7.0.25.01/ojdbc11-23.7.0.25.01.jar"
    $destJar  = Join-Path $sqlclLibDir "ojdbc11-23.7.0.25.01.jar"
    try {
        Invoke-WebRequest -Uri $mavenUrl -OutFile $destJar -UseBasicParsing
        Write-Host "Downloaded: $destJar"
    } catch {
        Write-Error "Failed to download ojdbc11: $_"
        return
    }
}

# Clear ORACLE_HOME and also set JAVA_TOOL_OPTIONS to suppress OCI loading at
# the JVM level.  Oracle's JDBC driver sniffs the Windows registry for Oracle
# client independent of ORACLE_HOME/PATH, so we force thin at two layers:
#  1. Explicit jdbc:oracle:thin: URL (primary)
#  2. JVM property oracle.jdbc.oracleClient=false (secondary)
$savedOracleHome    = $env:ORACLE_HOME
$savedOracleSid     = $env:ORACLE_SID
$savedJavaToolOpts  = $env:JAVA_TOOL_OPTIONS

$env:ORACLE_HOME        = $null
$env:JAVA_TOOL_OPTIONS  = (($env:JAVA_TOOL_OPTIONS, '-Doracle.jdbc.oracleClient=false') -ne '' -join ' ').Trim()

try {
    Write-Host "Connecting to ${dbHost}:$port using $ConnectBy (thin JDBC)"
    & $sqlclPath $connectionString
} finally {
    $env:ORACLE_HOME       = $savedOracleHome
    $env:ORACLE_SID        = $savedOracleSid
    $env:JAVA_TOOL_OPTIONS = $savedJavaToolOpts
}
}
