# Read-only Windows-side prerequisite check. Does not enable features or reboot.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wslCommand) {
    Write-Output 'WSL_NOT_READY: wsl.exe is unavailable. See docs/development.md.'
    exit 1
}

# wsl.exe emits UTF-16 when redirected, unlike most Windows CLI tools.
$previousEncoding = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    $distributions = @(& $wslCommand.Source --list --quiet 2>&1)
    $listExit = $LASTEXITCODE
    $details = @(& $wslCommand.Source --list --verbose 2>&1)
} finally {
    [Console]::OutputEncoding = $previousEncoding
}
Write-Output ($details -join [Environment]::NewLine)
if ($listExit -ne 0 -or -not (($distributions -join '').Trim())) {
    if (Get-Command ubuntu.exe -ErrorAction SilentlyContinue) {
        Write-Output 'Ubuntu launcher found. If Windows requested a reboot, reboot first; then open Ubuntu from Start to complete initial setup.'
    }
    Write-Output 'WSL_NOT_READY: no Linux distribution is registered.'
    exit 1
}

# Only inspect Ubuntu; never start a different user distribution implicitly.
$ubuntuInstalled = @($distributions | Where-Object { $_.ToString().Trim() -eq 'Ubuntu' }).Count -gt 0
if (-not $ubuntuInstalled) {
    Write-Output 'WSL_NOT_READY: Ubuntu is not registered. See docs/development.md.'
    exit 1
}
# No Linux command is run here: first launch may require interactive setup.
if (-not ($details | Where-Object { $_.ToString() -match '^\s*\*?\s*Ubuntu\s+.+\s+2\s*$' })) {
    Write-Output 'WSL_NOT_READY: Ubuntu is not configured as WSL2.'
    exit 1
}
Write-Output 'WSL_REGISTERED: Ubuntu uses WSL2. Run bash os check inside Ubuntu to verify tools.'
