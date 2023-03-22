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
			Write-Progress -Activity "Overriding $displayName" -Status "Removing volume..." -PercentComplete 0
			Clear-Disk -Number $Number -RemoveData -RemoveOEM -Confirm:$false -ErrorAction SilentlyContinue
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
	Deletes duplicate files that exist in reference path
.PARAMETER ReferencePath
	The main folder to keep. This should usually be a more recent version than ShrinkingPath
.PARAMETER ShrinkingPath
	The folder to delete files from that also exist in ReferecePath
.NOTES
	This commands compares files based on file name and SHA-256 hash. Duplicate files are only deleted if both are identical.
#>
function Remove-DuplicateFiles {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$ReferencePath,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$ShrinkingPath
    )

    begin {
        function SHA256 ([System.IO.Stream]$Stream, [bool]$Close) {
            $algorithm = [System.Security.Cryptography.SHA256]::Create()
            $hash = $algorithm.ComputeHash($Stream)
            $algorithm.Dispose()
            if ($Close) { 
                $Stream.Dispose()
            }
            return $hash
        }

        function MergeFolderRecursive ($State, [System.IO.DirectoryInfo]$WorkingDirectory) {
            $children = 0
            foreach ($folder in $WorkingDirectory.EnumerateDirectories()) {
                if (MergeFolderRecursive $State $folder) {
                    $children++
                }
            }
            foreach ($file in $WorkingDirectory.EnumerateFiles()) {
                $relativePath = $file.FullName.Substring($State.Shrinking.FullName.Length + 1) # Remove backslash
                $referenceFile = New-Object System.IO.FileInfo(Join-Path $State.Reference.FullName $relativePath)
                if ($referenceFile.Exists) {
                    $shrHash = SHA256 -Stream $file.OpenRead() -Close $true
                    $refHash = SHA256 -Stream $referenceFile.OpenRead() -Close $true
                    if (Compare-Object $refHash $shrHash) {
                        Write-Host "[Different] $relativePath exists in both directories with different binary content" -ForegroundColor Yellow
                        $children++
                        $State.Different++
                    } elseif ($file.FullName -eq $referenceFile.FullName) {
                        Write-Host "[Identical] $relativePath is the same file in both directories"
                        $children++
                        $State.Identical++
                    } else {
                        Write-Host "[Identical] $relativePath exists in both directories with identical binary content"
                        $file.Delete()
                        $State.Identical++
                    }
                } else {
                    $children++
                    $State.Additional++
                }
            }
            if ($children -gt 0) {
                return $true
            } else {
                Write-Host "[Empty] $relativePath does not contain files anymore"
                $WorkingDirectory.Delete()
                $State.Empty++
                return $false
            }
        }       
    }

    process {
        Write-Host "Deleting duplicate files in $ShrinkingPath which exist in $ReferencePath"

        $state = [PSCustomObject]@{
            Reference = New-Object System.IO.DirectoryInfo((Resolve-Path -Path $ReferencePath).Path.TrimEnd("\"))
            Shrinking = New-Object System.IO.DirectoryInfo((Resolve-Path -Path $ShrinkingPath).Path.TrimEnd("\"))
            Different = 0
            Identical = 0
            Additional = 0
            Empty = 0
        }
        MergeFolderRecursive $state $state.Shrinking | Out-Null
    
        Write-Host $state -ForegroundColor Green
    }
}

<#
.SYNOPSIS
	Deletes corrupted media files
.PARAMETER Path
	The folder to recursively process deleting all corrupted files
.PARAMETER RemoveWithoutExtension
	Treats files without extension as corrupted and deletes them
.PARAMETER RemoveExtensions
	Treats files with these extensions as corrupted and deletes them
	Use the lowercase value without a leading dot
.NOTES
	This modules bundles TagLibSharp 2.2.0 for netstandard2.0
#>
function Remove-CorruptedFiles {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, Position = 1)]
		[string]$Path,
		[switch]$RemoveWithoutExtension,
		[string[]]$RemoveExtensions
	)
	
	begin {
		Add-Type -Path (Join-Path $PSScriptRoot "TagLibSharp.dll")
		$supportedExtensions = 
		<# video #> "mkv","ogv","avi","wmv","asf","mp4","m4p","m4v","mpeg","mpg","mpe","mpv","mpg","m2v",
		<# audio #> "aa","aax","aac","aiff","ape","dsf","flac","m4a","m4b","m4p","mp3","mpc","mpp","ogg","oga","wav","wma","wv","webm",
		<# images #> "bmp","gif","jpg","jpeg","pbm","pgm","ppm","pnm","pcx","png","tiff","dng","svg"

		function UpdateState ($State) {
			Write-Progress -Activity "Validating files" -Status "Intact: $($State.Intact) Corrupted: $($State.Corrupted) Skipped: $($State.Skipped) Trash: $($State.Trash) Empty: $($State.Empty)/$($State.Folders)"
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
					$State.Trash++
				} elseif ($file.Extension.StartsWith(".") -and $options.RemoveExtensions.Contains($file.Extension.Substring(1).ToLower())) {
					$file.Delete()
					$State.Trash++
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
					# Skip files that are not supported by TagLibSharp
					catch [TagLib.UnsupportedFormatException] {
						$children++
						$State.Skipped++
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
			Trash = 0
			Empty = 0
			Folders = 0
		}
		$options = [PSCustomObject]@{
			RemoveWithoutExtension = $RemoveWithoutExtension
#			RemoveExtensions = $RemoveExtensions ?? [string[]]@() # Introduced in PowerShell 7.0
			RemoveExtensions = If ($RemoveExtensions) { $RemoveExtensions } else { [string[]]@() }
}

		$null = ProcessFolderRecursive $state $options $directory

		Write-Progress -Activity "Validating files" -Completed

		Write-Host "Summary"
		Write-Host "	Intact: $($state.Intact)"
		Write-Host "	Corrupted: $($state.Corrupted)"
		Write-Host "	Skipped: $($state.Skipped)"
		Write-Host "	Trash: $($state.Trash)"
		Write-Host "	Empty: $($state.Empty)/$($state.Folders)"
	}
}
