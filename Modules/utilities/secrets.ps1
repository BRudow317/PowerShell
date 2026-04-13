# Loads a .env file into the current PowerShell session.
# Searches for .env in this order:
#   1. Specified path (via -EnvPath)
#   2. $env:SECRETS_ENV (when -Evm is set, which is the default)
#   3. Current working directory
#
# Usage:
#   secrets -EnvPath "C:\path\to\.env"
#   secrets   # uses $env:SECRETS_ENV or cwd/.env
function secrets {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$false)]
    [string]$EnvPath,
    [Parameter(Mandatory=$false)]
    [switch]$Evm = $true  # Environment variable mode: check $env:SECRETS_ENV for the .env path
  )

  $envResolved = $null

  if ($EnvPath) {
    # User provided explicit path
    if (Test-Path -LiteralPath $EnvPath) {
      $envResolved = (Resolve-Path -LiteralPath $EnvPath).Path
      Write-Debug "Using .env from explicit path: $envResolved"
    } else {
      Write-Error "Provided .env path does not exist: $EnvPath"
      return
    }
  } elseif ($Evm -and $env:SECRETS_ENV) {
    # Check environment variable
    $envResolved = (Resolve-Path -LiteralPath $env:SECRETS_ENV).Path
    Write-Debug "Using .env from SECRETS_ENV: $envResolved"
  } else {
    # Check current working directory
    $currentDirEnv = Join-Path (Get-Location).Path ".env"
    if (Test-Path -LiteralPath $currentDirEnv) {
      $envResolved = (Resolve-Path -LiteralPath $currentDirEnv).Path
      Write-Debug "Found .env in current directory: $envResolved"
    }
  }

  if (-not $envResolved) {
    Write-Error @"
Missing .env file. Searched in:
  1. `$env:SECRETS_ENV: $env:SECRETS_ENV
  2. Current directory: $(Join-Path (Get-Location).Path '.env')
Provide an explicit path with: secrets -EnvPath 'C:\path\to\.env'
"@
    return
  }

  # Parse .env into an ordered dictionary (preserves file order)
  $vars = [System.Collections.Specialized.OrderedDictionary]::new()

  Get-Content -LiteralPath $envResolved | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith('#')) { return }

    if ($line.StartsWith('export ')) { $line = $line.Substring(7).Trim() }

    if ($line -notmatch '^[A-Za-z_][A-Za-z0-9_]*=') { return }

    $name, $value = $line -split '=', 2
    $name  = $name.Trim()
    $value = $value.Trim()

    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
      $value = $value.Substring(1, $value.Length - 2)
    }

    if (-not $vars.Contains($name)) { $vars.Add($name, $value) } else { $vars[$name] = $value }
  }

  if ($vars.Count -eq 0) {
    Write-Error "No KEY=VALUE entries found in $envResolved"
    return
  }

  Write-Debug "Loading $($vars.Count) environment variables from .env:"
  $vars.Keys | ForEach-Object { Write-Debug "  - $_" }

  # Load variables into current session
  foreach ($k in $vars.Keys) {
    Set-Item -Path ("Env:{0}" -f $k) -Value ([string]$vars[$k])
  }

  Write-Debug "Environment variables loaded successfully into current session."
}

# Set-Alias -Name secrets -Value secrets