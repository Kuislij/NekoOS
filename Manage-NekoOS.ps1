# Manage system generations of the separate NekoOS VM in the native WSL workspace.
[CmdletBinding()]
param(
    [ValidateSet('init', 'status', 'prepare', 'activate', 'rollback', 'discard', 'forget-previous', 'test')]
    [string]$Action = 'status',
    [string]$Distribution = 'Ubuntu',
    [string]$LinuxUser = 'neko',
    [string]$LinuxPath = '/home/neko/src/NekoOS'
)

$ErrorActionPreference = 'Stop'
$nekoArguments = @('-d', $Distribution, '-u', $LinuxUser, '--cd', $LinuxPath,
    '--', 'bash', 'os', 'arch', 'update', $Action)
& wsl.exe @nekoArguments
exit $LASTEXITCODE
