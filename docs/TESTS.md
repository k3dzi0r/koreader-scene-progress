# Wyniki i odtworzenie testów — 17.10.2026

**40 testów zakończonych powodzeniem**, składnia wszystkich 13 plików Lua poprawna w LuaJIT, Luacheck: **0 ostrzeżeń / 0 błędów**. Testy uruchomiono na macOS ARM64. Nie testowano fizycznego BOOX Palma 2 ani pełnego interfejsu Androida.

## Zakres

| Warstwa | Liczba | Co rzeczywiście uruchomiono |
| --- | ---: | --- |
| Logika | 13 | Prawdziwe moduły detekcji, indeksu i czasu w LuaJIT. |
| Cykl życia | 8 | Prawdziwy `main.lua` z atrapami UI, dokumentu i procesu: ustawienia, callbacki, cache, reflow, zmiana książki, wyłączanie i błędy. |
| Proces | 5 | Prawdziwy `worker.lua` i upstream `ffi/util.lua`, rzeczywiste fork/pipe/kill/waitpid. Zastąpiono tylko pętlę UI i niewykorzystywany helper filesystem. Wynik 1 MB sprawdza opróżnianie potoku większego niż bufor jądra. |
| Frontend | 3 | Rzeczywisty loader MO gettext i serializer `dump`; rzeczywiste metody rejestracji/usuwania/odświeżania ReaderFooter i jego generatory rozdziału/czasu. Zastąpiono zależności ekranu i widgetów, nie badane metody. |
| CREngine | 11 | Niezmieniony upstream `cre.cpp` skompilowany z pasującym CREngine. Otwieranie i renderowanie EPUB, walidacja XPointer, numery stron, font reflow, dwa starsze DOM-y i uszkodzony EPUB. Adapter zastępuje wyłącznie wrapper dokumentu frontendu, nie silnik. |

Zestaw nie jest pełnym testem APK. Lokalny silnik włączono z FreeType, zlib i SRELL; pozostałe opcjonalne komponenty (np. HarfBuzz/SVG) nie są potrzebne do tych testów. Nie uruchomiono całego zestawu upstream Busted ani `epubcheck`. Osobno sprawdzono ZIP, kolejność i kompresję `mimetype`, poprawność XML wszystkich XHTML/OPF oraz niezmienność SHA-256 wszystkich wejściowych EPUB-ów po testach.

## Powtarzalne książki

Wygenerowane przez `python3 tests/make_fixtures.py`. Tekst jest oryginalnym, powtarzanym zdaniem testowym; daty ZIP są stałe.

| Plik | Oczekiwane separatory | Wynik silnika przy 600×800, 24 px |
| --- | ---: | --- |
| `single.epub` | 2 | 2 separatory, 14 stron |
| `triple.epub` | 2 | 2 separatory, 11 stron |
| `none.epub` | 0 | 0 separatorów, 4 strony |
| `footnotes.epub` | 0 | 0 separatorów, 8 stron; link, superskrypt, przypis, CSS display:none i gwiazdki w zdaniu odrzucone |
| `midpage.epub` | 1 | Separator na stronie 1; licznik sceny daje 0 |
| `split.epub` | 1 | Separator w drugim DocFragment; TOC nadal ma tylko 2 prawdziwe rozdziały, 14 stron |
| `semantic.epub` | 5 | `hr`, pusta klasa CSS, encja numeryczna, asterism, gwiazdka w kursywie; 21 stron |
| `broken.epub` | nie dotyczy | CREngine klasyfikuje plik jako Plain text (TXT); bramka EPUB wtyczki go wyłącza |

Numery stron z tej tabeli dotyczą fontu Georgia użytego w wykonanym przebiegu. Testy nie zakładają tych stałych liczebności stron: porównują liczbę wykrytych separatorów, ważność pozycji, zachowanie TOC oraz kierunek zmiany liczby stron po zwiększeniu fontu z 24 do 36 px. Potwierdzono też, że skanowanie nie przesuwa pozycji czytelnika.

100 000 wyszukań następnej granicy w indeksie 10 000 separatorów zajęło około **0,02 s na komputerze testowym**. To test samego wyszukania binarnego; nie jest pomiarem przewracania stron lub zużycia energii na BOOX-ie. Skanowanie całego DOM nie występuje w callbacku stopki.

## Polecenia użyte do weryfikacji

```sh
python3 tools/check.py \
  --lua /private/tmp/sceneprogress-luajit/src/luajit \
  --upstream /private/tmp/sceneprogress-upstream \
  --cre-dir /private/tmp/sceneprogress-native \
  --font /System/Library/Fonts/Supplemental/Georgia.ttf
```

Luacheck uruchomiono zarówno z `.luacheckrc` upstream KOReadera, jak i z lokalną konfiguracją o tych samych zasadach dla kodu wtyczki:

```sh
luacheck --config .luacheckrc sceneprogress.koplugin tests
```

W tym środowisku brakowało zainstalowanego LuaJIT/Luacheck. Zbudowano LuaJIT i LuaFileSystem w `/private/tmp`, pobrano Luacheck i argparse, uruchomiono CLI `bin/luacheck.lua` ze ścieżkami `LUA_PATH`/`LUA_CPATH`. Wersje źródeł:

- LuaJIT: `2a8e017ef1ece6a95b983ffca073d30609dce7c4`
- Luacheck: `2f764bdcabe8b7c19deadf0e9bb2adc19df1a4c5`
- LuaFileSystem: `146ab458e821cd7617892099fe8e6e399b46185c`
- argparse: `412e6aca393e365f92c0315dfe50181b193f1ace`
- xxHash: `680bf463fa1ca0461b9a7c2dab7556e1f54cf4cf`
- SRELL: `04233e350a336553fc368296600bb9aa5636d82b`

Commity KOReadera/base/CREngine są w [API.md](API.md).

`tools/check.py` wykonuje także odpowiednie dla tej wtyczki kontrole z upstream `.ci/check.sh`: brak tabulatorów, nieoznaczonych TODO, nieprzeskalowanych stałych wymiarów UI i kontrolę ekstrakcji gettext. `msgfmt --check` weryfikuje polski katalog. Składnia jest sprawdzana przez `loadfile()` bez wykonywania kodu wtyczki.

## Zbudowanie lokalnego silnika na macOS

Wymagane: narzędzia Xcode/Command Line Tools, Git, CMake, pkg-config, FreeType i zlib. Skrypt pobiera źródła i buduje wszystko w zadanym katalogu tymczasowym; nie instaluje nic do systemu i nie zmienia aplikacji KOReader.

```sh
sh tools/setup_native_macos.sh /private/tmp/sceneprogress-tests
python3 tools/check.py \
  --lua /private/tmp/sceneprogress-tests/luajit/src/luajit \
  --upstream /private/tmp/sceneprogress-tests/koreader \
  --cre-dir /private/tmp/sceneprogress-tests/native \
  --font /System/Library/Fonts/Supplemental/Georgia.ttf
```

Przy gotowym środowisku deweloperskim KOReadera można wskazać jego `cre.so` i LuaJIT zamiast budować osobne. Skrypt macOS nie służy do budowy APK ani kompilacji na BOOX-ie; instalacja wtyczki wymaga wyłącznie skopiowania folderu.

## Test odbiorczy na Palma 2 — pozostaje do wykonania na urządzeniu

1. Zainstaluj wtyczkę i otwórz `single.epub`. Włącz Treści zewnętrzne, wszystkie elementy naraz, natywne strony i czas rozdziału oraz procent.
2. Porównaj z diagnostyką położenie obu separatorów; przejdź przed separator, na stronę separatora i stronę za nim, następnie cofnij. Sprawdź 0 na stronie granicy i przejście do następnej sceny.
3. Włącz statystyki i czytaj co najmniej trzy strony w zwykłym tempie. Sprawdź przejście od `—` do czasu i zgodność formatu z natywnym czasem rozdziału.
4. Zwiększ i zmniejsz font. Po pełnym renderowaniu sprawdź aktualizację stron. Jeżeli włączyło się renderowanie częściowe, sprawdź ukrycie pola i powrót po przeładowaniu/pełnym renderowaniu.
5. Otwórz `split.epub`, `midpage.epub`, `none.epub` i `footnotes.epub`. Nie powinny powstać dodatkowe wpisy TOC ani zakładki.
6. Przełącz strony/czas i tryb kompaktowy, wyłącz/włącz licznik, zamknij i ponownie uruchom KOReader. Sprawdź zapis ustawień.
7. Zmień książkę w czasie analizy; przejdź do PDF. Sprawdź brak pozostałości starego pola i brak komunikatów po każdej zmianie strony.
8. Oceń opóźnienie przewracania stron i odświeżanie E-Ink. Tych właściwości urządzenia nie można potwierdzić testem na komputerze.
