# Universal ionCube Loader Installer

**A Bash-based automation tool for installing and managing ionCube PHP Loaders across multiple Linux hosting environments.**

**Version:** `2.0.3`  
**Language:** Bash  
**Platform:** Linux  
**Project Status:** Under validation

---

## Overview

Managing ionCube Loader across multiple PHP versions and hosting environments can be challenging, especially on servers running cPanel, CloudLinux, EasyApache 4, and different PHP execution handlers.

Control panels usually provide their own PHP extension management mechanisms. However, administrators sometimes need more flexibility than the versions and configurations available through their control panel repositories.

**Universal ionCube Loader Installer** provides an interactive and command-line workflow for discovering PHP installations, selecting ionCube Loader versions, validating compatibility, modifying PHP configurations, and recovering from configuration changes.

The project is designed to simplify manual ionCube management across different Linux hosting environments while reducing the risks associated with direct configuration changes.

## Why This Project?

This project was motivated by real-world Linux hosting administration challenges involving:

- Outdated ionCube Loader versions available through control panel repositories.
- Applications requiring a specific ionCube Loader release.
- Multiple PHP versions installed on the same server.
- Differences between CLI, PHP-FPM, LSAPI, and web-facing PHP configurations.
- CloudLinux PHP Selector and CageFS integration.
- Manual loader installations requiring reliable backups and recovery.
- Inconsistent ionCube management procedures across hosting platforms.

The goal is to provide a more consistent, transparent, and flexible workflow for system administrators.

## Common Use Cases

### 1. Installing a Newer ionCube Loader Than EasyApache Provides

In some hosting environments, the ionCube Loader version available through EasyApache 4 may be older than the version required by an application.

For example:

| Component | Example version |
|---|---|
| ionCube Loader available through EasyApache | `13.3.1` |
| Required ionCube Loader | `15.5.1` |

These versions illustrate a possible scenario and do not represent the current EasyApache repository state.

The installer provides an alternative manual workflow for obtaining and configuring a newer loader, subject to PHP compatibility and download availability.

### 2. Installing an Exact ionCube Version

Some applications are tested or certified against a specific ionCube Loader release.

Instead of relying exclusively on the version supplied by the operating system or control panel repository, administrators can request an exact release.

Example:

```bash
sudo ./ioncube-universal-installer.sh --php=8.3 --ioncube-version=15.5.0
```

### 3. Historical Installation and Downgrades

Older applications may require a particular ionCube Loader version.

The installer supports requesting historical releases and can perform a downgrade when a compatible archive is available.

Historical archive availability is not guaranteed.

### 4. Supporting Non-cPanel Servers

The installer is not limited to cPanel or EasyApache 4.

It includes discovery and configuration logic for common environments such as:

- Plesk
- DirectAdmin
- Debian and Ubuntu
- RHEL-based Linux distributions
- Remi PHP
- System PHP
- LiteSpeed and OpenLiteSpeed LSPHP

This allows administrators to use a similar workflow across different hosting stacks.

### 5. CloudLinux and CageFS Integration

On CloudLinux servers, ionCube may be correctly configured for host-side PHP while an isolated CageFS environment still exposes an older or different configuration.

The installer includes:

- CageFS detection
- Managed loader directory registration
- CageFS update operations
- ALT-PHP configuration propagation
- Optional verification inside a specified user's CageFS environment

CageFS synchronization does not guarantee that every website will immediately use the expected loader. PHP Selector settings, user-specific configurations, and web execution handlers may require additional verification.

### 6. Managing Multiple PHP Versions

Servers frequently run several PHP versions simultaneously.

The installer allows administrators to select specific versions:

```bash
sudo ./ioncube-universal-installer.sh --php=8.2,8.3
```

Alternatively, all discovered PHP installations can be selected through the interactive workflow.

### 7. Managing Different PHP Execution Handlers

PHP installations may use different execution environments, including:

- PHP CLI
- PHP-FPM
- Apache/mod_php
- CGI and suPHP
- LiteSpeed/LSAPI

The installer inspects common configuration contexts and attempts to reload or recycle relevant services after configuration changes.

Handler-specific and per-domain configurations may still require manual verification.

### 8. Compatibility Preflight Before Installation

Before modifying PHP configuration, the installer tests a candidate ionCube Loader against the corresponding PHP binary.

This helps detect incompatible loader builds before installation.

If the loader cannot be verified, the affected PHP installation is skipped.

### 9. Dry-Run and Automation

Administrators can preview compatibility results and planned configuration actions using dry-run mode.

```bash
sudo ./ioncube-universal-installer.sh --php=8.3 --dry-run
```

The installer also supports non-interactive execution for automated administration workflows.

Dry-run does not modify PHP configuration files, but it may create working directories, logs, and downloaded temporary files.

### 10. Configuration Backups and Rollback

Before modifying PHP configuration files, the installer creates backups and records the affected paths.

A rollback script is generated to help restore backed-up configuration files.

Rollback is not a complete system snapshot, and relevant PHP services may need to be reloaded manually afterward.

### 11. Custom Loader Download Sources

Administrators can provide a custom loader archive URL.

This can be useful for:

- Historical archives
- Internal mirrors
- Alternative distribution sources

Example:

```bash
sudo ./ioncube-universal-installer.sh \
  --php=8.3 \
  --source-url=https://mirror.example.com/ioncube-loaders.tar.gz
```

Non-official sources require explicit approval or the `--allow-third-party` option.

Only use trusted download sources and verify archive authenticity before production deployment.

### 12. Standardizing Server Administration

Organizations managing multiple hosting environments often maintain different procedures for installing and updating PHP extensions.

This project aims to standardize common ionCube management operations through a single script and a consistent command-line interface.

It is designed to reduce repetitive manual work while preserving visibility into compatibility checks, configuration changes, and recovery procedures.

---

## How Is This Different from EasyApache 4?

EasyApache 4 manages PHP extensions within the cPanel ecosystem using packages and versions available through configured repositories.

Universal ionCube Loader Installer is intended for administrators who require additional control beyond those package-managed workflows.

| Capability | EasyApache 4 | Universal ionCube Loader Installer |
|---|---|---|
| PHP extension management | Native cPanel package management | Manual ionCube Loader configuration |
| Loader version selection | Repository-dependent | Latest or requested exact version |
| Historical loader installation | Depends on available packages | Attempts historical archive retrieval |
| Non-cPanel environments | Not its intended scope | Multiple Linux hosting stacks targeted |
| Multiple PHP installations | EA-PHP ecosystem | Multiple discovered PHP installations |
| CloudLinux CageFS | Depends on CloudLinux integration | Includes CageFS update operations |
| Compatibility preflight | Package-management mechanisms | Direct loader test against PHP binary |
| Configuration backups | Depends on system procedures | Script-generated configuration backups |
| Rollback | Package-management or manual procedures | Generated configuration rollback script |
| Custom download source | Repository-based | Explicit loader archive URL |

**This project complements existing control-panel tools rather than replacing their native package management systems.**

It does not repair EasyApache repository errors, resolve YUM/DNF dependency problems, or replace CloudLinux PHP Selector.

---

## Key Features

- Automatic discovery of common PHP installations
- Interactive PHP version selection
- Support for multiple PHP versions
- Latest production ionCube Loader selection
- Exact ionCube Loader version selection
- Historical release lookup and installation attempts
- CPU architecture and loader platform detection
- Compatibility preflight before configuration changes
- Detection of common PHP configuration locations
- Refusal of ambiguous ionCube configuration targets
- Configuration backups
- Generated rollback script
- CloudLinux ALT-PHP and CageFS integration
- PHP handler reload and recycle attempts
- Optional CageFS user-context verification
- Dry-run mode
- Non-interactive execution
- Installation logs
- Post-installation loader verification

---

## Supported and Targeted Environments

The installer includes detection and configuration logic for the following environments.

| Environment | Integration |
|---|---|
| cPanel / WHM | EasyApache EA-PHP |
| CloudLinux | ALT-PHP and CageFS |
| Plesk | Plesk-managed PHP |
| DirectAdmin | CustomBuild and local PHP |
| Debian / Ubuntu | System PHP and SAPI configurations |
| RHEL-based systems | System PHP |
| Remi | Remi PHP installations |
| LiteSpeed / OpenLiteSpeed | LSPHP |
| Apache | Common PHP execution configurations |
| PHP-FPM | Common PHP-FPM configurations |
| CGI / suPHP | Common CGI execution contexts |

**Important:** These are design targets. Full integration testing has not been established across every listed environment.

Custom PHP builds, nonstandard configuration layouts, and per-domain overrides may require manual intervention.

---

## Requirements

- Linux operating system
- Root privileges
- Bash
- One or more PHP installations
- `curl` or `wget`
- Standard Linux command-line utilities, including `tar`, `awk`, `sed`, `grep`, `sort`, `readlink`, and `sha256sum`
- Network access to the selected ionCube Loader download source

Additional utilities such as `file`, `ldd`, `systemctl`, and `cagefsctl` are used where applicable.

For production systems, create a server-level backup before installation.

---

## Installation

### Step 1: Clone the Repository

```bash
git clone https://github.com/omidfazelnejad/ioncube-universal-installer.git
```

### Step 2: Enter the Project Directory

```bash
cd ioncube-universal-installer
```

### Step 3: Make the Script Executable

```bash
chmod +x ioncube-universal-installer.sh
```

### Step 4: Inspect Available PHP Installations

```bash
sudo ./ioncube-universal-installer.sh --status
```

This command displays discovered PHP installations and their current ionCube Loader status.

### Step 5: Preview the Installation

```bash
sudo ./ioncube-universal-installer.sh --php=8.3 --dry-run
```

Review the compatibility results and planned actions before proceeding.

### Step 6: Run the Installer

```bash
sudo ./ioncube-universal-installer.sh
```

The interactive installer prompts for the target PHP installations and the desired ionCube Loader version.

Press Enter to select all discovered PHP installations or the latest production loader release.

---

## Command-Line Options

| Option | Description |
|---|---|
| `--status` | Display discovered PHP installations and current loader status |
| `--php=8.2,8.3` | Select specific PHP versions |
| `--ioncube-version=latest` | Request the latest production loader |
| `--ioncube-version=15.5.0` | Request an exact loader release |
| `--source-url=URL` | Use a custom loader archive URL |
| `--allow-third-party` | Permit a non-ioncube.com source without interactive approval |
| `--verify-user=USER` | Attempt verification inside the specified CageFS user environment |
| `--dry-run` | Perform preflight checks without changing PHP configuration |
| `--no-restart` | Skip automatic PHP/web handler reload attempts |
| `--yes`, `-y` | Enable non-interactive confirmation |
| `--help`, `-h` | Display command-line help |

## Usage Examples

### Check Current Loader Status

```bash
sudo ./ioncube-universal-installer.sh --status
```

### Interactive Installation

```bash
sudo ./ioncube-universal-installer.sh
```

### Install for PHP 8.2 and 8.3

```bash
sudo ./ioncube-universal-installer.sh --php=8.2,8.3
```

### Install the Latest Available Loader

```bash
sudo ./ioncube-universal-installer.sh \
  --php=8.3 \
  --ioncube-version=latest
```

### Install a Specific Loader Version

```bash
sudo ./ioncube-universal-installer.sh \
  --php=8.3 \
  --ioncube-version=15.5.0
```

### Preview Changes

```bash
sudo ./ioncube-universal-installer.sh \
  --php=8.3 \
  --dry-run
```

### Non-Interactive Installation

```bash
sudo ./ioncube-universal-installer.sh \
  --php=8.3 \
  --ioncube-version=latest \
  --yes
```

### Skip Automatic Service Reloads

```bash
sudo ./ioncube-universal-installer.sh \
  --php=8.3 \
  --no-restart
```

### Verify Within CageFS

```bash
sudo ./ioncube-universal-installer.sh \
  --php=8.3 \
  --verify-user=USERNAME
```

### Display Help

```bash
./ioncube-universal-installer.sh --help
```

---

## How the Installer Works

The installation workflow consists of several stages.

### 1. Environment Detection

The script identifies common server characteristics, including:

- Operating system
- CPU architecture
- Control panel
- CloudLinux and CageFS availability
- Common web server processes

### 2. PHP Discovery

The installer searches known PHP binary locations and collects information about each discovered installation.

This includes PHP version, installation family, binary path, loader status, and platform characteristics.

### 3. Loader Selection and Download

The installer selects an appropriate loader archive based on the requested version and detected platform.

For historical releases, it attempts known archive URL patterns and available repository metadata.

### 4. Compatibility Preflight

Each candidate loader is tested against its corresponding PHP binary before configuration changes are applied.

### 5. Configuration Target Discovery

The script inspects known PHP configuration paths and identifies potential ionCube configuration targets.

Ambiguous configurations are rejected rather than modified blindly.

### 6. Backup and Configuration

Before modifying PHP configuration files, the installer creates backups.

It then copies the selected loader into its managed directory and updates the relevant configuration directives.

### 7. CloudLinux Integration

When applicable, the script performs ALT-PHP propagation and CageFS update operations.

### 8. PHP Handler Reload

The installer attempts to reload or recycle relevant PHP execution handlers.

### 9. Verification

After installation, the script checks loader activation using discovered PHP binaries and available execution handlers.

### 10. Recovery Information

The installer displays backup, rollback, and log locations.

---

## Directory Structure

The installer uses the following directories.

### Managed Loader Files

```text
/usr/local/ioncube-universal/
```

### Configuration Backups

```text
/var/backups/ioncube-universal/
```

### Installation Logs

```text
/var/log/ioncube-universal-*.log
```

### CageFS Configuration

When applicable:

```text
/etc/cagefs/conf.d/ioncube-universal.cfg
```

The generated rollback script is stored inside the corresponding timestamped backup directory.

---

## Backup and Rollback

Before changing PHP configuration files, the installer creates a timestamped backup directory.

Example structure:

```text
/var/backups/ioncube-universal/
└── YYYYMMDD-HHMMSS/
    ├── files/
    ├── manifest.tsv
    ├── metadata.txt
    └── rollback.sh
```

To restore the backed-up configuration files:

```bash
sudo bash /var/backups/ioncube-universal/YYYYMMDD-HHMMSS/rollback.sh
```

Replace `YYYYMMDD-HHMMSS` with the actual backup directory name.

The rollback script restores backed-up configuration files and attempts a CageFS refresh when available.

**Limitations:**

- Rollback does not restore the entire operating system.
- Previously installed loader binaries may remain in the managed directory.
- PHP-FPM, Apache, or other services may require manual reloads.
- Automatic rollback is not triggered for every verification failure.

---

## Verification

After installation, administrators should verify the loader using the appropriate PHP binary.

Example for cPanel EA-PHP:

```bash
/opt/cpanel/ea-php83/root/usr/bin/php -v
```

Example for system PHP:

```bash
php -v
```

The output should identify the expected ionCube PHP Loader version.

For web applications, verify the active loader through the actual website PHP execution environment.

CLI verification alone does not guarantee that PHP-FPM, LSAPI, CageFS, or domain-specific PHP configurations are using the same loader.

---

## Security and Safety Considerations

This script modifies PHP configuration files and may reload services. It must be reviewed carefully before use on production systems.

Recommended precautions:

1. Review the script before execution.
2. Run the status command first.
3. Use dry-run mode before applying changes.
4. Create a full server or virtual machine backup.
5. Test on a staging environment when possible.
6. Prefer official ionCube download sources.
7. Verify custom archive authenticity.
8. Review generated installation logs.
9. Confirm the active loader through the website's PHP handler.
10. Keep the rollback path available before making further changes.

The installer performs compatibility checks and configuration backups, but these safeguards do not eliminate every operational or security risk.

---

## Known Limitations

- Custom PHP installations may use configuration paths that the script cannot discover.
- Per-domain `php.ini`, `PHPRC`, and user-specific overrides may differ from host CLI configuration.
- CloudLinux ALT-PHP requires an existing registered ionCube module configuration.
- Historical loader archives may not be publicly available.
- Some CPU architectures or loader builds may be unsupported.
- CageFS synchronization can require additional troubleshooting.
- PHP handler reload attempts may not cover every service configuration.
- Verification is not equivalent to a complete application-level integration test.
- Dry-run may still create logs, directories, and temporary downloads.
- Configuration rollback does not constitute a full server restore.
- Full compatibility testing across all targeted platforms remains incomplete.

---

## Troubleshooting

### Loader Is Visible in CLI but Not on the Website

Possible causes include:

- Different PHP versions used by CLI and the website.
- Different PHP configuration files.
- PHP-FPM or LSAPI workers still using older configurations.
- CageFS or PHP Selector differences.
- Domain-specific configuration overrides.

Recommended checks:

1. Identify the PHP version used by the website.
2. Inspect the active web PHP configuration.
3. Compare it with the CLI configuration.
4. Check CageFS and PHP Selector settings where applicable.
5. Reload the relevant PHP handler if appropriate.
6. Verify the loader again through the website.

### Requested Loader Version Cannot Be Downloaded

Historical loader archives may not be publicly indexed or available.

Use an official archive when possible, or specify a trusted custom source using `--source-url`.

### Compatibility Preflight Fails

The selected loader may not support the target PHP version, architecture, or build.

Review the compatibility output and confirm that the correct loader package was selected.

### Multiple Active ionCube Configuration Files

The installer may refuse to modify an environment when it detects ambiguous active ionCube configuration targets.

Inspect the reported configuration files manually before retrying.

### EasyApache Repository or Package Manager Errors

This installer does not repair broken EasyApache repositories or YUM/DNF dependency issues.

Resolve package-management problems separately before performing related server maintenance.

---

## Project Status and Roadmap

**Current version:** `2.0.3`  
**Status:** Under validation

The current script has passed a Bash syntax check. Comprehensive runtime and integration testing across the targeted hosting platforms has not yet been established.

Potential future improvements include:

- Automated ShellCheck validation
- GitHub Actions CI integration
- Expanded platform compatibility testing
- Automated regression tests
- Improved handling of unusual PHP configuration layouts
- More detailed installation reports
- Additional safeguards for production deployments
- Expanded documentation and troubleshooting examples

---

## Contributing

Contributions, bug reports, and compatibility feedback are welcome.

If you encounter an issue, please open a GitHub Issue and include:

- Linux distribution and version
- Hosting control panel, if applicable
- PHP version and execution handler
- Requested ionCube Loader version
- Relevant error messages
- Steps to reproduce the problem

Remove passwords, access tokens, customer information, private paths, and other sensitive data before sharing logs.

Pull requests should clearly describe the proposed changes and their intended impact.

---

## Disclaimer

This is an independent open-source-oriented system administration project.

It is not affiliated with, sponsored by, or officially endorsed by ionCube, cPanel, CloudLinux, Plesk, DirectAdmin, or other hosting software vendors.

ionCube Loader binaries are proprietary software distributed by their respective rights holders. This repository contains an installation script and does not redistribute ionCube Loader binaries.

The project is provided without any guarantee of compatibility, availability, or suitability for production use.

**Use this script at your own risk, especially on production hosting servers.**

---

## License

A license for this repository has not yet been finalized.

Until a license is added, the repository's public visibility does not automatically grant permission to copy, modify, or redistribute the code.

---

## Author

**Omid Fazelnejad**

GitHub: [@omidfazelnejad](https://github.com/omidfazelnejad)

Project Repository: [ioncube-universal-installer](https://github.com/omidfazelnejad/ioncube-universal-installer)

---

*Developed as a practical Linux system administration and automation project focused on improving ionCube Loader management across diverse hosting environments.*
