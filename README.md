*Read this in other languages: [English](README.md), [Português](README.pt-BR.md).*

# ESXi HBR Check

## Key Features

- **Automated Dependency Checks**: Verifies and silently installs the necessary `VMware.PowerCLI` and `Posh-SSH` modules.
- **Interactive Cluster Selection**: Prompts an interactive `Out-GridView` to let users quickly choose single or multiple target clusters from the vCenter.
- **SSH Automation**: Dynamically establishes and closes SSH interfaces to each target ESXi Host after bypassing strict checks using the ESXi root password.
- **Log Aggregation**: Reads `/var/run/log/hbr-agent.log`, searches for `Thumbprint and certificate is not allowed to send replication data`, cleanses output spaces, and consolidates the occurrences.
- **Export & Auditing**:
  - `logs/..`: Emits an ongoing execution transcript locally to timestamped log files.
  - `results/..`: Saves the aggregated validation mapping boolean results explicitly into CSVs for external reporting.

---

## Prerequisites

- **PowerShell 5.1+** (Windows environment recommended, given the reliance on `Out-GridView` and default PSGallery availability).
- **Credentials**: Administrator-level authentication string for the target `vCenter` and the unified `root` password applying towards the respective ESXi Hosts in its clusters.

---

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/9llo/hbr-check.git
cd hbr-check
```

### 2. Execution

You can run the script via PowerShell directly and it will interactively prompt you for missing arguments (`Server`, `Username`, `Password`, ESXi `Root Password`):

```powershell
.\hbr-check.ps1
```

If you wish to pass parameters implicitly to bypass early stage dialogue prompts:

```powershell
.\hbr-check.ps1 -Server "vcenter.local" -Username "administrator@vsphere.local" -Password "YourSecretPassword"
```

*Note: The script establishes security overrides dynamically to ignore invalid SSL certificates from vCenter internally using `Set-PowerCLIConfiguration`.*

### 3. Review Results

The execution concludes with an overall execution summary bridging the terminal process footprint (`Processed Hosts`, `Total Errors`).

Upon completion, results map to isolated directory trees:
- Detailed `.log` files will populate automatically in `.\logs\`.
- Parsed cluster and error matching lists can be found explicitly in `.\results\` saved as `.csv`.

---

## Directory Structure

```text
esxi-hbr-check/
├── hbr-check.ps1     # Core execution script
├── logs/             # Gitignored transcript files (Generated dynamically)
├── results/          # Gitignored export CSVs (Generated dynamically)
└── .gitignore        # Explicit exclusion filtering
```
