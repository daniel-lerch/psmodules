<#
.SYNOPSIS
    Tests a filter list against a specified DNS server and prints all domains which have been successfully resolved (not blocked)
.PARAMETER Path
    Path to a plain text file with all domains to test (empty lines are ignored)
.PARAMETER DnsFilter
    The DNS server to use with preconfigured IP address and blocking page settings
.PARAMETER Count
    The number of domains to check
.PARAMETER Skip
    The number of domains to skip
.PARAMETER HtmlFile
    The path to write an HTML file to for easier opening in the browser
#>
function Test-DnsFilter {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,
        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateSet("CleanBrowsing", "OpenDns", "JusProgDns", "Cloudflare", "Google")]
        [string]$DnsFilter,
        [Parameter(Mandatory = $false)]
        [int]$Count = 5000,
        [Parameter(Mandatory = $false)]
        [int]$Skip = 0,
        [Parameter(Mandatory = $false)]
        [string]$HtmlFile
    )
    
    begin {
        <#
        Clean Browsing Adult Filter
        Server: 185.228.168.10, 185.228.169.11
        Blocking page: NX_DOMAIN
    
        OpenDNS Family Shield
        Server: 208.67.222.123, 208.67.220.123
        Blocking page: 146.112.61.106
    
        JusProgDns
        Server: 109.235.61.210, 194.97.50.6
        Blocking page: 109.235.61.210, 194.97.50.6, NX_DOMAIN
    
        Cloudflare DNS
        Server: 1.1.1.1, 1.0.0.1
        Blocking page: None
        
        Google DNS
        Server: 8.8.8.8, 8.8.4.4
        Blocking page: None
        #>
        switch ($DnsFilter) {
            "CleanBrowsing" {
                $DnsServer = "185.228.168.10"
            }
            "OpenDns" {
                $DnsServer = "208.67.222.123"
                $BlockingPage = "146.112.61.106"
            }
            "JusProgDns" {
                $DnsServer = "109.235.61.210"
                $BlockingPage = "109.235.61.210"
            }
            "Cloudflare" {
                $DnsServer = "1.1.1.1"
            }
            "Google" {
                $DnsServer = "8.8.8.8"
            }
            Default {
                Write-Error "Internal error: Parameter validation does not match parameter handling"
            }
        }
        if ($HtmlFile) {
            Write-Output "<html><head></head><body>" | Out-File -FilePath $HtmlFile
        }
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $processed = 0
        $resolved = 0
    }
    
    process {
        if ($BlockingPage) {
            Write-Host "Using DNS server $DnsServer with blocking page $BlockingPage"
        }
        else {
            Write-Host "Using DNS server $DnsServer without a blocking page"
        }
    
        Get-Content -Path $Path | Select-Object -First $Count -Skip $Skip | ForEach-Object {
            if ($_) {
                [Microsoft.DnsClient.Commands.DnsRecord[]]$dnsEntry = Resolve-DnsName -Name $_ -Type A -Server $DnsServer -ErrorAction SilentlyContinue
                [Microsoft.DnsClient.Commands.DnsRecord_A[]]$aRecord = $dnsEntry -as [Microsoft.DnsClient.Commands.DnsRecord_A[]]
                if ($null -ne $dnsEntry -and $null -eq $aRecord) {
                    Write-Warning "Unexpected record type for $_"
                    if ($HtmlFile) {
                        Write-Output "<p><a href=`"http://$_`">$_</a></p>" | Out-File -FilePath $HtmlFile -Append
                    }
                    $resolved++
                }
                # We consider a domain to be blocked if the DNS Server does not return a record
                elseif (($aRecord.Length -gt 0) -and ($aRecord[0].IP4Address -ne $BlockingPage)) {
                    Write-Output "$_"
                    if ($HtmlFile) {
                        Write-Output "<p><a href=`"http://$_`">$_</a></p>" | Out-File -FilePath $HtmlFile -Append
                    }
                    $resolved++
                }
                $processed++
                Write-Progress -Activity "Resolving domains" -Status "Processed $processed / $Count. Elapsed time $($stopwatch.Elapsed.ToString())" -PercentComplete ([Math]::Round(100 * $processed / $Count))
                Start-Sleep -Milliseconds 125
            }
            else {
                Write-Output
            }
        }
    }
    
    end {
        if ($HtmlFile) {
            Write-Output "</body></html>" | Out-File -FilePath $HtmlFile -Append
        }
        Write-Progress -Activity "Resolving domains" -Completed
        Write-Host "Processed $processed domains in $($stopwatch.Elapsed.ToString()). Resolved $resolved ($([Math]::Round(100 * $resolved / $processed))%)."
    }    
}
