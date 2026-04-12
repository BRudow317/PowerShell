# Usage:
#     & "Q:\db\oracledb\stop.ps1" -env homelab

[CmdletBinding()]
Param([string]$env = "homelab")

$config_path = "Q:/.secrets/.env"
$Sqlplus = "C:\ORACLEHOME\WINDOWS.X64_193000_db_home\bin\sqlplus.exe"
$Config = @{}
Get-Content $config_path | ForEach-Object { if ($_ -match "oracle_${env}_(\w+)=(.*)") { $Config[$Matches[1]] = $Matches[2].Trim() } }

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

    $running = Get-Service -Name "OracleService*" -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq "Running" }
    if ($running.Count -eq 1) {
        return $running[0].Name
    }

    $all = Get-Service -Name "OracleService*" -ErrorAction SilentlyContinue
    if ($all.Count -eq 1) {
        return $all[0].Name
    }

    return $null
}

function Stop-ServiceElevatedIfNeeded {
    param([string]$Name)

    if (-not $Name) {
        return
    }

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $service -or $service.Status -eq "Stopped") {
        return
    }

    if ($service.Status -eq "StopPending") {
        try {
            $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(30))
        }
        catch {
            $service.Refresh()
        }
        if ($service.Status -eq "Stopped") {
            return
        }
    }

    try {
        Stop-Service -Name $Name -Force -ErrorAction Stop
        $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq "StopPending") {
            try {
                $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(30))
            }
            catch {
                $service.Refresh()
            }
        }
    }
    catch {
        Start-Process powershell -Verb RunAs -ArgumentList @(
            "-NoProfile",
            "-Command",
            "Stop-Service -Name '$Name' -Force"
        ) -Wait

        $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq "StopPending") {
            try {
                $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(30))
            }
            catch {
                $service.Refresh()
            }
        }
    }

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne "Stopped") {
        throw "Failed to stop service '$Name'. Final status: $($service.Status). Run this script in an elevated PowerShell session or verify no dependent process is blocking stop."
    }
}

$env:ORACLE_HOME = "C:\ORACLEHOME\WINDOWS.X64_193000_db_home"
$env:JDK_JAVA_OPTIONS = "--enable-native-access=ALL-UNNAMED"

$oracleService = Resolve-OracleServiceName -Config $Config
$serviceBefore = if ($oracleService) { Get-Service -Name $oracleService -ErrorAction SilentlyContinue } else { $null }

# 1. Close PDB and shut down CDB via sqlplus as sysdba
if ($serviceBefore -and $serviceBefore.Status -eq "Running") {
    @"
WHENEVER SQLERROR CONTINUE;
ALTER PLUGGABLE DATABASE $($Config.service_name) CLOSE IMMEDIATE;
SHUTDOWN IMMEDIATE;
EXIT SUCCESS;
"@ | & $Sqlplus "/ as sysdba"
}
else {
    $status = if ($serviceBefore) { $serviceBefore.Status } else { "NotFound" }
    Write-Host "Oracle service state is '$status'; skipping SQL shutdown step."
}

# 2. Stop Oracle database service so the oracle kernel process exits
if ($oracleService) {
    Write-Host "Stopping Oracle service: $oracleService"
}
else {
    Write-Warning "No OracleService* match found from config; database service may still be running."
}
Stop-ServiceElevatedIfNeeded -Name $oracleService

# If the service is down but oracle.exe is still alive, force cleanup.
$serviceAfter = if ($oracleService) { Get-Service -Name $oracleService -ErrorAction SilentlyContinue } else { $null }
if ($serviceAfter -and $serviceAfter.Status -eq "Stopped") {
    $oracleProcs = Get-Process -Name "oracle" -ErrorAction SilentlyContinue
    if ($oracleProcs) {
        Write-Warning "oracle.exe is still running after service stop; terminating process."
        Stop-Process -Name "oracle" -Force -ErrorAction SilentlyContinue
    }
}

# 3. Stop Listener - only elevate if running
$lsnrUp = (lsnrctl status 2>&1) -match "The command completed successfully"
if ($lsnrUp) {
    Start-Process lsnrctl -ArgumentList "stop" -Verb RunAs -Wait
}

# Script succeeded if we reached here without throw.
$global:LASTEXITCODE = 0
