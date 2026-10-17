"""Small, deterministic EPUB 3 books. No external text or copyrighted assets."""
from pathlib import Path
import zipfile
import json

ROOT = Path(__file__).parent / "fixtures"
PROSE = "Czytelniczka otworzyła okno. Nad rzeką powoli wstawał nowy dzień. " * 18


def paragraph(count=4):
    return "".join(f"<p>{PROSE}</p>" for _ in range(count))


def book(name, bodies, chapters, expected):
    files = {}
    for i, body in enumerate(bodies, 1):
        files[f"OPS/part{i}.xhtml"] = (
            '<?xml version="1.0" encoding="utf-8"?>'
            '<html xmlns="http://www.w3.org/1999/xhtml" '
            'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Próba</title>'
            '<style>.hidden {display:none} .scene-break {text-align:center}</style>'
            '</head><body>' + body + '</body></html>'
        )
    items = ''.join(f'<item id="p{i}" href="part{i}.xhtml" media-type="application/xhtml+xml"/>'
                    for i in range(1, len(bodies) + 1))
    spine = ''.join(f'<itemref idref="p{i}"/>' for i in range(1, len(bodies) + 1))
    files["OPS/package.opf"] = (
        '<?xml version="1.0" encoding="utf-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        f'<dc:identifier id="id">urn:sceneprogress:{name}</dc:identifier>'
        f'<dc:title>Scene Progress: {name}</dc:title><dc:language>pl</dc:language>'
        '<meta property="dcterms:modified">2026-10-17T00:00:00Z</meta></metadata>'
        '<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
        + items + '</manifest><spine>' + spine + '</spine></package>'
    )
    nav = ''.join(f'<li><a href="part{part}.xhtml#ch{n}">Rozdział {n}</a></li>'
                  for n, part in enumerate(chapters, 1))
    files["OPS/nav.xhtml"] = (
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
        '<head><title>Spis treści</title></head><body><nav epub:type="toc"><ol>'
        + nav + '</ol></nav></body></html>'
    )
    files["META-INF/container.xml"] = (
        '<?xml version="1.0"?>'
        '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
        '<rootfiles><rootfile full-path="OPS/package.opf" media-type="application/oebps-package+xml"/>'
        '</rootfiles></container>'
    )
    ROOT.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(ROOT / f"{name}.epub", "w") as out:
        entries = {"mimetype": "application/epub+zip", **files}
        for path, content in entries.items():
            info = zipfile.ZipInfo(path, date_time=(2026, 10, 17, 0, 0, 0))
            info.compress_type = zipfile.ZIP_STORED if path == "mimetype" else zipfile.ZIP_DEFLATED
            out.writestr(info, content.encode())
    return {"name": name, "separators": expected, "chapters": len(chapters)}


def main():
    cases = [
        book("single", [f'<h1 id="ch1">Rozdział 1</h1>{paragraph()}<p>*</p>{paragraph()}',
                        f'<h1 id="ch2">Rozdział 2</h1>{paragraph()}<p>*</p>{paragraph()}'], [1, 2], 2),
        book("triple", [f'<h1 id="ch1">Rozdział</h1>{paragraph()}<p>***</p>{paragraph()}'
                        f'<p>* * *</p>{paragraph()}'], [1], 2),
        book("none", [f'<h1 id="ch1">Rozdział</h1>{paragraph()}'], [1], 0),
        book("footnotes", [f'<h1 id="ch1">Rozdział</h1>{paragraph()}'
                           '<p>Zdanie z gwiazdką * w środku.</p>'
                           '<p><a epub:type="noteref" href="#fn1">*</a></p>'
                           '<p><sup>*</sup></p><aside epub:type="footnote" id="fn1"><p>*</p></aside>'
                           '<div class="hidden"><p>*</p></div><p style="display:none">***</p>'
                           f'<p>Tekst <em>*</em> w zdaniu</p>{paragraph()}'], [1], 0),
        book("midpage", ['<h1 id="ch1">Rozdział</h1><p>Początek sceny.</p>'
                         '<p>*</p><p>Dalsza scena na tej samej stronie.</p>' + paragraph()], [1], 1),
        book("split", [f'<h1 id="ch1">Rozdział 1</h1>{paragraph()}',
                       f'{paragraph()}<p>*</p>{paragraph()}',
                       f'<h1 id="ch2">Rozdział 2</h1>{paragraph()}'], [1, 3], 1),
        book("semantic", [f'<h1 id="ch1">Rozdział</h1>{paragraph()}<hr/>{paragraph()}'
                          f'<div class="scene-break"></div>{paragraph()}'
                          f'<p>&#42;</p>{paragraph()}<p>&#x2042;</p>{paragraph()}'
                          f'<p><em>*</em></p>{paragraph()}'], [1], 5),
    ]
    (ROOT / "manifest.json").write_text(json.dumps(cases, indent=2) + "\n")
    # A bad EPUB must disable only Scene Progress, never mutate the input.
    (ROOT / "broken.epub").write_bytes(b"not an EPUB\n")
    print(f"Generated {len(cases)} valid EPUBs and one corrupt-input fixture")


if __name__ == "__main__":
    main()
