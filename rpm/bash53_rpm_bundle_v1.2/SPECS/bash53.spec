Name:           bash53
Version:        5.3
Release:        1%{?dist}
Summary:        GNU Bash 5.3 (parallel install, does not replace system bash)

License:        GPLv3+
URL:            https://www.gnu.org/software/bash/
Source0:        bash-5.3.tar.gz

BuildRequires:  gcc, make, ncurses-devel

%description
Parallel-install Bash 5.3 as /usr/local/bin/bash53 (no system replacement).

%prep
%setup -q -n bash-5.3

%build
./configure --prefix=/usr/local \
            --program-suffix=53 \
            --disable-nls
make %{?_smp_mflags}

%install
rm -rf %{buildroot}
make install DESTDIR=%{buildroot}

mv %{buildroot}/usr/local/share/man/man1/bash.1 %{buildroot}/usr/local/share/man/man1/bash53.1
gzip -f %{buildroot}/usr/local/share/man/man1/bash53.1

%files
/usr/local/bin/bash53
/usr/local/bin/bashbug53
/usr/local/share/man/man1/bash53.1.gz
/usr/local/share/doc/bash-5.3
/usr/local/share/info/bash.info*

%changelog
* Wed Dec 03 2025 Groucho <you@example.com> - 5.3-1
- Corrected make flags for parallel install
