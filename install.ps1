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
Get-ChildItem -Path $sourcePath -Directory | ForEach-Object {
    if (Test-Path -Path (Join-Path $installPath $_.Name) -PathType Container) {
        Write-Host "Updating module $($_.Name)..."
        Remove-Item -Path (Join-Path $installPath $_.Name) -Recurse
    } else {
        Write-Host "Installing module $($_.Name)..."
    }
    Copy-Item -Path (Join-Path $sourcePath $_.Name) -Destination $installPath -Recurse
    # Force reload in active session to simplify debugging
    Import-Module $_.Name -Force
}
