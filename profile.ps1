# Master PowerShell profile script, this executes before other profiles.
function reload {
    $modules_path = Join-Path $PSScriptRoot 'Modules'
    Get-ChildItem -Path $modules_path -Directory | ForEach-Object {
        Remove-Module $_.Name -Force -ErrorAction SilentlyContinue
        $importParams = @{ Force = $true }
        if ($_.Name -eq 'linux') { $importParams['DisableNameChecking'] = $true }
        Import-Module (Join-Path $_.FullName "$($_.Name).psm1") @importParams
    }
}

reload
secrets
write-host "Master Profile Loaded" -ForegroundColor Green