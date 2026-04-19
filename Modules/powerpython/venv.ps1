function venv {
    $candidates = @('.venv', 'venv')

    foreach ($name in $candidates) {
        $script = Join-Path $PWD $name 'Scripts/Activate.ps1'
        if (Test-Path $script) {
            # Write-Host "Activating $name..." -ForegroundColor DarkGray
            . $script
            return
        }
    }

    Write-Host "No venv found in current directory" -ForegroundColor Yellow
}