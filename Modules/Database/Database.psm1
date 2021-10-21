$mysqlName = "MySQL"
$mariadbName = "MariaDB"
$installPath = Join-Path $env:LOCALAPPDATA "Programs"

function Install-DbServer {
	[CmdletBinding()]
	param(
		[Parameter()]
		[switch]$MySQL,
		[Parameter()]
		[switch]$MariaDB
	)

	# We require mirrors to support HTTPS
	$mysqlMirror = "https://downloads.mysql.com/archives/get/p/23/file/mysql-5.7.35-winx64.zip"
	$mysqlSize = "370 MB"
	$mariadbMirror = "https://downloads.mariadb.org/rest-api/mariadb/10.6.4/mariadb-10.6.4-winx64.zip"
	$mariadbSize = "71 MB"

	function InstallDbServer ($Mirror, $Size, $Name) {
		$guid = [System.Guid]::NewGuid().ToString()
		$tempPath = Join-Path $env:TEMP $guid
		$downloadPath = Join-Path $env:TEMP ($guid + ".zip")
		$versionPath = Join-Path $installPath $Name

		$message = "Download and install?"
		$question = "The download size is $Size. Do you want to proceed?"
		$choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
		$choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList "&Yes"))
		$choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList "&No"))
		
		$decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
		if ($decision -eq 1) {
			return
		}
			
		Write-Host "Downloading archive..."
		Start-BitsTransfer -Source $Mirror -Destination $downloadPath -ErrorAction Stop
		Write-Host "Unpacking archive..."
		Expand-Archive -Path $downloadPath -DestinationPath $tempPath
		$innerTempFolder = Get-ChildItem -Path $tempPath -Directory
		if (Test-Path -Path $versionPath) {
			if (Test-Path -Path (Join-Path $versionPath "data")) {
				Write-Host "Migrating data..."
				Move-Item -Path (Join-Path $versionPath "data") -Destination $innerTempFolder.FullName
			}
			Write-Host "Removing old files..."
			Remove-Item -Path $versionPath -Recurse
		}
		Move-Item -Path $innerTempFolder.FullName -Destination $versionPath -Force

		Write-Host "Cleaning up..."
		# Continue silenty in order not rely on temporary files still being in place
		Remove-Item -Path $downloadPath -ErrorAction SilentlyContinue
		Remove-Item -Path $tempPath -ErrorAction SilentlyContinue
	}

	function PurgeDbServer ($Path) {
		if (Test-Path -Path $Path -PathType Container) {
			$message = "Remove old database server?"
			$question = "An outdated database server was found at $Path. Do you want to remove it?"
			$choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
			$choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList "&Yes"))
			$choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList "&No"))
			
			$decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
			if ($decision -eq 0) {
				Remove-Item -Path $Path -Recurse
			}
		}
	}

	function PurgeEmptyFolder ($Path) {
		$info = (Get-Item -Path $Path -ErrorAction SilentlyContinue)
		if ($info.Exists -and $info.GetFiles().Count -eq 0) {
			Remove-Item -Path $Path -Recurse
		}
	}

	$mysqlInstalled = Test-Path -Path (Join-Path $installPath $mysqlName)
	$mariadbInstalled = Test-Path -Path (Join-Path $installPath $mariadbName)
	Write-Host "Installed database servers:"
	if ($mysqlInstalled) {
		Write-Host "MySQL:    $mysqlName"
	}
	else {
		Write-Host "MySQL:    ---"
	}
	if ($mariadbInstalled) {
		Write-Host "MariaDB:  $mariadbName"
	}
	else {
		Write-Host "MariaDB:  ---"
	}
	Write-Host ""
	Write-Host "Already installed versions will be overridden"
	Write-Host ""

	if ($MySQL) {
		InstallDbServer -Mirror $mysqlMirror -Size $mysqlSize -Name $mysqlName
	}
	if ($MariaDB) {
		InstallDbServer -Mirror $mariadbMirror -Size $mariadbSize -Name $mariadbName
	}

	PurgeDbServer (Join-Path $env:LOCALAPPDATA MariaDB)
	PurgeDbServer (Join-Path $env:LOCALAPPDATA "Programs" "Database Servers" "mysql-5.7.30-winx64")
	PurgeDbServer (Join-Path $env:LOCALAPPDATA "Programs" "Database Servers" "mariadb-10.5.5-winx64")
	PurgeEmptyFolder (Join-Path $env:LOCALAPPDATA "Programs" "Database Servers")
}

function Start-DbServer {
	[CmdletBinding()]
	param(
		[Parameter()]
		[switch]$MySQL,
		[Parameter()]
		[switch]$MariaDB
	)

	if (($MySQL -and $MariaDB) -or (-not $MySQL -and -not $MariaDB)) {
		Write-Host "Decide for one database server to start!"
		return
	}
	if (Get-Process -Name "mysqld" -ErrorAction SilentlyContinue) {
		Write-Host "A MySQL/MariaDB server is already running on this system."
		return
	}

	if ($MySQL) {
		$serverPath = Join-Path (Join-Path (Join-Path $installPath $mysqlName) "bin") "mysqld.exe"
		if (Test-Path -Path $serverPath -PathType Leaf) {
			$firstRun = !(Test-Path -Path (Join-Path (Join-Path $installPath $mysqlName) "data") -PathType Container)
			if ($firstRun) {
				Start-Process -FilePath $serverPath -ArgumentList `
					"--console", "--skip-log-syslog", "--explicit-defaults-for-timestamp", `
					"--initialize-insecure" -Wait
			}
			Start-Process -FilePath $serverPath -ArgumentList `
				"--console", "--skip-log-syslog", "--explicit-defaults-for-timestamp", "--transaction-isolation=READ-COMMITTED"
			if ($firstRun) {
				$execPath = GetPathWhenRunning -Name "mysqladmin.exe"
				if ($execPath) {
					Start-Process -FilePath $execPath -ArgumentList "-uroot", "password root"
				}
			}
		}
		else {
			Write-Host "MySQL was not found at $serverPath"
		}
	}

	if ($MariaDB) {
		$binPath = Join-Path (Join-Path $installPath $mariadbName) "bin"
		$serverPath = Join-Path $binPath "mysqld.exe"
		$initPath = Join-Path $binPath "mysql_install_db.exe"
		if ((Test-Path -Path $serverPath -PathType Leaf) -and (Test-Path -Path $initPath -PathType Leaf)) {
			if (!(Test-Path -Path (Join-Path (Join-Path (Join-Path $installPath $mariadbName) "data") "my.ini") -PathType Leaf)) {
				Start-Process -FilePath $initPath -ArgumentList `
					"--password=root" -Wait
			}
			Start-Process -FilePath $serverPath -ArgumentList `
				"--console", "--transaction-isolation=READ-COMMITTED"
		}
		else {
			Write-Host "MariaDB was not found $serverPath"
		}
	}
}

function Stop-DbServer {
	$execPath = GetPathWhenRunning -Name "mysqladmin.exe"
	if ($execPath) {
		Start-Process -FilePath $execPath -ArgumentList "-uroot", "-proot", "shutdown"
	}
}

function Start-DbCli {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false, Position = 0)]
		[string]$Database
	)
	$execPath = GetPathWhenRunning -Name "mysql.exe"
	if ($execPath) {
		if (-not [string]::IsNullOrWhiteSpace($Database)) {
			$Database = " $Database"
		}
		Start-Process -FilePath "cmd.exe" -ArgumentList "/c ""$execPath"" -uroot -proot$Database" -WindowStyle Normal
	}
}

function GetPathWhenRunning ($Name) {
	$process = Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
	if ($process) {
		$binPath = Split-Path -Path $process.Path -Parent
		$execPath = Join-Path $binPath $Name
		if (Test-Path -Path $execPath -PathType Leaf) {
			return $execPath
		}
		else {
			"Could not find executable at $execPath"
		}
	}
	else {
		Write-Host "No MySQL/MariaDB server is currently running on this system."
	}
}

Export-ModuleMember -Function Install-DbServer
Export-ModuleMember -Function Start-DbServer
Export-ModuleMember -Function Stop-DbServer
Export-ModuleMember -Function Start-DbCli
