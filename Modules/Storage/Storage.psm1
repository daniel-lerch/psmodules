<#
.SYNOPSIS
	Overrides a physical device with random data
.PARAMETER Number
	The physical drive number to override
.PARAMETER Force
	Start overriding without prompting for confirmation
#>
function Clear-PhysicalDrive {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[int]$Number,
		[switch]$Force
	)
	
	begin {
		function FormatBytes([long]$bytes) {
			if ($bytes -lt 1024) {
				return "$bytes bytes"
			}
			elseif ($bytes -lt 1024 * 1024) {
				return "$([System.Math]::Round($bytes / 1024)) KB"
			}
			elseif ($bytes -lt 1024 * 1024 * 1024) {
				return "$([System.Math]::Round($bytes / 1024 / 1024, 1)) MB"
			}
			else {
				return "$([System.Math]::Round($bytes / 1024 / 1024 / 1024, 2)) GB"
			}
		}
	}
	
	process {
		$bufferSizeMb = 32
		$buffer = New-Object byte[] ($bufferSizeMb * 1048576)
		$random = New-Object System.Random
		[long]$done = 0

		try {
			$diskDrive = Get-CimInstance -ClassName "Win32_DiskDrive" -Filter "DeviceID LIKE '%PHYSICALDRIVE$Number'"
			$displayName = "$($diskDrive.Caption) [$(FormatBytes $diskDrive.Size)]"
			if (!($PSCmdlet.ShouldProcess($displayName, "override"))) {
				$done = $diskDrive.Size
				return
			}
			if (!($Force -or $PSCmdlet.ShouldContinue("Do you really want to override $($displayName)?", "Override?"))) {
				return
			}
			$stream = New-Object System.IO.FileStream("\\.\PHYSICALDRIVE$Number", [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None, $buffer.Length, [System.IO.FileOptions]::None)
			$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
			while ($true) {
				$random.NextBytes($buffer)
				$stream.Write($buffer, 0, $buffer.Length)
				$done += $buffer.Length
				[int]$percentComplete = [System.Math]::Round(100 * $done / $diskDrive.Size)
				$stopwatch.Stop()
				[long]$bytesPerSecond = $buffer.Length / $stopwatch.Elapsed.TotalSeconds
				$stopwatch.Restart()
				Write-Progress -Activity "Overriding $displayName" -Status "$(FormatBytes $done) written ($(FormatBytes $bytesPerSecond)/s)" -PercentComplete $percentComplete
			}
		}
		finally {
			if ($stream) {
				$stream.Dispose()
			}
			Write-Progress -Activity "Overriding $displayName" -Completed
			Write-Host "$(FormatBytes $done) written"
		}
	}
}
