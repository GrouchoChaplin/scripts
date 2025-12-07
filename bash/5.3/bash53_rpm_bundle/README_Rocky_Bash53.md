# Bash 5.3 Parallel-Install RPM (`bash53`) for Rocky/RHEL 8/9

This bundle helps you build and install **Bash 5.3** *side-by-side* with the
system Bash on Rocky or RHEL 8/9:

- **System bash** remains `/bin/bash` (unchanged)
- New shell is installed as `/usr/local/bin/bash53`
- No system script is modified
- Clean uninstall via: `sudo rpm -e bash53`

---

## 0. First-Time Setup: RPM Build Environment

Run the helper script once on each new machine:

```bash
cd /path/to/bash53_rpm_bundle_v1.1/scripts
./setup_rpmbuild_env.sh --install-deps
```

This will:

- Install required build dependencies:
  - `rpm-build`, `gcc`, `make`, `ncurses-devel`, `curl`
- Create the RPM build tree (default: `~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}`)
- Configure `~/.rpmmacros` so that `rpmbuild` uses that topdir

To use a custom topdir instead (e.g. `~/projects/rpmbuild`):

```bash
./setup_rpmbuild_env.sh --topdir ~/projects/rpmbuild --install-deps
```

---

## 1. Copy Spec & Download Sources

After running the setup script, your topdir will normally be `~/rpmbuild`.
If you used a custom `--topdir`, substitute that path below.

```bash
cp SPECS/bash53.spec ~/rpmbuild/SPECS/
cd ~/rpmbuild/SOURCES
curl -O https://ftp.gnu.org/gnu/bash/bash-5.3.tar.gz
```

If the tarball is named differently, either rename it to exactly:

```text
bash-5.3.tar.gz
```

or update `Source0` in `bash53.spec`.

---

## 2. Optional: Use the One-Step Build Script

Instead of doing the manual copy + curl, you can also use the helper script:

```bash
cd /path/to/bash53_rpm_bundle_v1.1/scripts
./build_bash53_rpm.sh
```

That script will:

1. Ensure the rpmbuild tree exists (using `~/.rpmmacros` if present)
2. Install `rpm-build gcc make ncurses-devel curl` if missing
3. Copy `SPECS/bash53.spec` into `\$TOPDIR/SPECS`
4. Download `bash-5.3.tar.gz` into `\$TOPDIR/SOURCES`
5. Run `rpmbuild -ba bash53.spec`

---

## 3. Build the RPM Manually (Alternative)

If you prefer the manual route:

```bash
cd ~/rpmbuild/SPECS
rpmbuild -ba bash53.spec
```

If successful, the binary RPM will be in something like:

```text
~/rpmbuild/RPMS/x86_64/bash53-5.3-1.el8.x86_64.rpm
```

(or `el9`, depending on your system).

---

## 4. Install Bash 5.3 Side-by-Side

```bash
sudo dnf install ~/rpmbuild/RPMS/x86_64/bash53-5.3-1*.rpm
```

Verify:

```bash
bash53 --version
```

You should see:

```text
GNU bash, version 5.3.x(1)-release
```

---

## 5. Optional: Make Bash 5.3 Your Login Shell

This does **not** change `/bin/bash`; it only changes your user shell.

```bash
chsh -s /usr/local/bin/bash53
```

Log out and back in, then confirm:

```bash
echo "$SHELL"
# /usr/local/bin/bash53
```

---

## 6. Uninstalling

To remove the package:

```bash
cd /path/to/bash53_rpm_bundle_v1.1/scripts
./uninstall_bash53.sh
```

If you changed your login shell to `/usr/local/bin/bash53`, run:

```bash
chsh -s /bin/bash
```

**before** uninstalling.

---

## 7. Files Installed by This RPM

- `/usr/local/bin/bash53`
- `/usr/local/bin/bashbug53`
- `/usr/local/share/man/man1/bash53.1.gz`
- `/usr/local/share/doc/bash-5.3`
- `/usr/local/share/info/bash.info*`

No files in `/bin`, `/usr/bin`, or `/etc` are touched.

---

## 8. Notes

- The spec uses `--disable-nls` to simplify packaging by avoiding translations.
- The package name is `bash53` and **does not** `Provide: bash`, so it won't
  conflict with the system `bash` package.
- You can keep this RPM in your own repo or just install it locally.

Happy scripting!
