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

<#
.SYNOPSIS
	Deletes corrupted media files
.PARAMETER Path
	The folder to recursively process deleting all corrupted files
.PARAMETER RemoveWithoutExtension
	Treats files without extension as corrupted and deletes them
.NOTES
	This modules bundles TagLibSharp 2.2.0 for netstandard2.0
#>
function Remove-CorruptedFiles {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, Position = 1)]
		[string]$Path,
		[switch]$RemoveWithoutExtension
	)
	
	begin {
		Add-Type -Path (Join-Path $PSScriptRoot "TagLibSharp.dll")
		$supportedExtensions = 
		<# video #> "mkv","ogv","avi","wmv","asf","mp4","m4p","m4v","mpeg","mpg","mpe","mpv","mpg","m2v",
		<# audio #> "aa","aax","aac","aiff","ape","dsf","flac","m4a","m4b","m4p","mp3","mpc","mpp","ogg","oga","wav","wma","wv","webm",
		<# images #> "bmp","gif","jpg","jpeg","pbm","pgm","ppm","pnm","pcx","png","tiff","dng","svg"

		function UpdateState ($State) {
			Write-Progress -Activity "Validating files" -Status "Intact: $($State.Intact) Corrupted: $($State.Corrupted) Skipped: $($State.Skipped) Empty: $($State.Empty)/$($State.Folders)"
		}

		function ProcessFolderRecursive ($State, $Options, [System.IO.DirectoryInfo]$Directory) {
			$children = 0
			$State.Folders++

			foreach ($folder in $Directory.EnumerateDirectories()) {
				if (ProcessFolderRecursive $State $Options $folder) {
					$children++
				}
			}

			foreach ($file in $Directory.EnumerateFiles()) {
				if ($Options.RemoveWithoutExtension -and [String]::IsNullOrEmpty($file.Extension)) {
					$file.Delete()
					$State.Corrupted++
				} elseif ($file.Extension.StartsWith(".") -and $supportedExtensions.Contains($file.Extension.Substring(1).ToLower())) {
					try {
						$mediaFile = [TagLib.File]::Create($file.FullName)
						$children++
						$State.Intact++
					}
					catch [TagLib.CorruptFileException] {
						$file.Delete()
						$State.Corrupted++
					}
					finally {
						if ($null -ne $mediaFile) {
							$mediaFile.Dispose()
						}
					}
				} else {
					$children++
					$State.Skipped++
				}
				UpdateState $State
			}

			if ($children -gt 0) {
				return $true
			} else {
				$Directory.Delete()
				$State.Empty++
				UpdateState $State
				return $false
			}
		}
	}
	
	process {
		$directory = New-Object System.IO.DirectoryInfo (Resolve-Path -Path $Path).Path
		$state = [PSCustomObject]@{
			Intact = 0
			Corrupted = 0
			Skipped = 0
			Empty = 0
			Folders = 0
		}
		$options = [PSCustomObject]@{
			RemoveWithoutExtension = $RemoveWithoutExtension
		}

		$null = ProcessFolderRecursive $state $options $directory

		Write-Progress -Activity "Validating files" -Completed

		Write-Host "Summary"
		Write-Host "	Intact: $($state.Intact)"
		Write-Host "	Corrupted: $($state.Corrupted)"
		Write-Host "	Skipped: $($state.Skipped)"
		Write-Host "	Empty: $($state.Empty)/$($state.Folders)"
	}
}
