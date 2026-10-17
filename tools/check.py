"""Repeatable syntax, unit, native-engine and KOReader-style checks."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def run(*args, env=None):
    subprocess.run(args, cwd=ROOT, env=env, check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua", default="luajit")
    parser.add_argument("--upstream", type=Path)
    parser.add_argument("--cre-dir", type=Path)
    parser.add_argument("--font", type=Path)
    args = parser.parse_args()
    sources = sorted((ROOT / "sceneprogress.koplugin").rglob("*.lua")) + sorted((ROOT / "tests").glob("*.lua"))
    for source in sources:
        run(args.lua, "-e", 'assert(loadfile(os.getenv("SCENEPROGRESS_CHECK_FILE")))',
            env={**os.environ, "SCENEPROGRESS_CHECK_FILE": str(source)})
        text = source.read_text()
        assert "\t" not in text, f"tabs: {source}"
        assert not re.search(r"(?<!-)--\s*@?(TODO|FIXME|WARNING)\b", text, re.I), f"TODO style: {source}"
        assert not re.search(r"(?:padding|margin|bordersize|width|height|radius|linesize) = [1-9]\d?\b", text), f"unscaled UI size: {source}"
    print(f"PASS: LuaJIT syntax and KOReader whitespace/size conventions ({len(sources)} files)", flush=True)
    for test in ("test_core.lua", "test_lifecycle.lua"):
        run(args.lua, "tests/" + test)
    run("msgfmt", "--check", "sceneprogress.koplugin/l10n/pl/sceneprogress.po", "-o", os.devnull)
    run("xgettext", "--language=Lua", "--keyword=_", "--from-code=UTF-8", "--check=ellipsis-unicode",
        "--output=" + os.devnull, *map(str, sources[:len(list((ROOT / "sceneprogress.koplugin").rglob("*.lua")))]))
    before = {}
    for fixture in sorted((ROOT / "tests/fixtures").glob("*.epub")):
        before[fixture] = hashlib.sha256(fixture.read_bytes()).digest()
        if fixture.name == "broken.epub":
            continue
        with zipfile.ZipFile(fixture) as book:
            assert book.namelist()[0] == "mimetype" and book.getinfo("mimetype").compress_type == 0
            assert book.read("mimetype") == b"application/epub+zip"
            for name in book.namelist():
                if name.endswith((".xml", ".xhtml", ".opf")):
                    ET.fromstring(book.read(name))
    print("PASS: fixture ZIP/XML structure and uncompressed first mimetype", flush=True)
    if args.upstream:
        run(args.lua, "tests/test_worker_native.lua", str(args.upstream))
        run(args.lua, "tests/test_frontend_native.lua", str(args.upstream), str(ROOT))
    if args.cre_dir:
        assert args.font, "--font required with --cre-dir"
        env = {**os.environ, "LUA_CPATH": str(args.cre_dir / "?.so") + ";;"}
        run(args.lua, "tests/test_native.lua", str(args.font), env=env)
    assert all(hashlib.sha256(path.read_bytes()).digest() == digest for path, digest in before.items())
    print("PASS: all fixture EPUBs unchanged (SHA-256)", flush=True)


if __name__ == "__main__":
    main()
