# Master PowerShell profile script, this executes before other profiles.
function reload {
    $modules_path = Join-Path $PSScriptRoot 'Modules'
    Get-ChildItem -Path $modules_path -Directory | ForEach-Object {
        Remove-Module $_.Name -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $_.FullName "$($_.Name).psm1") -Force
    }
}

reload
secrets
write-host "Master Profile Loaded" -ForegroundColor Green