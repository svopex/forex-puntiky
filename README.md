# Sved Channel Breakout — strategie pro MetaTrader 5

Expert Advisor pro MT5, který detekuje ABCD kanály, kreslí je do grafu a obchoduje
průrazy H1 high/low uvnitř těchto kanálů. Do grafu vykresluje **pouze kanály
a informace o vstupu** — žádné jiné indikátory ani pomocnou grafiku.

Testovací prostředí: RoboForex MT5, demo účet `67205475`, ticker `XAUUSD`.

## Jak strategie funguje

### Kanály (timeframe M15)

1. Z historie M15 se sestaví zig‑zag kostra trhu — střídavé swingové vrcholy a dna
   (pivot okno o šířce `InpSwingDepth` svíček na každou stranu). Kostra se hledá
   opakovaně v několika měřítkách (`InpSwingScales`) s postupně dvojnásobným oknem —
   jemné okno najde malé kanály, hrubé velké. Právě tím vzniká **kanál v kanálu**.
2. Z každé dvojice swingů stejného typu (**A** a **C**) vzniká kandidát na kanál —
   mezi nimi smí ležet další swingy (až `InpMaxSwingGap`). Jako **B** se bere
   protilehlý swing **nejdál od základní úsečky** — měří se odstup od šikmé čáry,
   ne absolutní cena, protože cenově nejnižší swing nemusí být ten, který
   rovnoběžku odtlačí nejdál:
   - A a C jsou **dna** → základní čárou je **LOW úsečka** vedená body A–C,
     horní hrana je její rovnoběžka procházející bodem B (přesně situace z `docs/abcd.png`),
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
   - **Protější hrana** (rovnoběžka bodem B) musí držet jen mezi A a C. Za bodem C
     se toleruje `InpInvalidTolFrac` (15 % šířky); větší překročení znamená
     **proražený, tedy neplatný kanál** — vypadne z kandidátů a přestane se kreslit
     i obchodovat.
   - Základní úsečka se navíc kontroluje i `InpBackCheckBars` svíček **před** bodem
     A, aby ji zleva neprorážel dřívější extrém.
5. Opory **A a C musí být cenově nejvýraznějším extrémem** v okně
   ±`InpAnchorWindow` svíček — v okolí nesmí ležet vyšší vrchol (u HIGH základny),
   resp. hlubší dno (u LOW základny). To je jiná podmínka než nepřeříznutá úsečka:
   úsečka je šikmá, takže sousední vrchol může být cenově výš a přitom pořád **pod**
   prodlouženou čárou. Bez této kontroly by úsečka začínala na druhém nejvyšším
   vrcholu místo na tom nejvyšším.
7. Kanál se ohodnotí a musí projít filtry, aby byl považován za *hlavní a důležitý*:
   - minimální délka A→C (`InpMinSpanBars`),
   - minimální šířka v bodech i v násobcích ATR (`InpMinWidthPoints`, `InpMinWidthATR`),
   - minimální počet dotyků obou hran (`InpMinTouches`),
   - minimální podíl svíček uzavřených uvnitř kanálu (`InpMinContainment`),
   - maximální stáří bodu C (`InpMaxAgeBars`).
8. Kanály se seřadí podle skóre (dotyky, respektování hran, délka, šířka, stáří),
   odstraní se prakticky totožné duplicity a ponechá se nejvýše `InpMaxChannels`
   nejlepších. **Kanál v kanálu zůstává zachován** — zahazují se jen kanály, jejichž
   obě hrany leží prakticky na sobě.

### Vstup (úrovně H1, vyhodnocení M1)

- Úrovně průrazu = **HIGH posledního swingového vrcholu a LOW posledního swingového
  dna na H1**, které cena **ještě neprorazila**. Proražená úroveň je spotřebovaná,
  takže se pokračuje k předchozímu swingu — typicky výraznějšímu, který je pořád
  platnou hranicí. Jakmile úroveň padne, hledá se další okamžitě, nečeká se na
  otevření další H1 svíčky. Nestačí tedy libovolná hodinová svíčka — musí jít o svíčku, která je
  zároveň swingem (lokální extrém v okně `InpBreakSwingDepth` svíček na každou
  stranu). Swing je potvrzený až svíčkami za ním, takže úroveň je o pár hodin
  zpožděná — to je záměr, ne chyba.
- Na jedné swingové úrovni se obchoduje **nejvýše jednou**; příznaky se resetují až
  ve chvíli, kdy vznikne nový swing.
- Vypnutím `InpUseSwingLevels` se strategie vrátí k prostému high/low poslední
  uzavřené H1 svíčky.
- Průraz musí nastat **uvnitř** některého z detekovaných kanálů, jinak se signál zahodí.
- Vyhodnocení běží na **M1**: průraz je potvrzen uzavřením M1 svíčky za úrovní
  (o `InpBreakoutBuffer` bodů). Vstupuje se tržním příkazem.
- **Výchozí režim je `SVED_ENTRY_PENDING`**: BuyStop a SellStop se umístí přímo na
  swingové úrovně. Zadají se hned po nahození experta a přepočítají se s každou
  novou M15 svíčkou (posunuly se hrany kanálu, takže SL i PT už neodpovídají)
  i s každou novou H1 svíčkou. Po otevření pozice se zbylý příkaz zruší (OCO).
- Režim `SVED_ENTRY_M1_CLOSE` místo toho čeká na uzavření M1 svíčky za úrovní
  a vstupuje tržním příkazem — v terminálu tedy do vstupu není vidět žádný příkaz.
  Vstupuje se jen na **skutečném přechodu** přes úroveň (předchozí M1 svíčka musí
  být ještě na druhé straně), aby expert nevstoupil dlouho po průrazu — třeba až
  potom, co pominula překážka v podobě reliéfní přímky.
- Návrh vstupu se přestane nabízet, jakmile **běží pozice** (`pozice již otevřena`)
  nebo když už se **na dané swingové úrovni obchodovalo** (`tato úroveň už
  obchodována`). Vyplnění pending příkazu se zachytává v `OnTradeTransaction`, takže
  o něm expert ví i v případě, že příkaz vyplnil broker bez jeho přičinění.
- Návrh vstupu platí jen dokud průraz **teprve čeká**. Když cena úrovní už prošla,
  není co prorazit a STOP příkaz nad/pod trhem by stejně nešlo zadat — takový návrh
  se proto nekreslí do grafu ani nenabízí v panelu (`průraz už proběhl`).
- Směr je zablokovaný, dokud cena nebyla na správné straně úrovně — zabraňuje
  vstupu do už proběhlého pohybu (gap, start EA uprostřed pohybu).

### Reliéfní přímky (timeframe M1)

Reliéfní přímka je trendlinie vedená dvěma **hlavními swingy stejného typu** na
vstupním timeframu — dvěma vrcholy (odpor) nebo dvěma dny (podpora). Stojí průrazu
v cestě, takže ji strategie hlídá při plánování vstupu (viz `docs/relief_1.png`).

1. Swingy se hledají s hrubším oknem (`InpReliefSwingDepth`, výchozí 10 svíček),
   aby šlo opravdu o hlavní swingy a přímek nebylo příliš.
2. Přímka musí cenu **obalovat** — posuzuje se ale stejně, jako když se trendline
   kreslí ručně: **tělo svíčky ji nesmí překročit vůbec** (`InpReliefPierceTol`),
   zatímco **knot ji smí přesáhnout** až o `InpReliefWickTol` — ale **jen mezi
   oporami**; prostřel knotem uvnitř útvaru trendline neruší. **Za druhou oporou
   je přímka tvrdá hranice**: i knot přes ni znamená nový extrém — přímka přestává
   platit a kotva patří na novou svíčku. Tělo za přímkou = proražení kdykoli;
   **proražená přímka už není překážkou** a mezi kandidáty se nedostane.
3. Musí mít aspoň `InpReliefMinTouches` potvrzených dotyků a délku
   `InpReliefMinSpan` svíček. Z přímek **se stejnou první oporou a směrem** se drží
   jen ta nejlepší: přednost má **skutečná tečna** (nejmenší přesah knotů — přímka
   má procházet špičkami svíček, ne je řezat), pak víc dotyků, menší přilnutí
   a delší záběr. Přímka klenoucí se přes údolí mezi dvěma vzdálenými swingy je
   přitom pořád platná — přilnutí není filtr, jen rozhodčí mezi variantami.
4. Přímka nesmí od své druhé opory **ujet dál než `InpReliefMaxDrift`** a platí
   jen `InpReliefMaxAge` násobek vlastní délky za druhou oporou. Strmá čára se
   jinak za pár hodin vzdálí desítky dolarů od ceny, kde už se ničeho nedotýká —
   to není reliéf, ale artefakt prodloužení.
5. Ponechá se nejvýše `InpMaxReliefLines` nejvýznamnějších (podle dotyků, délky
   a čerstvosti), prakticky totožné přímky se sloučí. Při výběru se **střídají
   odpory a podpory**, aby jeden typ neobsadil všechny sloty.

Když leží přímka ve směru obchodu **blíž než plánovaný PT**, rozhoduje
`InpReliefMode`:

| Režim | Chování |
|---|---|
| `SVED_RELIEF_SKIP` (výchozí) | vstup se přeskočí, důvod se vypíše v panelu |
| `SVED_RELIEF_SHORTEN` | PT se zkrátí před přímku (mínus `InpReliefBuffer`), SL stejně — RRR zůstává 1:1 |

Přímky se přepočítávají s každou novou M1 svíčkou a kreslí se do grafu tečkovaně
(`InpColorRelief`).

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
- Když je místa méně než `InpMinEntryPoints`, obchod se neotevře a důvod se zobrazí
  v panelu.
- Po otevření se SL a PT dorovnají na skutečnou plnicí cenu, aby poměr zůstal přesně 1:1.

### Co se kreslí do grafu

| Objekt | Význam |
|---|---|
| HIGH úsečka (červená) | horní hrana kanálu, prodloužená doprava |
| LOW úsečka (modrá) | spodní hrana kanálu, prodloužená doprava |
| A1, B1, C1, D1 … | opory kanálu; číslice udává, ke kterému kanálu bod patří |
| D, E, F, G … | potvrzené dotyky hran za bodem C, kreslené až po jejich vzniku |
| Zlaté čárkované čáry | úrovně průrazu; čára začíná u swingové svíčky, ze které pochází |
| Bílá / červená / zelená tečkovaná | plánovaný vstup, SL a PT pro oba směry |
| Fialové tečkované | reliéfní přímky z hlavních M1 swingů |
| Panel vlevo nahoře | parametry kanálů, úrovně průrazu, návrhy vstupu, stav pozice |

Popisky sdílené opory se slučují (`E1 E3`), panel uhýbá one-click SELL/BUY panelu.

Hlavní kanál (nejvyšší skóre) se kreslí silnější čarou než ostatní.

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
  Experts/Sved/SvedChannelBreakout.mq5   hlavní EA — vstupy, obchodování, panel
  Include/Sved/SvedTypes.mqh             datové struktury a výčtové typy
  Include/Sved/SvedSwings.mqh            detekce swingových bodů (zig-zag)
  Include/Sved/SvedChannels.mqh          stavba, hodnocení a výběr kanálů
  Include/Sved/SvedDraw.mqh              vykreslování kanálů a úrovní
scripts/deploy.cmd                       spouštěč (obchází ExecutionPolicy)
scripts/deploy.ps1                       kopie do terminálu + kompilace
docs/zadani.md, docs/abcd.png            zadání
```

## Přehled parametrů

### Timeframy
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpChannelTF` | M15 | detekce a kreslení kanálů |
| `InpBreakoutTF` | H1 | svíčka, jejíž high/low se prorážejí |
| `InpEntryTF` | M1 | vyhodnocení průrazu |

### Detekce kanálů
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpLookbackBars` | 1500 | kolik M15 svíček se analyzuje |
| `InpSwingDepth` | 3 | základní šířka okna pro swingy |
| `InpSwingScales` | 3 | počet měřítek detekce (kanál v kanálu) |
| `InpMaxSwingGap` | 8 | kolik swingů smí ležet mezi A a C |
| `InpPierceTolFrac` | 0.05 | kolik smí cena prořezávat hranu (zlomek šířky) |
| `InpInvalidTolFrac` | 0.15 | za jakým přesahem je kanál invalidovaný |
| `InpBackCheckBars` | 20 | kolik svíček před bodem A se ještě kontroluje |
| `InpAnchorWindow` | 10 | okno, ve kterém musí být A a C nejvýraznějším extrémem |
| `InpMinSpanBars` | 20 | minimální délka A→C |
| `InpMaxAgeBars` | 300 | maximální stáří bodu C |
| `InpMinWidthPoints` | 300 | minimální šířka kanálu v bodech |
| `InpMinWidthATR` | 1.5 | minimální šířka v násobcích ATR |
| `InpMinTouches` | 4 | minimální počet dotyků hran |
| `InpTouchTolFrac` | 0.15 | tolerance dotyku jako zlomek šířky |
| `InpMinContainment` | 0.85 | minimální podíl svíček uvnitř |
| `InpMaxChannels` | 3 | kolik kanálů se ponechá |
| `InpDedupFrac` | 0.25 | práh, kdy se dva kanály považují za totožné |
| `InpRequireInside` | true | kanál platí jen když je v něm aktuální cena |

### Úrovně průrazu
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpUseSwingLevels` | true | prorážet jen swingové H1 svíčky |
| `InpBreakSwingDepth` | 2 | šířka okna pro H1 swingy |
| `InpBreakLookback` | 300 | kolik H1 svíček se prohledává |

### Vstup
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpEnableTrading` | true | false = jen kreslení bez obchodů |
| `InpEntryMode` | M1 close | potvrzení na M1 vs. pending STOP příkazy |
| `InpMaxEntryPoints` | 300 | maximální délka vstupu |
| `InpMinEntryPoints` | 100 | pod touto délkou se nevstupuje |
| `InpBreakoutBuffer` | 10 | buffer za úrovní průrazu |
| `InpEdgeBuffer` | 20 | rezerva PT před hranou kanálu |
| `InpEdgeProjBars` | 12 | o kolik svíček dopředu se hrany promítají |
| `InpMaxPositions` | 1 | maximální počet současných pozic |
| `InpMagic` | 67205475 | magic number |
| `InpAllowedAccount` | 0 | 0 = bez omezení, jinak povolený účet |

### Zobrazení
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpPanelLineHeight` | 20 | výška řádku panelu v pixelech (0 = podle písma) |
| `InpPanelOneClickShift` | 150 | posun panelu pod SELL/BUY okno MT5 |
| `InpPointFontSize` | 10 | velikost písma popisků opor |
| `InpLabelMergeATR` | 0.5 | sloučení blízkých popisků (násobek ATR) |

### Diagnostika
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpDiagnostics` | true | výpis detekce kanálů do Expert logu |
| `InpShotOnRequest` | true | snímek grafu na vyžádání (viz níže) |
| `InpShotEveryBars` | 0 | snímek každých N svíček TF kanálu (0 = vypnuto) |
| `InpShotFileName` | SvedShot.png | soubor snímku v `MQL5\Files` |
| `InpShotRequestFile` | SvedShot.request | soubor požadavku o snímek |

Při zapnuté diagnostice se s každým přepočtem kanálů (nová M15 svíčka) zapíše
do Expert logu, kolik kandidátů padlo na kterém filtru, a rozpis opor vybraných
kanálů. Z rozložení zamítnutí je hned vidět, který práh je úzkým hrdlem.

Snímek grafu si lze vyžádat kdykoliv — stačí v `MQL5\Files` vytvořit prázdný
soubor `SvedShot.request`. Expert ho do sekundy zpracuje, uloží
`MQL5\Files\SvedShot.png` a požadavek smaže.

### Reliéfní přímky
| Parametr | Výchozí | Význam |
|---|---|---|
| `InpUseRelief` | true | hlídat reliéfní přímky |
| `InpReliefMode` | SKIP | přeskočit vstup / zkrátit PT |
| `InpReliefLookback` | 2400 | kolik M1 svíček se analyzuje |
| `InpReliefSwingDepth` | 10 | šířka okna pro hlavní swingy |
| `InpReliefSwingGap` | 6 | max. odstup opor (počet swingů) |
| `InpReliefMinSpan` | 30 | minimální délka přímky ve svíčkách |
| `InpReliefMinTouches` | 2 | minimální počet dotyků |
| `InpReliefPierceTol` | 10 | proříznutí přímky tělem svíčky (body) |
| `InpReliefWickTol` | 150 | povolený přesah přímky knotem (body) |
| `InpReliefTouchTol` | 25 | tolerance dotyku (body) |
| `InpReliefDedupTol` | 40 | práh shody dvou přímek (body) |
| `InpMaxReliefLines` | 6 | kolik přímek ponechat |
| `InpReliefMaxAge` | 0.0 | platnost přímky za 2. oporou (0 = neomezeno) |
| `InpReliefMidTouch` | false | vyžadovat dotyk i uprostřed přímky |
| `InpReliefMidFrom` / `InpReliefMidTo` | 0.20 / 0.80 | prostřední úsek přímky |
| `InpReliefMaxDrift` | 1200 | max. vzdálení přímky od 2. opory (body) |
| `InpReliefBuffer` | 20 | rezerva PT před přímkou (body) |

### Objem
`InpLotMode` — pevný lot (`InpFixedLot`, výchozí 0.10) nebo dopočet z rizika
(`InpRiskPercent` % zůstatku na SL).

## Poznámky a omezení

- Kanály se přepočítávají jen z **uzavřených** M15 svíček, takže se uvnitř
  rozpracované svíčky nemění a nepřekreslují se zpětně.
- Výchozí filtry jsou nastavené konzervativně, aby prošly opravdu jen výrazné
  kanály. Pokud se na grafu nekreslí nic, sniž `InpMinTouches` na 3 nebo
  `InpMinContainment` na 0.80.
- Body se popisují písmenem a číslem kanálu (`A1`, `B1`, `C1`, `D1` … pro první
  kanál, `A2`, `B2` … pro druhý), takže je vidět, co ke kterému kanálu patří.
  Číslování odpovídá pořadí v panelu; kanál 1 je hlavní a kreslí se silnější čarou.
- Když je jedna svíčka oporou víc kanálů, popisky by se překrývaly. Proto se
  nejdřív sesbírají ze všech kanálů a ty, které padnou na stejné místo (stejná
  svíčka, stejná strana, cena blíž než `InpLabelMergeATR` × ATR), se sloučí do
  jednoho textu — např. `E1 E3`.
- Panel se automaticky posune o `InpPanelOneClickShift` pixelů níž, pokud je
  v grafu zapnutý one-click SELL/BUY panel MetaTraderu, aby se s ním nepřekrýval.
- Výběr kanálů probíhá dvoufázově: nejprve se vezme nejlepší kanál z **každého**
  měřítka (to zaručí, že se vedle velkého kanálu vykreslí i vnořený menší), teprve
  pak se zbylá místa doplní podle skóre.
- Strategie nemá časový filtr obchodních hodin ani filtr zpráv — pokud jsou
  potřeba, je to samostatné rozšíření.
