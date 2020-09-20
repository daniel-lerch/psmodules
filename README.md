# PSModules

This repository contains a bundle of PowerShell modules useful for developers.  
Run `install.ps1` with PowerShell 7+ to copy all modules to your local modules folder.

## Modules

### Database
This module was initially developed for [Skynet](https://github.com/skynet-im/skynet-server) but has been useful for many different projects.

Functions
- `Install-DbServer [-MySQL] [-MariaDB]`
- `Start-DbServer [-MySQL] [-MariaDB]`
- `Stop-DbServer`
- `Start-DbCli [-Database <database name>]`

Database Server are installed to `%LOCALAPPDATA%\Programs\Database Servers\`.

### Storage
This module was developed for power users who are missing some GNU core utils on their Windows system.

Functions
- `Clear-PhysicalDrive -Number <drive number>` (requires elevated permissions)
