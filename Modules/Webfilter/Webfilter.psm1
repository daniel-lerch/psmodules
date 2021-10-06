<#
.SYNOPSIS
    Tests a filter list against a specified DNS server and prints all domains which have been successfully resolved (not blocked)
.PARAMETER Domains
    A list of domains to deduplicate, sort and test
.PARAMETER DnsFilter
    The DNS server to use with preconfigured IP address and blocking page settings
.PARAMETER HtmlFile
    The path to write an HTML file to for easier opening in the browser
.EXAMPLE
    Test-DnsFilter -Domains "forbidden.com","blocked.com","dangerous.com" -DnsFilter OpenDns

    Check a list of domains which are not blocked by the specified server.
.EXAMPLE
    "forbidden.com","blocked.com","dangerous.com" | Test-DnsFilter OpenDns

    Pipe a list of domains to check which are not blocked by the specified server.
.EXAMPLE
    gc .\adultcontent.txt | Test-DnsFilter JusProgDns | tee .\reachable.txt

    Pipe an entire file to check which domains are not blocked by the specified server.
    Reachable domains are written to a text file and printed to the console.
.EXAMPLE
    gc .\block.txt | select -skip 1000 -first 1000 | Test-DnsFilter Cleanbrowsing

    Pipe a huge blocking file through a filter to take lines 1000-1999 (both inclusive)
    and check which of these domains are not blocked by the specified server. 
#>
function Test-DnsFilter {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$Domains,
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet("CleanBrowsing", "OpenDns", "JusProgDns", "Cloudflare", "Google")]
        [string]$DnsFilter
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

        if ($BlockingPage) {
            Write-Host "Using DNS server $DnsServer with blocking page $BlockingPage"
        }
        else {
            Write-Host "Using DNS server $DnsServer without a blocking page"
        }

        $set = New-Object System.Collections.Generic.HashSet[string]
        $inputCount = 0
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $processed = 0
        $resolved = 0
    }
    
    process {
        $Domains | ForEach-Object {
            if ($_) {
                $set.Add($_) | Out-Null
                $inputCount++
            }
        }
    }
    
    end {
        Write-Host "Found $($set.Count) unique entries skipping $($inputCount - $set.Count) duplicates"

        if (0 -eq $set.Count) {
            return
        }

        $set | Sort-Object | ForEach-Object {
            [Microsoft.DnsClient.Commands.DnsRecord[]]$dnsEntry = Resolve-DnsName -Name $_ -Type A -Server $DnsServer -ErrorAction SilentlyContinue
            [Microsoft.DnsClient.Commands.DnsRecord_A[]]$aRecord = $dnsEntry -as [Microsoft.DnsClient.Commands.DnsRecord_A[]]
            if ($null -ne $dnsEntry -and $null -eq $aRecord) {
                Write-Output "Unexpected record type for $_"
                $resolved++
            }
            # We consider a domain to be blocked if the DNS Server does not return a record
            elseif (($aRecord.Length -gt 0) -and ($aRecord[0].IP4Address -ne $BlockingPage)) {
                Write-Output $_
                $resolved++
            }
            $processed++
            Write-Progress -Activity "Resolving domains" -Status "Processed $processed / $($set.Count). Elapsed time $($stopwatch.Elapsed.ToString())" -PercentComplete ([Math]::Round(100 * $processed / $set.Count))
            Start-Sleep -Milliseconds 125
        }

        Write-Progress -Activity "Resolving domains" -Completed
        Write-Host "Processed $processed domains in $($stopwatch.Elapsed.ToString()). Resolved $resolved ($([Math]::Round(100 * $resolved / $processed))%)."
    }  
}
