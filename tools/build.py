"""Build the Polish gettext catalogue and a deterministic installable ZIP."""
from pathlib import Path
import subprocess
import zipfile
import hashlib

ROOT = Path(__file__).resolve().parent.parent
PLUGIN = ROOT / "sceneprogress.koplugin"


def main():
    po = PLUGIN / "l10n/pl/sceneprogress.po"
    subprocess.run(["msgfmt", "--check", str(po), "-o", str(po.with_suffix(".mo"))], check=True)
    out = ROOT / "dist/sceneprogress-1.0.0.zip"
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        files = {file.relative_to(ROOT).as_posix(): file.read_bytes()
                 for file in sorted(PLUGIN.rglob("*")) if file.is_file()}
        for name in ("README.md", "docs/API.md", "docs/TESTS.md"):
            files["sceneprogress.koplugin/" + name] = (ROOT / name).read_bytes()
        for name, content in sorted(files.items()):
            info = zipfile.ZipInfo(name, (2026, 10, 17, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, content)
    digest = hashlib.sha256(out.read_bytes()).hexdigest()
    out.with_suffix(".zip.sha256").write_text(digest + "  " + out.name + "\n")
    print(f"Built {out.name}: {out.stat().st_size} bytes; SHA-256 {digest}")


if __name__ == "__main__":
    main()
