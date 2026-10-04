#!/usr/bin/env python3
"""Build checksum-pinned official R releases for development-only Linux CI.

No package runtime calls this helper. It never invokes install.packages(), uses
sudo, updates the source manifest, or treats a failed command as successful.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest

RELEASES = {
    "4.5.3": {
        "sha256": "aa5c1ed4293c7271ac513d654670356ac0e8a6ad5e42be014365d11150b5b8f2",
        "announcement": "https://stat.ethz.ch/pipermail/r-announce/2026/000718.html",
    },
    "4.6.1": {
        "sha256": "4da6e61d2c0aac5f14a2e7e432cb5fcc269efe83da4293050ba7f03dff4e2cf4",
        "announcement": "https://stat.ethz.ch/pipermail/r-announce/2026/000727.html",
    },
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def file_sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify_download(path, expected):
    actual = file_sha(path)
    require(actual == expected, f"Source SHA-256 mismatch: {actual} != {expected}")
    return actual


def extract_source(archive, destination, version):
    """Reject unsafe entries before extraction; preserve safe in-tree links."""
    destination = Path(destination).resolve()
    require(not destination.exists(), "Extraction destination must be new")
    root = f"R-{version}"
    seen = set()
    with tarfile.open(archive, "r:gz") as stream:
        members = stream.getmembers()
        require(0 < len(members) <= 100000, "Unexpected R archive member count")
        require(sum(member.size for member in members) <= 1024**3, "R archive exceeds size limit")
        for member in members:
            path = PurePosixPath(member.name)
            require(not path.is_absolute() and path.parts and path.parts[0] == root
                    and ".." not in path.parts and "\\" not in member.name,
                    f"Unsafe archive member: {member.name}")
            require(str(path) not in seen, f"Duplicate archive member: {member.name}")
            seen.add(str(path))
            require(member.isdir() or member.isfile() or member.issym() or member.islnk(),
                    f"Unsupported archive member: {member.name}")
            if member.issym() or member.islnk():
                target = PurePosixPath(member.linkname)
                require(not target.is_absolute() and "\\" not in member.linkname,
                        f"Unsafe archive link: {member.name}")
                linked = (destination / path.parent / target if member.issym()
                          else destination / target).resolve()
                require(linked.is_relative_to(destination / root),
                        f"Archive link escapes R source: {member.name}")
            # Python 3.12's data filter also checks effective link paths, file
            # types, permissions and extraction outside destination.
            tarfile.data_filter(member, str(destination))
        require(f"{root}/configure" in seen, "R archive lacks configure")
        require(any(name.startswith(f"{root}/src/library/Recommended/codetools")
                    and name.endswith((".tgz", ".tar.gz")) for name in seen),
                "Pinned R source lacks bundled codetools; no network fallback allowed")
        destination.mkdir(parents=True)
        stream.extractall(destination, members=members, filter="data")
    return destination / root


def run_logged(command, cwd, evidence, label, receipt, env=None, timeout=3600):
    logfile = evidence / f"{label}.log"
    entry = {"command": [str(arg) for arg in command], "cwd": str(cwd),
             "log": str(logfile), "status": "running"}
    receipt["commands"].append(entry)
    start = time.monotonic()
    print(f"Running {label}; log: {logfile}", flush=True)
    try:
        with logfile.open("wb") as output:
            result = subprocess.run(command, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                    stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
        entry["exitCode"] = result.returncode
        entry["status"] = "passed" if result.returncode == 0 else "failed"
        result.check_returncode()
    except BaseException as error:
        entry.update(status="failed", error=repr(error))
        raise
    finally:
        entry["seconds"] = round(time.monotonic() - start, 3)
        if logfile.is_file():
            entry.update(logSha256=file_sha(logfile), logBytes=logfile.stat().st_size)


def install(version, tools, evidence, jobs):
    require(sys.version_info >= (3, 12), "Python 3.12 or later is required")
    require(platform.system() == "Linux" and platform.machine() == "x86_64",
            "This installer is restricted to Linux x86-64")
    require(1 <= jobs <= 64, "Invalid build parallelism")
    tools, evidence = tools.resolve(), evidence.resolve()
    tools.mkdir(parents=True, exist_ok=True)
    evidence.mkdir(parents=True, exist_ok=True)
    release = RELEASES[version]
    prefix = tools / f"R-{version}"
    work = tools / f"build-R-{version}"
    require(not prefix.exists() and not work.exists(), "Use fresh install and build directories")
    work.mkdir()
    archive = work / f"R-{version}.tar.gz"
    url = f"https://cran.r-project.org/src/base/R-4/R-{version}.tar.gz"
    receipt = {"schemaVersion": 1, "status": "running", "version": version,
               "sourceUrl": url, "sourceSha256Expected": release["sha256"],
               "announcement": release["announcement"], "prefix": str(prefix),
               "commands": [], "buildJobs": jobs}
    source = None
    try:
        run_logged(["curl", "--fail", "--location", "--retry", "3", "--proto", "=https",
                    "--proto-redir", "=https", "--tlsv1.2", url, "-o", str(archive)],
                   work, evidence, "download", receipt, timeout=600)
        receipt["sourceSha256Actual"] = verify_download(archive, release["sha256"])
        receipt["sourceBytes"] = archive.stat().st_size
        source = extract_source(archive, work / "source", version)
        receipt["bundledRecommended"] = [
            {"file": p.name, "sha256": file_sha(p)}
            for p in sorted((source / "src/library/Recommended").iterdir())
            if p.is_file() and p.name.endswith((".tgz", ".tar.gz"))
        ]
        build_env = dict(os.environ, CC="gcc", CXX="g++", FC="gfortran", F77="gfortran")
        configure = [str(source / "configure"), f"--prefix={prefix}",
                     "--with-recommended-packages=yes", "--without-x", "--without-readline",
                     "--without-tcltk", "--without-cairo", "--without-jpeglib",
                     "--without-libpng", "--without-libtiff", "--disable-java"]
        run_logged(configure, source, evidence, "configure", receipt, build_env)
        run_logged(["make", f"-j{jobs}"], source, evidence, "make", receipt, build_env)
        run_logged(["make", "install"], source, evidence, "install", receipt, build_env)
        rscript = prefix / "bin/Rscript"
        probe = ('stopifnot(as.character(getRversion()) == "' + version + '", '
                 '.Platform$OS.type == "unix", R.version$arch == "x86_64", '
                 '.Machine$sizeof.pointer == 8L, requireNamespace("codetools", quietly=TRUE)); '
                 'writeLines(c(R.version.string, R.version$platform, '
                 'paste0("codetools=", as.character(packageVersion("codetools"))))); '
                 'print(sessionInfo())')
        run_logged([str(rscript), "--vanilla", "-e", probe], source, evidence,
                   "runtime-probe", receipt, timeout=120)
        receipt.update(status="passed", rscript=str(rscript), rscriptSha256=file_sha(rscript))
        return receipt
    except BaseException as error:
        receipt.update(status="failed", error=repr(error))
        raise
    finally:
        if source is not None and (source / "config.log").is_file():
            shutil.copyfile(source / "config.log", evidence / "config.log")
        (evidence / "r-source-build.json").write_text(
            json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")


class InstallerTests(unittest.TestCase):
    """Small local fixtures; no downloads, compilation, apt or R required."""
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="specqr-ci-selftest-")
        self.root = Path(self.tmp.name)
        self.archive = self.root / "R.tar.gz"
        self.output = self.root / "unpacked"

    def tearDown(self):
        self.tmp.cleanup()

    def make_archive(self, extras=()):
        with tarfile.open(self.archive, "w:gz") as stream:
            for name in ["R-4.5.3/configure", "R-4.5.3/src/library/Recommended/codetools_0.2-20.tar.gz"]:
                item = tarfile.TarInfo(name)
                item.size = 4
                stream.addfile(item, io.BytesIO(b"test"))
            for item in extras:
                stream.addfile(item, io.BytesIO(b"x" * item.size) if item.isfile() else None)

    def rejected(self, item):
        self.make_archive([item])
        with self.assertRaises((ValueError, tarfile.FilterError)):
            extract_source(self.archive, self.output, "4.5.3")
        self.assertFalse(self.output.exists())

    def test_valid_archive(self):
        self.make_archive()
        self.assertEqual((extract_source(self.archive, self.output, "4.5.3") / "configure").read_bytes(), b"test")

    def test_valid_internal_symlink(self):
        item = tarfile.TarInfo("R-4.5.3/src/library/Recommended/codetools.tgz")
        item.type, item.linkname = tarfile.SYMTYPE, "codetools_0.2-20.tar.gz"
        self.make_archive([item])
        source = extract_source(self.archive, self.output, "4.5.3")
        self.assertEqual((source / "src/library/Recommended/codetools.tgz").read_bytes(), b"test")

    def test_absolute_name(self):
        self.rejected(tarfile.TarInfo("/outside"))

    def test_parent_traversal(self):
        self.rejected(tarfile.TarInfo("R-4.5.3/../../outside"))

    def test_wrong_root(self):
        self.rejected(tarfile.TarInfo("R-other/file"))

    def test_duplicate_name(self):
        self.rejected(tarfile.TarInfo("R-4.5.3/configure"))

    def test_device(self):
        item = tarfile.TarInfo("R-4.5.3/device")
        item.type = tarfile.CHRTYPE
        self.rejected(item)

    def test_external_symlink(self):
        item = tarfile.TarInfo("R-4.5.3/link")
        item.type, item.linkname = tarfile.SYMTYPE, "../../outside"
        self.rejected(item)

    def test_external_hardlink(self):
        item = tarfile.TarInfo("R-4.5.3/link")
        item.type, item.linkname = tarfile.LNKTYPE, "outside/file"
        self.rejected(item)

    def test_missing_codetools(self):
        with tarfile.open(self.archive, "w:gz") as stream:
            stream.addfile(tarfile.TarInfo("R-4.5.3/configure"))
        with self.assertRaisesRegex(ValueError, "codetools"):
            extract_source(self.archive, self.output, "4.5.3")

    def test_hash_mismatch(self):
        self.make_archive()
        with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
            verify_download(self.archive, "0" * 64)

    def test_hash_match(self):
        self.make_archive()
        self.assertEqual(verify_download(self.archive, file_sha(self.archive)), file_sha(self.archive))

    def test_command_failure_is_not_masked(self):
        receipt = {"commands": []}
        with self.assertRaises(subprocess.CalledProcessError):
            run_logged([sys.executable, "-c", "print('failure log'); raise SystemExit(7)"],
                       self.root, self.root, "failed-command", receipt)
        self.assertEqual(receipt["commands"][0]["exitCode"], 7)
        self.assertEqual(receipt["commands"][0]["status"], "failed")
        self.assertIn("failure log", (self.root / "failed-command.log").read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("self-test", help="Run small offline installer fixtures")
    build = sub.add_parser("install-r", help="Build one pinned official CRAN release")
    build.add_argument("--version", required=True, choices=RELEASES)
    build.add_argument("--tools", required=True, type=Path)
    build.add_argument("--evidence", required=True, type=Path)
    build.add_argument("--jobs", type=int, default=min(os.cpu_count() or 1, 4))
    args = parser.parse_args()
    if args.action == "self-test":
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(InstallerTests))
        raise SystemExit(0 if result.wasSuccessful() else 1)
    print(json.dumps(install(args.version, args.tools, args.evidence, args.jobs), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
