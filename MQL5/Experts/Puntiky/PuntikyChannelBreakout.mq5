//+------------------------------------------------------------------+
//|                                      PuntikyChannelBreakout.mq5  |
//|                                                                  |
//|  Strategie "Puntiky Channel Breakout":                           |
//|   - kanaly ABCD se detekuji a kresli na M15, vcetne vnorenych    |
//|   - urovne prurazu jsou HIGH / LOW swingove H1 svicky            |
//|     (bezna hodinova svicka signal nedava)                        |
//|   - vstup se vyhodnocuje na M1                                   |
//|   - rezim MANUAL: expert sam neobchoduje, jen kresli a blika,    |
//|     obchody zadava uzivatel tlacitky LONG / SHORT v grafu        |
//|   - tlacitka LONG 2x / SHORT 2x zadaji dva obchody naraz:        |
//|     prvni s PT 1:1, druhy s PT na dvojnasobku, oba se stejnym    |
//|     SL a kazdy s polovicnim rizikem (celkem stejne jako 1 obchod);|
//|     obchod odebira totez tlacitko, ktere ho zadalo               |
//|   - delka vstupu max. InpMaxEntryPoints bodu, SL:PT = 1:1        |
//|   - pokud je hrana kanalu bliz, PT se zkrati k teto hrane        |
//|     a SL se zkrati stejne (RRR zustava 1:1)                      |
//|   - do grafu se kresli kanaly, urovne prurazu, reliefni primky,  |
//|     urovne planovaneho vstupu a informacni panel                 |
//+------------------------------------------------------------------+
#property copyright "Puntiky"
#property version   "1.22"
#property description "Prurazy swingovych H1 urovni uvnitr ABCD kanalu (kanaly M15, vstup M1)"

#include <Trade\Trade.mqh>
#include <Puntiky\PuntikyTypes.mqh>
#include <Puntiky\PuntikySwings.mqh>
#include <Puntiky\PuntikyChannels.mqh>
#include <Puntiky\PuntikyRelief.mqh>
#include <Puntiky\PuntikyDraw.mqh>

//--- Timeframy
input group "=== Timeframy ==="
input ENUM_TIMEFRAMES InpBreakoutTF       = PERIOD_M15;   // TF urovni prurazu (high/low svicky)
input ENUM_TIMEFRAMES InpEntryTF          = PERIOD_M1;    // TF vyhodnoceni vstupu (potvrzeni svickou, spread)

//--- Timeframy detekce kanalu. Kanaly se hledaji v kazdem zapnutem
//--- timeframu zvlast a vysledky se michaji do jednoho grafu; kazdy
//--- kanal si nese, ze ktereho timeframu pochazi. Vypnuty slot se
//--- proste preskoci, poradi slotu nema na vysledek vliv.
//--- Bary vstupu (InpLookbackBars, InpMinSpanBars, InpMaxAgeBars,
//--- InpForwardBars) plati pro KAZDY zapnuty timeframe zvlast, stejne
//--- jako InpMaxChannels - ctyri zapnute timeframy tedy daji az
//--- ctyrnasobek kanalu.
//--- Prvni zapnuty timeframe je zaroven referencni: pocita se z nej
//--- ATR (filtr sirky kanalu, prah driftu reliefu, slucovani popisku)
//--- a v jeho barech se zadava InpEdgeProjBars.
input group "=== Timeframy kanalu ==="
input bool            InpChannelTF1Use    = true;         // Kanaly 1 - zapnout
input ENUM_TIMEFRAMES InpChannelTF1       = PERIOD_M15;   // Kanaly 1 - timeframe
input bool            InpChannelTF2Use    = true;         // Kanaly 2 - zapnout
input ENUM_TIMEFRAMES InpChannelTF2       = PERIOD_M1;    // Kanaly 2 - timeframe
input bool            InpChannelTF3Use    = true;         // Kanaly 3 - zapnout
input ENUM_TIMEFRAMES InpChannelTF3       = PERIOD_H1;    // Kanaly 3 - timeframe
input bool            InpChannelTF4Use    = true;         // Kanaly 4 - zapnout
input ENUM_TIMEFRAMES InpChannelTF4       = PERIOD_D1;    // Kanaly 4 - timeframe

//--- Timeframy detekce reliefnich primek. Plati totez co u kanalu:
//--- kazdy zapnuty timeframe se hleda samostatne, bary vstupu
//--- (InpReliefLookback, InpReliefMinSpan, InpReliefForwardBars) i
//--- InpMaxReliefLines plati pro kazdy z nich zvlast.
//--- Timeframe reliefu uz nesouvisi s TF vstupu - drive se primky
//--- hledaly vzdy na InpEntryTF, takze zmena potvrzovaci svicky
//--- prekreslila i cely relief.
input group "=== Timeframy reliefu ==="
input bool            InpReliefTF1Use     = true;         // Reliefni primky 1 - zapnout
input ENUM_TIMEFRAMES InpReliefTF1        = PERIOD_M15;   // Reliefni primky 1 - timeframe
input bool            InpReliefTF2Use     = true;         // Reliefni primky 2 - zapnout
input ENUM_TIMEFRAMES InpReliefTF2        = PERIOD_M1;    // Reliefni primky 2 - timeframe
input bool            InpReliefTF3Use     = true;         // Reliefni primky 3 - zapnout
input ENUM_TIMEFRAMES InpReliefTF3        = PERIOD_H1;    // Reliefni primky 3 - timeframe
input bool            InpReliefTF4Use     = true;         // Reliefni primky 4 - zapnout
input ENUM_TIMEFRAMES InpReliefTF4        = PERIOD_D1;    // Reliefni primky 4 - timeframe

//--- Urovne prurazu
input group "=== Urovne prurazu ==="
input bool            InpUseSwingLevels   = true;         // Prorazet jen swingove H1 svicky
input int             InpBreakSwingDepth  = 2;            // Sirka okna pro H1 swingy
input int             InpBreakLookback    = 300;          // Kolik H1 svicek prohledat

//--- Detekce kanalu
input group "=== Detekce kanalu ==="
input int             InpLookbackBars     = 1500;         // Kolik svicek analyzovat (v kazdem TF kanalu)
input int             InpSwingDepth       = 3;            // Sirka okna pro swingove body
input int             InpSwingScales      = 3;            // Pocet meritek (kanal v kanalu)
input int             InpMaxSwingGap      = 16;           // Max. odstup swingu A a C (pocet swingu)
input int             InpMinSpanBars      = 20;           // Minimalni delka kanalu A->C (bary)
input int             InpMaxAgeBars       = 300;          // Maximalni stari bodu C (bary)
input int             InpMinWidthPoints   = 300;          // Minimalni sirka kanalu (body)
input double          InpMinWidthATR      = 1.5;          // Minimalni sirka kanalu (nasobek ATR)
input int             InpATRPeriod        = 14;           // Perioda ATR pro filtr sirky
input int             InpMinTouches       = 1;            // Min. dotyku hran mimo opory A B C
input double          InpTouchTolFrac     = 0.15;         // Tolerance dotyku (zlomek sirky)
input double          InpMinContainment   = 0.85;         // Min. podil svicek uvnitr kanalu
input int             InpMaxChannels      = 4;            // Kolik hlavnich kanalu ponechat (v kazdem TF)
input double          InpPierceTolFrac    = 0.05;         // Povolene proriznuti hran (zlomek sirky)
input double          InpInvalidTolFrac   = 0.15;         // Prah invalidace kanalu (zlomek sirky)
input int             InpBackCheckBars    = 20;           // Kolik baru pred bodem A jeste kontrolovat
input int             InpAnchorWindow     = 5;            // Okno, ve kterem musi byt A a C extremem
input double          InpDedupFrac        = 0.15;         // Prah shody dvou kanalu (zlomek sirky)
input bool            InpRequireInside    = true;         // Vyzadovat cenu uvnitr kanalu

//--- Vstup a rizeni obchodu
input group "=== Vstup ==="
input bool            InpEnableTrading    = true;         // Povolit obchodovani (false = jen kresleni)
input ENUM_PUNTIKY_ENTRY InpEntryMode        = PUNTIKY_ENTRY_MANUAL;   // Rezim vstupu (vychozi: rucne tlacitky)
input int             InpMaxEntryPoints   = 300;          // Maximalni delka vstupu (body)
input int             InpMinEntryPoints   = 150;          // Minimalni delka vstupu (body)
input double          InpRiskReward       = 1.0;          // Pomer PT:SL (1 = 1:1, 2 = PT dvakrat dal nez SL)
input int             InpBreakoutBuffer   = 10;           // Buffer nad/pod urovni prurazu (body)
input int             InpMaxLevelOffset   = 30;           // Max. odstup trzniho vstupu od urovne (body)
input int             InpEdgeBuffer       = 20;           // Rezerva PT pred hranou kanalu (body)
input int             InpEdgeProjBars     = 12;           // Strop projekce hran dopredu (bary referencniho TF)
input double          InpInsideTolFrac    = 0.02;         // Tolerance testu "uvnitr kanalu"
input bool            InpAllowBuy         = true;         // Povolit nakupy
input bool            InpAllowSell        = true;         // Povolit prodeje
input int             InpMaxPositions     = 2;            // Max. soucasnych pozic strategie
input int             InpSlippage         = 20;           // Maximalni skluz (body)
input long            InpMagic            = 67205475;     // Magic number
input long            InpAllowedAccount   = 0;            // Povoleny ucet (0 = bez omezeni)

//--- Reliefni primky. Timeframy se zadavaji ve skupine
//--- "Timeframy reliefu", zde jsou uz jen prahy detekce - ty plati
//--- pro vsechny zapnute timeframy stejne.
input group "=== Reliefni primky ==="
input bool            InpUseRelief        = true;         // Hlidat reliefni primky (TF viz skupina vyse)
input ENUM_PUNTIKY_RELIEF InpReliefMode      = PUNTIKY_RELIEF_SHORTEN; // Co delat, kdyz primka vadi
input int             InpReliefLookback   = 7200;         // Kolik svicek analyzovat (v kazdem TF reliefu)
input int             InpReliefSwingDepth = 25;           // Sirka okna pro hlavni swingy
input int             InpReliefScales     = 4;            // Pocet meritek swingu (25/50/100/200)
input int             InpReliefSwingGap   = 20;           // Max. odstup opor (pocet swingu)
input int             InpReliefMinSpan    = 120;          // Minimalni delka primky (bary)
input int             InpReliefMinTouches = 0;            // Min. dotyku primky mimo jeji opory (0 = staci cista spojnice)
input int             InpReliefPierceTol  = 10;           // Proriznuti primky TELEM svicky (body)
input double          InpReliefPierceATR  = 0.15;         // Proriznuti primky TELEM svicky (nasobek ATR)
input int             InpReliefWickTol    = 150;          // Povoleny presah primky KNOTEM (body)
input double          InpReliefWickATR    = 1.00;         // Povoleny presah primky KNOTEM (nasobek ATR)
input int             InpReliefTouchTol   = 25;           // Tolerance dotyku primky (body)
input double          InpReliefTouchATR   = 0.35;         // Tolerance dotyku primky (nasobek ATR)
input int             InpReliefDedupTol   = 40;           // Prah shody dvou primek (body)
input double          InpReliefMaxAge     = 0.0;          // Platnost primky za 2. oporou (0 = neomezeno)
input int             InpReliefMaxDrift   = 3000;         // Max. vzdaleni primky od 2. opory (body)
input double          InpReliefMaxDriftATR = 4.0;         // Max. vzdaleni primky od 2. opory (nasobek ATR)
input int             InpReliefMaxDist    = 1500;         // Max. vzdalenost primky od CENY (body, 0 = bez omezeni)
input double          InpReliefMaxDistATR = 8.0;          // Max. vzdalenost primky od CENY (nasobek ATR)
input int             InpReliefMaxGap     = 2000;         // Max. prumerny odstup primky od ceny (body, 0 = bez omezeni)
input double          InpReliefMaxGapATR  = 5.0;          // Max. prumerny odstup primky od ceny (nasobek ATR)
input bool            InpReliefMidTouch   = false;        // Vyzadovat dotyk i uprostred primky
input int             InpReliefMidTol     = 60;           // Tolerance stredniho dotyku (body)
input double          InpReliefMidFrom    = 0.20;         // Stredni usek primky - od (0..1)
input double          InpReliefMidTo      = 0.80;         // Stredni usek primky - do (0..1)
input int             InpMaxReliefLines   = 15;           // Kolik primek ponechat (v kazdem TF)
input int             InpReliefBuffer     = 20;           // Rezerva pred primkou (body)
input int             InpReliefForwardBars = 120;         // Prodlouzeni primek doprava (bary)

//--- Rizeni objemu
input group "=== Objem ==="
input ENUM_PUNTIKY_LOT   InpLotMode          = PUNTIKY_LOT_RISK;  // Rezim vypoctu objemu (vychozi: dopocet z rizika)
input double          InpFixedLot         = 0.10;         // Pevny lot
input double          InpRiskPercent      = 1.0;          // Riziko na obchod (% uctu)

//--- Zobrazeni
input group "=== Zobrazeni ==="
input bool            InpShowChannels     = true;         // Kreslit kanaly
input bool            InpShowPoints       = true;         // Kreslit opory A B C D
input bool            InpShowBreakLevels  = true;         // Kreslit urovne prurazu H1
input bool            InpShowEntryLevels  = true;         // Kreslit urovne planovaneho vstupu
input bool            InpShowRelief       = true;         // Kreslit reliefni primky
input bool            InpShowPanel        = false;        // Zobrazit textovy panel (prepina tlacitko PANEL)
input int             InpForwardBars      = 30;           // Prodlouzeni kanalu doprava (bary)
input color           InpColorHigh        = clrTomato;    // Barva HIGH usecky
input color           InpColorLow         = clrDodgerBlue;// Barva LOW usecky
input color           InpColorPoint       = clrSilver;    // Barva popisku A B C D
input color           InpColorBreak       = clrGoldenrod; // Barva urovni prurazu
input color           InpColorRelief      = clrMediumOrchid; // Barva reliefnich primek
input color           InpColorEntry       = clrWhite;     // Barva urovne vstupu
input color           InpColorSL          = clrOrangeRed; // Barva SL
input color           InpColorTP          = clrLimeGreen; // Barva PT
input color           InpColorPanel       = clrWhite;     // Barva textu panelu
input int             InpPanelX           = 12;           // Panel - odsazeni X
input int             InpPanelY           = 22;           // Panel - odsazeni Y
input int             InpPanelFontSize    = 9;            // Panel - velikost pisma
input int             InpPanelLineHeight  = 20;           // Panel - vyska radku (0 = podle pisma)
input int             InpPanelOneClickShift = 130;        // Posun panelu pod SELL/BUY okno MT5
input int             InpPointFontSize    = 10;           // Velikost pisma popisku opor
input double          InpLabelMergeATR    = 0.5;          // Slouceni blizkych popisku (nasobek ATR)

//--- Upozorneni na priblizeni k urovni vstupu (zarovky Philips Hue)
input group "=== Upozorneni Hue ==="
input bool            InpHueEnabled       = true;          // Blikat zarovkou pri priblizeni k urovni vstupu
input string          InpHueUrl           = "http://192.168.0.157:8082/hue"; // URL sluzby Hue (vcetne portu)
input int             InpHueNearPoints    = 500;           // Vzdalenost od urovne vstupu pro upozorneni (body)
input double          InpHueResetFactor   = 1.50;          // Hystereze - pamet se uvolni az za N-nasobkem prahu
input int             InpHueRepeatMinutes = 0;             // Opakovat upozorneni po N minutach (0 = jen jednou)
input int             InpHueTimeout       = 1000;          // Timeout HTTP pozadavku (ms)
input bool            InpHueTestButton    = true;          // Zobrazit tlacitko pro test upozorneni
input bool            InpHueOnEntry       = false;         // Bliknout 1x pri vstupu do pozice (jen AUTO rezim)

//--- Diagnostika a ladeni
input group "=== Diagnostika ==="
input bool            InpDiagnostics      = true;         // Vypisovat diagnostiku detekce do logu
input bool            InpShotOnRequest    = true;         // Ulozit snimek grafu na vyzadani
input int             InpShotEveryBars    = 0;            // Snimek kazdych N baru TF kanalu (0 = ne)
input string          InpShotFileName     = "PuntikyShot.png";      // Soubor snimku (MQL5/Files)
input string          InpShotRequestFile  = "PuntikyShot.request";  // Soubor pozadavku o snimek

//--- Pojmenovane konstanty misto magickych cisel v kodu
#define PUNTIKY_MIN_BARS        50    // minimum svicek pro smysluplnou detekci
#define PUNTIKY_PANEL_MAX_LINES 40    // kapacita panelu (radku)
#define PUNTIKY_PANEL_RESERVE   14    // radky drzene pro vypis pod kanaly
#define PUNTIKY_PANEL_BTN_GAP   6     // mezera mezi tlacitky a panelem (px)

// Sirka tlacitka se pocita ze skutecne sirky nejdelsiho textu, ktery se
// v nem muze objevit (viz ButtonWidth). Pevne hodnoty v pixelech tuhle
// praci nezvladly: MT5 skaluje pismo grafickych objektu podle rozliseni
// obrazovky, takze stejne cislo jednou textu nechalo misto navic a
// podruhe useklo "TEST Hue" na "EST Hue".
#define PUNTIKY_BTN_TEXT_PAD    24    // volne misto kolem textu tlacitka (px)

// Nouzove sirky pro pripad, ze mereni textu selze. Odpovidaji pismu o
// velikosti 9 na bezne obrazovce (~13 px na znak).
#define PUNTIKY_BTN_HUE_W       130   // sirka tlacitka testu Hue (px)
#define PUNTIKY_BTN_PANEL_W     145   // sirka tlacitka prepinace panelu (px)
#define PUNTIKY_BTN_AUTO_W      140   // sirka tlacitka automatickeho rezimu (px)
#define PUNTIKY_BTN_AUTO2_W     175   // sirka tlacitka dvojiteho automatu (px)
#define PUNTIKY_BTN_TRADE_W     226   // sirka obchodnich tlacitek (px)

// Nejdelsi text, ktery se v obchodnim tlacitku muze objevit. Sirku z nej
// dostanou vsechna ctyri, aby tlacitka 2x sedela presne pod svymi
// protejsky a rada nevypadala rozhozene.
#define PUNTIKY_BTN_TRADE_MAX   "ZAVŘÍT SHORT 2x"

// Pozadi tlacitek. Kazdy stav ma vlastni barvu, aby slo od pohledu poznat,
// co je funkcni a co ne - tmava sed je vyhrazena jedine nedostupnemu
// tlacitku, takze zadne aktivni tlacitko ji nesmi mit.
#define PUNTIKY_BTN_BG_HUE      C'30,70,120'   // test Hue (funkcni vzdy)
#define PUNTIKY_BTN_BG_LONG     C'0,90,0'      // zadat LONG
#define PUNTIKY_BTN_BG_SHORT    C'130,0,0'     // zadat SHORT
#define PUNTIKY_BTN_BG_REMOVE   C'150,90,0'    // zrusit prikaz / zavrit pozici
#define PUNTIKY_BTN_BG_OFF      C'48,48,48'    // navrh neni platny, klik nic neudela
#define PUNTIKY_BTN_BG_PANEL_ON  C'85,60,115'  // panel v grafu zapnuty
#define PUNTIKY_BTN_BG_PANEL_OFF C'55,40,75'   // panel v grafu vypnuty
// Automaticky rezim ma vlastni, vyrazne odlisnou barvu - zapnuty
// znamena, ze expert obchoduje sam, a to musi byt videt na prvni pohled
#define PUNTIKY_BTN_BG_AUTO_ON   C'0,120,60'   // expert obchoduje sam
#define PUNTIKY_BTN_BG_AUTO_OFF  C'35,60,45'   // automaticky rezim vypnuty

// Parametry dvojiteho vstupu (tlacitka LONG 2x / SHORT 2x).
// Prvni obchod ma PT presne podle navrhu (RRR 1:1), druhy ho ma na
// nasobku teto delky; SL maji oba stejny. Riziko se mezi ne deli, takze
// soucet obou obchodu odpovida riziku jednoho bezneho obchodu.
#define PUNTIKY_DOUBLE_PT_MULT  2.0   // nasobek delky PT pro druhy obchod
#define PUNTIKY_DOUBLE_RISK     0.5   // podil rizika pripadajici na jeden obchod

// Kolik prikazu smi v automatickem rezimu lezet na JEDNOM smeru.
// Bezny automat drzi jednu nohu, dvojity dve (PT 1:1 a PT na nasobku).
#define PUNTIKY_MAX_LEGS        2

// Znacka v komentari prikazu, podle ktere se pozna obchod z dvojiteho
// vstupu. Cely komentar se vejde do limitu MT5 (31 znaku).
// Podle ni se rozhoduje, ktere tlacitko obchod odebira - dvojity vstup
// se rusi tlacitkem 2x, jednoduchy tlacitkem LONG / SHORT.
#define PUNTIKY_DOUBLE_TAG      "2x"

// Kdyz broker komentar prepise, rozhodne geometrie: druha noha
// dvojiteho vstupu ma PT vyrazne delsi nez SL, coz jednoduchy obchod
// s RRR 1:1 nikdy nema. Prah je s rezervou pod skutecnym nasobkem.
#define PUNTIKY_DOUBLE_TP_RATIO 1.5

// MT5 zobrazi z textu grafickeho objektu jen prvnich 63 znaku a zbytek
// tise zahodi (i uprostred slova). Delsi radky panelu se proto zalomi.
#define PUNTIKY_PANEL_MAX_CHARS 63
#define PUNTIKY_PANEL_INDENT    "     "   // odsazeni pokracovaciho radku

// Jak dlouho zustane posledni udalost viset pod tlacitky, kdyz je panel
// vypnuty. Se zapnutym panelem se nemaze - tam ma vlastni radek
// "poslední:" a jeho zmizeni by z panelu udelalo blikajici plochu.
#define PUNTIKY_EVENT_FLASH_SEC 10
// Kolik radku smi hlaska zabrat (delsi duvody zamitnuti se zalomi)
#define PUNTIKY_EVENT_MAX_LINES 4

// Referencni spread pro testy urovni prurazu. Zivy spread se pri
// rolloveru nafoukne i desetinasobne a takova spicka se nesmi dostat
// do prepoctu bidu na exekucni cenu: "prorazila" by naraz vsechny
// historicke swingy (uroven prurazu by odskocila na davno neplatny)
// a zaklapla priznak "prorazeno", aniz by se cena k urovni priblizila.
// Proto se pouziva median poslednich vzorku, ne okamzita hodnota.
#define PUNTIKY_SPREAD_SAMPLES  32    // kolik vzorku spreadu se drzi
#define PUNTIKY_SPREAD_PERIOD   60    // odstup dvou vzorku (sekundy)

// Jak casto se reliefni primky pocitaji cele znovu (v barech TF
// vstupu). Plny prepocet overuje kazdeho kandidata pres celou
// historii, tedy radove miliony pruchodu bary - kazdou minutu je to
// zbytecne, hlavni swingy se tak rychle nemeni. Mezi prepocty se
// drzene primky jen kontroluji proti nove uzavrene svicce.
#define PUNTIKY_RELIEF_REBUILD_BARS 15
#define PUNTIKY_LABEL_FALLBACK  10.0  // nahradni tolerance slouceni popisku (body)
#define PUNTIKY_VOLUME_EPS      1e-8  // tolerance porovnani objemu
#define PUNTIKY_LOTSTEP_EPS     1e-9  // tolerance deleni objemu krokem

//--- Globalni stav
CTrade        g_trade;                 // obchodni rozhrani
SReliefLine   g_relief[];              // reliefni primky vsech zapnutych TF
SChannel      g_channels[];            // vybrane hlavni kanaly vsech zapnutych TF
int           g_atrHandle = INVALID_HANDLE;
double        g_atr       = 0.0;       // ATR referencniho TF, cte se jednou za prepocet

//--- ATR KAZDEHO zapnuteho TF reliefu. Tolerance primek se odvozuji od
//--- volatility timeframu, na kterem primka vznikla, ne od referencniho
//--- TF kanalu: rozpeti svicky D1 je o rady jinde nez u M1, takze jedno
//--- spolecne ATR by na dlouhych timeframech drzelo tolerance neunosne
//--- tesne a primky by tam nevznikly vubec.
int           g_relAtrHandle[PUNTIKY_TF_SLOTS];
double        g_relAtr[PUNTIKY_TF_SLOTS];
bool          g_relAtrWarned[PUNTIKY_TF_SLOTS];  // hlaska o cekani na ATR jen jednou

//--- Zapnute timeframy detekce. Vstupy se za behu nemeni, takze se
//--- seznamy sestavi jednou v ResolveTFSlots: vypnute sloty vypadnou a
//--- dvakrat zadany tentyz timeframe se zapocita jen jednou (jinak by
//--- vznikly dve sady totoznych kanalu pres sebe). Index do techto
//--- poli je tfIdx, ktery si nese kazdy kanal i kazda primka.
ENUM_TIMEFRAMES g_chTF[PUNTIKY_TF_SLOTS];
int             g_chTFCount  = 0;
ENUM_TIMEFRAMES g_relTF[PUNTIKY_TF_SLOTS];
int             g_relTFCount = 0;

//--- Referencni timeframe: prvni zapnuty TF kanalu. Cte se z nej ATR
//--- (filtr sirky kanalu, prah driftu reliefu, slucovani popisku) a v
//--- jeho barech je zadany InpEdgeProjBars.
ENUM_TIMEFRAMES g_refTF = PERIOD_M15;

//--- Statistika detekce zvlast za kazdy zapnuty timeframe. Jedno
//--- souhrnne cislo by zakrylo prave to podstatne, tedy ze kandidaty
//--- zahazuje jiny prah na M1 a jiny na H1; navic se timeframy
//--- prepocitavaji nezavisle, takze by soucet michal cerstve cislo
//--- jednoho se starym cislem druheho.
SChannelStats g_stats[PUNTIKY_TF_SLOTS];
SReliefStats  g_reliefStats[PUNTIKY_TF_SLOTS];

//--- Parametry modulu se plni jednou v OnInit - jsou to same nemenne
//--- vstupy a prepocet bodu na cenu nema smysl delat na kazdem baru
SChannelParams g_chParams;
SReliefParams  g_reliefParams;
double         g_breakBuffer    = 0.0; // InpBreakoutBuffer v cene
double         g_maxLevelOffset = 0.0; // InpMaxLevelOffset v cene

datetime      g_lastChannelBar[PUNTIKY_TF_SLOTS];  // posledni zpracovany bar kazdeho TF kanalu
datetime      g_lastBreakoutBar = 0;   // cas posledniho zpracovaneho baru TF prurazu
datetime      g_lastEntryBar    = 0;   // cas posledniho zpracovaneho baru TF vstupu
int           g_barsSinceShot   = 0;   // pocitadlo baru pro periodicky snimek

//--- Stav obou smeru prurazu: uroven, jeji cas, nabito / obchodovano /
//--- prorazeno a pamet upozorneni Hue. Index urcuje DirIdx, takze kod
//--- obou smeru je tentyz (viz hlavicka SDirection).
SDirection    g_dir[2];

//--- Index smeru v polich stavu a navrhu (0 = BUY, 1 = SELL)
#define PUNTIKY_DIR_BUY   0
#define PUNTIKY_DIR_SELL  1
int DirIdx(const bool isBuy) { return(isBuy ? PUNTIKY_DIR_BUY : PUNTIKY_DIR_SELL); }

//+------------------------------------------------------------------+
//| Lezici pending prikaz strategie tak, jak ho vidi rekonciliace.   |
//| Drzet ho ve strukture misto v peti paralelnich polich ma jediny  |
//| duvod: pri dvou noha na smer uz by se indexy do peti poli musely |
//| trefovat rucne na kazdem miste.                                  |
//+------------------------------------------------------------------+
struct SPendingOrder
  {
   ulong             ticket;
   double            price;
   double            sl;
   double            tp;
   double            volume;
  };

//--- Kolik prikazu ma v aktualnim rezimu lezet na jednom smeru
int AutoLegCount()
  {
   return(g_autoDouble ? 2 : 1);
  }

//+------------------------------------------------------------------+
//| Rezim vstupu platny PRAVE TED.                                   |
//| Vstup InpEntryMode urcuje jen vychozi stav - tlacitko AUTO ho za |
//| behu prepina do rezimu pending prikazu, ve kterem expert          |
//| obchoduje sam. Vsechna rozhodnuti o rezimu proto musi chodit sem, |
//| ne primo na vstup; jinak by cast kodu jela podle tlacitka a cast  |
//| podle nastaveni.                                                  |
//+------------------------------------------------------------------+
ENUM_PUNTIKY_ENTRY EntryMode()
  {
   return(g_autoMode ? PUNTIKY_ENTRY_PENDING : InpEntryMode);
  }

//--- Odlozena vymena spotrebovane urovne za dalsi swing. V rezimu
//--- M1_CLOSE se nesmi provest uvnitr svicky vstupniho TF: vstup se
//--- potvrzuje az jejim uzavrenim a meri se proti urovni, kterou
//--- svicka skutecne prorazila (viz OnTick).
bool          g_breakSwapPending = false;
datetime      g_breakSwapBar     = 0;  // bar vstupniho TF, ve kterem pruraz nastal

SEntryPlan    g_plan[2];               // aktualni navrhy obou smeru
string        g_lastEvent = "";        // posledni udalost pro panel
// Kdy udalost vznikla a kolik radku hlasky je prave vykresleno pod
// tlacitky. Cas se bere z GetTickCount64, ne ze serveroveho casu: ten
// se na klidnem trhu nehne a hlaska by viselo dokud neprijde tick.
// Hlaska pod tlacitky nese JEN to, co uzivateli zabranilo zadat pokyn -
// potvrzeni ("AUTO režim ZAPNUT", "panel vypnut", vyplneny prikaz) by
// pri vypnutem panelu jen prekryvala graf. Text se proto drzi zvlast od
// g_lastEvent, ktery panel vypisuje na radku "poslední:" vzdy.
string        g_flashText      = "";
ulong         g_flashTick      = 0;
int           g_eventShown     = 0;
bool          g_tradingAllowed = true; // vysledek kontroly uctu
bool          g_showPanel     = false;// kreslit textovy panel pod tlacitky
                                      // (prepina se tlacitkem PANEL v grafu)
// Automaticky rezim: expert obchoduje sam pres pending STOP prikazy na
// obou urovnich prurazu. Prepina se tlacitkem AUTO v grafu, takze to
// nemuze byt vstup - ten se za behu nemeni (viz EntryMode).
// Zamerne se nikam neuklada: po restartu terminalu se expert vraci do
// rezimu podle InpEntryMode a sam od sebe obchodovat nezacne.
bool          g_autoMode      = false;
// Dvojity automat: kazdy vstup se zada jako DVE nohy s polovicnim
// objemem - prvni s PT podle navrhu (RRR 1:1), druha s PT na nasobku
// delky vstupu. Totez, co delaji tlacitka LONG 2x / SHORT 2x, jen
// automaticky a pres pending prikazy.
bool          g_autoDouble    = false;
bool          g_ordersDirty    = false;// navrhy se zmenily, prikazy je treba srovnat
bool          g_needInitCalc   = true; // ceka se na data pro prvni vypocet

//--- Uklid pending prikazu po prepnuti do rezimu M1_CLOSE. Pri startu
//--- muze byt obchodovani vypnute (AutoTrading, jiny ucet), a protoze
//--- jeho zapnuti zadny OnInit nevyvola, uklid se opakuje z timeru,
//--- dokud neprojde - jinak by na urovni zustal lezet prikaz, ktery uz
//--- zadny rezim neridi, a jeho plneni by pridalo druhou pozici.
bool          g_cleanupOrders = false;
bool          g_cleanupWarned = false; // varovani do logu jen jednou

//--- Stav panelu - kolik radku je vykresleno a na jake vysce zacina
//--- prvni radek textu (tedy uz pod radkem tlacitek)
int           g_panelShown = 0;
int           g_panelY     = -1;

//--- Rozmery tlacitek a rezim uctu se za behu nemeni, ale merily se
//--- pri kazdem obnoveni panelu, tedy kazdou sekundu - a mereni textu
//--- (TextSetFont + TextGetSize) je z celeho panelu nejdrazsi operace.
//--- Spocitaji se jednou v InitPanelMetrics.
int           g_btnHeight  = 0;
int           g_btnHueW    = 0;
int           g_btnPanelW  = 0;
int           g_btnAutoW   = 0;
int           g_btnAuto2W  = 0;
// Spodni hrana rady tlacitek z posledniho vykresleni - viz DrawPanelButtons
int           g_btnBottomY = 0;
int           g_btnTradeW  = 0;
bool          g_accountHedging = false;

//--- Tlacitka, ktera se mimo rucni rezim nekresli, staci smazat jednou
bool          g_tradeBtnCleared = false;

//--- Referencni bar posledni detekce. Kanaly i reliefni primky jsou
//--- vedene v indexech pole, ze ktereho vznikly; aby sly vyhodnotit i
//--- pozdeji (panel bezi kazdou sekundu, navrhy kazdou minutu), drzi se
//--- cas a index posledniho analyzovaneho baru a aktualni index se z
//--- nej dopocita.
//--- Vse je vedeno po slotech (index = tfIdx), protoze kazdy timeframe
//--- ma vlastni casovou osu i vlastni cyklus prepoctu.
datetime      g_channelRefTime[PUNTIKY_TF_SLOTS];  // cas posledniho baru detekce kanalu
int           g_channelRefIdx[PUNTIKY_TF_SLOTS];   // jeho index v analyzovanem poli
datetime      g_reliefRefTime[PUNTIKY_TF_SLOTS];   // totez pro reliefni primky
int           g_reliefRefIdx[PUNTIKY_TF_SLOTS];
int           g_reliefBarsSinceBuild[PUNTIKY_TF_SLOTS];  // baru od posledniho plneho prepoctu
datetime      g_reliefCheckedBar[PUNTIKY_TF_SLOTS];      // posledni prekontrolovana uzavrena svicka

//--- Posledni spolehlive spocteny index prave otevreneho baru pro obe
//--- geometrie. Kdyz rada jeste neni synchronizovana (po startu nebo
//--- reconnectu), vrati se posledni znama hodnota - dopocet z
//--- nastenneho casu by pres vikend pricetl tisice neexistujicich baru
//--- (viz BarIndexNow).
datetime      g_channelBarCacheRef[PUNTIKY_TF_SLOTS];
double        g_channelBarCache[PUNTIKY_TF_SLOTS];
datetime      g_reliefBarCacheRef[PUNTIKY_TF_SLOTS];
double        g_reliefBarCache[PUNTIKY_TF_SLOTS];

//--- Vzorky spreadu pro ReferenceSpread (kruhovy buffer + jejich median)
double        g_spreadSamples[PUNTIKY_SPREAD_SAMPLES];
int           g_spreadCount = 0;       // kolik vzorku uz je nasbirano
int           g_spreadNext  = 0;       // kam se zapise dalsi vzorek
datetime      g_spreadTime  = 0;       // cas posledniho odberu
double        g_spreadRef   = 0.0;     // median vzorku (0 = jeste zadny)
bool          g_spreadPrimed = false;  // vzorky uz naplneny z historickych svicek

//+------------------------------------------------------------------+
//| Ohlasi udalost do panelu i do Expert logu.                       |
//| Obe cesty musi nest totez: panel jde tlacitkem schovat a log je  |
//| pak jedine misto, kde se uzivatel dozvi, proc obchod nevznikl.   |
//| Drive to byla dvojice prikazu opsana na osmnacti mistech a na    |
//| trech z nich se na vypis do logu zapomnelo.                     |
//|  text     - text udalosti (bez prefixu strategie)                |
//|  blocking - udalost zabranila zadat pokyn; jen takova se pri     |
//|             vypnutem panelu vypise i pod tlacitka                |
//+------------------------------------------------------------------+
void ReportEvent(const string text, const bool blocking = false)
  {
   g_lastEvent = text;
   Print("PUNTIKY: ", text);

   if(!blocking)
      return;

   g_flashText = text;
   g_flashTick = GetTickCount64();

   // Pri vypnutem panelu je hlaska pod tlacitky jedine misto, kde se
   // uzivatel dozvi, proc klik nic neudelal - vykresli se hned, ne az
   // za sekundu z timeru
   if(!g_showPanel)
     {
      DrawEventFlash();
      ChartRedraw();
     }
  }

//+------------------------------------------------------------------+
//| Prepne zobrazeni textoveho panelu v grafu a zmenu ohlasi.        |
//| Tyka se jen vypisu na obrazovce - Expert log bezi dal beze zmeny,|
//| takze je se kam podivat i pri schovanem panelu.                  |
//| Pri vypnuti se cely panel maze, takze se po opetovnem zapnuti    |
//| stejne vykresli od nuly (radky se porovnavaji s tim, co je       |
//| skutecne v grafu) - poslednou vysku prvniho radku neni treba      |
//| zapominat.                                                       |
//+------------------------------------------------------------------+
void TogglePanel()
  {
   g_showPanel = !g_showPanel;
   ReportEvent(g_showPanel ? "panel v grafu zapnut" : "panel v grafu vypnut");
  }

//+------------------------------------------------------------------+
//| Prepnuti automatickeho rezimu tlacitkem AUTO.                    |
//|                                                                  |
//| Zapnuty rezim znamena pending STOP prikazy na obou urovnich       |
//| prurazu - expert je sam zada, sam upravuje pri posunu urovni a po |
//| uzavreni obchodu sam zada dalsi. Zapnuti se proto odmita, dokud   |
//| expert na ucet nesmi: prazdny rezim, ktery nic nezada, by budil   |
//| dojem, ze strategie bezi.                                         |
//| Pri vypnuti se lezici prikazy RUSI. Rezim, do ktereho se expert   |
//| vraci (typicky rucni), je totiz uz nespravuje a zapomenuty GTC    |
//| prikaz by se vyplnil do pozice, kterou nikdo nehlida.             |
//+------------------------------------------------------------------+
void ToggleAutoMode()
  {
   // Dvojity automat patri svemu tlacitku - stejne jako dvojity vstup
   // neodebira tlacitko LONG, ale LONG 2x. Bez teto pojistky by klik na
   // (zesedle) tlacitko vypnul rezim, ktery nezapnul.
   if(g_autoMode && g_autoDouble)
     {
      ReportEvent("běží dvojitý automat - vypni ho tlačítkem AUTO VYP 2x", true);
      return;
     }

   if(!g_autoMode)
     {
      const string blocked = TradingDisabledReason();
      if(blocked != "")
        {
         ReportEvent("AUTO režim - " + blocked, true);
         return;
        }

      g_autoMode   = true;
      g_autoDouble = false;
      ReportEvent("AUTO režim ZAPNUT - expert obchoduje sám "
                  "(upozornění Hue jsou potlačená)");

      // Prikazy se zadaji hned, ne az s dalsim barem
      RebuildPlans();
      SyncPendingOrders();
      UpdatePanel();
      ChartRedraw();
      return;
     }

   StopAutoMode("AUTO režim");
  }

//+------------------------------------------------------------------+
//| Prepnuti dvojiteho automatickeho rezimu tlacitkem AUTO 2x.       |
//|                                                                  |
//| Kazdy vstup se zada jako dve nohy s polovicnim objemem - prvni    |
//| s PT podle navrhu, druha s PT na nasobku delky vstupu (totez, co  |
//| delaji tlacitka LONG 2x / SHORT 2x, jen automaticky).            |
//| Dve podminky navic proti beznemu automatu:                       |
//|  - hedgovaci ucet: netting by obe nohy sloucil do jedine pozice   |
//|    a z dvojiteho vstupu by se tise stal jeden obchod se spatnym PT|
//|  - InpMaxPositions >= 2: pri limitu jedne pozice by po vyplneni    |
//|    prvni nohy prestal navrh platit a rekonciliace by druhou nohu  |
//|    zrusila drive, nez by se vyplnila                              |
//+------------------------------------------------------------------+
void ToggleAutoDouble()
  {
   // Zrcadlove k ToggleAutoMode: bezny automat toto tlacitko nevypina
   if(g_autoMode && !g_autoDouble)
     {
      ReportEvent("běží běžný automat - vypni ho tlačítkem AUTO VYP", true);
      return;
     }

   if(!g_autoMode)
     {
      const string blocked = TradingDisabledReason();
      if(blocked != "")
        {
         ReportEvent("AUTO 2x - " + blocked, true);
         return;
        }
      if(!AccountIsHedging())
        {
         ReportEvent("AUTO 2x nelze zapnout - účet není hedgovací", true);
         return;
        }
      if(InpMaxPositions < 2)
        {
         ReportEvent("AUTO 2x nelze zapnout - InpMaxPositions musí být aspoň 2", true);
         return;
        }

      g_autoMode   = true;
      g_autoDouble = true;
      ReportEvent("AUTO 2x ZAPNUT - expert obchoduje sám, dvojitý vstup "
                  "(upozornění Hue jsou potlačená)");

      RebuildPlans();
      SyncPendingOrders();
      UpdatePanel();
      ChartRedraw();
      return;
     }

   StopAutoMode("AUTO 2x");
  }

//+------------------------------------------------------------------+
//| Spolecne vypnuti automatickeho rezimu.                           |
//| Lezici prikazy se RUSI: rezim, do ktereho se expert vraci        |
//| (typicky rucni), je uz nespravuje a zapomenuty GTC prikaz by se  |
//| vyplnil do pozice, kterou nikdo nehlida.                          |
//|  label - jmeno rezimu do hlasky                                   |
//+------------------------------------------------------------------+
void StopAutoMode(const string label)
  {
   g_autoMode   = false;
   g_autoDouble = false;

   const int left = CountOrders();
   if(left > 0 && CancelPendingOrders())
      ReportEvent(StringFormat("%s VYPNUT - %d ležící příkaz(ů) zrušen(o)", label, left));
   else
      ReportEvent(label + " VYPNUT");

   RebuildPlans();
   UpdatePanel();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Inicializace experta                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Seznamy zapnutych timeframu musi byt hotove jako prvni: cte je
   //--- uz kontrola vstupu i vyber timeframu pro ATR
   ResolveTFSlots();

   //--- Nesmyslne zadany vstup se ma projevit hlaskou pri startu, ne
   //--- tichym nefunkcnim chovanim za behu
   if(!ValidateInputs())
      return(INIT_PARAMETERS_INCORRECT);

   // Vstup urcuje jen POCATECNI stav panelu - za behu ho prepina
   // tlacitko PANEL v grafu
   g_showPanel = InpShowPanel;

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);

   //--- Pojistka proti spusteni na jinem nez povolenem uctu
   g_tradingAllowed = true;
   if(InpAllowedAccount != 0 && AccountInfoInteger(ACCOUNT_LOGIN) != InpAllowedAccount)
     {
      g_tradingAllowed = false;
      Print("PUNTIKY: účet ", AccountInfoInteger(ACCOUNT_LOGIN),
            " neodpovídá povolenému účtu ", InpAllowedAccount, " - obchodování vypnuto.");
     }

   //--- ATR na referencnim TF (prvni zapnuty TF kanalu) slouzi jako
   //--- filtr minimalni sirky kanalu, prah driftu reliefu i tolerance
   //--- slucovani popisku. Je jedno spolecne pro vsechny timeframy -
   //--- kdyby si kazdy nesl vlastni, filtry by se mezi nimi rozesly a
   //--- stejne zadani by v kazdem timeframu znamenalo neco jineho.
   g_atrHandle = iATR(_Symbol, g_refTF, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("PUNTIKY: nepodařilo se vytvořit ATR handle.");
      return(INIT_FAILED);
     }

   //--- Vlastni ATR pro kazdy zapnuty TF reliefu (viz g_relAtr)
   for(int s = 0; s < PUNTIKY_TF_SLOTS; s++)
     {
      g_relAtrHandle[s] = INVALID_HANDLE;
      g_relAtr[s]       = 0.0;
      g_relAtrWarned[s] = false;
     }
   if(InpUseRelief)
      for(int s = 0; s < g_relTFCount; s++)
        {
         g_relAtrHandle[s] = iATR(_Symbol, g_relTF[s], InpATRPeriod);
         if(g_relAtrHandle[s] == INVALID_HANDLE)
           {
            PrintFormat("PUNTIKY: nepodařilo se vytvořit ATR handle pro reliéf %s.",
                        TFText(g_relTF[s]));
            return(INIT_FAILED);
           }
        }
   PrintFormat("PUNTIKY: kanály %s | reliéf %s | ATR a projekce z %s",
               TFListText(g_chTF, g_chTFCount),
               InpUseRelief ? TFListText(g_relTF, g_relTFCount) : "vypnuto",
               TFText(g_refTF));

   InitParams();
   InitPanelMetrics();      // rozmery tlacitek a rezim uctu se za behu nemeni
   PrimeSpreadSamples();    // referencni spread z historie, ne z jedineho vzorku
   for(int i = 0; i < 2; i++)
     {
      g_dir[i].Reset();
      ResetPlan(g_plan[i], i == PUNTIKY_DIR_BUY);
     }

   PrintPointDiagnostics();

   EventSetTimer(1);

   // Bez povoleni adresy v nastaveni terminalu skonci WebRequest chybou 4014,
   // proto se URL vypise hned pri startu
   if(InpHueEnabled)
      PrintFormat("PUNTIKY: upozornění Hue zapnuto - %d b od úrovně vstupu, paměť se "
                  "uvolní za %.0f b, %s (adresu povol v Nástroje > Možnosti > "
                  "Strategie > Povolit WebRequest)",
                  InpHueNearPoints, InpHueNearPoints * InpHueResetFactor, InpHueUrl);

   if(EntryMode() == PUNTIKY_ENTRY_MANUAL)
      Print("PUNTIKY: ruční režim - expert sám neobchoduje, obchody se zadávají "
            "tlačítky LONG / SHORT (a LONG 2x / SHORT 2x) v grafu.");

   // Po prepnuti z pending rezimu by na urovnich zustaly lezet GTC
   // prikazy se starym SL/PT - jejich plneni by otevrelo pozici, kterou
   // uz zadny rezim neridi. V rucnim rezimu se prikazy naopak nechavaji
   // byt: zadal je uzivatel tlacitkem a nesou vlastni SL i PT, takze mu
   // rekompilace ani zmena parametru nesmi obchod zrusit.
   // Kdyz je obchodovani prave vypnute, uklid se odlozi a opakuje z
   // timeru - zapnuti AutoTradingu uz zadny OnInit nevyvola.
   if(EntryMode() == PUNTIKY_ENTRY_M1_CLOSE)
     {
      g_cleanupOrders = true;
      TryCleanupOrders();
     }

   //--- Prvni vypocet hned pri startu, aby byl graf ihned popsany.
   //--- Kdyz jeste nejsou data indikatoru, odlozi se na prvni tick.
   g_needInitCalc = true;
   if(!TryInitialCalc())
      Print("PUNTIKY: čeká se na dopočet ATR, první výpočet proběhne s prvními daty.");

   UpdatePanel();
   ChartRedraw();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Ma se pri ukonceni s timto duvodem uklidit lezici pending prikaz?|
//| Expert se sam od sebe vraci jen pri rekompilaci, zmene parametru,|
//| ukonceni terminalu, neuspesne inicializaci (zustava na grafu a   |
//| ceka na opravu vstupu) a pri zmene uctu, kde uz na prikazy       |
//| stareho uctu stejne nedosahne. Tam se prikazy nechavaji byt a    |
//| srovna je nasledny OnInit.                                       |
//| Ve vsech ostatnich pripadech - odebrani z grafu, zavreni grafu,  |
//| nova sablona, zmena symbolu, ExpertRemove - uz zadny OnInit      |
//| neprijde a GTC prikaz by na trhu zustal bez dozoru: jeho plneni  |
//| by otevrelo pozici, kterou nikdo neridi.                         |
//| Zmenu periody sice expert prezije, jenze ji pri deinitu nelze od |
//| zmeny symbolu odlisit (obe hlasi REASON_CHARTCHANGE). Zruseny    |
//| prikaz zada nasledny OnInit v pending rezimu stejne hned znovu,  |
//| kdezto prikaz zapomenuty na jinem symbolu uz nezrusi nikdo.      |
//|  reason - duvod ukonceni (viz REASON_*)                          |
//+------------------------------------------------------------------+
bool DeinitShouldCancel(const int reason)
  {
   return(reason != REASON_RECOMPILE &&
          reason != REASON_PARAMETERS &&
          reason != REASON_CLOSE &&
          reason != REASON_INITFAILED &&
          reason != REASON_ACCOUNT);
  }

//+------------------------------------------------------------------+
//| Deinicializace - uklid vlastnich objektu a handlu.               |
//|  reason - duvod ukonceni (viz REASON_*)                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   for(int s = 0; s < PUNTIKY_TF_SLOTS; s++)
      if(g_relAtrHandle[s] != INVALID_HANDLE)
         IndicatorRelease(g_relAtrHandle[s]);

   if(DeinitShouldCancel(reason))
     {
      const int left = CountOrders();
      if(left > 0)
        {
         // V rucnim rezimu prikaz vedome zadal uzivatel a nese vlastni
         // SL i PT - ten se nerusi, jen se do logu napise, co na trhu
         // zustava. Totez pri vypnutem obchodovani, kde by OrderDelete
         // stejne skoncil chybou - at je aspon videt, ze prikazy na
         // trhu zustavaji bez dozoru.
         if(EntryMode() == PUNTIKY_ENTRY_MANUAL)
            PrintFormat("PUNTIKY: ruční režim - na trhu zůstává %d příkaz(ů) "
                        "zadaných tlačítkem.", left);
         else
            if(!TradingEnabled())
               PrintFormat("PUNTIKY: %s - na trhu zůstává %d příkaz(ů) bez dozoru "
                           "experta.", TradingDisabledReason(), left);
            else
               CancelPendingOrders();
        }
     }

   PuntikyDeleteObjects();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Hlavni smycka - reaguje na kazdy tick                            |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- Vzorek spreadu se bere jeste pred jakymkoli testem urovni -
   //--- vsechny prepocty bidu na exekucni cenu z nej vychazeji
   SampleSpread();

   //--- Dokud nejsou data pro prvni vypocet, nema smysl pokracovat
   if(g_needInitCalc && !TryInitialCalc())
      return;

   //--- Nove bary se zjistuji najednou na zacatku: vyhodnoceni vstupu
   //--- musi probehnout jeste nad urovnemi platnymi v okamziku
   //--- uzavreni svicky vstupniho TF (viz krok 2)
   //--- Kanaly se prepocitavaji po timeframech: novy bar M15 nesmi
   //--- spustit prepocet H4, ktery se stejne meni o rad pomaleji
   bool newChannelSlot[];
   ArrayResize(newChannelSlot, g_chTFCount);
   bool newChannelBar = false;
   for(int s = 0; s < g_chTFCount; s++)
     {
      newChannelSlot[s] = IsNewBar(g_chTF[s], g_lastChannelBar[s]);
      if(newChannelSlot[s])
         newChannelBar = true;
     }

   const bool newBreakoutBar = IsNewBar(InpBreakoutTF, g_lastBreakoutBar);
   const bool newEntryBar    = IsNewBar(InpEntryTF,    g_lastEntryBar);

   //--- Reliefni primky maji vlastni timeframy, takze se nove bary
   //--- hledaji zvlast a s TF vstupu uz nesouvisi. Pri vypnutem
   //--- reliefu se netestuje vubec: pocitadla by zustala nulova, priznak
   //--- by platil na kazdem ticku a s nim by se na kazdem ticku
   //--- prepocitaly i navrhy vstupu.
   //--- Slot, ktery jeste ceka na sve ATR, se zkousi prepocitat na
   //--- kazdem ticku - revalidace uz mu totiz posunula posledni
   //--- zkontrolovanou svicku, takze samotny test "novy bar" by dalsi
   //--- pokus odlozil az na dalsi bar TOHOTO timeframu (na D1 o den).
   //--- Cekani se drzi zvlast od "noveho baru": navrhy vstupu se
   //--- prepocitavaji na novem baru vzdy (sikma primka ma na kazdem
   //--- baru jinou hodnotu, i kdyz se sama neprepocitala), ale kvuli
   //--- cekani na ATR by se prepocitavaly na kazdem ticku zbytecne.
   bool newReliefBar   = false;
   bool reliefWaitsATR = false;
   if(InpUseRelief)
      for(int s = 0; s < g_relTFCount; s++)
        {
         if(g_relAtr[s] <= 0.0)
            reliefWaitsATR = true;
         if(iTime(_Symbol, g_relTF[s], 1) != g_reliefCheckedBar[s])
            newReliefBar = true;
        }

   //--- Navrhy se prepocitaji nejvyse JEDNOU za tick, az kdyz je vse
   //--- ostatni srovnane. Drive to na hodinove hranici bylo az trikrat
   //--- a mezivysledek stejne nikdo necetl - kazdy prepocet pritom
   //--- znamena pruchod pozicemi, ctyri vypocty objemu, hledani hran i
   //--- reliefu a pres sto volani do terminalu pri kresleni.
   bool plansDirty = false;

   //--- 1) Reliefni primky prorazene prave uzavrenou svickou musi
   //---    zmizet JESTE PRED vyhodnocenim vstupu. Prurazova svicka
   //---    casto prorazi i primku kotvenou na svem vlastnim swingu, a
   //---    dokud primka drzi, zamitne si vstup sama sebou; o par kroku
   //---    niz uz ji revalidace smaze, jenze dalsi svicka uz prechodem
   //---    pres uroven neni a signal je nenavratne pryc.
   bool reliefDropped[];
   if(InpUseRelief && newReliefBar)
      RevalidateRelief(reliefDropped);

   //--- 2) Vstup potvrzeny uzavrenou svickou vstupniho TF.
   //---    Kdyby se urovne prepocitaly driv, na hodinove hranici by se
   //---    prechod pres uroven meril proti uz jine (starsi) urovni a
   //---    platny signal by zmizel.
   if(EntryMode() == PUNTIKY_ENTRY_M1_CLOSE && newEntryBar)
      CheckEntryOnEntryTF();

   //--- 3) Novy bar TF kanalu -> prepocet a prekresleni kanalu.
   //---    Hrany se posunuly, takze SL i PT navrhu uz neodpovidaji.
   if(newChannelBar)
     {
      RecalcChannels(newChannelSlot);
      plansDirty = true;
     }

   //--- 4) Novy bar nektereho TF reliefu -> prepocet jeho primek
   //---    (nebo dotazeni slotu, ktery cekal na sve ATR)
   if(newReliefBar || reliefWaitsATR)
      RecalcRelief(false, reliefDropped);
   if(newReliefBar)
      plansDirty = true;

   //--- 5) Novy bar TF prurazu -> nove urovne high/low
   if(newBreakoutBar)
     {
      RefreshBreakoutLevels();
      plansDirty = true;
     }

   //--- 6) Pruraz urovne se hlida na kazdem ticku, aby se prikaz na
   //---    spotrebovanou uroven zrusil hned, ne az za minutu
   const bool wasBuyBroken  = g_dir[PUNTIKY_DIR_BUY].broken;
   const bool wasSellBroken = g_dir[PUNTIKY_DIR_SELL].broken;
   UpdateArming();
   if(g_dir[PUNTIKY_DIR_BUY].broken  != wasBuyBroken ||
      g_dir[PUNTIKY_DIR_SELL].broken != wasSellBroken)
     {
      // Uroven padla, je spotrebovana - hleda se dalsi swing (vcetne
      // prave otevrene svicky TF prurazu), jinak by expert cekal az na
      // otevreni dalsi svicky TF prurazu
      g_breakSwapPending = true;
      g_breakSwapBar     = g_lastEntryBar;
     }

   //--- 7) Vymena spotrebovane urovne za dalsi swing. V rezimu
   //---    M1_CLOSE se odklada az za PRVNI novy bar vstupniho TF po
   //---    prurazu, tedy az za krok 2: vstup se potvrzuje uzavrenim
   //---    svicky a musi se merit proti urovni, kterou svicka
   //---    prorazila. Vymena uvnitr svicky znamenala, ze se close
   //---    porovnal uz s dalsim (vyssim) swingem, takze rezim se
   //---    swingovymi urovnemi prakticky nikdy nevstoupil.
   if(g_breakSwapPending &&
      (EntryMode() != PUNTIKY_ENTRY_M1_CLOSE ||
       (newEntryBar && g_lastEntryBar != g_breakSwapBar)))
     {
      g_breakSwapPending = false;
      RefreshBreakoutLevels();
      plansDirty = true;
     }

   //--- 8) Jediny prepocet navrhu za tick
   if(plansDirty)
      RebuildPlans();

   //--- 9) Skutecne prikazy se srovnaji s navrhy nejvyse jednou za tick
   if(EntryMode() == PUNTIKY_ENTRY_PENDING && g_ordersDirty)
      SyncPendingOrders();

   //--- 10) Priblizeni k urovni vstupu rozblika zarovky Hue
   CheckHueAlerts();
  }

//+------------------------------------------------------------------+
//| Obchodni transakce - zachyti otevreni pozice.                    |
//| V pending rezimu se prikaz vyplni bez zasahu experta, takze bez  |
//| teto obsluhy by expert nevedel, ze uz na dane urovni obchodoval, |
//| a dal by nabizel vstup, ktery je davno vyplneny. Uroven se       |
//| spotrebuje jen tehdy, kdyz k ni obchod skutecne patri (viz       |
//| EntryBelongsToLevel) - po prurazu uz muze byt aktualni jiny swing.|
//|  trans   - popis transakce                                       |
//|  request - odeslany pozadavek (nepouziva se)                     |
//|  result  - odpoved serveru (nepouziva se)                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   // Zajima nas jen pridani obchodu do historie tohoto symbolu; obchod
   // musi patrit teto strategii (magic) a musi to byt VSTUP do pozice.
   // Vystup (DEAL_ENTRY_OUT) zadnou uroven nespotrebovava, zato obrat
   // pozice na nettingovem uctu (DEAL_ENTRY_INOUT) ano - jednim
   // obchodem se tam stara pozice zavre a opacna otevre. Podrobnosti
   // obchodu jdou precist az po jeho vyberu z historie.
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(trans.symbol != _Symbol)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic)
      return;
   const long dealEntry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(dealEntry != DEAL_ENTRY_IN && dealEntry != DEAL_ENTRY_INOUT)
      return;

   const long   dealType  = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   const double dealPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL)
      return;

   const bool   isBuy = (dealType == DEAL_TYPE_BUY);
   const string dir   = isBuy ? "BUY" : "SELL";

   // Prikaz, ze ktereho obchod vznikl, se vybira jednou: jeho cena urcuje
   // uroven, ke ktere obchod patri, jeho typ rozhoduje o dorovnani stopu
   // a jeho SL / PT davaji delky, na ktere se stopy dorovnaji. Kdyz uz
   // prikaz k dispozici neni, poslouzi pro urceni urovne cena obchodu -
   // od ceny prikazu se lisi jen o skluz.
   double orderPrice = 0.0, orderSL = 0.0, orderTP = 0.0;
   long   orderType  = -1;
   if(trans.order != 0)
     {
      if(HistoryOrderSelect(trans.order))
        {
         orderType  = HistoryOrderGetInteger(trans.order, ORDER_TYPE);
         orderPrice = HistoryOrderGetDouble(trans.order, ORDER_PRICE_OPEN);
         orderSL    = HistoryOrderGetDouble(trans.order, ORDER_SL);
         orderTP    = HistoryOrderGetDouble(trans.order, ORDER_TP);
        }
      else
         // Bez prikazu nejsou zname ZADANE delky SL a PT (z obchodu jdou
         // precist jen delky vcetne skluzu, tedy prave to, co se ma
         // dorovnat), takze dorovnani odpada - at je to aspon v logu
         PrintFormat("PUNTIKY: příkaz #%I64u k obchodu #%I64u nelze načíst z historie "
                     "(chyba %d), stopy zůstávají tak, jak je vyplnil broker.",
                     trans.order, trans.deal, GetLastError());
     }
   const double entryPrice = (orderPrice > 0.0) ? orderPrice : dealPrice;

   // Obchod spotrebovava jen uroven, ke ktere skutecne patri. Tick, ktery
   // STOP prikaz vyplnil, tutez uroven zaroven prorazil, a OnTick uz mohl
   // prepnout na dalsi (starsi) swing driv, nez tato obsluha dostala slovo.
   // Drive se tu bez rozmyslu oznacila aktualni uroven - tedy ta nova, na
   // ktere nikdo neobchodoval - a to i trvale v globalni promenne
   // terminalu, takze smer zustal zablokovany ("tato uroven uz
   // obchodovana") az do vzniku dalsiho swingu. Prorazenou (starou)
   // uroven neni treba spotrebovavat, tu uz vyber swingu preskakuje.
   const int    idx   = DirIdx(isBuy);
   const double level = g_dir[idx].level;
   if(EntryBelongsToLevel(isBuy, entryPrice, level))
     {
      g_dir[idx].taken = true;
      g_dir[idx].armed = false;
      MarkLevelTaken(isBuy, level);
      ReportEvent(StringFormat("%s vyplněn @ %s", dir,
                               DoubleToString(dealPrice, _Digits)));
     }
   else
      ReportEvent(StringFormat("%s vyplněn @ %s (úroveň už posunuta na %s)", dir,
                               DoubleToString(dealPrice, _Digits),
                               DoubleToString(level, _Digits)));

   // Jedno bliknuti na to, ze obchod vznikl. Bezna upozorneni Hue hlasi
   // PRIBLIZENI k urovni a v automatickem rezimu jsou potlacena (nemaji
   // koho upozornit) - tohle je opacny pripad: expert uz vstoupil sam a
   // uzivatel u toho nebyl. Proto jen v AUTO rezimu a jen jednou, primo
   // z obsluhy vyplneni; zadna pamet se nevede, protoze kazde vyplneni
   // je samostatna udalost.
   HueOnEntry(isBuy, dealPrice);

   // Odtud dal se uz saha na obchodni ucet, takze instance urcena jen
   // ke kresleni (vypnute obchodovani nebo jiny ucet) konci. Stav
   // urovni si vede i ona, aby kreslila totez co obchodujici instance.
   if(!TradingEnabled())
     {
      UpdatePanel();
      return;
     }

   // Pending prikaz nese absolutni SL a PT spoctene pro nominalni
   // vstupni cenu. Pri plneni se skluzem by pak SL a PT nemely stejnou
   // delku (RRR by nebylo 1:1), proto se dorovnaji na skutecny vstup.
   // Delky se berou z vyplneneho prikazu, SL i PT zvlast - u druhe
   // pozice dvojiteho vstupu je PT na nasobku SL a musi mu zustat.
   // Trzni prikaz sem NEPATRI: jeho stopy uz dorovnal OpenMarket podle
   // delky navrhu, kdezto jeho ORDER_PRICE_OPEN nese cenu PLNENI -
   // delky by z nej vysly vcetne skluzu (SL o skluz delsi, PT o skluz
   // kratsi) a druhe dorovnani by je vratilo na puvodni hodnoty.
   const bool fromPending = (orderType != (long)ORDER_TYPE_BUY &&
                             orderType != (long)ORDER_TYPE_SELL);
   if(fromPending && orderPrice > 0.0 && orderSL > 0.0)
     {
      const ulong  posId      = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
      const double slDistance = MathAbs(orderPrice - orderSL);
      const double tpDistance = (orderTP > 0.0) ? MathAbs(orderTP - orderPrice) : 0.0;
      AdjustPositionStops(posId, slDistance, tpDistance);
     }

   // Opacny prikaz se rusi ADRESNE, ne pres rekonciliaci podle poctu
   // pozic: v okamziku teto obsluhy nemusi mit terminal novou pozici
   // jeste v PositionsTotal(), takze by ji EntryBlockReason nevidel,
   // navrh druheho smeru by zustal platny a jeho prikaz by lezel dal
   // (whipsaw by ho vyplnil pres InpMaxPositions = 1).
   RebuildPlans();
   if(EntryMode() == PUNTIKY_ENTRY_PENDING)
      CancelOppositeOrder(isBuy);

   // Rekonciliace se tu ZAMERNE nespousti. Bezela by nad uctem, ktery
   // novou pozici jeste nemusi hlasit, takze by navrh protistrany
   // zustal platny a prave zruseny opacny prikaz by se okamzite zadal
   // znovu - OCO by neplatilo a pri InpMaxPositions = 1 by whipsaw
   // otevrel druhou pozici. RebuildPlans uz nastavil g_ordersDirty,
   // takze prikazy srovna dalsi tick nad srovnanym uctem.
   UpdatePanel();
  }

//+------------------------------------------------------------------+
//| Timer - drzi panel aktualni i v obdobich bez ticku.              |
//| Panel se z ticku zamerne nekresli: na zlate chodi desitky ticku  |
//| za sekundu a kazde prekresleni je pres sto volani do terminalu.  |
//+------------------------------------------------------------------+
void OnTimer()
  {
   // Vzorky spreadu chodi i pres timer - na klidnem trhu by jinak
   // hodinovy median stal na par ticcich
   SampleSpread();

   // Kdyz pri startu chybela data indikatoru, zkusi se vypocet i zde -
   // graf bez ticku (zavreny trh) by jinak zustal prazdny
   if(g_needInitCalc)
      TryInitialCalc();

   // Uklid prikazu po prepnuti do rezimu M1_CLOSE muze cekat na
   // povoleni obchodovani (viz TryCleanupOrders)
   TryCleanupOrders();

   UpdatePanel();
   CheckScreenshotRequest();
  }

//+------------------------------------------------------------------+
//| Udalosti grafu - obsluha tlacitek nad panelem.                   |
//| Tlacitek je sest: test upozorneni Hue, prepinac textoveho panelu,|
//| rucni LONG / SHORT a dvojity vstup LONG 2x / SHORT 2x.           |
//| MT5 necha tlacitko po kliknuti zamacknute, proto se stav vraci   |
//| do puvodni polohy rucne.                                         |
//|  id     - druh udalosti                                          |
//|  lparam - cislo udalosti (u kliknuti se nepouziva)               |
//|  dparam - hodnota udalosti (u kliknuti se nepouziva)             |
//|  sparam - jmeno objektu, na ktery se kliklo                      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam,
                  const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   const bool isHue    = (sparam == PUNTIKY_PREFIX + "BTN_HUETEST");
   const bool isPanel  = (sparam == PUNTIKY_PREFIX + "BTN_PANEL");
   const bool isAuto   = (sparam == PUNTIKY_PREFIX + "BTN_AUTO");
   const bool isAuto2  = (sparam == PUNTIKY_PREFIX + "BTN_AUTO2");
   const bool isLong   = (sparam == PUNTIKY_PREFIX + "BTN_LONG");
   const bool isShort  = (sparam == PUNTIKY_PREFIX + "BTN_SHORT");
   const bool isLong2  = (sparam == PUNTIKY_PREFIX + "BTN_LONG2");
   const bool isShort2 = (sparam == PUNTIKY_PREFIX + "BTN_SHORT2");
   if(!isHue && !isPanel && !isAuto && !isAuto2 &&
      !isLong && !isShort && !isLong2 && !isShort2)
      return;

   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);

   // Hlaska patri k PREDCHOZIMU kliknuti - novy klik ji zahodi hned, at
   // uzivatel neceka PUNTIKY_EVENT_FLASH_SEC na stary text. Kdyz akce
   // znovu selze, obsluha nize vypise cerstvou; kdyz projde (napr. po
   // zapnuti algoritmickeho obchodovani v MT5), pod tlacitky uz nic
   // nezustane.
   ClearEventFlash();
   ChartRedraw();

   if(isHue)
      HueSendTest();
   else
      if(isPanel)
         TogglePanel();
      else
      if(isAuto)
         ToggleAutoMode();
      else
      if(isAuto2)
         ToggleAutoDouble();
      else
         if(isLong2 || isShort2)
            ManualDouble(isLong2);
         else
            ManualToggle(isLong);

   UpdatePanel();
  }

//+------------------------------------------------------------------+
//| Kontrola vstupnich parametru.                                    |
//| Nesmyslna kombinace se driv projevila jen tim, ze expert tise    |
//| neobchodoval (napr. InpMaxPositions = 0) nebo ze kazdy bar byl   |
//| pivotem (InpSwingDepth = 0). Radeji se odmitne uz pri startu.    |
//| Vraci false, kdyz je nektery vstup mimo povoleny rozsah.         |
//+------------------------------------------------------------------+
bool ValidateInputs()
  {
   string err = "";

   // Vypnout VSECHNY timeframy kanalu je legitimni nastaveni - reliefni
   // primky maji vlastni timeframy i vlastni ATR, takze bez kanalu
   // funguji dal. Neni to tedy chyba vstupu; kdyby jí bylo, expert by
   // se nespustil a OnDeinit by z grafu smazal i reliéf.
   // Referencni timeframe pro ATR a projekci prekazek pak zastoupi TF
   // vstupu (viz ResolveTFSlots).
   // Zapnute hlidani primek bez jedineho timeframu reliefu uz ale chyba
   // je - primky by se nikdy nenasly a nikdo by se to nedozvedel.
   if(InpUseRelief && g_relTFCount < 1)
      err += "zapni aspoň jeden timeframe reliéfu (nebo vypni InpUseRelief); ";

   if(InpSwingDepth < 1)         err += "InpSwingDepth >= 1; ";
   if(InpBreakSwingDepth < 1)    err += "InpBreakSwingDepth >= 1; ";
   if(InpReliefSwingDepth < 1)   err += "InpReliefSwingDepth >= 1; ";
   if(InpSwingScales < 1)        err += "InpSwingScales >= 1; ";
   if(InpReliefScales < 1)       err += "InpReliefScales >= 1; ";
   if(InpMaxSwingGap < 2)        err += "InpMaxSwingGap >= 2; ";
   if(InpReliefSwingGap < 2)     err += "InpReliefSwingGap >= 2; ";
   if(InpLookbackBars < PUNTIKY_MIN_BARS)   err += "InpLookbackBars >= 50; ";
   if(InpBreakLookback < PUNTIKY_MIN_BARS)  err += "InpBreakLookback >= 50; ";
   if(InpReliefLookback < PUNTIKY_MIN_BARS) err += "InpReliefLookback >= 50; ";
   if(InpMinSpanBars < 1)        err += "InpMinSpanBars >= 1; ";
   if(InpMaxAgeBars < 1)         err += "InpMaxAgeBars >= 1; ";
   if(InpReliefMinSpan < 1)      err += "InpReliefMinSpan >= 1; ";
   if(InpMaxChannels < 1)        err += "InpMaxChannels >= 1; ";
   if(InpMaxReliefLines < 1)     err += "InpMaxReliefLines >= 1; ";
   if(InpMaxPositions < 1)       err += "InpMaxPositions >= 1; ";
   if(InpATRPeriod < 1)          err += "InpATRPeriod >= 1; ";
   if(InpDedupFrac <= 0.0)       err += "InpDedupFrac > 0; ";
   if(InpTouchTolFrac <= 0.0)    err += "InpTouchTolFrac > 0; ";
   if(InpInsideTolFrac < 0.0)    err += "InpInsideTolFrac >= 0; ";
   if(InpPierceTolFrac < 0.0)    err += "InpPierceTolFrac >= 0; ";
   if(InpInvalidTolFrac < 0.0)   err += "InpInvalidTolFrac >= 0; ";
   if(InpMinContainment < 0.0 || InpMinContainment > 1.0)
      err += "InpMinContainment v rozsahu 0..1; ";
   if(InpBackCheckBars < 0)      err += "InpBackCheckBars >= 0; ";
   if(InpAnchorWindow < 0)       err += "InpAnchorWindow >= 0; ";
   if(InpMinWidthPoints < 0)     err += "InpMinWidthPoints >= 0; ";
   if(InpBreakoutBuffer < 0)     err += "InpBreakoutBuffer >= 0; ";
   if(InpMaxLevelOffset < 0)     err += "InpMaxLevelOffset >= 0; ";
   if(InpEdgeBuffer < 0)         err += "InpEdgeBuffer >= 0; ";
   if(InpReliefBuffer < 0)       err += "InpReliefBuffer >= 0; ";
   if(InpMinEntryPoints < 1)     err += "InpMinEntryPoints >= 1; ";
   if(InpMinEntryPoints > InpMaxEntryPoints)
      err += "InpMinEntryPoints <= InpMaxEntryPoints; ";
   // Nulovy nebo zaporny pomer by z SL udelal nulu nebo ho prehodil na
   // druhou stranu vstupu
   if(InpRiskReward <= 0.0)      err += "InpRiskReward > 0; ";
   if(InpSlippage < 0)           err += "InpSlippage >= 0; ";

   // Pocty baru pro projekci a prodlouzeni. Zaporny InpEdgeProjBars
   // obraci smysl konzervativni projekce hran: FutureBarTime by vratil
   // bar v MINULOSTI a MathMin / MathMax by vybraly hranu tam, kde uz
   // byla, misto tam, kam teprve smeruje - PT by se planoval za hranu,
   // ke ktere se cena blizi.
   if(InpEdgeProjBars < 0)       err += "InpEdgeProjBars >= 0; ";
   if(InpForwardBars < 0)        err += "InpForwardBars >= 0; ";
   if(InpReliefForwardBars < 0)  err += "InpReliefForwardBars >= 0; ";
   if(InpShotEveryBars < 0)      err += "InpShotEveryBars >= 0; ";

   // Tolerance reliefu v bodech - zaporna hodnota by test obratila
   if(InpReliefPierceTol < 0)    err += "InpReliefPierceTol >= 0; ";
   if(InpReliefWickTol < 0)      err += "InpReliefWickTol >= 0; ";
   if(InpReliefTouchTol < 0)     err += "InpReliefTouchTol >= 0; ";
   if(InpReliefDedupTol < 0)     err += "InpReliefDedupTol >= 0; ";
   if(InpReliefMidTol < 0)       err += "InpReliefMidTol >= 0; ";
   if(InpReliefMaxAge < 0.0)     err += "InpReliefMaxAge >= 0; ";
   if(InpReliefMaxDrift < 0)     err += "InpReliefMaxDrift >= 0; ";
   if(InpReliefMaxDriftATR < 0.0) err += "InpReliefMaxDriftATR >= 0; ";
   if(InpReliefMaxDist < 0)      err += "InpReliefMaxDist >= 0; ";
   if(InpReliefMaxDistATR < 0.0) err += "InpReliefMaxDistATR >= 0; ";
   if(InpReliefMaxGap < 0)       err += "InpReliefMaxGap >= 0; ";
   if(InpReliefMaxGapATR < 0.0)  err += "InpReliefMaxGapATR >= 0; ";

   // Nasobky ATR u tolerance primek - zaporny by z tolerance udelal
   // zapornou cenu a test by se obratil (viz PuntikyReliefTol)
   if(InpReliefPierceATR < 0.0)  err += "InpReliefPierceATR >= 0; ";
   if(InpReliefWickATR < 0.0)    err += "InpReliefWickATR >= 0; ";
   if(InpReliefTouchATR < 0.0)   err += "InpReliefTouchATR >= 0; ";

   // Upozorneni Hue - nulovy timeout by WebRequest nechal viset
   if(InpHueTimeout < 1)         err += "InpHueTimeout >= 1; ";
   if(InpHueNearPoints < 0)      err += "InpHueNearPoints >= 0; ";
   if(InpHueRepeatMinutes < 0)   err += "InpHueRepeatMinutes >= 0; ";

   // Hystereze pod 1 by pamet upozorneni uvolnila jeste UVNITR pasma,
   // ve kterem se hlasi - upozorneni by se pak posilalo znovu a znovu
   // pri kazdem ticku, ktery se do pasma vrati
   if(InpHueResetFactor < 1.0)   err += "InpHueResetFactor >= 1; ";

   // Zobrazeni - nulove pismo by udelalo z panelu i tlacitek prazdna mista
   if(InpPanelFontSize < 1)      err += "InpPanelFontSize >= 1; ";
   if(InpPointFontSize < 1)      err += "InpPointFontSize >= 1; ";
   if(InpPanelLineHeight < 0)    err += "InpPanelLineHeight >= 0; ";
   if(InpPanelOneClickShift < 0) err += "InpPanelOneClickShift >= 0; ";
   if(InpLabelMergeATR < 0.0)    err += "InpLabelMergeATR >= 0; ";

   // Stredni usek primky musi byt neprazdny interval uvnitr 0..1,
   // jinak by test stredniho dotyku zamitl uplne vsechny primky
   if(InpReliefMidFrom < 0.0 || InpReliefMidTo > 1.0 || InpReliefMidFrom >= InpReliefMidTo)
      err += "0 <= InpReliefMidFrom < InpReliefMidTo <= 1; ";

   if(InpLotMode == PUNTIKY_LOT_RISK && InpRiskPercent <= 0.0)
      err += "InpRiskPercent > 0; ";
   if(InpLotMode == PUNTIKY_LOT_FIXED && InpFixedLot <= 0.0)
      err += "InpFixedLot > 0; ";

   if(err == "")
      return(true);

   Print("PUNTIKY: chybné vstupní parametry - ", err);
   return(false);
  }

//+------------------------------------------------------------------+
//| Sestavi seznam zapnutych timeframu z ctyr slotu vstupu.          |
//| Vypnuty slot se preskoci a tentyz timeframe zadany dvakrat se    |
//| zapocita jen jednou: deduplikace uvnitr modulu bezi vzdy jen nad |
//| jednim polem svicek, takze dve sady totoznych utvaru pres sebe   |
//| by neodhalila a jen by zdvojila kresleni i vypocty.              |
//| PERIOD_CURRENT se prevede na skutecnou periodu grafu, jinak by   |
//| se s toutez periodou zadanou napevno nesparoval.                 |
//|  use   - ctyri prepinace slotu                                   |
//|  tf    - ctyri zadane timeframy                                  |
//|  out   - vystupni seznam zapnutych timeframu                     |
//|  count - out: kolik jich zbylo                                   |
//+------------------------------------------------------------------+
void CollectTFSlots(const bool &use[], const ENUM_TIMEFRAMES &tf[],
                    ENUM_TIMEFRAMES &out[], int &count)
  {
   count = 0;
   for(int i = 0; i < PUNTIKY_TF_SLOTS; i++)
     {
      if(!use[i])
         continue;

      const ENUM_TIMEFRAMES period = (tf[i] == PERIOD_CURRENT)
                                     ? (ENUM_TIMEFRAMES)_Period : tf[i];

      bool dup = false;
      for(int k = 0; k < count && !dup; k++)
         dup = (out[k] == period);
      if(dup)
        {
         PrintFormat("PUNTIKY: timeframe %s je zadaný dvakrát, druhý výskyt se ignoruje.",
                     EnumToString(period));
         continue;
        }

      out[count++] = period;
     }
  }

//+------------------------------------------------------------------+
//| Sestavi seznamy zapnutych timeframu kanalu i reliefu a urci      |
//| referencni timeframe. Vola se jako prvni v OnInit, jeste pred    |
//| kontrolou vstupu a pred vytvorenim ATR handle - oboji uz z toho  |
//| seznamu vychazi.                                                 |
//+------------------------------------------------------------------+
void ResolveTFSlots()
  {
   bool            use[PUNTIKY_TF_SLOTS];
   ENUM_TIMEFRAMES tf[PUNTIKY_TF_SLOTS];

   use[0] = InpChannelTF1Use; tf[0] = InpChannelTF1;
   use[1] = InpChannelTF2Use; tf[1] = InpChannelTF2;
   use[2] = InpChannelTF3Use; tf[2] = InpChannelTF3;
   use[3] = InpChannelTF4Use; tf[3] = InpChannelTF4;
   CollectTFSlots(use, tf, g_chTF, g_chTFCount);

   use[0] = InpReliefTF1Use; tf[0] = InpReliefTF1;
   use[1] = InpReliefTF2Use; tf[1] = InpReliefTF2;
   use[2] = InpReliefTF3Use; tf[2] = InpReliefTF3;
   use[3] = InpReliefTF4Use; tf[3] = InpReliefTF4;
   CollectTFSlots(use, tf, g_relTF, g_relTFCount);

   // Referencni timeframe je prvni zapnuty TF kanalu - z nej se cte ATR
   // (slucovani popisku) a v jeho barech je zadany InpEdgeProjBars,
   // tedy horizont, ke kteremu se posuzuji hrany i reliefni primky.
   // Kanaly smi byt vypnute uplne; horizont pak drzi TF vstupu, aby
   // projekce prekazek nezustala bez meritka.
   g_refTF = (g_chTFCount > 0) ? g_chTF[0] : InpEntryTF;
   if(g_chTFCount < 1)
      PrintFormat("PUNTIKY: kanály jsou vypnuté (žádný zapnutý timeframe) - "
                  "projekce překážek se měří ve svíčkách %s.", TFText(g_refTF));
  }

//+------------------------------------------------------------------+
//| Vypis seznamu timeframu pro panel a log ("M15+H1").              |
//|  list  - seznam timeframu, count - kolik jich je                 |
//+------------------------------------------------------------------+
string TFListText(const ENUM_TIMEFRAMES &list[], const int count)
  {
   if(count <= 0)
      return("-");

   string s = TFText(list[0]);
   for(int i = 1; i < count; i++)
      s += "+" + TFText(list[i]);
   return(s);
  }

//+------------------------------------------------------------------+
//| Naplni parametry modulu a prepocty bodu na cenu.                 |
//| Vstupy se za behu nemeni, takze cele struktury plati po celou    |
//| dobu behu a naplni se jedinkrat pri startu.                      |
//+------------------------------------------------------------------+
void InitParams()
  {
   g_breakBuffer    = InpBreakoutBuffer * _Point;
   g_maxLevelOffset = InpMaxLevelOffset * _Point;

   g_chParams.minSpanBars    = InpMinSpanBars;
   g_chParams.minWidthPrice  = InpMinWidthPoints * _Point;
   g_chParams.minWidthATR    = InpMinWidthATR;
   g_chParams.atr            = 0.0;         // doplni RefreshATR
   g_chParams.minTouches     = InpMinTouches;
   g_chParams.touchTolFrac   = InpTouchTolFrac;
   g_chParams.insideTolFrac  = InpInsideTolFrac;
   g_chParams.minContainment = InpMinContainment;
   g_chParams.maxChannels    = InpMaxChannels;
   g_chParams.maxAgeBars     = InpMaxAgeBars;
   g_chParams.maxSwingGap    = InpMaxSwingGap;
   g_chParams.scales         = InpSwingScales;
   g_chParams.pierceTolFrac  = InpPierceTolFrac;
   g_chParams.invalidTolFrac = InpInvalidTolFrac;
   g_chParams.backCheckBars  = InpBackCheckBars;
   g_chParams.anchorWindow   = InpAnchorWindow;
   g_chParams.dedupFrac      = InpDedupFrac;
   g_chParams.requireInside  = InpRequireInside;

   g_reliefParams.swingDepth   = InpReliefSwingDepth;
   g_reliefParams.scales       = InpReliefScales;
   g_reliefParams.maxSwingGap  = InpReliefSwingGap;
   g_reliefParams.minSpanBars  = InpReliefMinSpan;
   g_reliefParams.minTouches   = InpReliefMinTouches;
   g_reliefParams.pierceTol    = InpReliefPierceTol * _Point;
   g_reliefParams.wickTol      = InpReliefWickTol * _Point;
   g_reliefParams.touchTol     = InpReliefTouchTol * _Point;
   g_reliefParams.dedupTol     = InpReliefDedupTol * _Point;
   g_reliefParams.maxAgeFactor = InpReliefMaxAge;
   g_reliefParams.maxDrift     = InpReliefMaxDrift * _Point;
   g_reliefParams.maxDriftATR  = InpReliefMaxDriftATR;
   g_reliefParams.maxDist      = InpReliefMaxDist * _Point;
   g_reliefParams.maxDistATR   = InpReliefMaxDistATR;
   g_reliefParams.maxGap       = InpReliefMaxGap * _Point;
   g_reliefParams.maxGapATR    = InpReliefMaxGapATR;
   // ATR se doplnuje az per timeframe v ReliefParamsForSlot - kazdy TF
   // reliefu ma vlastni a tolerance se od nej odvozuji
   g_reliefParams.atr          = 0.0;
   g_reliefParams.needMidTouch = InpReliefMidTouch;
   g_reliefParams.midTol       = InpReliefMidTol * _Point;
   g_reliefParams.midFrom      = InpReliefMidFrom;
   g_reliefParams.midTo        = InpReliefMidTo;
   g_reliefParams.maxLines     = InpMaxReliefLines;
  }

//+------------------------------------------------------------------+
//| Vypise prepocet vsech bodovych vstupu na cenu.                   |
//| U zlata se pocet desetinnych mist mezi brokery lisi - stejne     |
//| zadani se pak chova desetkrat jinak (tolerance reliefu zmizi,    |
//| minimalni sirka kanalu se uvolni). Z vypisu je to hned videt.    |
//+------------------------------------------------------------------+
void PrintPointDiagnostics()
  {
   PrintFormat("PUNTIKY: %s  digits=%d  point=%s", _Symbol, _Digits,
               DoubleToString(_Point, _Digits));
   PrintFormat("PUNTIKY: vstup max %d b = %s, min %d b = %s, buffer %d b = %s, "
               "odstup trzniho vstupu %d b = %s",
               InpMaxEntryPoints, DoubleToString(InpMaxEntryPoints * _Point, _Digits),
               InpMinEntryPoints, DoubleToString(InpMinEntryPoints * _Point, _Digits),
               InpBreakoutBuffer, DoubleToString(InpBreakoutBuffer * _Point, _Digits),
               InpMaxLevelOffset, DoubleToString(InpMaxLevelOffset * _Point, _Digits));
   PrintFormat("PUNTIKY: rezerva k hraně %d b = %s, k přímce %d b = %s, "
               "min. šířka kanálu %d b = %s",
               InpEdgeBuffer, DoubleToString(InpEdgeBuffer * _Point, _Digits),
               InpReliefBuffer, DoubleToString(InpReliefBuffer * _Point, _Digits),
               InpMinWidthPoints, DoubleToString(InpMinWidthPoints * _Point, _Digits));
   // Nasobky ATR se sem nevypisuji v cene - ta zavisi na ATR kazdeho
   // TF reliefu zvlast a vypisuje ji az diagnostika po prvnim prepoctu
   PrintFormat("PUNTIKY: reliéf - násobky ATR: proříznutí %.2f, knot %.2f, dotyk %.2f, "
               "drift %.1f, od ceny %.1f, odstup %.1f  (0 = jen bodová mez; "
               "platí větší z obou)",
               InpReliefPierceATR, InpReliefWickATR, InpReliefTouchATR,
               InpReliefMaxDriftATR, InpReliefMaxDistATR, InpReliefMaxGapATR);
   PrintFormat("PUNTIKY: reliéf - proříznutí %d b = %s, knot %d b = %s, dotyk %d b = %s, "
               "shoda %d b = %s, drift %d b = %s, střed %d b = %s",
               InpReliefPierceTol, DoubleToString(InpReliefPierceTol * _Point, _Digits),
               InpReliefWickTol, DoubleToString(InpReliefWickTol * _Point, _Digits),
               InpReliefTouchTol, DoubleToString(InpReliefTouchTol * _Point, _Digits),
               InpReliefDedupTol, DoubleToString(InpReliefDedupTol * _Point, _Digits),
               InpReliefMaxDrift, DoubleToString(InpReliefMaxDrift * _Point, _Digits),
               InpReliefMidTol, DoubleToString(InpReliefMidTol * _Point, _Digits));
  }

//+------------------------------------------------------------------+
//| Nacte aktualni ATR TF kanalu do g_atr.                           |
//| Handle indikatoru na jinem TF, nez ma graf, se pocita            |
//| asynchronne - hned po iATR() vraci CopyBuffer chybu. Nula z ATR  |
//| se pritom bere jako "bez ATR" a filtr sirky i slozka skore by se |
//| tise vypnuly, takze se rozlisuje "jeste nespocteno" od hodnoty.  |
//| Vraci true, kdyz je ATR k dispozici.                             |
//+------------------------------------------------------------------+
bool RefreshATR()
  {
   if(BarsCalculated(g_atrHandle) <= 0)
      return(false);

   double buf[];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, buf) != 1)
      return(false);
   if(buf[0] <= 0.0)
      return(false);

   g_atr          = buf[0];
   g_chParams.atr = g_atr;
   return(true);
  }

//+------------------------------------------------------------------+
//| Nacte ATR jednoho TF reliefu do g_relAtr[slot].                  |
//| Plati totez co u RefreshATR: handle na jinem TF, nez ma graf, se |
//| pocita asynchronne, takze hned po startu jeste hodnotu nema.     |
//|  slot - poradi timeframu v g_relTF                               |
//| Vraci true, kdyz je ATR tohoto timeframu k dispozici.            |
//+------------------------------------------------------------------+
bool RefreshReliefATR(const int slot)
  {
   if(g_relAtrHandle[slot] == INVALID_HANDLE)
      return(false);
   if(BarsCalculated(g_relAtrHandle[slot]) <= 0)
      return(false);

   double buf[];
   if(CopyBuffer(g_relAtrHandle[slot], 0, 1, 1, buf) != 1)
      return(false);
   if(buf[0] <= 0.0)
      return(false);

   g_relAtr[slot] = buf[0];
   return(true);
  }

//+------------------------------------------------------------------+
//| Parametry hledani reliefu pro jeden timeframe.                   |
//| Prahy detekce jsou pro vsechny timeframy tytez, ale tolerance se |
//| dopocitavaji z ATR TOHOTO timeframu - rozpeti svicky D1 je o     |
//| rady jinde nez u M1 a jedina bodova mez by na dlouhych           |
//| timeframech znamenala nulovou toleranci (viz PuntikyReliefTol).  |
//| Parametry se vraci KOPII, ne prepsanim globalu: prepocet jednoho |
//| timeframu se tak nemuze projevit na tom, cim se prave meri jiny. |
//|  slot - poradi timeframu v g_relTF                               |
//|  p    - out: parametry platne pro tento timeframe                |
//+------------------------------------------------------------------+
void ReliefParamsForSlot(const int slot, SReliefParams &p)
  {
   p = g_reliefParams;
   p.atr = (slot >= 0 && slot < PUNTIKY_TF_SLOTS) ? g_relAtr[slot] : 0.0;

   p.pierceTol = PuntikyReliefTol(g_reliefParams.pierceTol, InpReliefPierceATR, p.atr);
   p.wickTol   = PuntikyReliefTol(g_reliefParams.wickTol,   InpReliefWickATR,   p.atr);
   p.touchTol  = PuntikyReliefTol(g_reliefParams.touchTol,  InpReliefTouchATR,  p.atr);
  }

//+------------------------------------------------------------------+
//| Dokonci inicializaci, jakmile jsou k dispozici data indikatoru.  |
//| Do te doby se nic nepocita ani nekresli - z kanalu vybranych bez |
//| ATR filtru by se rovnou zadaly pending prikazy.                  |
//| Vraci true, kdyz uz je inicializace hotova.                      |
//+------------------------------------------------------------------+
bool TryInitialCalc()
  {
   if(!g_needInitCalc)
      return(true);
   if(!RefreshATR())
      return(false);

   // Vzorky spreadu z historie - pri startu jeste nemusely byt k
   // dispozici, ted uz data jsou
   PrimeSpreadSamples();

   g_needInitCalc = false;

   // Nejdriv reliefni primky, pak kanaly: MT5 kresli objekty v poradi
   // vzniku a kanal ma na spolecne usecce lezet NAD reliefem (viz
   // RedrawChannels). V opacnem poradi se kanaly kreslily dvakrat.
   RecalcRelief();          // pri startu vzdy plny prepocet vsech TF
   RecalcChannels();
   RefreshBreakoutLevels();
   RebuildPlans();

   // Casy prave otevrenych svicek se zapisou hned, aby prvni tick po
   // startu neopakoval tentyz vypocet jeste jednou jako "novy bar"
   for(int s = 0; s < g_chTFCount; s++)
      IsNewBar(g_chTF[s], g_lastChannelBar[s]);
   IsNewBar(InpBreakoutTF, g_lastBreakoutBar);
   IsNewBar(InpEntryTF,    g_lastEntryBar);

   // V pending rezimu se prikazy zadaji hned - jinak by se cekalo
   // az na otevreni dalsi svicky TF prurazu
   if(EntryMode() == PUNTIKY_ENTRY_PENDING)
      SyncPendingOrders();

   return(true);
  }

//+------------------------------------------------------------------+
//| Uklidi pending prikazy, ktere v rezimu M1_CLOSE nemaji co delat. |
//| Rezim M1_CLOSE otevira pozice na trhu a lezici prikazy vubec     |
//| neridi - zbyly by po pending rezimu se starym SL a PT a jejich   |
//| plneni by pridalo druhou pozici s plnym rizikem, kterou uz nikdo |
//| nesleduje (EntryBlockReason pocita jen pozice, ne prikazy).      |
//| Uklid se opakuje, dokud neprojde: pri startu byva obchodovani     |
//| vypnute (AutoTrading, jiny ucet) a jeho zapnuti zadny OnInit      |
//| nevyvola, takze jednorazovy pokus v OnInit se tise ztratil.      |
//+------------------------------------------------------------------+
void TryCleanupOrders()
  {
   if(!g_cleanupOrders)
      return;

   // Neni co uklizet - v tomto rezimu uz zadny prikaz vzniknout nemuze
   const int left = CountOrders();
   if(left == 0)
     {
      g_cleanupOrders = false;
      return;
     }

   const string blocked = TradingDisabledReason();
   if(blocked != "")
     {
      if(!g_cleanupWarned)
        {
         g_cleanupWarned = true;
         PrintFormat("PUNTIKY: režim M1 - %d ležící příkaz(ů) zatím nelze zrušit "
                     "(%s); uklidí se, jakmile bude obchodování povoleno.",
                     left, blocked);
        }
      return;
     }

   if(CancelPendingOrders())
     {
      g_cleanupOrders = false;
      PrintFormat("PUNTIKY: režim M1 - zrušeno %d ležících příkazů z pending režimu.", left);
     }
  }

//+------------------------------------------------------------------+
//| Detekce nove svicky na zadanem timeframu.                        |
//| Vraci true prave jednou pri otevreni nove svicky.                |
//|  tf      - sledovany timeframe                                   |
//|  lastBar - cas posledni zpracovane svicky (in/out)               |
//+------------------------------------------------------------------+
bool IsNewBar(const ENUM_TIMEFRAMES tf, datetime &lastBar)
  {
   const datetime t = iTime(_Symbol, tf, 0);
   if(t == 0 || t == lastBar)
      return(false);
   lastBar = t;
   return(true);
  }

//+------------------------------------------------------------------+
//| Cas o zadany pocet baru za prave otevrenym barem - pro pravy     |
//| konec kreslenych usecek.                                         |
//| Kotvi se na OTEVRENI aktualniho baru, aby vraceny cas odpovidal  |
//| presne tomu indexu, na ktery ho MT5 v grafu vykresli; pocitano   |
//| od TimeCurrent() sedel pravy konec usecky o zlomek baru jinam.   |
//|  tf   - timeframe, ze ktereho se bere delka baru                 |
//|  bars - o kolik baru dopredu                                     |
//+------------------------------------------------------------------+
datetime FutureBarTime(const ENUM_TIMEFRAMES tf, const int bars)
  {
   const int      secs = MathMax(PeriodSeconds(tf), 1);
   const datetime t0   = iTime(_Symbol, tf, 0);
   if(t0 <= 0)
      return(TimeCurrent() + (datetime)(secs * bars));
   return(t0 + (datetime)(secs * bars));
  }

//+------------------------------------------------------------------+
//| Index prave otevreneho baru v souradnicich posledni detekce.     |
//| Geometrie kanalu i reliefnich primek je vedena v indexech pole,  |
//| ze ktereho vznikla (viz hlavicka SChannel). Bars() spocita bary  |
//| mezi referencnim barem a soucasnosti, takze se index nerozjede   |
//| ani pres vikend.                                                 |
//| Kdyz rada jeste neni synchronizovana (po startu nebo reconnectu), |
//| vrati Bars() nulu. Index se z casu NEDOPOCITAVA: pres vikend by  |
//| z nej vyslo o stovky az tisice baru vic, sikme hrany i reliefni  |
//| primky by odskocily o kus grafu, rekonciliace by prepsala SL a PT|
//| lezicich prikazu a revalidace by kazdou sklonenou primku zahodila|
//| jako "ujetou". Vraci se proto posledni spolehliva hodnota.       |
//|  tf       - timeframe, ve kterem geometrie vznikla               |
//|  refTime  - cas posledniho analyzovaneho baru                    |
//|  refIdx   - jeho index v analyzovanem poli                       |
//|  cacheRef - referencni bar, ke kteremu patri cache (in/out)      |
//|  cache    - posledni spolehlive spocteny index (in/out)          |
//+------------------------------------------------------------------+
double BarIndexNow(const ENUM_TIMEFRAMES tf, const datetime refTime, const int refIdx,
                   datetime &cacheRef, double &cache)
  {
   const datetime now = TimeCurrent();
   if(refTime <= 0 || now <= refTime)
      return((double)refIdx);

   // Bars() zapocita oba krajni bary, referencni se tedy odecte
   const int bars = Bars(_Symbol, tf, refTime, now);
   if(bars > 0)
     {
      cacheRef = refTime;
      cache    = (double)refIdx + (double)(bars - 1);
      return(cache);
     }

   // Cache patri jinemu referencnimu baru? Pak zbyva jen sam referencni
   // index - geometrie tak zustane u posledniho analyzovaneho baru
   return((cacheRef == refTime) ? cache : (double)refIdx);
  }

//--- Index aktualniho baru v souradnicich kanalu / reliefnich primek
//--- jednoho timeframu (slot = tfIdx utvaru)
double ChannelBarNow(const int slot)
  {
   return(BarIndexNow(g_chTF[slot], g_channelRefTime[slot], g_channelRefIdx[slot],
                      g_channelBarCacheRef[slot], g_channelBarCache[slot]));
  }
double ReliefBarNow(const int slot)
  {
   return(BarIndexNow(g_relTF[slot], g_reliefRefTime[slot], g_reliefRefIdx[slot],
                      g_reliefBarCacheRef[slot], g_reliefBarCache[slot]));
  }

//+------------------------------------------------------------------+
//| Naplni pro kazdy zapnuty timeframe index prave otevreneho baru a |
//| index baru projekce dopredu.                                     |
//| Kanaly i primky vsech timeframu lezi v jednom poli, ale kazdy    |
//| utvar ve VLASTNIM indexovem prostoru - hledani nejblizsi hrany   |
//| nebo primky proto dostava cele pole indexu a vybira si podle     |
//| tfIdx (viz PuntikyDistanceToNextEdge).                           |
//|  barNow  - out: index prave otevreneho baru kazdeho timeframu    |
//|  barProj - out: index baru projekce dopredu kazdeho timeframu    |
//+------------------------------------------------------------------+
void ChannelBarIndexes(double &barNow[], double &barProj[])
  {
   ArrayResize(barNow,  g_chTFCount);
   ArrayResize(barProj, g_chTFCount);
   for(int s = 0; s < g_chTFCount; s++)
     {
      barNow[s]  = ChannelBarNow(s);
      barProj[s] = barNow[s] + ProjBars(g_chTF[s]);
     }
  }
void ReliefBarIndexes(double &barNow[], double &barProj[])
  {
   ArrayResize(barNow,  g_relTFCount);
   ArrayResize(barProj, g_relTFCount);
   for(int s = 0; s < g_relTFCount; s++)
     {
      barNow[s]  = ReliefBarNow(s);
      barProj[s] = barNow[s] + ProjBars(g_relTF[s]);
     }
  }

//+------------------------------------------------------------------+
//| Horizont projekce prekazek prepocteny na bary zadaneho TF.       |
//|                                                                  |
//| Hrany kanalu i reliefni primky jsou sikme, takze se posuzuji ke  |
//| stejnemu okamziku - k tomu, kdy obchod nejspis skonci. Ten se    |
//| odhaduje z delky vstupu a ATR: obchod dlouhy jednu ATR trva      |
//| radove jeden bar. InpEdgeProjBars uz slouzi jen jako STROP.      |
//|                                                                  |
//| Pevny pocet baru sam o sobe nefungoval, protoze se neprizpusobil |
//| nastroji - stejne jako prah driftu u reliefu. Na BTCUSD je cely  |
//| obchod 300 b = 3 USD proti ATR M15 kolem 84 USD, tedy otazka     |
//| minut; hrana kanalu za 12 baru (3 hodiny) mezitim vyjela pres    |
//| 100 USD nad vstup a konzervativni odhad zamitl smer, kde bylo    |
//| 3708 b mista - dvanactkrat vic, nez obchod potreboval.           |
//|                                                                  |
//| Odhad je zamerne linearni (dist / ATR). Presnejsi model nahodne  |
//| prochazky tu nema co zlepsit: rozhoduje rad velikosti a ten je   |
//| shora omezen stropem.                                            |
//|  tf - timeframe, ve kterem se ma horizont vyjadrit               |
//+------------------------------------------------------------------+
double ProjBars(const ENUM_TIMEFRAMES tf)
  {
   const int src = PeriodSeconds(g_refTF);
   const int dst = PeriodSeconds(tf);
   if(src <= 0 || dst <= 0)
      return((double)InpEdgeProjBars);

   // Kolik baru TF kanalu obchod nejspis potrva. Bere se plna delka
   // vstupu - skutecny PT uz muze byt jen kratsi, takze je to horni odhad.
   double bars = (double)InpEdgeProjBars;
   if(g_atr > 0.0)
      bars = MathMin(bars, (InpMaxEntryPoints * _Point) / g_atr);

   return(bars * (double)src / (double)dst);
  }

//+------------------------------------------------------------------+
//| Nacte uzavrene svicky zadaneho TF do pole.                       |
//| Bere se od shiftu 1, tedy bez prave otevrene svicky - jinak by   |
//| se vysledek menil uvnitr rozpracovane svicky.                    |
//|  tf    - timeframe, count - kolik svicek                         |
//|  rates - vystupni pole (index 0 = nejstarsi)                     |
//| Vraci pocet nactenych svicek (zaporne pri chybe).                |
//+------------------------------------------------------------------+
int LoadClosedBars(const ENUM_TIMEFRAMES tf, const int count, MqlRates &rates[])
  {
   ArraySetAsSeries(rates, false);
   return(CopyRates(_Symbol, tf, 1, count, rates));
  }

//--- Pocet kanalu / reliefnich primek. Jedinym zdrojem pravdy je
//--- velikost pole - samostatny citac by se pri predcasnem navratu z
//--- prepoctu rozesel s tim, co v poli skutecne je.
int ChannelCount() { return(ArraySize(g_channels)); }
int ReliefCount()  { return(ArraySize(g_relief)); }

//--- Patri prave vybrana pozice teto strategii? (symbol + magic)
bool IsOurPosition()
  {
   return(PositionGetString(POSITION_SYMBOL) == _Symbol &&
          PositionGetInteger(POSITION_MAGIC) == InpMagic);
  }

//--- Patri prave vybrany prikaz teto strategii? (symbol + magic)
bool IsOurOrder()
  {
   return(OrderGetString(ORDER_SYMBOL) == _Symbol &&
          OrderGetInteger(ORDER_MAGIC) == InpMagic);
  }

//+------------------------------------------------------------------+
//| Posbira tickety pozic strategie do pole.                         |
//| Tickety se sbiraji PRED zpracovanim: kazde zavreni nebo zruseni  |
//| meni seznam i to, co ma terminal prave vybrane, takze by se      |
//| dalsi polozky cetly z rozpadleho kontextu. Sestupna smycka sama  |
//| o sobe nestaci - je bezpecna jen dokud se maze prave ta polozka, |
//| na ktere stoji.                                                  |
//|  type    - pozadovany typ pozice (-1 = jakykoli)                 |
//|  tickets - out: nalezene tickety                                 |
//| Vraci jejich pocet.                                              |
//+------------------------------------------------------------------+
int CollectOurPositions(const long type, ulong &tickets[])
  {
   ArrayResize(tickets, 0);
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong t = PositionGetTicket(i);
      if(t == 0 || !IsOurPosition())
         continue;
      if(type >= 0 && PositionGetInteger(POSITION_TYPE) != type)
         continue;
      ArrayResize(tickets, n + 1, 8);
      tickets[n++] = t;
     }
   return(n);
  }

//+------------------------------------------------------------------+
//| Totez pro pending prikazy strategie (viz CollectOurPositions).   |
//|  type    - pozadovany typ prikazu (-1 = jakykoli)                |
//|  tickets - out: nalezene tickety                                 |
//+------------------------------------------------------------------+
int CollectOurOrders(const long type, ulong &tickets[])
  {
   ArrayResize(tickets, 0);
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong t = OrderGetTicket(i);
      if(t == 0 || !IsOurOrder())
         continue;
      if(type >= 0 && OrderGetInteger(ORDER_TYPE) != type)
         continue;
      ArrayResize(tickets, n + 1, 8);
      tickets[n++] = t;
     }
   return(n);
  }

//+------------------------------------------------------------------+
//| Pocet otevrenych pozic strategie na aktualnim symbolu            |
//+------------------------------------------------------------------+
int CountPositions()
  {
   ulong tickets[];
   return(CollectOurPositions(-1, tickets));
  }

//+------------------------------------------------------------------+
//| Pochazi obchod s temito udaji z dvojiteho vstupu?                |
//| Rozhoduje znacka v komentari, kterou dava PlaceStopOrder. Kdyz   |
//| broker komentar prepise (bezne u castecneho plneni nebo pri      |
//| zavreni), zaskoci geometrie: druha noha dvojiteho vstupu ma PT   |
//| vyrazne delsi nez SL, coz obchod s RRR 1:1 nikdy nema.           |
//|  comment - komentar prikazu nebo pozice                          |
//|  open    - vstupni cena, sl / tp - stopy obchodu                 |
//+------------------------------------------------------------------+
bool LooksDoubleEntry(const string comment, const double open,
                      const double sl, const double tp)
  {
   if(StringFind(comment, PUNTIKY_DOUBLE_TAG) >= 0)
      return(true);

   // Nas vlastni komentar bez znacky 2x je jasna odpoved: obchod
   // pochazi z tlacitka LONG / SHORT. Geometrie se na nej pouzit nesmi -
   // staci, aby uzivatel pritahl SL, a pomer PT:SL prekroci prah:
   // tlacitko by zesedlo, klik prestal fungovat a pozice by se ohlasila
   // jako "2x". Geometrie je zaloha JEN pro prepsany komentar.
   if(StringFind(comment, "PUNTIKY") >= 0)
      return(false);

   if(open <= 0.0 || sl <= 0.0 || tp <= 0.0)
      return(false);

   const double slDist = MathAbs(open - sl);
   const double tpDist = MathAbs(tp - open);
   if(slDist <= 0.0)
      return(false);

   return(tpDist > slDist * PUNTIKY_DOUBLE_TP_RATIO);
  }

//+------------------------------------------------------------------+
//| Zjisti JEDINYM pruchodem, co strategie drzi v obou smerech.      |
//| Text tlacitka, jeho bublina i radek panelu ctou tentyz vysledek -|
//| drive si kazdy z nich volal sken sam a seznam pozic a prikazu se |
//| pri kazdem obnoveni panelu, tedy kazdou sekundu, prochazel       |
//| sestkrat (a na kazde polozce cetl jeste komentar a stopy).       |
//| Kdyz se ve smeru sejde jednoduchy i dvojity obchod (rucni zasah  |
//| v terminalu), ma prednost dvojity - jinak by tlacitko 2x         |
//| zesedlo a jeho druha noha by sla odebrat jen z terminalu.        |
//|  ms - out: prehled obou smeru vcetne souhrnu pro panel           |
//+------------------------------------------------------------------+
void ScanBothDirections(SMarketState &ms)
  {
   ms.Reset();

   bool buyDouble = false, sellDouble = false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition())
         continue;

      // Prvni nalezena pozice se pamatuje pro radek panelu - ten uz
      // seznam neprochazi znovu
      if(ms.firstPosition == 0)
         ms.firstPosition = ticket;

      const bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      const bool dbl   = LooksDoubleEntry(PositionGetString(POSITION_COMMENT),
                                          PositionGetDouble(POSITION_PRICE_OPEN),
                                          PositionGetDouble(POSITION_SL),
                                          PositionGetDouble(POSITION_TP));
      if(isBuy)
        {
         ms.buy.positions++;
         if(dbl)
            buyDouble = true;
        }
      else
        {
         ms.sell.positions++;
         if(dbl)
            sellDouble = true;
        }
     }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderGetTicket(i) == 0 || !IsOurOrder())
         continue;

      // Do souhrnu pro panel patri vsechny prikazy strategie, do
      // prehledu smeru jen STOP prikazy, ktere rucni tlacitka ovladaji
      ms.totalOrders++;

      const long type = OrderGetInteger(ORDER_TYPE);
      if(type != ORDER_TYPE_BUY_STOP && type != ORDER_TYPE_SELL_STOP)
         continue;

      const bool isBuy = (type == ORDER_TYPE_BUY_STOP);
      const bool dbl   = LooksDoubleEntry(OrderGetString(ORDER_COMMENT),
                                          OrderGetDouble(ORDER_PRICE_OPEN),
                                          OrderGetDouble(ORDER_SL),
                                          OrderGetDouble(ORDER_TP));
      if(isBuy)
        {
         ms.buy.orders++;
         if(dbl)
            buyDouble = true;
        }
      else
        {
         ms.sell.orders++;
         if(dbl)
            sellDouble = true;
        }
     }

   // Dvojity vstup se pozna i podle jedine nohy: po vyplneni PT1 zbyva
   // druha pozice a ta porad patri tlacitku 2x
   if(ms.buy.Busy())
      ms.buy.kind = buyDouble ? PUNTIKY_MANUAL_DOUBLE : PUNTIKY_MANUAL_SINGLE;
   if(ms.sell.Busy())
      ms.sell.kind = sellDouble ? PUNTIKY_MANUAL_DOUBLE : PUNTIKY_MANUAL_SINGLE;
  }

//+------------------------------------------------------------------+
//| Prehled jednoho smeru. Pouziva ho obsluha kliknuti, kde na cene  |
//| jednoho pruchodu navic nezalezi.                                 |
//|  isBuy - smer (true = LONG, false = SHORT)                       |
//|  st    - out: prehled smeru                                      |
//+------------------------------------------------------------------+
void ScanDirection(const bool isBuy, SDirectionState &st)
  {
   SMarketState ms;
   ScanBothDirections(ms);

   // Strukturu nelze vybrat podminenym vyrazem, proto vetveni
   if(isBuy)
      st = ms.buy;
   else
      st = ms.sell;
  }

//+------------------------------------------------------------------+
//| Umi ucet drzet vic pozic na jednom symbolu soucasne?             |
//| Na nettingovem uctu se dva prikazy stejneho smeru sloucily do    |
//| jedine pozice a SL/PT toho druheho by prepsaly ten prvni - z     |
//| dvojiteho vstupu by nezbylo nic nez jeden obchod se spatnym PT.  |
//| Tlacitka 2x se proto na takovem uctu nabizet nesmi.              |
//+------------------------------------------------------------------+
bool AccountIsHedging()
  {
   // Rezim uctu se za behu experta nemeni (zmena uctu znamena novy
   // OnInit), takze se cte z hodnoty zjistene pri startu
   return(g_accountHedging);
  }

//+------------------------------------------------------------------+
//| Pocet aktivnich pending prikazu strategie                        |
//+------------------------------------------------------------------+
int CountOrders()
  {
   ulong tickets[];
   return(CollectOurOrders(-1, tickets));
  }

//+------------------------------------------------------------------+
//| Smi expert vubec sahat na obchodni ucet?                         |
//| Zamerne neresi pocet pozic - to je otazka noveho vstupu, ne      |
//| opravneni. Instance jen pro kresleni (InpEnableTrading = false   |
//| nebo jiny ucet) takto nesmi ani rusit cizi prikazy.              |
//+------------------------------------------------------------------+
bool TradingEnabled()
  {
   return(TradingDisabledReason() == "");
  }

//+------------------------------------------------------------------+
//| Proc expert nesmi obchodovat ("" = smi).                         |
//| Duvodu je sest a kazdy se resi jinde: dva ve vstupech experta,   |
//| dva v terminalu a dva na strane brokera. Spolecna hlaska         |
//| "obchodování je vypnuto" nutila uzivatele hledat, ktery z nich   |
//| to zrovna je - typicky pritom jde o globalni tlacitko            |
//| algoritmickeho obchodovani v liste MT5.                          |
//| Poradi neni libovolne: pri vypnutem globalnim tlacitku vraci     |
//| MQL_TRADE_ALLOWED taky false, takze by se ohlasilo zaskrtavatko  |
//| ve vlastnostech experta misto skutecne priciny.                  |
//+------------------------------------------------------------------+
string TradingDisabledReason()
  {
   if(!InpEnableTrading)
      return("obchodování je vypnuté vstupem InpEnableTrading");
   if(!g_tradingAllowed)
      return(StringFormat("účet %d neodpovídá povolenému účtu %d (InpAllowedAccount)",
                          AccountInfoInteger(ACCOUNT_LOGIN), InpAllowedAccount));
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return("zapni algoritmické obchodování v MT5 (tlačítko v liště nahoře)");
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return("povol obchodování ve vlastnostech experta "
             "(záložka Obecné > Povolit algoritmické obchodování)");
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      return("broker má na tomto účtu obchodování zakázané");
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      return("broker má na tomto účtu zakázané obchodování experty");
   return("");
  }

//+------------------------------------------------------------------+
//| Vynuluje navrh vstupu.                                           |
//|  pl    - navrh, isBuy - smer, pro ktery navrh plati              |
//+------------------------------------------------------------------+
void ResetPlan(SEntryPlan &pl, const bool isBuy)
  {
   pl.valid        = false;
   pl.isBuy        = isBuy;
   pl.trigger      = 0.0;
   pl.entry        = 0.0;
   pl.sl           = 0.0;
   pl.tp           = 0.0;
   pl.distance     = 0.0;
   pl.tpDistance   = 0.0;
   pl.lots         = 0.0;
   pl.lotsDouble   = 0.0;
   pl.doubleReason = "";
   pl.tpDouble     = 0.0;
   pl.barrier      = PUNTIKY_BARRIER_NONE;
   pl.channelIdx   = -1;
   pl.reason       = "";
   pl.block        = PUNTIKY_BLOCK_NONE;
  }

//--- Nazev prekazky pro texty panelu a logu
string BarrierText(const ENUM_PUNTIKY_BARRIER barrier)
  {
   if(barrier == PUNTIKY_BARRIER_EDGE)
      return("hraně kanálu");
   if(barrier == PUNTIKY_BARRIER_RELIEF)
      return("reliéfní přímce");
   return("cíli");
  }

//--- Uroven brokera (stop level, freeze level) prepoctena na cenu
double SymbolLevelPrice(const ENUM_SYMBOL_INFO_INTEGER prop)
  {
   return((double)SymbolInfoInteger(_Symbol, prop) * _Point);
  }

//--- Stop level brokera prepocteny na cenu
double StopsLevelPrice() { return(SymbolLevelPrice(SYMBOL_TRADE_STOPS_LEVEL)); }

//+------------------------------------------------------------------+
//| Zarovna cenu na krok kotace nastroje.                            |
//| Zaokrouhleni na _Digits nestaci vsude: na nastroji, kde je krok  |
//| kotace vetsi nez bod (indexove CFD s krokem 0.25), by broker cenu|
//| mimo krok odmitl chybou INVALID_PRICE - a protoze se navrh       |
//| prepocitava kazdou minutu, expert by ho zkousel zadat porad      |
//| dokola a panel by mezitim hlasil "pripraven".                    |
//| Kdyz symbol krok nehlasi, pouzije se bod.                        |
//|  price - cena k zarovnani                                        |
//+------------------------------------------------------------------+
double AlignToTick(const double price)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(step <= 0.0)
      step = _Point;
   if(step <= 0.0)
      return(NormalizeDouble(price, _Digits));
   return(NormalizeDouble(MathRound(price / step) * step, _Digits));
  }

//+------------------------------------------------------------------+
//| Lezi STOP cena prilis blizko trhu?                               |
//| Broker nedovoli zadat ani upravit STOP prikaz bliz k trhu, nez   |
//| je jeho stop level; kdyz uz cena urovni prosla, prikaz nad (pod) |
//| trhem nelze zadat vubec. Jedina definice pro obe mista, ktera se |
//| na to ptaji - drive to byly kopie s ruznymi kraji a klik po      |
//| prurazu hlasil "blíž než stop-level" tam, kde navrh spravne      |
//| rikal "průraz už proběhl".                                       |
//|  isBuy  - smer prikazu, price - jeho vstupni cena                |
//|  margin - pozadovany odstup od trhu v cene                       |
//|  reason - out: duvod pro panel a log ("" = cena je v poradku)    |
//| Vraci true, kdyz je cena prilis blizko nebo uz za trhem. Bez     |
//| kotaci se netvrdi nic (false) - zadani prikazu si je overi samo. |
//+------------------------------------------------------------------+
bool StopTooClose(const bool isBuy, const double price, const double margin, string &reason)
  {
   reason = "";

   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return(false);

   const double market = isBuy ? ask : bid;
   if(isBuy ? (price > market + margin) : (price < market - margin))
      return(false);

   const bool passed = isBuy ? (price <= market) : (price >= market);
   reason = passed ? "průraz už proběhl"
                   : StringFormat("blíž než stop-level brokera (%.0f b)", margin / _Point);
   return(true);
  }

//+------------------------------------------------------------------+
//| Aktualni spread v cene.                                          |
//| Kdyz kotace jeste nejsou k dispozici, pouzije se spread hlaseny  |
//| symbolem - nula by znamenala, ze BUY plni presne na bidu.        |
//+------------------------------------------------------------------+
double CurrentSpread()
  {
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask > 0.0 && bid > 0.0 && ask >= bid)
      return(ask - bid);
   return((double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point);
  }

//+------------------------------------------------------------------+
//| Prepocita median z nasbiranych vzorku spreadu.                   |
//| Radi se KOPIE - poradi v kruhovem bufferu musi zustat, jinak by  |
//| se nejstarsi vzorek prepsal na spatnem miste.                    |
//+------------------------------------------------------------------+
void RecalcSpreadMedian()
  {
   if(g_spreadCount <= 0)
      return;

   double sorted[];
   ArrayResize(sorted, g_spreadCount);
   for(int i = 0; i < g_spreadCount; i++)
      sorted[i] = g_spreadSamples[i];
   ArraySort(sorted);
   g_spreadRef = sorted[g_spreadCount / 2];
  }

//+------------------------------------------------------------------+
//| Odebere vzorek spreadu a prepocita jeho median.                  |
//| Vola se nejvyse jednou za PUNTIKY_SPREAD_PERIOD sekund, takze    |
//| vzorky pokryvaji pul hodiny - rolloverova spicka trva par minut  |
//| a na median nedosahne.                                           |
//+------------------------------------------------------------------+
void SampleSpread()
  {
   const datetime now = TimeCurrent();
   if(g_spreadCount > 0 && now - g_spreadTime < PUNTIKY_SPREAD_PERIOD)
      return;

   const double s = CurrentSpread();
   if(s <= 0.0)
      return;

   g_spreadTime = now;
   g_spreadSamples[g_spreadNext] = s;
   g_spreadNext = (g_spreadNext + 1) % PUNTIKY_SPREAD_SAMPLES;
   if(g_spreadCount < PUNTIKY_SPREAD_SAMPLES)
      g_spreadCount++;

   RecalcSpreadMedian();
  }

//+------------------------------------------------------------------+
//| Naplni vzorky spreadu ze SPREADU HISTORICKYCH SVICEK vstupniho   |
//| TF, aby prvni vypocet nestal na jedinem vzorku.                  |
//| Jediny vzorek odebrany pri startu urcoval median pro cely prvni   |
//| vyber urovni prurazu. Kdyz expert nabehl behem rolloveru, byl to  |
//| spread nekolikanasobne nad normalem (500 b misto 25 b) a vyber    |
//| swingu prohlasil za prorazeny kazdy vrchol, ke kteremu se cena    |
//| kdy priblizila na tuto vzdalenost - uroven odskocila o stovky     |
//| bodu na davno neplatny swing a v pending rezimu tam expert rovnou |
//| zadal prikaz. Normalizovalo se to az po tretim vzorku, tedy po    |
//| dvou minutach.                                                    |
//| Vraci true, kdyz se vzorky podarilo naplnit; jinak se to zkusi    |
//| znovu, az budou data (viz TryInitialCalc).                       |
//+------------------------------------------------------------------+
bool PrimeSpreadSamples()
  {
   if(g_spreadPrimed)
      return(true);

   MqlRates rates[];
   const int copied = LoadClosedBars(InpEntryTF, PUNTIKY_SPREAD_SAMPLES, rates);

   int n = 0;
   for(int i = 0; i < copied && n < PUNTIKY_SPREAD_SAMPLES; i++)
     {
      // Nekteri brokeri spread do historie neplni (0) - takova svicka
      // se preskoci, at median neklesne k nule
      if(rates[i].spread <= 0)
         continue;
      g_spreadSamples[n++] = (double)rates[i].spread * _Point;
     }

   if(n <= 0)
     {
      SampleSpread();      // aspon jeden zivy vzorek, at se nemeri proti nule
      return(false);
     }

   g_spreadCount = n;
   g_spreadNext  = n % PUNTIKY_SPREAD_SAMPLES;
   g_spreadTime  = TimeCurrent();
   RecalcSpreadMedian();

   g_spreadPrimed = true;
   PrintFormat("PUNTIKY: referenční spread z historie %s - %d vzorků, medián %.0f b",
               EnumToString(InpEntryTF), n, g_spreadRef / _Point);
   return(true);
  }

//+------------------------------------------------------------------+
//| Spread uzavrene svicky zadaneho TF v cene.                       |
//| Historicka svicka nese vlastni spread, takze se na ni nemusi     |
//| aplikovat dnesni median: ten se s casem posouva, a protoze se    |
//| pricita k historickemu high, menil uzavreny swing stav           |
//| "prorazeno / neprorazeno" bez jedineho pohybu ceny.              |
//| Kdyz broker spread do historie neplni, pouzije se median.        |
//|  tf, shift - svicka                                              |
//+------------------------------------------------------------------+
double BarSpread(const ENUM_TIMEFRAMES tf, const int shift)
  {
   const int sp = iSpread(_Symbol, tf, shift);
   return(sp > 0 ? (double)sp * _Point : ReferenceSpread());
  }

//--- Totez pro svicku, kterou uz ma volajici nactenou v poli
double RatesSpread(const MqlRates &r)
  {
   return(r.spread > 0 ? (double)r.spread * _Point : ReferenceSpread());
  }

//+------------------------------------------------------------------+
//| Spread pouzity pri prepoctu bidu na exekucni cenu.               |
//| Zamerne to NENI okamzity spread: jedina spicka pri rolloveru by  |
//| jinak prohlasila za prorazene i swingy stovky bodu daleko a      |
//| uroven prurazu by odskocila na davno neplatny swing (viz         |
//| SampleSpread). Dokud neni nasbiran zadny vzorek, bere se         |
//| aktualni hodnota - lepsi nez nula, ktera by znamenala plneni     |
//| nakupu presne na bidu.                                           |
//+------------------------------------------------------------------+
double ReferenceSpread()
  {
   return(g_spreadRef > 0.0 ? g_spreadRef : CurrentSpread());
  }

//+------------------------------------------------------------------+
//| Prepocet bidove ceny na cenu, za kterou se dany smer skutecne    |
//| plni. Graf i historie jsou v BID, ale BuyStop se plni za ASK -   |
//| kdyz se pruraz nahoru meril bidem, nakup se plnil uz o spread    |
//| POD urovni a zadna svicka pak pruraz nezaznamenala.              |
//| Spread si vybira volajici podle toho, co testuje:                |
//|   - probihajici tick -> CurrentSpread (z bidu vyjde presne ask)  |
//|   - uzavrena svicka  -> BarSpread / RatesSpread (spread te svicky)|
//|   - jinak            -> ReferenceSpread (median vzorku)          |
//| Jediny medianovy spread pro vsechno drive znamenal dvoji chybu:  |
//| na ziveho ticku prohlasil uroven za prorazenou driv, nez k ni    |
//| ask dosahl, a na historicke svicce menil jeji stav pri kazdem    |
//| posunu medianu, tedy bez jedineho pohybu ceny.                   |
//|  isBuy    - smer obchodu                                         |
//|  bidPrice - cena v bidovem vyjadreni (high svicky, tick, close)  |
//|  spread   - spread platny pro tuto cenu                          |
//+------------------------------------------------------------------+
double ExecPrice(const bool isBuy, const double bidPrice, const double spread)
  {
   return(isBuy ? bidPrice + spread : bidPrice);
  }

//+------------------------------------------------------------------+
//| Test "cena je za urovni prurazu".                                |
//| Jedina definice pro vsechny detektory - drive byla tataz         |
//| nerovnost opsana na peti mistech a kopie se uz rozesly (jednou   |
//| ostre, jindy neostre, jednou proti bidu, jindy proti asku),      |
//| takze si stavy "nabito / prorazeno / navrh plati" odporovaly.    |
//| Porovnava se neostre, protoze STOP prikaz se plni uz pri         |
//| dosazeni sve ceny.                                               |
//|  isBuy    - smer obchodu                                         |
//|  bidPrice - testovana cena v bidovem vyjadreni                   |
//|  level    - uroven prurazu                                       |
//|  buffer   - rezerva nad (pod) urovni v cene                      |
//|  spread   - spread platny pro testovanou cenu (viz ExecPrice)    |
//+------------------------------------------------------------------+
bool PriceBeyondLevel(const bool isBuy, const double bidPrice,
                      const double level, const double buffer, const double spread)
  {
   if(level <= 0.0 || bidPrice <= 0.0)
      return(false);
   const double price = ExecPrice(isBuy, bidPrice, spread);
   return(isBuy ? (price >= level + buffer) : (price <= level - buffer));
  }

//+------------------------------------------------------------------+
//| Jmeno globalni promenne terminalu, ve ktere je ulozena uz        |
//| obchodovana uroven daneho smeru.                                 |
//| Priznak v pameti experta restart neprezije, takze by se po       |
//| restartu tataz uroven obchodovala podruhe.                       |
//|  isBuy - smer obchodu                                            |
//+------------------------------------------------------------------+
string TakenVarName(const bool isBuy)
  {
   return("PUNTIKY_" + _Symbol + "_" + IntegerToString(InpMagic) +
          (isBuy ? "_BUY" : "_SELL"));
  }

//--- Zapamatuje si, ze na dane urovni uz strategie obchodovala
void MarkLevelTaken(const bool isBuy, const double level)
  {
   if(level > 0.0)
      GlobalVariableSet(TakenVarName(isBuy), level);
  }

//+------------------------------------------------------------------+
//| Obchodovalo se uz na teto urovni? (prezije restart terminalu)    |
//| Zaznam v globalni promenne se overuje proti historii uctu:       |
//| verze do 1.18 po vyplneni ukladala AKTUALNI uroven misto te, na  |
//| ktere obchod vznikl, takze v terminalu muze lezet zaznam o       |
//| urovni, na ktere nikdo neobchodoval - a ta by zustala            |
//| zablokovana, dokud by ji nekdo rucne nesmazal (F3). Zaznam bez   |
//| odpovidajiciho obchodu se proto zahodi.                          |
//| Zaznam se maze jen tehdy, kdyz historie SKUTECNE odpovedela.     |
//| Prazdna odpoved neni dukaz: po pripojeni nebo restartu nemusi byt|
//| historie uctu jeste dosynchronizovana, a protoze zaznam je jedina|
//| ochrana proti druhemu vstupu na teze urovni (napr. kdyz pruraz    |
//| zustal pri spreadove spicce nezdetekovany), jeho nevratne smazani |
//| naslepo by tuhle ochranu zahodilo.                                |
//|  isBuy     - smer obchodu, level - uroven prurazu                |
//|  levelTime - cas svicky urovne (obchod na ni mohl vzniknout az   |
//|              po ni, starsi historie se neprochazi)               |
//+------------------------------------------------------------------+
bool LevelWasTaken(const bool isBuy, const double level, const datetime levelTime)
  {
   if(level <= 0.0)
      return(false);
   double stored = 0.0;
   if(!GlobalVariableGet(TakenVarName(isBuy), stored))
      return(false);
   if(!PriceWithin(stored, level, 1.0))
      return(false);

   const int check = LevelRecordCheck(isBuy, level, levelTime);
   if(check != 0)
      return(true);      // potvrzeno, nebo se to nedalo zjistit

   GlobalVariableDel(TakenVarName(isBuy));
   PrintFormat("PUNTIKY: záznam o obchodované úrovni %s %s nemá v historii žádný "
               "obchod, zahozen.", isBuy ? "BUY" : "SELL", DoubleToString(level, _Digits));
   return(false);
  }

//+------------------------------------------------------------------+
//| Co rika historie uctu o obchodu na dane urovni?                  |
//| Prochazi obchody od casu svicky urovne (drivejsi k ni patrit     |
//| nemohou) a hleda VSTUP teto strategie ve spravnem smeru s cenou  |
//| za urovni v toleranci EntryBelongsToLevel. Na nettingovem uctu je|
//| vstupem i obrat pozice (DEAL_ENTRY_INOUT).                       |
//|  isBuy - smer, level - uroven prurazu, since - cas svicky urovne |
//| Vraci  1 = obchod nalezen (zaznam sedi),                         |
//|        0 = historie je k dispozici a obchod v ni neni,           |
//|       -1 = historii nejde precist nebo je prazdna, takze se z ni |
//|            nic vyvodit neda (po pripojeni byva jeste             |
//|            nedosynchronizovana).                                 |
//+------------------------------------------------------------------+
int LevelRecordCheck(const bool isBuy, const double level, const datetime since)
  {
   // Horni mez s rezervou - historie se vybira po posledni obchod
   if(!HistorySelect(since, TimeCurrent() + 86400))
      return(-1);

   const int total = HistoryDealsTotal();
   if(total <= 0)
      return(-1);      // prazdny vyber neni dukaz neexistence obchodu

   const long wantType = isBuy ? DEAL_TYPE_BUY : DEAL_TYPE_SELL;
   for(int i = total - 1; i >= 0; i--)
     {
      const ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
         continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic)
         continue;
      const long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT)
         continue;
      if(HistoryDealGetInteger(ticket, DEAL_TYPE) != wantType)
         continue;
      if(EntryBelongsToLevel(isBuy, HistoryDealGetDouble(ticket, DEAL_PRICE), level))
         return(1);
     }
   return(0);
  }

//+------------------------------------------------------------------+
//| Patri vstup na dane cene k dane urovni prurazu?                  |
//| Vstup lezi vzdy za urovni: STOP prikaz presne o buffer, trzni    |
//| vstup (rezim M1) nejdal o InpMaxLevelOffset (viz EntryBlockReason)|
//| a k tomu se pripousti skluz pro pripad, ze se misto ceny prikazu |
//| porovnava cena obchodu. Kdyz uroven lezi az za vstupem (zaporny  |
//| odstup) nebo je dal, obchod k teto urovni nepatri - vznikl na    |
//| jine, napr. na te, kterou uz nahradil dalsi swing.               |
//|  isBuy - smer obchodu, entry - cena vstupu (prikazu nebo obchodu)|
//|  level - uroven prurazu, proti ktere se vstup posuzuje           |
//+------------------------------------------------------------------+
bool EntryBelongsToLevel(const bool isBuy, const double entry, const double level)
  {
   if(level <= 0.0 || entry <= 0.0)
      return(false);

   const double offset    = isBuy ? (entry - level) : (level - entry);
   const double tolerance = g_breakBuffer + g_maxLevelOffset + InpSlippage * _Point;
   return(offset >= 0.0 && offset <= tolerance);
  }

//+------------------------------------------------------------------+
//| Prepocet kanalu jednoho timeframu.                               |
//| Kanaly ostatnich timeframu zustanou ve spolecnem poli nedotcene  |
//| (viz PuntikyReplaceSlot) - novy bar M15 nesmi zahodit kanaly H4, |
//| ktere se prepocitavaji o rad pomaleji.                           |
//|  slot - poradi timeframu v g_chTF (zaroven tfIdx kanalu)         |
//| Vraci pocet analyzovanych svicek (0 = data nestacila).           |
//+------------------------------------------------------------------+
int RecalcChannelSlot(const int slot)
  {
   SChannel part[];

   MqlRates rates[];
   const int copied = LoadClosedBars(g_chTF[slot], InpLookbackBars, rates);
   if(copied < PUNTIKY_MIN_BARS)
     {
      // Bez dat se stary vysledek TOHOTO timeframu zahodi. Kdyby v poli
      // zustal, kreslily by se v grafu kanaly, ktere uz nikdo nepocita,
      // a panel by k nim hlasil "zadny kanal".
      PuntikyReplaceSlot(g_channels, slot, part);
      g_stats[slot].Reset();
      PrintFormat("PUNTIKY: málo dat %s (%d svíček), kanály tohoto timeframu zrušeny.",
                  EnumToString(g_chTF[slot]), copied);
      return(0);
     }

   // Kanaly jsou vedene v indexech tohoto pole - referencni bar se musi
   // zapamatovat, aby sly hrany vyhodnotit i mezi prepocty
   g_channelRefTime[slot] = rates[copied - 1].time;
   g_channelRefIdx[slot]  = copied - 1;

   // Kanaly se hledaji ve vice meritkach, aby vznikl i kanal v kanalu
   PuntikyBuildChannels(rates, g_chParams, InpSwingDepth, part, g_stats[slot]);

   // Az ted se kanaly oznaci timeframem - modul o slotech nevi a
   // indexy iA/iB/iC bez nej neni proti cemu vyhodnotit
   for(int i = 0; i < ArraySize(part); i++)
      part[i].tfIdx = slot;

   PuntikyReplaceSlot(g_channels, slot, part);
   return(copied);
  }

//+------------------------------------------------------------------+
//| Prepocet kanalu vsech zapnutych timeframu a jejich vykresleni.   |
//|  slots - pro ktere timeframy se ma prepocet spustit; prazdne     |
//|          pole (nebo delka 0) znamena vsechny                     |
//+------------------------------------------------------------------+
void RecalcChannels(const bool &slots[])
  {
   // ATR se cte jednou za prepocet a odtud ho berou vsichni
   // (vypocet, diagnostika i kresleni)
   RefreshATR();

   const int mask = ArraySize(slots);
   int bars = 0;
   for(int s = 0; s < g_chTFCount; s++)
     {
      if(mask > 0 && s < mask && !slots[s])
         continue;
      const int copied = RecalcChannelSlot(s);
      if(copied > bars)
         bars = copied;
     }

   // Vyber "kanalu, uvnitr ktereho lezi pruraz" bere prvni vyhovujici,
   // a hlavni kanal se kresli silnejsi carou - oboji predpoklada pole
   // serazene podle skore. Po slouceni timeframu se proto radi znovu.
   PuntikySortByScoreDesc(g_channels);

   PrintDiagnostics(bars);
   RedrawChannels();

   //--- Periodicky snimek grafu pro ladeni
   if(InpShotEveryBars > 0)
     {
      g_barsSinceShot++;
      if(g_barsSinceShot >= InpShotEveryBars)
        {
         g_barsSinceShot = 0;
         SaveScreenshot("periodický");
        }
     }
  }

//+------------------------------------------------------------------+
//| Prepocet kanalu vsech timeframu naraz (start, prvni vypocet).    |
//+------------------------------------------------------------------+
void RecalcChannels()
  {
   bool all[];
   RecalcChannels(all);
  }

//+------------------------------------------------------------------+
//| Vypise do logu, kolik kandidatu padlo na kterem filtru a jak     |
//| vypadaji vybrane kanaly. Z rozlozeni zamitnuti je hned videt,    |
//| ktery prah je uzkym hrdlem detekce.                              |
//| Filtry se vypisuji ZVLAST za kazdy zapnuty timeframe - souhrn by |
//| zakryl prave to podstatne, tedy ze kandidaty zahazuje jiny prah  |
//| na M1 a jiny na H1.                                              |
//|  bars - kolik svicek nejdelsi rada TF kanalu mela                |
//+------------------------------------------------------------------+
void PrintDiagnostics(const int bars)
  {
   if(!InpDiagnostics)
      return;

   PrintFormat("PUNTIKY diag: kanály %s (%d svíček), reliéf %s, ATR %s %.2f",
               TFListText(g_chTF, g_chTFCount), bars,
               InpUseRelief ? TFListText(g_relTF, g_relTFCount) : "vypnuto",
               TFText(g_refTF), g_atr);

   for(int s = 0; s < g_chTFCount; s++)
     {
      PrintFormat("PUNTIKY diag: kanály %s - kombinací A-C %d, zamítnuto: bod B %d, "
                  "délka %d, stáří %d, šířka %d, cena mimo %d, opory %d, "
                  "proříznuto %d, dotyky %d, uvnitř %d -> prošlo %d, vybráno %d",
                  TFText(g_chTF[s]), g_stats[s].generated, g_stats[s].noB,
                  g_stats[s].span, g_stats[s].age, g_stats[s].width,
                  g_stats[s].outside, g_stats[s].anchors, g_stats[s].pierced,
                  g_stats[s].touches, g_stats[s].containment,
                  g_stats[s].passed, g_stats[s].selected);

      // Horizont projekce prekazek - odvozuje se z delky vstupu a ATR,
      // takze na kazdem nastroji i timeframu vyjde jinak (viz ProjBars)
      PrintFormat("PUNTIKY diag: projekce překážek %.2f svíčky %s (strop %d svíček %s, "
                  "vstup %d b, ATR %.2f)",
                  ProjBars(g_chTF[s]), TFText(g_chTF[s]),
                  InpEdgeProjBars, TFText(g_refTF), InpMaxEntryPoints, g_atr);
     }

   if(InpUseRelief)
     {
      PrintFormat("PUNTIKY diag: reliéf - přímek celkem %d", ReliefCount());

      for(int s = 0; s < g_relTFCount; s++)
        {
         // "prošlo" je pocet skutecnych kandidatu, ne pocet dvojic, ktere
         // prosly filtry - vejir primek z jedne kotvy da jednoho kandidata
         // a ostatni se do nej slouci (proto je uvedeno i "sloučeno")
         PrintFormat("PUNTIKY diag: reliéf %s - dvojic %d, délka %d, stáří %d, drift %d, "
                     "daleko od ceny %d, nesedí na ceně %d, proraženo %d, střed %d, "
                     "dotyky %d -> prošlo %d (sloučeno %d), vybráno %d",
                     TFText(g_relTF[s]),
                     g_reliefStats[s].pairs, g_reliefStats[s].span, g_reliefStats[s].age,
                     g_reliefStats[s].drift, g_reliefStats[s].farPrice,
                     g_reliefStats[s].looseGap, g_reliefStats[s].pierced,
                     g_reliefStats[s].midTouch, g_reliefStats[s].touches,
                     g_reliefStats[s].passed, g_reliefStats[s].merged,
                     g_reliefStats[s].selected);

         // Ktere meze zrovna plati - bez toho se ladi naslepo, protoze
         // bodova mez a nasobek ATR daji na kazdem nastroji i timeframu
         // jine cislo (viz PuntikyReliefTol a PuntikyReliefDriftLimit).
         // Hvezdicka znaci, ze rozhodl nasobek ATR, ne zadana bodova mez.
         SReliefParams p;
         ReliefParamsForSlot(s, p);
         PrintFormat("PUNTIKY diag: reliéf %s - ATR %.2f, proříznutí %.0f b%s, "
                     "knot %.0f b%s, dotyk %.0f b%s, drift %.0f b%s, "
                     "od ceny %.0f b%s, odstup %.0f b%s",
                     TFText(g_relTF[s]), p.atr,
                     p.pierceTol / _Point, p.pierceTol > g_reliefParams.pierceTol ? " *" : "",
                     p.wickTol   / _Point, p.wickTol   > g_reliefParams.wickTol   ? " *" : "",
                     p.touchTol  / _Point, p.touchTol  > g_reliefParams.touchTol  ? " *" : "",
                     PuntikyReliefDriftLimit(p) / _Point,
                     PuntikyReliefDriftLimit(p) > g_reliefParams.maxDrift ? " *" : "",
                     PuntikyReliefDistLimit(p) / _Point,
                     PuntikyReliefDistLimit(p) > g_reliefParams.maxDist ? " *" : "",
                     PuntikyReliefGapLimit(p) / _Point,
                     PuntikyReliefGapLimit(p) > g_reliefParams.maxGap ? " *" : "");
        }

      double relBarNow[], relBarProj[];
      ReliefBarIndexes(relBarNow, relBarProj);
      for(int i = 0; i < ReliefCount(); i++)
        {
         const int tf = g_relief[i].tfIdx;
         if(tf < 0 || tf >= g_relTFCount)
            continue;

         PrintFormat("PUNTIKY diag: reliéf %d %s (%s) %s @ %s -> %s @ %s, dotyků %d, "
                     "záběr %d barů, stáří %d barů, přilnutí %.0f b, přesah %.0f b, nyní %s",
                     i + 1, TFText(g_relTF[tf]),
                     g_relief[i].isHigh ? "odpor" : "podpora",
                     DoubleToString(g_relief[i].p1, _Digits),
                     TimeToString(g_relief[i].t1, TIME_DATE | TIME_MINUTES),
                     DoubleToString(g_relief[i].p2, _Digits),
                     TimeToString(g_relief[i].t2, TIME_DATE | TIME_MINUTES),
                     g_relief[i].touches, g_relief[i].spanBars, g_relief[i].ageBars,
                     g_relief[i].meanGap / _Point,
                     g_relief[i].maxOver / _Point,
                     DoubleToString(g_relief[i].ValueAtBar(relBarNow[tf]), _Digits));
        }
     }

   for(int i = 0; i < ChannelCount(); i++)
     {
      const int chTf = g_channels[i].tfIdx;
      if(chTf < 0 || chTf >= g_chTFCount)
         continue;

      PrintFormat("PUNTIKY diag: kanál %d %s (měřítko %d, %s) A %s @ %s | B %s @ %s | C %s @ %s",
                  i + 1, TFText(g_chTF[chTf]), g_channels[i].scaleIdx,
                  g_channels[i].baseIsLow ? "LOW základna" : "HIGH základna",
                  DoubleToString(g_channels[i].pA, _Digits),
                  TimeToString(g_channels[i].tA, TIME_DATE | TIME_MINUTES),
                  DoubleToString(g_channels[i].pB, _Digits),
                  TimeToString(g_channels[i].tB, TIME_DATE | TIME_MINUTES),
                  DoubleToString(g_channels[i].pC, _Digits),
                  TimeToString(g_channels[i].tC, TIME_DATE | TIME_MINUTES));

      PrintFormat("PUNTIKY diag: kanál %d - šířka %.0f b, dotyků mimo opory %d, uvnitř %.0f %%, "
                  "délka %d barů, stáří %d barů, skóre %.2f, body po C %d",
                  i + 1, g_channels[i].width / _Point, g_channels[i].touches,
                  g_channels[i].containment * 100.0, g_channels[i].spanBars,
                  g_channels[i].ageBars, g_channels[i].score, g_channels[i].extraCount);
     }
  }

//+------------------------------------------------------------------+
//| Ulozi snimek grafu do MQL5/Files pro ladeni.                     |
//|  reason - duvod ulozeni (jde do logu)                            |
//+------------------------------------------------------------------+
void SaveScreenshot(const string reason)
  {
   const int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   const int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(w <= 0 || h <= 0)
      return;

   if(ChartScreenShot(0, InpShotFileName, w, h, ALIGN_RIGHT))
      PrintFormat("PUNTIKY: snímek grafu uložen (%s) -> MQL5/Files/%s  [%dx%d]",
                  reason, InpShotFileName, w, h);
   else
      PrintFormat("PUNTIKY: snímek grafu se nepodařilo uložit, chyba %d", GetLastError());
  }

//+------------------------------------------------------------------+
//| Zkontroluje pozadavek na snimek grafu.                           |
//| Pozadavek se podava vytvorenim souboru InpShotRequestFile ve     |
//| slozce MQL5/Files - expert ho zpracuje a soubor smaze.           |
//+------------------------------------------------------------------+
void CheckScreenshotRequest()
  {
   if(!InpShotOnRequest)
      return;
   if(!FileIsExist(InpShotRequestFile))
      return;

   FileDelete(InpShotRequestFile);
   SaveScreenshot("na vyžádání");
  }

//+------------------------------------------------------------------+
//| Prekresleni vsech kanalu (HIGH a LOW usecky + opory A B C D).    |
//|                                                                  |
//| Objekty se ruSi a zakladaji ZNOVU, ne aktualizuji na miste. MT5  |
//| kresli objekty v poradi, v jakem vznikly, takze nove zalozeny    |
//| kanal skonci NAD reliefnimi primkami - to je zamer: kdyz hrana   |
//| kanalu a reliefni primka lezi na sobe, ma byt videt kanal.       |
//| Pri aktualizaci na miste by nahore zustal ten, kdo vznikl        |
//| naposledy, tedy po prepoctu reliefu prave primka.                |
//| Vytvari se par desitek objektu jednou za bar TF kanalu (a po     |
//| prepoctu reliefu), coz je proti panelu, ktery bezi kazdou        |
//| sekundu, zanedbatelne. Vse probiha pred jedinym ChartRedraw,     |
//| takze graf pri prekresleni neblika.                              |
//+------------------------------------------------------------------+
void RedrawChannels()
  {
   const int total = ChannelCount();
   const int count = InpShowChannels ? total : 0;

   // Prava hranice usecek - kousek do budoucnosti, aby bylo videt,
   // kam kanal smeruje. Cas i index musi ukazovat na tentyz bar,
   // jinak by usecka koncila jinde, nez kam ji expert pocita.
   // Kazdy timeframe ma vlastni delku baru i vlastni indexovou osu,
   // takze se konec pocita pro kazdy zvlast a kanal si ho vybere
   // podle sveho tfIdx.
   datetime tEnd[];
   double   barEnd[];
   ArrayResize(tEnd,   g_chTFCount);
   ArrayResize(barEnd, g_chTFCount);
   for(int s = 0; s < g_chTFCount; s++)
     {
      tEnd[s]   = FutureBarTime(g_chTF[s], InpForwardBars);
      barEnd[s] = ChannelBarNow(s) + (double)InpForwardBars;
     }

   //--- Stare usecky i popisky pryc, aby ty nove vznikly az ted
   PuntikyDeleteObjects("CH");
   PuntikyDeleteObjects("PT");

   //--- Nejprve usecky vsech kanalu
   for(int i = 0; i < count; i++)
     {
      const int tf = g_channels[i].tfIdx;
      if(tf < 0 || tf >= g_chTFCount)
         continue;
      PuntikyDrawChannel(g_channels[i], i, tEnd[tf], barEnd[tf], InpColorHigh, InpColorLow);
     }

   //--- Popisky opor se sesbiraji ze vsech kanalu najednou a teprve pak
   //--- vykresli - popisky padnouci na stejne misto se slouci do jednoho
   //--- textu (napr. "E1 E3"), takze se pri sdilene opore neprepisuji.
   //--- Ridi se VYHRADNE vstupem InpShowPoints: drive se pocet bral z
   //--- prepinace usecek, takze cisty graf jen s pismeny A B C D
   //--- (InpShowChannels = false) nevykreslil vubec nic.
   if(InpShowPoints && total > 0)
     {
      SChannelLabel items[];
      for(int i = 0; i < total; i++)
         PuntikyCollectChannelLabels(g_channels[i], i, items);

      // Tolerance slucovani vychazi z ATR, aby sedela na volatilite trhu
      const double mergeTol = (g_atr > 0.0) ? g_atr * InpLabelMergeATR
                                            : PUNTIKY_LABEL_FALLBACK * _Point;
      PuntikyDrawLabels(items, InpColorPoint, InpPointFontSize, mergeTol);
     }

   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Plny prepocet reliefnich primek jednoho timeframu.               |
//| Primky vznikaji z hlavnich swingu tohoto TF a musi cenu obalovat |
//| - prorazena primka uz neni prekazkou a mezi kandidaty se         |
//| nedostane. Primky ostatnich timeframu zustanou nedotcene.        |
//|  slot - poradi timeframu v g_relTF (zaroven tfIdx primek)        |
//| Vraci false, kdyz se prepocet odlozil (ceka se na ATR).          |
//+------------------------------------------------------------------+
bool RecalcReliefSlot(const int slot)
  {
   SReliefLine part[];

   // Bez ATR tohoto timeframu by tolerance spadly na pouhou bodovou mez
   // a s ni postavene primky by v pameti zustaly az do dalsiho plneho
   // prepoctu - na D1 klidne tri tydny. Prepocet se proto odlozi:
   // pocitadlo ani posledni zkontrolovana svicka se neposunou, takze to
   // dalsi tick zkusi znovu. Handle na cizim TF se pocita asynchronne,
   // jde tedy o par ticku po startu.
   if(!RefreshReliefATR(slot))
     {
      if(!g_relAtrWarned[slot])
        {
         g_relAtrWarned[slot] = true;
         PrintFormat("PUNTIKY: čeká se na dopočet ATR %s, reliéf tohoto timeframu "
                     "se spočítá s prvními daty.", TFText(g_relTF[slot]));
        }
      return(false);
     }
   g_relAtrWarned[slot] = false;

   g_reliefBarsSinceBuild[slot] = 0;
   g_reliefCheckedBar[slot]     = iTime(_Symbol, g_relTF[slot], 1);

   MqlRates rates[];
   const int copied = LoadClosedBars(g_relTF[slot], InpReliefLookback, rates);
   if(copied < PUNTIKY_MIN_BARS)
     {
      // Stejne jako u kanalu: bez dat se stary vysledek TOHOTO
      // timeframu zahodi, jinak by v grafu zustaly primky, ktere uz
      // nikdo neprepocitava
      PuntikyReplaceSlot(g_relief, slot, part);
      g_reliefStats[slot].Reset();
      return(true);
     }

   // Primky jsou vedene v indexech tohoto pole (viz BarIndexNow)
   g_reliefRefTime[slot] = rates[copied - 1].time;
   g_reliefRefIdx[slot]  = copied - 1;

   // Tolerance se odvozuji od ATR tohoto timeframu (viz ReliefParamsForSlot)
   SReliefParams p;
   ReliefParamsForSlot(slot, p);
   PuntikyBuildReliefLines(rates, p, part, g_reliefStats[slot]);

   // Az ted se primky oznaci timeframem - modul o slotech nevi a
   // indexy i1/i2 bez nej neni proti cemu vyhodnotit
   for(int i = 0; i < ArraySize(part); i++)
      part[i].tfIdx = slot;

   PuntikyReplaceSlot(g_relief, slot, part);
   return(true);
  }

//+------------------------------------------------------------------+
//| Prepocet reliefnich primek vsech zapnutych timeframu.            |
//|                                                                  |
//| Plny prepocet overuje kazdeho kandidata pres celou historii      |
//| daneho TF - pri vychozich 7200 barech a ctyrech meritkach jsou   |
//| to radove miliony pruchodu bary a expert po tu dobu nezpracovava |
//| ticky. Na kazdem baru je to zbytecne (hlavni swingy se tak       |
//| rychle nemeni), takze se cely prepocet dela jen jednou za N baru |
//| daneho timeframu a mezi tim se hlida to podstatne: prorazena     |
//| primka musi zmizet hned.                                         |
//| Jakmile nektera drzena primka padne, prepocet jejiho timeframu   |
//| se udela HNED - jinak by na jejim miste az 15 baru nebylo nic a  |
//| graf i zkraceni PT by zustaly bez reliefu, prestoze cerstva      |
//| primka existuje. Revalidace zaroven posouva pocitadlo baru.      |
//| Pocitadlo i revalidace bezi po timeframech: prepocet H1 se nesmi |
//| spoustet kazdou minutu jen proto, ze pribyl bar M1.              |
//|  force   - true = plny prepocet vsech timeframu hned, bez ohledu |
//|            na pocitadla baru (pouziva se pri startu)             |
//|  dropped - revalidace uz probehla drive v temze ticku (viz       |
//|            OnTick); pro kazdy timeframe rika, jestli pri ni      |
//|            nejaka primka odpadla. Prazdne pole = revalidace      |
//|            jeste nebezela a spusti se zde.                       |
//+------------------------------------------------------------------+
void RecalcRelief(const bool force, const bool &dropped[])
  {
   // Bez hlidani reliefu neni co pocitat ani kreslit. Prazdne pole se
   // uklidi jednou - drive se kazdou minutu smazaly a znovu vykreslily
   // vsechny objekty kanalu (pres sto volani do terminalu) jen kvuli
   // vyprazdneni pole, ktere uz prazdne bylo.
   if(!InpUseRelief)
     {
      if(ReliefCount() > 0)
        {
         ArrayResize(g_relief, 0);
         for(int s = 0; s < PUNTIKY_TF_SLOTS; s++)
            g_reliefStats[s].Reset();
         DrawRelief();
        }
      return;
     }

   // Kdyz revalidace jeste nebezela, spusti se ted - jinak by se
   // pocitadla baru nikdy neposunula a plny prepocet by nikdy nenastal
   bool fell[];
   if(!force && ArraySize(dropped) < g_relTFCount)
      RevalidateRelief(fell);
   else
     {
      ArrayResize(fell, g_relTFCount);
      for(int s = 0; s < g_relTFCount; s++)
         fell[s] = (!force && s < ArraySize(dropped)) ? dropped[s] : false;
     }

   bool changed = false;
   for(int s = 0; s < g_relTFCount; s++)
     {
      // Slot, ktery minule cekal na ATR, se musi zkusit znovu bez ohledu
      // na pocitadlo baru - jeho prepocet se neuskutecnil, takze by
      // pocitadlo (jeste nevynulovane) rebuild odlozilo az za 15 baru
      const bool waiting = (g_relAtr[s] <= 0.0);
      if(!force && !waiting && !fell[s] &&
         g_reliefBarsSinceBuild[s] < PUNTIKY_RELIEF_REBUILD_BARS)
         continue;

      // Odlozeny prepocet (ceka se na ATR) nic neprekreslil
      if(RecalcReliefSlot(s))
         changed = true;
     }

   // Kresli se az po vsech timeframech - kazde volani DrawRelief
   // znamena smazani a vytvoreni vsech objektu reliefu i kanalu
   if(changed)
      DrawRelief();

   // Diagnostiku vypisuje prepocet kanalu, jenze pri vypnutych kanalech
   // uz zadny nebezi a s nim by zmizel i vypis filtru reliefu - prave
   // ten, podle ktereho se prahy ladi. V tom pripade ji vypise prepocet
   // reliefu, aby v logu nechybela.
   if(changed && g_chTFCount < 1)
      PrintDiagnostics(0);
  }

//+------------------------------------------------------------------+
//| Plny prepocet reliefu vsech timeframu (start, prvni vypocet).    |
//+------------------------------------------------------------------+
void RecalcRelief()
  {
   bool none[];
   RecalcRelief(true, none);
  }

//+------------------------------------------------------------------+
//| Levne prekontroluje drzene reliefni primky mezi plnymi prepocty. |
//| Overuje presne ty filtry, ktere se meni s kazdym novym barem:    |
//| prorazeni nove uzavrenou svickou, vzdaleni od druhe opory a jeji |
//| stari. Predikaty jsou metody SReliefLine, tedy tytez, ktere      |
//| pouziva plny prepocet - drive to byly kopie a jejich rozejiti by |
//| znamenalo primky blikajici kazdych PUNTIKY_RELIEF_REBUILD_BARS.  |
//| Odlozit se smi jen OBJEVENI nove primky - novy swing potrebuje   |
//| k potvrzeni aspon InpReliefSwingDepth baru, takze o nej neni     |
//| nouze. Zanik primky odlozit nelze: prorazena primka uz prekazkou |
//| neni a nesmi dal zkracovat PT.                                   |
//| Prochazi VSECHNY svicky uzavrene od posledni kontroly, ne jen tu |
//| posledni: po vypadku spojeni vznikne bez jedineho ticku i vic    |
//| baru najednou a primka prorazena v nekterem z nich by jinak      |
//| zustala v pameti az do plneho prepoctu.                          |
//| Volani navic (dvakrat v jednom ticku) nic nestoji - kdyz od      |
//| posledni kontroly nepribyla svicka, funkce se hned vrati.        |
//| Kazdy timeframe ma vlastni pocitadlo i vlastni posledni           |
//| zkontrolovanou svicku: novy bar M1 nesmi posunout cyklus         |
//| prepoctu primek H1 ani je kontrolovat proti minutovym svickam.   |
//|  dropped - out: pro kazdy zapnuty timeframe true, kdyz v nem     |
//|            nejaka primka odpadla (volajici pak spusti jeho plny  |
//|            prepocet hned)                                        |
//| Vraci true, kdyz odpadla primka v kterémkoli timeframu.          |
//+------------------------------------------------------------------+
bool RevalidateRelief(bool &dropped[])
  {
   ArrayResize(dropped, g_relTFCount);
   for(int s = 0; s < g_relTFCount; s++)
      dropped[s] = false;

   bool anyDropped = false;

   for(int s = 0; s < g_relTFCount; s++)
     {
      const datetime lastClosed = iTime(_Symbol, g_relTF[s], 1);
      if(lastClosed <= 0 || lastClosed == g_reliefCheckedBar[s])
         continue;

      // Tytez tolerance, se kterymi primky tohoto timeframu vznikly -
      // jinak by je levna kontrola zahazovala prisneji, nez podle ceho
      // je plny prepocet vybral, a primky by kazdych par baru blikaly
      SReliefParams p;
      ReliefParamsForSlot(s, p);
      const double tol        = p.pierceTol;
      const double driftLimit = PuntikyReliefDriftLimit(p);
      const double distLimit  = PuntikyReliefDistLimit(p);

      // Tataz cena, ke ktere vzdalenost meri plny prepocet (zaver
      // posledni uzavrene svicky) - jinak by se obe cesty rozesly a
      // primka by mezi prepocty blikala
      const double lastPrice = iClose(_Symbol, g_relTF[s], 1);

      // Kolik svicek se od posledni kontroly uzavrelo. Pocitadlo do
      // plneho prepoctu se zvysuje o skutecny pocet baru, ne o pocet
      // volani - jinak by se cyklus prepoctu pri vypadku spojeni protahl.
      int bars = 1;
      if(g_reliefCheckedBar[s] > 0)
        {
         const int b = Bars(_Symbol, g_relTF[s], g_reliefCheckedBar[s], lastClosed);
         if(b > 1)
            bars = b - 1;
        }
      g_reliefCheckedBar[s]      = lastClosed;
      g_reliefBarsSinceBuild[s] += bars;

      const int cnt = ReliefCount();
      if(cnt <= 0)
         continue;

      // Prochazet vic nez PUNTIKY_RELIEF_REBUILD_BARS svicek nema smysl -
      // pocitadlo uz stejne vynutilo plny prepocet, ktery projde vsechny
      const int    scan   = MathMin(bars, PUNTIKY_RELIEF_REBUILD_BARS);
      const double barNow = ReliefBarNow(s);

      int kept = 0;
      for(int i = 0; i < cnt; i++)
        {
         // Primky ostatnich timeframu se v tomto kole nekontroluji -
         // jejich indexy patri jine casove ose
         if(g_relief[i].tfIdx != s)
           {
            if(kept != i)
               g_relief[kept] = g_relief[i];
            kept++;
            continue;
           }

         // Primka se s kazdym barem vzdaluje od sve druhe opory a ta
         // zaroven starne; za prahem uz to neni relief, ale artefakt.
         // Posledni UZAVRENA svicka lezi o bar zpet za prave otevrenou.
         const double lastBar = barNow - 1.0;
         // Trh se od primky vzdaluje i bez toho, aby ji prorazil - pak
         // uz neni prekazkou a nema dal zkracovat PT ani strasit v grafu
         bool dead = g_relief[i].Drifted(lastBar, driftLimit) ||
                     g_relief[i].Expired(lastBar, p.maxAgeFactor) ||
                     (lastPrice > 0.0 &&
                      g_relief[i].TooFarFrom(lastBar, lastPrice, distLimit));

         // Vsechny svicky uzavrene od posledni kontroly. Jsou to bary za
         // druhou oporou, kde je primka tvrdou hranici i pro knot - proto
         // je tolerance knotu tataz jako u tela.
         for(int sh = scan; sh >= 1 && !dead; sh--)
           {
            const double high  = iHigh(_Symbol,  g_relTF[s], sh);
            const double low   = iLow(_Symbol,   g_relTF[s], sh);
            const double open  = iOpen(_Symbol,  g_relTF[s], sh);
            const double close = iClose(_Symbol, g_relTF[s], sh);
            if(high <= 0.0 || low <= 0.0 || open <= 0.0 || close <= 0.0)
               continue;

            if(g_relief[i].BarPierces(barNow - (double)sh, open, high, low, close, tol, tol))
               dead = true;
           }

         if(dead)
            continue;

         if(kept != i)
            g_relief[kept] = g_relief[i];
         kept++;
        }

      if(kept == cnt)
         continue;

      // Stavy statistiky srovna nasledny plny prepocet tohoto timeframu
      ArrayResize(g_relief, kept);
      dropped[s] = true;
      anyDropped = true;
     }

   return(anyDropped);
  }

//+------------------------------------------------------------------+
//| Vykresleni reliefnich primek                                     |
//+------------------------------------------------------------------+
void DrawRelief()
  {
   const int count = InpShowRelief ? ReliefCount() : 0;
   // Cas i index praveho konce musi ukazovat na tentyz bar (viz
   // RedrawChannels) - jinak by nakreslena primka koncila jinde, nez
   // kam ji expert pocita. Kazdy timeframe ma vlastni delku baru i
   // vlastni indexovou osu, takze se konec pocita pro kazdy zvlast.
   datetime tEnd[];
   double   barEnd[];
   ArrayResize(tEnd,   g_relTFCount);
   ArrayResize(barEnd, g_relTFCount);
   for(int s = 0; s < g_relTFCount; s++)
     {
      tEnd[s]   = FutureBarTime(g_relTF[s], InpReliefForwardBars);
      barEnd[s] = ReliefBarNow(s) + (double)InpReliefForwardBars;
     }

   PuntikyDeleteObjects("REL_");

   for(int i = 0; i < count; i++)
     {
      const int tf = g_relief[i].tfIdx;
      if(tf < 0 || tf >= g_relTFCount)
         continue;

      PuntikyTrendLine(PUNTIKY_PREFIX + "REL_" + IntegerToString(i),
                    g_relief[i].t1, g_relief[i].p1, tEnd[tf],
                    g_relief[i].ValueAtBar(barEnd[tf]),
                    InpColorRelief, 1, STYLE_DOT, true,
                    StringFormat("Reliéfní přímka %s (%s), dotyků %d",
                                 TFText(g_relTF[tf]),
                                 g_relief[i].isHigh ? "odpor" : "podpora",
                                 g_relief[i].touches));
     }

   // Kanal ma na spolecne usecce lezet NAD reliefem, a protoze MT5
   // kresli objekty v poradi vzniku, musi vzniknout az po nem
   RedrawChannels();
  }

//+------------------------------------------------------------------+
//| Vykresleni urovni prurazu (HIGH / LOW svicky TF prurazu)         |
//+------------------------------------------------------------------+
void DrawBreakoutLevels()
  {
   if(!InpShowBreakLevels || g_dir[PUNTIKY_DIR_BUY].level <= 0.0 ||
      g_dir[PUNTIKY_DIR_SELL].level <= 0.0)
     {
      PuntikyDeleteObjects("BRK_");
      return;
     }

   const datetime tTo = FutureBarTime(InpBreakoutTF, 2);

   // Cara zacina u svicky, ze ktere uroven pochazi - u swingoveho
   // rezimu je tak na prvni pohled videt, ktery swing se prorazi
   const SDirection buy  = g_dir[PUNTIKY_DIR_BUY];
   const SDirection sell = g_dir[PUNTIKY_DIR_SELL];

   PuntikyTrendLine(PUNTIKY_PREFIX + "BRK_H", buy.levelTime, buy.level, tTo, buy.level,
                 InpColorBreak, 1, STYLE_DASH, false,
                 "Úroveň průrazu HIGH " + DoubleToString(buy.level, _Digits));
   PuntikyTrendLine(PUNTIKY_PREFIX + "BRK_L", sell.levelTime, sell.level, tTo, sell.level,
                 InpColorBreak, 1, STYLE_DASH, false,
                 "Úroveň průrazu LOW " + DoubleToString(sell.level, _Digits));
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Vykresleni urovni planovaneho vstupu pro oba smery               |
//+------------------------------------------------------------------+
void DrawEntryLevels()
  {
   if(!InpShowEntryLevels)
     {
      PuntikyDeleteObjects("ENT_");
      return;
     }

   const datetime tFrom = iTime(_Symbol, InpBreakoutTF, 0);
   const datetime tTo   = FutureBarTime(InpBreakoutTF, 3);

   PuntikyDrawEntryLevels("BUY",  g_plan[PUNTIKY_DIR_BUY],  tFrom, tTo,
                       InpColorEntry, InpColorSL, InpColorTP, _Digits);
   PuntikyDrawEntryLevels("SELL", g_plan[PUNTIKY_DIR_SELL], tFrom, tTo,
                       InpColorEntry, InpColorSL, InpColorTP, _Digits);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Prorazila cena uroven uz v prave otevrene svicce TF prurazu?     |
//| Zahrnuti otevrene svicky je to, co strategii umoznuje hledat     |
//| dalsi swing hned po prurazu - bez nej by prorazenou uroven       |
//| "videla" az po uzavreni hodinove svicky, tedy az o 59 minut      |
//| pozdeji, a do te doby by nabizela vstup na spotrebovanou uroven. |
//|  isBuy - strana urovne, level - cena urovne                      |
//+------------------------------------------------------------------+
bool LevelBrokenNow(const bool isBuy, const double level)
  {
   if(level <= 0.0)
      return(false);

   // Prave otevrena svicka je "ted", takze se pouziva ZIVY spread.
   // S medianem (ktery byva vetsi nez okamzity spread) expert uroven
   // prohlasil za prorazenou driv, nez k ni ask dosahl.
   const double ext = isBuy ? iHigh(_Symbol, InpBreakoutTF, 0)
                            : iLow(_Symbol, InpBreakoutTF, 0);
   return(PriceBeyondLevel(isBuy, ext, level, g_breakBuffer, CurrentSpread()));
  }

//+------------------------------------------------------------------+
//| Prorazila cena swingovou uroven uz po jejim vzniku?              |
//| Prochazi uzavrene svicky TF prurazu za swingem a pta se i na     |
//| prave otevrenou svicku.                                          |
//|  rates  - svicky TF prurazu, ktere uz ma volajici nactene        |
//|  s      - testovany swing                                        |
//|  isHigh - true = swingovy vrchol (uroven pro nakup)              |
//|  buffer - rezerva nad/pod urovni v cene                          |
//+------------------------------------------------------------------+
bool SwingBroken(const MqlRates &rates[], const SSwing &s, const bool isHigh,
                 const double buffer)
  {
   const int n = ArraySize(rates);
   for(int i = s.index + 1; i < n; i++)
     {
      // Uzavrena svicka se posuzuje SVYM spreadem, ne dnesnim medianem -
      // ten se s casem posouva a menil by stav davno uzavreneho swingu
      const double ext = isHigh ? rates[i].high : rates[i].low;
      if(PriceBeyondLevel(isHigh, ext, s.price, buffer, RatesSpread(rates[i])))
         return(true);
     }
   return(LevelBrokenNow(isHigh, s.price));
  }

//+------------------------------------------------------------------+
//| Najde posledni swingovy vrchol a posledni swingove dno na TF     |
//| prurazu. Prorazi se tedy jen H1 svicka, ktera je zaroven         |
//| swingovym bodem - beznou hodinovou svicku strategie ignoruje.    |
//| Prorazena uroven je spotrebovana, takze se pokracuje             |
//| k predchozimu swingu - typicky vyraznejsimu, ktery je stale      |
//| platnou hranici.                                                 |
//| Vysledek se vraci po stranach: kdyz se jedna strana najit        |
//| nepodari (v silnem trendu jsou vsechny starsi vrcholy prorazene),|
//| druha se presto aktualizuje - drive padl cely prepocet a zamrzla |
//| i strana, ktera cerstvy swing mela.                              |
//|  hi, hiTime - out: cena a cas posledniho platneho vrcholu        |
//|  foundHi    - out: podarilo se vrchol najit?                     |
//|  lo, loTime - out: cena a cas posledniho platneho dna            |
//|  foundLo    - out: podarilo se dno najit?                        |
//+------------------------------------------------------------------+
void FindBreakoutSwings(double &hi, datetime &hiTime, bool &foundHi,
                        double &lo, datetime &loTime, bool &foundLo)
  {
   foundHi = false;
   foundLo = false;

   MqlRates rates[];
   const int copied = LoadClosedBars(InpBreakoutTF, InpBreakLookback, rates);
   if(copied < InpBreakSwingDepth * 2 + 3)
      return;

   SSwing sw[];
   const int ns = PuntikyDetectSwings(rates, InpBreakSwingDepth, sw);
   if(ns < 1)
      return;

   for(int i = ns - 1; i >= 0; i--)
     {
      if(sw[i].isHigh && !foundHi && !SwingBroken(rates, sw[i], true, g_breakBuffer))
        {
         hi      = sw[i].price;
         hiTime  = sw[i].time;
         foundHi = true;
        }
      if(!sw[i].isHigh && !foundLo && !SwingBroken(rates, sw[i], false, g_breakBuffer))
        {
         lo      = sw[i].price;
         loTime  = sw[i].time;
         foundLo = true;
        }
      if(foundHi && foundLo)
         break;
     }
  }

//+------------------------------------------------------------------+
//| Nastavi priznak "uroven prorazena" a pri prvnim prurazu si       |
//| zapamatuje jeho cas. Podle nej pozna rezim M1_CLOSE, jestli      |
//| pruraz patri k prave uzavrene svicce vstupniho TF, nebo je       |
//| starsi a uroven uz svou prilezitost mela (viz EntryBlockReason). |
//|  isBuy  - strana urovne                                          |
//|  broken - novy stav priznaku                                     |
//+------------------------------------------------------------------+
void MarkBroken(const bool isBuy, const bool broken)
  {
   const int idx = DirIdx(isBuy);

   // Cas se zapisuje jen pri PRECHODU do prorazeneho stavu, aby
   // opakovany pruraz teze urovne nepredstiral cerstvy signal
   if(broken && !g_dir[idx].broken)
      g_dir[idx].brokenTime = TimeCurrent();
   if(!broken)
      g_dir[idx].brokenTime = 0;
   g_dir[idx].broken = broken;
  }

//+------------------------------------------------------------------+
//| Ulozi novou uroven prurazu jedne strany a srovna jeji priznaky.  |
//| Priznaky se resetuji jen pri zmene urovne - na jednom swingu se  |
//| tedy obchoduje nejvyse jednou. Jestli uz se na urovni            |
//| obchodovalo, se cte z globalni promenne terminalu, takze to      |
//| prezije i restart (drive to byl jen priznak v pameti a po        |
//| restartu se tataz uroven obchodovala podruhe).                   |
//|  isBuy - strana (true = HIGH uroven pro nakup)                   |
//|  price - cena urovne, levelTime - cas svicky, ze ktere pochazi   |
//+------------------------------------------------------------------+
void ApplyBreakLevel(const bool isBuy, const double price, const datetime levelTime)
  {
   if(price <= 0.0 || levelTime <= 0)
      return;

   const int  idx     = DirIdx(isBuy);
   const bool changed = (levelTime != g_dir[idx].levelTime);

   g_dir[idx].level     = price;
   g_dir[idx].levelTime = levelTime;

   if(changed)
     {
      // Nova uroven zacina s cistymi priznaky vcetne casu prurazu
      MarkBroken(isBuy, false);
      g_dir[idx].taken = LevelWasTaken(isBuy, price, levelTime);
      g_dir[idx].armed = false;
     }

   // Uzavrene svicky TF prurazu uz prosel vyber swingu, zbyva prave
   // otevrena svicka. Pri nezmenene urovni se drzi i to, co mezitim
   // zjistil tick - jinak by se prorazeni pri vypadku dat ztratilo.
   if(!g_dir[idx].broken && LevelBrokenNow(isBuy, price))
      MarkBroken(isBuy, true);
  }

//+------------------------------------------------------------------+
//| Nacte urovne prurazu, srovna priznaky a prekresli je.            |
//| Kazda strana se aktualizuje samostatne (viz FindBreakoutSwings). |
//+------------------------------------------------------------------+
void RefreshBreakoutLevels()
  {
   double   h = 0.0, l = 0.0;
   datetime th = 0, tl = 0;
   bool     foundHi = false, foundLo = false;

   if(InpUseSwingLevels)
     {
      // Proraz se jen swingovy vrchol / dno, ne kazda hodinova svicka
      FindBreakoutSwings(h, th, foundHi, l, tl, foundLo);
     }
   else
     {
      // Zalozni rezim: high/low posledni uzavrene svicky TF prurazu
      h  = iHigh(_Symbol, InpBreakoutTF, 1);
      l  = iLow(_Symbol, InpBreakoutTF, 1);
      th = iTime(_Symbol, InpBreakoutTF, 1);
      tl = th;
      foundHi = (h > 0.0 && th > 0);
      foundLo = (l > 0.0 && tl > 0);
     }

   if(foundHi)
      ApplyBreakLevel(true, h, th);
   if(foundLo)
      ApplyBreakLevel(false, l, tl);

   UpdateArming();

   // Navrhy se prepocitavaji az na konci ticku (viz OnTick) - tady by
   // to bylo uz druhe ze tri volani v jedinem ticku a jeho vysledek by
   // stejne nikdo neprecetl. Volajici si nastavi priznak plansDirty.
   DrawBreakoutLevels();
  }

//+------------------------------------------------------------------+
//| Nastavi priznaky pripravenosti smeru.                            |
//| Smer je "nabity" teprve tehdy, kdyz je cena na spravne strane    |
//| urovne - zabranuje vstupu do jiz probehleho prurazu (napr. po    |
//| vikendovem gapu nebo pri startu experta uprostred pohybu).       |
//| Jakmile cena uroven prorazi, je smer vycerpany - dalsi           |
//| prilezitost prijde az s novym swingem. Bez teto pameti by se     |
//| prikaz zadal znovu pokazde, kdyz se cena k urovni vrati.         |
//+------------------------------------------------------------------+
void UpdateArming()
  {
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0.0)
      return;

   // Probihajici tick se posuzuje ZIVYM spreadem: pro BUY z nej vyjde
   // presne aktualni ask, tedy cena, za kterou by se STOP prikaz
   // vyplnil. S medianem (ktery byva vetsi nez okamzity spread) expert
   // uroven prohlasil za prorazenou driv, nez k ni ask dosahl - lezici
   // prikaz se pak zrusil nebo presunul tesne pred svym vyplnenim a
   // pruraz, na ktery cekal, propasl.
   const double spread = CurrentSpread();

   for(int i = 0; i < 2; i++)
     {
      const bool   isBuy = (i == PUNTIKY_DIR_BUY);
      const double level = g_dir[i].level;
      if(level <= 0.0)
         continue;

      if(PriceBeyondLevel(isBuy, bid, level, g_breakBuffer, spread))
         MarkBroken(isBuy, true);

      // Nabiji se proti exekucni cene smeru: nakup se plni za ask, takze
      // dokud je ask jeste pod urovni, ma pruraz teprve prijit
      const double exec = ExecPrice(isBuy, bid, spread);
      if(isBuy ? (exec <= level) : (exec >= level))
         g_dir[i].armed = true;
     }
  }

//+------------------------------------------------------------------+
//| Prepocita navrhy vstupu pro oba smery a vykresli jejich urovne.  |
//| Navrhy se pocitaji z hypotetickeho vstupu na urovni prurazu,     |
//| takze panel ukazuje parametry obchodu jeste pred jeho vznikem.   |
//+------------------------------------------------------------------+
void RebuildPlans()
  {
   for(int i = 0; i < 2; i++)
     {
      const bool   isBuy = (i == PUNTIKY_DIR_BUY);
      const double level = g_dir[i].level;

      if(level > 0.0)
         g_plan[i] = BuildPlan(isBuy, isBuy ? level + g_breakBuffer : level - g_breakBuffer,
                               level, false);
      else
         ResetPlan(g_plan[i], isBuy);
     }

   // Navrh se zmenil, takze lezici prikazy uz mu nemusi odpovidat.
   // Srovnani se dela jednou za tick v OnTick (viz SyncPendingOrders).
   g_ordersDirty = true;

   DrawEntryLevels();
  }

//+------------------------------------------------------------------+
//| Duvod, proc v danem smeru nelze vstoupit ("" = lze).             |
//| Ochrany jsou na jednom miste pro oba rezimy vstupu - drive je    |
//| kazdy rezim kontroloval jinak: pending rezim vubec necetl        |
//| "nabito" (a zadal prikaz do uz beziciho pohybu), zatimco rezim   |
//| M1 jedinym boolem vypinal rovnou celou sadu ochran a nakupoval   |
//| i na urovni, kterou sam oznacil za prorazenou.                   |
//| Opravneni k obchodovani se zde zamerne netestuje - navrh se ma   |
//| kreslit i v instanci, ktera jen kresli.                          |
//|  isBuy    - smer obchodu                                         |
//|  entry    - planovana cena vstupu                                |
//|  trigger  - uroven prurazu                                       |
//|  atMarket - vstup se otevira na trhu (rezim M1_CLOSE): pruraz    |
//|             prave probehl, takze se netestuje dosazitelnost a    |
//|             priznak "prorazeno" se posuzuje podle casu prurazu,  |
//|             zato se hlida odstup od urovne                       |
//|  block    - out: druh zamitnuti; rozhoduje o osudu uz leziciho   |
//|             prikazu pri rekonciliaci (viz SyncOneDirection)      |
//+------------------------------------------------------------------+
string EntryBlockReason(const bool isBuy, const double entry, const double trigger,
                        const bool atMarket, ENUM_PUNTIKY_BLOCK &block)
  {
   // Vychozi je "uroven neni k dispozici" - prikaz na ni lezet nema
   block = PUNTIKY_BLOCK_LEVEL;

   const int idx = DirIdx(isBuy);

   if(isBuy ? !InpAllowBuy : !InpAllowSell)
      return("směr vypnut");

   // Otevrena pozice navrh rusi - dokud bezi obchod, neni co nabizet
   if(CountPositions() >= InpMaxPositions)
      return("pozice již otevřena");

   // Na jedne swingove urovni se obchoduje nejvyse jednou
   if(g_dir[idx].taken)
      return("tato úroveň už obchodována");

   // Smer musi byt nabity, tedy cena musela byt na spravne strane
   // urovne - jinak se vstupuje do uz beziciho pohybu
   if(!g_dir[idx].armed)
      return(isBuy ? "čeká na návrat pod úroveň" : "čeká na návrat nad úroveň");

   if(atMarket)
     {
      // Uroven prorazenou driv, nez se otevrela prave uzavrena svicka,
      // uz nelze obchodovat: vstup by nevznikl z prurazu, ale z navratu
      // ceny k urovni, ktera svou prilezitost mela. Pruraz z PRAVE
      // uzavrene svicky se naopak propustit musi - jeho priznak nastavil
      // nektery tick uvnitr teze svicky, takze samotny priznak
      // "prorazeno" tu rozhodnout nemuze (drive se proto netestoval
      // vubec a rezim vstupoval i na davno spotrebovane urovni).
      const datetime brokenTime = g_dir[idx].brokenTime;
      const datetime barOpen     = iTime(_Symbol, InpEntryTF, 1);
      if(g_dir[idx].broken && brokenTime > 0 && barOpen > 0 && brokenTime < barOpen)
         return("úroveň už byla proražena");

      // Po gapu nebo dlouhe svicce muze byt trh uz stovky bodu za
      // urovni; takovy vstup uz s prurazem nema nic spolecneho a nesl
      // by plnou delku PT z mista, kde uz pohyb probehl
      const double offset = isBuy ? (entry - trigger) : (trigger - entry);
      if(offset > g_maxLevelOffset)
         return(StringFormat("vstup %.0f b od úrovně", offset / _Point));

      block = PUNTIKY_BLOCK_NONE;
      return("");
     }

   // Uroven, kterou cena uz jednou prorazila, je spotrebovana -
   // i kdyz se cena mezitim vratila zpatky
   if(g_dir[idx].broken)
      return("úroveň už byla proražena");

   // Navrh ma smysl jen dokud pruraz teprve ceka. Kdyz uz cena urovni
   // prosla, STOP prikaz nad (pod) trhem by stejne neslo zadat.
   // Zapocitava se i stop level brokera, aby panel nehlasil "pripraven"
   // u navrhu, ktery by broker odmitl. Tohle omezeni se ale tyka jen
   // ZADANI a upravy prikazu, ne jeho drzeni - proto ma vlastni druh
   // blokace a uz lezici prikaz podle nej rusit nelze.
   string tooClose = "";
   if(StopTooClose(isBuy, entry, StopsLevelPrice(), tooClose))
     {
      block = PUNTIKY_BLOCK_REACH;
      return(tooClose);
     }

   block = PUNTIKY_BLOCK_NONE;
   return("");
  }

//+------------------------------------------------------------------+
//| Sestavi navrh vstupu pro jeden smer.                             |
//|  isBuy      - smer obchodu                                       |
//|  entryPrice - predpokladana cena vstupu                          |
//|  trigger    - uroven prurazu (high/low svicky TF prurazu)        |
//|  atMarket   - vstup na trhu misto pending prikazu (viz           |
//|               EntryBlockReason)                                  |
//| Delka vstupu je min(InpMaxEntryPoints, vzdalenost k nejblizsi    |
//| hrane kanalu nebo reliefni primce ve smeru obchodu); SL ma vzdy  |
//| stejnou delku jako PT (RRR 1:1).                                 |
//| Kanal NENI podminkou vstupu - je to obycejna S/R uroven jako     |
//| kterakoli jina a slouzi uz jen ke zkraceni PT k hrane. Vstup     |
//| mimo kanal (i uplna absence kanalu) je tedy legitimni.           |
//+------------------------------------------------------------------+
SEntryPlan BuildPlan(const bool isBuy, const double entryPrice, const double trigger,
                     const bool atMarket)
  {
   SEntryPlan pl;
   ResetPlan(pl, isBuy);
   pl.trigger = trigger;
   pl.entry   = AlignToTick(entryPrice);

   pl.reason = EntryBlockReason(isBuy, pl.entry, trigger, atMarket, pl.block);
   if(pl.reason != "")
      return(pl);

   // Geometrie kanalu i primek je vedena v indexech baru (viz hlavicka
   // SChannel), takze se pracuje s indexem prave otevreneho baru -
   // a protoze kazdy timeframe ma vlastni indexovou osu, jde o cele
   // pole indexu, ze ktereho si utvar vybere podle sveho tfIdx
   double chBarNow[], chBarProj[];
   ChannelBarIndexes(chBarNow, chBarProj);

   // Kanal, uvnitr ktereho pruraz lezi (-1 = zadny takovy). Drive to
   // byla tvrda podminka a pruraz mimo kanal se zahazoval; kanal je ale
   // jen S/R uroven, takze vstup nezakazuje a uplatni se az nize pri
   // zkracovani PT k hrane. Vyhodnoceni je proto stejne ve vsech
   // rezimech vstupu - lisi se jen to, kdo prikaz posle na trh.
   const int ci = PuntikyFindContainingChannel(g_channels, chBarNow, trigger, InpInsideTolFrac);
   pl.channelIdx = ci;

   const double maxDist = InpMaxEntryPoints * _Point;
   const double minDist = InpMinEntryPoints * _Point;
   double dist = maxDist;

   //--- Referencni cena, od ktere se hledaji prekazky.
   //--- U pending prikazu je to SPOUSTEC, tedy stejna cena, proti ktere
   //--- se testovalo "pruraz uvnitr kanalu". Kdyz se hledalo az od
   //--- vstupu, prekazka lezici mezi spoustecem a vstupem se povazovala
   //--- za neexistujici a PT pak mirilo v plne delce za hranu kanalu -
   //--- presne v pripade, kdy swing sedi na hrane.
   //--- U trzniho vstupu je ale trh uz ZA spoustecem: prekazka mezi
   //--- spoustecem a vstupem je prave prorazena a misto k ni vyjde vzdy
   //--- nula ("malo mista k reliefni primce (0 b)"), takze by vstup
   //--- zamitla prave ta prekazka, kterou prurazova svicka sama zrusila.
   //--- Proto se v tom rezimu hleda az od vstupu.
   const double refPrice = atMarket
                           ? (isBuy ? MathMax(trigger, pl.entry) : MathMin(trigger, pl.entry))
                           : trigger;

   //--- Nejblizsi hrana ve smeru obchodu (vcetne hran vnorenych kanalu
   //--- a kanalu z ostatnich timeframu)
   double edge = 0.0;
   const double edgeGap = PuntikyDistanceToNextEdge(g_channels, chBarNow, chBarProj,
                                                    refPrice, isBuy, edge);
   if(edgeGap >= 0.0)
     {
      // Misto pro PT se ale meri od skutecneho vstupu
      const double avail = MathMax(isBuy ? (edge - pl.entry) : (pl.entry - edge), 0.0)
                           - InpEdgeBuffer * _Point;
      if(avail < dist)
        {
         dist       = MathMax(avail, 0.0);
         pl.barrier = PUNTIKY_BARRIER_EDGE;
        }
     }

   //--- Reliefni primka ve smeru obchodu.
   //--- Primka blize nez planovany PT stoji prurazu v ceste: bud se
   //--- vstup preskoci, nebo se PT zkrati pred ni (podle InpReliefMode).
   //--- Projekce dopredu je stejne dlouha jako u hran kanalu, jen
   //--- vyjadrena v barech prislusneho TF reliefu (viz ProjBars) - obe
   //--- prekazky se tak posuzuji ke stejnemu okamziku.
   if(InpUseRelief && ReliefCount() > 0)
     {
      double relBarNow[], relBarProj[];
      ReliefBarIndexes(relBarNow, relBarProj);

      double relPrice = 0.0;
      const double relGap = PuntikyNearestRelief(g_relief, relBarNow, relBarProj,
                                                 refPrice, isBuy, relPrice);
      if(relGap >= 0.0)
        {
         const double relFromEntry = MathMax(isBuy ? (relPrice - pl.entry)
                                                   : (pl.entry - relPrice), 0.0);
         if(relFromEntry < dist)
           {
            if(InpReliefMode == PUNTIKY_RELIEF_SKIP)
              {
               pl.barrier = PUNTIKY_BARRIER_RELIEF;
               pl.block   = PUNTIKY_BLOCK_LEVEL;
               pl.reason  = StringFormat("v cestě reliéfní přímka (%.0f b, %s)",
                                         relFromEntry / _Point,
                                         DoubleToString(relPrice, _Digits));
               return(pl);
              }

            // Zkraceni PT pred primku, SL se zkrati stejne (RRR 1:1)
            dist       = MathMax(relFromEntry - InpReliefBuffer * _Point, 0.0);
            pl.barrier = PUNTIKY_BARRIER_RELIEF;
           }
        }
     }

   //--- Kontrola minimalni delky vstupu a stop-levelu brokera.
   //--- Zamitnuti se tyka teto konkretni urovne, takze prikaz na ni
   //--- lezet nema (na rozdil od priblizeni trhu ke stop-levelu).
   pl.block = PUNTIKY_BLOCK_LEVEL;
   if(dist < minDist)
     {
      pl.reason = StringFormat("málo místa k %s (%.0f b)", BarrierText(pl.barrier),
                               dist / _Point);
      return(pl);
     }

   //--- Prekazky omezuji CIL: dist je nejdelsi PT, ktery se pred hranu
   //--- nebo primku jeste vejde. Rizikova noha se z nej odvodi zadanym
   //--- pomerem - pri RRR 1:1 vyjde stejna jako dosud, pri 2:1 polovicni.
   //--- Zkracovat naopak cil by znamenalo, ze PT projde prekazkou,
   //--- kvuli ktere se cela delka pocitala.
   const double slDist = dist / InpRiskReward;

   // Stop level brokera omezuje obe nohy, a pri pomeru ruznem od 1:1 je
   // kriticka ta kratsi z nich
   if(MathMin(dist, slDist) <= StopsLevelPrice())
     {
      pl.reason = "délka pod stop-level brokera";
      return(pl);
     }

   pl.distance   = slDist;
   pl.tpDistance = dist;
   pl.sl = AlignToTick(isBuy ? pl.entry - slDist : pl.entry + slDist);
   pl.tp = AlignToTick(isBuy ? pl.entry + dist   : pl.entry - dist);

   // Objem se pocita z RIZIKOVE nohy - riziko obchodu urcuje SL, ne cil
   string lotReason = "";
   pl.lots = CalcLot(slDist, lotReason);
   if(pl.lots <= 0.0)
     {
      pl.reason = (lotReason == "") ? "nelze určit objem" : lotReason;
      return(pl);
     }

   // Objem i vzdalenejsi cil druhe nohy dvojiteho vstupu se pocitaji uz
   // tady, na jednom miste: bublina tlacitka 2x je pak jen cte (misto
   // aby je dopocitavala pri kazdem obnoveni panelu, tedy kazdou
   // sekundu) a klik zada presne to, co bublina slibuje - drive si
   // obe strany pocitaly vlastni cislo z jine equity.
   pl.lotsDouble = CalcLot(slDist, pl.doubleReason, PUNTIKY_DOUBLE_RISK);
   pl.tpDouble   = AlignToTick(isBuy ? pl.entry + dist * PUNTIKY_DOUBLE_PT_MULT
                                     : pl.entry - dist * PUNTIKY_DOUBLE_PT_MULT);

   pl.valid = true;
   pl.block = PUNTIKY_BLOCK_NONE;
   return(pl);
  }

//+------------------------------------------------------------------+
//| Pocet desetinnych mist kroku objemu (0.01 -> 2, 0.001 -> 3).     |
//| Pevne dve mista objem pri kroku 0.001 znicila: 0.004 se          |
//| zaokrouhlilo na 0.00 a obchod se neotevrel vubec.                |
//|  step - krok objemu podle symbolu                                |
//+------------------------------------------------------------------+
int VolumeDigits(const double step)
  {
   if(step <= 0.0)
      return(2);

   int    digits = 0;
   double value  = step;
   while(digits < 8 && MathAbs(value - MathRound(value)) > PUNTIKY_LOTSTEP_EPS)
     {
      value *= 10.0;
      digits++;
     }
   return(digits);
  }

//+------------------------------------------------------------------+
//| Vypocet objemu pozice.                                           |
//|  slDistance   - vzdalenost stop lossu v cene                     |
//|  reason       - out: duvod, proc objem nelze pouzit              |
//|  riskFraction - podil rizika pripadajici na tento obchod         |
//|                 (1.0 = cele, 0.5 = polovina pri vstupu 2x)       |
//| V rezimu rizika se objem dopocita tak, aby ztrata na SL          |
//| odpovidala zadanemu procentu zustatku uctu. Kdyz na to nestaci   |
//| ani nejmensi dovoleny lot, vraci 0 a obchod se neotevre - drive  |
//| se lot zvedl na minimum a riziko tise preteklo pres zadany limit.|
//| V rezimu pevneho lotu se podilem deli primo lot, aby dvojity     |
//| vstup nesl stejny objem jako jeden bezny obchod.                 |
//| Objem se NIKDY nezveda na minimum brokera. Drive to delal        |
//| MathMax(lot, minLot) uplne nakonec a tise tim rusil obe deleni:  |
//| pri pevnem lotu 0.10 a minimu 0.10 dostaly obe nohy dvojiteho    |
//| vstupu plnych 0.10 (tedy dvojnasobek expozice jednoho obchodu,   |
//| prestoze bublina i README slibuji polovinu), v rezimu rizika     |
//| stejny clamp rusil zaokrouhleni na krok objemu.                  |
//| Vraci objem, nebo 0 pri chybe.                                   |
//+------------------------------------------------------------------+
double CalcLot(const double slDistance, string &reason, const double riskFraction = 1.0)
  {
   reason = "";

   // Nesmyslny podil by tise znasobil riziko, proto se orizne
   const double frac = (riskFraction > 0.0 && riskFraction <= 1.0) ? riskFraction : 1.0;

   const double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double lot = InpFixedLot * frac;

   if(InpLotMode == PUNTIKY_LOT_RISK)
     {
      const double balance = AccountInfoDouble(ACCOUNT_BALANCE);

      // Pocita se ztratova strana ticku - u nesymetrickych nastroju se
      // od TICK_VALUE lisi a riziko by vyslo mimo
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tickValue <= 0.0)
         tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      const double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

      if(balance <= 0.0 || tickValue <= 0.0 || tickSize <= 0.0 || slDistance <= 0.0)
        {
         reason = "chybí data pro výpočet rizika";
         return(0.0);
        }

      // Ztrata na 1 lot pri zasazeni SL
      const double lossPerLot = (slDistance / tickSize) * tickValue;
      if(lossPerLot <= 0.0)
        {
         reason = "chybí data pro výpočet rizika";
         return(0.0);
        }

      lot = (balance * InpRiskPercent * frac / 100.0) / lossPerLot;

      if(lot < minLot)
        {
         reason = StringFormat("riziko %.2f %% nestačí ani na %.2f lot (bylo by %.2f %%)",
                               InpRiskPercent * frac, minLot,
                               minLot * lossPerLot / balance * 100.0);
         return(0.0);
        }
     }

   //--- Zaokrouhleni dolu na krok objemu.
   //--- Tolerance srovnava chybu deleni v plovouci radove carce:
   //--- 0.29 / 0.01 vyjde 28.999999999999996 a bez ni by se
   //--- obchodovalo 0.28 misto zadanych 0.29.
   if(lotStep > 0.0)
      lot = MathFloor(lot / lotStep + PUNTIKY_LOTSTEP_EPS) * lotStep;

   const int digits = VolumeDigits(lotStep);

   //--- Pod minimum brokera se objem nezveda (viz hlavicka) - takovy
   //--- obchod se radeji nezada. Tyka se i rezimu rizika: kdyz minLot
   //--- neni nasobkem lotStep, muze objem spadnout pod minimum az tady.
   if(minLot > 0.0 && lot < minLot - PUNTIKY_VOLUME_EPS)
     {
      reason = StringFormat("objem %s nedosahuje minima brokera %s",
                            DoubleToString(lot, digits),
                            DoubleToString(minLot, digits));
      return(0.0);
     }

   if(maxLot > 0.0)
      lot = MathMin(lot, maxLot);

   return(NormalizeDouble(lot, digits));
  }

//--- Prisna shoda dvou cen (double se presne neporovnava): rozdil pod
//--- polovinou bodu, tedy tataz cena po normalizaci
bool SamePrice(const double a, const double b)
  {
   return(MathAbs(a - b) < _Point / 2.0);
  }

//--- Shoda dvou cen s tolerance v bodech. Pouziva se tam, kde druhou
//--- cenu urcil nekdo jiny (ulozena uroven, stopy pozice od brokera,
//--- uroven uz odeslaneho upozorneni), takze na presnou shodu
//--- spolehnout nelze.
bool PriceWithin(const double a, const double b, const double points)
  {
   return(MathAbs(a - b) <= points * _Point);
  }

//+------------------------------------------------------------------+
//| Lezi prikaz uvnitr freeze zony brokera?                          |
//| Prikaz tak blizko trhu nejde ani upravit, ani zrusit - pokus     |
//| skonci chybou TRADE_RETCODE_FROZEN. Drive se freeze level        |
//| nekontroloval vubec a zamitnute ruseni nechalo na trhu stary     |
//| prikaz vedle noveho.                                             |
//|  isBuy - smer prikazu, price - jeho vstupni cena                 |
//+------------------------------------------------------------------+
bool OrderIsFrozen(const bool isBuy, const double price)
  {
   // Vlastni test, ne StopTooClose: nulovy freeze level znamena, ze
   // broker zonu nema vubec, kdezto nulovy stop level jen to, ze prikaz
   // smi lezet tesne u trhu
   const double freeze = SymbolLevelPrice(SYMBOL_TRADE_FREEZE_LEVEL);
   if(freeze <= 0.0)
      return(false);

   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return(false);

   return(isBuy ? (price - ask <= freeze) : (bid - price <= freeze));
  }

//+------------------------------------------------------------------+
//| Zrusi jeden pending prikaz a vysledek zapise do logu.            |
//| Navratovou hodnotu musi volajici testovat: zamitnute ruseni       |
//| necha prikaz na trhu, a kdo na jeho misto rovnou zada novy,       |
//| zdvojnasobi expozici.                                             |
//|  ticket - ticket ruseneho prikazu                                |
//| Vraci true pri uspechu.                                          |
//+------------------------------------------------------------------+
bool DeleteOrder(const ulong ticket)
  {
   if(g_trade.OrderDelete(ticket))
      return(true);

   PrintFormat("PUNTIKY: příkaz #%I64u se nepodařilo zrušit, retcode %d (%s)",
               ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   return(false);
  }

//+------------------------------------------------------------------+
//| Zrusi vsechny pending prikazy strategie.                         |
//| Vraci true, kdyz se povedlo zrusit vsechny.                      |
//+------------------------------------------------------------------+
bool CancelPendingOrders()
  {
   ulong tickets[];
   const int n = CollectOurOrders(-1, tickets);

   bool all = true;
   for(int i = 0; i < n; i++)
      if(!DeleteOrder(tickets[i]))
         all = false;
   return(all);
  }

//+------------------------------------------------------------------+
//| Zada STOP prikaz podle navrhu vstupu.                            |
//|  pl       - navrh vstupu (musi byt platny)                       |
//|  isDouble - prikaz je cast dvojiteho vstupu (tlacitko 2x);       |
//|             promitne se do komentare, podle ktereho se pozna,    |
//|             ktere tlacitko smi obchod odebrat                    |
//| Vraci true, kdyz prikaz vznikl. Neuspech se zapise do panelu i   |
//| do logu a dalsi pokus prijde s pristim prepoctem navrhu, tedy    |
//| nejpozdeji s dalsi svickou vstupniho TF.                         |
//+------------------------------------------------------------------+
bool PlaceStopOrder(SEntryPlan &pl, const bool isDouble = false)
  {
   const string dir = pl.isBuy ? "BUY" : "SELL";

   // Bez kotaci nelze cenu prikazu vubec posoudit. Drive se tenhle
   // pripad tise preskocil, takze volajici vypsal duvod, ktery v
   // g_lastEvent zbyl po nejake starsi (a uplne jine) udalosti.
   if(SymbolInfoDouble(_Symbol, SYMBOL_ASK) <= 0.0 ||
      SymbolInfoDouble(_Symbol, SYMBOL_BID) <= 0.0)
     {
      g_lastEvent = dir + " nezadán - chybí kotace";
      return(false);
     }

   // Broker nedovoli STOP prikaz bliz k trhu, nez je jeho stop level.
   // Drive se takovy pripad jen tise preskocil a panel dal hlasil
   // "pripraven", i kdyz na trhu zadny prikaz nelezel.
   string tooClose = "";
   if(StopTooClose(pl.isBuy, pl.entry, StopsLevelPrice(), tooClose))
     {
      g_lastEvent = dir + " nezadán - " + tooClose;
      return(false);
     }

   const string comment = "PUNTIKY " + (pl.isBuy ? "BUYSTOP" : "SELLSTOP") +
                          (isDouble ? " " + PUNTIKY_DOUBLE_TAG : "");

   const bool ok = pl.isBuy
                   ? g_trade.BuyStop(pl.lots, pl.entry, _Symbol, pl.sl, pl.tp,
                                     ORDER_TIME_GTC, 0, comment)
                   : g_trade.SellStop(pl.lots, pl.entry, _Symbol, pl.sl, pl.tp,
                                      ORDER_TIME_GTC, 0, comment);
   if(!ok)
      g_lastEvent = StringFormat("%s STOP příkaz selhal, retcode %d (%s)", dir,
                                 g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());

   // Do logu pise VOLAJICI - jen on vi, jestli slo o rekonciliaci nebo
   // o klik na tlacitko, a jen tak se hlaska nevypise dvakrat
   return(ok);
  }

//+------------------------------------------------------------------+
//| Srovna skutecny prikaz jednoho smeru s navrhem.                  |
//|  pl     - navrh vstupu pro tento smer                            |
//|  ticket - nalezeny prikaz (0 = zadny)                            |
//|  price  - jeho vstupni cena, sl / tp - jeho stopy                |
//|  volume - jeho objem                                             |
//+------------------------------------------------------------------+
//| Pozadovane nohy vstupu pro aktualni rezim.                       |
//| Bezny automat ma jednu nohu presne podle navrhu. Dvojity ma dve  |
//| s POLOVICNIM objemem: prvni s PT podle navrhu (RRR 1:1), druha   |
//| se stejnym vstupem i SL, ale s PT na nasobku delky vstupu -      |
//| tedy totez, co zada tlacitko LONG 2x / SHORT 2x.                 |
//| Objem i vzdalenejsi cil pocita uz BuildPlan, aby zadani a bubliny|
//| tlacitek nemely kazde vlastni cislo.                             |
//|  pl   - navrh vstupu                                             |
//|  legs - out: jednotlive nohy                                     |
//| Vraci pocet noh; 0 znamena, ze navrh v tomto rezimu zadat nelze  |
//| (duvod nese pl.doubleReason a ukazuje ho panel).                 |
//+------------------------------------------------------------------+
int PlanLegs(SEntryPlan &pl, SEntryPlan &legs[])
  {
   if(!g_autoDouble)
     {
      legs[0] = pl;
      return(1);
     }

   if(pl.lotsDouble <= 0.0)
      return(0);

   legs[0] = pl;
   legs[0].lots = pl.lotsDouble;

   legs[1] = pl;
   legs[1].lots = pl.lotsDouble;
   legs[1].tp   = pl.tpDouble;
   return(2);
  }

//+------------------------------------------------------------------+
//| Srovna JEDEN lezici prikaz s pozadovanou nohou.                  |
//| Uprava se dela jen pri skutecnem rozdilu - drive se prikaz rusil |
//| a zadaval znovu i beze zmeny (2-4 blokujici pozadavky kazdych 15 |
//| minut), zatimco zmena SL/PT/objemu bez zmeny platnosti navrhu se |
//| do nej naopak nepromitla vubec.                                  |
//|  want     - pozadovana noha                                      |
//|  ord      - lezici prikaz                                        |
//|  isDouble - noha dvojiteho vstupu (znacka v komentari prikazu)   |
//+------------------------------------------------------------------+
void SyncLeg(SEntryPlan &want, SPendingOrder &ord, const bool isDouble)
  {
   const bool sameVolume = (MathAbs(ord.volume - want.lots) < PUNTIKY_VOLUME_EPS);
   if(SamePrice(ord.price, want.entry) && SamePrice(ord.sl, want.sl) &&
      SamePrice(ord.tp, want.tp) && sameVolume)
      return;

   if(OrderIsFrozen(want.isBuy, ord.price))
     {
      PrintFormat("PUNTIKY: příkaz #%I64u je ve freeze zóně brokera, úprava odložena.",
                  ord.ticket);
      return;
     }

   // Objem leziciho prikazu zmenit nelze - musi se zadat znovu
   if(!sameVolume)
     {
      if(DeleteOrder(ord.ticket) && !PlaceStopOrder(want, isDouble))
         Print("PUNTIKY: ", g_lastEvent);
      return;
     }

   if(!g_trade.OrderModify(ord.ticket, want.entry, want.sl, want.tp, ORDER_TIME_GTC, 0, 0.0))
      PrintFormat("PUNTIKY: úpravu příkazu #%I64u se nepodařilo provést, retcode %d (%s)",
                  ord.ticket, g_trade.ResultRetcode(),
                  g_trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Srovna lezici prikazy JEDNOHO smeru s navrhem vstupu.            |
//| Prikazy se k noham paruji podle PT, ne podle poradi: broker je   |
//| vraci v libovolnem poradi a dvojity vstup ma obe nohy na stejne  |
//| cene i SL, takze PT je jedine, cim se od sebe lisi.              |
//|  pl    - navrh vstupu tohoto smeru                               |
//|  have  - spolecne pole lezicich prikazu obou smeru               |
//|  base  - index, na kterem zacinaji prikazy tohoto smeru          |
//|  count - kolik jich je                                           |
//+------------------------------------------------------------------+
void SyncOneDirection(SEntryPlan &pl, SPendingOrder &have[], const int base, const int count)
  {
   SEntryPlan want[PUNTIKY_MAX_LEGS];
   const int  n = pl.valid ? PlanLegs(pl, want) : 0;

   //--- Navrh neplati (nebo ho v tomto rezimu nelze zadat) -> zadny
   //--- prikaz lezet nema.
   //--- Vyjimka: prikaz uz lezi presne na planovane cene a jedinou
   //--- vadou navrhu je, ze se k nemu trh priblizil na stop level
   //--- brokera. Ten omezuje ZADANI a upravu prikazu, ne jeho drzeni -
   //--- rusit ho tesne pred vyplnenim by znamenalo propast prave ten
   //--- pruraz, kvuli kteremu prikaz lezi. Vsechny ostatni duvody
   //--- (spotrebovana nebo vymenena uroven, limit pozic, vypnuty smer)
   //--- znamenaji, ze prikaz na trhu byt nema.
   if(n == 0)
     {
      for(int i = 0; i < count; i++)
        {
         const bool keep = (pl.block == PUNTIKY_BLOCK_REACH) &&
                           SamePrice(have[base + i].price, pl.entry);
         if(!keep && !OrderIsFrozen(pl.isBuy, have[base + i].price))
            DeleteOrder(have[base + i].ticket);
        }
      return;
     }

   //--- Kazda noha si najde lezici prikaz s nejblizsim PT
   bool used[PUNTIKY_MAX_LEGS];
   for(int i = 0; i < PUNTIKY_MAX_LEGS; i++)
      used[i] = false;

   for(int leg = 0; leg < n; leg++)
     {
      int    best     = -1;
      double bestDiff = 0.0;
      for(int i = 0; i < count; i++)
        {
         if(used[i])
            continue;
         const double diff = MathAbs(have[base + i].tp - want[leg].tp);
         if(best < 0 || diff < bestDiff)
           {
            best     = i;
            bestDiff = diff;
           }
        }

      //--- Noha chybi -> zadat novy prikaz
      if(best < 0)
        {
         if(!PlaceStopOrder(want[leg], n > 1))
            Print("PUNTIKY: ", g_lastEvent);
         continue;
        }

      used[best] = true;
      SyncLeg(want[leg], have[base + best], n > 1);
     }

   //--- Prikazy navic (napr. po prepnuti z dvojiteho automatu na bezny)
   for(int i = 0; i < count; i++)
      if(!used[i] && !OrderIsFrozen(pl.isBuy, have[base + i].price))
         DeleteOrder(have[base + i].ticket);
  }

//+------------------------------------------------------------------+
//| Zrusi lezici STOP prikaz opacneho smeru (OCO).                   |
//| Vola se hned pri vyplneni prikazu, kdy je vysledek jisty bez     |
//| ohledu na to, jestli uz terminal stihl zaradit novou pozici do   |
//| PositionsTotal(). Prikaz ve freeze zone brokera zrusit nejde -   |
//| takovy se necha na rekonciliaci pri nekterem z dalsich ticku.    |
//| Kresli-li instance jen graf, nesaha na prikazy vubec.            |
//|  filledIsBuy - smer, ktery se prave vyplnil                      |
//+------------------------------------------------------------------+
void CancelOppositeOrder(const bool filledIsBuy)
  {
   if(!TradingEnabled())
      return;

   const bool opposite = !filledIsBuy;
   const long wanted   = filledIsBuy ? ORDER_TYPE_SELL_STOP : ORDER_TYPE_BUY_STOP;

   ulong tickets[];
   const int n = CollectOurOrders(wanted, tickets);

   for(int i = 0; i < n; i++)
     {
      if(!OrderSelect(tickets[i]))
         continue;

      if(OrderIsFrozen(opposite, OrderGetDouble(ORDER_PRICE_OPEN)))
        {
         PrintFormat("PUNTIKY: opačný příkaz #%I64u je ve freeze zóně brokera, "
                     "zrušení odloženo.", tickets[i]);
         continue;
        }
      DeleteOrder(tickets[i]);
     }
  }

//+------------------------------------------------------------------+
//| Srovna skutecne pending prikazy s aktualnimi navrhy.             |
//|                                                                  |
//| Nahrazuje puvodni "zrus vse a zadej znovu": to zahazovalo        |
//| vysledek ruseni (pri zamitnutem OrderDelete vznikl vedle stareho |
//| prikazu druhy identicky a expozice byla dvojnasobna) a na        |
//| hodinove hranici probehlo az trikrat v jedinem ticku.            |
//| Rekonciliace se dela nejvyse jednou za tick a jen kdyz se navrhy |
//| zmenily (priznak g_ordersDirty).                                 |
//+------------------------------------------------------------------+
void SyncPendingOrders()
  {
   g_ordersDirty = false;

   // Instance urcena jen ke kresleni (vypnute obchodovani nebo jiny
   // ucet) nesmi sahat ani na cizi prikazy se stejnym magic - drive je
   // mazala pri kazdem prepoctu, i kdyz sama neobchodovala
   if(!TradingEnabled())
      return;

   //--- Prehled skutecnych prikazu strategie. Pole je spolecne pro oba
   //--- smery, kazdy ma v nem vyhrazeny usek PUNTIKY_MAX_LEGS prikazu
   //--- (index smeru urcuje DirIdx, stejne jako u g_plan).
   SPendingOrder have[2 * PUNTIKY_MAX_LEGS];
   int           count[2] = {0, 0};
   const int     legs     = AutoLegCount();

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong t = OrderGetTicket(i);
      if(t == 0 || !IsOurOrder())
         continue;

      const long type = OrderGetInteger(ORDER_TYPE);
      int dir = -1;
      if(type == ORDER_TYPE_BUY_STOP)
         dir = PUNTIKY_DIR_BUY;
      if(type == ORDER_TYPE_SELL_STOP)
         dir = PUNTIKY_DIR_SELL;

      // Prikaz jineho typu nebo prikaz nad ramec poctu noh (pozustatek
      // po nezdarilem ruseni nebo po prepnuti rezimu) - prebytek se
      // rusi, jinak by se vyplnilo vic obchodu, nez rezim pripousti
      if(dir < 0 || count[dir] >= legs)
        {
         DeleteOrder(t);
         continue;
        }

      const int k = dir * PUNTIKY_MAX_LEGS + count[dir];
      have[k].ticket = t;
      have[k].price  = OrderGetDouble(ORDER_PRICE_OPEN);
      have[k].sl     = OrderGetDouble(ORDER_SL);
      have[k].tp     = OrderGetDouble(ORDER_TP);
      have[k].volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      count[dir]++;
     }

   for(int d = 0; d < 2; d++)
      SyncOneDirection(g_plan[d], have, d * PUNTIKY_MAX_LEGS, count[d]);
  }

//+------------------------------------------------------------------+
//| ID pozice otevrene poslednim obchodnim pozadavkem.               |
//| Bere se z vysledneho obchodu; kdyz ho nelze precist, pouzije se  |
//| ticket prikazu (u hedgovaciho uctu je ID pozice rovno ticketu    |
//| otevirajiciho prikazu).                                          |
//+------------------------------------------------------------------+
ulong ResultPositionId()
  {
   const ulong deal = g_trade.ResultDeal();
   if(deal != 0 && HistoryDealSelect(deal))
      return((ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID));
   return(g_trade.ResultOrder());
  }

//+------------------------------------------------------------------+
//| Dorovna SL a PT jedne pozice na jeji skutecnou vstupni cenu.     |
//| Kazda vetev si drzi vlastni delku, takze u bezneho obchodu vyjde |
//| RRR 1:1 a u druhe pozice dvojiteho vstupu zustane PT na svem     |
//| nasobku - drive se PT natvrdo dorovnaval na delku SL a dvojity   |
//| vstup tak pri plneni prisel o svuj vzdalenejsi cil.              |
//| Uprava se provede jen pri rozdilu vetsim nez 1 bod.              |
//| Meni se vyhradne zadana pozice - drive se prepsaly stopy vsech   |
//| pozic strategie, takze druhy soubezny obchod dostal ramec toho   |
//| tretiho a o svuj puvodni prisel.                                 |
//|  ticket     - ticket (ID) upravovane pozice                      |
//|  slDistance - pozadovana delka SL v cene                         |
//|  tpDistance - pozadovana delka PT v cene (<= 0 = stejna jako SL) |
//+------------------------------------------------------------------+
void AdjustPositionStops(const ulong ticket, const double slDistance,
                         const double tpDistance)
  {
   if(ticket == 0 || slDistance <= 0.0)
      return;
   if(!PositionSelectByTicket(ticket))
     {
      // Terminal jeste nemusi mit novou pozici v seznamu; dorovnani se
      // uz nezopakuje, takze o tom musi byt aspon zaznam v logu
      PrintFormat("PUNTIKY: pozici #%I64u nelze vybrat (chyba %d), SL a PT "
                  "zůstávají tak, jak je vyplnil broker.", ticket, GetLastError());
      return;
     }
   if(!IsOurPosition())
      return;

   // Neznama delka PT (napr. prikaz zadany bez PT) znamena RRR 1:1
   const double tpDist = (tpDistance > 0.0) ? tpDistance : slDistance;

   const bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   const double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   const double sl    = AlignToTick(isBuy ? open - slDistance : open + slDistance);
   const double tp    = AlignToTick(isBuy ? open + tpDist : open - tpDist);

   if(PriceWithin(PositionGetDouble(POSITION_SL), sl, 1.0) &&
      PriceWithin(PositionGetDouble(POSITION_TP), tp, 1.0))
      return;

   if(!g_trade.PositionModify(ticket, sl, tp))
      PrintFormat("PUNTIKY: úpravu stopů pozice #%I64u se nepodařilo provést, retcode %d (%s)",
                  ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Otevreni pozice podle navrhu vstupu.                             |
//|  pl - platny navrh vstupu                                        |
//| Vraci true, kdyz pozice vznikla.                                 |
//+------------------------------------------------------------------+
bool OpenMarket(SEntryPlan &pl)
  {
   if(!TradingEnabled())
     {
      ReportEvent("tržní vstup nezadán - obchodování je vypnuté", true);
      return(false);
     }

   const string comment = "PUNTIKY " + (pl.isBuy ? "BUY" : "SELL");
   const bool   ok = pl.isBuy
                     ? g_trade.Buy(pl.lots, _Symbol, 0.0, pl.sl, pl.tp, comment)
                     : g_trade.Sell(pl.lots, _Symbol, 0.0, pl.sl, pl.tp, comment);

   if(!ok)
     {
      ReportEvent(StringFormat("Chyba vstupu %d / %d",
                               g_trade.ResultRetcode(), GetLastError()), true);
      return(false);
     }

   // Skutecna plnici cena se od navrhu lisi o skluz - SL i PT se
   // dorovnaji na realny vstup, aby zadany pomer PT:SL zustal presny
   AdjustPositionStops(ResultPositionId(), pl.distance, pl.tpDistance);

   ReportEvent(StringFormat("%s %.2f lot @ %s  SL %s  PT %s  (SL %.0f b, PT %.0f b%s)",
                            pl.isBuy ? "BUY" : "SELL", pl.lots,
                            DoubleToString(pl.entry, _Digits),
                            DoubleToString(pl.sl, _Digits),
                            DoubleToString(pl.tp, _Digits),
                            pl.distance / _Point,
                            pl.tpDistance / _Point,
                            pl.barrier == PUNTIKY_BARRIER_NONE
                            ? "" : ", zkráceno k " + BarrierText(pl.barrier)));
   return(true);
  }

//+------------------------------------------------------------------+
//| Zada obchod podle navrhu na pokyn uzivatele (tlacitko).          |
//| Zadava se stejny STOP prikaz jako v automatickem pending rezimu, |
//| vcetne SL a PT s RRR 1:1 - tlacitko je tedy jen rucni schvaleni  |
//| toho, co uz expert kresli do grafu. Neplatny navrh se nezadava:  |
//| obchod se nabizi jen tam, kde je na nej misto.                   |
//|  pl - navrh vstupu prislusneho smeru                             |
//+------------------------------------------------------------------+
void ManualPlace(SEntryPlan &pl)
  {
   const string dir = pl.isBuy ? "LONG" : "SHORT";

   if(!pl.valid)
     {
      ReportEvent(StringFormat("%s nelze zadat - %s", dir,
                               pl.reason == "" ? "návrh není platný" : pl.reason), true);
      return;
     }

   if(!PlaceStopOrder(pl))
     {
      // Duvod uz zapsal PlaceStopOrder do g_lastEvent
      PrintFormat("PUNTIKY: %s tlačítkem nezadán (%s)", dir, g_lastEvent);
      return;
     }

   ReportEvent(StringFormat("%s zadán tlačítkem @ %s  SL %s  PT %s  %.2f lot",
                            dir,
                            DoubleToString(pl.entry, _Digits),
                            DoubleToString(pl.sl, _Digits),
                            DoubleToString(pl.tp, _Digits),
                            pl.lots));
  }

//+------------------------------------------------------------------+
//| Zada dvojici obchodu na pokyn uzivatele (tlacitka LONG / SHORT   |
//| 2x). Oba obchody maji stejny vstup i stejny SL podle navrhu,     |
//| lisi se jen cilem: prvni bere zisk na delce vstupu (RRR 1:1),    |
//| druhy az na jejim nasobku (PUNTIKY_DOUBLE_PT_MULT). Objem se     |
//| pocita s polovicnim rizikem, takze soucet obou obchodu odpovida  |
//| jednomu beznemu obchodu zadanemu tlacitkem LONG / SHORT.         |
//|  pl - navrh vstupu prislusneho smeru                             |
//+------------------------------------------------------------------+
void ManualPlaceDouble(SEntryPlan &pl)
  {
   const string dir = pl.isBuy ? "LONG 2x" : "SHORT 2x";

   if(!pl.valid)
     {
      ReportEvent(StringFormat("%s nelze zadat - %s", dir,
                               pl.reason == "" ? "návrh není platný" : pl.reason), true);
      return;
     }

   // Nettingovy ucet oba prikazy slouci do jedine pozice, takze by se
   // dvojity vstup tise zmenil v jeden obchod se spatnym PT
   if(!AccountIsHedging())
     {
      ReportEvent(dir + " nelze zadat - účet není hedgovací", true);
      return;
     }

   //--- Objem jedne z obou pozic - polovina rizika bezneho obchodu.
   //--- Bere se z navrhu, tedy presne to cislo, ktere ukazuje bublina
   //--- tlacitka; drive se pocital znovu z aktualni equity a klik pak
   //--- zadal jiny objem, nez bublina slibovala.
   const double lots = pl.lotsDouble;
   if(lots <= 0.0)
     {
      ReportEvent(StringFormat("%s nelze zadat - %s", dir,
                               pl.doubleReason == "" ? "nelze určit objem" : pl.doubleReason), true);
      return;
     }

   //--- Prvni obchod: cil presne podle navrhu (RRR 1:1)
   SEntryPlan first = pl;
   first.lots = lots;

   //--- Druhy obchod: stejny vstup i SL, cil na nasobku delky vstupu
   //--- (spocteny uz v BuildPlan, aby ho bublina a zadani nemely kazde
   //--- vlastni)
   SEntryPlan second = pl;
   second.lots = lots;
   second.tp   = pl.tpDouble;

   if(!PlaceStopOrder(first, true))
     {
      // Duvod uz zapsal PlaceStopOrder do g_lastEvent
      PrintFormat("PUNTIKY: %s tlačítkem nezadán (%s)", dir, g_lastEvent);
      return;
     }

   // Kdyz druhy prikaz neprojde, prvni se zamerne nerusi - na trhu uz
   // lezi platny obchod s RRR 1:1 a rusit ho automaticky by znamenalo
   // sahat na uzivateluv obchod kvuli chybe, ktera se ho netyka.
   // Zbyva tedy polovicni objem a hlaska o tom jde do logu i do panelu.
   if(!PlaceStopOrder(second, true))
     {
      ReportEvent(StringFormat("%s zadán jen zpola - druhý příkaz selhal (%s)",
                               dir, g_lastEvent), true);
      return;
     }

   ReportEvent(StringFormat("%s zadán tlačítkem @ %s  SL %s  PT1 %s  PT2 %s  2x %.2f lot",
                            dir,
                            DoubleToString(pl.entry, _Digits),
                            DoubleToString(pl.sl, _Digits),
                            DoubleToString(first.tp, _Digits),
                            DoubleToString(second.tp, _Digits),
                            lots));
  }

//+------------------------------------------------------------------+
//| Odebere z trhu vsechno, co strategie v danem smeru drzi.         |
//| Resi pozice i prikazy najednou - dvojity vstup jich zaklada po   |
//| dvou a po vyplneni prvniho z nich muze vedle bezici pozice lezet |
//| jeste druhy prikaz.                                              |
//|  isBuy - smer (true = LONG, false = SHORT)                       |
//|  label - popis tlacitka pro hlaseni ("LONG", "SHORT 2x", ...)    |
//+------------------------------------------------------------------+
void ManualRemoveDirection(const bool isBuy, const string label)
  {
   const string dir = isBuy ? "LONG" : "SHORT";

   //--- Otevrene pozice a jeste nevyplnene prikazy tohoto smeru
   ulong posTickets[], ordTickets[];
   const int nPos = CollectOurPositions(isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL,
                                        posTickets);
   const int nOrd = CollectOurOrders(isBuy ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP,
                                     ordTickets);

   int closed = 0, closeFail = 0, deleted = 0, deleteFail = 0;

   for(int i = 0; i < nPos; i++)
     {
      if(g_trade.PositionClose(posTickets[i]))
         closed++;
      else
        {
         closeFail++;
         PrintFormat("PUNTIKY: %s pozici #%I64u se nepodařilo zavřít, retcode %d (%s)",
                     dir, posTickets[i], g_trade.ResultRetcode(),
                     g_trade.ResultRetcodeDescription());
        }
     }

   for(int i = 0; i < nOrd; i++)
     {
      // Neuspech uz vypsal DeleteOrder do logu
      if(DeleteOrder(ordTickets[i]))
         deleted++;
      else
         deleteFail++;
     }

   //--- Shrnuti pro panel - vypisuji se jen skutecne dotcene polozky
   string done = "";
   if(closed > 0)
      done = StringFormat("%d pozic(e) zavřeno", closed);
   if(deleted > 0)
      done = done + (done == "" ? "" : ", ") + StringFormat("%d příkaz(ů) zrušeno", deleted);
   if(done == "")
      done = "nic se odebrat nepodařilo";

   string failed = "";
   if(closeFail > 0 || deleteFail > 0)
      failed = StringFormat("  (neúspěch: %d pozic, %d příkazů)", closeFail, deleteFail);

   // Pripadny neuspech uz je soucasti hlaseni, vypis je tedy jeden
   ReportEvent(label + " tlačítkem - " + done + failed);
  }

//+------------------------------------------------------------------+
//| Obsluha kliknuti na rucni tlacitko LONG / SHORT.                 |
//| Tlacitko se chova stridave: kdyz v danem smeru nic na trhu neni, |
//| zada obchod podle navrhu; kdyz tam lezi obchod z tohoto tlacitka,|
//| odebere ho. Dvojity vstup mu nepatri - ten se rusi tlacitkem 2x, |
//| aby obchod odebiralo totez tlacitko, ktere ho zadalo.            |
//|  isBuy - smer tlacitka (true = LONG, false = SHORT)              |
//+------------------------------------------------------------------+
void ManualToggle(const bool isBuy)
  {
   const string dir = isBuy ? "LONG" : "SHORT";

   const string blocked = TradingDisabledReason();
   if(blocked != "")
     {
      ReportEvent(dir + " - " + blocked, true);
      return;
     }

   SDirectionState st;
   ScanDirection(isBuy, st);

   //--- Dvojity vstup patri tlacitku 2x
   if(st.kind == PUNTIKY_MANUAL_DOUBLE)
     {
      ReportEvent(StringFormat("%s - ve směru leží dvojitý vstup, odebere se "
                               "tlačítkem %s 2x", dir, dir));
      return;
     }

   //--- Vlastni obchod klik odebira
   if(st.Busy())
     {
      ManualRemoveDirection(isBuy, dir);
      return;
     }

   //--- V tomto smeru nic nelezi, takze se obchod zadava
   ManualPlace(g_plan[DirIdx(isBuy)]);
  }

//+------------------------------------------------------------------+
//| Obsluha kliknuti na tlacitko LONG 2x / SHORT 2x.                 |
//| Chova se stejne stridave jako tlacitko LONG / SHORT, jen pracuje |
//| s dvojitym vstupem: prazdny smer obsadi dvojici obchodu, vlastni |
//| dvojity vstup odebere celý najednou (vcetne nohy, ktera uz se    |
//| stihla vyplnit). Jednoduchy obchod mu nepatri.                   |
//|  isBuy - smer tlacitka (true = LONG 2x, false = SHORT 2x)        |
//+------------------------------------------------------------------+
void ManualDouble(const bool isBuy)
  {
   const string plain = isBuy ? "LONG" : "SHORT";
   const string dir   = plain + " 2x";

   const string blocked = TradingDisabledReason();
   if(blocked != "")
     {
      ReportEvent(dir + " - " + blocked, true);
      return;
     }

   SDirectionState st;
   ScanDirection(isBuy, st);

   //--- Vlastni dvojity vstup klik odebira cely
   if(st.kind == PUNTIKY_MANUAL_DOUBLE)
     {
      ManualRemoveDirection(isBuy, dir);
      return;
     }

   //--- Jednoduchy obchod patri tlacitku LONG / SHORT
   if(st.Busy())
     {
      ReportEvent(StringFormat("%s nelze zadat - ve směru leží obchod z tlačítka "
                               "%s (tím se také odebere)", dir, plain), true);
      return;
     }

   ManualPlaceDouble(g_plan[DirIdx(isBuy)]);
  }

//+------------------------------------------------------------------+
//| Vyhodnoceni prurazu na vstupnim TF (PUNTIKY_ENTRY_M1_CLOSE).     |
//| Pruraz je potvrzen az uzavrenim svicky vstupniho TF za urovni    |
//| HIGH / LOW svicky TF prurazu. Vstupuje se jen na skutecnem       |
//| prechodu pres uroven - predchozi svicka musi byt jeste pred ni.  |
//| Bez toho by expert vstoupil i dlouho po prurazu, treba az potom, |
//| co pominula prekazka v podobe reliefu.                           |
//+------------------------------------------------------------------+
void CheckEntryOnEntryTF()
  {
   const double closeTF = iClose(_Symbol, InpEntryTF, 1);
   const double prevTF  = iClose(_Symbol, InpEntryTF, 2);
   if(closeTF <= 0.0 || prevTF <= 0.0)
      return;

   //--- Obe strany se resi stejnym kodem (indexy jako v g_dir)
   for(int dir = 0; dir < 2; dir++)
     {
      const bool   isBuy = (dir == PUNTIKY_DIR_BUY);
      const double level = g_dir[dir].level;
      if(level <= 0.0)
         continue;

      // Obe svicky uz jsou uzavrene, takze se posuzuji svym vlastnim
      // spreadem - dnesni median na ne nepatri
      const bool wasBefore = !PriceBeyondLevel(isBuy, prevTF,  level, g_breakBuffer,
                                               BarSpread(InpEntryTF, 2));
      const bool crossed   =  PriceBeyondLevel(isBuy, closeTF, level, g_breakBuffer,
                                               BarSpread(InpEntryTF, 1));
      if(!wasBefore || !crossed)
         continue;

      const double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                 : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(price <= 0.0)
         continue;

      SEntryPlan pl = BuildPlan(isBuy, price, level, true);
      if(!pl.valid)
        {
         // Duvod patri i do logu - pri schovanem panelu je jinak
         // zamitnuty vstup nedohledatelny
         ReportEvent((isBuy ? "BUY" : "SELL") + " zamítnut: " + pl.reason);
         continue;
        }

      if(!OpenMarket(pl))
         continue;

      // Po vstupu je uroven spotrebovana - dalsi prilezitost prijde
      // az s novym swingem
      g_dir[dir].armed = false;
      g_dir[dir].taken = true;
      MarkLevelTaken(isBuy, level);
     }
  }

//+------------------------------------------------------------------+
//| Hlida, jestli se cena priblizila k urovni planovaneho vstupu,    |
//| a rozblika zarovky Hue. Sleduji se jen platne navrhy - k         |
//| neproveditelnemu vstupu neni proc upozornovat.                   |
//+------------------------------------------------------------------+
void CheckHueAlerts()
  {
   if(!InpHueEnabled || InpHueUrl == "" || InpHueNearPoints <= 0)
      return;

   // V automatickem rezimu upozorneni nemaji koho upozornit - obchod
   // zada expert sam a blikajici zarovka by jen rusila. Pamet obou
   // smeru se uvolni, aby po vypnuti rezimu upozorneni zase prislo.
   if(g_autoMode)
     {
      g_dir[PUNTIKY_DIR_BUY].hueLevel  = 0.0;
      g_dir[PUNTIKY_DIR_SELL].hueLevel = 0.0;
      return;
     }

   // V testeru ani pri optimalizaci WebRequest nefunguje
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
      return;

   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return;

   const double nearDist = InpHueNearPoints * _Point;

   //--- K urovni se cena blizi zespodu (BUY) nebo shora (SELL)
   for(int i = 0; i < 2; i++)
     {
      const bool isBuy   = (i == PUNTIKY_DIR_BUY);
      const bool allowed = isBuy ? InpAllowBuy : InpAllowSell;

      if(!allowed || !g_plan[i].valid)
        {
         g_dir[i].hueLevel = 0.0;    // navrh zmizel, priznak se uvolni
         continue;
        }

      const double entry = g_plan[i].entry;
      HueCheckDirection(isBuy, entry, isBuy ? (entry - ask) : (bid - entry),
                        nearDist, g_dir[i]);
     }
  }

//+------------------------------------------------------------------+
//| Vyhodnoti jeden smer a pripadne posle upozorneni.                |
//|  isBuy    - smer navrhu                                          |
//|  level    - cena planovaneho vstupu                              |
//|  dist     - vzdalenost ceny k urovni (zaporna = uz je za ni)     |
//|  nearDist - prah upozorneni v cene                               |
//|  d        - stav smeru; drzi pamet uz odeslanych upozorneni      |
//+------------------------------------------------------------------+
void HueCheckDirection(const bool isBuy, const double level, const double dist,
                       const double nearDist, SDirection &d)
  {
   // Priznak se uvolni az za hysterezi nad prahem - pri kolisani presne
   // na hranici pasma by se jinak blikalo porad dokola. Sirku hystereze
   // urcuje InpHueResetFactor (1.0 = zadna, uvolni se hned za prahem).
   // Cena za urovni vstupu priznak uvolnuje vzdy, bez ohledu na nej.
   if(dist < 0.0 || dist > nearDist * InpHueResetFactor)
     {
      d.hueLevel = 0.0;
      return;
     }

   // Mezipasmo hystereze: uz mimo prah, ale priznak se jeste drzi
   if(dist > nearDist)
      return;

   // Na stejnou uroven se hlasi jen jednou, dokud neni zapnute opakovani
   if(d.hueLevel > 0.0 && PriceWithin(d.hueLevel, level, 1.0))
     {
      if(InpHueRepeatMinutes <= 0)
         return;
      if(TimeCurrent() - d.hueTime < InpHueRepeatMinutes * 60)
         return;
     }

   // Priznak se nastavi i pri neuspechu, aby se pri vypadku sluzby
   // neposilal pozadavek na kazdem ticku
   d.hueLevel = level;
   d.hueTime  = TimeCurrent();
   HueSend(isBuy, level, dist);
  }

//+------------------------------------------------------------------+
//| Bliknuti zarovkou pri vstupu do pozice v automatickem rezimu.    |
//| Vypnuto vstupem InpHueOnEntry, mimo AUTO rezim se nedela vubec.  |
//| Neuspech se nikde neresi - jde o informaci navic, ne o podminku  |
//| obchodu; duvod uz zapsal HueSend do logu i panelu.               |
//|  isBuy - smer vznikle pozice, price - cena plneni                |
//+------------------------------------------------------------------+
void HueOnEntry(const bool isBuy, const double price)
  {
   if(!InpHueOnEntry || !g_autoMode || InpHueUrl == "")
      return;

   // V testeru ani pri optimalizaci WebRequest nefunguje
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
      return;

   HueSend(isBuy, price, 0.0);
  }

//+------------------------------------------------------------------+
//| Adresa sluzby Hue bez cesty, tedy "schema://host:port".          |
//| Do seznamu povolenych URL v terminalu se zapisuje prave tento    |
//| tvar - s cestou (/hue) by povoleni nesedelo, takze hlaska o      |
//| chybe 4014 musi ukazovat uz orizlou adresu.                      |
//+------------------------------------------------------------------+
string HueBaseUrl()
  {
   const int scheme = StringFind(InpHueUrl, "://");
   if(scheme < 0)
      return(InpHueUrl);

   const int slash = StringFind(InpHueUrl, "/", scheme + 3);
   return(slash < 0 ? InpHueUrl : StringSubstr(InpHueUrl, 0, slash));
  }

//+------------------------------------------------------------------+
//| Odesle POST pozadavek na sluzbu Hue.                             |
//| Telo ma stejny tvar jako rucni volani curl:                      |
//|   "BTCUSD Greater Than 9001" / "BTCUSD Less Than 9001"           |
//|  isBuy  - smer upozorneni                                        |
//|  level  - cena urovne vstupu                                     |
//|  dist   - vzdalenost ceny od urovne (jen do textu udalosti)      |
//|  isTest - rucni test z tlacitka                                  |
//| Vraci true, kdyz sluzba odpovedela HTTP 2xx.                     |
//+------------------------------------------------------------------+
bool HueSend(const bool isBuy, const double level, const double dist, const bool isTest = false)
  {
   const string body = StringFormat("%s %s %s", _Symbol,
                                    isBuy ? "Greater Than" : "Less Than",
                                    DoubleToString(level, _Digits));

   // Telo jde jako cisty text v UTF-8; koncova nula do pozadavku nepatri
   char data[];
   int len = StringToCharArray(body, data, 0, WHOLE_ARRAY, CP_UTF8) - 1;
   if(len < 0)
      len = 0;
   ArrayResize(data, len);

   char   result[];
   string resultHeaders = "";
   const string headers = "Content-Type: text/plain; charset=utf-8\r\n";

   ResetLastError();
   const int code = WebRequest("POST", InpHueUrl, headers, InpHueTimeout,
                               data, result, resultHeaders);

   if(code == -1)
     {
      const int err  = GetLastError();
      const string co = isTest ? "test" : "upozornění";

      // 4014 = adresa neni v seznamu povolenych URL v nastaveni terminalu.
      // Nestaci to napsat do logu - do nej se za behu nikdo nediva, proto
      // panel rovnou nese i navod, co v terminalu zaskrtnout.
      if(err == ERR_FUNCTION_NOT_ALLOWED)
        {
         ReportEvent(StringFormat("Hue %s: chyba 4014 - povol adresu %s "
                                  "v Nástroje > Možnosti > Strategie > "
                                  "Povolit WebRequest pro uvedené URL",
                                  co, HueBaseUrl()));
         return(false);
        }

      ReportEvent(StringFormat("Hue %s selhalo: chyba %d (%s)", co, err, InpHueUrl));
      return(false);
     }

   ReportEvent(isTest
               ? StringFormat("Hue test: HTTP %d", code)
               : StringFormat("Hue %s: %.0f b k %s (HTTP %d)",
                              isBuy ? "BUY" : "SELL", dist / _Point,
                              DoubleToString(level, _Digits), code));
   Print("PUNTIKY: tělo požadavku Hue: ", body);

   return(code >= 200 && code < 300);
  }

//+------------------------------------------------------------------+
//| Rucni test upozorneni. Posle pozadavek s aktualni cenou, takze   |
//| jde overit sluzbu i povoleni URL bez cekani na skutecny pruraz.  |
//+------------------------------------------------------------------+
void HueSendTest()
  {
   const double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double level = (ask > 0.0) ? ask : iClose(_Symbol, _Period, 0);

   PrintFormat("PUNTIKY: Hue - ruční test, cíl %s", InpHueUrl);
   HueSend(true, level, 0.0, true);
  }

//+------------------------------------------------------------------+
//| Vyska tlacitek v pixelech.                                       |
//| Odvozuje se od pisma panelu, aby tlacitka sedela k jeho radkum,  |
//| a je zamerne dvojnasobna - na tlacitka se klika za behu trhu a   |
//| nizky prouzek se trefuje spatne. Hodnotu spocita InitPanelMetrics|
//| pri startu; nez k tomu dojde, dopocita se tady.                  |
//+------------------------------------------------------------------+
int ButtonHeight()
  {
   return(g_btnHeight > 0 ? g_btnHeight : MathMax(InpPanelFontSize * 2 + 4, 20) * 2);
  }

//+------------------------------------------------------------------+
//| Sirka textu v pixelech pri pismu panelu.                         |
//| Velikost se predava ZAPORNA, v desetinach bodu: kladna hodnota    |
//| znamena podle dokumentace pixely nezavisle na rozliseni, kdezto   |
//| graficke objekty (OBJPROP_FONTSIZE) berou body a skaluji se podle |
//| DPI obrazovky. S kladnym cislem se merilo mensi pismo, nez        |
//| tlacitko doopravdy vykresli, a pri vetsim pisme nebo skalovani    |
//| 150 % se text useknul uprostred slova ("AVŘÍT SHORT 2x") - presne |
//| to, cemu ma mereni predchazet.                                    |
//|  text - merany retezec                                           |
//| Vraci sirku v pixelech, nebo 0 kdyz mereni selhalo.              |
//+------------------------------------------------------------------+
int PanelTextWidth(const string text)
  {
   if(!TextSetFont("Consolas", -InpPanelFontSize * 10))
      return(0);

   uint w = 0, h = 0;
   if(!TextGetSize(text, w, h))
      return(0);

   return((int)w);
  }

//+------------------------------------------------------------------+
//| Sirka tlacitka podle nejdelsiho textu, ktery se v nem objevi.    |
//| Pocita se z nejdelsiho stavu, ne z toho aktualniho, aby tlacitko |
//| pri prepnuti (LONG -> ZAVŘÍT LONG) neskakalo a rada se nerozjela.|
//| Nouzova sirka slouzi zaroven jako spodni mez: kdyz mereni selze  |
//| nebo vyjde mensi, nez pismo doopravdy zabere, radeji je tlacitko |
//| o kus sirsi, nez aby MT5 text uriznul uprostred slova.           |
//|  longest  - nejdelsi mozny text tlacitka                         |
//|  fallback - nouzova sirka pro pismo velikosti 9 (~13 px na znak) |
//+------------------------------------------------------------------+
int ButtonWidth(const string longest, const int fallback)
  {
   const int w = PanelTextWidth(longest);
   if(w <= 0)
      return(fallback);
   return(MathMax(w + PUNTIKY_BTN_TEXT_PAD, fallback));
  }

//+------------------------------------------------------------------+
//| Spocita rozmery tlacitek a zjisti rezim uctu.                    |
//| Vse to plyne z nemennych vstupu a z uctu, na kterem expert bezi, |
//| takze staci jednou pri startu - drive se sirky merily a rezim     |
//| uctu cetl pri kazdem obnoveni panelu, tedy kazdou sekundu.        |
//+------------------------------------------------------------------+
void InitPanelMetrics()
  {
   g_btnHeight = MathMax(InpPanelFontSize * 2 + 4, 20) * 2;
   g_btnHueW   = ButtonWidth("TEST Hue", PUNTIKY_BTN_HUE_W);
   g_btnPanelW = ButtonWidth("PANEL VYP", PUNTIKY_BTN_PANEL_W);
   g_btnAutoW  = ButtonWidth("AUTO VYP", PUNTIKY_BTN_AUTO_W);
   g_btnAuto2W = ButtonWidth("AUTO ZAP 2x", PUNTIKY_BTN_AUTO2_W);
   g_btnTradeW = ButtonWidth(PUNTIKY_BTN_TRADE_MAX, PUNTIKY_BTN_TRADE_W);

   g_accountHedging = (AccountInfoInteger(ACCOUNT_MARGIN_MODE) ==
                       ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
  }

//+------------------------------------------------------------------+
//| Kolik rad tlacitek se nad panelem kresli.                        |
//| Prvni rada (test Hue a prepinac panelu) je vzdy, dalsi dve jen v |
//| rucnim rezimu - jinde obchodni tlacitka nedavaji smysl.          |
//+------------------------------------------------------------------+
int ButtonRowCount()
  {
   return(EntryMode() == PUNTIKY_ENTRY_MANUAL ? 3 : 1);
  }

//+------------------------------------------------------------------+
//| Vyska vsech rad tlacitek vcetne mezery pod nimi. O tuto hodnotu  |
//| se posouva text panelu, ktery zacina az pod tlacitky.            |
//+------------------------------------------------------------------+
int ButtonRowHeight()
  {
   return(ButtonRowCount() * (ButtonHeight() + PUNTIKY_PANEL_BTN_GAP));
  }

//+------------------------------------------------------------------+
//| Horni okraj cele sestavy (tlacitka + panel).                     |
//| Kdyz je zapnuty one-click SELL/BUY panel MT5, sestava se posune  |
//| pod nej, aby se s nim neprekryvala.                              |
//+------------------------------------------------------------------+
int PanelTopY()
  {
   int y = InpPanelY;
   if(ChartGetInteger(0, CHART_SHOW_ONE_CLICK))
      y += InpPanelOneClickShift;
   return(y);
  }

//+------------------------------------------------------------------+
//| Vykresli tlacitko pro rucni test upozorneni Hue.                 |
//|  x, y - poloha leveho horniho rohu v pixelech                    |
//| Vraci sirku, kterou tlacitko zabralo vcetne mezery za nim        |
//| (0 = tlacitko se nekresli), aby na nej sla navazat dalsi.        |
//+------------------------------------------------------------------+
int DrawHueTestButton(const int x, const int y)
  {
   const string name = PUNTIKY_PREFIX + "BTN_HUETEST";

   if(!InpHueTestButton)
     {
      ObjectDelete(0, name);
      return(0);
     }

   const string text = "TEST Hue";
   const int    w    = g_btnHueW;

   if(PuntikyButton(name, x, y, w, ButtonHeight(), text,
                    InpColorPanel, PUNTIKY_BTN_BG_HUE, InpPanelFontSize, "Consolas",
                    "Odešle testovací upozornění na " + InpHueUrl))
      ChartRedraw();

   return(w + PUNTIKY_PANEL_BTN_GAP);
  }

//+------------------------------------------------------------------+
//| Vykresli jedno rucni tlacitko a nastavi mu podobu podle toho,    |
//| co je v danem smeru na trhu.                                     |
//| Prazdny smer = tlacitko obchod zadava, jinak ho odebira; text i  |
//| barva se meni, aby bylo na prvni pohled videt, co klik udela.    |
//| Neproveditelny navrh necha tlacitko zesedle a duvod da do        |
//| bubliny - obchod se nabizi jen tam, kde je na nej misto.         |
//| Odebira se cely smer, tedy i obe casti dvojiteho vstupu naraz -  |
//| bublina proto uvadi, kolik pozic a prikazu klik odklidi.         |
//|  name  - jmeno objektu                                           |
//|  pl    - navrh vstupu tohoto smeru (nese i smer tlacitka)        |
//|  x, y  - poloha leveho horniho rohu v pixelech                   |
//|  st    - prehled smeru z jedineho skenu (viz ScanBothDirections) |
//+------------------------------------------------------------------+
void DrawManualButton(const string name, SEntryPlan &pl, const int x, const int y,
                      SDirectionState &st)
  {
   const string dir = pl.isBuy ? "LONG" : "SHORT";

   string text    = dir;
   string tooltip = "";
   color  bg      = pl.isBuy ? PUNTIKY_BTN_BG_LONG : PUNTIKY_BTN_BG_SHORT;

   if(st.kind == PUNTIKY_MANUAL_DOUBLE)
     {
      // Dvojity vstup patri tlacitku 2x - odebira ho to tlacitko,
      // ktere ho zadalo
      bg      = PUNTIKY_BTN_BG_OFF;
      tooltip = StringFormat("Ve směru leží dvojitý vstup (pozic %d, příkazů %d) - "
                             "odebere se tlačítkem %s 2x.",
                             st.positions, st.orders, dir);
     }
   else
      if(st.positions > 0)
        {
         // Zavreni ma prednost v popisu: bezici pozice je to podstatne
         text    = "ZAVŘÍT " + dir;
         bg      = PUNTIKY_BTN_BG_REMOVE;
         tooltip = StringFormat("Zavře %s pozici (%d) za trhu", dir, st.positions) +
                   (st.orders > 0
                    ? StringFormat(" a zruší %d ležící %s příkaz(y).", st.orders, dir)
                    : ".");
        }
      else
      if(st.orders > 0)
        {
         text    = "ZRUŠIT " + dir;
         bg      = PUNTIKY_BTN_BG_REMOVE;
         tooltip = StringFormat("Zruší ležící %s příkaz(y) (%d).", dir, st.orders);
        }
      else
        {
         if(pl.valid)
            tooltip = StringFormat("Zadá %s STOP příkaz @ %s  SL %s  PT %s  %.2f lot.",
                                   dir,
                                   DoubleToString(pl.entry, _Digits),
                                   DoubleToString(pl.sl, _Digits),
                                   DoubleToString(pl.tp, _Digits),
                                   pl.lots);
         else
           {
            bg      = PUNTIKY_BTN_BG_OFF;   // na obchod zatim neni misto
            tooltip = "Návrh " + dir + " teď není platný" +
                      (pl.reason == "" ? "." : " (" + pl.reason + ").");
           }
        }

   // Text, pozadi i bublinu srovna PuntikyButton a rekne, jestli se
   // zmenilo neco viditelneho
   if(PuntikyButton(name, x, y, g_btnTradeW, ButtonHeight(), text,
                    InpColorPanel, bg, InpPanelFontSize, "Consolas", tooltip))
      ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Vykresli tlacitko prepinace textoveho panelu v grafu.            |
//| Text nese aktualni stav, ne akci - podle nej se pozna, co klik   |
//| udela, i kdyz je panel prave schovany.                           |
//| Kresli se ve vsech rezimech vstupu, protoze panel je spolecny.   |
//|  x, y - poloha leveho horniho rohu v pixelech                    |
//| Vraci sirku vcetne mezery za tlacitkem.                          |
//+------------------------------------------------------------------+
int DrawPanelToggleButton(const int x, const int y)
  {
   const string name = PUNTIKY_PREFIX + "BTN_PANEL";
   // Popisek rika, co klik UDELA, ne jaky je stav - stav nese barva
   // pozadi. Obracene to matlo: "PANEL VYP" u vypnuteho panelu vypadalo
   // jako tlacitko, ktere ho ma teprve vypnout.
   const string text = g_showPanel ? "PANEL VYP" : "PANEL ZAP";
   const color  bg   = g_showPanel ? PUNTIKY_BTN_BG_PANEL_ON : PUNTIKY_BTN_BG_PANEL_OFF;

   // Bublina zduraznuje, ze jde jen o vypis v grafu - do Expert logu se
   // pise porad, takze se ma kam podivat i pri schovanem panelu
   const string tip = (g_showPanel
                       ? "Textový panel pod tlačítky je zapnutý - klik ho schová. "
                       : "Textový panel pod tlačítky je vypnutý - klik ho zobrazí. ") +
                      "Týká se jen výpisu v grafu, do Expert logu se píše dál.";

   const int w = g_btnPanelW;

   if(PuntikyButton(name, x, y, w, ButtonHeight(), text,
                    InpColorPanel, bg, InpPanelFontSize, "Consolas", tip))
      ChartRedraw();

   return(w + PUNTIKY_PANEL_BTN_GAP);
  }

//+------------------------------------------------------------------+
//| Vykresli jedno tlacitko dvojiteho vstupu (LONG 2x / SHORT 2x).   |
//| Chova se stridave stejne jako tlacitko LONG / SHORT, jen pracuje |
//| s dvojici obchodu: prazdny smer obsadi, vlastni dvojity vstup    |
//| odebere. Zesedne, kdyz ve smeru lezi jednoduchy obchod (ten      |
//| patri tlacitku LONG / SHORT), kdyz navrh neni platny, kdyz na    |
//| polovicni riziko nevyjde lot nebo kdyz ucet neni hedgovaci.      |
//|  name  - jmeno objektu                                           |
//|  pl    - navrh vstupu tohoto smeru (nese i smer tlacitka)        |
//|  x, y  - poloha leveho horniho rohu v pixelech                   |
//|  st    - prehled smeru z jedineho skenu (viz ScanBothDirections) |
//+------------------------------------------------------------------+
void DrawManualDoubleButton(const string name, SEntryPlan &pl, const int x, const int y,
                            SDirectionState &st)
  {
   const string dir = pl.isBuy ? "LONG" : "SHORT";

   string text    = dir + " 2x";
   string tooltip = "";
   color  bg      = pl.isBuy ? PUNTIKY_BTN_BG_LONG : PUNTIKY_BTN_BG_SHORT;

   if(st.kind == PUNTIKY_MANUAL_DOUBLE)
     {
      // Vlastni dvojity vstup - klik ho odebere cely
      const bool hasPos = (st.positions > 0);
      text    = (hasPos ? "ZAVŘÍT " : "ZRUŠIT ") + dir + " 2x";
      bg      = PUNTIKY_BTN_BG_REMOVE;
      tooltip = StringFormat("Odebere celý dvojitý vstup %s - %s%d pozic(e) za trhu "
                             "a %d ležící příkaz(y).",
                             dir, hasPos ? "zavře " : "", st.positions, st.orders);
     }
   else
      if(!AccountIsHedging())
        {
         bg      = PUNTIKY_BTN_BG_OFF;
         tooltip = "Účet není hedgovací - dva příkazy stejného směru by se "
                   "sloučily do jedné pozice, takže dvojitý vstup nelze zadat.";
        }
      else
      if(st.Busy())
        {
         bg      = PUNTIKY_BTN_BG_OFF;
         tooltip = StringFormat("Ve směru leží obchod z tlačítka %s "
                                "(pozic %d, příkazů %d) - tím se také odebere.",
                                dir, st.positions, st.orders);
        }
      else
        {
         if(pl.valid)
           {
            // Objem i vzdalenejsi cil uz spocital BuildPlan - tady se
            // jen ctou, aby se pri kazdem obnoveni panelu nedopocitavaly
            // znovu (tudy chodi kazda sekunda) a aby klik zadal presne
            // to, co bublina slibuje
            if(pl.lotsDouble > 0.0)
               tooltip = StringFormat("Zadá dva %s STOP příkazy @ %s  SL %s, "
                                      "PT1 %s a PT2 %s, každý %.2f lot "
                                      "(poloviční riziko na obchod).",
                                      dir,
                                      DoubleToString(pl.entry, _Digits),
                                      DoubleToString(pl.sl, _Digits),
                                      DoubleToString(pl.tp, _Digits),
                                      DoubleToString(pl.tpDouble, _Digits),
                                      pl.lotsDouble);
            else
              {
               bg      = PUNTIKY_BTN_BG_OFF;   // na polovicni objem to nevyjde
               tooltip = "Dvojitý vstup " + dir + " nelze zadat" +
                         (pl.doubleReason == "" ? "." : " (" + pl.doubleReason + ").");
              }
           }
         else
           {
            bg      = PUNTIKY_BTN_BG_OFF;   // na obchod zatim neni misto
            tooltip = "Návrh " + dir + " teď není platný" +
                      (pl.reason == "" ? "." : " (" + pl.reason + ").");
           }
        }

   if(PuntikyButton(name, x, y, g_btnTradeW, ButtonHeight(), text,
                    InpColorPanel, bg, InpPanelFontSize, "Consolas", tooltip))
      ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Vykresli ctverici rucnich tlacitek LONG / SHORT / LONG 2x /      |
//| SHORT 2x. Mimo rucni rezim obchoduje expert sam a rucni zasah by |
//| mu lezl do rekonciliace prikazu, proto se tam tlacitka nekresli. |
//|  x, y - poloha prvniho tlacitka v pixelech                       |
//|  ms   - prehled trhu z jedineho skenu                            |
//+------------------------------------------------------------------+
int DrawManualButtons(const int x, const int y, SMarketState &ms)
  {
   const string nameLong   = PUNTIKY_PREFIX + "BTN_LONG";
   const string nameShort  = PUNTIKY_PREFIX + "BTN_SHORT";
   const string nameLong2  = PUNTIKY_PREFIX + "BTN_LONG2";
   const string nameShort2 = PUNTIKY_PREFIX + "BTN_SHORT2";

   if(EntryMode() != PUNTIKY_ENTRY_MANUAL)
     {
      // Mimo rucni rezim tlacitka nikdy nevzniknou, takze staci smazat
      // je jednou - ne ctyrikrat za sekundu po celou dobu behu
      if(!g_tradeBtnCleared)
        {
         g_tradeBtnCleared = true;
         ObjectDelete(0, nameLong);
         ObjectDelete(0, nameShort);
         ObjectDelete(0, nameLong2);
         ObjectDelete(0, nameShort2);
        }
      return(0);
     }

   // Priznak "uz smazano" plati jen pro rezim, ve kterem vzniknul.
   // Tlacitko AUTO prepina rezim za behu, takze se pri navratu do
   // rucniho rezimu musi uvolnit - jinak by pristi prepnuti do AUTO
   // tlacitka nesmazalo a hlaska pod nimi by se kreslila pres ne.
   g_tradeBtnCleared = false;

   // Vsechna ctyri tlacitka maji stejnou sirku, takze dvojite varianty
   // sedi presne pod svymi protejsky (LONG 2x pod LONG, SHORT 2x pod SHORT)
   const int x2 = x + g_btnTradeW + PUNTIKY_PANEL_BTN_GAP;
   const int y2 = y + ButtonHeight() + PUNTIKY_PANEL_BTN_GAP;

   DrawManualButton(nameLong,  g_plan[PUNTIKY_DIR_BUY],  x,  y,  ms.buy);
   DrawManualButton(nameShort, g_plan[PUNTIKY_DIR_SELL], x2, y,  ms.sell);
   DrawManualDoubleButton(nameLong2,  g_plan[PUNTIKY_DIR_BUY],  x,  y2, ms.buy);
   DrawManualDoubleButton(nameShort2, g_plan[PUNTIKY_DIR_SELL], x2, y2, ms.sell);
   return(2);
  }

//+------------------------------------------------------------------+
//| Vykresli vsechny rady tlacitek nad panelem.                      |
//|   1. rada: obsluzna  - TEST Hue, PANEL                           |
//|   2. rada: obchodni  - LONG, SHORT                               |
//|   3. rada: obchodni  - LONG 2x, SHORT 2x (pod svymi protejsky)   |
//| Sest tlacitek vedle sebe by preteklo pres graf a dvojite varianty|
//| by nebylo videt pod jejich jednoduchymi protejsky.               |
//| Text panelu zacina az pod posledni radou.                        |
//|  y  - svisle odsazeni prvni rady v pixelech                      |
//|  ms - prehled trhu z jedineho skenu                              |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Tlacitko automatickeho rezimu.                                   |
//| Text nese STAV (stejne jako u tlacitka panelu), aby slo od        |
//| pohledu poznat, jestli expert prave obchoduje sam.                |
//|  x, y - levy horni roh                                            |
//| Vraci sirku vcetne mezery, aby na nej slo navazat dalsim.         |
//+------------------------------------------------------------------+
int DrawAutoModeButton(const int x, const int y)
  {
   const string name = PUNTIKY_PREFIX + "BTN_AUTO";

   // Dvojity automat patri svemu tlacitku - to tento vypnout nesmi,
   // stejne jako tlacitko LONG neodebira dvojity vstup
   const bool   busy = (g_autoMode && g_autoDouble);
   const bool   on   = (g_autoMode && !g_autoDouble);

   // Popisek rika, co klik UDELA (viz DrawPanelToggleButton)
   const string text = on ? "AUTO VYP" : "AUTO ZAP";
   const color  bg   = busy ? PUNTIKY_BTN_BG_OFF
                            : (on ? PUNTIKY_BTN_BG_AUTO_ON : PUNTIKY_BTN_BG_AUTO_OFF);

   const string tip = busy
                      ? "Běží dvojitý automat - vypni ho tlačítkem AUTO VYP 2x."
                      : (on
                         ? "Expert obchoduje SÁM: drží pending STOP příkazy na obou "
                           "úrovních průrazu a po uzavření obchodu zadá další. "
                           "Upozornění Hue jsou potlačená. Klik režim vypne a "
                           "ležící příkazy zruší."
                         : "Expert sám neobchoduje. Klik zapne automatický režim - "
                           "pending STOP příkazy na obou úrovních průrazu, "
                           "bez upozornění Hue.");

   const int w = g_btnAutoW;

   if(PuntikyButton(name, x, y, w, ButtonHeight(), text,
                    InpColorPanel, bg, InpPanelFontSize, "Consolas", tip))
      ChartRedraw();

   return(w + PUNTIKY_PANEL_BTN_GAP);
  }

//+------------------------------------------------------------------+
//| Tlacitko dvojiteho automatickeho rezimu.                         |
//| Stejna dvojice jako LONG / LONG 2x: kazde tlacitko odebira jen   |
//| to, co samo zapnulo, druhe je mezitim nedostupne.                |
//|  x, y - levy horni roh                                            |
//| Vraci sirku vcetne mezery.                                        |
//+------------------------------------------------------------------+
int DrawAutoDoubleButton(const int x, const int y)
  {
   const string name = PUNTIKY_PREFIX + "BTN_AUTO2";

   const bool   busy = (g_autoMode && !g_autoDouble);
   const bool   on   = (g_autoMode && g_autoDouble);

   const string text = on ? "AUTO VYP 2x" : "AUTO ZAP 2x";
   const color  bg   = busy ? PUNTIKY_BTN_BG_OFF
                            : (on ? PUNTIKY_BTN_BG_AUTO_ON : PUNTIKY_BTN_BG_AUTO_OFF);

   const string tip = busy
                      ? "Běží běžný automat - vypni ho tlačítkem AUTO VYP."
                      : (on
                         ? StringFormat("Expert obchoduje SÁM dvojitým vstupem: dvě nohy "
                                        "s polovičním objemem, PT 1:1 a %.0fx. "
                                        "Klik režim vypne a ležící příkazy zruší.",
                                        PUNTIKY_DOUBLE_PT_MULT)
                         : StringFormat("Klik zapne automatický režim s dvojitým vstupem - "
                                        "dvě nohy s polovičním objemem, PT 1:1 a %.0fx. "
                                        "Vyžaduje hedgovací účet a InpMaxPositions >= 2.",
                                        PUNTIKY_DOUBLE_PT_MULT));

   const int w = g_btnAuto2W;

   if(PuntikyButton(name, x, y, w, ButtonHeight(), text,
                    InpColorPanel, bg, InpPanelFontSize, "Consolas", tip))
      ChartRedraw();

   return(w + PUNTIKY_PANEL_BTN_GAP);
  }

//+------------------------------------------------------------------+
//| Vykresleni rady obsluznych a obchodnich tlacitek.                |
//+------------------------------------------------------------------+
int DrawPanelButtons(const int y, SMarketState &ms)
  {
   //--- 1. rada: obsluzna tlacitka
   int x = InpPanelX;
   x += DrawHueTestButton(x, y);
   x += DrawPanelToggleButton(x, y);
   x += DrawAutoModeButton(x, y);
   DrawAutoDoubleButton(x, y);

   //--- 2. a 3. rada: obchodni tlacitka (mimo rucni rezim se jen smazou)
   const int rows = 1 + DrawManualButtons(InpPanelX,
                                          y + ButtonHeight() + PUNTIKY_PANEL_BTN_GAP, ms);

   // Spodni hrana rady se pamatuje, protoze podle ni se umistuje text
   // panelu i hlaska pod tlacitky. Odvozovat ji z rezimu nestaci: pri
   // prepnuti rezimu se pocet rad a skutecne vykreslena tlacitka na
   // jeden pruchod rozchazi a text pak pristal na tlacitkach.
   g_btnBottomY = y + rows * (ButtonHeight() + PUNTIKY_PANEL_BTN_GAP);
   return(g_btnBottomY - y);
  }

//+------------------------------------------------------------------+
//| Textovy popis stavu jednoho smeru pro panel.                     |
//| Rozlisuje, jestli uz bylo obchodovano, jestli je navrh vubec     |
//| proveditelny a jestli je smer nabity (cena na spravne strane).   |
//|  pl - navrh vstupu (nese i smer)                                 |
//+------------------------------------------------------------------+
string StateText(SEntryPlan &pl)
  {
   const string dir   = pl.isBuy ? "BUY" : "SELL";
   const bool   taken = g_dir[DirIdx(pl.isBuy)].taken;

   if(taken)
      return(dir + " obchodován");

   // Nenabity smer uz zamitl EntryBlockReason ("čeká na návrat pod
   // úroveň"), takze se sem dostane jen s neplatnym navrhem a duvodem -
   // vlastni vetev pro "blokován" by proto nemela co vypsat.
   if(!pl.valid)
      return(dir + " nelze" + (pl.reason == "" ? "" : " (" + pl.reason + ")"));
   return(dir + " připraven");
  }

//+------------------------------------------------------------------+
//| Co je v danem smeru na trhu - popisek pro radek rucniho rezimu.  |
//| Pocty se vypisuji az od dvou kusu: u bezneho obchodu je vic nez  |
//| jeden vyloucen, cislo by tam jen zabiralo misto na radku.        |
//| U dvojiteho vstupu se prida znacka 2x, aby bylo videt, ktere     |
//| tlacitko obchod odebira.                                         |
//|  pl    - navrh vstupu tohoto smeru                               |
//|  st    - prehled smeru z jedineho skenu (viz ScanBothDirections) |
//+------------------------------------------------------------------+
string ManualStateText(SEntryPlan &pl, SDirectionState &st)
  {
   if(!st.Busy())
      return(pl.valid ? "lze zadat" : "není místo");

   string state = "";
   if(st.positions > 0)
      state = (st.positions > 1) ? StringFormat("%d pozice", st.positions) : "pozice";
   if(st.orders > 0)
      state = state + (state == "" ? "" : " + ") +
              ((st.orders > 1) ? StringFormat("%d příkazy", st.orders) : "příkaz");

   if(st.kind == PUNTIKY_MANUAL_DOUBLE)
      state += " 2x";

   return(state);
  }

//+------------------------------------------------------------------+
//| Textovy popis navrhu vstupu pro panel.                           |
//|  pl - navrh vstupu                                               |
//+------------------------------------------------------------------+
string PlanToText(SEntryPlan &pl)
  {
   const string dir = pl.isBuy ? "BUY " : "SELL";

   if(!pl.valid)
      return(StringFormat("%s  spouštěč %s  -  %s", dir,
                          DoubleToString(pl.trigger, _Digits),
                          pl.reason == "" ? "čeká na kanál" : pl.reason));

   // Popisky jsou zkracene zamerne - na radek panelu se vejde 63 znaku
   // a delka i objem jsou z pozice v radku zrejme. "k-" znamena obchod
   // mimo kanal, ktery jde zadat jen v rucnim rezimu.
   return(StringFormat("%s vstup %s  SL %s  PT %s  %.0f b  %.2f lot  %s%s",
                       dir,
                       DoubleToString(pl.entry, _Digits),
                       DoubleToString(pl.sl, _Digits),
                       DoubleToString(pl.tp, _Digits),
                       pl.distance / _Point,
                       pl.lots,
                       pl.channelIdx >= 0
                       ? "k" + IntegerToString(pl.channelIdx + 1) : "k-",
                       pl.barrier == PUNTIKY_BARRIER_NONE
                       ? "" : "  [PT k " + BarrierText(pl.barrier) + "]"));
  }

//+------------------------------------------------------------------+
//| Textovy popis aktualni pozice strategie pro panel.               |
//| Pozice i pocet prikazu prichazeji z jedineho skenu (viz          |
//| ScanBothDirections) - drive si tenhle radek prochazel oba seznamy|
//| jeste jednou, tedy kazdou sekundu navic.                         |
//|  ms - souhrn toho, co strategie drzi na trhu                     |
//+------------------------------------------------------------------+
string PositionText(SMarketState &ms)
  {
   if(ms.firstPosition == 0 || !PositionSelectByTicket(ms.firstPosition))
      return(StringFormat("pozice: žádná   (pending %d)", ms.totalOrders));

   const bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   return(StringFormat("pozice: %s %.2f lot  vstup %s  SL %s  PT %s  zisk %.2f %s",
                       isBuy ? "BUY" : "SELL",
                       PositionGetDouble(POSITION_VOLUME),
                       DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), _Digits),
                       DoubleToString(PositionGetDouble(POSITION_SL), _Digits),
                       DoubleToString(PositionGetDouble(POSITION_TP), _Digits),
                       PositionGetDouble(POSITION_PROFIT),
                       AccountInfoString(ACCOUNT_CURRENCY)));
  }

//+------------------------------------------------------------------+
//| Zkraceny nazev timeframu pro panel ("PERIOD_M15" -> "M15").      |
//| Panel ma na radek jen 63 znaku, takze se prefixem plytvat neda.  |
//+------------------------------------------------------------------+
string TFText(const ENUM_TIMEFRAMES tf)
  {
   const string name = EnumToString(tf);
   return(StringSubstr(name, 7));   // odrizne "PERIOD_"
  }

//+------------------------------------------------------------------+
//| Zkraceny cas pro panel ("2026.08.28 11:00" -> "08.28 11:00").    |
//| Rok je u urovni z posledniho dne zbytecny a zabira misto.        |
//+------------------------------------------------------------------+
string ShortTime(const datetime t)
  {
   if(t <= 0)
      return("-");
   return(StringSubstr(TimeToString(t, TIME_DATE | TIME_MINUTES), 5));
  }

//+------------------------------------------------------------------+
//| Prida radek do panelu a zalomi ho na limit MT5.                  |
//| Delsi text nez PUNTIKY_PANEL_MAX_CHARS by terminal urizl         |
//| uprostred slova, proto se zbytek prelije do dalsiho radku         |
//| s odsazenim. Lame se na posledni mezere pred limitem.            |
//|                                                                  |
//| Mezera se hleda az ZA odsazenim pokracovaciho radku. Kdyz se     |
//| hledala od zacatku, dlouhe slovo bez mezer (napr. URL sluzby Hue |
//| v hlasce o chybe 4014) narazilo na mezeru uvnitr samotneho       |
//| odsazeni: nouzovy tvrdy rez se pak nespustil, uriznul se prazdny |
//| kus a zbytek zustal beze zmeny - panel se zaplnil prazdnymi      |
//| radky az do sve kapacity a skutecne udaje pod tim zmizely.       |
//| Rez nejvyse na PUNTIKY_PANEL_MAX_CHARS a nejmene za odsazenim    |
//| zaroven zarucuje, ze zbytek pri kazdem pruchodu opravdu zkrati.  |
//|  lines - pole radku panelu                                       |
//|  n     - pocet dosud naplnenych radku (in/out)                   |
//|  text  - text radku                                              |
//+------------------------------------------------------------------+
void PanelAdd(string &lines[], int &n, const string text)
  {
   const int minCut = StringLen(PUNTIKY_PANEL_INDENT) + 1;
   string    rest   = text;

   while(n < PUNTIKY_PANEL_MAX_LINES)
     {
      if(StringLen(rest) <= PUNTIKY_PANEL_MAX_CHARS)
        {
         lines[n++] = rest;
         return;
        }

      // Hledani mezery zprava, aby se nerezalo uprostred slova
      int cut = PUNTIKY_PANEL_MAX_CHARS;
      while(cut >= minCut && StringGetCharacter(rest, cut) != ' ')
         cut--;

      // Jedno dlouhe slovo se ureze natvrdo; pri rezu na mezere se
      // mezera zahodi, pri tvrdem rezu se znak musi zachovat
      int skip = 1;
      if(cut < minCut)
        {
         cut  = PUNTIKY_PANEL_MAX_CHARS;
         skip = 0;
        }

      lines[n++] = StringSubstr(rest, 0, cut);
      rest = PUNTIKY_PANEL_INDENT + StringSubstr(rest, cut + skip);
     }
  }

//+------------------------------------------------------------------+
//| Smaze hlasku posledni udalosti pod tlacitky.                     |
//| Vlastni prefix MSG_ je nutny: uklid panelu maze PNL_, takze pri  |
//| vypnutem panelu by hlasku smazal hned po jejim vykresleni.       |
//+------------------------------------------------------------------+
void ClearEventFlash()
  {
   // Text se zahazuje spolu s objekty - jinak by hlasku pri dalsim
   // pruchodu (timer bezi kazdou sekundu) DrawEventFlash nakreslil znovu
   g_flashText = "";
   g_flashTick = 0;

   if(g_eventShown == 0)
      return;
   PuntikyDeleteObjects("MSG_");
   g_eventShown = 0;
  }

//+------------------------------------------------------------------+
//| Vypise posledni udalost pod radu tlacitek.                       |
//| Pri vypnutem panelu je to jedine misto v grafu, kde se uzivatel  |
//| dozvi, proc klik na LONG / SHORT nic neudelal - proto se kresli  |
//| i tehdy. Po PUNTIKY_EVENT_FLASH_SEC sekundach zmizi, aby v grafu |
//| nevisela stara hlaska; se zapnutym panelem se nekresli vubec,    |
//| tam ma udalost vlastni radek.                                    |
//| Text se zalamuje toutez cestou jako panel - duvody zamitnuti     |
//| byvaji delsi nez limit MT5 na text objektu.                      |
//+------------------------------------------------------------------+
void DrawEventFlash()
  {
   if(g_flashText == "" || g_flashTick == 0)
     {
      ClearEventFlash();
      return;
     }

   // GetTickCount64 bezi od startu systemu, takze se nemusi hlidat
   // pretoceni ani skok serveroveho casu
   if(GetTickCount64() - g_flashTick >= (ulong)PUNTIKY_EVENT_FLASH_SEC * 1000)
     {
      ClearEventFlash();
      return;
     }

   string lines[PUNTIKY_PANEL_MAX_LINES];
   int    n = 0;
   PanelAdd(lines, n, g_flashText);
   if(n > PUNTIKY_EVENT_MAX_LINES)
      n = PUNTIKY_EVENT_MAX_LINES;

   const int lineH = (InpPanelLineHeight > 0) ? InpPanelLineHeight
                                              : (InpPanelFontSize + 5);
   // Tataz vyska, na ktere zacina text zapnuteho panelu - hlaska tak
   // nesedi na tlacitkach a po zapnuti panelu se nic neposune.
   // Bere se skutecna spodni hrana rady tlacitek; nez se poprve
   // vykresli, zastoupi ji odhad z rezimu.
   const int y = (g_btnBottomY > 0) ? g_btnBottomY
                                    : (PanelTopY() + ButtonRowHeight());

   for(int i = 0; i < n; i++)
      PuntikyLabel(PUNTIKY_PREFIX + "MSG_" + IntegerToString(i),
                   InpPanelX, y + i * lineH,
                   lines[i], InpColorPanel, InpPanelFontSize, "Consolas");

   // Radky, ktere po kratsi hlasce zbyly navic
   PuntikyDeleteIndexed("MSG_", n, g_eventShown);
   g_eventShown = n;
  }

//+------------------------------------------------------------------+
//| Vykresleni informacniho panelu.                                  |
//| Prekresluji se jen radky, jejichz text se zmenil - panel ma pres |
//| deset radku a kazdy je nekolik volani do terminalu, takze plne   |
//| prekresleni na kazdem ticku stalo tisice volani za sekundu.      |
//+------------------------------------------------------------------+
void UpdatePanel()
  {
   // Prehled trhu se ziska JEDINYM pruchodem pozicemi a prikazy; ctou
   // ho texty tlacitek, jejich bubliny i radky panelu. Sken je potreba
   // jen tam, kde ho nekdo cte: v rucnim rezimu kvuli tlacitkum a pri
   // zobrazenem panelu kvuli radku s pozici.
   SMarketState ms;
   if(EntryMode() == PUNTIKY_ENTRY_MANUAL || g_showPanel)
      ScanBothDirections(ms);
   else
      ms.Reset();

   if(!g_showPanel)
     {
      // Uklid staci jednou, ne na kazdem volani
      if(g_panelShown != 0)
        {
         PuntikyDeleteObjects("PNL_");
         g_panelShown = 0;
        }
      DrawPanelButtons(PanelTopY(), ms);
      DrawEventFlash();
      return;
     }

   // Se zapnutym panelem ma udalost vlastni radek "poslední:", takze
   // samostatna hlaska pod tlacitky by se jen zdvojila
   ClearEventFlash();

   string lines[PUNTIKY_PANEL_MAX_LINES];
   int    n = 0;

   PanelAdd(lines, n, "PUNTIKY CHANNEL BREAKOUT  |  " + _Symbol + "  |  účet " +
                      IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)));
   PanelAdd(lines, n, StringFormat("kanály %s   průraz %s   vstup %s   |  max %d b, PT:SL %.2g:1",
                                   TFListText(g_chTF, g_chTFCount), TFText(InpBreakoutTF),
                                   TFText(InpEntryTF), InpMaxEntryPoints, InpRiskReward));

   //--- Prehled detekovanych kanalu. Kazdy kanal ma dva radky - na
   //--- jeden se pri limitu 63 znaku nevejde ani polovina udaju.
   const int channels = ChannelCount();
   if(channels <= 0)
      // "Vypnuto" a "nic neprošlo filtry" jsou dva ruzne stavy - spolecna
      // hlaska by nutila hledat v nastaveni prahy, kdyz jsou jen vypnute
      // vsechny timeframy
      PanelAdd(lines, n, (g_chTFCount < 1)
                         ? "kanály: vypnuté (žádný zapnutý timeframe)"
                         : "kanály: žádný hlavní kanál nesplnil filtry");
   else
     {
      PanelAdd(lines, n, StringFormat("kanály: %d", channels));
      double chBarNow[], chBarProj[];
      ChannelBarIndexes(chBarNow, chBarProj);
      for(int i = 0; i < channels && n < PUNTIKY_PANEL_MAX_LINES - PUNTIKY_PANEL_RESERVE; i++)
        {
         const int tf = g_channels[i].tfIdx;
         if(tf < 0 || tf >= g_chTFCount)
            continue;
         const double barNow = chBarNow[tf];

         // "dotyků od A" a "body po C" jsou zamerne dve ruzna cisla:
         // prvni je slozka skore (obe hrany od bodu A), druhe je pocet
         // pismen D, E, F ... v grafu (stridave dotyky za bodem C).
         // Spolecny popisek "dotyků" driv vypadal jako rozpor.
         PanelAdd(lines, n, StringFormat("  kanál %d %s (%s, měřítko %d)  šířka %.0f b  dotyků %d",
                                         i + 1, TFText(g_chTF[tf]),
                                         g_channels[i].baseIsLow ? "LOW základna" : "HIGH základna",
                                         g_channels[i].scaleIdx,
                                         g_channels[i].width / _Point,
                                         g_channels[i].touches));
         PanelAdd(lines, n, StringFormat("     uvnitř %.0f %%  body po C %d  hrany %s / %s",
                                         g_channels[i].containment * 100.0,
                                         g_channels[i].extraCount,
                                         DoubleToString(g_channels[i].LowerAtBar(barNow), _Digits),
                                         DoubleToString(g_channels[i].UpperAtBar(barNow), _Digits)));
        }
     }

   //--- Urovne prurazu a navrhy vstupu
   PanelAdd(lines, n, StringFormat("průraz %s %s:  H %s  (%s)",
                                   InpUseSwingLevels ? "swing" : "poslední",
                                   TFText(InpBreakoutTF),
                                   DoubleToString(g_dir[PUNTIKY_DIR_BUY].level, _Digits),
                                   ShortTime(g_dir[PUNTIKY_DIR_BUY].levelTime)));
   PanelAdd(lines, n, StringFormat("                  L %s  (%s)",
                                   DoubleToString(g_dir[PUNTIKY_DIR_SELL].level, _Digits),
                                   ShortTime(g_dir[PUNTIKY_DIR_SELL].levelTime)));
   if(InpUseRelief)
      PanelAdd(lines, n, StringFormat("reliéfní přímky %s: %d  (režim: %s)",
                                      TFListText(g_relTF, g_relTFCount), ReliefCount(),
                                      InpReliefMode == PUNTIKY_RELIEF_SKIP ? "přeskočit vstup"
                                                                           : "zkrátit PT"));

   //--- Automaticky rezim: co prave dela expert sam
   if(g_autoMode)
      PanelAdd(lines, n, StringFormat("AUTO režim%s: expert obchoduje sám, %d ležící "
                                      "příkaz(ů), max %d pozic",
                                      g_autoDouble ? " 2x" : "",
                                      CountOrders(), InpMaxPositions));

   //--- Stav upozorneni na zarovky Hue
   if(InpHueEnabled)
      PanelAdd(lines, n, g_autoMode
                         ? "Hue: potlačeno (AUTO režim)"
                         : StringFormat("Hue: upozornění %d b od úrovně vstupu  "
                                        "(BUY %s / SELL %s)",
                                        InpHueNearPoints,
                                        g_dir[PUNTIKY_DIR_BUY].hueLevel  > 0.0 ? "posláno" : "-",
                                        g_dir[PUNTIKY_DIR_SELL].hueLevel > 0.0 ? "posláno" : "-"));

   //--- Rucni rezim - co je v jednotlivych smerech na trhu
   if(EntryMode() == PUNTIKY_ENTRY_MANUAL)
      PanelAdd(lines, n, "ruční režim: LONG " + ManualStateText(g_plan[PUNTIKY_DIR_BUY], ms.buy) +
                         "   SHORT " + ManualStateText(g_plan[PUNTIKY_DIR_SELL], ms.sell));

   // Kazdy smer na vlastnim radku - duvody zamitnuti byvaji dlouhe a
   // spolecny radek by se stejne zalomil
   PanelAdd(lines, n, "stav: " + StateText(g_plan[PUNTIKY_DIR_BUY]));
   PanelAdd(lines, n, "      " + StateText(g_plan[PUNTIKY_DIR_SELL]));
   PanelAdd(lines, n, PlanToText(g_plan[PUNTIKY_DIR_BUY]));
   PanelAdd(lines, n, PlanToText(g_plan[PUNTIKY_DIR_SELL]));
   PanelAdd(lines, n, PositionText(ms));

   if(g_lastEvent != "")
      PanelAdd(lines, n, "poslední: " + g_lastEvent);

   //--- Tlacitka jsou nahore, text panelu zacina az pod nimi
   const int panelY = PanelTopY();
   const int textY  = panelY + DrawPanelButtons(panelY, ms);

   // Vyska radku je samostatny parametr - odvozeni od velikosti pisma
   // nestaci na obrazovkach s vyssim DPI, kde se radky slepuji
   const int lineH = (InpPanelLineHeight > 0) ? InpPanelLineHeight
                                              : (InpPanelFontSize + 5);

   // Prvni radek textu se muze posunout i tim, ze rada tlacitek
   // pribyla nebo zmizela - pak se prekresli cely panel
   const bool moved = (textY != g_panelY);
   g_panelY = textY;

   //--- Prekresli se jen radky, jejichz text se skutecne zmenil.
   //--- Porovnava se s textem SKUTECNE ulozenym v objektu, ne se stinovou
   //--- kopii v pameti: kdyz objekt z grafu zmizi (zmena sablony, uklid
   //--- grafu, neuspesne vytvoreni), vrati ObjectGetString prazdny
   //--- retezec a radek se obnovi. Stinova kopie takovy vypadek
   //--- nepoznala a prazdne misto v panelu uz zustalo navzdy.
   bool changed = false;
   for(int i = 0; i < n; i++)
     {
      const string name = PUNTIKY_PREFIX + "PNL_" + IntegerToString(i);
      if(!moved && ObjectGetString(0, name, OBJPROP_TEXT) == lines[i])
         continue;
      PuntikyLabel(name, InpPanelX, textY + i * lineH,
                   lines[i], InpColorPanel, InpPanelFontSize, "Consolas");
      changed = true;
     }

   // Dotaz na neexistujici objekt nastavuje chybu 4202 - zahodi se, aby
   // se neobjevila v pozdejsim vypisu chyby obchodu
   ResetLastError();

   //--- Radky, ktere po zkraceni panelu zbyly
   if(n < g_panelShown)
     {
      PuntikyDeleteIndexed("PNL_", n, g_panelShown);
      changed = true;
     }
   g_panelShown = n;

   if(changed)
      ChartRedraw();
  }
//+------------------------------------------------------------------+
