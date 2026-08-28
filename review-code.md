# Revize kódu – `MQL5/` (Sved Channel Breakout, EA v1.10)

Datum: 2026-08-28 · Revidovaný stav: commit `675d8df` (main) · Rozsah: celý adresář `MQL5/`
(`Experts/Sved/SvedChannelBreakout.mq5`, `Include/Sved/SvedTypes.mqh`, `SvedSwings.mqh`,
`SvedChannels.mqh`, `SvedRelief.mqh`, `SvedDraw.mqh`; 3 189 řádků).

Metoda: 10 nezávislých hledacích úhlů (řádek po řádku, slíbené chování dle README/komentářů,
křížové vazby volajících, pasti MQL5, konzistence stavového automatu, reuse, zjednodušení,
efektivita, „altitude“, konvence dle `~/.claude/CLAUDE.md`) → deduplikace → každý kandidát
ověřen samostatným verifikátorem (CONFIRMED / PLAUSIBLE / REFUTED) → závěrečný „sweep“
na mezery → další ověření. Číslo řádku = řádek v uvedeném souboru.

Poznámka k defaultům: výchozí režim je `SVED_ENTRY_PENDING`, `InpBreakoutBuffer = 10 b`,
`InpMaxPositions = 1`, `InpLotMode = FIXED`, `InpReliefMode = SKIP`, `InpUseSwingLevels = true`.

> **Stav pro navázání (2026-08-28):** revidovaný kód odpovídá commitu `4e13aa9` (main) – oproti
> `675d8df` se změnily jen výchozí hodnoty `InpLotMode = SVED_LOT_RISK` a `InpRiskPercent = 1.0`
> (mq5:102–104) a README; čísla řádků v tomto souboru tedy stále platí. Rizikový režim objemu je
> teď výchozí, takže nález 2.8 (`CalcLot`: `MathMax(lot, minLot)` tiše zvedne riziko nad limit,
> `TICK_VALUE` místo `TICK_VALUE_LOSS`) se týká výchozí konfigurace. Doporučené pořadí oprav:
> 2.1 → 2.2 → 2.3 → 2.4/2.5 (společná rekonciliace příkazů) → 2.6/2.11 → 2.8 → 2.9/2.14 → zbytek;
> každou opravu samostatným commitem, kompilace přes `scripts\deploy.cmd`, komentáře česky,
> identifikátory anglicky (viz `~/.claude/CLAUDE.md`).

---

## 1. Shrnutí – 15 nejzávažnějších nálezů

| # | Soubor:řádek | Nález | Stav |
|---|---|---|---|
| 1 | mq5:1115 (1270, 247–299) | Rušení pending příkazů ignoruje výsledek `OrderDelete`; cancel+re-place běží až 3× v jednom ticku → duplicitní STOP příkazy, dvojnásobná expozice | CONFIRMED |
| 2 | mq5:808 (845, 783, 863) | Detekce průrazu je BID-based a ostrá, BuyStop se plní na ASK → při spread ≥ buffer se BUY plní pod úrovní a průraz se nikdy nezaznamená; po restartu se stejná úroveň obchoduje znovu | CONFIRMED |
| 3 | SvedChannels.mqh:590 (mq5:937/951) | Test „uvnitř kanálu“ bere `trigger`, hledání hrany `entry`; hrana mezi nimi se přeskočí → plný 300b PT mimo kanál právě když swing sedí na hraně | CONFIRMED |
| 4 | mq5:293 (1280–1292) | Nezadaný / neúspěšný STOP příkaz se nikdy neopakuje; `g_lastPlanState` sleduje jen `valid`, takže změna SL/PT/lotu se do ležícího příkazu nepromítne | CONFIRMED |
| 5 | mq5:1280 (813–816) | Pending režim vůbec nečte `g_buyArmed/g_sellArmed` → BuyStop se zadá do už běžícího pohybu, panel přitom hlásí „BUY blokován“ | CONFIRMED |
| 6 | mq5:770 (680–681) | `FindBreakoutSwings` vrací `foundHi && foundLo` → chybí-li jedna strana, druhá zůstane zamrzlá na staré úrovni i s příznaky; při `brokenChanged` se navíc přeskočí `RebuildPlans` | CONFIRMED |
| 7 | mq5:258 (1164, 808) | Režim M1_CLOSE: signál se ztratí, když M1 close spadne na hranici H1; `checkReachable=false` obchází guardy taken/broken a nemá strop vzdálenosti vstupu od úrovně | CONFIRMED |
| 8 | mq5:1060 (1046, 1061, 1064) | `CalcLot`: `MathFloor(lot/lotStep)` bez tolerance (0.29→0.28), `NormalizeDouble(lot,2)` ignoruje krok 0.001, v režimu rizika `MathMax(lot,minLot)` tiše zvedne riziko nad limit, používá se `TICK_VALUE` místo `TICK_VALUE_LOSS` | CONFIRMED |
| 9 | mq5:345 (1216) | Ve výchozím pending režimu se po plnění se skluzem SL/PT nedorovnají → RRR ≠ 1:1 (`AdjustPositionStops` se volá jen z tržní cesty) | CONFIRMED |
| 10 | SvedSwings.mqh:86 | Outside bar (pivot high i low) uloží jen jeden extrém → skutečný vrchol zmizí, `FindBreakoutSwings` vybere špatnou úroveň | CONFIRMED |
| 11 | mq5:275–278 (737, 781) | „Po průrazu se hned hledá další swing“ není implementováno – `SwingBroken` vidí jen uzavřené H1 svíčky → strana blokovaná až 59 minut | CONFIRMED |
| 12 | SvedRelief.mqh:334 (SvedChannels.mqh:213) | Opory se samy počítají jako dotyky → `InpReliefMinTouches=2` je prázdný filtr (každá čistá spojnice dvou swingů blokuje vstupy), `InpMinTouches=4` reálně = 1 dotyk navíc | CONFIRMED |
| 13 | mq5:400 (192, 211) | `GetATR()` hned po `iATR()` v `OnInit` typicky vrátí 0 → ATR filtr šířky i složka skóre se při prvním výpočtu (a prvních pending příkazech) tiše vypnou | CONFIRMED |
| 14 | mq5:1243 (1302) | `InpMaxPositions > 1` nefunguje: `AdjustPositionStops` přepíše SL/PT všech pozic strategie; v pending režimu OCO „jakákoli pozice ⇒ zrušit vše“ druhou pozici nikdy nepustí | CONFIRMED |
| 15 | SvedChannels.mqh:187 (171, 228) | S výchozími prahy jsou `InpMinContainment` a `InpRequireInside` mrtvé filtry – `SvedChannelIsClean` už garantuje close v ±15 % šířky → containment ≡ 1.0, skóre +6 konstantně, diagnostika lže | CONFIRMED |

Vyvráceno: tvrzení, že `datetime − datetime` je v MQL5 bezznaménkové a `BaseAt()` přetéká
(viz kap. 4 – empiricky vyvráceno kompilační sondou).

---

## 2. Podrobné nálezy – korektnost (seřazeno podle závažnosti)

### 2.1 Duplicitní STOP příkazy: ignorovaný výsledek `OrderDelete` + trojí cancel/re-place v jednom ticku

- **Soubor:** `MQL5/Experts/Sved/SvedChannelBreakout.mq5:1106–1116` (`CancelPendingOrders`),
  `:1268–1294` (`PlacePendingOrders`), `:247–252`, `:256–260`, `:293–298` (`OnTick`), `:217–218` (`OnInit`)
- **Stav:** CONFIRMED · **Závažnost:** vysoká (peníze, výchozí režim)
- **Mechanismus:** `CancelPendingOrders` volá `g_trade.OrderDelete(ticket)` a návratovou hodnotu
  zahazuje; `PlacePendingOrders` hned poté bezpodmínečně zadá nový BuyStop/SellStop. Když smazání
  selže (`TRADE_RETCODE_FROZEN` – příkaz uvnitř `SYMBOL_TRADE_FREEZE_LEVEL`, requote, výpadek
  spojení, `TOO_MANY_REQUESTS`, příkaz právě v exekuci), starý příkaz přežije a vedle něj leží druhý
  identický. `PlacePendingOrders` kontroluje jen `entry > ask + stopsLevel`, freeze level vůbec ne.
  Navíc se na hodinové hranici (nový M15 i H1 bar v témže ticku) volá `PlacePendingOrders` až 3×
  (krok 1 se STARÝMI H1 úrovněmi, krok 2 s novými, krok 5 kvůli `planState != g_lastPlanState`,
  který kroky 1/2 neaktualizují; při startu je `g_lastPlanState = -1`) – šest obchodních požadavků
  v jednom ticku, mezi nimi krátce existují STOP příkazy na staré úrovni. Terminál navíc po
  synchronním `OrderSend` nemusí mít nový příkaz okamžitě v `OrdersTotal()`, takže i „úspěšné“
  kolo může druhý příkaz minout.
- **Scénář:** BuyStop 2400.10 leží 25 b od trhu, broker má freeze level 30 b. Nová M15 svíčka →
  `OrderDelete` vrátí FROZEN (ignorováno) → nový BuyStop 2400.10 → dva příkazy → oba se vyplní
  v jednom ticku dřív, než `OnTradeTransaction` stihne OCO → 2× lot i při `InpMaxPositions = 1`.
- **Oprava:** kontrolovat výsledek `OrderDelete` (při neúspěchu nezadávat nový příkaz / opakovat);
  místo cancel+re-place dělat rekonciliaci „požadovaný stav vs. skutečné příkazy“ (`OrderModify`
  jen když se liší cena/SL/PT/lot); `PlacePendingOrders` volat nejvýše jednou za tick přes příznak
  „nutno přepočítat“ a v každé cestě aktualizovat `g_lastPlanState`; respektovat freeze level.

### 2.2 Detekce průrazu je BID-based a ostrá, BuyStop se plní na ASK

- **Soubor:** `mq5:808` (`UpdateArming`), `:845` (`LevelAlreadyBroken`), `:783` (`SwingBroken`),
  `:863` (`RebuildPlans` – entry = H + buffer), `:1282` (`BuyStop`)
- **Stav:** CONFIRMED · **Závažnost:** vysoká (systematická, výchozí konfigurace na XAUUSD)
- **Mechanismus:** všechny tři detektory testují `high/bid > level + buffer` (ostře), graf i historie
  jsou BID. BuyStop na `H + buffer` se plní, když **ASK** ≥ cena, tj. bid = H + buffer − spread.
  Se spreadem 20 b a bufferem 10 b se BUY plní na bid = **H − 10 b**, tedy pod úrovní (efektivní
  buffer = buffer − spread < 0), a pokud se cena otočí, žádná M1/H1 svíčka nemá `high > H + buffer`
  → průraz se nikdy nezaznamená. Po restartu (`g_buyTaken` je volatilní globál, historie dealů se
  nikde nečte) `FindBreakoutSwings` vrátí tentýž swing, `LevelAlreadyBroken` = false → druhý BuyStop
  na téže úrovni – v rozporu s README „na jedné swingové úrovni se obchoduje nejvýše jednou“.
  Cesta existuje i bez restartu: vznikne-li nižší swing S2 a je proražen, `FindBreakoutSwings` se
  vrátí k H, `th` se změní → `g_buyTaken = false` → H se obchoduje podruhé. U SELL je ostré `<`
  vs. plnění při rovnosti 1-tick hraniční případ (navíc citlivý na FP rozdíl `g_breakLow - buffer`
  vs. `NormalizeDouble(entry)`).
- **Oprava:** pro BUY pracovat s ask (bid + spread) v detekci i při konstrukci úrovně (entry =
  H + buffer + spread), nebo detekci vztáhnout k ceně příkazu; spotřebované úrovně ukládat
  perzistentně (globální proměnné terminálu / sken historie dealů v `OnInit`).

### 2.3 Hrana mezi `trigger` a `entry` se přeskočí → plný PT mimo kanál

- **Soubor:** `MQL5/Include/Sved/SvedChannels.mqh:590` (`if(vNow <= price) continue;`, zrcadlově `:602`),
  `mq5:937` (`SvedFindContainingChannel(..., trigger, ...)`), `:951` (`SvedDistanceToNextEdge(..., pl.entry, ...)`)
- **Stav:** CONFIRMED · **Závažnost:** vysoká (typická ABCD konfigurace: swing = dotyk hrany)
- **Mechanismus:** test „uvnitř kanálu“ používá `trigger` s tolerancí `InpInsideTolFrac × šířka`
  (2 %), hledání nejbližší hrany začíná od `entry = trigger + buffer` a hranu s `vNow <= entry`
  zahodí jako „neexistuje“ (vrátí −1). Swing ležící v pásmu `[U − buffer, U + tol]` tedy projde
  testem uvnitř, hrana se přeskočí, `edgeDist = −1`, `dist = maxDist` → BuyStop s PT 300 b
  **nad** hranou a bez `limitedByEdge`. Swing o 1 bod níž dá `avail = −19 b` → „málo místa“.
- **Číselně (U = 2000.00, šířka 5.00, buffer 0.10, EdgeBuffer 0.20):** H = 1999.89 → zamítnuto
  „málo místa (−19 b)“; H = 1999.90 → platný BuyStop, TP 2003.00 (3 USD nad hranou); H = 2000.05 →
  platný, TP 2003.15 mimo kanál; H = 2000.15 → „průraz mimo kanál“.
- **Oprava:** oba testy vztáhnout ke stejné referenční ceně; hranu v intervalu `[trigger, entry]`
  brát jako vzdálenost 0 (→ zamítnutí „málo místa“), nebo explicitně rozhodnout případ „swing na
  hraně = průraz kanálu“ a zdokumentovat ho.

### 2.4 Nezadaný / neúspěšný STOP příkaz se neopakuje; změna SL/PT/lotu se do ležícího příkazu nepromítne

- **Soubor:** `mq5:293–298` (bitmaska `planState`), `:1280`, `:1284`, `:1288`, `:1292`
- **Stav:** CONFIRMED · **Závažnost:** vysoká (ztracené vstupy, zastaralé stopy)
- **Mechanismus:** `PlacePendingOrders` běží jen při novém M15/H1 baru nebo změně bitmasky
  `(valid?1:0)+(valid?2:0)`. Když se příkaz nezadá (`entry <= ask + stopsLevel`; jen tichý skip)
  nebo `BuyStop()` vrátí chybu (jen `Print`), plán zůstává `valid`, bitmaska se nemění → žádný
  pokus až do dalšího M15/H1 baru (až 15 min), panel hlásí „BUY připraven“. Totéž po dočasném
  vypnutí AutoTradingu (`CanTrade` false → příkazy zrušeny, po zapnutí se nevrátí). `RebuildPlans`
  běží každou M1 svíčku a mění entry/SL/PT/lot (např. reliéf v režimu SHORTEN, projekce hrany,
  zůstatek v režimu RISK), ale bez změny platnosti se ležící příkaz neaktualizuje – nese PT za
  reliéfní přímkou, kterou měl zkrátit; panel/graf ukazují jiné hodnoty než skutečný příkaz.
- **Oprava:** každou M1 svíčku (nebo tick) rekonciliovat požadovaný vs. skutečný příkaz
  (cena/SL/PT/lot) a při rozdílu `OrderModify`/znovu zadat; logovat důvod přeskočení.

### 2.5 Pending režim ignoruje příznak „nabito“ (`g_buyArmed/g_sellArmed`)

- **Soubor:** `mq5:1280`, `:1288` (`PlacePendingOrders`), `:878–926` (`BuildPlan`), `:813–816`
- **Stav:** CONFIRMED · **Závažnost:** střední–vysoká (výchozí režim)
- **Mechanismus:** příznak čtou jen `CheckEntryOnEntryTF` (režim M1) a `StateText` (panel).
  Mezi H a H + buffer je „mrtvá zóna“: ani armed, ani broken. Start EA s bid = H + 5 b: `BuildPlan`
  projde (`entry <= ask` false) → BuyStop 4 b nad trhem do už běžícího pohybu – přesně to, čemu
  má arming podle hlavičky `UpdateArming` i README bránit; panel současně píše „BUY blokován“.
  Totéž nastane za běhu po vzniku nového swingu (reset na ř. 697–701).
- **Oprava:** kontrolovat `armed` v `BuildPlan(checkReachable=true)` nebo v `PlacePendingOrders`.

### 2.6 `FindBreakoutSwings` je „vše nebo nic“; při `brokenChanged` se přeskočí `RebuildPlans`

- **Soubor:** `mq5:770` (`return(foundHi && foundLo)`), `:680–681`, `:277–281`, `:808–816`
- **Stav:** CONFIRMED · **Závažnost:** střední–vysoká
- **Mechanismus:** poslední 2 uzavřené H1 svíčky nikdy nejsou swingem, ale svým high všechny
  starší swing-high „prorazí“, jakmile udělají nové 300barové maximum + 10 b. V silném trendu je
  tak `foundHi = false`, zatímco čerstvé higher-low existuje → celý přepočet padne:
  `g_breakLow` zůstane na starém (nižším) swingu, `g_sellTaken/g_sellBroken` se nepřepočítají,
  čáry se nepřekreslí, plány se nepřepočítají. Při startu v této fázi zůstanou obě úrovně 0,
  `UpdateArming` nastaví `g_buyBroken = true` a `g_sellArmed = true` bez jakékoli úrovně (bezpečné,
  ale nechtěné – EA nic nekreslí ani neobchoduje). Na cestě `brokenChanged` se místo `RebuildPlans`
  volá jen `RefreshBreakoutLevels`, které při selhání nic nepřepočítá → `g_planBuy.valid` zůstane
  true s `g_buyBroken = true` až do další M1 svíčky. Komentář ř. 729 („pokud se oba typy
  nepodařilo najít“) popisuje jiný záměr než kód.
- **Oprava:** vracet výsledek per strana a aktualizovat každou nezávisle; `RebuildPlans` volat
  vždy, když se změnil `broken`.

### 2.7 Režim M1_CLOSE: ztráta signálu na hranici H1, obcházení guardů, vstup libovolně daleko od úrovně

- **Soubor:** `mq5:256–258` vs. `:284–287` (pořadí v `OnTick`), `:1164`, `:1184`
  (`BuildPlan(..., false)`), `:907`, `:808`
- **Stav:** CONFIRMED · **Závažnost:** střední–vysoká (nevýchozí režim)
- **Mechanismus:** (a) Když M1 close, který úroveň překročil, spadne na hranici H1 (1 z 60),
  krok 2 (`RefreshBreakoutLevels`) uvidí uzavřenou H1 svíčku s high nad úrovní, `SwingBroken`
  vrátí true, úroveň se posune na starší (vyšší) swing, `th` se změní, příznaky se resetují –
  a krok 5 (`CheckEntryOnEntryTF`) pak `crossedUp` počítá proti NOVÉ úrovni → platný signál
  zmizí. (b) V normálním případě `UpdateArming` úroveň spotřebuje (`g_buyBroken`) ještě před
  M1 close a vstup projde jen proto, že `checkReachable=false` guard obchází – tedy i na úrovni,
  kterou EA sám označil za proraženou (panel hlásí „BUY nelze“, EA přitom kupuje). (c) Entry =
  `ask` bez stropu vzdálenosti od úrovně: po gapu / dlouhé svíčce se vstupuje stovky bodů nad
  úrovní s plným PT.
- **Oprava:** vyhodnotit vstup před `RefreshBreakoutLevels` (nebo si zapamatovat úroveň platnou
  v okamžiku křížení); guardy skládat, ne vypínat jedním boolem (vypnout jen test „cena už za
  úrovní“); omezit `entry − trigger` na násobek bufferu.

### 2.8 `CalcLot`: chybné zaokrouhlení objemu a překročení rizika

- **Soubor:** `mq5:1060` (`MathFloor(lot / lotStep) * lotStep`), `:1064` (`NormalizeDouble(lot, 2)`),
  `:1061` (`MathMax(lot, minLot)`), `:1046` (`SYMBOL_TRADE_TICK_VALUE`)
- **Stav:** CONFIRMED (numericky ověřeno) · **Závažnost:** střední (objem každého obchodu)
- **Mechanismus:** IEEE dělení „hezkých“ hodnot vychází těsně pod celým číslem:
  `0.29/0.01 = 28.999999999999996 → 28 → 0.28`, `0.57 → 0.56`, `0.58 → 0.57`, `0.3/0.1 → 0.2`.
  Uživatel zadá `InpFixedLot = 0.29`, obchoduje se 0.28; panel i log ukazují jiný objem.
  `NormalizeDouble(lot, 2)` ignoruje `SYMBOL_VOLUME_STEP`: při kroku 0.001 lot 0.004 → 0.00 →
  „nelze určit objem“, lot 0.005 → 0.01 (zaokrouhlení NAHORU, ruší předchozí floor). V režimu RISK:
  zůstatek 200 USD, riziko 0.5 % = 1 USD, SL 300 b na XAUUSD → lot 0.0033 → floor 0.0 →
  `MathMax` 0.01 → ztráta 3 USD = 1.5 % (3× nad limit); `BuildPlan` kontroluje jen `lots <= 0`.
  `lossPerLot` počítá z `TICK_VALUE` (profit strana), správně `TICK_VALUE_LOSS`.
- **Oprava:** `MathFloor(lot / lotStep + 1e-9)`, normalizovat na počet desetinných míst kroku,
  v režimu RISK obchod odmítnout (nebo varovat), je-li rizikový lot < minLot; použít
  `SYMBOL_TRADE_TICK_VALUE_LOSS`.

### 2.9 Pending režim: po plnění se skluzem se SL/PT nedorovnají (RRR ≠ 1:1)

- **Soubor:** `mq5:345–347` (`OnTradeTransaction`), `:1216` (jediné volání `AdjustPositionStops`)
- **Stav:** CONFIRMED · **Závažnost:** střední (výchozí režim, každé plnění se skluzem)
- **Mechanismus:** STOP příkaz nese absolutní SL/PT pro nominální entry; při plnění 2400.60 místo
  2400.10 má pozice SL 350 b a PT 250 b (RRR 1.4:1). `OnTradeTransaction` má `DEAL_PRICE`, ale
  jen ho tiskne. Hlavička EA (ř. 9–11) i README slibují 1:1 obecně; dorovnání existuje jen
  v tržní cestě.
- **Oprava:** v `OnTradeTransaction` po `DEAL_ENTRY_IN` zavolat `AdjustPositionStops(distance)`,
  kde `distance = |ORDER_PRICE_OPEN − ORDER_SL|` z `HistoryOrderSelect(trans.order)` – a jen pro
  danou pozici (viz 2.14).

### 2.10 Outside bar zahodí druhý extrém → chybná úroveň průrazu

- **Soubor:** `MQL5/Include/Sved/SvedSwings.mqh:84–92` (rozhodující `:86`), dopad `mq5:752–768`, `:777–789`
- **Stav:** CONFIRMED · **Závažnost:** střední
- **Mechanismus:** `SvedDetectSwings` staví jeden `SSwing` na bar; u baru, který je pivot high
  i low, vezme typ opačný k předchozímu swingu a druhý extrém zahodí – i když je extrémnější
  než poslední swing téhož typu (merge větev se nespustí, protože `s` nese opačný typ).
  Sekvence (H1, depth 2): H(2400@p), outside bar q ≥ p+3 s high 2405 / low 2380 → uloží se jen
  L(2380@q); později H(2395@r). `FindBreakoutSwings` → BUY úroveň 2395 (nebo `SwingBroken(2400)`
  = true kvůli 2405 → skok na starší swing / `foundHi = false`), skutečný vrchol 2405 nikdy
  úrovní není. Stejný mechanismus platí pro M15 kostru kanálů (kotvy A/C na nižším vrcholu).
- **Oprava:** u outside baru emitovat oba extrémy (nejprve typ opačný k předchozímu, pak druhý),
  nebo aspoň sloučit stejnotypový extrém do předchozího swingu, je-li extrémnější.

### 2.11 „Po průrazu se hned hledá další swing“ není implementováno

- **Soubor:** `mq5:275–278` (komentář + volání), `:737` (`CopyRates(..., 1, ...)` – jen uzavřené),
  `:781–786` (`SwingBroken`), `:697–701`, `:715`
- **Stav:** CONFIRMED · **Závažnost:** střední (každý průraz, výchozí režim)
- **Mechanismus:** po tickovém průrazu `UpdateArming` nastaví `g_buyBroken`, `brokenChanged`
  spustí `RefreshBreakoutLevels`, ale `FindBreakoutSwings`/`SwingBroken` pracují jen s uzavřenými
  H1 svíčkami – prorážející svíčka v poli není → vrátí TENTÝŽ swing (`th == g_breakHighTime`,
  žádný reset), `g_buyBroken` se jen přepočítá na true. BUY strana je „úroveň už byla proražena“
  až 59 minut; předchozí (vyšší) swing a jeho BuyStop přijdou až s novou H1 svíčkou. Každý tick
  s `brokenChanged` navíc zaplatí `CopyRates(H1, 300)` + 2× `CopyRates(M1, od swingu do teď)`
  pro nic. README („hledá se další okamžitě, nečeká se na otevření další H1 svíčky“) i komentář
  tvrdí opak.
- **Oprava:** při výběru swingu zahrnout i aktuální otevřenou H1 svíčku (shift 0) do testu
  proražení, nebo použít `LevelAlreadyBroken` per kandidátní swing; případně zpoždění
  zdokumentovat.

### 2.12 Opory se počítají jako dotyky → filtry `minTouches` jsou (skoro) prázdné

- **Soubor:** `MQL5/Include/Sved/SvedRelief.mqh:334` (`:157–171` `SvedReliefCountTouches`),
  `MQL5/Include/Sved/SvedChannels.mqh:213` (`:180–208`)
- **Stav:** CONFIRMED · **Závažnost:** střední (výchozí režim SKIP → falešné blokace vstupů)
- **Mechanismus:** v `i1` a `i2` prochází přímka přesně high/low (d = 0), opory jsou ≥ 30 barů
  od sebe ≥ `SVED_RELIEF_TOUCH_GAP` → každá čistá přímka má `touches ≥ 2`; `InpReliefMinTouches = 2`
  nikdy nevypadne, `st.touches` je trvale 0. S `InpReliefMidTouch = false` (výchozí) se reliéfní
  přímkou stane libovolná neproražená spojnice dvou swingů (délka ≥ 30, drift ≤ 1200 b) bez jediného
  nezávislého dotyku – a v režimu SKIP blokuje vstupy. Vlastní komentář kódu (ř. 201–205) to
  přiznává („same krajni dotyky nic nedokazuji“). U kanálů jsou A, C (základna) a B (protější
  hrana) 3 garantované dotyky (čítače per hrana, gap se neuplatní) → `InpMinTouches = 4` reálně
  vyžaduje jediný další dotyk.
- **Oprava:** dotyky počítat bez oporových barů (nebo opory odečíst) a dokumentovat skutečný
  význam; zvážit výchozí `InpReliefMidTouch = true`.

### 2.13 `GetATR()` vrátí při `OnInit` 0 → ATR filtr se tiše vypne

- **Soubor:** `mq5:400` (`CopyBuffer(g_atrHandle, 0, 1, 1, buf) != 1 → 0.0`), `:192` (`iATR`),
  `:211` (`RecalcChannels` hned poté), `SvedChannels.mqh:151`, `:243`
- **Stav:** CONFIRMED · **Závažnost:** střední (start/restart)
- **Mechanismus:** handle indikátoru na jiném TF než graf se počítá asynchronně; první `CopyBuffer`
  hned po `iATR()` typicky vrátí −1 (`BarsCalculated == -1`). `p.atr = 0` znamená
  `if(p.atr > 0.0 && ...)` → filtr `InpMinWidthATR` neběží, složka skóre `width/ATR` chybí;
  z takto vybraných kanálů se v `OnInit` rovnou zadají pending příkazy. Žádný retry, 0 se bere
  jako „bez ATR“, ne „ještě nepřipraveno“; stav trvá do dalšího M15 baru. `GetATR()` se navíc
  volá 3× za přepočet (`RecalcChannels`, `PrintDiagnostics`, `RedrawChannels`).
- **Oprava:** před použitím ověřit `BarsCalculated(g_atrHandle) > 0`; není-li ATR k dispozici,
  odložit první přepočet/zadání příkazů na první tick s daty; ATR číst jednou za přepočet.

### 2.14 `InpMaxPositions > 1` nefunguje (přepis SL/PT cizí pozice; OCO ruší vše)

- **Soubor:** `mq5:1243–1259` (`AdjustPositionStops`), `:1216`, `:1302` (`ManagePendingOrders`),
  `:892`, `:1130`
- **Stav:** CONFIRMED · **Závažnost:** střední (nevýchozí konfigurace, dopad na peníze)
- **Mechanismus:** (a) `AdjustPositionStops(distance)` projde VŠECHNY pozice symbolu+magic a každé
  nastaví `open ± distance` nového obchodu – běžící BUY s distance 300 b dostane po otevření SELL
  s distance 120 b SL/PT ±120 b (`PositionModify`), ztratí původní rámec. `OpenMarket` má
  `g_trade.ResultDeal()/ResultOrder()`, ale nepředává je. (b) V pending režimu s `InpMaxPositions = 2`:
  po plnění BuyStop `BuildPlan` i `CanTrade` SellStop pustí, ale `ManagePendingOrders`
  (`CountPositions() > 0 && CountOrders() > 0`) ho v témže ticku zruší – a znovu na každém M15/H1
  baru (OrderSend + OrderDelete pokaždé). Druhá pozice je nedosažitelná.
- **Oprava:** modifikovat jen novou pozici (ticket z `DEAL_POSITION_ID` výsledného dealu);
  OCO rušit až při `CountPositions() >= InpMaxPositions`.

### 2.15 `InpMinContainment` a `InpRequireInside` jsou s výchozími prahy mrtvé filtry

- **Soubor:** `MQL5/Include/Sved/SvedChannels.mqh:171` (tol), `:187`, `:218`, `:228`, `:240`; příčina `:54`, `:59–70`
- **Stav:** CONFIRMED · **Závažnost:** střední–nižší (mrtvá logika, klamavá dokumentace/diagnostika)
- **Mechanismus:** `SvedChannelIsClean` (běží dřív) garantuje pro každý bar i ≥ iA
  `Lower − 0.05w ≤ low ≤ close ≤ high ≤ Upper + 0.15w` (obě orientace). Containment test používá
  `tol = touchTolFrac·w = 0.15w` → `close ∈ [Lower − 0.15w, Upper + 0.15w]` platí vždy →
  `containment ≡ 1.0`, `1.0 < 0.85` nikdy, `st.containment = 0`, složka skóre `+6` konstantně.
  `ch.Contains(tLast, close, 0.15w)` je také vždy true → `st.outside = 0`; kanál s close 14 %
  šířky nad horní hranou se hlásí „cena uvnitř“. README radí snižovat `InpMinContainment` a
  přepínat `InpRequireInside` – bez efektu. Filtry ožijí jen při `touchTolFrac < pierceTolFrac`.
- **Oprava:** samostatná tolerance pro containment/inside (< `pierceTolFrac`), nebo filtry
  odstranit a uvést README/diagnostiku do souladu.

---

## 3. Další ověřené nálezy (pod čarou – nevešly se do 15)

### 3.1 „Jen kreslicí“ instance maže živé příkazy – CONFIRMED
`mq5:1270` – `PlacePendingOrders` volá `CancelPendingOrders()` PŘED `CanTrade()`, `ManagePendingOrders`
běží každý tick bez ohledu na `CanTrade`. Instance s `InpEnableTrading = false` nebo na jiném účtu
(`g_tradingAllowed = false`) posílá `OrderDelete` v `OnInit`, na každém M15/H1 baru i při změně
`planState` na příkazy se stejným magic+symbol (druhá instance na jiném grafu, restart s vypnutým
obchodováním). README slibuje „jen kreslení“. Oprava: `CanTrade` před rušením; `ManagePendingOrders`
přeskočit při vypnutém obchodování.

### 3.2 `LevelAlreadyBroken` přepíše tickem zjištěný průraz při selhání `CopyRates` – PLAUSIBLE
`mq5:715` (bezpodmínečné přiřazení), `:839` (`copied <= 0 → false`). V hlavním scénáři to zachrání
`UpdateArming()` na ř. 718 (stejný bid ho obnoví). Reálná expozice: start/restart uprostřed H1
svíčky, kdy úroveň už byla v této svíčce proražena a cena se vrátila – M1 historie ještě není
synchronizovaná → `false` → `OnInit` zadá BuyStop na spotřebovanou úroveň (max. do konce H1
svíčky); křížový případ sell/buy v téže svíčce. Oprava: třístavový výsledek („neznámo“), při
nezměněné úrovni příznak držet a OR-ovat s historií; před prvním zadáním ověřit
`SERIES_SYNCHRONIZED`.

### 3.3 Chybí validace vstupů – CONFIRMED
`mq5:175` – `OnInit` nikdy nevrátí `INIT_PARAMETERS_INCORRECT`. `InpMaxPositions = 0` →
`0 >= 0` → každý plán „pozice již otevřena“, EA nikdy neobchoduje, bez logu. `InpSwingDepth = 0` →
smyčka `k <= 0` neběží → každý bar je pivot high i low. `InpReliefMidFrom > InpReliefMidTo`
+ MidTouch → všechny přímky zamítnuty. `InpDedupFrac = 0` → `MathAbs(..) >= 0` → identický kanál
se ve 2. fázi `SvedSelectChannels` přidá podruhé. Clamp existuje jen pro `InpMaxChannels` a
`InpMaxReliefLines`. Oprava: validace v `OnInit` (depth > 0, lookback ≥ 50, min < max, 0 ≤ from < to ≤ 1,
MaxPositions ≥ 1, DedupFrac > 0, MinEntry ≤ MaxEntry, RiskPercent > 0).

### 3.4 `InpAllowBuy/InpAllowSell` ignorují plány, panel i `planState` – CONFIRMED
`mq5:863`, `:293`, `:1354`; vstupy se čtou jen na ř. 1161/1181/1280/1288. Vypnutý směr se dál
kreslí, panel hlásí „připraven“ a jeho platnost mění bitmasku → zbytečné zrušení a znovuzadání
příkazu druhého směru. Oprava: `BuildPlan` vrací neplatný plán s důvodem „směr vypnut“.

### 3.5 Osiřelé GTC příkazy po přepnutí režimu / odebrání EA – PLAUSIBLE
`mq5:229–236` (`OnDeinit` neruší), `:217–218` (`OnInit` ruší jen v pending). Po přepnutí na
M1_CLOSE zůstanou STOP příkazy se starým SL/PT; jejich plnění otevře pozici, kterou režim neměl
otevřít, a ta přes `CanTrade` blokuje řádné vstupy. Scénář „2 pozice“ vyvrací ř. 347 (OCO
v `OnTradeTransaction` běží nezávisle na režimu). Oprava: v `OnInit` při režimu ≠ PENDING
`CancelPendingOrders()`; volitelně i v `OnDeinit` pro `REASON_REMOVE/REASON_PARAMETERS`.

### 3.6 Předčasný návrat `RecalcChannels`/`RecalcRelief` nechá staré objekty i statistiku – CONFIRMED
`mq5:416–420`, `:618–622` – vynulují jen čítač, nezmenší pole, nepřekreslí. Po výpadku historie
zůstanou kanály/reliéf v grafu, panel píše „žádný kanál“, `PrintDiagnostics` tiskne staré
`g_reliefStats` (a při `OnInit` reliéfní statistiku ještě před prvním `RecalcRelief`). Ochrana
čítači v `BuildPlan` je úplná (do výpočtu se staré pole nedostane). Vedlejší efekt: neúspěšný
`RecalcChannels` → `RebuildPlans` neplatné → `PlacePendingOrders` zruší čekající příkazy kvůli
dočasnému výpadku dat. Oprava: v obou větvích `ArrayResize(..., 0)` + překreslit (jako větev
`!InpUseRelief`), nebo při selhání zachovat předchozí výsledek a jen logovat.

### 3.7 Dedup reliéfních přímek porovnává jen jeden okamžik – PLAUSIBLE
`SvedRelief.mqh:433` – `|out[j].ValueAt(tLast) − cand[i].ValueAt(tLast)| < dedupTol`; dvě přímky
s různým sklonem, které se u poslední svíčky kříží, se sloučí – přesně chyba, kterou kanálový
modul řeší dvěma časy (`SvedChannelsSimilar`, ř. 318–342). Oprava: porovnat ve dvou časech.

### 3.8 `SvedDistanceToNextEdge` vrátí d = 0 a hranu POD vstupem – PLAUSIBLE (nízká)
`SvedChannels.mqh:592–593` – když `vProj < price`, `MathMin` dá hodnotu pod vstupem, `d = 0`,
`edgePrice < entry`; `BuildPlan` pak počítá `avail = −20 b`, panel ukáže „málo místa k hraně
(−20 b)“ a v režimu SKIP se `relDist < dist` nikdy nesplní, takže se reliéfní překážka v důvodu
neobjeví. Výsledek (zamítnutí) je správný, hodnoty/text ne. Oprava: případ `v <= price` ošetřit
explicitně a záporné délky nevypisovat.

---

## 4. Vyvrácený kandidát

**„`datetime` je bezznaménkový, `(double)(t − tA)` pro `t < tA` přetéká na ~1.8e19“**
(`SvedTypes.mqh:92`, dopad `SvedChannelIsClean` před bodem A a `tPast` v dedupu) – **REFUTED**.

Empirický důkaz: kompilační sonda přes MetaEditor (RoboForex MT5, `/compile`) s konstantními
výrazy, které interpretují znaménko (dělení, `>>`, převod na double):

```
int  tA = (D'1970.01.01 00:00:01' - D'1970.01.01 00:00:02') / 2;      // bez varování  → 0   (signed)
char tB = (double)(D'1970.01.01 00:00:01' - D'1970.01.01 00:00:02');  // bez varování  → -1.0
int  uA = ((ulong)18446744073709551615) / 2;                          // warning 44: truncation ... 'ulong(9223372036854775807)'
char uB = (double)((ulong)18446744073709551615);                      // warning 44: truncation ... 'double(1.8446744073709552e+19)'
```

Řádky s `datetime − datetime` se chovají jako `long` (−1), kontrolní `ulong` řádky vyvolaly
varování o zkrácení. Shoduje se s dokumentací MQL5 („místo typu long lze použít datetime“).

---

## 5. Konvence (`C:\Users\Admin\.claude\CLAUDE.md`)

Pravidlo: *„definice funkcí a tříd (zde udelej komentář s popisem účelu a parametrů)“*,
*„Komentáře piš nad každý netriviální blok kódu, zejména u: podmínek a větvení … práce s externími
službami a API … workaroundů, omezení a okrajových případů“*, *„Piš čistý a dobře strukturovaný kód“*.

| Soubor:řádek | Porušení |
|---|---|
| mq5:875 | Hlavička `BuildPlan` uvádí „min(450 bodu …)“ – kód používá `InpMaxEntryPoints` (300, ř. 63, 945); parametr `checkReachable` v popisu chybí. |
| SvedDraw.mqh:36, 60, 79 | `SvedTrendLine` (10 parametrů, popsán jen `ray`), `SvedText` a `SvedLabel` (7 parametrů, žádný popsán); `SvedText` natvrdo `"Arial Bold"` (ř. 68) bez komentáře, zatímco `SvedLabel` font přijímá. |
| SvedDraw.mqh:223 | `SvedDrawEntryLevels` – 8 parametrů, žádný popsán; komentář odkazuje na „cas ta“, který neexistuje (`tFrom`). |
| SvedDraw.mqh:4 (mq5:12) | Hlavička tvrdí „kresli se VYHRADNE kanaly“, soubor/EA kreslí i vstup/SL/PT, úrovně průrazu (`BRK_`) a reliéf (`REL_`). |
| SvedRelief.mqh:259–387 | Tělo vnější smyčky přes měřítka není odsazeno (stejná úroveň jako `for`), uzavírací závorka musí nést komentář. |
| mq5:315–324 | Řetězec pěti filtrů v `OnTradeTransaction` (API historie dealů) bez komentáře (proč ignorovat `DEAL_ENTRY_OUT`, proč `HistoryDealSelect`). |
| mq5:1280, 1288 | Podmínka `entry > ask + stopsLevel` = omezení brokera, při nesplnění tichý skip – okrajový případ bez komentáře. |
| SvedChannels.mqh:326; SvedRelief.mqh:151, 207; mq5:364, 777, 825, 1354 | Hlavičky bez popisu parametrů (`frac`, `t1/t2`, `tol`, `midFrom/midTo`, `lastBar`, …). |

Jinak kód konvence dodržuje: komentáře jsou české (bez diakritiky – v pořádku), používá se `//`,
prefixy `g_`/`Inp`/`Sved` konzistentně.

---

## 6. Cleanup – reuse / zjednodušení / efektivita / altitude

Tyto nálezy neřeší pády ani špatné obchody, ale cenu údržby a výkonu. Korektnostní nálezy výše
mají přednost. Kde se kopie kódu **už rozešly**, je to uvedeno – to je nejsilnější argument
pro sjednocení.

### 6.1 Reuse (duplicity)

| Soubor:řádek | Duplicita | Kde se kopie už liší / cena |
|---|---|---|
| mq5:1070 (1088, 1106, 1243, 1482) | Filtr „pozice/příkaz patří strategii“ (symbol + magic) 5× místo predikátu `IsOurPosition()/IsOurOrder()` (nebo `CPositionInfo/COrderInfo`); `OpenMarket` má ticket z `g_trade.ResultDeal()/ResultOrder()`, ale nepoužívá ho. | Polarita podmínky se liší (`==` vs. negace + `continue`); `AdjustPositionStops` přepisuje stopy všem pozicím (2.14). Změna identifikace = 5 editací. |
| mq5:916 (783, 845, 808, 1157) | Test „cena za úrovní“ 5× s vlastní obsluhou bufferu místo `PriceBeyondLevel(isBuy, price, level, buffer)` + jedné smyčky `BarsBreakLevel(rates, from, ...)` pro H1 i M1 variantu. | `BuildPlan` testuje BUY proti ASK neostře (`entry <= ask`), `UpdateArming` proti BID ostře → v pásmu šířky spreadu se plán zneplatní („průraz už proběhl“), ale `g_buyBroken` zůstane false; po návratu ceny plán ožije, `planState` se překlopí a příkaz se zruší/znovu zadá. Zdroj nálezů 2.2, 2.6, 2.11. |
| SvedChannels.mqh:546 (357–371), SvedRelief.mqh:257–273 | Víceměřítková smyčka `depth = base<<s; if(depth*2+3 >= n) break;` a generátor dvojic `for i / for gap += 2` opsány mezi kanály a reliéfem; `SvedBuildChannels` dostává `scales` dvakrát (`p.scales` clampnuté, argument surový). | Kopie se liší (`if(ns < 2) continue;` jen v reliéfu, `i + 2 < ns` vs. `i < ns`, `maxGap = MathMax(..., 2)` 2×); detekce jede podle argumentu, 1. fáze výběru podle `p.scales` – při změně jednoho místa se vybírá z jiného počtu měřítek, než kolik se detekovalo. Tělo reliéfní smyčky není ani odsazené (pozůstatek vložení kopie). |
| SvedRelief.mqh:161 (194, 221, 125/136) | Signed vzdálenost svíčky od přímky a predikát dotyku `d >= -tol && d <= tol` opsány ve 3–4 funkcích místo `SReliefLine::GapTo()/Touches()`. | Sémantika není na jednom místě: `IsClean` mezi oporami toleruje knot až `wickTol` (150 b), `touchTol` je 25 b → knot 30–150 b za přímkou není ani průraz, ani dotyk a mlčky vypadne z `touches` i `midTouch`. Makra `SVED_TOUCH_GAP` a `SVED_RELIEF_TOUCH_GAP` = dvě konstanty téhož významu a hodnoty. |
| mq5:1161 (1280, 327; SvedChannels.mqh:588; SvedRelief.mqh:475) | Zrcadlové BUY/SELL bloky (2×17, 2×12, 2×11 řádků) místo parametrizace přes `isBuy`, jak už to dělají `BuildPlan`, `StateText`, `AdjustPositionStops`. | SELL větev `CheckEntryOnEntryTF` je bezkomentářová kopie; `d = isBuy ? v - price : price - v; if(d <= 0) continue;` nahradí obě větve `SvedDistanceToNextEdge`/`SvedNearestRelief`. Nastavování příznaků se rozjíždí mezi `OnTradeTransaction` a `CheckEntryOnEntryTF`. |
| SvedChannels.mqh:451 (512), SvedRelief.mqh:393 | Výběrové řazení podle `score` 3× místo `template<typename T> SvedSortByScoreDesc(T &arr[])`. | 3×8 řádků; při rovnosti skóre dnes rozhoduje pořadí vzniku kandidáta – sekundární klíč (stáří) by se musel přidat třikrát. |
| SvedChannels.mqh:478 (496) | Dedup smyčka fáze 1 a 2 `SvedSelectChannels` identická; analogická dvojice `used/dup` v `SvedBuildReliefLines` (418–440). | 2×8 řádků, `tPast`/`dedupFrac` se předávají dvakrát. |
| mq5:746 (803, 842, 860, 1152; 999, 1277; 573, 655, 949, 1315, 1340; 410–416, 614–618, 733–738) | `InpBreakoutBuffer * _Point` 5×, stops-level 2×, `TimeCurrent() + PeriodSeconds(tf)*bars` 5×, `ArraySetAsSeries + CopyRates(shift 1) + copied < 50` 3×; `SChannelParams/SReliefParams` se plní z neměnných inputů každý bar. | Buffer je součást obchodní logiky na 5 místech – závislost na ATR/směru = 5 editací, vynechání jednoho rozjede `UpdateArming` proti `BuildPlan`. Helpery `g_breakBuffer`, `FutureTime(tf, bars)`, `LoadClosedBars(tf, n, rates)`, parametry naplnit v `OnInit`. |

### 6.2 Zjednodušení

(Úhel „simplification“ výstup nedodal; postřehy revidenta z četby, neověřené verifikátorem.)

- `g_channelCount`/`g_reliefCount` vs. `ArraySize(...)` – redundantní stav, který se v předčasných
  návratech rozchází (3.6). `SEntryPlan.distance` odvoditelné z entry/sl; `SEntryPlan.blockedByRelief`
  se nikde nečte.
- Typ překážky se rekonstruuje rovností doublů `pl.edgePrice == pl.reliefPrice` (ř. 1003) a přetížením
  `limitedByEdge` (viz 6.4).
- Magické konstanty: `n − 51` (dedup), `n < 12` / `string lines[20]` (panel), `copied < 50`, `−1000`,
  `10.0 * _Point`, `tol * 2.0`, váhy skóre 6/15/6/0.6/2 a 2/100/200, `InpPanelFontSize + 5`.
- `ArrayResize(cand, 0)` na čerstvém lokálním poli, `ArraySetAsSeries(rates, false)` na čerstvém poli
  (výchozí stav), `if(ok)` dvakrát za sebou v `OpenMarket`, `used` test v `SvedBuildReliefLines`
  (418–426) nemůže nastat (kandidáti jsou už unikátní na `(i1, isHigh)`).
- Zavádějící komentáře: hlavička `BuildPlan` „min(450 bodu“, hlavička `SvedDraw.mqh` „VYHRADNE kanaly“,
  komentář `SEntryPlan.distance` „SL = TP = distance“ (viz kap. 5); překlepy ve viditelných textech
  vstupů („pruzazu“ místo „prurazu“ v `input group` a komentářích vstupů ř. 16, 28, 31–35).

### 6.3 Efektivita

| Soubor:řádek | Plýtvání | Odhad ceny / levnější varianta |
|---|---|---|
| mq5:302 (354) | `UpdatePanel()` na každém ticku **a** každou sekundu z timeru: ~13× `StringFormat`, `PositionText` + `CountOrders` (smyčky), 13× `SvedLabel` (`ObjectFind` + 10× `ObjectSet*`), 7× `ObjectDelete` neexistujících jmen, `ChartGetInteger`, `ChartRedraw`. Při `InpShowPanel=false` navíc plný průchod objekty grafu (`SvedDeleteObjects("PNL_")`) na každém ticku. | ~150 volání chart API + 1 překreslení na tick → na XAUUSD (10–30 ticků/s) 1 500–4 500 volání/s. Volat jen z timeru + událostí, držet poslední text řádků a měnit jen změněné; statické vlastnosti nastavit jen při `ObjectCreate`. |
| mq5:1270 | Cancel + re-place všech příkazů i beze změny; volá se na každém M15 i H1 baru a při každém flipu `planState`. | 2–4 blokující round-tripy (~50–300 ms) každých 15 min ≈ 200–400 požadavků/den; na hranici hodiny až 8–12 round-tripů v jednom ticku, během nichž EA nezpracovává ticky. Rekonciliace: `OrderModify` jen při rozdílu (řeší i 2.1, 2.4). |
| SvedRelief.mqh:306 (315, 327, 333, 342) | O(n) `SvedReliefIsClean` běží PŘED O(1) testem driftu; přeživší kandidát dostane další 2–3 průchody týmiž bary (`HasMidTouch`, `CountTouches`, `MeanGap`). | ~1 500–2 000 dvojic/min × sken až 2 400 barů ≈ 0,5–1 mil. iterací/min živě (~1–3 ms); ve Strategy Testeru ×350 000 M1 barů/rok ≈ 10–20 min/rok. Drift před IsClean, `maxOver/touches/meanGap/midTouch` v jednom průchodu. |
| mq5:838 | `LevelAlreadyBroken` kopíruje M1 od swingu do teď (až ~17 000 svíček, ~1 MB) 2× při každém `RefreshBreakoutLevels`, ačkoli uzavřené H1 bary už prověřil `SwingBroken`. | Stačí otevřený H1 bar: `iHigh(_Symbol, InpBreakoutTF, 0) > level + buffer` – 2 O(1) volání místo dvou kopií pole (viz i 2.11, 3.2). |
| SvedDraw.mqh:24 | `SvedDeleteObjects` = plný průchod `ObjectsTotal` + `ObjectName` + `StringFind` pro každý prefix zvlášť před každým překreslením (3 průchody na M1 bar, +2 na M15, +1 na H1), pak znovuvytvoření objektů (13 volání na čáru). | ~150–300 volání/min + blikání. `ObjectsDeleteAll(0, prefix)` (1 volání), nebo mazání vynechat – `SvedTrendLine/SvedText` už aktualizují in-place, smazat jen přebytečné indexy (jako `UpdatePanel`). |
| SvedChannels.mqh:451 (427) | Výběrové řazení O(nc²) struktur `SChannel` (~300 B, 3 kopie na swap) + `ArrayResize(cand, nc + 1)` bez rezervy. | nc≈200: ~20 000 porovnání, ~9 MB memcpy; nc≈1 000: ~500 000 porovnání, ~225 MB. Řadit indexy / insertion do top-K (K = maxChannels × scales); `ArrayResize(cand, nc + 1, 256)`. |
| SvedChannels.mqh:225 (165, 180, 425) | O(1) test `requireInside` až po O(n) `IsClean` + smyčce dotyků; kandidát pak dostane třetí průchod v `SvedCollectTouchPoints`. | ~150 000–500 000 iterací na M15 bar; test „cena uvnitř“ hned za filtry šířky, tři průchody sloučit do jedné smyčky `iA..n`. (Pozn.: s výchozími prahy je `requireInside` beztak mrtvý – 2.15.) |

### 6.4 Altitude (hloubka řešení)

| Soubor:řádek | Náplast | Obecný mechanismus / cena |
|---|---|---|
| mq5:293 | Bitmaska platnosti `g_lastPlanState` + 4 roztroušená volání `PlacePendingOrders`. | Rekonciliace „požadovaný stav příkazu vs. skutečný příkaz“ z jednoho místa po každém `RebuildPlans` (najít podle magic+typ, porovnat cenu/SL/TP/objem, vytvořit/`OrderModify`/smazat). Řeší 2.1, 2.4, 3.4 najednou; každý nový vliv na návrh dnes vyžaduje další ruční spouštěč. |
| mq5:329 (1171, 699) | „Na této úrovni už obchodováno“ v prchavých příznacích se dvěma zapisovateli a třetím nulovacím místem. | Odvození z historie dealů (`HistorySelect` od času swingu, `DEAL_ENTRY_IN` + magic + symbol + směr) – bez stavu, přežije restart (viz 2.2). |
| mq5:889 | Sada ochran svázaná s jedním bool `checkReachable`. | `EntryBlockReason(isBuy, mode)` se stejným seznamem ochran pro oba režimy, liší se jen predikát dosažitelnosti; `CountPositions` se dnes kontroluje dvakrát a každá nová ochrana v `BuildPlan` se tiše netýká M1 režimu (2.7). |
| mq5:808 (783, 845, 916) | Čtyři nezávislé skenery „proraženo“ nad čtyřmi zdroji dat (uzavřené H1, M1 CopyRates, živý bid, ask/bid). | Jeden stavový objekt úrovně (cena, čas, ARMED/BROKEN/TAKEN) s jedinou `IsBroken`, kterou by používal i `FindBreakoutSwings` (2.2, 2.6, 2.11). |
| mq5:175 (430, 433, 640; SvedChannels 366, 471, 546; SvedRelief 249, 257) | Ořezy `MathMax` rozsypané v callerech i knihovnách, většina vstupů nekontrolována. | Jedna `ValidateInputs()` v `OnInit` → `INIT_PARAMETERS_INCORRECT` s názvem parametru; ořezy v knihovnách mění sémantiku potichu (`InpSwingScales = 0` běží jako 1) a už nejsou konzistentní (3.3). |
| SvedChannels.mqh:191 (59–70, 278, 627) | „Dotyk“, „proříznutí“, „uvnitř“ = čtyři ad-hoc nerovnosti. | Jedna signovaná vzdálenost od hrany na `SChannel` + predikáty `Touches/Pierces/Contains`. Dnes: při `touchTolFrac 0.05` / `invalidTolFrac 0.15` svíčka 0.08 w nad hranou projde IsClean, není dotyk (nad `2×tol`), ale `CollectTouchPoints` (bez horní meze) ji zapíše jako bod D → panel „dotyků N“ a písmena D/E/F si odporují; „uvnitř“ má dvě definice (0.15 w vs. `InpInsideTolFrac` 0.02 w). |
| mq5:1003 (992, 1225, 1389) | Druh bariéry rekonstruován porovnáním doublů + přetížený `limitedByEdge`. | Enum bariéry (NONE/CHANNEL_EDGE/RELIEF) + cena v `SEntryPlan`; dnes v režimu SHORTEN panel i log hlásí „zkráceno hranou“, ačkoli bariérou byla přímka – obchodník ladí špatný parametr. |
| mq5:630 (424, 45–46, 86–97) | Tolerance ve čtyřech jednotkách (zlomek šířky, body, násobek ATR, body + ATR u šířky), převod na cenu na místě použití. | Přesun na brokera s 3 desetinnými místy u XAUUSD zpřísní všech 6 reliéfních bodových tolerancí 10× (reliéf tiše zmizí – vše „proraženo“) a `InpMinWidthPoints` 10× uvolní; varování v `OnInit` (202–206) pokrývá jen `InpMaxEntryPoints` z ~13 bodových vstupů. Jedna cenová jednotka (násobek ATR / normalizace na digits) převedená jednou v `OnInit`. |
