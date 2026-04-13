"
query select 'hello' world from dual;

# Different env
query select count(*) from users; -env prod
A few notes on what it does:

-S flag runs sqlplus in silent mode — suppresses the banner, copyright, and SQL> prompt so you only see query output
SET PAGESIZE 50000 / SET LINESIZE 200 prevents sqlplus from truncating rows or inserting page breaks mid-output
SQL is piped via stdin so you don't need to deal with temp files or escaping
If you find you want the sqlplus banner/prompt visible (e.g. for interactive debugging), just remove the -S flag.
"

function ora {
[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Sql,
    [string]$File,
    [string]$env = "homelab"
)

if ($Sql -and $File) { Write-Error "Specify either a SQL string or -File, not both."; return }
if (-not $Sql -and -not $File) { Write-Error "Specify either a SQL string or -File <path>."; return }

if ($File) {
    if (-not (Test-Path $File)) { Write-Error "File not found: $File"; return }
    $sqlContent = Get-Content $File -Raw
} else {
    $sqlContent = $Sql
}

$config_path = "Q:/.secrets/.env"
$Config = @{}
Get-Content $config_path | ForEach-Object { if ($_ -match "oracle_${env}_(\w+)=(.*)") { $Config[$Matches[1]] = $Matches[2].Trim() } }

if (-not $env:ORACLE_HOME) {
    $env:ORACLE_HOME = "C:\ORACLEHOME\WINDOWS.X64_193000_db_home"
}

$sqlplusPath = Join-Path $env:ORACLE_HOME "bin\sqlplus.exe"
$connectionString = "$($Config.user)/$($Config.pass)@$($Config.host):$($Config.port)/$($Config.service_name)"

@"
SET PAGESIZE 50000
SET LINESIZE 200
SET FEEDBACK ON
SET HEADING ON
$sqlContent
EXIT;
"@ | & $sqlplusPath -S $connectionString
}
