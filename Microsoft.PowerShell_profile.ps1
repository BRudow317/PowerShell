# ----PowerShell 7 Default Profile File------------------------------------------------------------------
# $MyUtilModulePath = "Q:\HomeLabDev\PowerShellScripts\MyUtilModule\MyUtilModule.psm1"
# Import-Module $MyUtilModulePath -Force -Verbose
# Set-Alias touch New-Item

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

# ----End of File---------------------------------------------------------------------------------------