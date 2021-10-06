<#
.SYNOPSIS
    Installs all PowerShell modules from this bundle to Documents\PowerShell\Modules for usage with PowerShell 7+
#>

$documents = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::MyDocuments)
$installPath = Join-Path $documents "PowerShell" "Modules"
if (!(Test-Path -Path $installPath -PathType Container)) {
    Write-Host "Creating user modules directory..."
    New-Item -Path $installPath -ItemType Directory | Out-Null
}

$sourcePath = Join-Path $PSScriptRoot "Modules"
Start-Process -FilePath "Robocopy.exe" -ArgumentList "`"$sourcePath`"","`"$installPath`"","/mir","/njh","/njs","/nfl","/ndl" -NoNewWindow -Wait

Get-ChildItem -Path $sourcePath -Directory | ForEach-Object {
    # Force reload in active session to simplify debugging
    Import-Module $_.Name -Force
}
