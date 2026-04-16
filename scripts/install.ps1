param(
    [Parameter(Mandatory = $true)]
    [string]$BoundaryVersion
)

$ErrorActionPreference = "Stop"

$InstallerUrl = "https://github.com/rebelopsio/boundary/releases/download/v${BoundaryVersion}/boundary-installer.ps1"

Write-Host "Installing boundary v${BoundaryVersion}..."
powershell -ExecutionPolicy Bypass -c "irm '${InstallerUrl}' | iex"
