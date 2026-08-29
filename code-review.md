# Code review – Puntiky Channel Breakout EA (MQL5)

| | |
|---|---|
| **Datum** | 29. 8. 2026 |
| **Rozsah** | celý zdrojový kód (ne jen poslední commit): `MQL5/Experts/Puntiky/PuntikyChannelBreakout.mq5` (4037 ř.), `MQL5/Include/Puntiky/PuntikyChannels.mqh` (674), `PuntikyRelief.mqh` (529), `PuntikyDraw.mqh` (349), `PuntikyTypes.mqh` (330), `PuntikySwings.mqh` (163) – celkem 6082 řádků |
| **Stav kódu** | commit `13f8b84` (v1.20). **Čísla řádků odpovídají tomuto commitu.** Hledací fáze běžela nad předchozím stavem `54e84b3` (v1.18), ověřovací fáze nad `13f8b84`; commit `13f8b84` mezitím opravil nález K1 (viz kap. 5) |
| **Úroveň** | xhigh – 10 hledacích agentů (5 úhlů pro chyby + reuse, zjednodušení, efektivita, „altitude“, konvence), poté 6 nezávislých ověřovatelů; každý kandidát dohledán v aktuálním kódu |
| **Verdikty** | **POTVRZENO** – mechanismus dohledán v kódu a scénář je dosažitelný. **PRAVDĚPODOBNÉ** – mechanismus v kódu existuje, výsledek ale závisí na neověřeném chování terminálu MT5/brokera nebo na vzácné podmínce. **ZAMÍTNUTO** – kód to řeší, je to dokumentovaný záměr, nebo se tvrzení nepotvrdilo |

## Shrnutí

* **21 chyb** (4 high, 7 medium, 10 low), **17 návrhů na úklid** (5 medium, 12 low), **2 porušení konvencí**, 7 kandidátů zamítnuto.
* Tři nejzávažnější nálezy mají **společný kořen**: tickový test průrazu v `UpdateArming` (bid + mediánový spread) okamžitě vymění úroveň a rekonciliace `SyncOneDirection` zruší/přesune ležící příkaz při jakékoli změně nebo neplatnosti plánu, bez ohledu na důvod. Důsledky:
  * režim **M1_CLOSE se swingovými úrovněmi prakticky neobchoduje** (L1) a tam, kde obchoduje, ignoruje spotřebovanou úroveň (L2);
  * v režimu **PENDING se ležící STOP příkaz zruší nebo přesune těsně před vyplněním** – při spreadové špičce (L3) i při přiblížení ceny na stop-level brokera (L4);
  * v obsluze vyplnění se **právě zrušený OCO příkaz může hned znovu zadat** (K2).
* Commit `13f8b84` správně opravil označování špatné úrovně po vyplnění (K1); nový kód přinesl jen dva drobné okrajové případy (K6, K7).
* Největší úklid s reálným přínosem: jedno `RebuildPlans` na tick místo tří (E1), nedokončený refaktor `lotsDouble` (U2), sjednocené hlášení do panelu i logu (U5), mrtvá pole `barrierPrice` / `SChannel.valid` (U7).

Doporučené pořadí oprav je v kapitole 6.

---

## 1. Chyby – vysoká závažnost

### L1 – Režim M1_CLOSE se swingovými úrovněmi nikdy nevstoupí (úroveň se vymění uvnitř svíčky)
`PuntikyChannelBreakout.mq5:485` · POTVRZENO · high

**Problém.** V `InpEntryMode = PUNTIKY_ENTRY_M1_CLOSE` s `InpUseSwingLevels = true` se úroveň spotřebuje a vymění už prvním tickem za ní: `UpdateArming` (ř. 478 → 2077–2078) nastaví `g_buyBroken`, `brokenChanged` (ř. 479) vyvolá `RefreshBreakoutLevels` (ř. 485), `SwingBroken`/`LevelBrokenNow` (ř. 1950, 1913) vidí high otevřené H1 svíčky, úroveň A přeskočí a `ApplyBreakLevel` (ř. 1977) nastaví starší, vyšší swing B a `g_buyArmed = false`. Na uzavření M1 svíčky pak `CheckEntryOnEntryTF` (ř. 456, 3099–3100) porovnává close s B → `crossed = false` → žádný vstup. Vstup projde jen tehdy, když `FindBreakoutSwings` nenajde žádný starší neproražený swing (`foundHi = false`).

**Scénář.** `g_breakHigh = A`, existuje starší neproražený swing B > A. Uprostřed minuty `bid + refSpread >= A + buffer` → úroveň se přepne na B. Na prvním ticku další minuty se close testuje proti B → nic. Pokud close prošel i B, byl při swapu bid už nad B a `UpdateArming` (ř. 2053) směr nenabil → blok „čeká na návrat pod úroveň“.

**Poznámka.** Ochrana popsaná v komentáři ř. 451–454 řeší jen hodinový `RefreshBreakoutLevels` (ř. 472), ne tickový swap. Snapshot úrovně z otevření baru neexistuje. Při `InpUseSwingLevels = false` swap nenastane a vstup funguje.

**Oprava.** V režimu M1_CLOSE nedělat tickový swap úrovně (ř. 485) – odložit ho až za `CheckEntryOnEntryTF`; nebo si při otevření M1 svíčky uložit snapshot úrovně (cena + čas) a v `CheckEntryOnEntryTF` porovnávat close proti snapshotu. Řešit společně s L2.

### L3 – Průraz BUY se detekuje z bid + medián spreadu, broker plní na živém asku → příkaz se přesune/zruší těsně před vyplněním
`PuntikyChannelBreakout.mq5:2077` · POTVRZENO · high

**Problém.** `ExecPrice` (ř. 1332–1334) přičítá pro BUY vždy `ReferenceSpread()` (medián, ř. 1304), nikdy živý ask. `UpdateArming` (ř. 2077) tuto hodnotu testuje proti úrovni, na níž leží reálný BUY STOP. Je-li medián větší než okamžitý spread (statisticky zhruba polovina času), expert prohlásí úroveň za proraženou dřív, než ji dosáhne ask. SELL strana (ř. 2079, `bid <= L − buffer`) je totožná s podmínkou serveru a netrpí.

**Scénář.** PENDING, BUY STOP na `A + buffer` (ř. 2098), `refSpread = 25 b`, živý spread 18 b. Bid = `A + buffer − 25` → `PriceBeyondLevel` platí, ask = `bid + 18 < A + buffer` → nevyplněno. `brokenChanged` → `RefreshBreakoutLevels` → A přeskočena → `ApplyBreakLevel(B)` + `RebuildPlans` → `SyncPendingOrders` (ř. 492) → `SyncOneDirection`: `DeleteOrder + PlaceStopOrder` (ř. 2581) nebo `OrderModify` na `B + buffer` (ř. 2586); nebo při `foundHi = false` plán neplatný (ř. 2163) → `DeleteOrder` (ř. 2553). Další tick `ask >= A + buffer`: příkaz už neleží, průraz A propásnut.

**Oprava.** V `UpdateArming` (a v `LevelBrokenNow` pro otevřenou svíčku) testovat BUY proti živému asku (`SymbolInfoDouble(SYMBOL_ASK) >= level + buffer`); medián nechat jen pro historické svíčky. V pending režimu navíc nerušit příkaz, dokud ask nepřekročil jeho cenu.

### L4 – Přiblížení ceny na stop-level brokera zneplatní plán a ležící STOP příkaz se smaže
`PuntikyChannelBreakout.mq5:2553` · POTVRZENO · high

**Problém.** `EntryBlockReason` (ř. 2172–2175) vrací „blíž než stop-level brokera“ i pro úroveň, na které příkaz už leží; `SyncOneDirection` (ř. 2550–2555) ruší příkaz při jakémkoli důvodu neplatnosti plánu. Stop-level přitom omezuje jen zadání/úpravu příkazu, ne jeho držení. Stop-level je správně hlídán při zadání (`PlaceStopOrder` ř. 2515–2521).

**Scénář.** PENDING, `SYMBOL_TRADE_STOPS_LEVEL = 30 b`, freeze level 0, BUY STOP na `A + buffer`. Ask vystoupá na `A + buffer − 20`. Na otevření další M1 svíčky `RebuildPlans` (ř. 488) → `entry <= ask + stops` → `pl.valid = false` → `g_ordersDirty` → `SyncPendingOrders` → `OrderIsFrozen = false` → `DeleteOrder`. Cena projde `A + buffer` bez příkazu; expert označí A za proraženou a přeskočí dál. Při ústupu ceny se příkaz zase zadá (ř. 2504) – příkaz u úrovně střídavě mizí a vzniká. Maskováno jen u brokerů s freeze level ≥ stops level nebo stops level 0.

**Oprava.** V `SyncOneDirection` rušit ležící příkaz jen z důvodů, které znamenají spotřebovanou/změněnou úroveň (broken, taken, jiná úroveň, limit pozic); nebo v `EntryBlockReason` vracet stop-level důvod jen tehdy, když příkaz ještě neleží.

### K2 – Okamžité `SyncPendingOrders()` v obsluze DEAL_ADD znovu zadá právě zrušený opačný příkaz
`PuntikyChannelBreakout.mq5:604` · PRAVDĚPODOBNÉ · high

**Problém.** Pořadí v `OnTradeTransaction`: `RebuildPlans()` (ř. 600) → `CancelOppositeOrder()` (ř. 603) → `SyncPendingOrders()` (ř. 604) → `g_ordersDirty = true` (ř. 608). Vlastní komentář ř. 595–599 připouští, že `PositionsTotal()` novou pozici ještě nemusí vidět. Pak `EntryBlockReason` pro opačný směr vrátí `CountPositions() = 0` → plán protistrany zůstane platný → `SyncOneDirection` vidí `ticket = 0` → `PlaceStopOrder` (ř. 2558–2561) opačný STOP znovu zadá.

**Scénář.** PENDING, `InpMaxPositions = 1`, oba STOPy leží. BUY STOP se vyplní; SELL STOP je smazán a v témže handleru zase zadán. Whipsaw ho vyplní → 2 pozice navzdory `InpMaxPositions = 1`. **Deterministická varianta bez externího předpokladu:** při `InpMaxPositions >= 2` je plán protistrany platný vždy, takže OCO zrušení se okamžitě odvolá – dva zbytečné požadavky na server a OCO záměr neplatí. Vedlejší efekt: vyplněný příkaz může ještě ležet v `OrdersTotal`, plán jeho směru je neplatný („tato úroveň už obchodována“, ř. 2141) → `DeleteOrder` na něj a chyba v logu.

**Proč PRAVDĚPODOBNÉ.** Zda je pozice v okamžiku DEAL_ADD už v `PositionsTotal()`, je vlastnost terminálu.

**Oprava.** Odstranit okamžité `SyncPendingOrders()` (ř. 604) i redundantní ř. 608 – `g_ordersDirty` už nastavil `RebuildPlans` (ř. 2109) a další tick provede sync (ř. 491–492) nad srovnaným účtem. Případně `EntryBlockReason` doplnit o započtení pozice z `DEAL_POSITION_ID`.

---

## 2. Chyby – střední závažnost

### L2 – Tržní vstup (M1_CLOSE) ignoruje příznak „proraženo“ a vstoupí na spotřebované úrovni
`PuntikyChannelBreakout.mq5:2149` · POTVRZENO · medium

`EntryBlockReason` při `atMarket = true` přeskakuje test `g_buyBroken/g_sellBroken` (ř. 2149–2157; komentář ř. 2117–2121 přitom tuto chybu prohlašuje za opravenou). Když `FindBreakoutSwings` nenajde náhradní swing (`foundHi = false`, ř. 2048–2051), stará úroveň i `g_buyBroken = true` zůstanou; `g_buyArmed` (ř. 2084–2085) se při návratu ceny pod úroveň znovu nastaví. Další M1 close nad A → `BuildPlan(atMarket)` → `OpenMarket` na úrovni, kterou pending režim blokuje (ř. 2163 „úroveň už byla proražena“). Totéž při `InpUseSwingLevels = false` při každém zpětném průrazu high poslední H1 svíčky. Výjimka je dnes nutná kvůli L1 (na ticku close je broken už nastaven).

**Oprava.** Zavést čas prvního průrazu (`g_buyBrokenTime`) a při `atMarket` blokovat, pokud k průrazu došlo před otevřením právě uzavřené M1 svíčky; řešit společně s L1.

### R3 – Vstup se zamítne kvůli reliéfní přímce, kterou právě uzavřená průrazová svíčka sama prorazila
`PuntikyChannelBreakout.mq5:456` · POTVRZENO · medium

`CheckEntryOnEntryTF` (krok 1, ř. 455–456) běží před `RecalcRelief`/`RevalidateRelief` téhož ticku (krok 3, ř. 467–468). `PuntikyNearestRelief` (PuntikyRelief.mqh ř. 507–516) porovnává hodnotu přímky se spouštěčem, ne s ask; `BuildPlan` měří vzdálenost od vstupu s ořezem na 0 (ř. 2259–2260). Přímka mezi triggerem a ask tak vždy dá 0 b → SHORTEN: „málo místa k reliéfní přímce (0 b)“ (ř. 2281–2285), SKIP: „v cestě reliéfní přímka“ (ř. 2264–2271). O pár řádků později `RevalidateRelief` (ř. 1772) tutéž přímku smaže, ale další M1 svíčka má `wasBefore = false` → vstup definitivně ztracen. Přímky kotvené na průrazovém swingu do pásma padají systematicky.

**Oprava.** Při `newEntryBar` zavolat `RevalidateRelief()` před krokem 1 (levné); nebo v `BuildPlan(atMarket = true)` ignorovat přímky, jejichž hodnota už leží pod ask (BUY) / nad bid (SELL) o víc než `pierceTol`.

### L5 – Jediný vzorek spreadu při startu; medián „teď“ se aplikuje na historické svíčky
`PuntikyChannelBreakout.mq5:359` · POTVRZENO · medium

`OnInit` volá `SampleSpread()` jednou (ř. 359) a hned `TryInitialCalc` (ř. 389) → `RefreshBreakoutLevels` (ř. 894) → `SwingBroken` (ř. 1950/1910) s `g_spreadRef` = jediný vzorek. Start během rolloveru (spread 500 b místo 25 b) prohlásí za proražený každý vrchol, k němuž se pozdější high přiblížil na 490 b → úroveň skočí o stovky bodů na starý swing a v PENDING `SyncPendingOrders` (ř. 905) tam ihned zadá příkaz; normalizuje se až po 3. vzorku, úroveň se přepočítá až s další H1 svíčkou. Za běhu se medián posouvá a přičítá k historickému `rates[i].high`, takže uzavřený swing mění stav proraženo/neproraženo bez pohybu ceny; `ApplyBreakLevel` (ř. 2000–2001) pak resetuje armed/taken. Pole `MqlRates.spread` se nikde nepoužívá.

**Oprava.** Při startu naplnit vzorky ze spreadů historických M1 svíček (`rates[i].spread`) nebo počkat na min. 3 vzorky před prvním `RefreshBreakoutLevels`; pro historické svíčky používat spread dané svíčky místo aktuálního mediánu.

### M1 – `OnDeinit` ruší pending příkazy jen pro REASON_REMOVE
`PuntikyChannelBreakout.mq5:414` · POTVRZENO · medium

`if(reason == REASON_REMOVE && TradingEnabled())`. Zavření grafu (REASON_CHARTCLOSE), aplikace šablony (REASON_TEMPLATE), REASON_PROGRAM i změna symbolu (REASON_CHARTCHANGE – nový `OnInit` už příkazy starého symbolu nevidí, `IsOurOrder` filtruje přes `_Symbol`, ř. 1035–1039) expert trvale odstraní, ale příkazy zůstanou na serveru bez OCO a bez dozoru; „následný OnInit“ z komentáře ř. 410–411 nepřijde. README ř. 214–216 slibuje zrušení při odebrání z grafu. Guard `TradingEnabled()` je pro `InpEnableTrading = false` záměr; při vypnutém AutoTrading by `OrderDelete` stejně selhal – chybí ale varování do logu, že příkazy zůstávají.

**Oprava.** V PENDING rušit vždy kromě REASON_RECOMPILE, REASON_PARAMETERS, REASON_CLOSE (a REASON_CHARTCHANGE jen při změně periody); při `TradingEnabled() == false` vypsat do logu počet ponechaných příkazů. Upravit komentář ř. 408–411.

### M3 – Úklid osiřelých příkazů v režimu M1_CLOSE proběhne jen jednou a jen při povoleném obchodování
`PuntikyChannelBreakout.mq5:383` · POTVRZENO · medium

Ř. 383–384 je jediné místo, kde se v M1_CLOSE sahá na pending příkazy; všechny ostatní cesty jsou podmíněné PENDING (ř. 491, 601, 904). Scénář: expert běžel v PENDING, uživatel vypne AutoTrading, přepne na M1_CLOSE (REASON_PARAMETERS) → `TradingEnabled()` false → úklid přeskočen; zapnutí AutoTrading `OnInit` nevyvolá. M1 close za úrovní → `OpenMarket` (příkazy `EntryBlockReason` nepočítá), pak se vyplní i starý STOP → druhá pozice s plným rizikem, expert ji neřídí. README ř. 216–217 slibuje úklid při startu bez výhrady.

**Oprava.** Držet příznak „úklid čeká“ a v `OnTick`/`OnTimer` ho zopakovat, jakmile `TradingEnabled()` platí a `CountOrders() > 0`; při přeskočení vypsat varování.

### K3 – U tržního vstupu se SL/PT dorovnávají dvakrát a druhé dorovnání vrátí původní hodnoty
`PuntikyChannelBreakout.mq5:588` · PRAVDĚPODOBNÉ · medium

`OpenMarket` (ř. 2754–2756) pošle Buy s absolutním SL/TP a pak `AdjustPositionStops(posId, d, d)` (ř. 2768) nastaví `sl = fill − d`, `tp = fill + d`. Po `OnTick` se zpracuje DEAL_ADD: obsluha (ř. 509–611) nečte `ORDER_TYPE` a z `ORDER_PRICE_OPEN/ORDER_SL/ORDER_TP` počítá délky (ř. 589–591). Pokud terminál u vyplněného tržního příkazu drží v `ORDER_PRICE_OPEN` cenu plnění, vyjde `slDistance = d + skluz`, `tpDistance = d − skluz` a `AdjustPositionStops` (ř. 2727–2735) vrátí SL/PT na `E ± d` – RRR není 1:1, liší se o 2× skluz; každý tržní vstup stojí dva `PositionModify`. Pořadí (DEAL_ADD až po `OnTick`) je jisté, sémantika `ORDER_PRICE_OPEN` je vlastnost terminálu.

**Oprava.** V obsluze přeskočit dorovnání pro `ORDER_TYPE_BUY/SELL` (postaral se `OpenMarket`), nebo dorovnávat jen na jednom místě – v obsluze z `DEAL_PRICE`/`DEAL_SL`/`DEAL_TP` – a z `OpenMarket` to odstranit.

### R2 – `BarIndexNow` při `Bars() == 0` dopočítá index z nástěnného času (víkend = tisíce neexistujících barů)
`PuntikyChannelBreakout.mq5:965` · PRAVDĚPODOBNÉ · medium

Fallback ř. 964–965 se použije, kdykoli `Bars(_Symbol, tf, refTime, now)` nevrátí kladné číslo (ř. 960–961) – podle dokumentace se to děje, když řada není synchronizována (po startu/reconnectu). Přes víkend vyjde `refIdx + ~192` barů M15 (resp. +2880 M1) místo +1..3. `ChannelBarNow()` v `BuildPlan` (ř. 2208) posune šikmé hrany o 192 barů; v PENDING `SyncPendingOrders` přepíše SL/PT ležících příkazů; `RevalidateRelief` (ř. 1761, 1779–1780) zamítne každou skloněnou přímku jako „drifted“. Jakmile `Bars()` začne vracet data, index se opraví; spouštěč závisí na časování synchronizace.

**Oprava.** Při `Bars() <= 0` nevracet extrapolaci z času, ale poslední známý dobrý index (cache) nebo `refIdx`; případně `iBarShift(refTime)`, a k času se vracet jen s explicitním logem.

---

## 3. Chyby – nízká závažnost

### K5 – `OnTradeTransaction` nemá guard `TradingEnabled()` – instance jen pro kreslení volá `PositionModify`
`PuntikyChannelBreakout.mq5:593` · POTVRZENO · low

Obsluha (ř. 509–611) nemá early-return pro vypnuté obchodování; `AdjustPositionStops` (ř. 2713–2738) kontroluje jen ticket, délku a `IsOurPosition`. Instance s `InpEnableTrading = false` / jiným `InpAllowedAccount` a stejným magic tak po cizím vyplnění pošle `PositionModify` – v rozporu se zásadou ř. 1207–1211. Prakticky obě instance spočítají totéž (přeskočení díky toleranci nebo chyba „no changes“). Ostatní obchodní cesty guard mají (ř. 2602, 2643, 2747, 2998, 3044, 383, 414).
**Oprava.** `if(!TradingEnabled()) return;` před ř. 593 (stav úrovně `g_*Taken`/GV nechat zapisovat i bez obchodování).

### K7 – Obrat pozice na nettingu (`DEAL_ENTRY_INOUT`) obsluha ignoruje
`PuntikyChannelBreakout.mq5:525` · POTVRZENO · low

Ř. 525–526 a `LevelRecordConfirmed` ř. 1434–1435 filtrují výhradně `DEAL_ENTRY_IN`. Na nettingovém účtu (MANUAL: LONG i SHORT STOP zadané, SELL s větším objemem otočí pozici) vznikne jediný obchod INOUT → úroveň se nespotřebuje, GV se nezapíše, stopy se nedorovnají, v PENDING se nezruší opačný příkaz. Dopad malý – expert netting nepreferuje (`ManualPlaceDouble` ho odmítá, ř. 2841).
**Oprava.** Přijímat i `DEAL_ENTRY_INOUT` (ř. 525, 1434), nebo netting odmítnout v `OnInit`.

### K6 – `LevelWasTaken` (nový kód z 13f8b84) nevratně smaže záznam při neúplné historii účtu
`PuntikyChannelBreakout.mq5:1404` · PRAVDĚPODOBNÉ · low

Ř. 1421–1422 ošetřuje jen selhání `HistorySelect`, ne neúplnost vrácených dat; ř. 1404 maže bez návratu, a to i při startu experta (`TryInitialCalc` → `ApplyBreakLevel` → `LevelWasTaken`). Scénář: restart po vyplnění BUY na L1, kde průraz nebyl detekován (spreadová špička – záznam v GV je jediná ochrana), historie ještě nedosynchronizovaná → záznam smazán → po zavření pozice se L1 nabídne a v PENDING zadá podruhé. Ostatní části nového kódu (znaménko offsetu pro SELL ř. 1460, četnost `HistorySelect` jen při změně úrovně, částečná plnění, mazání během zpracování obchodu) jsou v pořádku.
**Oprava.** Mazat jen při jistotě (ne při startu experta, nebo až po první úspěšné konfirmaci v běhu); případně záznam jen ignorovat s logem.

### K4 – Selhání `HistoryOrderSelect` v DEAL_ADD tiše přeskočí dorovnání stopů
`PuntikyChannelBreakout.mq5:541` · PRAVDĚPODOBNÉ · low

Ř. 541–547 nemá else větev s logem; při selhání zůstane `slDistance = 0` a `AdjustPositionStops` se nezavolá (ř. 592); nic se nezopakuje. Stejně tiše selhává `AdjustPositionStops`, když `PositionSelectByTicket` pozici ještě nevidí (ř. 2718–2719). Robustnější zdroj je k dispozici: obchod je už vybraný (`HistoryDealSelect` ř. 521) → `DEAL_PRICE`/`DEAL_SL`/`DEAL_TP`.
**Oprava.** Délky brát z obchodu (fallback na příkaz), selhání logovat, případně dorovnání odložit na další tick (pamatovat `posId`).

### M4 – `LooksDoubleEntry` překlasifikuje obyčejnou pozici na „dvojitý vstup“, jakmile uživatel přitáhne SL
`PuntikyChannelBreakout.mq5:1080` · POTVRZENO · low

Geometrická záloha (ř. 1069–1080: `tpDist > 1,5 × slDist` ⇒ DOUBLE) se uplatní i na pozici s naším komentářem `PUNTIKY BUYSTOP` (ř. 2522–2523), protože ten neobsahuje „2x“. SL přitažený z 300 na 100 b → tlačítko LONG zešedne (ř. 3437–3444), klik nic neudělá (ř. 3010–3016), 2x ukáže „ZAVŘÍT LONG 2x“ (ř. 3562–3564), panel „pozice 2x“; SL na breakeven (ř. 1076–1077) vrátí SINGLE – bliká. Pozici lze stále zavřít tlačítkem 2x (`ManualRemoveDirection` nerozlišuje kind).
**Oprava.** Geometrii použít jen když komentář neobsahuje „PUNTIKY“ (byl přepsán); náš prefix bez „2x“ ⇒ false.

### M6 – `TextSetFont` s kladnou velikostí měří menší písmo, než tlačítko kreslí
`PuntikyChannelBreakout.mq5:3325` · POTVRZENO · low

Dokumentace: kladná hodnota = pixely nezávislé na OS, záporná = desetiny bodu („multiply by −10 to make the size similar to OBJ_LABEL“). Kód posílá `+InpPanelFontSize`, `PuntikyButton` (PuntikyDraw.mqh ř. 171) nastavuje `OBJPROP_FONTSIZE` v bodech. Komentář ř. 3317–3320 a README ř. 403–405 tvrdí opak dokumentace. Před oříznutím chrání jen pevná šířka 226 (ř. 3350); při `InpPanelFontSize = 14` a škálování 150 % se text ořízne („AVŘÍT SHORT 2x“) – symptom, který má podle ř. 164–168 měření řešit.
**Oprava.** `TextSetFont("Consolas", -InpPanelFontSize * 10)`; opravit komentář i README.

### M5 – Ceny se nezarovnávají na `SYMBOL_TRADE_TICK_SIZE`
`PuntikyChannelBreakout.mq5:2200` · PRAVDĚPODOBNÉ · low

Normalizace jen na `_Digits` (ř. 2200, 2296–2297, 2728–2729, 2866–2869, 3602–3604). Na nástroji s tick size > `_Point` (indexové CFD, 0,25) by broker vracel INVALID_PRICE/INVALID_STOPS, PENDING by to zkoušel každou M1 svíčku a panel by hlásil „připraven“. Dokumentovaný cíl je forex a XAUUSD (README ř. 14), kde tick size = `_Point` – mimo deklarovaný rozsah.
**Oprava.** `AlignToTick(price)` pro entry/SL/TP, nebo v README uvést podporované nástroje.

### R1 – `RevalidateRelief` kontroluje jen shift 1; bary vzniklé bez ticku se nikdy neprověří
`PuntikyChannelBreakout.mq5:1753` · PRAVDĚPODOBNÉ · low

`IsNewBar` (ř. 916–923) je jediný příznak, `RevalidateRelief` čte jen shift 1 (ř. 1753–1756), čítač `g_reliefBarsSinceBuild` (ř. 1709) počítá události, ne bary. Po výpadku spojení zůstane přímka proražená v nepozorovaném baru v `g_relief` až 15 detekovaných barů a zkracuje PT / blokuje vstup. Vyžaduje výpadek + průraz a návrat během nepozorovaných barů.
**Oprava.** Pamatovat čas naposledy prověřené svíčky a projít všechny uzavřené bary od něj; čítač zvyšovat o skutečný počet barů. Souvisí s R5.

### R4 – Test „hrana ve směru obchodu“ bez tolerance vs. dotyk hrany s tolerancí
`PuntikyChannels.mqh:635` · PRAVDĚPODOBNÉ · low

`vNow <= price → přeskočit` (ř. 635–636) nemá toleranci, `TouchesUpperAtBar` (PuntikyTypes.mqh ř. 239–243) má pásmo −tol…+2·tol. Trigger 1 b pod hranou → „málo místa k hraně kanálu (0 b)“ (BuildPlan ř. 2234–2235), 1 b nad → plné PT 300 b. Zda je to chyba, je nedokumentované návrhové rozhodnutí; postihuje jen swingy v pásmu ±tol.
**Oprava.** Rozhodnout záměr a sjednotit tolerance na obou místech.

### E11 – Výběr kanálů přiděluje sloty po měřítkách; při `InpMaxChannels < InpSwingScales` se hrubé měřítko nikdy nedostane na řadu
`PuntikyChannels.mqh:525` · PRAVDĚPODOBNÉ · low

Smyčka ř. 525–536 bere prvního ne-duplicitního kandidáta měřítka s od nejjemnějšího a `break`; 2. fáze (ř. 539–544) pak nemá volné místo. Při `InpMaxChannels = 2`, `InpSwingScales = 3` se globálně nejlepší kanál měřítka 2 (velký kanál – podle komentáře ř. 520–523 cíl) vyloučí. Výchozí konfigurace (4/3) netrpí; `ValidateInputs` vztah nekontroluje.
**Oprava.** Sesbírat nejlepšího kandidáta každého měřítka, seřadit podle skóre a vzít top `maxChannels`; nebo aspoň `ValidateInputs: InpMaxChannels >= InpSwingScales`.

---

## 4. Úklid – reuse, zjednodušení, efektivita

### E1 – `RebuildPlans` běží až 3× a `UpdateArming` 2× v jednom ticku, `RedrawChannels` při startu 2×
`PuntikyChannelBreakout.mq5:463` · POTVRZENO · medium

`RefreshBreakoutLevels` (ř. 2053, 2058) dělá totéž, co kroky 2 a 5 v `OnTick` (ř. 463, 478, 488). Na hranici TF průrazu: 3× `RebuildPlans` (každé = 2× `CountPositions`, 4× `CalcLot`, 2× hledání hran/reliéfu, ~110 `Object*` v `DrawEntryLevels`) a 5–7× `ChartRedraw`; na M15 hranici 2×. Mezi voláními nikdo mezivýsledek `g_planBuy/g_planSell` nečte (`SyncPendingOrders` až v kroku 6, `CheckHueAlerts` v kroku 7). `TryInitialCalc` (ř. 892–894): `RecalcChannels` → `RedrawChannels`, pak `RecalcRelief(true)` → `DrawRelief` → `RedrawChannels` znovu.
**Návrh.** `plansDirty = newChannelBar || newEntryBar || newBreakoutBar || brokenChanged` a jediné `RebuildPlans()` po kroku 5; z `RefreshBreakoutLevels` vyhodit `RebuildPlans` (`UpdateArming` tam kvůli pořadí nechat); `TryInitialCalc` volá `UpdateArming(); RebuildPlans();` explicitně před `SyncPendingOrders` (ř. 905). Překreslení kanálů jednou v místě, které zná pořadí relief → kanály.

### U2 – `ManualPlaceDouble` počítá objem znovu, ačkoli `BuildPlan` už ukládá `lotsDouble`; PT2 opsáno 2×
`PuntikyChannelBreakout.mq5:2850` · POTVRZENO · medium

`BuildPlan` (ř. 2307–2310) plní `pl.lotsDouble`/`doubleReason` (přidáno v `54e84b3`, PuntikyTypes.mqh ř. 318–322), `DrawManualDoubleButton` (ř. 3600–3601) je čte, ale `ManualPlaceDouble` (ř. 2848–2857) volá `CalcLot(..., PUNTIKY_DOUBLE_RISK)` znovu – bublina ukazuje objem z posledního `RebuildPlans`, klik zadá objem z aktuální equity; `ManualPlace` (ř. 2790–2816) přitom bere `pl.lots` z návrhu. Vzorec PT2 `NormalizeDouble(entry ± distance*PUNTIKY_DOUBLE_PT_MULT)` je na ř. 2866–2869 a 3602–3604; kontrola `pl.valid` s hlášením ř. 2794–2799 = 2831–2836.
**Návrh.** `SEntryPlan.tpDouble` plněný v `BuildPlan`; `ManualPlaceDouble` použije `pl.lotsDouble/doubleReason/tpDouble`; `DrawManualDoubleButton` čte `pl.tpDouble`; volitelně `ManualPlace(pl, isDouble)`.

### U5 – Dvojice `g_lastEvent = …; Print(...)` 18×, na třech místech chybí výpis do logu
`PuntikyChannelBreakout.mq5:2798` · POTVRZENO · medium

Dvojice: ř. 318–319, 571/575–578, 2760–2762, 2770–2778, 2796–2798, 2809–2815, 2833–2835, 2843–2844, 2853–2855, 2884–2886, 2890–2897, 2982–2983, 3000–3001, 3011–3013, 3046–3047, 3064–3066, 3268–3272, 3276–3277 (+ varianty 2532–2534, 3281–3286). Bez `Print`: ř. 2517 (`PlaceStopOrder` – z cesty `SyncOneDirection` ř. 2559 se nevypíše vůbec), 2749 (`OpenMarket` – „obchodování vypnuto“), 3112 (`CheckEntryOnEntryTF` – důvod zamítnutí jen do panelu). V M1_CLOSE se tedy důvod zamítnutého vstupu nikdy nedostane do Expert logu; při schovaném panelu (README ř. 500–505 slibuje log vždy) není vidět nikde.
**Návrh.** `ReportEvent(const string text)` a použít všude včetně ř. 2749 a 3112; u 2517/2805/2874 sjednotit, kdo loguje (dnes text obalují `ManualPlace`/`ManualPlaceDouble`), aby se nelogovalo dvakrát.

### U7 – Mrtvá pole `SEntryPlan.barrierPrice` a `SChannel.valid`
`PuntikyTypes.mqh:324` · POTVRZENO · medium

`barrierPrice`: deklarace Types ř. 324, zápisy mq5 ř. 1241, 2240, 2267, 2277; žádné čtení. `SChannel.valid`: deklarace Types ř. 190, zápisy PuntikyChannels.mqh ř. 272 (true) a 431 (false); žádné čtení – volající (ř. 475–484) ukládá do `cand[]` jen kanály, které prošly, takže `valid = false` vzbuzuje falešný dojem neplatných kanálů v poli. Komentáře u obou polí navádějí čtenáře k tomu, že je má testovat/kreslit.
**Návrh.** Obě pole i jejich zápisy smazat; odstranění je bez změny chování.

### U3 – Test „STOP cena příliš blízko trhu“ 3× s odlišnými kraji; `PlaceStopOrder` selhává tiše
`PuntikyChannelBreakout.mq5:2515` · PRAVDĚPODOBNÉ · medium

Kopie: `EntryBlockReason` ř. 2169–2176, `OrderIsFrozen` ř. 2448–2457, `PlaceStopOrder` ř. 2506–2519. Divergence: (1) při `ask/bid == 0` vrátí `PlaceStopOrder` false bez `g_lastEvent` a `ManualPlace` (ř. 2805) / `ManualPlaceDouble` (ř. 2874) vypíší „tlačítkem nezadán (…)“ se **starým** textem; (2) klik po proražení úrovně hlásí „blíž než stop-level brokera“, zatímco `EntryBlockReason` by řekl „průraz už proběhl“; (3) freeze level se násobí `_Point` inline (ř. 2448), ačkoli existuje `StopsLevelPrice()` (ř. 1257–1260). Kraje se sjednotit nesmí (`OrderIsFrozen` při `freeze <= 0` musí vracet false).
**Návrh.** `StopTooClose(isBuy, price, margin)` + `SymbolLevelPrice(prop)` pro porovnání a přepočet; v `PlaceStopOrder` nastavit `g_lastEvent` i při `ask/bid == 0` a odlišit „průraz už proběhl“.

### R5 – `RevalidateRelief` opisuje predikáty z `PuntikyReliefScan`/`PuntikyBuildReliefLines`
`PuntikyChannelBreakout.mq5:1772` · POTVRZENO · low

Tělo ř. 1772–1773 ≡ PuntikyRelief.mqh ř. 191–200; knot ř. 1774 ≡ ř. 203–206; drift ř. 1779–1780 ≡ ř. 350–357; stáří ř. 1783–1786 ≡ ř. 332–334. Dnes shodné, drží je jen komentář ř. 1737–1739; rozejití = přímky blikající každých 15 barů.
**Návrh.** Metody `SReliefLine::BarPierces(...)` a `Expired(...)` volané z obou míst (usnadní i R1).

### R7 – S `InpUseRelief = false` se každou M1 svíčku smažou a znovu vytvoří všechny objekty kanálů
`PuntikyChannelBreakout.mq5:1696` · POTVRZENO · low

`OnTick` (ř. 467–468) → `RecalcRelief` → větev ř. 1692–1697 → `DrawRelief` → `RedrawChannels` (ř. 1828) → smazání `CH`/`PT` objektů (ř. 1657–1658), nové vykreslení a `ChartRedraw` (ř. 1682) – 15× mezi dvěma skutečnými přepočty kanálů, jen aby se vyprázdnilo prázdné pole.
**Návrh.** `RecalcRelief` volat jen při `InpUseRelief`; kreslit jen při skutečné změně.

### U6 – Workaround „porovnat a znovu nastavit text/bg/tooltip“ opsán 3×, patří do `PuntikyButton`
`PuntikyChannelBreakout.mq5:3489` · POTVRZENO · low

`PuntikyButton` (PuntikyDraw.mqh ř. 161–186) nastavuje bg/text/tooltip jen při vzniku. Kopie: `DrawManualButton` ř. 3486–3497, `DrawPanelToggleButton` ř. 3526–3534 (porovná jen text, bg jen spolu s ním), `DrawManualDoubleButton` ř. 3635–3645; všech pět tlačítek zapisuje `OBJPROP_TOOLTIP` každou sekundu beze změny; `DrawHueTestButton` (ř. 3404) obcházení nemá vůbec.
**Návrh.** Porovnání a zápis přesunout do `PuntikyButton` (vrací `bool changed`), volající `if(PuntikyButton(...)) ChartRedraw();`.

### U8 – Výběr návrhu člen po členu ternáry `isBuy ? g_planBuy.x : g_planSell.x` (15×)
`PuntikyChannelBreakout.mq5:3464` · POTVRZENO · low

`DrawManualButton` ř. 3462–3473 (6), `DrawManualDoubleButton` ř. 3586–3601 (8), `ManualStateText` ř. 3740; if/else v `ManualToggle` ř. 3025–3028, `ManualDouble` ř. 3070–3073, `ScanDirection` ř. 1173–1178. Volající (ř. 3678–3681, 3976–3977) předávají literály true/false, takže mohou předat `g_planBuy/g_planSell` odkazem, jak to už dělají `StateText` (ř. 3712) a `PlanToText` (ř. 3759). Riziko: při přidání členu (např. `tpDouble` z U2) se ternár v jedné kopii zapomene.
**Návrh.** Signatury s `SEntryPlan &pl` (směr z `pl.isBuy`); volitelně `g_plan[2]`.

### E2 – Tlačítka se každou sekundu od nuly měří i rozmisťují (~60 volání/s)
`PuntikyChannelBreakout.mq5:3695` · POTVRZENO · low

Za sekundu: 7× `TextSetFont + TextGetSize` nad konstantami (ř. 3402, 3521, 3674, 3482 ×2, 3631 ×2), 6× `PuntikyButton` (ObjectFind + 4× geometrie), 7 čtení stavu, 5 zápisů tooltipu, 2× `AccountInfoInteger` (ř. 3570), `ChartGetInteger` (ř. 3380); mimo ruční režim navíc 4× `ObjectDelete` neexistujících tlačítek (ř. 3668–3671). Nic z měřeného se za běhu nemění.
**Návrh.** Šířky/výšky do globálů v `OnInit`; `AccountIsHedging` cachovat; geometrii pushovat jen při vzniku objektu nebo změně `PanelTopY`; tooltip zapisovat jen při změně proti poslední hodnotě v paměti; mazání mimo ruční režim jen jednou.

### E10 – Reset `g_panelY = -1` v `TogglePanel` je mrtvý
`PuntikyChannelBreakout.mq5:316` · POTVRZENO · low

Při skrytí `UpdatePanel` smaže všechny `PNL_` objekty (ř. 3905–3908); při zobrazení `ObjectGetString` neexistujícího objektu vrátí „“ a každý řádek se překreslí (ř. 4009) i s `moved = false`. Reset nemění výsledek; komentář ř. 305–306 tvrdí opak.
**Návrh.** Smazat ř. 315–316 a opravit komentář; `g_panelShown` nechat.

### E7 – Stav směru v 16 párových globálech vynucuje ~12 if/else bloků a ~22 členových ternárů
`PuntikyChannelBreakout.mq5:256` · PRAVDĚPODOBNÉ · low

Páry ř. 256–265, 267–268, 303–306; bloky v `ApplyBreakLevel` (ř. 1985–2019), `OnTradeTransaction` (ř. 557–569), `RebuildPlans` (ř. 2097–2104), `CheckEntryOnEntryTF` (ř. 3095, 3121–3130), `CheckHueAlerts` (ř. 3157–3168), `ManualToggle`, `ManualDouble`; grep `isBuy ?` = 66 výskytů. Komentáře ř. 3462–3463 a 3585–3586 obcházejí to, že MQL5 neumí ternár nad strukturou – `g_dir[isBuy ? 0 : 1]` to řeší přímo. Refaktor je smysluplný (odstraní třídu copy-paste chyb, z níž vzešla i původní chyba K1), ale invazivní (≈50 řádků ve 14 funkcích).
**Návrh.** Po krocích a jako samostatné commity bez změny chování: nejdřív `SEntryPlan g_plan[2]` (odstraní 16 ternárů), pak level+time+armed+taken+broken do `SDirection`, nakonec hue paměť; pomocná `int DirIdx(bool isBuy)`.

### U1 – Kostra smyčky přes `PositionsTotal()/OrdersTotal()` opsána 8×
`PuntikyChannelBreakout.mq5:2917` · PRAVDĚPODOBNÉ · low

Kopie: `CountPositions` ř. 1047–1053, `ScanBothDirections` ř. 1101–1147, `CountOrders` ř. 1197–1203, `CancelPendingOrders` ř. 2483–2490, `CancelOppositeOrder` ř. 2608–2622, `SyncPendingOrders` ř. 2653–2676, `ManualRemoveDirection` ř. 2917–2942, `PositionText` ř. 3789–3793. Rozdíly ve filtru typu jsou záměrné. Komentář ř. 2905–2907 („část seznamu by se přeskočila“) je pro sestupnou smyčku nepřesný. Sběrač ticketů se hodí jen na počítání a mazání; skeny čtoucí vlastnosti nechat.
**Návrh.** `CollectOurOrders/CollectOurPositions(type, tickets[])` pro `CountPositions`, `CountOrders`, `CancelPendingOrders`, `CancelOppositeOrder`, `ManualRemoveDirection`; opravit komentář.

### U4 – Dvě definice „stejné ceny“ (`SamePrice` < `_Point/2` vs. `<= _Point`)
`PuntikyChannelBreakout.mq5:2731` · PRAVDĚPODOBNÉ · low

`SamePrice` (ř. 2433–2436) se používá jen v `SyncOneDirection` (ř. 2569); tolerance 1 bod: `LevelWasTaken` ř. 1398, `AdjustPositionStops` ř. 2731–2732 (záměr, hlavička ř. 2705), `HueCheckDirection` ř. 3196. Prosté nahrazení `SamePrice` by změnilo chování.
**Návrh.** `PriceWithin(a, b, points)` pro tři místa s tolerancí; `SamePrice` nechat pro striktní shodu.

### E3 – `UpdatePanel` projde pozice/příkazy až 2×+2× za sekundu
`PuntikyChannelBreakout.mq5:3895` · PRAVDĚPODOBNÉ · low

`ScanBothDirections` (ř. 1094) + při zobrazeném panelu `PositionText` (ř. 3787) a `CountOrders` (ř. 1194) znovu; ~20–60 volání/s. Cachování z `OnTrade` nedoporučeno (stav se může rozejít s účtem).
**Návrh.** Do výsledku jediného skenu uložit souhrn první vlastní pozice a počet příkazů; `PositionText` pak jen `PositionSelectByTicket` + `POSITION_PROFIT`.

### E8 – 33 komentářů vypráví odstraněné chování („dříve se…“) místo aktuálního invariantu
`PuntikyChannelBreakout.mq5:552` · PRAVDĚPODOBNÉ · low

.mq5 ř. 552, 678, 774, 1022, 1086, 1339, 1485, 1667, 1925, 1972, 2116, 2210, 2345, 2349, 2441, 2462, 2513, 2564, 2629, 2641, 2703, 2706, 2723, 3722, 3937; PuntikyChannels.mqh ř. 564, 608; PuntikyDraw.mqh ř. 194; PuntikyRelief.mqh ř. 47, 265, 402, 487; PuntikyTypes.mqh ř. 174. Část nese platné zdůvodnění konkrétního selhání (např. ř. 552–556, 2349–2355) – to je „proč u workaroundu“, které CLAUDE.md žádá; čistě historické (např. 1022–1023, 1339, 1485, 2462, 3722) přeformulovat.
**Návrh.** Kde věta jen říká „dříve to bylo jinak“, nahradit popisem invariantu; kde popisuje chybový scénář, nechat rationale a vypustit „dříve“.

### R6 – Každá dvojice swingů jde do O(n) `PuntikyReliefScan`; předfiltr přes swingové extrémy by dal stejný výsledek
`PuntikyRelief.mqh:361` · PRAVDĚPODOBNÉ · low

Výchozí `InpReliefMaxAge = 0` (ř. 98) filtr stáří vypíná, drift 3000 b pustí každou plochou přímku → tisíce dvojic × tisíce M1 barů („miliony průchodů“, mq5 ř. 1701–1704), během nichž expert nezpracovává ticky. Předfiltr (swing téhož typu za oporami přesahující přímku o víc než `wickTol`/`pierceTol`) je nutnou podmínkou testu knotu ř. 203–206 → výsledek shodný. Nezměřeno.
**Návrh.** Před ř. 361 projít `sw[]` od `i+2` (stejný typ) a zamítnout dvojici, kterou některý extrém proráží.

---

## 5. Konvence

### M7 – Hlavička `RecalcRelief(const bool force = false)` nepopisuje parametr `force`
`PuntikyChannelBreakout.mq5:1690` · POTVRZENO · low

Hlavička ř. 1685–1689 popisuje jen účel; že `force = true` vynutí plný přepočet mimo cyklus `PUNTIKY_RELIEF_REBUILD_BARS` (`TryInitialCalc` ř. 895), se čte až z těla (ř. 1710). Ostatní hlavičky (např. `OnDeinit` ř. 399–401, `PlaceStopOrder` ř. 2496–2503) parametry vypisují; CLAUDE.md popis parametrů u definic funkcí vyžaduje.
**Oprava.** Doplnit `//|  force - true = plny prepocet hned, bez ohledu na pocitadlo baru |`.

### Commit messages nejsou podle pravidel CLAUDE.md
`git log` · POTVRZENO · low

CLAUDE.md: „Piš git commit messages vždy v češtině. Začínej zprávu velkým písmenem. Používej tečku na konci zprávy.“ Z posledních 20 commitů je 18 anglicky a bez koncové tečky (`13f8b84 Update version to 1.20 and enhance README…`, `54e84b3 Refactor PuntikyDraw and PuntikyRelief…`, …), dva začínají malým `fix:` (`87dc359`, `19227f1`). Česky a s tečkou jsou jen dva nejstarší (`675d8df`, `4460912`).

---

## 6. Prověřeno a zamítnuto

| ID | Místo | Tvrzení | Proč zamítnuto |
|---|---|---|---|
| **K1** | mq5:558 | `OnTradeTransaction` označí jako obchodovanou aktuální `g_breakHigh/Low` místo úrovně vyplněného příkazu (6 hledačů se shodlo) | **Opraveno commitem `13f8b84`**: cena z `ORDER_PRICE_OPEN` (fallback `DEAL_PRICE`), `EntryBelongsToLevel` (ř. 1455–1463, tolerance buffer + `InpMaxLevelOffset` + `InpSlippage`, záporný offset = nepatří), `LevelWasTaken` ověřuje záznam proti historii od času svíčky úrovně. Zbytkové okrajové případy (jednotná tolerance pro všechny režimy, MANUAL příkaz na staré úrovni) jsou neškodné; případně zúžit toleranci podle `ORDER_TYPE`. |
| **L6** | mq5:1910 | `SwingBroken` přičítá spread k historickým bid high a skoro každý čerstvý vrchol tak prohlásí za proražený | Záměrný model „BUY STOP na level+buffer by se na asku vyplnil“ (README ř. 116–119, komentář ř. 1323–1331); test odpovídá podmínkám serveru pro spuštění příkazů. Asymetrie vůči SELL odpovídá exekuci; uživatel ji řídí `InpBreakoutBuffer` > typický spread. Skutečný problém je drift mediánu – L5. |
| **M2** | mq5:601 | V ručním režimu mohou ležet oba STOPy a po vyplnění jednoho se druhý neruší – porušení `InpMaxPositions` | Dokumentovaný záměr (README ř. 474–486: expert na ručně zadané příkazy nesahá). Jediná nesrovnalost: README ř. 196–197 pod „Společné pro oba režimy“ tvrdí OCO – doplnit, že ruční příkazy OCO ani `InpMaxPositions` neomezují; volitelně `InpManualOCO`. |
| **E4** | mq5:1858 | `DrawEntryLevels` překresluje ~110 objektů při každém `RebuildPlans` i beze změny | Pravda, ale jen 1× za M1 bar (~2 volání/s); memo by stejně muselo obsahovat `tFrom/tTo` měnící se každou hodinu. Skutečné plýtvání řeší E1. |
| **E5** | mq5:2095 | `RebuildPlans` počítá `CountPositions` 2×, `CalcLot` 4×, `Bars()` 4× | ~50 levných volání za minutu v jednom obslužném volání, bez rizika nekonzistence; rozdělení `CalcLot` by funkci zkomplikovalo. Nanejvýš předat počet pozic a stop level parametrem. |
| **E6** | mq5:447 | 3× `iTime`, 2× `MQLInfoInteger`, 3× bid/ask na tick | Pod prahem měřitelnosti; „hrubší TF testovat jen při novém baru vstupního TF“ není bezpečné bez validace dělitelnosti TF, kterou `ValidateInputs` nevynucuje. |
| **E9** | Channels.mqh:417 | Knihovní guardy (`n<10`, `MathMax(p.*, …)`) duplikují `ValidateInputs` | Moduly mají vlastní API a nemají znát validaci EA; guardy jsou triviální. Jen v `FindBreakoutSwings` lze smazat ř. 1941–1942 a 1945–1946 (no-op), stojí to za to jen při jiné úpravě téže funkce. |

---

## 7. Doporučené pořadí oprav

1. **Detekce průrazu a rekonciliace příkazů (L1, L2, L3, L4, K2)** – společný kořen, opravovat jako celek:
   * `UpdateArming`/`LevelBrokenNow` pro otevřenou svíčku testovat BUY proti živému asku (L3);
   * v M1_CLOSE odložit swap úrovně za `CheckEntryOnEntryTF` nebo porovnávat proti snapshotu z otevření svíčky, a blokovat tržní vstup podle času prvního průrazu (L1 + L2);
   * `SyncOneDirection` rušit ležící příkaz jen z důvodů spotřebované/změněné úrovně, ne kvůli stop-levelu (L4);
   * z `OnTradeTransaction` odstranit okamžité `SyncPendingOrders()` a ř. 608 (K2).
2. **Pořadí kroků v `OnTick` (R3 + E1)** – `RevalidateRelief` před vstupem na novém baru a jediné `RebuildPlans` na tick; jde o jednu úpravu téhož bloku.
3. **Životní cyklus příkazů (M1, M3)** a **dorovnání stopů (K3, K4, K5)** – malé, lokální změny v `OnDeinit`, `OnInit` a obsluze DEAL_ADD; při K3/K4 sjednotit dorovnání na jedno místo z `DEAL_*`.
4. **Spread při startu a v historii (L5)** – naplnit vzorky z `MqlRates.spread`.
5. **`BarIndexNow` fallback (R2)** – vrátit poslední dobrý index místo extrapolace z času.
6. **Úklid s přínosem pro správnost**: U2 (`lotsDouble`/`tpDouble`), U5 (`ReportEvent` + tři chybějící logy), U7 (mrtvá pole), U3 (`PlaceStopOrder` bez hlášení).
7. **Drobnosti**: K6, K7, M4, M6, M7, R5/R1, R7, U6, U8, E2, E10; komentáře (E8) a konvence commit messages při dalších commitech.
8. **Větší refaktor až nakonec a zvlášť**: E7 (`SDirection g_dir[2]`), U1, E3, R6, E11, R4, M5 podle uvážení.
