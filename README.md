*Read this in other languages: [English](README.md), [Português](README.pt-BR.md).*

# ESXi & HBR Appliance Diagnostics

A comprehensive PowerShell diagnostic toolkit for VMware environments. This interactive script provides automated capabilities to connect to vCenter Servers, inspect ESXi hosts for Host-Based Replication (HBR) thumbprint errors, extract internal pairing data directly from HBR appliances, and systematically compare databases across datacenters for replication discrepancies.

## Features

An interactive UI menu (`Show-Menu`) wraps three distinct diagnostic modules:

### 1. Check hbr-agent thumbprint error
- **Automated Logging:** Connects to a target vCenter (while securely bypassing invalid SSLs).
- **Cluster Selection:** Displays an interactive `Out-GridView` to let users choose one or multiple clusters.
- **SSH Automation:** Interrogates each ESXi host in the target cluster, dynamically enabling `TSM-SSH` (if disabled), establishing an SSH tunnel using the provided Host root password, and parsing `/var/run/log/hbr-agent.log`.
- **Validation:** Specifically flags hosts returning `Thumbprint and certificate is not allowed to send replication data`.
- **Reporting:** Safely shuts down the SSH connections and generates discrete timestamped CSVs mapping the boolean failure status for each node.

### 2. Extract pairing info from replication appliance
- **Direct Appliance Access:** Connects directly into a VMware Replication Appliance via SSH.
- **DB Discovery:** Automatically executes `/usr/bin/hbrsrv-bin --print-default-db` to dynamically locate the primary internal database map.
- **SQL Extraction:** Formats and executes an internal `sqlite3` query (`select * from HostInfo`) via the pipeline, dumping the target appliance's internal host registration array seamlessly into an automated CSV inside the `/HostInfo/` directory.

### 3. Compare hostInfo between appliance replications
- **Data Cross-referencing:** Selects an exported Source `HostInfo` CSV and a Destination `HostInfo` CSV.
- **UUID Mapping:** Leverages a local `pairings.csv` mapping file to identify the remote datacenter target UUID.
- **Array Checking:** Automates a `Compare-Object` pipeline filtering Local hosts (sans UUID) from the Source DB against matching Remote Hosts (UUID filtered) on the Destination DB. 
- **Directional Check:** Allows users to interactively choose between Bi-directional (mapping gaps on both sides) or Unidirectional (Source hosts missing on the Destination appliance) mapping.
- **Output:** Highlights all orphan/missing hosts inside a graphical `Out-GridView` and a `/results/` CSV dump.

---

## Directory Structure

```text
esxi-hbr-check/
├── hbr-check.ps1     # Core interactive execution script
├── pairings.csv      # Local reference map for Remote Datacenter UUIDs
├── logs/             # Gitignored transcript logic files
├── HostInfo/         # Gitignored outputs of HBR Appliance DB extracts (Option 2)
├── results/          # Gitignored export CSVs (Option 1 & 3 logic)
└── .gitignore        # Explicit execution block filtering
```

## Prerequisites

- **PowerShell 5.1+** (Windows environment highly recommended for `Out-GridView` visual pipeline).
- Target **vCenter** Administrator credentials.
- **ESXi** `root` credentials (for Host level SSH in Option 1).
- **HBR Appliance** admin credentials (for Option 2 SQLite access).
- Populated `pairings.csv` with a `name,pairing_id` header block.

The script relies on `VMware.PowerCLI` and `Posh-SSH`. It will actively scan and attempt to automatically install them via `Install-Module` into the `CurrentUser` scope upon invocation if they are not already present.

---

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/9llo/hbr-check.git
cd hbr-check
```

### 2. Populate Pairings (If utilizing Option 3)
Ensure `pairings.csv` exists in the local directory following this layout:
```csv
name,pairing_id
SiteB-DR,7f73033e-4578-45e6-9274-582b421c5413
SiteC-DR,bb1641ce-741f-4348-b8cc-ce960c0bb8ca
```

### 3. Execution

Execute the script via your preferred PowerShell terminal. The script operates within an interactive loop, allowing sequential diagnostic testing.

```powershell
.\hbr-check.ps1
```

If utilizing Option 1 natively, you can bypass the interactive credential prompts directly:
```powershell
.\hbr-check.ps1 -Server "vcenter.local" -Username "administrator@vsphere.local" -Password "YourSecretPassword"
```
