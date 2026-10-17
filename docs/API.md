# API i wybory implementacyjne

Zweryfikowane źródła (17.10.2026):

| Projekt | Commit |
| --- | --- |
| KOReader | `79b24c0a3af7ea115f0bae3810855ed6328a1741` |
| koreader-base | `51bc7096973bc8eab5f2fd6ca3ae9a0227c8905e` |
| CREngine | `ab1981c22e4e67cf9d98be3c301736941d2d271c` |

## ReaderFooter

[readerfooter.lua](https://github.com/koreader/koreader/blob/79b24c0a3af7ea115f0bae3810855ed6328a1741/frontend/apps/reader/modules/readerfooter.lua) udostępnia `addAdditionalFooterContent(content_func)` i `removeAdditionalFooterContent(content_func)`. Pierwsza metoda ustawia standardowe pole `additional_content`. Generator tego pola wywołuje callbacki i łączy ich wyniki z innymi elementami paska. Pusty wynik callbacka niczego nie wyświetla.

Scene Progress przechowuje jeden stabilny callback na instancję czytnika; usuwa dokładnie tę samą referencję po wyłączeniu i przy zamknięciu. Nie nadpisuje metod stopki ani jej tablicy generatorów. Do zgłoszenia zmiany używa zdarzenia `RefreshAdditionalContent`, którego handler wykonuje `maybeUpdateFooter()`. Po usunięciu callbacka wysyła także `UpdateFooter(true)`, zgodnie z przykładem [SSH.koplugin/main.lua](https://github.com/koreader/koreader/blob/79b24c0a3af7ea115f0bae3810855ed6328a1741/plugins/SSH.koplugin/main.lua).

Zmiana strony powoduje natywne `PageUpdate`/`PosUpdate` i ponowne wywołanie generatora. Nie ma dodatkowego timera repaintu, powiadomienia ani odrębnego widgetu. Wtyczka odświeża pole jawnie tylko przy zmianie stanu/ustawień. Pozostały rozdział nadal liczy standardowa stopka.

## CREngine: rzeczywiste pozycje

[credocument.lua](https://github.com/koreader/koreader/blob/79b24c0a3af7ea115f0bae3810855ed6328a1741/frontend/document/credocument.lua) opakowuje funkcje z [cre.cpp](https://github.com/koreader/koreader-base/blob/51bc7096973bc8eab5f2fd6ca3ae9a0227c8905e/cre.cpp):

- `getHTMLFromXPointer(".0", 0x4400)` eksportuje załadowane drzewo DOM, włącznie z węzłami `stylesheet` i znacznikami metody renderowania `~X`, `~K`, `~B`, `~F`, `~i`. `.0` jest wskaźnikiem korzenia używanym także w komentarzu diagnostycznym ReaderUI. Flagi są opisane w `lvtinydom.cpp`: `0x0400 = SHOW_REND_METHOD`, `0x4000 = INCLUDE_STYLESHEET_ELEMENT`.
- Na podstawie nazw elementów i numerów rodzeństwa powstają strukturalne ścieżki XPointer. Dla DOM ≥ `getDomVersionWithNormalizedXPointers()` liczniki i ścieżki pomijają silnikowe `autoBoxing`, `tabularBox`, `rubyBox`, `mathBox`, `floatBox`, `inlineBox`, `pseudoElem`, dokładnie jak `createXPointerV2()`/`toStringV2()`. Dla starszego DOM używane są ścieżki z tymi elementami. Gałęzie `cloneNode` nie dostarczają kandydatur.
- `getNormalizedXPointer()` oraz `isXPointerInDocument()` potwierdzają istnienie kandydata. To konieczne: samo `getPageFromXPointer()` zwraca **1 także dla nieprawidłowej pozycji**.
- `getPageFromXPointer()` mapuje zatwierdzoną pozycję na aktualną stronę silnika, a `getPageNumberInFlow()` zapewnia zgodność z ukrytymi nieliniowymi przepływami.
- Indeks jest posortowany po stronach. Callback stopki robi wyszukanie binarne pierwszej granicy na/po bieżącej stronie i ogranicza wynik do natywnego końca rozdziału.

Nie są potrzebne ZIP/XML-biblioteki ani odtwarzanie parsera EPUB: silnik już połączył pliki spine, rozwinął encje i zastosował style. Zachowane są oryginalne pozycje i prawdziwy spis treści. Użycie eksportu DOM wymaga niewielkiego parsera jego specyficznej składni, w tym atrybutów z `>` wewnątrz cudzysłowów. Nie jest to parser dowolnego XHTML.

Zbadano także `findText()` i `findAllText()`. W tym API odnalezione zakresy ustawiają zaznaczenie silnika, a wyszukiwanie tekstu nie pokrywa pustego `hr` i jawnych graficznych separatorów. Implementacja nie używa ich, nie przesuwa czytelnika i nie zmienia zaznaczenia. Nie używa `gotoPage()`, `gotoXPointer()` ani `highlightXPointer()`.

## Rozdział i czas

[ReaderToc:getChapterPagesLeft(page, true)](https://github.com/koreader/koreader/blob/79b24c0a3af7ea115f0bae3810855ed6328a1741/frontend/apps/reader/modules/readertoc.lua#L715) liczy wyrenderowane strony do następnej granicy TOC; wynik może być `nil` w ostatnim rozdziale. Wtedy stosowane jest `getTotalPagesLeft()`, tak samo jak w standardowej stopce. Nie ma założenia „rozdział = jeden XHTML”.

[ReaderStatistics:getTimeForPages()](https://github.com/koreader/koreader/blob/79b24c0a3af7ea115f0bae3810855ed6328a1741/plugins/statistics.koplugin/main.lua#L3025) korzysta z `avg_time` i formatu czasu użytkownika. Warunek trzech próbek odczytuje istniejące `book_read_pages + mem_read_pages`. Bez niego początkowe `avg_time = 0.5 * max_sec` byłoby myląco przedstawione jako zmierzone tempo. Nie ma własnych tabel czasu ani bazy danych.

## Reflow, cache i proces

`DocumentRerendered` unieważnia indeks i po krótkim opóźnieniu uruchamia analizę. Callback dodatkowo porównuje `getDocumentRenderingHash(true)` z hashem indeksu: `PageUpdate` bywa wysyłane przed zdarzeniem reflow, więc stary indeks nie może wtedy wyświetlić wartości. `DocumentPartiallyRerendered` ukrywa wynik, ponieważ sam KOReader uznaje wtedy numery stron za nieważne. Normalna automatyka KOReadera kończy taki stan przeładowaniem dokumentu.

Analiza używa istniejącego `ffi/util.runInSubProcess()` z kopią aktualnego silnika. Główny proces sprawdza `getNonBlockingReadSize()` i czyta co najwyżej 64 KiB w jednej iteracji. Kod nigdy nie wywołuje blokującego `readAllFromFD()` podczas oczekiwania. Wynik jest serializowany przez standardowy `string.buffer`; w potoku nie ma tekstu książki, tylko zatwierdzone XPointery, strony i typ separatora. Polling kończy się po odebraniu wyniku. Zmiana ustawień, reflow lub zamknięcie książki zabija zadanie, zamyka deskryptor i odpina polling. Krótkie, niezależne od obiektu czytnika zadanie zbiera zakończony proces przez `isSubProcessDone()`, zapobiegając zombie.

Generacja zadania uniemożliwia dostarczenie wyniku starej książki/układu do nowego czytnika. Cache przechowuje tylko jeden indeks na książkę w jej standardowych ustawieniach. Klucz zawiera tożsamość pliku, DOM, hash układu oraz reguły. Żaden z tych zapisów nie zmienia pliku EPUB.

## Lokalizacja

`i18n.lua` czyta własny katalog PO/MO przez standardowy loader `gettext.loadMO()`. KOReader ma singleton gettext, bez fabryki domen. Dlatego katalog ładowany jest raz, synchronicznie, do tymczasowego słownika; wszystkie zmienione referencje singletonu są przywracane przed zwrotem. Nie ma w tym miejscu yield ani zdarzeń UI. Wywołanie `gettext.lua` ponownie przez `dofile` jest błędne: próbuje ponownie zadeklarować struktury FFI. Test korzysta z rzeczywistego loadera KOReadera i sprawdza zachowanie globalnego katalogu.
