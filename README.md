# Scene Progress 1.0.0 — KOReader

Wtyczka dodaje **strony i czas do końca sceny do standardowego dolnego paska KOReadera**. Nie tworzy dodatkowego paska ani nakładki. Natywne wskaźniki rozdziału, czasu do końca rozdziału i procentu książki nadal obsługuje KOReader.

Domyślnie: `S:4 · 0:06`. W trybie opisowym: `Scena: 4 str. · 0:06`. To przykład formatu, nie stałe wartości. Czas korzysta z formatu czasu wybranego w KOReaderze; `0:06` oznacza sześć minut.

## Instalacja na BOOX Palma 2 / Android

1. Uruchom KOReader przynajmniej raz, następnie zamknij go przez menu aplikacji.
2. Rozpakuj [dist/sceneprogress-1.0.0.zip](dist/sceneprogress-1.0.0.zip).
3. Skopiuj **cały folder `sceneprogress.koplugin`** do katalogu:

   ```text
   /storage/emulated/0/koreader/plugins/
   ```

   To ten sam katalog co `/sdcard/koreader/plugins/` — pamięć wewnętrzna → `koreader` → `plugins`. Utwórz `plugins`, jeśli go nie ma. Prawidłowa końcowa ścieżka:

   ```text
   /storage/emulated/0/koreader/plugins/sceneprogress.koplugin/main.lua
   ```

   Unikaj dodatkowego poziomu `sceneprogress-1.0.0/sceneprogress.koplugin`. Nie kopiuj wtyczki do katalogu książek ani do prywatnego katalogu APK. Jeśli świadomie zmieniłeś katalog danych lub `extra_plugin_paths`, użyj jego podkatalogu `plugins`.
4. Uruchom ponownie KOReader. W menedżerze wtyczek sprawdź, czy **Scene Progress** jest włączone. Po zmianie stanu w menedżerze uruchom aplikację ponownie, jeśli o to poprosi.
5. Otwórz EPUB. W menu narzędzi pojawi się **Scene Progress**. Włącz „Włącz licznik scen”. Skanowanie odbywa się w tle, bez okien i powiadomień. Wskaźnik pojawi się po jego zakończeniu.

Ścieżka wynika z [katalogu danych Androida](https://github.com/koreader/koreader/blob/79b24c0a3af7ea115f0bae3810855ed6328a1741/datastorage.lua#L22) oraz [wyszukiwania dodatkowych wtyczek](https://github.com/koreader/koreader/blob/79b24c0a3af7ea115f0bae3810855ed6328a1741/frontend/pluginloader.lua#L194).

## Włączenie informacji w istniejącej stopce

W otwartym EPUB-ie wejdź w **Pasek stanu / Status bar** → **Elementy paska stanu / Status bar items**. Nazwy polskiego tłumaczenia mogą różnić się między wydaniami.

- Włącz sam pasek stanu.
- Włącz **External content / Treści zewnętrzne** — to standardowe pole, którego używa wtyczka. API KOReadera zazwyczaj włącza je automatycznie podczas rejestracji wtyczki.
- Włącz **Show all selected items at once / Pokazuj wszystkie wybrane elementy naraz**, aby scena i rozdział były widoczne jednocześnie.
- Zaznacz **Pages left in chapter**, **Time left to finish chapter** i opcjonalnie **Progress percentage**. To istniejące wskaźniki KOReadera, z własnym formatem i prefiksami.
- Na wąskim ekranie Palma 2 pozostaw tryb kompaktowy Scene Progress. Jeśli brakuje miejsca, ogranicz inne elementy stopki lub zmniejsz jej czcionkę w standardowych ustawieniach.

Bez trybu „wszystkie naraz” KOReader przełącza elementy stopki; sam licznik scen tego ustawienia nie zmienia.

## Ustawienia Scene Progress

| Ustawienie | Działanie |
| --- | --- |
| Włącz licznik scen | Dodaje lub usuwa callback standardowej stopki. |
| Pokazuj pozostałe strony | Osobne włączenie liczby stron. |
| Pokazuj pozostały czas | Osobne włączenie czasu. |
| Tryb kompaktowy | Włączony: `S:4 · 0:06`; wyłączony: `Scena: 4 str. · 0:06`. |
| Pojedyncza gwiazdka | Osobny blok zawierający tylko `*`, również wewnątrz elementu kursywy. |
| Wiele gwiazdek | Co najmniej trzy gwiazdki, również rozdzielone odstępami. |
| Ozdobniki typograficzne | M.in. `⁂`, `⁎`, `⁎⁎⁎`, `※`, `❦`, `❧`, `✦`, `✧`, `•••`, `···`. |
| Separatory semantyczne | Widoczne `hr`, `role="separator"` lub bloki o wybranej klasie CSS. Akceptuje pusty blok/obraz lub sam ozdobnik, odrzuca zwykłą prozę. |
| Nazwy klas CSS | Dokładne nazwy klas oddzielone spacjami. Domyślne: `scene-break scenebreak scene_break asterism dinkus`. |
| Skanuj książkę ponownie | Wymusza nową analizę otwartej książki. |
| Diagnostyka | Stan skanowania, liczba separatorów, odrzuconych pozycji oraz do 30 numerów stron. Nie pokazuje treści książki. |

Ustawienia są globalne i zapisują się przez standardowe `G_reader_settings`. Indeks pozycji zapisuje się w ustawieniach danej książki pod kluczem `sceneprogress_cache`. Wtyczka nie tworzy zakładek ani wpisów spisu treści.

## Znaczenie liczników

- Są to **wyrenderowane strony ekranowe**, nie drukowane numery stron z EPUB-a. Liczba zależy od czcionki, marginesów i układu.
- Do separatora na stronie 8, z obecnej strony 5, pozostają 3 strony. Separator na aktualnej stronie daje **0**. Przejście na kolejną stronę wybiera następny separator. Cofnięcie przywraca odpowiednią wcześniejszą scenę.
- Wtyczka nie wie, który wiersz aktualnej strony właśnie czytasz. Jeśli na stronie są dwie sceny, granicą pozostaje pierwszy separator na tej stronie aż do jej opuszczenia. Ten wybór zapobiega skokom i ujemnym wynikom.
- Koniec sceny nie wykracza poza natywny koniec rozdziału. Jeśli wcześniej nie ma separatora, wynik pochodzi z `ReaderToc:getChapterPagesLeft(page, true)`, a w ostatnim rozdziale z `getTotalPagesLeft(page)`. Wtyczka stosuje tę samą interpretację rozdziałów co natywna stopka, również przy alternatywnym/ręcznym spisie treści i rozdziałach rozłożonych na kilka XHTML.
- Strona z tytułem następnego rozdziału jest wyłączona z pozostałych stron poprzedniego, zgodnie z natywnym licznikiem. Zmiana opcji KOReadera „uwzględnij aktualną stronę” wpływa na natywny wskaźnik rozdziału; licznik scen zachowuje opisaną wyżej stałą konwencję.
- Czas pochodzi z **Reading statistics → `getTimeForPages()`**, tego samego API co czas rozdziału. Włącz statystyki czytania. Po co najmniej trzech zmierzonych stronach w bieżącej książce używane jest jej zmierzone średnie tempo. Przedtem, przy wyłączonych statystykach lub nieważnym tempie widnieje `—`. Wtyczka odrzuca początkowe, sztucznie podstawiane przez KOReader tempo. Nie prowadzi drugiego systemu statystyk.

## Zgodność i ograniczenia

Sprawdzono źródła KOReadera na commitcie `79b24c0a3af7ea115f0bae3810855ed6328a1741`, koreader-base `51bc7096973bc8eab5f2fd6ca3ae9a0227c8905e` i CREngine `ab1981c22e4e67cf9d98be3c301736941d2d271c` (pobrane 17.10.2026). Wtyczka wymaga API dodatkowych treści stopki oraz metod CREngine użytych w [docs/API.md](docs/API.md). To test kompatybilności z konkretnym kodem źródłowym, nie gwarancja dla każdego starszego APK.

- Obsługiwany format: EPUB otwierany przez CREngine. W innych formatach licznik pozostaje nieaktywny. Uszkodzony EPUB lub błąd skanowania ukrywa licznik; KOReader nadal sam odpowiada za możliwość otwarcia uszkodzonej książki.
- **Częściowe renderowanie:** gdy KOReader po zmianie ustawień opóźnia pełne przeliczenie układu, numery stron i spis treści mogą być tymczasowo nieważne. Scene Progress ukrywa wtedy wynik i wraca po pełnym renderowaniu/przeładowaniu książki. Dla natychmiastowego przeliczenia można wyłączyć standardową opcję **Enable partial renderings** i ponownie otworzyć książkę. Wtyczka nie wymusza kosztownego renderowania w głównym wątku ani nie zmienia tego ustawienia użytkownika.
- Rozpoznawanie jest konserwatywną heurystyką. Niezaznaczony semantycznie przypis wyglądający dokładnie jak samodzielny akapit `*` jest nieodróżnialny od separatora. W takiej książce wyłącz pojedynczą gwiazdkę. Odrzucane są linki, `sup`, `sub`, `aside`, oznaczenia przypisów i ukryte elementy/ich przodkowie.
- Same puste akapity, dodatkowe marginesy i przypadkowe obrazy nie są automatycznie uznawane za podział sceny. Dla ozdobnika graficznego/niestandardowej klasy dodaj jej nazwę w ustawieniach. Dowolne znaki i CSS `::before`/`::after` generujące symbol bez jawnego elementu-klasy nie są obsługiwane.
- Opiera się na zserializowanym DOM-ie silnika, a nie własnym parserze źródłowego EPUB-a. Nietypowy lub niepoprawny eksport DOM może zakończyć analizę bez wyniku. Limit: 64 MiB zserializowanego DOM-u, 10 000 kandydatur, 4 MiB wyniku procesu i około 60 s analizy. Limit rozmiaru DOM-u jest sprawdzany po eksporcie przez silnik; bardzo duży EPUB nadal wymaga pamięci na ten eksport w procesie roboczym.
- Cache uwzględnia ścieżkę, rozmiar, mtime/ctime pliku, wersję DOM, hash renderowania, tryb przepływów/wyświetlania i reguły. Zmiana układu powoduje nową analizę. Przy zmianie zawartości otwartej książki z zewnątrz należy ją ponownie otworzyć.
- W ukrytych nieliniowych przepływach (np. osobno otwartych przypisach) licznik jest ukryty. Zwykły tekst używa liniowej numeracji stron bez ukrytych przepływów.
- Nie wykonano testu na fizycznym BOOX Palma 2 ani pełnego testu dotykowego interfejsu Androida. Testy silnika, API stopki, gettext, procesu POSIX i cyklu życia są automatyczne. Pomiary szybkości z komputera nie są pomiarami E-Ink.

## Budowa, testy i struktura

Nie ma zależności sieciowych ani binarnych wymaganych przez wtyczkę. Wszystkie używane biblioteki Lua/FFI dostarcza KOReader.

```text
sceneprogress.koplugin/
  _meta.lua, main.lua         integracja KOReader/menu/stopka/cykl życia
  sceneprogress/config.lua   ustawienia
  sceneprogress/detector.lua  reguły i odczyt eksportu DOM
  sceneprogress/index.lua     XPointer → strona, indeks i pozostałe strony
  sceneprogress/time.lua      natywne statystyki czasu
  sceneprogress/worker.lua    izolowany proces i nieblokujący odbiór wyniku
  sceneprogress/i18n.lua      katalog gettext wtyczki
  l10n/pl/                    polski PO i gotowy MO
tests/fixtures/               siedem EPUB-ów i uszkodzony plik testowy
```

Podstawowe testy wymagają Python 3, LuaJIT i GNU gettext (`msgfmt`, `xgettext`):

```sh
python3 tests/make_fixtures.py
python3 tools/check.py --lua luajit
luacheck --config .luacheckrc sceneprogress.koplugin tests
python3 tools/build.py
```

Testy z prawdziwym silnikiem, modułem `cre.cpp` i źródłami frontendu:

```sh
python3 tools/check.py --lua /ścieżka/do/luajit \
  --upstream /ścieżka/do/koreader \
  --cre-dir /katalog/z/cre.so \
  --font /ścieżka/do/testowej/czcionki.ttf
```

Dokładne kroki zbudowania środowiska testowego na macOS oraz uzyskane wyniki są w [docs/TESTS.md](docs/TESTS.md). Pakiet instalacyjny zawiera wyłącznie wtyczkę, instrukcję i licencję; nie zawiera silnika ani narzędzi programistycznych.

## Odinstalowanie

Zamknij KOReader, usuń `/storage/emulated/0/koreader/plugins/sceneprogress.koplugin/`, uruchom KOReader ponownie. Nie usuwaj katalogów `.sdr`: mogą zawierać Twoje zakładki. Pozostały klucz `sceneprogress_cache` w ustawieniach książki oraz globalny `sceneprogress` są nieaktywne i można je zostawić. W polu „Treści zewnętrzne” mogą nadal wyświetlać się inne wtyczki.

Licencja: AGPL-3.0-or-later.
