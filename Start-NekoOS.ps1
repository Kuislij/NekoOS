# Launch the Arch desktop from its Linux workspace in WSL2.
[CmdletBinding()]
param(
    [switch]$Build,
    [switch]$Test,
    [switch]$Headless,
    [switch]$Uefi,
    [string]$Distribution = 'Ubuntu',
    [string]$LinuxUser = 'neko',
    [string]$LinuxPath = '/home/neko/src/NekoOS'
)

$ErrorActionPreference = 'Stop'
if ($Build -and $Test) {
    throw 'Choose either -Build or -Test.'
}
$nekoAction = if ($Build) { 'build' } elseif ($Test) { 'test' } else { 'run' }
$nekoArguments = @('-d', $Distribution, '-u', $LinuxUser, '--cd', $LinuxPath,
    '--', 'bash', 'os', 'arch', $nekoAction)
if ($Headless) {
    if ($nekoAction -ne 'run') { throw '-Headless is only available when running NekoOS.' }
    $nekoArguments += '--headless'
}
if ($Uefi) {
    if ($Build) { throw '-Uefi selects VM firmware; the builder prepares both BIOS and UEFI.' }
    $nekoArguments += '--uefi'
}
& wsl.exe @nekoArguments
exit $LASTEXITCODE
