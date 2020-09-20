<#
.SYNOPSIS
Overrides a physical device with random data
#>
function Clear-PhysicalDrive {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[int]$Number
	)
	
	begin {
		function FormatBytes([long]$bytes) {
			if ($bytes -lt 1024) {
				return "$bytes bytes"
			}
			elseif ($bytes -lt 1024 * 1024) {
				return "$($bytes / 1024) KB"
			}
			elseif ($bytes -lt 1024 * 1024 * 1024) {
				return "$($bytes / 1024 / 1024) MB"
			}
			else {
				return "$($bytes / 1024 / 1024 / 1024) GB"
			}
		}
	}
	
	process {
		$buffer = New-Object byte[] 16777216
		$random = New-Object System.Random
		[long]$done = 0

		try {
			$stream = New-Object System.IO.FileStream("\\.\PHYSICALDRIVE$Number", [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, $buffer.Length, [System.IO.FileOptions]::None)
			while ($true) {
				$random.NextBytes($buffer)
				$stream.Write($buffer, 0, $buffer.Length)
				$done += $buffer.Length
				Write-Progress -Activity "Overriding drive $Number" -Status "$(FormatBytes $done) written"
			}
		}
		finally {
			if ($stream) {
				$stream.Dispose()
			}
			Write-Progress -Activity "Overriding drive $Number" -Completed
			Write-Host "$(FormatBytes $done) written"
		}
	}
}
