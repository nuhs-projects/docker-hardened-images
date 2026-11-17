"""Harden a Debian-based image filesystem in place.

Run inside the image being hardened (as root), with Python 3 and nothing else:
DHI runtime images have no shell or package manager, so this script removes
packages by editing the dpkg database directly instead of calling dpkg.

    python3 harden.py [--purge PKG ...] [--strip-setuid]

--purge PKG       Remove every file the package installed (from
                  /var/lib/dpkg/info/PKG.list), its dpkg metadata, and its
                  entry in /var/lib/dpkg/status and /var/lib/dpkg/status.d/.
                  Scanners read that database, so a package removed this way
                  is no longer reported. Directories are removed only once
                  empty, so paths shared with other packages survive.
--strip-setuid    Clear the setuid and setgid bits on every file.
--install-from ROOT --install PKG ...
                  Replace PKG with the build installed in the filesystem
                  mounted at ROOT (files and dpkg records), e.g. a newer build
                  the vendor already ships in its -dev image.

Fails if a package to purge is not installed, so a renamed package in a new
upstream image is noticed instead of silently left in place.
"""

import argparse
import os
import shutil
import stat
import sys

DPKG = "/var/lib/dpkg"
DOCS = tuple(f"/usr/share/{d}/" for d in ("doc", "man", "info", "lintian", "locale"))


def package_names(stanza):
    for line in stanza.splitlines():
        if line.startswith("Package:"):
            return line.split(":", 1)[1].strip()
    return None


def remove_status_entry(pkg):
    """Drop pkg from status (one file, blank-line separated stanzas) and
    status.d (one file per package, used by distroless-style images)."""
    found = False

    status_d = os.path.join(DPKG, "status.d")
    if os.path.isdir(status_d):
        for name in os.listdir(status_d):
            path = os.path.join(status_d, name)
            if name == pkg or name.startswith(pkg + ".") or name.startswith(pkg + ":"):
                with open(path) as f:
                    if package_names(f.read()) == pkg:
                        os.remove(path)
                        found = True

    status = os.path.join(DPKG, "status")
    if os.path.isfile(status):
        with open(status) as f:
            stanzas = f.read().split("\n\n")
        kept = [s for s in stanzas if package_names(s) != pkg]
        if len(kept) != len(stanzas):
            found = True
            with open(status, "w") as f:
                f.write("\n\n".join(kept))

    return found


def remove_truncated(path):
    """DHI's .list files cut names at the first space ("Lorem ipsum.txt" is
    listed as "Lorem"), so a listed path that does not exist may be the start
    of one or more real names: remove the files in its directory that begin
    with it plus a space."""
    parent, stem = os.path.split(path.rstrip("/"))
    if not os.path.isdir(parent):
        return
    for name in os.listdir(parent):
        full = os.path.join(parent, name)
        if name.startswith(stem + " ") and (os.path.isfile(full) or os.path.islink(full)):
            os.remove(full)


def purge(pkg):
    info = os.path.join(DPKG, "info")
    # PKG.list, or PKG:ARCH.list for multi-arch packages
    lists = [n for n in os.listdir(info)
             if n == pkg + ".list" or (n.startswith(pkg + ":") and n.endswith(".list"))]
    if not lists:
        sys.exit(f"harden.py: {pkg} is not installed (no {pkg}.list in {info})")

    paths = []
    for name in lists:
        with open(os.path.join(info, name)) as f:
            paths += [line.rstrip("\n") for line in f if line.strip() and line.strip() != "/."]

    dirs = []
    for path in paths:
        if os.path.islink(path) or os.path.isfile(path):
            os.remove(path)
        elif os.path.isdir(path):
            dirs.append(path)
        else:
            remove_truncated(path)

    # Deepest first. Bytecode caches are not in the .list (Python writes them
    # at runtime), so a directory holding only __pycache__ counts as empty.
    for path in sorted(set(dirs), key=lambda p: p.count("/"), reverse=True):
        try:
            entries = os.listdir(path)
        except FileNotFoundError:
            continue
        if entries == ["__pycache__"]:
            shutil.rmtree(os.path.join(path, "__pycache__"))
            entries = []
        if not entries:
            os.rmdir(path)

    for name in os.listdir(info):
        if name.startswith(pkg + ".") or name.startswith(pkg + ":"):
            os.remove(os.path.join(info, name))

    if not remove_status_entry(pkg):
        sys.exit(f"harden.py: {pkg} has files but no dpkg status entry")
    print(f"harden.py: purged {pkg} ({len(paths)} paths)")


def read_status_entry(root, pkg):
    """The dpkg status stanza for pkg in the filesystem at root."""
    status_d = os.path.join(root, DPKG.lstrip("/"), "status.d")
    if os.path.isfile(os.path.join(status_d, pkg)):
        with open(os.path.join(status_d, pkg)) as f:
            return f.read().strip("\n")
    status = os.path.join(root, DPKG.lstrip("/"), "status")
    if os.path.isfile(status):
        with open(status) as f:
            for stanza in f.read().split("\n\n"):
                if package_names(stanza) == pkg:
                    return stanza.strip("\n")
    sys.exit(f"harden.py: {pkg} is not installed in {root}")


def install_from(root, pkg):
    """Replace pkg with the build of it installed in the filesystem at root
    (e.g. a newer build of the same package in the same vendor's -dev image):
    purge ours, then copy its files and dpkg records across. Both images must
    be the same distribution and architecture."""
    stanza = read_status_entry(root, pkg)
    version = next(l.split(":", 1)[1].strip() for l in stanza.splitlines() if l.startswith("Version:"))
    if any(n == pkg + ".list" or (n.startswith(pkg + ":") and n.endswith(".list"))
           for n in os.listdir(os.path.join(DPKG, "info"))):
        purge(pkg)

    info = os.path.join(root, DPKG.lstrip("/"), "info")
    names = [n for n in os.listdir(info) if n.startswith(pkg + ".") or n.startswith(pkg + ":")]
    with open(os.path.join(info, next(n for n in names if n.endswith(".list")))) as f:
        paths = [line.rstrip("\n") for line in f if line.strip() and line.strip() != "/."]

    for path in paths:
        src = os.path.join(root, path.lstrip("/"))
        if os.path.isdir(src) and not os.path.islink(src):
            os.makedirs(path, exist_ok=True)
            continue
        if not os.path.lexists(src):
            # Name cut at a space in the .list: copy the real names
            parent, stem = os.path.split(src)
            matches = [n for n in os.listdir(parent) if n.startswith(stem + " ")] if os.path.isdir(parent) else []
            if not matches:
                # Images often drop documentation their packages list
                if path.startswith(DOCS):
                    continue
                sys.exit(f"harden.py: {path} (from {pkg}) is missing in {root}")
            pairs = [(os.path.join(parent, n), os.path.join(os.path.dirname(path), n)) for n in matches]
        else:
            pairs = [(src, path)]
        for s, d in pairs:
            os.makedirs(os.path.dirname(d), exist_ok=True)
            if os.path.lexists(d):
                os.remove(d)
            if os.path.islink(s):
                os.symlink(os.readlink(s), d)
            else:
                shutil.copy2(s, d)

    for name in names:
        shutil.copy2(os.path.join(info, name), os.path.join(DPKG, "info", name))
    status_d = os.path.join(DPKG, "status.d")
    if os.path.isdir(status_d):
        with open(os.path.join(status_d, pkg), "w") as f:
            f.write(stanza + "\n")
    else:
        with open(os.path.join(DPKG, "status"), "a") as f:
            f.write("\n" + stanza + "\n")
    print(f"harden.py: installed {pkg} {version} from {root}")


def strip_setuid():
    for root, dirs, files in os.walk("/", topdown=True):
        # Stay on the image filesystem: skip kernel and build mounts
        dirs[:] = [d for d in dirs if not os.path.ismount(os.path.join(root, d))]
        for name in files:
            path = os.path.join(root, name)
            try:
                mode = os.lstat(path).st_mode
            except FileNotFoundError:
                continue
            if stat.S_ISREG(mode) and mode & (stat.S_ISUID | stat.S_ISGID):
                os.chmod(path, mode & ~(stat.S_ISUID | stat.S_ISGID) & 0o7777)
                print(f"harden.py: cleared setuid/setgid on {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--purge", nargs="+", default=[], metavar="PKG")
    parser.add_argument("--strip-setuid", action="store_true")
    parser.add_argument("--install-from", metavar="ROOT",
                        help="filesystem to take the --install packages from")
    parser.add_argument("--install", nargs="+", default=[], metavar="PKG")
    args = parser.parse_args()
    if args.install and not args.install_from:
        parser.error("--install needs --install-from")
    for pkg in args.purge:
        purge(pkg)
    for pkg in args.install:
        install_from(args.install_from, pkg)
    if args.strip_setuid:
        strip_setuid()


if __name__ == "__main__":
    main()
