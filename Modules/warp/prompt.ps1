# Global setup
$Global:promptColor = "Default"
$Global:globalCustomPrompt = "PS $(Get-Location) > "
$Global:rainbowIncrement = 0

# ANSI escape codes — PS7 and modern terminals on PS5 (Windows Terminal, VS Code)
$colorMap_V7 = [ordered]@{
    "brightcyan"  = "`e[96m"
    "grey"        = "`e[90m"
    "cyan"        = "`e[36m"
    "purple"      = "`e[35m"
    "brightgreen" = "`e[92m"
    "brightwhite" = "`e[97m"
    "red"         = "`e[31m"
    "gold"        = "`e[33m"
    "blue"        = "`e[34m"
    "brightblue"  = "`e[94m"
    "orange"      = "`e[91m"
    "green"       = "`e[32m"
    "white"       = "`e[37m"
    "pink"        = "`e[95m"
    "yellow"      = "`e[93m"
}

# ConsoleColor names — PS5 fallback via Write-Host
$colorMap_V5 = [ordered]@{
    "brightcyan"  = "Cyan"
    "grey"        = "Gray"
    "cyan"        = "DarkCyan"
    "purple"      = "DarkMagenta"
    "brightgreen" = "Green"
    "white"       = "White"
    "red"         = "Red"
    "gold"        = "DarkYellow"
    "blue"        = "DarkBlue"
    "brightblue"  = "Blue"
    "orange"      = "DarkRed"
    "green"       = "DarkGreen"
    "pink"        = "Magenta"
    "yellow"      = "Yellow"
}

function Switch-PromptColor {
    param([string]$Color)

    if (-not $PSBoundParameters.ContainsKey('Color') -or [string]::IsNullOrWhiteSpace($Color)) {
        $Color = Read-Host "What color do you want for the prompt?"
    }

    $Global:promptColor = $Color
}

function prompt {
    try {
        return Get-CustomPrompt -colorChoice $Global:promptColor
    }
    catch {
        Write-Host "Prompt error: $($_.Exception.Message)" -ForegroundColor Red
        return "PS $(Get-Location) > "
    }
}

function Get-CustomPrompt {
    param([string]$colorChoice = "Default")

    try {
        if ([string]::IsNullOrWhiteSpace($colorChoice) -or $colorChoice.ToLower() -eq "default") {
            Set-DefaultPrompt
            return $Global:globalCustomPrompt
        }

        $version = $PSVersionTable.PSVersion.Major
        $colorChoice = $colorChoice.ToLower()

        switch ($version) {
            7 {
                if ($colorChoice -eq "rainbow") { Set-Rainbow_V7 }
                else                            { Set-StaticColor_V7 -colorChoice $colorChoice }
            }
            5 {
                if ($colorChoice -eq "rainbow") { Set-Rainbow_V5 }
                else                            { Set-StaticColor_V5 -colorChoice $colorChoice }
            }
            default {
                Write-Host "PowerShell version $version unsupported for custom prompt colors."
                Set-DefaultPrompt
            }
        }

        return $Global:globalCustomPrompt
    }
    catch {
        Write-Host "Get-CustomPrompt error: $($_.Exception.Message)" -ForegroundColor Red
        Set-DefaultPrompt
        return $Global:globalCustomPrompt
    }
}

function Set-DefaultPrompt {
    $Global:promptColor = "Default"
    $Global:globalCustomPrompt = "PS $(Get-Location) > "
}

function Set-Rainbow_V7 {
    try {
        $chars = ("PS $(Get-Location) > ").ToCharArray()
        $keys  = @($colorMap_V7.Keys)
        $Global:globalCustomPrompt = ""

        foreach ($char in $chars) {
            if ($Global:rainbowIncrement -ge $colorMap_V7.Count) {
                $Global:rainbowIncrement = 0
            }
            $Global:globalCustomPrompt += $colorMap_V7[$keys[$Global:rainbowIncrement]] + $char
            $Global:rainbowIncrement++
        }
    }
    catch {
        Write-Host "Set-Rainbow_V7 error: $($_.Exception.Message)" -ForegroundColor Red
        Set-DefaultPrompt
    }
}

function Set-StaticColor_V7 {
    param([string]$colorChoice = "Default")

    try {
        if ($colorMap_V7.Contains($colorChoice)) {
            $Global:globalCustomPrompt = $colorMap_V7[$colorChoice] + "PS $(Get-Location) > "
        }
        else {
            Write-Host "Invalid color choice: $colorChoice"
            Set-DefaultPrompt
        }
    }
    catch {
        Write-Host "Set-StaticColor_V7 error: $($_.Exception.Message)" -ForegroundColor Red
        Set-DefaultPrompt
    }
}

# V5 can't embed ConsoleColor in a return string — use Write-Host for the
# colored text and return a single space so PowerShell doesn't append its default prompt.
function Set-Rainbow_V5 {
    try {
        $chars = ("PS $(Get-Location) > ").ToCharArray()
        $keys  = @($colorMap_V5.Keys)

        foreach ($char in $chars) {
            if ($Global:rainbowIncrement -ge $colorMap_V5.Count) {
                $Global:rainbowIncrement = 0
            }
            Write-Host $char -ForegroundColor $colorMap_V5[$keys[$Global:rainbowIncrement]] -NoNewline
            $Global:rainbowIncrement++
        }

        # Return a space — prompt fn needs a non-empty string to suppress PS's default
        $Global:globalCustomPrompt = " "
    }
    catch {
        Write-Host "Set-Rainbow_V5 error: $($_.Exception.Message)" -ForegroundColor Red
        Set-DefaultPrompt
    }
}

function Set-StaticColor_V5 {
    param([string]$colorChoice = "Default")

    try {
        if ($colorMap_V5.Contains($colorChoice)) {
            $color      = $colorMap_V5[$colorChoice]
            $promptText = "PS $(Get-Location) > "
            Write-Host $promptText -ForegroundColor $color -NoNewline
            $Global:globalCustomPrompt = " "
        }
        else {
            Write-Host "Invalid color choice: $colorChoice"
            Set-DefaultPrompt
        }
    }
    catch {
        Write-Host "Set-StaticColor_V5 error: $($_.Exception.Message)" -ForegroundColor Red
        Set-DefaultPrompt
    }
}