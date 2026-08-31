# Puntiky Channel Breakout — strategie pro MetaTrader 5

Expert Advisor pro MT5 (verze 1.22), který detekuje ABCD kanály na M15, kreslí je
do grafu a obchoduje průrazy swingových H1 úrovní. Vstup se
vyhodnocuje na M1. Do grafu vykresluje **pouze kanály, reliéfní přímky
a informace o vstupu** — žádné jiné indikátory ani pomocnou grafiku.

**Ve výchozím nastavení expert sám neobchoduje**: obchody jen zobrazuje a hlásí
blikáním, na trh je posílá až člověk tlačítky `LONG` / `SHORT` (jeden obchod)
nebo `LONG 2x` / `SHORT 2x` (dva obchody se společným SL a odstupňovanými cíli) —
viz [Ruční režim](#ruční-režim--obchodování-tlačítky). Automatické režimy zůstávají
k dispozici přes `InpEntryMode`.

Testovací prostředí: RoboForex MT5, demo účet `67205475`, ticker `XAUUSD`.
Cílem jsou **forexové páry a XAUUSD**, tedy nástroje, kde se krok kotace rovná
bodu. Ceny se přesto zarovnávají na `SYMBOL_TRADE_TICK_SIZE`, takže nástroj
s hrubším krokem (indexové CFD s krokem 0,25) nekončí odmítnutým příkazem —
otestovaný ale není.

## Jak strategie funguje

### Kanály (výchozí timeframe M15)

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
   Geometrie kanálu (i reliéfních přímek) je vedena v **indexech svíček**, ne
   v reálném čase. MT5 kreslí úsečku v prostoru indexů — víkendová mezera na ose x
   žádné místo nezabírá — takže sklon počítaný na sekundy znamenal, že nakreslená
   čára a hodnota, se kterou expert počítá, se uprostřed okna rozešly o velkou část
   šířky kanálu (při 1500 svíčkách M15 je ~28 % okna víkend). Poznalo se to podle
   toho, že popisky A, B, C seděly na svých svíčkách, ale viditelně **mimo**
   nakreslenou hranu. V indexech se obě věci kryjí přesně.
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
     `InpMinWidthATR`; ATR s periodou `InpATRPeriod` na referenčním TF),
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
  Spread se bere podle toho, co se zrovna testuje:
  - **probíhající tick** — živý spread, takže u nákupu vyjde přesně aktuální ASK.
    Úroveň tak padne právě ve chvíli, kdy by se STOP příkaz vyplnil. S mediánem
    (který bývá větší než okamžitý spread) ji expert prohlašoval za proraženou
    dřív, než k ní ASK dosáhl, a ležící příkaz se rušil nebo přesouval těsně před
    vlastním vyplněním — právě ten průraz, na který čekal, pak propásl.
  - **uzavřená svíčka** — spread té svíčky (`MqlRates.spread`). Dnešní medián na ni
    nepatří: přičítá se k historickému high, takže se s každým jeho posunem měnil
    stav dávno uzavřeného swingu, aniž by se cena pohnula.
  - **jinde** — medián posledních vzorků (jeden za minutu, půlhodinové okno).
    Vzorky se při startu naplní ze spreadů historických M1 svíček; jediný vzorek
    odebraný v rolloveru (na zlatě 500 bodů místo 25) by jinak určoval medián pro
    celý první výběr úrovní a ten by prohlásil za proražený každý vrchol, ke
    kterému se cena kdy přiblížila na tuto vzdálenost.
- Obě strany se aktualizují **samostatně**: když se pro jeden směr žádný
  neproražený swing nenajde (v silném trendu jsou všechny starší vrcholy
  proražené), druhá strana se přesto přepočítá.
- Na jedné swingové úrovni se obchoduje **nejvýše jednou**. Spotřebovaná úroveň
  se ukládá do globální proměnné terminálu (`PUNTIKY_<symbol>_<magic>_BUY` / `_SELL`),
  takže to přežije i restart terminálu — dřív se po restartu tatáž úroveň
  obchodovala podruhé. Spotřebuje se jen úroveň, ke které vyplněný obchod
  **skutečně patří** (vstup leží za ní nejdál o buffer + `InpMaxLevelOffset`
  + skluz): tick, který STOP příkaz vyplní, úroveň zároveň prorazí a expert
  hned přepne na další swing, takže by se jinak jako obchodovaná označila nová
  úroveň, na které nikdo neobchodoval, a směr by zůstal zablokovaný až do
  vzniku dalšího swingu (do verze 1.18 se to takhle dělo). Záznam v globální
  proměnné se navíc při každém načtení úrovně **ověřuje proti historii účtu**:
  když k němu od času svíčky úrovně neexistuje vstup strategie za úrovní, zahodí
  se (uklidí to i falešné záznamy po starších verzích, bez ručního mazání přes F3).
  Zahodí se ale **jen když historie skutečně odpověděla**. Prázdný výběr není důkaz:
  po připojení nebo restartu nemusí být historie účtu dosynchronizovaná, a protože
  je záznam jediná ochrana proti druhému vstupu na téže úrovni (třeba když průraz
  zůstal při spreadové špičce nedetekovaný), naslepo se nemaže.
- Směr je **zablokovaný**, dokud cena nebyla na správné straně úrovně (pod HIGH pro
  BUY, nad LOW pro SELL) — zabraňuje vstupu do už proběhlého pohybu (gap, start EA
  uprostřed pohybu).
- Vypnutím `InpUseSwingLevels` se strategie vrátí k prostému high/low poslední
  uzavřené H1 svíčky.

### Vstup (vyhodnocení M1)

Kanál **není podmínkou vstupu** — je to S/R zóna jako reliéfní přímka, ne filtr.
Uplatní se až na zkrácení PT k nejbližší hraně ve směru obchodu, takže **průraz
mimo kanál i stav bez jediného detekovaného kanálu jsou legitimní** a obchodují
se. Kanál obsahující úroveň se dohledává s tolerancí `InpInsideTolFrac` × šířka
(při více kanálech ten s nejlepším skóre) jen kvůli popisu návrhu — když žádný
takový není, nese návrh v panelu `k-` místo `k1`, `k2` …

Vyhodnocení návrhu je **ve všech režimech stejné**; liší se jen to, kdo příkaz
pošle na trh. Režim vstupu určuje `InpEntryMode`:

- **`PUNTIKY_ENTRY_PENDING`**: BuyStop a SellStop se umístí přímo na
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
  jinak je návrh označený jako neproveditelný a důvod je vidět v panelu. **Už
  ležící příkaz se kvůli tomu ale neruší**: stop-level omezuje zadání a úpravu
  příkazu, ne jeho držení, takže by příkaz mizel z trhu přesně ve chvíli, kdy se
  k němu cena blíží — tedy těsně před vlastním vyplněním. Ležící příkaz opouští
  trh jen z důvodů, které se týkají samotné úrovně (spotřebovaná nebo vyměněná
  úroveň, limit pozic, vypnutý směr), nebo když už neleží na plánované ceně.
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
  Ze stejného důvodu se v tomto režimu **výměna spotřebované úrovně za další swing
  odkládá** až za první novou M1 svíčku po průrazu: průraz se hlídá na každém ticku,
  takže by se úroveň vyměnila uprostřed svíčky a při jejím uzavření by se close
  porovnával už s dalším (vyšším) swingem — se swingovými úrovněmi by režim
  prakticky nikdy nevstoupil. Příznak „proraženo“ přitom vstup neblokuje, pokud
  k průrazu došlo **až během právě uzavřené svíčky**; starší průraz už úroveň
  spotřeboval a tržní vstup se zamítne.
- **`PUNTIKY_ENTRY_MANUAL` (výchozí)**: režim pro ostré obchodování pod dohledem. Expert
  **sám neobchoduje** — jen detekuje, kreslí návrhy do grafu a blikáním žárovek
  hlásí přiblížení k úrovni vstupu. STOP příkaz (a s ním SL i PT) se zapíná
  a vypíná tlačítky `LONG` / `SHORT` nad panelem, tlačítka `LONG 2x` / `SHORT 2x`
  zadají místo jednoho obchodu rovnou dva, viz
  [Ruční režim](#ruční-režim--obchodování-tlačítky). Detekce, filtry ani výpočet
  návrhu se nemění: obchod jde zadat jen tam, kde na něj podle strategie je místo.

Společné pro oba režimy:

- Vyplnění příkazu se zachytává v `OnTradeTransaction`, takže o něm expert ví
  i v případě, že pending příkaz vyplnil broker bez jeho přičinění; návrhy se
  hned přepočítají a v **pending režimu** se opačný příkaz zruší (OCO).
  V ručním režimu expert na příkazy zadané tlačítky nesahá, takže tam OCO neplatí
  a `InpMaxPositions` je ani neomezuje — mohou ležet oba směry a vyplnit se oba.
  Rekonciliace příkazů se v obsluze vyplnění **záměrně nespouští**: běžela by nad
  účtem, který novou pozici ještě nemusí hlásit, takže by právě zrušený opačný
  příkaz okamžitě zadala zpátky. Příkazy srovná až následující tick.
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
- Pending příkazy se ruší při **každém ukončení, po kterém se expert sám nevrátí**:
  odebrání z grafu, zavření grafu, nová šablona, změna symbolu i `ExpertRemove()`.
  Jinak by ležely bez dozoru a jejich vyplnění by otevřelo neřízenou pozici.
  Zůstávají naopak při rekompilaci, změně parametrů, ukončení terminálu, neúspěšné
  inicializaci a změně účtu — tam se expert vrací a jen je srovná s novým návrhem.
  Změnu periody sice expert přežije, jenže ji při deinitu nelze odlišit od změny
  symbolu; zrušený příkaz zadá následný `OnInit` v pending režimu stejně hned znovu,
  kdežto příkaz zapomenutý na jiném symbolu už nezruší nikdo.
  V ručním režimu se příkazy nikdy neruší (zadal je uživatel a nesou vlastní SL i
  PT) — do logu se jen napíše, kolik jich na trhu zůstává. Totéž při vypnutém
  obchodování, kde by zrušení stejně skončilo chybou.
- Po přepnutí do režimu `PUNTIKY_ENTRY_M1_CLOSE` se osiřelé příkazy z pending režimu
  zruší při startu. Když je zrovna vypnuté obchodování (AutoTrading), úklid se
  **opakuje z timeru**, dokud neprojde — jeho zapnutí totiž žádný `OnInit` nevyvolá
  a příkaz by na trhu zůstal bez dozoru (tržní vstup příkazy nepočítá, takže by se
  vedle pozice vyplnil ještě on).

### Reliéfní přímky (výchozí timeframe M1)

Reliéfní přímka je trendlinie vedená dvěma **hlavními swingy stejného typu** na
timeframu reliéfu — dvěma vrcholy (odpor) nebo dvěma dny (podpora). Stojí průrazu
v cestě, takže ji strategie hlídá při plánování vstupu.

1. Swingy se hledají z `InpReliefLookback` uzavřených M1 svíček (výchozí 7200,
   tedy 5 dní) s hrubším oknem (`InpReliefSwingDepth`, výchozí 25 svíček)
   a v několika měřítkách (`InpReliefScales`, výchozí 4 → okna 25/50/100/200
   svíček). Šířka okna je zároveň hlavní páka na **dosah do minulosti**: odstup
   opor se počítá v *počtu swingů* (`InpReliefSwingGap`), takže čím řidší swingy,
   tím dál přímka sahá. Jemné okno dá čerstvé
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

Jak daleko smí přímka ujet od své druhé opory, hlídá **dvojí mez**: bodová
(`InpReliefMaxDrift`) a relativní k ATR (`InpReliefMaxDriftATR`); platí ta **větší**.
#### Vzdálenost od ceny a přilnutí

Práh driftu měří, jak daleko přímka ujela od **své druhé opory** — ne jak daleko
je od trhu. Téměř vodorovná čára ukotvená stovky bodů od ceny jím proto projde:
neujela nikam, jen tam nikdy nebyla. Přesně takové přímky pak obsadily všechny
sloty a kreslily se mimo viditelný rozsah grafu (na D1 i tisíce bodů od ceny).

Proto jsou tu dva samostatné filtry:

- `InpReliefMaxDist` / `InpReliefMaxDistATR` — jak daleko od **aktuální ceny**
  (závěr poslední uzavřené svíčky) smí přímka ležet. Překážkou průrazu je jen
  přímka, na kterou cena během obchodu vůbec může dosáhnout. Test je O(1), takže
  běží ještě před průchodem svíčkami; kontroluje ho i levná revalidace, aby
  přímka zmizela hned, jakmile se od ní trh vzdálí.
- `InpReliefMaxGap` / `InpReliefMaxGapATR` — strop na **přilnutí** (`meanGap`),
  tedy průměrný odstup přímky od ceny mezi oporami. Odlišuje trendlinii od pouhé
  tětivy: čistá spojnice dvou vzdálených swingů není proražená a bez tohoto prahu
  projde, i když se ceny mezi oporami ani jednou nedotkne. Testuje se až po
  průchodu svíčkami, protože dřív průměrný odstup není znám.

Obě používají stejné pravidlo jako drift — platí **větší** z bodové meze
a násobku ATR, `0` v bodové mezi filtr vypne úplně.

#### Tolerance detekce a ATR

Tolerance proříznutí, knotu a dotyku mají vedle bodové meze i **násobek ATR** —
ze stejného důvodu jako práh driftu níže. Zadání 10 b znamená na pětimístném FX
páru 1 pip, tedy asi třetinu rozpětí svíčky M1, kdežto na zlatě (2 desetinná
místa) 0,10 USD, tedy jen pár procent rozpětí svíčky. A protože tělo přes přímku
nesmí vůbec, taková mez zahodí skoro každého kandidáta.

Platí **větší** z obou hodnot, takže násobek ATR může toleranci jen *uvolnit*,
nikdy zpřísnit: zapnutí násobku nemůže žádnou dosud nalezenou přímku zahodit, jen
přidat další. `0` v násobku vrací původní chování (jen bodová mez).

ATR se bere z **timeframu, na kterém přímka vzniká**, ne z referenčního TF kanálů
— rozpětí svíčky D1 je o řády jinde než u M1 a jedno společné ATR by na dlouhých
timeframech znamenalo prakticky nulovou toleranci. Každý zapnutý TF reliéfu má
proto vlastní ATR handle. Dokud terminál ATR nedopočítá, přepočet toho timeframu
se **odloží** (ne spočítá s pouhou bodovou mezí) — jinak by takto postavené
přímky zůstaly v paměti až do dalšího plného přepočtu, na D1 klidně tři týdny.

Co zrovna platí, vypisuje diagnostika; hvězdička znamená, že rozhodl násobek ATR:

```
PUNTIKY diag: reliéf M1 - ATR 1.42, proříznutí 21 b *, knot 142 b, dotyk 50 b *, drift 3000 b
```

Samotná bodová mez se totiž nepřizpůsobí nástroji — zadání 3000 b znamená na zlatě
přiměřených pár ATR, ale na BTCUSD (ATR M15 kolem 84 USD) jen 0,36 ATR, takže filtr
zahazoval **99 % kandidátů** (v diagnostice `drift 2450` z 2470) a zbyly jen vodorovné
nebo čerstvé přímky. Šířka kanálu se měří stejně (`InpMinWidthPoints` vedle
`InpMinWidthATR`). `InpReliefMaxDrift = 0` filtr vypne úplně i s násobkem ATR.
Do logu se vypisuje, která mez zrovna platí:
`PUNTIKY diag: reliéf - přímek celkem N, práh driftu N b (bodově M b, ATR A × K)`.

Plný přepočet přímek běží **jednou za 15 svíček daného TF reliéfu**, ne na každé.
Počítadlo i revalidace jsou vedené po timeframech — nový bar M1 nesmí spouštět
přepočet přímek H1 ani je kontrolovat proti minutovým svíčkám.
Ověřit každého kandidáta přes celou historii znamená při výchozích 7200 svíčkách
a čtyřech měřítkách řádově miliony průchodů svíčkami a expert po tu dobu
nezpracovává ticky (nekontroluje průraz, nesrovnává příkazy, neblikají žárovky).
Každou minutu je to zbytečné — hlavní swingy se tak rychle nemění. Mezi přepočty
se hlídá to podstatné: přímka, kterou právě uzavřená svíčka prorazila, **zmizí
hned**, protože už překážkou není. Nová přímka může počkat na nejbližší přepočet.

Když leží přímka ve směru obchodu **blíž než plánovaný PT**, rozhoduje
`InpReliefMode`:

| Režim | Chování |
|---|---|
| `PUNTIKY_RELIEF_SHORTEN` (výchozí) | PT se zkrátí před přímku (mínus `InpReliefBuffer`), SL stejně — RRR zůstává 1:1 |
| `PUNTIKY_RELIEF_SKIP` | vstup se přeskočí, důvod se vypíše v panelu |

Zkrácení podléhá stejnému prahu jako hrana kanálu: když po odečtení
`InpReliefBuffer` zbývá méně než `InpMinEntryPoints`, obchod se neotevře.

Přímky se přepočítávají s každou novou M1 svíčkou a kreslí se do grafu tečkovaně
(`InpColorRelief`), prodloužené o `InpReliefForwardBars` svíček doprava. Plný
přepočet běží jednou za `PUNTIKY_RELIEF_REBUILD_BARS` svíček (prochází celou
historii), mezi tím se držené přímky jen kontrolují proti nově uzavřeným svíčkám —
prohlédnou se **všechny** svíčky od poslední kontroly, takže se přímka proražená
v baru, který vznikl bez ticku (výpadek spojení), nedrží dál.

Tahle kontrola běží **ještě před vyhodnocením vstupu**: průrazová svíčka často
prorazí i přímku kotvenou na svém vlastním swingu, a dokud přímka drží, zamítne si
vstup sama sebou (`v cestě reliéfní přímka`). O pár kroků později by ji revalidace
stejně smazala, jenže další svíčka už přechodem přes úroveň není a signál je
nenávratně pryč. U **tržního vstupu** se navíc překážky hledají až od skutečného
vstupu, ne od úrovně: trh je už za úrovní, takže překážka mezi nimi je právě
proražená a měřit k ní místo pro PT by vždy dalo nulu.

### Délka vstupu a stopy

- Základní délka vstupu je **300 bodů** (`InpMaxEntryPoints`), SL : PT = **1 : 1**.
- Pokud je nejbližší hrana kanálu ve směru obchodu blíž, PT se zkrátí tak, aby se
  před ni vešel (mínus rezerva `InpEdgeBuffer`), a SL se zkrátí stejně — **RRR
  zůstává 1:1**.
- Hrana se hledá od **úrovně průrazu**, tedy od ceny, na které obchod vzniká;
  volné místo se pak měří od skutečného vstupu.
  Když hrana leží mezi úrovní a vstupem, je volného místa nula a obchod se
  zamítne (`málo místa k hraně kanálu`). Dřív se hledalo až od vstupu a taková
  hrana se považovala za neexistující — PT pak mířil v plné délce **za** hranu
  kanálu, právě když swing seděl na hraně.
- Hledají se hrany **všech** aktivních kanálů, takže cílem může být i hrana menšího
  kanálu vnořeného do většího.
- Protože jsou hrany šikmé, bere se konzervativnější hodnota z aktuální svíčky a ze
  svíčky projekce dopředu. **Stejně** se promítá i reliéfní přímka — horizont se jen
  přepočte na svíčky vstupního TF, aby se obě překážky posuzovaly ke stejnému
  okamžiku. Dřív se reliéf měřil jen „teď“, takže strmá přímka
  (`InpReliefMaxDrift` připouští i velmi strmé) zkracovala PT podle polohy, kterou
  v okamžiku vyplnění příkazu dávno neměla.
- **Délka projekce se odvozuje z obchodu, ne z pevného počtu svíček.** Odhaduje se
  jako `InpMaxEntryPoints / ATR` — obchod dlouhý jednu ATR trvá řádově jednu svíčku;
  `InpEdgeProjBars` je už jen **strop**. Pevný počet svíček se totiž nepřizpůsobil
  nástroji, stejně jako dřív práh driftu: na BTCUSD je celý obchod 300 b = 3 USD proti
  ATR M15 kolem 84 USD, tedy otázka minut, ale hrana kanálu za 12 svíček (3 hodiny)
  mezitím vyjela přes 100 USD nad vstup — a konzervativní odhad zamítl směr
  (`málo místa k hraně kanálu (0 b)`), kde bylo **3708 b místa, dvanáctkrát víc, než
  obchod potřeboval**. Do logu se vypisuje, co zrovna platí:
  `PUNTIKY diag: projekce překážek N svíčky PERIOD_M15 (strop 12, vstup 300 b, ATR A)`.
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
  Objem se **na minimum brokera nikdy nezvedá**, a to ani v režimu pevného lotu.
  Dřív to dělal `MathMax(lot, minLot)` úplně nakonec a tiše tím rušil obě dělení:
  při `InpFixedLot = 0.10` a minimu symbolu 0.10 dostaly obě nohy dvojitého vstupu
  plných 0.10, tedy **dvojnásobek** expozice jednoho obchodu, přestože bublina
  tlačítka i tato dokumentace slibují polovinu. Takový obchod se teď nezadá
  a důvod je v panelu.

### Stavy a důvody zamítnutí v panelu

Řádek `stav:` ukazuje pro každý směr `připraven` / `obchodován` / `nelze (důvod)`.
Nenabitý směr (cena ještě nebyla na správné straně úrovně) spadá pod `nelze`
s důvodem `čeká na návrat pod/nad úroveň`. Možné důvody:

| Důvod | Význam |
|---|---|
| `směr vypnut` | směr je vypnutý (`InpAllowBuy` / `InpAllowSell`) |
| `pozice již otevřena` | běží pozice strategie (`InpMaxPositions`) |
| `tato úroveň už obchodována` | na aktuálním swingu už proběhl vstup |
| `čeká na návrat pod úroveň` / `nad úroveň` | směr není nabitý — cena ještě nebyla na správné straně úrovně |
| `úroveň už byla proražena` | cena úroveň prorazila (i intrabar), čeká se na nový swing |
| `průraz už proběhl` | cena je právě za úrovní, STOP příkaz nelze zadat |
| `blíž než stop-level brokera (N b)` | úroveň je k trhu blíž, než broker pro STOP příkaz dovolí; už ležící příkaz se kvůli tomu ale neruší |
| `vstup N b od úrovně` | tržní vstup dál od úrovně než `InpMaxLevelOffset` (gap, dlouhá svíčka) |
| `v cestě reliéfní přímka (N b, cena)` | přímka blíž než PT, režim SKIP |
| `málo místa k hraně kanálu / reliéfní přímce (N b)` | zbývá méně než `InpMinEntryPoints` |
| `délka pod stop-level brokera` | SL/PT by byly blíž, než broker dovolí |
| `riziko N % nestačí ani na M lot` | v režimu RISK by minimální lot překročil zadané riziko |
| `objem N nedosahuje minima brokera M` | po zaokrouhlení na krok objemu (a u dvojitého vstupu po rozdělení rizika) zbyl objem pod minimem symbolu |
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
| Tečkované čáry (`InpColorRelief`, MediumOrchid) | reliéfní přímky ze všech zapnutých TF reliéfu |
| Panel vlevo nahoře | hlavička, přehled kanálů, úrovně průrazu, reliéf, stav upozornění Hue, stav směrů, návrhy vstupu, pozice / pending, poslední událost |
| Hláška pod tlačítky (`InpColorPanel`) | poslední událost při **vypnutém** panelu; po 10 s zmizí |
| Tlačítko `AUTO ZAP/VYP` | automatický režim — expert obchoduje sám (pending STOP na obou úrovních), Hue potlačeno |
| Tlačítko `AUTO ZAP/VYP 2x` | totéž s dvojitým vstupem — dvě nohy s polovičním objemem, PT 1:1 a 2×; vyžaduje hedgovací účet a `InpMaxPositions >= 2` |
| Tři řady tlačítek nad panelem | 1. řada obslužná (`TEST Hue`, `PANEL`), 2. řada `LONG` / `SHORT`, 3. řada `LONG 2x` / `SHORT 2x` přesně pod nimi (2. a 3. jen v ručním režimu); text panelu začíná až pod nimi |

Popisky sdílené opory se slučují (`E1 E3`), panel uhýbá one-click SELL/BUY panelu
a obnovuje se každou sekundu i bez ticků. Hlavní kanál (nejvyšší skóre) se kreslí
silnější čarou než ostatní. Všechny objekty mají prefix `PUNTIKY_`, jsou nevybíratelné
a mají tooltip s popisem; při odebrání experta se smažou jen tyto objekty.

### Ruční režim — obchodování tlačítky

`InpEntryMode = PUNTIKY_ENTRY_MANUAL` (výchozí) je režim pro ostré obchodování, kde
rozhoduje člověk. Po startu experta se obchody **jen zobrazují** (kanály, úrovně
průrazu, návrh vstupu se SL a PT) a upozorňuje se na ně blikáním žárovek Hue —
na trh se sám nic nepošle.

Tlačítka jsou nad panelem ve **třech řadách** — v první obslužná (`TEST Hue`,
`PANEL`), ve druhé `LONG` a `SHORT`, ve třetí jejich dvojité varianty `LONG 2x`
a `SHORT 2x` **přesně pod svými protějšky**. Všechna čtyři obchodní tlačítka mají
stejnou šířku, takže řada nevypadá rozházeně.

Šířka se počítá ze skutečné šířky nejdelšího možného textu (`TextGetSize`), takže
se text vejde i při jiném DPI nebo jiném `InpPanelFontSize`. Velikost písma se do
`TextSetFont` předává **záporná, v desetinách bodu** — kladná hodnota znamená podle
dokumentace pixely nezávislé na rozlišení, kdežto grafické objekty berou body a
škálují se podle DPI; s kladným číslem se měřilo menší písmo, než tlačítko
doopravdy vykreslí, a při škálování 150 % se text usekl uprostřed slova. Počítá se
z nejdelšího **stavu** (`ZAVŘÍT SHORT 2x`), ne z aktuálního textu, aby tlačítko při
přepnutí neskákalo. Naměřené šířky se zjišťují jednou při startu — vstupy se za
běhu nemění, takže není proč měřit při každém obnovení panelu.

**Obchod odebírá vždy totéž tlačítko, které ho zadalo.** Dokud ve směru leží
jednoduchý obchod, je tlačítko `2x` zešedlé a naopak — takže je od pohledu jasné,
kam kliknout. Expert pozná dvojitý vstup podle značky `2x` v komentáři příkazu;
kdyby ji broker přepsal, zaskočí geometrie (druhá noha má PT výrazně delší
než SL, což obchod s RRR 1:1 nikdy nemá). Geometrie se ale použije **jen na
obchod s cizím komentářem**: náš vlastní komentář bez značky `2x` je jasná
odpověď, že obchod patří tlačítku `LONG` / `SHORT`. Jinak by stačilo přitáhnout
SL a poměr PT:SL by práh překročil — tlačítko by zešedlo a klik přestal fungovat.

#### `LONG` / `SHORT` — jeden obchod

| Stav směru | Text tlačítka | Co klik udělá |
|---|---|---|
| nic na trhu, návrh platný | `LONG` / `SHORT` (zeleně / červeně) | zadá STOP příkaz přesně podle návrhu, včetně SL a PT (RRR 1:1) |
| nic na trhu, návrh neplatný | `LONG` / `SHORT` (zešedlé) | nic — v bublině je důvod (např. „úroveň už byla proražena“) |
| leží nevyplněný příkaz | `ZRUŠIT LONG` / `ZRUŠIT SHORT` (oranžově) | zruší ležící STOP příkaz |
| příkaz se vyplnil do pozice | `ZAVŘÍT LONG` / `ZAVŘÍT SHORT` (oranžově) | zavře otevřenou pozici za trhu |
| ve směru leží **dvojitý** vstup | `LONG` / `SHORT` (zešedlé) | nic — dvojitý vstup patří tlačítku `2x` |

Tlačítko se tedy chová **střídavě**: zadat → odebrat → zadat. Jediné, co je proti
automatickým režimům nové, je právě toto zapnutí a vypnutí STOP příkazu (a s ním
SL a PT) — detekce, filtry i výpočet návrhu zůstávají beze změny a **obchod se
nabídne jen tehdy, když na něj je místo**.

#### `LONG 2x` / `SHORT 2x` — dva obchody s odstupňovaným cílem

Jeden klik zadá **dva STOP příkazy naráz** na stejné vstupní úrovni. Liší se
pouze cílem, takže první bere zisk na plánované délce a druhý nechá pozici běžet
dál:

| | Vstup | SL | PT | Objem |
|---|---|---|---|---|
| 1. obchod | podle návrhu | podle návrhu (délka vstupu) | `PT1` = délka vstupu, tedy RRR 1:1 | poloviční riziko |
| 2. obchod | **stejný** | **stejný** | `PT2` = **dvojnásobek** `PT1`, tedy RRR 1:2 | poloviční riziko |

Riziko se mezi oba obchody dělí, takže **součet obou pozic odpovídá jednomu
běžnému obchodu** zadanému tlačítkem `LONG` / `SHORT` — když trh sáhne na SL,
ztráta je stejná jako u jednoho obchodu. Násobek `PT2` a rozdělení rizika jsou
konstanty `PUNTIKY_DOUBLE_PT_MULT` (2.0) a `PUNTIKY_DOUBLE_RISK` (0.5) v hlavičce
expertu.

Tlačítko se chová **střídavě** stejně jako `LONG` / `SHORT`, jen pracuje s celou
dvojicí:

| Stav směru | Text tlačítka | Co klik udělá |
|---|---|---|
| nic na trhu, návrh platný | `LONG 2x` / `SHORT 2x` (zeleně / červeně) | zadá oba STOP příkazy naráz |
| leží nevyplněný dvojitý vstup | `ZRUŠIT LONG 2x` / `ZRUŠIT SHORT 2x` (oranžově) | zruší **oba** ležící příkazy |
| dvojitý vstup se (částečně) vyplnil | `ZAVŘÍT LONG 2x` / `ZAVŘÍT SHORT 2x` (oranžově) | zavře obě pozice za trhu i příkaz, který ještě zbývá |
| ve směru leží **jednoduchý** obchod | `LONG 2x` / `SHORT 2x` (zešedlé) | nic — ten patří tlačítku `LONG` / `SHORT` |

Zešedne (klik nic neudělá) a důvod dá do bubliny také, když:

- návrh vstupu není platný (stejné důvody jako u jednoho obchodu),
- na poloviční riziko nevyjde ani nejmenší dovolený lot,
- **účet není hedgovací** — na nettingovém účtu by se dva příkazy stejného směru
  slily do jediné pozice a SL/PT druhého by přepsaly první, takže by z dvojitého
  vstupu zbyl jeden obchod se špatným cílem.

Poznámky:

- `PT2` se počítá **z délky vstupu**, tedy i tehdy, když `PT1` zkrátila hrana
  kanálu nebo reliéfní přímka. Druhý cíl pak leží za touto překážkou — je to
  záměr (druhá pozice má běžet dál), ale při zkráceném návrhu stojí za pohled,
  kam přesně `PT2` míří (je v bublině tlačítka i na řádku `poslední:`).
- Po vyplnění se u **každé** pozice dorovnají SL i PT na její skutečnou plnicí
  cenu, přičemž **každá větev si drží vlastní délku** — druhá pozice o svůj
  vzdálenější cíl skluzem nepřijde.
- `InpMaxPositions` (výchozí 1) dvojitý vstup neblokuje: brání jen vzniku
  *nového* návrhu, dokud je pozice otevřená. Dva příkazy se zadají, dokud žádná
  pozice neběží.

Další vlastnosti režimu:

- Expert **nesrovnává** ručně zadaný příkaz s návrhem (`SyncPendingOrders` v tomto
  režimu neběží) — co se zadalo tlačítkem, to na trhu leží beze změny, i když se
  návrh mezitím pohne. Nechtěný příkaz se odebere tlačítkem.
- Rekompilace, změna parametrů ani odebrání experta z grafu ručně zadaný příkaz
  **neruší** — zadal ho uživatel a nese vlastní SL a PT. Při odebrání experta se
  do Expert logu vypíše, kolik příkazů na trhu zůstává.
- Vyplnění se dál zachytává v `OnTradeTransaction`: SL a PT se dorovnají na
  skutečnou plnicí cenu a úroveň se označí za spotřebovanou, takže se na ní
  podruhé neobchoduje.
- Stav obou směrů je vidět v panelu na řádku `ruční režim:`
  (`lze zadat` / `není místo` / `příkaz` / `pozice`; u dvojitého vstupu i s počtem
  a značkou, např. `2 příkazy 2x` nebo `pozice + příkaz 2x`) a každý klik se
  zapíše na řádek `poslední:` i do Expert logu.
- Při `InpEnableTrading = false`, na nepovoleném účtu nebo se zakázaným
  obchodováním v terminálu tlačítka jen nahlásí `obchodování je vypnuto`.

### Tlačítko `PANEL` — zobrazení textového panelu v grafu

Nad tlačítky je fialový přepínač textového panelu, tedy toho bloku řádků pod
tlačítky (přehled kanálů, úrovně průrazu, návrhy vstupu, pozice, řádek
`poslední:`). Text tlačítka nese aktuální stav — `PANEL ZAP` / `PANEL VYP`.

- **Výchozí stav je vypnuto** (`InpShowPanel = false`), takže graf zůstane po
  startu čistý a vidět jsou jen tlačítka, kanály a úrovně. Zapne se kliknutím,
  případně natrvalo přepnutím `InpShowPanel` v nastavení experta.
- Týká se **jen výpisu v grafu**. Do Expert logu se píše pořád stejně, takže
  i se schovaným panelem je se kam podívat — každý klik, zadání i odebrání
  obchodu tam zůstává.
- Tlačítka samotná zůstávají viditelná vždy, schová se jen text pod nimi.
- Přepínač se kreslí ve **všech** režimech vstupu, ne jen v ručním.
- Objem výpisů do logu řídí dál `InpDiagnostics` (viz [Diagnostika](#diagnostika)),
  s tímto tlačítkem to nesouvisí.

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
  odblokuje; opakování na stejné úrovni zapne `InpHueRepeatMinutes` — s hodnotou
  N se upozornění posílá znovu každých N minut, dokud cena zůstává v pásmu
  a úroveň se nemění. Interval se měří od posledního **odeslaného** upozornění
  a kontrola běží jen na ticku, takže bez pohybu trhu se neopakuje.
- Odchod z pásma uvolní příznak až za **hysterezí** `InpHueResetFactor` × práh
  (výchozí 1,5, tedy 750 bodů při prahu 500), aby se při kolísání přesně na
  hranici neblikalo pořád dokola. Hodnota 1,0 hysterezi vypne — příznak se uvolní
  hned za prahem. Níž než 1 to jít nesmí: paměť by se uvolňovala ještě uvnitř
  pásma, ve kterém se hlásí, a upozornění by chodilo při každém návratu do něj.
- Cenu **za** úrovní vstupu (`dist < 0`) bere expert jako uvolnění příznaku vždy,
  na hysterezi nezávisle. Proto se při kolísání kolem samotné úrovně vstupu
  hlásí znovu, i když je `InpHueRepeatMinutes = 0`.
- Stav upozornění je vidět v panelu na řádku `Hue:` a odeslání se loguje do
  Expert logu i s tělem požadavku.

**Nutné povolení v terminálu:** Nástroje → Možnosti → Strategie →
*Povolit WebRequest pro uvedené URL* a přidat `http://192.168.0.157:8082`.
Bez toho volání skončí chybou 4014. Expert ji nenechá jen v logu — na řádek
`poslední:` v panelu napíše rovnou návod včetně adresy, kterou je třeba povolit
(adresa se bere z `InpHueUrl` bez cesty, tedy ve tvaru, jaký seznam povolených
URL očekává).
V testeru strategie `WebRequest` nefunguje, upozornění se tam přeskakuje.

Nad panelem je modré tlačítko **`TEST Hue`** (`InpHueTestButton`) — kliknutím se pošle
testovací požadavek s aktuální cenou Ask, takže jde ověřit spojení i povolení URL
bez čekání na skutečný průraz. Výsledek (`Hue test: HTTP 200`, nebo chyba) se
objeví v panelu na řádku `poslední:` a v Expert logu. Barvu má vlastní záměrně:
tmavá šeď je vyhrazená nedostupnému tlačítku, takže funkční tlačítko ji nikdy nemá.

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

1. **Nástroje → Možnosti → Strategie** → povolit algoritmické obchodování.
2. Otevřít graf `XAUUSD` (libovolný timeframe, kanály se kreslí podle `InpChannelTF1..4`).
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
  Include/Puntiky/PuntikyRelief.mqh            reliéfní přímky na TF reliéfu
  Include/Puntiky/PuntikyDraw.mqh              vykreslování kanálů, popisků, úrovní a panelu
scripts/deploy.cmd                       spouštěč (obchází ExecutionPolicy)
scripts/deploy.ps1                       kopie do terminálu + kompilace
```

## Přehled parametrů

### Timeframy
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpBreakoutTF` | H1 | svíčka, jejíž high/low se prorážejí |
| `InpEntryTF` | M1 | potvrzení vstupu uzavřenou svíčkou a vzorky spreadu |

### Timeframy kanálů
Kanály se hledají v každém zapnutém timeframu **zvlášť** a výsledky se míchají do
jednoho grafu; každý kanál si nese, ze kterého timeframu pochází (vidíš to
v bublině úsečky, v panelu i v diagnostice). Vypnutý slot se přeskočí, pořadí
slotů na výsledek nemá vliv a tentýž timeframe zadaný dvakrát se započítá jednou.

**První zapnutý** timeframe je zároveň *referenční*: počítá se z něj ATR (filtr
šířky kanálu, slučování popisků) a v jeho svíčkách se zadává `InpEdgeProjBars`,
tedy horizont, ke kterému se posuzují hrany i reliéfní přímky.

Vypnout **všechny** timeframy kanálů je legitimní nastavení — reliéfní přímky mají
vlastní timeframy i vlastní ATR, takže bez kanálů fungují dál. Horizont projekce
pak drží `InpEntryTF`.

| Parametr | Výchozí | Význam |
|---|---|---|
| `InpChannelTF1Use` / `InpChannelTF1` | true / M15 | 1. timeframe kanálů (referenční) |
| `InpChannelTF2Use` / `InpChannelTF2` | false / H1 | 2. timeframe kanálů |
| `InpChannelTF3Use` / `InpChannelTF3` | false / H4 | 3. timeframe kanálů |
| `InpChannelTF4Use` / `InpChannelTF4` | false / D1 | 4. timeframe kanálů |

### Timeframy reliéfu
Platí totéž co u kanálů. Timeframe reliéfu **už nesouvisí s `InpEntryTF`** — dřív
se přímky hledaly vždy na vstupním timeframu, takže změna potvrzovací svíčky
překreslila i celý reliéf.

| Parametr | Výchozí | Význam |
|---|---|---|
| `InpReliefTF1Use` / `InpReliefTF1` | true / M1 | 1. timeframe reliéfu |
| `InpReliefTF2Use` / `InpReliefTF2` | false / M5 | 2. timeframe reliéfu |
| `InpReliefTF3Use` / `InpReliefTF3` | false / M15 | 3. timeframe reliéfu |
| `InpReliefTF4Use` / `InpReliefTF4` | false / H1 | 4. timeframe reliéfu |

> Počty svíček (`InpLookbackBars`, `InpReliefLookback`, `InpMinSpanBars`,
> `InpReliefMinSpan`, `InpMaxAgeBars`, `InpForwardBars`, `InpReliefForwardBars`)
> i limity `InpMaxChannels` a `InpMaxReliefLines` platí pro **každý zapnutý
> timeframe zvlášť** — čtyři zapnuté timeframy tedy dají až čtyřnásobek útvarů.
> Prahy detekce (tolerance, skóre, filtry) jsou naopak společné.

### Úrovně průrazu
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpUseSwingLevels` | true | prorážet jen swingové H1 svíčky |
| `InpBreakSwingDepth` | 2 | šířka okna pro H1 swingy |
| `InpBreakLookback` | 300 | kolik H1 svíček se prohledává |

### Detekce kanálů
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpLookbackBars` | 1500 | kolik svíček se analyzuje v každém TF kanálu |
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
| `InpEntryMode` | MANUAL | ruční tlačítka, pending STOP příkazy, nebo potvrzení uzavřením M1 |
| `InpMaxEntryPoints` | 300 | maximální délka vstupu |
| `InpMinEntryPoints` | 150 | pod touto délkou se nevstupuje |
| `InpBreakoutBuffer` | 10 | buffer za úrovní průrazu |
| `InpMaxLevelOffset` | 30 | max. odstup tržního vstupu od úrovně (režim M1_CLOSE) |
| `InpEdgeBuffer` | 20 | rezerva PT před hranou kanálu |
| `InpEdgeProjBars` | 12 | **strop** projekce hran dopředu (skutečná délka vyjde z `InpMaxEntryPoints / ATR`) |
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
| `InpReliefLookback` | 7200 | kolik svíček se analyzuje v každém TF reliéfu (na M1 5 dní) |
| `InpReliefSwingDepth` | 25 | šířka okna pro hlavní swingy (zároveň dosah do minulosti) |
| `InpReliefScales` | 4 | počet měřítek swingů (25/50/100/200) |
| `InpReliefSwingGap` | 20 | max. odstup opor (počet swingů) |
| `InpReliefMinSpan` | 120 | minimální délka přímky ve svíčkách |
| `InpReliefMinTouches` | 0 | minimální počet dotyků **mimo vlastní opory přímky** (0 = stačí čistá spojnice) |
| `InpReliefPierceTol` | 10 | proříznutí přímky tělem svíčky (body) |
| `InpReliefPierceATR` | 0.15 | totéž jako násobek ATR (0 = jen bodová mez) |
| `InpReliefWickTol` | 150 | povolený přesah přímky knotem mezi oporami (body) |
| `InpReliefWickATR` | 1.00 | totéž jako násobek ATR (0 = jen bodová mez) |
| `InpReliefTouchTol` | 25 | tolerance dotyku (body) |
| `InpReliefTouchATR` | 0.35 | totéž jako násobek ATR (0 = jen bodová mez) |
| `InpReliefDedupTol` | 40 | práh shody dvou přímek (body) |
| `InpReliefMaxAge` | 0.0 | platnost přímky za 2. oporou v násobcích délky (0 = neomezeno) |
| `InpReliefMaxDrift` | 3000 | max. vzdálení přímky od 2. opory (body; 0 = filtr vypnutý) |
| `InpReliefMaxDriftATR` | 4.0 | totéž jako násobek ATR — platí větší z obou mezí |
| `InpReliefMaxDist` | 1500 | max. vzdálenost přímky od **ceny** (body; 0 = filtr vypnutý) |
| `InpReliefMaxDistATR` | 8.0 | totéž jako násobek ATR — platí větší z obou mezí |
| `InpReliefMaxGap` | 2000 | max. průměrný odstup přímky od ceny mezi oporami (body; 0 = vypnuto) |
| `InpReliefMaxGapATR` | 5.0 | totéž jako násobek ATR — platí větší z obou mezí |
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
| `InpShowPoints` | true | kreslit opory A B C D … (nezávisle na `InpShowChannels`) |
| `InpShowBreakLevels` | true | kreslit úrovně průrazu |
| `InpShowEntryLevels` | true | kreslit úrovně plánovaného vstupu |
| `InpShowRelief` | true | kreslit reliéfní přímky |
| `InpShowPanel` | **false** | výchozí stav textového panelu; za běhu ho přepíná tlačítko `PANEL` |
| `InpForwardBars` | 30 | prodloužení kanálů doprava (svíčky vlastního TF kanálu) |
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
| `InpHueResetFactor` | 1.50 | hystereze — paměť se uvolní až za N× prahem (1 = bez hystereze) |
| `InpHueRepeatMinutes` | 0 | opakovat upozornění po N minutách (0 = jen jednou) |
| `InpHueTimeout` | 1000 | timeout HTTP požadavku (ms) |
| `InpHueTestButton` | true | zobrazit tlačítko `TEST Hue` nad panelem |

### Diagnostika
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpDiagnostics` | true | výpis detekce kanálů a reliéfu do Expert logu |
| `InpShotOnRequest` | true | snímek grafu na vyžádání (viz níže) |
| `InpShotEveryBars` | 0 | snímek každých N přepočtů kanálů (0 = vypnuto) |
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
