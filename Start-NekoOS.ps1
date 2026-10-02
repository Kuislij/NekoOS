# Launch the Arch desktop from its Linux workspace in WSL2.
[CmdletBinding()]
param(
    [switch]$Build,
    [switch]$Test,
    [switch]$Headless,
    [switch]$Uefi,
    [switch]$Iso,
    [switch]$Usb,
    [switch]$Managed,
    [string]$Distribution = 'Ubuntu',
    [string]$LinuxUser = 'neko',
    [string]$LinuxPath = '/home/neko/src/NekoOS'
)

$ErrorActionPreference = 'Stop'
if ($Build -and $Test) {
    throw 'Choose either -Build or -Test.'
}
$nekoAction = if ($Build) { 'build' } elseif ($Test) { 'test' } else { 'run' }
if ($Managed -and ($Iso -or $Usb -or $Build)) {
    throw '-Managed selects the separate managed VM. Use Manage-NekoOS.ps1 for its initialization and updates.'
}
if ($Managed -and $Test -and $Uefi) { throw 'The managed update test already checks BIOS and UEFI.' }
$nekoArguments = @('-d', $Distribution, '-u', $LinuxUser, '--cd', $LinuxPath,
    '--', 'bash', 'os', 'arch')
if ($Iso) { $nekoArguments += 'iso' }
if ($Managed) { $nekoArguments += 'update' }
$nekoArguments += $nekoAction
if ($Headless) {
    if ($Build) { throw '-Headless selects VM display; use it with run or -Test.' }
    if (-not ($Managed -and $Test)) { $nekoArguments += '--headless' }
}
if ($Uefi) {
    if ($Build) { throw '-Uefi selects VM firmware; the builder prepares both BIOS and UEFI.' }
    if ($Iso -and $Test) { throw 'The ISO test already checks both BIOS and UEFI.' }
    $nekoArguments += '--uefi'
}
if ($Usb) {
    if (-not $Iso -or $Build -or $Test) { throw '-Usb selects a virtual USB medium for an ISO run.' }
    $nekoArguments += '--usb'
}
& wsl.exe @nekoArguments
exit $LASTEXITCODE
