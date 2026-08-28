# Puntiky Channel Breakout — strategie pro MetaTrader 5

Expert Advisor pro MT5 (verze 1.13), který detekuje ABCD kanály na M15, kreslí je
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
   duplicitní pivoty. Dva stejné typy za sebou se sloučí do extrémnějšího.
   Svíčka, která je pivotem **obou** typů zároveň (outside bar), přispěje do kostry
   **oběma** extrémy — dřív se zapsal jen jeden a skutečný vrchol (nebo dno) tak
   z kostry zmizel, takže úroveň průrazu sedla na nižší swing. Kostra
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
     se počítají jako jeden. **Opory A, B a C se nepočítají** — leží na hranách
     z definice, takže by každý kanál dostal tři dotyky zadarmo; parametr tedy
     říká, kolik dotyků má kanál mít *navíc* nad rámec vlastních opor. Opora
     zároveň uzavírá dotykovou epizodu, takže se místo ní nezapočítá svíčka
     hned vedle ní,
   - minimální podíl svíček uzavřených uvnitř kanálu (`InpMinContainment`;
     „uvnitř“ znamená close v pásmu `InpInsideTolFrac` × šířka kolem hran —
     stejná tolerance jako u testu úrovně průrazu),
   - volitelně musí být aktuální close stále uvnitř kanálu (`InpRequireInside`,
     tatáž tolerance).
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
  otevření další H1 svíčky — do testu proražení vstupuje i **právě otevřená**
  H1 svíčka, ne jen ty uzavřené.
- Průraz se posuzuje proti ceně, za kterou se daný směr **skutečně plní**: graf
  i historie jsou v BID, ale BuyStop se plní za ASK, takže se u nákupu k ceně
  přičítá spread. Bez toho se BUY při širokém spreadu plnil ještě *pod* úrovní
  a žádná svíčka průraz nezaznamenala.
- Obě strany se aktualizují **samostatně**: když se pro jeden směr žádný
  neproražený swing nenajde (v silném trendu jsou všechny starší vrcholy
  proražené), druhá strana se přesto přepočítá.
- Na jedné swingové úrovni se obchoduje **nejvýše jednou**. Spotřebovaná úroveň
  se ukládá do globální proměnné terminálu (`PUNTIKY_<symbol>_<magic>_BUY` / `_SELL`),
  takže to přežije i restart terminálu — dřív se po restartu tatáž úroveň
  obchodovala podruhé.
- Směr je **zablokovaný**, dokud cena nebyla na správné straně úrovně (pod HIGH pro
  BUY, nad LOW pro SELL) — zabraňuje vstupu do už proběhlého pohybu (gap, start EA
  uprostřed pohybu).
- Vypnutím `InpUseSwingLevels` se strategie vrátí k prostému high/low poslední
  uzavřené H1 svíčky.

### Vstup (vyhodnocení M1)

Průraz musí nastat **uvnitř** některého z detekovaných kanálů (tolerance
`InpInsideTolFrac` × šířka; při více kanálech se bere ten s nejlepším skóre),
jinak se signál zahodí. Režim vstupu určuje `InpEntryMode`:

- **`PUNTIKY_ENTRY_PENDING` (výchozí)**: BuyStop a SellStop se umístí přímo na
  swingové úrovně (± `InpBreakoutBuffer`) se SL a PT z návrhu vstupu, platnost GTC.
  Zadají se hned po nahození experta. Dál se **nerušily a nezadávaly znovu**, ale
  srovnávají se s návrhem: expert najde svůj příkaz podle magic a typu a sáhne na
  něj jen tehdy, když se liší cena, SL, PT nebo objem (`OrderModify`; při změně
  objemu se příkaz zadá znovu). Rekonciliace běží nejvýš jednou za tick a jen po
  přepočtu návrhu, tedy s každou M1 svíčkou, s novou M15/H1 svíčkou a při každé
  změně úrovní. Tím se zároveň propíše každá změna SL/PT/objemu do už ležícího
  příkazu — dřív se ležící příkaz aktualizoval jen tehdy, když návrh změnil
  *platnost*, takže mohl nést PT za reliéfní přímkou, kterou měl obcházet.
  Neúspěšné zrušení příkazu se loguje a nový příkaz se v takovém případě nezadá
  (dřív vedle sebe mohly zůstat dva identické příkazy a expozice byla dvojnásobná);
  příkaz uvnitř freeze zóny brokera se nechá být a zkusí se při dalším přepočtu.
  Příkaz se zadá jen tehdy, je-li úroveň dál od trhu než stop-level brokera —
  jinak je návrh označený jako neproveditelný a důvod je vidět v panelu.
  Po otevření pozice se zbylý příkaz zruší (OCO), a to až při dosažení
  `InpMaxPositions` — s `InpMaxPositions = 2` tedy může běžet i druhý směr.
- **`PUNTIKY_ENTRY_M1_CLOSE`**: čeká na uzavření M1 svíčky za úrovní (o
  `InpBreakoutBuffer` bodů) a vstupuje tržním příkazem — v terminálu tedy do
  vstupu není vidět žádný příkaz. Vstupuje se jen na **skutečném přechodu** přes
  úroveň (předchozí M1 close musí být ještě na druhé straně), aby expert
  nevstoupil dlouho po průrazu — třeba až potom, co pominula překážka v podobě
  reliéfní přímky. Vstup se vyhodnocuje **ještě před přepočtem úrovní**, aby se
  na hodinové hranici neporovnával s úrovní, která platí až od další H1 svíčky.
  Vstup dál od úrovně než `InpMaxLevelOffset` bodů se zamítne — po gapu nebo
  dlouhé svíčce už s průrazem nemá nic společného.

Společné pro oba režimy:

- Vyplnění příkazu se zachytává v `OnTradeTransaction`, takže o něm expert ví
  i v případě, že pending příkaz vyplnil broker bez jeho přičinění; návrhy se
  hned přepočítají a druhý příkaz se zruší.
- **Po vyplnění se SL a PT dorovnají na skutečnou plnicí cenu** (v obou režimech),
  aby poměr zůstal přesně 1:1 — pending příkaz nese absolutní SL a PT spočtené pro
  nominální cenu, takže při plnění se skluzem by jinak byla jedna strana delší.
  Upravuje se výhradně právě otevřená pozice (podle ID pozice z vyplněného
  obchodu), ne všechny pozice strategie.
- Ochrany vstupu jsou pro **oba režimy stejné**: běžící pozice (`InpMaxPositions`),
  „na této úrovni už obchodováno“, vypnutý směr a **nabitost směru** (cena musela
  být na správné straně úrovně). Pending režim navíc kontroluje, že úroveň ještě
  není proražená a že je STOP příkaz proveditelný; tržní vstup místo toho hlídá
  odstup od úrovně (`InpMaxLevelOffset`).
- Směry lze jednotlivě vypnout (`InpAllowBuy`, `InpAllowSell`) — vypnutý směr se
  přestane i kreslit a v panelu má důvod `směr vypnut`. `InpEnableTrading = false`
  nechá experta jen kreslit; taková instance **nesahá ani na cizí příkazy** se
  stejným magic (dřív je mazala při každém přepočtu). Při `InpAllowedAccount ≠ 0`
  a jiném čísle účtu se obchodování vypne (kreslení zůstává). Obchoduje se jen při
  povoleném algoritmickém obchodování v terminálu i na účtu.
- Při odebrání experta z grafu se jeho pending příkazy zruší (jinak by ležely bez
  dozoru a jejich vyplnění by otevřelo neřízenou pozici); při změně parametrů nebo
  rekompilaci zůstávají a jen se srovnají s novým návrhem. Po přepnutí do režimu
  `PUNTIKY_ENTRY_M1_CLOSE` se osiřelé příkazy zruší při startu.

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
   počítají jako jeden; opora epizodu uzavírá, takže se místo ní nezapočítá
   svíčka hned vedle ní). **Vlastní opory přímky se do dotyků nepočítají** —
   prochází jimi z definice, takže dřív měla každá čistá spojnice dvou swingů
   „zadarmo“ dva dotyky a práh 2 nic nefiltroval. Výchozí hodnota je proto
   **0** = platí i čistá spojnice dvou swingů bez dalšího dotyku (běžná
   trendlinie, chování jako dřív); zvýšením na 1 a víc se drží jen přímky,
   které si cena skutečně osahala i mimo své opory. Volitelně
   (`InpReliefMidTouch`) se vyžaduje i dotyk v prostřední části přímky
   (`InpReliefMidFrom`–`InpReliefMidTo` délky, tolerance `InpReliefMidTol`).
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
   nejvýše `InpMaxReliefLines` nejvýznamnějších; přímky stejného typu, které se
   liší o méně než `InpReliefDedupTol`, se sloučí — porovnává se ve **dvou**
   časech (poslední svíčka a 50 svíček zpět), aby se dvě různě skloněné přímky,
   které se právě kříží, chybně nesloučily. Při výběru se **střídají odpory
   a podpory**, aby jeden typ neobsadil všechny sloty.

Když leží přímka ve směru obchodu **blíž než plánovaný PT**, rozhoduje
`InpReliefMode`:

| Režim | Chování |
|---|---|
| `PUNTIKY_RELIEF_SHORTEN` (výchozí) | PT se zkrátí před přímku (mínus `InpReliefBuffer`), SL stejně — RRR zůstává 1:1 |
| `PUNTIKY_RELIEF_SKIP` | vstup se přeskočí, důvod se vypíše v panelu |

Zkrácení podléhá stejnému prahu jako hrana kanálu: když po odečtení
`InpReliefBuffer` zbývá méně než `InpMinEntryPoints`, obchod se neotevře.

Přímky se přepočítávají s každou novou M1 svíčkou a kreslí se do grafu tečkovaně
(`InpColorRelief`), prodloužené o `InpReliefForwardBars` svíček doprava.

### Délka vstupu a stopy

- Základní délka vstupu je **300 bodů** (`InpMaxEntryPoints`), SL : PT = **1 : 1**.
- Pokud je nejbližší hrana kanálu ve směru obchodu blíž, PT se zkrátí tak, aby se
  před ni vešel (mínus rezerva `InpEdgeBuffer`), a SL se zkrátí stejně — **RRR
  zůstává 1:1**.
- Hrana se hledá od **úrovně průrazu**, tedy od stejné ceny, proti které se
  testovalo „průraz uvnitř kanálu“; volné místo se pak měří od skutečného vstupu.
  Když hrana leží mezi úrovní a vstupem, je volného místa nula a obchod se
  zamítne (`málo místa k hraně kanálu`). Dřív se hledalo až od vstupu a taková
  hrana se považovala za neexistující — PT pak mířil v plné délce **za** hranu
  kanálu, právě když swing seděl na hraně.
- Hledají se hrany **všech** aktivních kanálů, takže cílem může být i hrana menšího
  kanálu vnořeného do většího.
- Protože jsou hrany šikmé, bere se konzervativnější hodnota z času vstupu a z času
  projekce o `InpEdgeProjBars` svíček dopředu.
- Když je místa méně než `InpMinEntryPoints`, nebo délka nepřesahuje stop-level
  brokera, obchod se neotevře a důvod se zobrazí v panelu.
- Objem: výchozí je dopočet z rizika (`InpLotMode = PUNTIKY_LOT_RISK`: ztráta na SL
  = `InpRiskPercent` % zůstatku, výchozí 1 %) nebo pevný lot (`PUNTIKY_LOT_FIXED`, `InpFixedLot`).
  Lot se zaokrouhlí dolů na krok objemu (s tolerancí proti chybě dělení
  v plovoucí řadové čárce — `0.29 / 0.01` vyjde `28.999…` a bez ní by se
  obchodovalo 0.28 místo zadaných 0.29), normalizuje na počet desetinných míst
  **kroku objemu** (u kroku 0.001 tedy na tři místa) a ořízne do rozsahu symbolu.
  Ztráta se počítá z `SYMBOL_TRADE_TICK_VALUE_LOSS`. Když riziko nestačí ani na
  nejmenší dovolený lot, **obchod se neotevře** a v panelu je vidět, jaké procento
  by minimální lot znamenal — dřív se lot zvedl na minimum a riziko tiše překročilo
  zadaný limit (na malém účtu i několikanásobně).

### Stavy a důvody zamítnutí v panelu

Řádek `stav:` ukazuje pro každý směr `připraven` / `blokován` (cena ještě nebyla
na správné straně úrovně) / `obchodován` / `nelze (důvod)`. Možné důvody:

| Důvod | Význam |
|---|---|
| `směr vypnut` | směr je vypnutý (`InpAllowBuy` / `InpAllowSell`) |
| `pozice již otevřena` | běží pozice strategie (`InpMaxPositions`) |
| `tato úroveň už obchodována` | na aktuálním swingu už proběhl vstup |
| `čeká na návrat pod úroveň` / `nad úroveň` | směr není nabitý — cena ještě nebyla na správné straně úrovně |
| `úroveň už byla proražena` | cena úroveň prorazila (i intrabar), čeká se na nový swing |
| `průraz už proběhl` | cena je právě za úrovní, STOP příkaz nelze zadat |
| `blíž než stop-level brokera` | úroveň je k trhu blíž, než broker pro STOP příkaz dovolí |
| `vstup N b od úrovně` | tržní vstup dál od úrovně než `InpMaxLevelOffset` (gap, dlouhá svíčka) |
| `žádný platný kanál` | žádný kanál neprošel filtry |
| `průraz mimo kanál` | úroveň neleží uvnitř žádného kanálu |
| `v cestě reliéfní přímka (N b, cena)` | přímka blíž než PT, režim SKIP |
| `málo místa k hraně kanálu / reliéfní přímce (N b)` | zbývá méně než `InpMinEntryPoints` |
| `délka pod stop-level brokera` | SL/PT by byly blíž, než broker dovolí |
| `riziko N % nestačí ani na M lot` | v režimu RISK by minimální lot překročil zadané riziko |
| `nelze určit objem` | výpočet lotu selhal (chybí data symbolu nebo účtu) |

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
| Panel vlevo nahoře | hlavička, přehled kanálů, úrovně průrazu, reliéf, stav upozornění Hue, stav směrů, návrhy vstupu, pozice / pending, poslední událost |

Popisky sdílené opory se slučují (`E1 E3`), panel uhýbá one-click SELL/BUY panelu
a obnovuje se každou sekundu i bez ticků. Hlavní kanál (nejvyšší skóre) se kreslí
silnější čarou než ostatní. Všechny objekty mají prefix `PUNTIKY_`, jsou nevybíratelné
a mají tooltip s popisem; při odebrání experta se smažou jen tyto objekty.

### Upozornění Hue na blížící se vstup

Když se cena přiblíží k úrovni plánovaného vstupu na `InpHueNearPoints` bodů
(výchozí 500), expert pošle POST požadavek na `InpHueUrl` a rozbliká tím žárovky
Philips Hue. Odpovídá to ručnímu volání:

```
curl -H "Content-Type: text/plain; charset=utf-8" -d "BTCUSD Greater Than 9001" -X POST "http://192.168.0.157:8082/hue"
```

Tělo požadavku se skládá automaticky ze symbolu, směru a ceny vstupu —
`<symbol> Greater Than <cena>` pro BUY (cena se k úrovni blíží zespodu),
`<symbol> Less Than <cena>` pro SELL.

- Hlídají se jen **platné návrhy** vstupu. Pokud je směr zamítnutý (úroveň už
  proražená, v cestě reliéfní přímka, málo místa k hraně …), upozornění nechodí —
  není k čemu zvát.
- Na jednu úroveň se hlásí **jednou**. Nová úroveň (nový H1 swing) upozornění
  odblokuje; opakování na stejné úrovni lze zapnout přes `InpHueRepeatMinutes`.
- Odchod z pásma uvolní příznak až za hysterezí 25 % nad prahem, aby se při
  kolísání přesně na hranici neblikalo pořád dokola.
- Stav upozornění je vidět v panelu na řádku `Hue:` a odeslání se loguje do
  Expert logu i s tělem požadavku.

**Nutné povolení v terminálu:** Nástroje → Nastavení → Expert Advisors →
*Povolit WebRequest pro uvedené URL* a přidat `http://192.168.0.157:8082`.
Bez toho volání skončí chybou 4014, což expert v logu jednorázově vypíše.
V testeru strategie `WebRequest` nefunguje, upozornění se tam přeskakuje.

Pod panelem je tlačítko **`TEST Hue`** (`InpHueTestButton`) — kliknutím se pošle
testovací požadavek s aktuální cenou Ask, takže jde ověřit spojení i povolení URL
bez čekání na skutečný průraz. Výsledek (`Hue test: HTTP 200`, nebo chyba) se
objeví v panelu na řádku `poslední:` a v Expert logu.

Pokud URL nejde přidat přes GUI, použij:

```
scripts\allow-webrequest.ps1
```

Skript zapíše adresu přímo do `config\common.ini` terminálu. **Terminál musí být
zavřený** — MT5 si soubor při ukončení přepisuje, takže by změnu zahodil.

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
3. Přetáhnout `Experts\Puntiky\PuntikyChannelBreakout` na graf.
4. Zkontrolovat řádek v Expert logu s přepočtem bodů na cenu — u zlata se počet
   desetinných míst mezi brokery liší. Při `digits = 3` je potřeba nastavit
   `InpMaxEntryPoints = 3000`, aby délka vstupu odpovídala 3,00 USD.

## Struktura projektu

```
MQL5/
  Experts/Puntiky/PuntikyChannelBreakout.mq5   hlavní EA — vstupy, úrovně průrazu, obchodování, panel
  Include/Puntiky/PuntikyTypes.mqh             datové struktury a výčtové typy
  Include/Puntiky/PuntikySwings.mqh            detekce swingových bodů (zig-zag)
  Include/Puntiky/PuntikyChannels.mqh          stavba, hodnocení a výběr kanálů, hledání hran
  Include/Puntiky/PuntikyRelief.mqh            reliéfní přímky na vstupním TF
  Include/Puntiky/PuntikyDraw.mqh              vykreslování kanálů, popisků, úrovní a panelu
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
| `InpMinTouches` | 1 | minimální počet dotyků hran **mimo opory A, B, C** |
| `InpTouchTolFrac` | 0.15 | tolerance dotyku jako zlomek šířky |
| `InpMinContainment` | 0.85 | minimální podíl svíček uvnitř (tolerance `InpInsideTolFrac`) |
| `InpMaxChannels` | 4 | kolik kanálů se ponechá |
| `InpPierceTolFrac` | 0.05 | kolik smí cena prořezávat hranu (zlomek šířky) |
| `InpInvalidTolFrac` | 0.15 | za jakým přesahem protější hrany za C je kanál invalidovaný |
| `InpBackCheckBars` | 20 | kolik svíček před bodem A se ještě kontroluje |
| `InpAnchorWindow` | 5 | okno, ve kterém musí být A a C nejvýraznějším extrémem |
| `InpDedupFrac` | 0.15 | práh, kdy se dva kanály považují za totožné |
| `InpRequireInside` | true | kanál platí jen když je v něm aktuální cena |

### Vstup
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpEnableTrading` | true | false = jen kreslení bez obchodů |
| `InpEntryMode` | PENDING | pending STOP příkazy vs. potvrzení uzavřením M1 |
| `InpMaxEntryPoints` | 300 | maximální délka vstupu |
| `InpMinEntryPoints` | 150 | pod touto délkou se nevstupuje |
| `InpBreakoutBuffer` | 10 | buffer za úrovní průrazu |
| `InpMaxLevelOffset` | 30 | max. odstup tržního vstupu od úrovně (režim M1_CLOSE) |
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
| `InpReliefMode` | SHORTEN | zkrátit PT / přeskočit vstup |
| `InpReliefLookback` | 2400 | kolik M1 svíček se analyzuje |
| `InpReliefSwingDepth` | 10 | šířka okna pro hlavní swingy |
| `InpReliefScales` | 4 | počet měřítek swingů (10/20/40/80) |
| `InpReliefSwingGap` | 20 | max. odstup opor (počet swingů) |
| `InpReliefMinSpan` | 30 | minimální délka přímky ve svíčkách |
| `InpReliefMinTouches` | 0 | minimální počet dotyků **mimo vlastní opory přímky** (0 = stačí čistá spojnice) |
| `InpReliefPierceTol` | 10 | proříznutí přímky tělem svíčky (body) |
| `InpReliefWickTol` | 150 | povolený přesah přímky knotem mezi oporami (body) |
| `InpReliefTouchTol` | 25 | tolerance dotyku (body) |
| `InpReliefDedupTol` | 40 | práh shody dvou přímek (body) |
| `InpReliefMaxAge` | 0.0 | platnost přímky za 2. oporou v násobcích délky (0 = neomezeno) |
| `InpReliefMaxDrift` | 1200 | max. vzdálení přímky od 2. opory (body) |
| `InpReliefMidTouch` | false | vyžadovat dotyk i uprostřed přímky |
| `InpReliefMidTol` | 60 | tolerance středního dotyku (body) |
| `InpReliefMidFrom` / `InpReliefMidTo` | 0.20 / 0.80 | prostřední úsek přímky |
| `InpMaxReliefLines` | 15 | kolik přímek ponechat |
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

### Upozornění Hue
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpHueEnabled` | true | blikat žárovkou při přiblížení k úrovni vstupu |
| `InpHueUrl` | http://192.168.0.157:8082/hue | URL služby Hue včetně portu |
| `InpHueNearPoints` | 500 | vzdálenost od úrovně vstupu pro upozornění (body) |
| `InpHueRepeatMinutes` | 0 | opakovat upozornění po N minutách (0 = jen jednou) |
| `InpHueTimeout` | 1000 | timeout HTTP požadavku (ms) |
| `InpHueTestButton` | true | zobrazit tlačítko `TEST Hue` pod panelem |

### Diagnostika
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpDiagnostics` | true | výpis detekce kanálů a reliéfu do Expert logu |
| `InpShotOnRequest` | true | snímek grafu na vyžádání (viz níže) |
| `InpShotEveryBars` | 0 | snímek každých N svíček TF kanálu (0 = vypnuto) |
| `InpShotFileName` | PuntikyShot.png | soubor snímku v `MQL5\Files` |
| `InpShotRequestFile` | PuntikyShot.request | soubor požadavku o snímek |

Při zapnuté diagnostice se s každým přepočtem kanálů (nová M15 svíčka) zapíše
do Expert logu, kolik kandidátů padlo na kterém filtru (bod B, délka, stáří,
šířka, opory, proříznutí, dotyky, uvnitř, cena mimo), rozpis opor a metrik
vybraných kanálů a totéž pro reliéfní přímky. Z rozložení zamítnutí je hned
vidět, který práh je úzkým hrdlem.

Snímek grafu si lze vyžádat kdykoliv — stačí v `MQL5\Files` vytvořit prázdný
soubor `PuntikyShot.request`. Expert ho do sekundy zpracuje (kontrola běží
v timeru), uloží `MQL5\Files\PuntikyShot.png` a požadavek smaže.

## Poznámky a omezení

- Kanály, H1 swingy i reliéfní přímky se počítají jen z **uzavřených** svíček,
  takže se uvnitř rozpracované svíčky nemění a nepřekreslují se zpětně. Jedinou
  výjimkou je hlídání průrazu úrovně, které běží na každém ticku.
- Výchozí filtry jsou nastavené konzervativně, aby prošly opravdu jen výrazné
  kanály. Pokud se na grafu nekreslí nic, sniž `InpMinTouches` na 0 nebo
  `InpMinContainment` na 0.80, případně uvolni `InpInsideTolFrac` — diagnostika
  v logu ukáže, který filtr brzdí.
- Když v grafu **chybí konkrétní podkanál**, který je vidět okem, podívej se do
  logu na řádek `prošlo N, vybráno M`. Když prošly desítky kandidátů a vybralo se
  jen pár, nebrzdí filtry, ale **deduplikace**: `InpDedupFrac` × šířka je pásmo,
  ve kterém se dva kanály považují za totožné, a stoupající podkanál se s klesajícím
  nadřazeným kanálem může v tomto pásmu křížit. Pomůže snížit `InpDedupFrac`
  a přidat slot přes `InpMaxChannels`. Pod ~0.10 už ale sloty obsazují varianty
  téhož kanálu posunuté o pár bodů.
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
- Úrovně průrazu se aktualizují **po stranách**: strana, pro kterou se neproražený
  swing najde, se přepočítá i tehdy, když ta druhá zůstane bez nálezu (tam platí
  poslední známá hodnota).
- Vstupní parametry se kontrolují při startu — nesmyslná kombinace (např.
  `InpMaxPositions = 0` nebo `InpSwingDepth = 0`) skončí chybou
  `INIT_PARAMETERS_INCORRECT` s výpisem toho, co je špatně, místo tichého
  neobchodování.
- Filtr šířky podle ATR potřebuje dopočítaný indikátor. ATR na jiném timeframu,
  než má graf, se počítá asynchronně, takže první výpočet i první příkazy se
  odloží na okamžik, kdy jsou data k dispozici (do logu jde hláška „čeká se na
  dopočet ATR“). Dřív se v takové chvíli filtr šířky i složka skóre tiše vypnuly.
- Panel se překresluje z timeru (jednou za sekundu) a jen v řádcích, jejichž text
  se skutečně změnil; grafické objekty se aktualizují na místě a maže se jen to,
  co po zmenšení počtu kanálů či přímek zbylo. Porovnává se s textem **skutečně
  uloženým v objektu**, ne se stínovou kopií v paměti — když objekt z grafu zmizí
  (změna šablony, úklid grafu), řádek se sám obnoví místo aby v panelu zůstalo
  prázdné místo.
- MT5 zobrazí z textu grafického objektu jen **prvních 63 znaků** a zbytek tiše
  zahodí, klidně uprostřed slova. Panel proto delší řádky sám zalomí a pokračování
  odsadí; texty jsou zkrácené tak, aby se běžné řádky do limitu vešly (timeframy
  bez prefixu `PERIOD_`, časy úrovní bez roku).
- `datetime − datetime` je v MQL5 **znaménkový** rozdíl (typ se chová jako `long`)
  — ověřeno kompilační sondou v MetaEditoru. Projekce `BaseAt()` a `ValueAt()` do
  časů *před* první oporou tedy nepřetéká a nepotřebuje ošetřit; není to chyba,
  kterou by bylo potřeba „opravovat“.
- Strategie se ve verzi 1.13 přejmenovala ze `Sved*` na `Puntiky*` (soubory,
  adresáře, identifikátory, prefix objektů v grafu i jména globálních proměnných
  terminálu). Po starší verzi můžou v terminálu zůstat globální proměnné
  `SVED_…` — jsou neškodné, jen se v nich ztratí paměť „na téhle úrovni už bylo
  obchodováno“. Objekty `SVED_*` v grafu smaže starý expert sám při odebrání.
- Strategie nemá časový filtr obchodních hodin ani filtr zpráv — pokud jsou
  potřeba, je to samostatné rozšíření.
