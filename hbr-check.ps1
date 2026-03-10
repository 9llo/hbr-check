<#
.SYNOPSIS
    Connects to a VMware vCenter Server.

.DESCRIPTION
    This script checks for the VMware.PowerCLI module, installs it if necessary,
    and connects to a specified vCenter Server using provided or prompted credentials.

.EXAMPLE
    .\hbr-check.ps1
    # Prompts for all inputs interactively.

.EXAMPLE
    .\hbr-check.ps1 -Server "vcenter.local" -Username "administrator@vsphere.local" -Password "Secret123!"
    # Connects using provided parameters without prompting.
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

# Paths and Logging
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptDir) { $ScriptDir = $PWD.Path }
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

    # Prompting logic for missing parameters
    if ($Server -eq "") {
        $Server = Read-Host -Prompt "Enter vCenter Server Name or IP"
    }

    if ($Username -eq "") {
        $Username = Read-Host -Prompt "Enter Username (e.g., administrator@vsphere.local)"
    }

    $securePassword = $null
    if ($null -eq $Password) {
        $securePassword = Read-Host -Prompt "Enter Password for $Username" -AsSecureString
    }
    else {
        $securePassword = $Password
    }
    
    # Ensure no stale vCenter connections exist before connecting
    $activeServers = Get-Variable -Name "DefaultVIServers" -Scope Global -ErrorAction SilentlyContinue
    if ($activeServers -and $activeServers.Value -and $activeServers.Value.Count -gt 0) {
        Write-Log "Disconnecting existing vCenter sessions..."
        Disconnect-VIServer * -Force -Confirm:$false | Out-Null
    }
    
    Write-Log "Connecting to vCenter Server: $Server..."
    
    # Build credentials
    $credential = New-Object System.Management.Automation.PSCredential($Username, $securePassword)
    
    # Connect
    $connection = Connect-VIServer -Server $Server -Credential $credential
    
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
                exit 0
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
        exit 1
    }

    Write-Log "Log saved to: $logFile"
    exit 0
}
catch {
    $time = Get-Date -Format "HH:mm:ss"
    Write-Warning "[$time] [!] Error: $_"
    exit 1
}
