function touch {
    param([string[]]$Paths)

    foreach ($Path in $Paths) {
        if (Test-Path $Path) {
            (Get-Item $Path).LastWriteTime = Get-Date
        } else {
            New-Item -ItemType File -Path $Path | Out-Null
        }
    }
}