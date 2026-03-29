function newpy {
    param(
        [string]$Name = ''
    )

    #  Resolve project root 
    if ([string]::IsNullOrWhiteSpace($Name)) {
        $project_root = $PWD.Path
        $project_name = Split-Path $project_root -Leaf
    }
    else {
        $project_root = Join-Path $PWD.Path $Name
        $project_name = $Name
    }

    #  Helpers 
    function Write-Step  { param($msg) Write-Host "  $msg" -ForegroundColor DarkGray }
    function Write-Skip  { param($msg) Write-Host "  skip  $msg" -ForegroundColor DarkYellow }
    function Write-Done  { param($msg) Write-Host "  ok    $msg" -ForegroundColor DarkGreen }

    function New-SafeDir {
        param([string]$Path)
        if (-not (Test-Path $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-Done $Path
        }
        else {
            Write-Skip $Path
        }
    }

    function New-SafeFile {
        param([string]$Path, [string]$Content)
        if (-not (Test-Path $Path)) {
            Set-Content -Path $Path -Value $Content -Encoding UTF8
            Write-Done $Path
        }
        else {
            Write-Skip $Path
        }
    }

    #  Create project root 
    Write-Host ""
    Write-Host "newpy: $project_name" -ForegroundColor Cyan
    Write-Host ""

    New-SafeDir $project_root

    #  Directory structure 
    New-SafeDir (Join-Path $project_root 'app')
    New-SafeDir (Join-Path $project_root 'tests')

    #  app/app.py 
    New-SafeFile (Join-Path $project_root 'app\app.py') @"
def main():
    pass
"@

    #  app/__init__.py 
    New-SafeFile (Join-Path $project_root 'app\__init__.py') ""

    #  tests/__init__.py 
    New-SafeFile (Join-Path $project_root 'tests\__init__.py') ""

    #  tests/test_app.py 
    New-SafeFile (Join-Path $project_root 'tests\test_app.py') @"
from app.app import main


def test_main():
    pass
"@

    #  main.py 
    New-SafeFile (Join-Path $project_root 'main.py') @"
from app.app import main

if __name__ == '__main__':
    main()
"@

    #  .env 
    New-SafeFile (Join-Path $project_root '.env') "# environment variables"

    #  .gitignore 
    New-SafeFile (Join-Path $project_root '.gitignore') @"
# venv
.venv/
venv/

# env
.env

# Python
__pycache__/
*.py[cod]
*.pyo
*.pyd
*.egg
*.egg-info/
dist/
build/
.eggs/

# pytest
.pytest_cache/
htmlcov/
.coverage
coverage.xml

# tools
.vscode/
.idea/
*.log
"@

    #  pyproject.toml 
    New-SafeFile (Join-Path $project_root 'pyproject.toml') @"
[build-system]
requires = ["setuptools>=68", "wheel"]
build-backend = "setuptools.backends.legacy:build"

[project]
name = "$project_name"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = []

[tool.pytest.ini_options]
testpaths = ["tests"]

[tool.setuptools.packages.find]
where = ["."]
"@

    #  README.md 
    New-SafeFile (Join-Path $project_root 'README.md') @"
# $project_name
"@

    #  .venv 
    $venv_path = Join-Path $project_root '.venv'
    if (-not (Test-Path $venv_path)) {
        Write-Step "creating .venv..."
        python -m venv $venv_path
        Write-Done ".venv"
    }
    else {
        Write-Skip ".venv (already exists)"
    }

    #  pip install from PSScriptRoot\requirements.txt 
    $default_reqs = Join-Path $PSScriptRoot 'requirements.txt'
    if (Test-Path $default_reqs) {
        Write-Step "installing default requirements..."
        & "$venv_path\Scripts\python.exe" -m pip install -r $default_reqs --quiet
        Write-Done "requirements installed"
    }
    else {
        Write-Skip "no requirements.txt found at $default_reqs"
    }

    #  Done 
    Write-Host ""
    Write-Host "done. " -NoNewline -ForegroundColor DarkGreen
    Write-Host "cd $project_root" -ForegroundColor DarkGray
    Write-Host ""
}