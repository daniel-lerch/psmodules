<#
.SYNOPSIS
    Installs all PowerShell modules from this bundle to Documents\PowerShell\Modules for usage with PowerShell 7+
#>

$userModulesPath = $env:PSModulePath.Split(';')[0]
if (!(Test-Path -Path $userModulesPath -PathType Container)) {
    Write-Host "Creating user modules directory..."
    New-Item -Path $userModulesPath -ItemType Directory | Out-Null
}

$sourcePath = Join-Path $PSScriptRoot "Modules"
Start-Process -FilePath "Robocopy.exe" -ArgumentList "`"$sourcePath`"","`"$userModulesPath`"","/mir","/njh","/njs","/nfl","/ndl" -NoNewWindow -Wait

Get-ChildItem -Path $sourcePath -Directory | ForEach-Object {
    # Force reload in active session to simplify debugging
    Import-Module $_.Name -Force
}
