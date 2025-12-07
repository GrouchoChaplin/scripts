# RPM Sanity Check Script — Full Explanation

**Last updated:** 2025-12-06  
**Script:** `rpm_sanity_check.sh`  
**Purpose:** Ensure your RPM build environment is correctly configured before running `rpmbuild`.

---

# ✅ High-Level Summary

This script performs a **complete pre-flight validation** of your RPM build environment on Rocky/RHEL/Fedora systems. It ensures:

- Your `~/.rpmmacros` file exists and defines `%_topdir`.
- Your RPM build tree (`BUILD`, `RPMS`, `SOURCES`, `SPECS`, `SRPMS`) exists.
- The required spec file (`bash53.spec`) is present.
- The expected source tarball (`bash-5.3.tar.gz`) is present — and automatically downloads it if missing.
- All required build dependencies are installed (`rpm-build`, `gcc`, `make`, `ncurses-devel`, `curl`).

If everything checks out, the script prints a success message and shows the correct `rpmbuild` command to run.

---

# 🧠 Detailed Breakdown

---

## 1. Color Setup & Helper Functions

If the terminal supports colors, it defines:

- Green (`[GOOD]`)
- Yellow (`[WARN]`)
- Red (`[FAIL]`)
- Blue (`[INFO]`)

Helper methods (`good`, `warn`, `bad`, `info`) print color-coded status messages.  
The script uses `set -euo pipefail` for strict error handling.

---

## 2. Validate `~/.rpmmacros`

The script requires that your RPM environment was previously initialized.

It checks:

### ✔ File exists  
If not, it aborts and instructs you to run `setup_rpmbuild_env.sh`.

### ✔ `%_topdir` is defined  
If missing, the script fails immediately.

### ✔ Resolves the actual TOPDIR path  
The script pulls `%_topdir` from your macros file and expands `~` to `$HOME`.

Example OUTPUT:
```
[GOOD] ~/.rpmmacros OK (TOPDIR=/home/user/rpmbuild)
```

---

## 3. Validate TOPDIR Structure

Your RPM topdir **must** contain:

- BUILD
- RPMS
- SOURCES
- SPECS
- SRPMS

The script checks all of these and fails if any are missing.

---

## 4. Validate Spec File (`bash53.spec`)

The script checks for:

```
$TOPDIR/SPECS/bash53.spec
```

If missing, the script prints instructions for copying it into place and exits.

---

## 5. Validate Source Tarball (`bash-5.3.tar.gz`)

The script checks for:

```
$TOPDIR/SOURCES/bash-5.3.tar.gz
```

### If missing:
- Prints warnings.
- Automatically downloads from:  
  `https://ftp.gnu.org/gnu/bash/bash-5.3.tar.gz`
- Fails if curl cannot download it.

If present, prints `[GOOD]`.

---

## 6. Validate Build Dependencies

The script checks for the following packages using `rpm -q`:

- `rpm-build`
- `gcc`
- `make`
- `ncurses-devel`
- `curl`

If any are missing, the script:

- Prints warnings
- Displays the exact `dnf install` command
- Aborts

No system modifications occur automatically except the optional tarball download earlier.

---

## 7. Final Summary

If all checks pass:

```
[GOOD] RPM build environment sanity check PASSED.
```

It then tells you what to run next:

```
rpmbuild -ba $SPECFILE
```

---

# 🎯 What the Script *Actually* Does

**It validates your entire RPM build environment, fixes only the missing tarball automatically, and stops you early if anything is misconfigured — preventing wasted time on failed `rpmbuild` attempts.**

---

# 🔍 Side Effects

| Action | Effect |
|--------|--------|
| Missing tarball | Automatically downloads `bash-5.3.tar.gz` |
| Missing dependencies | Script aborts, does NOT auto-install |
| Missing directories | Script aborts with clear guidance |
| Missing spec | Script aborts with fix instructions |

The script **never** builds RPMs, modifies system configuration, or installs packages automatically.

---

# 📌 Bottom Line

This script acts as a **professional "doctor" tool for RPM building**, similar to a pre-flight checklist:

> “Is the environment configured perfectly before we start building packages?”

It ensures everything is in place before running:

```
rpmbuild -ba bash53.spec
```

---

# 📝 If You Want Enhancements

I can extend this tool to include:

- Auto-fix mode (create missing directories, install deps)
- Support for multiple spec files
- JSON/YAML machine-readable output (for CI pipelines)
- `--doctor` diagnostic mode
- Modular functions to reuse in other scripts

Just tell me what you'd like added.

---
