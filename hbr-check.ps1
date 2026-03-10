<#
.SYNOPSIS
    Connects to a VMware vCenter Server and presents a diagnostic menu.

.DESCRIPTION
    This script checks for the VMware.PowerCLI module, installs it if necessary,
    and provides an interactive menu. The primary function currently is to connect 
    to a specified vCenter Server and verify ESXi hosts for HBR replication thumbprint errors.

.EXAMPLE
    .\hbr-check.ps1
    # Prompts for all inputs interactively and opens the menu.

.EXAMPLE
    .\hbr-check.ps1 -Server "vcenter.local" -Username "administrator@vsphere.local" -Password "Secret123!"
    # Pre-fills parameters, but still opens the menu awaiting your selection.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$Server = "",

    [Parameter(Mandatory = $false)]
    [string]$Username = "",

    [Parameter(Mandatory = $false)]
    [SecureString]$Password = $null
)

# Strict mode validation
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "Info")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if ($Level -eq "Warning") {
        Write-Warning "[$timestamp] [$Level] $Message"
    }
    else {
        Write-Output "[$timestamp] [$Level] $Message"
    }
}

function Invoke-HBRCheck {
    # Paths and Logging
    $ScriptDir = $PSScriptRoot
    if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = $PWD.Path }
    $logDir = Join-Path $ScriptDir "logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }
    $logFile = Join-Path $logDir "HBR_Check_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    
    $resultsDir = Join-Path $ScriptDir "results"
    if (-not (Test-Path $resultsDir)) {
        New-Item -ItemType Directory -Path $resultsDir | Out-Null
    }
    $csvFile = Join-Path $resultsDir "HBR_Check_Results_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    
    Start-Transcript -Path $logFile -Append -NoClobber | Out-Null
    
    try {
        Write-Log "Checking for required modules (VMware.PowerCLI, Posh-SSH)"
        
        # Check VMware.PowerCLI
        $hasPowerCLI = Get-Module -ListAvailable -Name "VMware.PowerCLI"
        if (-not $hasPowerCLI) {
            Write-Log "VMware.PowerCLI module is not installed." "Warning"
            Write-Log "Attempting to install VMware.PowerCLI from PSGallery for CurrentUser..."
            Install-Module -Name "VMware.PowerCLI" -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck
            Write-Log "PowerCLI installed successfully."
        }
    
        # Check Posh-SSH
        $hasPoshSSH = Get-Module -ListAvailable -Name "Posh-SSH"
        if (-not $hasPoshSSH) {
            Write-Log "Posh-SSH module is not installed." "Warning"
            Write-Log "Attempting to install Posh-SSH from PSGallery for CurrentUser..."
            Install-Module -Name "Posh-SSH" -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck
            Write-Log "Posh-SSH installed successfully."
        }
    
        Write-Log "Importing required modules"
        Import-Module VMware.PowerCLI
        Import-Module Posh-SSH
        
        # Ignore certificate warnings (common in vCenter homelab/internal environments) and disable CEIP
        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Scope Session -Confirm:$false | Out-Null
        Set-PowerCLIConfiguration -ParticipateInCEIP $false -Scope Session -Confirm:$false | Out-Null
    
        # Prompting logic for missing parameters (utilizing script scope to cache them for repeatability)
        if ($script:Server -eq "") {
            $script:Server = Read-Host -Prompt "Enter vCenter Server Name or IP"
        }
    
        if ($script:Username -eq "") {
            $script:Username = Read-Host -Prompt "Enter Username (e.g., administrator@vsphere.local)"
        }
    
        $securePassword = $null
        if ($null -eq $script:Password) {
            $securePassword = Read-Host -Prompt "Enter Password for $($script:Username)" -AsSecureString
        }
        else {
            $securePassword = $script:Password
        }
        
        # Ensure no stale vCenter connections exist before connecting
        $activeServers = Get-Variable -Name "DefaultVIServers" -Scope Global -ErrorAction SilentlyContinue
        if ($activeServers -and $activeServers.Value -and $activeServers.Value.Count -gt 0) {
            Write-Log "Disconnecting existing vCenter sessions..."
            Disconnect-VIServer * -Force -Confirm:$false | Out-Null
        }
        
        Write-Log "Connecting to vCenter Server: $($script:Server)..."
        
        # Build credentials
        $credential = New-Object System.Management.Automation.PSCredential($script:Username, $securePassword)
        
        # Connect
        $connection = Connect-VIServer -Server $script:Server -Credential $credential
        
        if ($connection) {
            # Store in variable first before interpolation, per skill guidelines
            $connectedServer = $connection.Name
            Write-Log "Successfully connected to vCenter: $connectedServer"
            
            Write-Log "=================================================="
            Write-Log "Starting ESXi HBR Thumbprint Verification"
            Write-Log "=================================================="
            
            Write-Log "Retrieving available clusters..."
            $allClusters = Get-Cluster
            
            if ($allClusters) {
                Write-Log "Prompting for cluster selection via Out-GridView"
                
                # Using Out-GridView with -OutputMode Multiple allows the user to select one or more
                $selectedClusters = $allClusters | Out-GridView -Title "Select one or more Clusters from $connectedServer" -OutputMode Multiple
                
                if ($selectedClusters) {
                    # Force into array to ensure Count works even with a single selection, adhering to skill instructions for array operations
                    $clusterArray = @($selectedClusters)
                    $clusterCount = $clusterArray.Count
                    
                    Write-Log "Selected $clusterCount cluster(s):"
                    foreach ($cluster in $clusterArray) {
                        $clusterName = $cluster.Name
                        Write-Log " - $clusterName"
                    }
                    
                    # Prompt for root password once
                    $rootPassword = Read-Host -Prompt "Enter Root Password for ESXi Hosts (Used for SSH)" -AsSecureString
                    $rootCred = New-Object System.Management.Automation.PSCredential("root", $rootPassword)
                    
                    Write-Log "Processing ESXi hosts in selected clusters..."
                    
                    # Initialize results array
                    $resultsArray = @()
                    
                    $totalProcessed = 0
                    $totalErrors = 0
                    
                    foreach ($cluster in $clusterArray) {
                        $hosts = Get-VMHost -Location $cluster
                        foreach ($vmhost in $hosts) {
                            $hostName = $vmhost.Name
                            Write-Log "Processing Host: $hostName"
                            
                            $totalProcessed++
                            $hasThumbprintError = $false
                            
                            try {
                                # 1. Enable SSH Service temporarily if it's not running
                                $sshService = Get-VMHostService -VMHost $vmhost | Where-Object { $_.Key -eq "TSM-SSH" }
                                $sshWasRunning = $sshService.Running
                                
                                if (-not $sshWasRunning) {
                                    Write-Log "Enabling SSH on $hostName"
                                    Start-VMHostService -HostService $sshService -Confirm:$false | Out-Null
                                }
    
                                # 2. Connect via SSH
                                Write-Log "Connecting via SSH to $hostName..."
                                # AcceptKey bypasses the strict host key checking prompt
                                $sshSession = New-SSHSession -ComputerName $hostName -Credential $rootCred -AcceptKey -Force -ErrorAction Stop
                                
                                if ($sshSession) {
                                    # 3. Run the exact command requested
                                    $command = 'cat /var/run/log/hbr-agent.log | grep -i "Thumbprint and certificate is not allowed to send replication data"'
                                    Write-Log "Executing grep on HBR log..."
                                    
                                    $sshResult = Invoke-SSHCommand -SSHSession $sshSession -Command $command
                                    
                                    if ($sshResult.Output) {
                                        Write-Log "MATCH FOUND on '$hostName':" "Warning"
                                        $hasThumbprintError = $true
                                        $totalErrors++
                                        # Output might be an array or string, so iterate to handle multiple matches gracefully
                                        foreach ($line in $sshResult.Output) {
                                            # Trim to avoid extra whitespace from ssh stdout
                                            $cleanLine = $line.Trim()
                                            if ($cleanLine) {
                                                Write-Log $cleanLine "Warning"
                                            }
                                        }
                                    }
                                    else {
                                        Write-Log "No matching errors found on $hostName."
                                    }
    
                                    # Ensure we close the session
                                    Remove-SSHSession -SSHSession $sshSession | Out-Null
                                }
                                
                                # 4. Restore SSH state
                                if (-not $sshWasRunning) {
                                    Write-Log "Disabling SSH on $hostName"
                                    Stop-VMHostService -HostService $sshService -Confirm:$false | Out-Null
                                }
                            }
                            catch {
                                Write-Log "Failed to process host $hostName`: $_" "Warning"
                            }
                            
                            # Store properties to array
                            $resultItem = [PSCustomObject]@{
                                Cluster          = $cluster.Name
                                Hostname         = $hostName
                                thumbprint_error = $hasThumbprintError
                            }
                            $resultsArray += $resultItem
                        }
                    }
                    
                    Write-Log "=================================================="
                    Write-Log "Execution Summary"
                    Write-Log "=================================================="
                    Write-Log "Processed Hosts : $($totalProcessed)"
                    Write-Log "Total Errors    : $($totalErrors)"
                    Write-Log "=================================================="
                    
                    # Display output and save CSV
                    Write-Log "Exporting results to $csvFile"
                    $resultsArray | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
                    Write-Log "Export completed successfully."
                    
                    Write-Log "Opening results in GridView for review..."
                    $resultsArray | Out-GridView -Title "HBR Check Results"
                    
                }
                else {
                    Write-Log "No clusters were selected. Process aborted." "Warning"
                    Write-Log "Disconnecting..."
                    Disconnect-VIServer -Server $connection -Confirm:$false | Out-Null
                    Stop-Transcript | Out-Null
                    return
                }
            }
            else {
                Write-Log "No clusters found in the connected vCenter." "Warning"
            }
            
            Write-Log "Disconnecting..."
            Disconnect-VIServer -Server $connection -Confirm:$false | Out-Null
        }
        else {
            Write-Log "Failed to connect to vCenter." "Warning"
            Stop-Transcript | Out-Null
            return
        }
    
        Write-Log "Log saved to: $logFile"
        Stop-Transcript | Out-Null
        return
    }
    catch {
        $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Warning "[$time] [Warning] Error: $_"
        Stop-Transcript | Out-Null
        return
    }
}

function Invoke-AppliancePairingExtraction {
    # Paths and Logging
    $ScriptDir = $PSScriptRoot
    if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = $PWD.Path }
    $logDir = Join-Path $ScriptDir "logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }
    $logFile = Join-Path $logDir "Appliance_Extraction_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    
    $hostInfoDir = Join-Path $ScriptDir "HostInfo"
    if (-not (Test-Path $hostInfoDir)) {
        New-Item -ItemType Directory -Path $hostInfoDir | Out-Null
    }
    
    Start-Transcript -Path $logFile -Append -NoClobber | Out-Null
    
    try {
        Write-Log "Checking for Posh-SSH module"
        $hasPoshSSH = Get-Module -ListAvailable -Name "Posh-SSH"
        if (-not $hasPoshSSH) {
            Write-Log "Posh-SSH module is not installed." "Warning"
            Write-Log "Attempting to install Posh-SSH from PSGallery for CurrentUser..."
            Install-Module -Name "Posh-SSH" -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck
            Write-Log "Posh-SSH installed successfully."
        }
        Import-Module Posh-SSH

        Write-Log "Prompting for Appliance details..."
        $applianceHost = Read-Host "Enter Replication Appliance Hostname or IP"
        
        $csvFile = Join-Path $hostInfoDir "$($applianceHost)_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        
        $adminUser = Read-Host "Enter Admin Username (default: root)"
        if ([string]::IsNullOrWhiteSpace($adminUser)) { $adminUser = "root" }
        $adminPass = Read-Host "Enter Password for $adminUser" -AsSecureString

        $cred = New-Object System.Management.Automation.PSCredential($adminUser, $adminPass)

        Write-Log "Connecting via SSH to appliance: $applianceHost..."
        $sshSession = New-SSHSession -ComputerName $applianceHost -Credential $cred -AcceptKey -Force -ErrorAction Stop

        if ($sshSession) {
            Write-Log "Successfully connected to appliance."
            
            Write-Log "Identifying primary database..."
            $dbIdentifyCmd = "/usr/bin/hbrsrv-bin --print-default-db"
            $dbResult = Invoke-SSHCommand -SSHSession $sshSession -Command $dbIdentifyCmd
            
            $dbPath = $null
            if ($dbResult.Output) {
                foreach ($line in $dbResult.Output) {
                    $cleanLine = $line.Trim()
                    # The path is usually /etc/vmware/hbrsrv.<id>.db
                    if ($cleanLine -match "/etc/vmware/.*\.db") {
                        $dbPath = $cleanLine
                        break
                    }
                }
            }

            if ($dbPath) {
                Write-Log "Primary database identified: $dbPath"
                
                Write-Log "Extracting HostInfo table to CSV format..."
                # Using sqlite3 .mode csv and .headers on to enforce standard CSV formatting on the raw output
                $sqlCmd = "echo -e '.mode csv\n.headers on\nselect * from HostInfo;' | sqlite3 $dbPath"
                
                $extractResult = Invoke-SSHCommand -SSHSession $sshSession -Command $sqlCmd
                
                if ($extractResult.Output) {
                    Write-Log "Saving extraction to $csvFile..."
                    # Removing empty lines and trimmimg spaces to avoid double-newline glitches from SSH standard out pipes
                    $cleanOutput = $extractResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() }
                    $cleanOutput | Out-File -FilePath $csvFile -Encoding UTF8
                    Write-Log "Extraction completed successfully."
                }
                else {
                    Write-Log "No output returned from SQL query." "Warning"
                }

            }
            else {
                Write-Log "Could not identify the primary database from output. Try running manually." "Warning"
            }

            Write-Log "Closing SSH session..."
            Remove-SSHSession -SSHSession $sshSession | Out-Null
        }
        else {
            Write-Log "Failed to connect to appliance." "Warning"
        }
    }
    catch {
        $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Warning "[$time] [Warning] Error: $_"
    }
    finally {
        Write-Log "Log saved to: $logFile"
        Stop-Transcript | Out-Null
    }
}

function Show-Menu {
    do {
        Clear-Host
        Write-Host "==================================================" -ForegroundColor Cyan
        Write-Host "              VMware Diagnostics Menu             " -ForegroundColor Cyan
        Write-Host "==================================================" -ForegroundColor Cyan
        Write-Host "1. Check hbr-agent thumbprint error"
        Write-Host "2. Extract pairing info from replication appliance"
        Write-Host "0. Exit"
        Write-Host "==================================================" -ForegroundColor Cyan
        
        $choice = Read-Host "Select an option"
        
        switch ($choice) {
            '1' {
                Invoke-HBRCheck
                Write-Host "`nPress Enter to return to the menu..."
                Read-Host | Out-Null
            }
            '2' {
                Invoke-AppliancePairingExtraction
                Write-Host "`nPress Enter to return to the menu..."
                Read-Host | Out-Null
            }
            '0' {
                Write-Host "Exiting script."
                exit 0
            }
            default {
                Write-Warning "Invalid selection. Please try again."
                Start-Sleep -Seconds 2
            }
        }
    } while ($true)
}

# Start execution
Show-Menu
