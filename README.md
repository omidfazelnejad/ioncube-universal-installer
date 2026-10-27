# Universal ionCube Loader Installer

**A Bash-based automation tool for installing and managing ionCube PHP Loaders across multiple Linux hosting environments.**

Version: `2.0.3`

## Overview

Managing ionCube Loader across multiple PHP versions and hosting environments can become challenging, especially on servers running cPanel, CloudLinux, EasyApache 4, and multiple PHP handlers.

This project provides an interactive and command-line installer designed to simplify ionCube Loader deployment, configuration, compatibility checks, and recovery.

It supports automatic discovery of common PHP installations and provides a structured installation workflow with configuration backups and rollback support.

## Background

This project was motivated by practical Linux hosting administration challenges involving:

- Multiple PHP versions installed on the same server.
- Different PHP configuration paths and execution handlers.
- ionCube Loader availability versus actual PHP activation.
- CloudLinux PHP Selector and CageFS integration.
- The need to minimize configuration risks during manual loader installation.

The goal is to make ionCube management more predictable, transparent, and maintainable.

## Key Features

- **Automatic PHP discovery:** Detects common PHP installations across hosting environments.
- **Multi-version support:** Select one, multiple, or all detected PHP installations.
- **Flexible ionCube selection:** Use the latest production release or request a specific historical version.
- **Compatibility preflight:** Tests candidate loaders against their corresponding PHP binaries before modifying configuration.
- **Configuration discovery:** Inspects known PHP configuration layouts and runtime contexts.
- **Automatic backups:** Preserves configuration files before modification.
- **Rollback support:** Generates a rollback script for restoring backed-up configuration files.
- **CloudLinux integration:** Supports CageFS updates and existing ALT-PHP module configurations.
- **Service reloads:** Attempts to refresh relevant PHP-FPM, Apache, and LiteSpeed handlers.
- **Logging and verification:** Records operations and checks loader activation after installation.
- **Dry-run mode:** Allows preflight checks without modifying server configuration.

## Target Environments

The installer is designed for common Linux PHP hosting stacks, including:

| Environment | Targeted integration |
|---|---|
| cPanel / WHM | EasyApache EA-PHP |
| CloudLinux | ALT-PHP and CageFS |
| Plesk | Plesk-managed PHP |
| DirectAdmin | CustomBuild PHP |
| Debian / Ubuntu | System PHP and SAPI configurations |
| RHEL-based systems | System PHP and Remi PHP |
| LiteSpeed / OpenLiteSpeed | LSPHP |
| Apache / PHP-FPM | Common PHP execution handlers |

**Note:** These are design targets, not a guarantee of successful installation on every distribution, custom PHP build, or hosting configuration.

## Requirements

- Linux server
- Root privileges
- Bash
- PHP installation(s)
- `curl` or `wget`
- Standard Linux utilities used by the script
- Network access to the selected loader download source

## Installation

Clone the repository:

```bash
git clone https://github.com/YOUR-USERNAME/ioncube-universal-installer.git
cd ioncube-universal-installer
```

Make the script executable:

```bash
chmod +x ioncube-universal-installer.sh
```

Inspect the detected PHP installations:

```bash
sudo ./ioncube-universal-installer.sh --status
```

## Usage

### Interactive installation

```bash
sudo ./ioncube-universal-installer.sh
```

The installer prompts for PHP versions and the desired ionCube Loader version.

Press Enter to select all detected PHP installations or use the latest loader release.

### Install for specific PHP versions

```bash
sudo ./ioncube-universal-installer.sh --php=8.2,8.3
```

### Install a specific ionCube version

```bash
sudo ./ioncube-universal-installer.sh --php=8.3 --ioncube-version=15.5.0
```

Historical releases depend on archive availability.

### Preview changes

```bash
sudo ./ioncube-universal-installer.sh --php=8.3 --dry-run
```

### Non-interactive installation

```bash
sudo ./ioncube-universal-installer.sh --php=8.3 --ioncube-version=latest --yes
```

### Avoid automatic service reloads

```bash
sudo ./ioncube-universal-installer.sh --php=8.3 --no-restart
```

### Verify within CloudLinux CageFS

```bash
sudo ./ioncube-universal-installer.sh --php=8.3 --verify-user=USERNAME
```

## Safety and Recovery

The installer includes several safeguards:

1. Loader compatibility checks before configuration changes.
2. Detection of ambiguous ionCube configuration targets.
3. Backups of configuration files before modification.
4. A generated rollback script.
5. Installation logs and post-installation verification.

Backup files are stored under:

```text
/var/backups/ioncube-universal/
```

Logs are stored under:

```text
/var/log/ioncube-universal-*.log
```

To restore configuration files, execute the generated `rollback.sh` from the relevant backup directory.

**Important:** Rollback restores backed-up configuration files; service reloads may still be necessary. It is not a complete server snapshot.

## Known Limitations

- Custom PHP builds and per-domain `php.ini` overrides may require manual verification.
- CloudLinux ALT-PHP requires an existing registered ionCube module configuration.
- Historical ionCube releases may not be publicly downloadable.
- PHP CLI verification does not guarantee that every website PHP handler is using the same loader.
- Some service reloads and CageFS updates may require manual follow-up.
- Installation on production servers should be preceded by testing and appropriate backups.

## Project Status

**Version 2.0.3 — Under validation**

The script has passed a Bash syntax check. Full integration testing across the listed hosting platforms has not yet been established.

Contributions, bug reports, and compatibility feedback are welcome.

## Disclaimer

This project is an independent administration utility and is not affiliated with or endorsed by ionCube, cPanel, CloudLinux, or other hosting software vendors.

ionCube Loader is downloaded from the configured distribution source. The project does not distribute proprietary ionCube Loader binaries.

Use this script at your own risk, particularly on production hosting servers.

## License

License to be determined.

## Contributing

Contributions and feedback are welcome through GitHub Issues and Pull Requests.
