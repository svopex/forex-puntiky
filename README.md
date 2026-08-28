# Sved Channel Breakout — strategie pro MetaTrader 5

Expert Advisor pro MT5 (verze 1.10), který detekuje ABCD kanály na M15, kreslí je
do grafu a obchoduje průrazy swingových H1 úrovní uvnitř těchto kanálů. Vstup se
vyhodnocuje na M1. Do grafu vykresluje **pouze kanály, reliéfní přímky
a informace o vstupu** — žádné jiné indikátory ani pomocnou grafiku.

Testovací prostředí: RoboForex MT5, demo účet `67205475`, ticker `XAUUSD`.

## Jak strategie funguje

### Kanály (timeframe M15)

1. Z historie **uzavřených** M15 svíček (`InpLookbackBars`) se sestaví zig‑zag
   kostra trhu — střídavé swingové vrcholy a dna. Pivot je svíčka, jejíž high
   (resp. low) je extrémem v okně `InpSwingDepth` svíček na každou stranu; levé
   rameno musí být striktně nižší, pravé smí být rovné, aby ploché vrcholy nedávaly
   duplicitní pivoty. Dva stejné typy za sebou se sloučí do extrémnějšího. Kostra
   se hledá opakovaně v několika měřítkách (`InpSwingScales`) s postupně
   dvojnásobným oknem (3, 6, 12 svíček) — jemné okno najde malé kanály, hrubé velké.
   Právě tím vzniká **kanál v kanálu**.
2. Z každé dvojice swingů stejného typu (**A** a **C**) vzniká kandidát na kanál —
   mezi nimi smí ležet další swingy (odstup až `InpMaxSwingGap` swingů). Jako **B**
   se bere protilehlý swing **nejdál od základní úsečky** — měří se odstup od šikmé
   čáry, ne absolutní cena, protože cenově nejnižší swing nemusí být ten, který
   rovnoběžku odtlačí nejdál. Šířka kanálu = odstup bodu B od základní úsečky.
   - A a C jsou **dna** → základní čárou je **LOW úsečka** vedená body A–C,
     horní hrana je její rovnoběžka procházející bodem B,
   - A a C jsou **vrcholy** → základní čárou je **HIGH úsečka**, spodní hrana je
     rovnoběžka bodem B.
3. Body **D, E, F, G …** jsou další potvrzené dotyky hran za bodem C. Kreslí se
   **až ve chvíli, kdy k dotyku skutečně dojde** — nic se nepredikuje dopředu.
   Dotyky se střídají: A a C leží na základní úsečce, B na protější, takže D se
   čeká na protější hraně vůči C, E zase na základní a tak dál. Z jedné dotykové
   epizody se bere její nejzazší svíčka. Maximálně se sleduje 8 bodů (D až K).
4. Kanál musí cenu **obalovat a nesmí být proražený**. Kontroluje se celý úsek od
   bodu A až po poslední svíčku, přičemž obě hrany se posuzují **různě**, protože
   mají jiný význam:

   - **Základní úsečka** (nese body A a C) nesmí být proříznutá nikdy — ani za
     bodem C, tolerance je vždy jen `InpPierceTolFrac` (5 % šířky). Když ji
     pozdější swing protne, není to invalidace kanálu, ale znamení, že je úsečka
     vedená špatně: **C patří na ten pozdější extrém**. Kandidát vypadne a projde
     jiný, s posunutým C — a tím se automaticky srovná i sklon protější hrany,
     protože je to rovnoběžka.
   - **Protější hrana** (rovnoběžka bodem B) musí držet přísně (5 %) jen mezi
     A a C. Za bodem C se toleruje `InpInvalidTolFrac` (15 % šířky); větší
     překročení znamená **proražený, tedy neplatný kanál** — vypadne z kandidátů
     a přestane se kreslit i obchodovat.
   - Základní úsečka se navíc kontroluje i `InpBackCheckBars` svíček **před** bodem
     A, aby ji zleva neprorážel dřívější extrém.
5. Opory **A a C musí být cenově nejvýraznějším extrémem** v okně
   ±`InpAnchorWindow` svíček — v okolí nesmí ležet vyšší vrchol (u HIGH základny),
   resp. hlubší dno (u LOW základny). To je jiná podmínka než nepřeříznutá úsečka:
   úsečka je šikmá, takže sousední vrchol může být cenově výš a přitom pořád **pod**
   prodlouženou čárou. Bez této kontroly by úsečka začínala na druhém nejvyšším
   vrcholu místo na tom nejvyšším.
6. Kanál se ohodnotí a musí projít filtry, aby byl považován za *hlavní a důležitý*:
   - minimální délka A→C (`InpMinSpanBars`) a maximální stáří bodu C (`InpMaxAgeBars`),
   - minimální šířka v bodech i v násobcích ATR (`InpMinWidthPoints`,
     `InpMinWidthATR`; ATR s periodou `InpATRPeriod` na TF kanálu),
   - minimální počet dotyků obou hran (`InpMinTouches`) — dotyk je high/low
     v pásmu `InpTouchTolFrac` × šířka kolem hrany, dotyky blíž než 3 svíčky
     se počítají jako jeden,
   - minimální podíl svíček uzavřených uvnitř kanálu (`InpMinContainment`),
   - volitelně musí být aktuální close stále uvnitř kanálu (`InpRequireInside`).
7. Skóre kanálu: `containment × 6 + min(dotyky, 15) + min(délka / InpMinSpanBars, 6)
   + min(šířka / ATR, 6) × 0,6 − min(stáří / InpMaxAgeBars, 1) × 2`. Váhy jsou
   voleny tak, aby se složky rychle nesečetly do stropu — jinak by měly všechny
   slušné kanály stejné skóre a výběr hlavního kanálu by byl náhodný.
8. Výběr hlavních kanálů probíhá dvoufázově: nejprve se vezme nejlepší kanál
   z **každého** měřítka (to zaručí, že se vedle velkého kanálu vykreslí i vnořený
   menší), teprve pak se zbylá místa do `InpMaxChannels` doplní podle skóre.
   Prakticky totožné kanály se zahazují — hrany se porovnávají ve **dvou** časových
   okamžicích (poslední svíčka a 50 svíček zpět, práh `InpDedupFrac` × šířka),
   aby se stoupající a klesající kanál, které se právě protínají, chybně nesloučily.
   **Kanál v kanálu zůstává zachován** — zahazují se jen kanály, jejichž obě hrany
   leží prakticky na sobě. Výsledek se seřadí podle skóre; kanál 1 je hlavní.

### Úrovně průrazu (timeframe H1)

- Úrovně průrazu = **HIGH posledního swingového vrcholu a LOW posledního swingového
  dna na H1**, které cena **ještě neprorazila** (o víc než `InpBreakoutBuffer`).
  Nestačí tedy libovolná hodinová svíčka — musí jít o svíčku, která je zároveň
  swingem (lokální extrém v okně `InpBreakSwingDepth` svíček na každou stranu).
  Swing je potvrzený až svíčkami za ním, takže úroveň je o pár hodin zpožděná —
  to je záměr, ne chyba. Prohledává se `InpBreakLookback` uzavřených H1 svíček.
- Proražená úroveň je spotřebovaná, takže se pokračuje k předchozímu swingu —
  typicky výraznějšímu, který je pořád platnou hranicí. Průraz se hlídá na
  **každém ticku**; jakmile úroveň padne, hledá se další okamžitě, nečeká se na
  otevření další H1 svíčky.
- Po startu experta (nebo restartu) se z M1 historie zpětně dohledá, jestli cena
  úroveň neprorazila už dřív — od konce swingové svíčky do současnosti. Bez toho
  by expert oživil dávno spotřebované úrovně a zadal na ně příkazy.
- Na jedné swingové úrovni se obchoduje **nejvýše jednou**; příznaky
  „obchodováno“ a „proraženo“ se resetují až ve chvíli, kdy vznikne nový swing.
- Směr je **zablokovaný**, dokud cena nebyla na správné straně úrovně (pod HIGH pro
  BUY, nad LOW pro SELL) — zabraňuje vstupu do už proběhlého pohybu (gap, start EA
  uprostřed pohybu).
- Vypnutím `InpUseSwingLevels` se strategie vrátí k prostému high/low poslední
  uzavřené H1 svíčky.

### Vstup (vyhodnocení M1)

Průraz musí nastat **uvnitř** některého z detekovaných kanálů (tolerance
`InpInsideTolFrac` × šířka; při více kanálech se bere ten s nejlepším skóre),
jinak se signál zahodí. Režim vstupu určuje `InpEntryMode`:

- **`SVED_ENTRY_PENDING` (výchozí)**: BuyStop a SellStop se umístí přímo na
  swingové úrovně (± `InpBreakoutBuffer`) se SL a PT z návrhu vstupu, platnost GTC.
  Zadají se hned po nahození experta a přepočítají se (zrušit a zadat znovu)
  s každou novou M15 svíčkou (posunuly se hrany kanálu, takže SL i PT už
  neodpovídají), s každou novou H1 svíčkou a kdykoli se **změní platnost návrhu**
  (např. do cesty vstoupila reliéfní přímka nebo naopak zmizela). Příkaz se zadá
  jen tehdy, je-li úroveň dál od trhu než stop-level brokera. Po otevření pozice
  se zbylý příkaz zruší (OCO).
- **`SVED_ENTRY_M1_CLOSE`**: čeká na uzavření M1 svíčky za úrovní (o
  `InpBreakoutBuffer` bodů) a vstupuje tržním příkazem — v terminálu tedy do
  vstupu není vidět žádný příkaz. Vstupuje se jen na **skutečném přechodu** přes
  úroveň (předchozí M1 close musí být ještě na druhé straně), aby expert
  nevstoupil dlouho po průrazu — třeba až potom, co pominula překážka v podobě
  reliéfní přímky. Po vyplnění se SL a PT dorovnají na skutečnou plnicí cenu,
  aby poměr zůstal přesně 1:1.

Společné pro oba režimy:

- Vyplnění příkazu se zachytává v `OnTradeTransaction`, takže o něm expert ví
  i v případě, že pending příkaz vyplnil broker bez jeho přičinění; návrhy se
  hned přepočítají a druhý příkaz se zruší.
- Návrh vstupu se přestane nabízet, jakmile **běží pozice** (`InpMaxPositions`),
  když už se **na dané swingové úrovni obchodovalo**, nebo když **úroveň už byla
  proražena**. Když cena úrovní právě prochází, není co prorazit a STOP příkaz
  nad/pod trhem by stejně nešlo zadat — takový návrh se nekreslí do grafu ani
  nenabízí v panelu (`průraz už proběhl`).
- Směry lze jednotlivě vypnout (`InpAllowBuy`, `InpAllowSell`); `InpEnableTrading
  = false` nechá experta jen kreslit. Při `InpAllowedAccount ≠ 0` a jiném čísle
  účtu se obchodování vypne (kreslení zůstává). Obchoduje se jen při povoleném
  algoritmickém obchodování v terminálu i na účtu.

### Reliéfní přímky (timeframe M1)

Reliéfní přímka je trendlinie vedená dvěma **hlavními swingy stejného typu** na
vstupním timeframu — dvěma vrcholy (odpor) nebo dvěma dny (podpora). Stojí průrazu
v cestě, takže ji strategie hlídá při plánování vstupu.

1. Swingy se hledají z `InpReliefLookback` uzavřených M1 svíček s hrubším oknem
   (`InpReliefSwingDepth`, výchozí 10 svíček) a v několika měřítkách
   (`InpReliefScales`, výchozí 4 → okna 10/20/40/80 svíček). Jemné okno dá čerstvé
   lokální přímky, hrubé vidí jen hlavní vrcholy/dna, takže i přes omezený odstup
   opor (`InpReliefSwingGap` swingů) dosáhne na vzdálené swingy — vějíř trendlinií
   z hlavních vrcholů.
2. Přímka musí cenu **obalovat** — posuzuje se ale stejně, jako když se trendline
   kreslí ručně: **tělo svíčky ji nesmí překročit** o víc než `InpReliefPierceTol`,
   zatímco **knot ji smí přesáhnout** až o `InpReliefWickTol` — ale **jen mezi
   oporami**; prostřel knotem uvnitř útvaru trendline neruší. **Za druhou oporou
   je přímka tvrdá hranice**: i knot přes ni (nad `InpReliefPierceTol`) znamená
   nový extrém — přímka přestává platit a kotva patří na novou svíčku. Tělo za
   přímkou = proražení kdykoli; **proražená přímka už není překážkou** a mezi
   kandidáty se nedostane.
3. Musí mít délku aspoň `InpReliefMinSpan` svíček a aspoň `InpReliefMinTouches`
   potvrzených dotyků (tolerance `InpReliefTouchTol`, dotyky blíž než 3 svíčky se
   počítají jako jeden). Volitelně (`InpReliefMidTouch`) se vyžaduje i dotyk
   v prostřední části přímky (`InpReliefMidFrom`–`InpReliefMidTo` délky, tolerance
   `InpReliefMidTol`) — krajní dotyky má z definice každá přímka, takže samy
   o sobě nic nedokazují.
4. Přímka nesmí od své druhé opory **ujet dál než `InpReliefMaxDrift`** a platí
   jen `InpReliefMaxAge` násobek vlastní délky za druhou oporou (0 = neomezeno).
   Strmá čára se jinak za pár hodin vzdálí desítky dolarů od ceny, kde už se
   ničeho nedotýká — to není reliéf, ale artefakt prodloužení.
5. Z přímek **se stejnou první oporou a směrem** se drží jen ta nejlepší: přednost
   má **skutečná tečna** (nejmenší přesah knotů — přímka má procházet špičkami
   svíček, ne je řezat), pak víc dotyků, menší průměrné přilnutí k ceně a delší
   záběr. Přímka klenoucí se přes údolí mezi dvěma vzdálenými swingy je přitom
   pořád platná — přilnutí není filtr, jen rozhodčí mezi variantami.
6. Přímky se ohodnotí (`dotyky × 2 + délka / 100 − stáří / 200`) a ponechá se
   nejvýše `InpMaxReliefLines` nejvýznamnějších; přímky stejného typu, které se na
   poslední svíčce liší o méně než `InpReliefDedupTol`, se sloučí. Při výběru se
   **střídají odpory a podpory**, aby jeden typ neobsadil všechny sloty.

Když leží přímka ve směru obchodu **blíž než plánovaný PT**, rozhoduje
`InpReliefMode`:

| Režim | Chování |
|---|---|
| `SVED_RELIEF_SKIP` (výchozí) | vstup se přeskočí, důvod se vypíše v panelu |
| `SVED_RELIEF_SHORTEN` | PT se zkrátí před přímku (mínus `InpReliefBuffer`), SL stejně — RRR zůstává 1:1 |

Přímky se přepočítávají s každou novou M1 svíčkou a kreslí se do grafu tečkovaně
(`InpColorRelief`), prodloužené o `InpReliefForwardBars` svíček doprava.

### Délka vstupu a stopy

- Základní délka vstupu je **300 bodů** (`InpMaxEntryPoints`), SL : PT = **1 : 1**.
  Zadání uvádí strop 450 bodů, výchozí hodnota je nastavená níž.
- Pokud je nejbližší hrana kanálu ve směru obchodu blíž, PT se zkrátí tak, aby se
  před ni vešel (mínus rezerva `InpEdgeBuffer`), a SL se zkrátí stejně — **RRR
  zůstává 1:1**.
- Hledají se hrany **všech** aktivních kanálů, takže cílem může být i hrana menšího
  kanálu vnořeného do většího.
- Protože jsou hrany šikmé, bere se konzervativnější hodnota z času vstupu a z času
  projekce o `InpEdgeProjBars` svíček dopředu.
- Když je místa méně než `InpMinEntryPoints`, nebo délka nepřesahuje stop-level
  brokera, obchod se neotevře a důvod se zobrazí v panelu.
- Objem: výchozí je dopočet z rizika (`InpLotMode = SVED_LOT_RISK`: ztráta na SL
  = `InpRiskPercent` % zůstatku, výchozí 1 %) nebo pevný lot (`SVED_LOT_FIXED`, `InpFixedLot`).
  Lot se zaokrouhlí dolů na krok objemu a ořízne do rozsahu symbolu.

### Stavy a důvody zamítnutí v panelu

Řádek `stav:` ukazuje pro každý směr `připraven` / `blokován` (cena ještě nebyla
na správné straně úrovně) / `obchodován` / `nelze (důvod)`. Možné důvody:

| Důvod | Význam |
|---|---|
| `pozice již otevřena` | běží pozice strategie (`InpMaxPositions`) |
| `tato úroveň už obchodována` | na aktuálním swingu už proběhl vstup |
| `úroveň už byla proražena` | cena úroveň prorazila (i intrabar), čeká se na nový swing |
| `průraz už proběhl` | cena je právě za úrovní, STOP příkaz nelze zadat |
| `žádný platný kanál` | žádný kanál neprošel filtry |
| `průraz mimo kanál` | úroveň neleží uvnitř žádného kanálu |
| `v cestě reliéfní přímka (N b, cena)` | přímka blíž než PT, režim SKIP |
| `málo místa k hraně / reliéfní přímce (N b)` | zbývá méně než `InpMinEntryPoints` |
| `délka pod stop-level brokera` | SL/PT by byly blíž, než broker dovolí |
| `nelze určit objem` | výpočet lotu selhal |

### Co se kreslí do grafu

| Objekt | Význam |
|---|---|
| HIGH úsečka (`InpColorHigh`, výchozí Tomato) | horní hrana kanálu, prodloužená doprava (`InpForwardBars`, ray) |
| LOW úsečka (`InpColorLow`, výchozí DodgerBlue) | spodní hrana kanálu, prodloužená doprava |
| A1, B1, C1, D1 … (`InpColorPoint`) | opory kanálu; číslice udává, ke kterému kanálu bod patří |
| D, E, F, G … | potvrzené dotyky hran za bodem C, kreslené až po jejich vzniku |
| Čárkované čáry (`InpColorBreak`, Goldenrod) | úrovně průrazu; čára začíná u swingové svíčky, ze které pochází |
| Tečkované čáry (`InpColorEntry` / `InpColorSL` / `InpColorTP`) | plánovaný vstup, SL a PT pro oba směry, s popisky `SL` / `PT` |
| Tečkované čáry (`InpColorRelief`, MediumOrchid) | reliéfní přímky z hlavních M1 swingů |
| Panel vlevo nahoře | hlavička, přehled kanálů, úrovně průrazu, reliéf, stav směrů, návrhy vstupu, pozice / pending, poslední událost |

Popisky sdílené opory se slučují (`E1 E3`), panel uhýbá one-click SELL/BUY panelu
a obnovuje se každou sekundu i bez ticků. Hlavní kanál (nejvyšší skóre) se kreslí
silnější čarou než ostatní. Všechny objekty mají prefix `SVED_`, jsou nevybíratelné
a mají tooltip s popisem; při odebrání experta se smažou jen tyto objekty.

## Instalace

```
scripts\deploy.cmd
```

Skript zkopíruje zdrojové soubory do datového adresáře terminálu a zkompiluje je
MetaEditorem. Pro jiného brokera lze předat `-Broker "IC Markets"`, pro pouhé
zkopírování bez kompilace `-NoCompile`.

`deploy.cmd` je jen obálka nad `deploy.ps1` — obchází výchozí ExecutionPolicy,
která na Windows spouštění `.ps1` souborů blokuje. Přímé volání skriptu proto
vyžaduje `powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1`.

Po nasazení v terminálu:

1. **Nástroje → Volby → Expert Advisors** → povolit algoritmické obchodování.
2. Otevřít graf `XAUUSD` (libovolný timeframe, kanály se kreslí podle `InpChannelTF`).
3. Přetáhnout `Experts\Sved\SvedChannelBreakout` na graf.
4. Zkontrolovat řádek v Expert logu s přepočtem bodů na cenu — u zlata se počet
   desetinných míst mezi brokery liší. Při `digits = 3` je potřeba nastavit
   `InpMaxEntryPoints = 3000`, aby délka vstupu odpovídala 3,00 USD.

## Struktura projektu

```
MQL5/
  Experts/Sved/SvedChannelBreakout.mq5   hlavní EA — vstupy, úrovně průrazu, obchodování, panel
  Include/Sved/SvedTypes.mqh             datové struktury a výčtové typy
  Include/Sved/SvedSwings.mqh            detekce swingových bodů (zig-zag)
  Include/Sved/SvedChannels.mqh          stavba, hodnocení a výběr kanálů, hledání hran
  Include/Sved/SvedRelief.mqh            reliéfní přímky na vstupním TF
  Include/Sved/SvedDraw.mqh              vykreslování kanálů, popisků, úrovní a panelu
scripts/deploy.cmd                       spouštěč (obchází ExecutionPolicy)
scripts/deploy.ps1                       kopie do terminálu + kompilace
```

## Přehled parametrů

### Timeframy
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpChannelTF` | M15 | detekce a kreslení kanálů |
| `InpBreakoutTF` | H1 | svíčka, jejíž high/low se prorážejí |
| `InpEntryTF` | M1 | vyhodnocení průrazu a reliéfní přímky |

### Úrovně průrazu
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpUseSwingLevels` | true | prorážet jen swingové H1 svíčky |
| `InpBreakSwingDepth` | 2 | šířka okna pro H1 swingy |
| `InpBreakLookback` | 300 | kolik H1 svíček se prohledává |

### Detekce kanálů
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpLookbackBars` | 1500 | kolik M15 svíček se analyzuje |
| `InpSwingDepth` | 3 | základní šířka okna pro swingy |
| `InpSwingScales` | 3 | počet měřítek detekce (kanál v kanálu) |
| `InpMaxSwingGap` | 16 | kolik swingů smí ležet mezi A a C |
| `InpMinSpanBars` | 20 | minimální délka A→C |
| `InpMaxAgeBars` | 300 | maximální stáří bodu C |
| `InpMinWidthPoints` | 300 | minimální šířka kanálu v bodech |
| `InpMinWidthATR` | 1.5 | minimální šířka v násobcích ATR |
| `InpATRPeriod` | 14 | perioda ATR pro filtr šířky |
| `InpMinTouches` | 4 | minimální počet dotyků hran |
| `InpTouchTolFrac` | 0.15 | tolerance dotyku jako zlomek šířky |
| `InpMinContainment` | 0.85 | minimální podíl svíček uvnitř |
| `InpMaxChannels` | 3 | kolik kanálů se ponechá |
| `InpPierceTolFrac` | 0.05 | kolik smí cena prořezávat hranu (zlomek šířky) |
| `InpInvalidTolFrac` | 0.15 | za jakým přesahem protější hrany za C je kanál invalidovaný |
| `InpBackCheckBars` | 20 | kolik svíček před bodem A se ještě kontroluje |
| `InpAnchorWindow` | 5 | okno, ve kterém musí být A a C nejvýraznějším extrémem |
| `InpDedupFrac` | 0.25 | práh, kdy se dva kanály považují za totožné |
| `InpRequireInside` | true | kanál platí jen když je v něm aktuální cena |

### Vstup
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpEnableTrading` | true | false = jen kreslení bez obchodů |
| `InpEntryMode` | PENDING | pending STOP příkazy vs. potvrzení uzavřením M1 |
| `InpMaxEntryPoints` | 300 | maximální délka vstupu |
| `InpMinEntryPoints` | 100 | pod touto délkou se nevstupuje |
| `InpBreakoutBuffer` | 10 | buffer za úrovní průrazu |
| `InpEdgeBuffer` | 20 | rezerva PT před hranou kanálu |
| `InpEdgeProjBars` | 12 | o kolik svíček dopředu se hrany promítají |
| `InpInsideTolFrac` | 0.02 | tolerance testu „úroveň uvnitř kanálu“ (zlomek šířky) |
| `InpAllowBuy` / `InpAllowSell` | true / true | povolení jednotlivých směrů |
| `InpMaxPositions` | 1 | maximální počet současných pozic |
| `InpSlippage` | 20 | maximální skluz tržního příkazu (body) |
| `InpMagic` | 67205475 | magic number |
| `InpAllowedAccount` | 0 | 0 = bez omezení, jinak povolený účet |

### Reliéfní přímky
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpUseRelief` | true | hlídat reliéfní přímky |
| `InpReliefMode` | SKIP | přeskočit vstup / zkrátit PT |
| `InpReliefLookback` | 2400 | kolik M1 svíček se analyzuje |
| `InpReliefSwingDepth` | 10 | šířka okna pro hlavní swingy |
| `InpReliefScales` | 4 | počet měřítek swingů (10/20/40/80) |
| `InpReliefSwingGap` | 20 | max. odstup opor (počet swingů) |
| `InpReliefMinSpan` | 30 | minimální délka přímky ve svíčkách |
| `InpReliefMinTouches` | 2 | minimální počet dotyků |
| `InpReliefPierceTol` | 10 | proříznutí přímky tělem svíčky (body) |
| `InpReliefWickTol` | 150 | povolený přesah přímky knotem mezi oporami (body) |
| `InpReliefTouchTol` | 25 | tolerance dotyku (body) |
| `InpReliefDedupTol` | 40 | práh shody dvou přímek (body) |
| `InpReliefMaxAge` | 0.0 | platnost přímky za 2. oporou v násobcích délky (0 = neomezeno) |
| `InpReliefMaxDrift` | 1200 | max. vzdálení přímky od 2. opory (body) |
| `InpReliefMidTouch` | false | vyžadovat dotyk i uprostřed přímky |
| `InpReliefMidTol` | 60 | tolerance středního dotyku (body) |
| `InpReliefMidFrom` / `InpReliefMidTo` | 0.20 / 0.80 | prostřední úsek přímky |
| `InpMaxReliefLines` | 6 | kolik přímek ponechat |
| `InpReliefBuffer` | 20 | rezerva PT před přímkou (body) |
| `InpReliefForwardBars` | 120 | prodloužení přímek doprava (M1 svíčky) |

### Objem
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpLotMode` | RISK | pevný lot / dopočet z rizika |
| `InpFixedLot` | 0.10 | pevný objem |
| `InpRiskPercent` | 1.0 | riziko na obchod v % zůstatku (režim RISK) |

### Zobrazení
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpShowChannels` | true | kreslit kanály |
| `InpShowPoints` | true | kreslit opory A B C D … |
| `InpShowBreakLevels` | true | kreslit úrovně průrazu |
| `InpShowEntryLevels` | true | kreslit úrovně plánovaného vstupu |
| `InpShowRelief` | true | kreslit reliéfní přímky |
| `InpShowPanel` | true | zobrazit informační panel |
| `InpForwardBars` | 30 | prodloužení kanálů doprava (M15 svíčky) |
| `InpColorHigh` / `InpColorLow` | Tomato / DodgerBlue | barvy HIGH a LOW úsečky |
| `InpColorPoint` | Silver | barva popisků opor |
| `InpColorBreak` | Goldenrod | barva úrovní průrazu |
| `InpColorRelief` | MediumOrchid | barva reliéfních přímek |
| `InpColorEntry` / `InpColorSL` / `InpColorTP` | White / OrangeRed / LimeGreen | barvy úrovní vstupu, SL a PT |
| `InpColorPanel` | White | barva textu panelu |
| `InpPanelX` / `InpPanelY` | 12 / 22 | odsazení panelu v pixelech |
| `InpPanelFontSize` | 9 | velikost písma panelu (Consolas) |
| `InpPanelLineHeight` | 20 | výška řádku panelu v pixelech (0 = podle písma) |
| `InpPanelOneClickShift` | 130 | posun panelu pod SELL/BUY okno MT5 |
| `InpPointFontSize` | 10 | velikost písma popisků opor |
| `InpLabelMergeATR` | 0.5 | sloučení blízkých popisků (násobek ATR) |

### Diagnostika
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpDiagnostics` | true | výpis detekce kanálů a reliéfu do Expert logu |
| `InpShotOnRequest` | true | snímek grafu na vyžádání (viz níže) |
| `InpShotEveryBars` | 0 | snímek každých N svíček TF kanálu (0 = vypnuto) |
| `InpShotFileName` | SvedShot.png | soubor snímku v `MQL5\Files` |
| `InpShotRequestFile` | SvedShot.request | soubor požadavku o snímek |

Při zapnuté diagnostice se s každým přepočtem kanálů (nová M15 svíčka) zapíše
do Expert logu, kolik kandidátů padlo na kterém filtru (bod B, délka, stáří,
šířka, opory, proříznutí, dotyky, uvnitř, cena mimo), rozpis opor a metrik
vybraných kanálů a totéž pro reliéfní přímky. Z rozložení zamítnutí je hned
vidět, který práh je úzkým hrdlem.

Snímek grafu si lze vyžádat kdykoliv — stačí v `MQL5\Files` vytvořit prázdný
soubor `SvedShot.request`. Expert ho do sekundy zpracuje (kontrola běží
v timeru), uloží `MQL5\Files\SvedShot.png` a požadavek smaže.

## Poznámky a omezení

- Kanály, H1 swingy i reliéfní přímky se počítají jen z **uzavřených** svíček,
  takže se uvnitř rozpracované svíčky nemění a nepřekreslují se zpětně. Jedinou
  výjimkou je hlídání průrazu úrovně, které běží na každém ticku.
- Výchozí filtry jsou nastavené konzervativně, aby prošly opravdu jen výrazné
  kanály. Pokud se na grafu nekreslí nic, sniž `InpMinTouches` na 3 nebo
  `InpMinContainment` na 0.80 — diagnostika v logu ukáže, který filtr brzdí.
- Body se popisují písmenem a číslem kanálu (`A1`, `B1`, `C1`, `D1` … pro první
  kanál, `A2`, `B2` … pro druhý), takže je vidět, co ke kterému kanálu patří.
  Číslování odpovídá pořadí v panelu; kanál 1 je hlavní a kreslí se silnější čarou.
  Popisky A a C se kreslí vně kanálu na straně základní úsečky, B na protější.
- Když je jedna svíčka oporou víc kanálů, popisky by se překrývaly. Proto se
  nejdřív sesbírají ze všech kanálů a ty, které padnou na stejné místo (stejná
  svíčka, stejná strana, cena blíž než `InpLabelMergeATR` × ATR), se sloučí do
  jednoho textu — např. `E1 E3`.
- Panel se automaticky posune o `InpPanelOneClickShift` pixelů níž, pokud je
  v grafu zapnutý one-click SELL/BUY panel MetaTraderu, aby se s ním nepřekrýval.
- Úrovně průrazu se aktualizují jen tehdy, když se podaří najít **oba** neproražené
  swingy (vrchol i dno); jinak zůstávají poslední známé hodnoty.
- Strategie nemá časový filtr obchodních hodin ani filtr zpráv — pokud jsou
  potřeba, je to samostatné rozšíření.
