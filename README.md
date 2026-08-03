# Linux Disk Resizer

`disk-resizer` detects the running Linux distribution and launches its matching, version-specific disk-expansion script after a VMware vCenter or ESXi virtual disk has been enlarged. The dispatcher deliberately contains no disk-resize logic: the existing scripts in `os/` remain the sole owners of that work.

## Features

- One installation command followed by automatic operating-system detection.
- Root, package-manager, repository, script, and unsupported-OS checks with actionable failures.
- Idempotent installation: an existing checkout in `/opt/disk-resizer` is fast-forward updated.
- Timestamped, colorized terminal output and centralized logging at `/var/log/disk-resizer.log`.
- Version-specific dispatch, so a script is never selected by an unsafe best guess.
- Small, ShellCheck-friendly Bash modules and a lightweight mapping test.

## Supported distributions

| Distribution | Supported versions |
| --- | --- |
| Ubuntu | 22, 24, 26 |
| Debian | 10, 11, 12, 13 |
| AlmaLinux | 8, 9, 10 |
| Rocky Linux | 10 |
| CentOS Stream | 10 |
| Fedora | 44 |
| Arch Linux | rolling |

Support is limited to the exact version/script mappings in `lib/os.sh`. RHEL, Oracle Linux, SUSE/openSUSE, and unmapped releases fail clearly until their script and mapping are added.

## Installation and usage

Before publishing, replace `<github-user>` in `config.sh` and `install.sh` with the repository owner. Then users can run:

```bash
curl -fsSL https://raw.githubusercontent.com/aminnajmi/disk-resizer/main/install.sh | sudo bash
```

For a custom fork or test checkout, set the repository explicitly:

```bash
curl -fsSL https://raw.githubusercontent.com/aminnajmi/disk-resizer/main/install.sh | \
  sudo DISK_RESIZER_REPOSITORY=https://github.com/aminnajmi/disk-resizer.git bash
```

The installer installs Git when needed, clones into `/opt/disk-resizer`, updates that checkout on later runs, makes shell scripts executable, and executes `launcher.sh`. To run an installed copy again:

```bash
sudo /opt/disk-resizer/launcher.sh
```

Only run this after confirming the virtual disk has been expanded in VMware. Review and test the appropriate `os/` script for the server’s storage layout before production use.

## Project structure

```text
install.sh       bootstrap/update entry point
launcher.sh      root check, OS detection, dispatch, and output handling
config.sh        overridable project settings
lib/             logging, OS detection, package, and utility modules
os/              existing resize scripts; not modified by the framework
tests/           framework tests
```

## Logging and configuration

Every framework and invoked-script output line is written with a timestamp to `/var/log/disk-resizer.log`. Main settings live in `config.sh`; they may also be overridden as environment variables, including `LOG_FILE`, `DEBUG`, `AUTO_INSTALL_PACKAGES`, `INSTALL_DIR`, and `REPOSITORY_URL`.

## Adding a distribution

1. Add the tested, executable resize script to `os/`.
2. Add one `ID:major-version` entry to `resolve_resize_script` in `lib/os.sh`.

No launcher or installer change is required. For a distribution-wide script, use `distro:*` as the mapping key, as Arch does.

## Troubleshooting

- **Must be run as root:** use `sudo`; direct writes to `/var/log` and disk operations require it.
- **Unsupported distribution:** inspect `/etc/os-release`, then add and test a specific mapping rather than reusing another release’s script.
- **Git update failed:** check connectivity and the existing checkout’s remote/branch; the installer intentionally refuses a non-Git directory at `/opt/disk-resizer`.
- **Resize script failed:** read `/var/log/disk-resizer.log`; the launcher passes through the OS script’s exit status.

## Contributing

Keep resize logic in its OS script, keep framework code out of `os/`, run `bash -n` on shell files, and run `bash tests/os_mapping_test.sh` before opening a pull request. Validate new scripts on a non-production VM first.

## License

Released under the [MIT License](LICENSE).
