//+------------------------------------------------------------------+
//|                                      PuntikyChannelBreakout.mq5  |
//|                                                                  |
//|  Strategie "Puntiky Channel Breakout":                           |
//|   - kanaly ABCD se detekuji a kresli na M15, vcetne vnorenych    |
//|   - urovne prurazu jsou HIGH / LOW swingove H1 svicky            |
//|     (bezna hodinova svicka signal nedava)                        |
//|   - vstup se vyhodnocuje na M1                                   |
//|   - delka vstupu max. InpMaxEntryPoints bodu, SL:PT = 1:1        |
//|   - pokud je hrana kanalu bliz, PT se zkrati k teto hrane        |
//|     a SL se zkrati stejne (RRR zustava 1:1)                      |
//|   - do grafu se kresli kanaly, urovne prurazu, reliefni primky,  |
//|     urovne planovaneho vstupu a informacni panel                 |
//+------------------------------------------------------------------+
#property copyright "Puntiky"
#property version   "1.13"
#property description "Prurazy swingovych H1 urovni uvnitr ABCD kanalu (kanaly M15, vstup M1)"

#include <Trade\Trade.mqh>
#include <Puntiky\PuntikyTypes.mqh>
#include <Puntiky\PuntikySwings.mqh>
#include <Puntiky\PuntikyChannels.mqh>
#include <Puntiky\PuntikyRelief.mqh>
#include <Puntiky\PuntikyDraw.mqh>

//--- Timeframy
input group "=== Timeframy ==="
input ENUM_TIMEFRAMES InpChannelTF        = PERIOD_M15;   // TF pro detekci a kresleni kanalu
input ENUM_TIMEFRAMES InpBreakoutTF       = PERIOD_H1;    // TF urovni prurazu (high/low svicky)
input ENUM_TIMEFRAMES InpEntryTF          = PERIOD_M1;    // TF vyhodnoceni vstupu

//--- Urovne prurazu
input group "=== Urovne prurazu ==="
input bool            InpUseSwingLevels   = true;         // Prorazet jen swingove H1 svicky
input int             InpBreakSwingDepth  = 2;            // Sirka okna pro H1 swingy
input int             InpBreakLookback    = 300;          // Kolik H1 svicek prohledat

//--- Detekce kanalu
input group "=== Detekce kanalu ==="
input int             InpLookbackBars     = 1500;         // Kolik svicek TF kanalu analyzovat
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
input int             InpMaxChannels      = 4;            // Kolik hlavnich kanalu ponechat
input double          InpPierceTolFrac    = 0.05;         // Povolene proriznuti hran (zlomek sirky)
input double          InpInvalidTolFrac   = 0.15;         // Prah invalidace kanalu (zlomek sirky)
input int             InpBackCheckBars    = 20;           // Kolik baru pred bodem A jeste kontrolovat
input int             InpAnchorWindow     = 5;            // Okno, ve kterem musi byt A a C extremem
input double          InpDedupFrac        = 0.15;         // Prah shody dvou kanalu (zlomek sirky)
input bool            InpRequireInside    = true;         // Vyzadovat cenu uvnitr kanalu

//--- Vstup a rizeni obchodu
input group "=== Vstup ==="
input bool            InpEnableTrading    = true;         // Povolit obchodovani (false = jen kresleni)
input ENUM_PUNTIKY_ENTRY InpEntryMode        = PUNTIKY_ENTRY_PENDING;  // Rezim vstupu
input int             InpMaxEntryPoints   = 300;          // Maximalni delka vstupu (body)
input int             InpMinEntryPoints   = 100;          // Minimalni delka vstupu (body)
input int             InpBreakoutBuffer   = 10;           // Buffer nad/pod urovni prurazu (body)
input int             InpMaxLevelOffset   = 30;           // Max. odstup trzniho vstupu od urovne (body)
input int             InpEdgeBuffer       = 20;           // Rezerva PT pred hranou kanalu (body)
input int             InpEdgeProjBars     = 12;           // Projekce hran dopredu (bary TF kanalu)
input double          InpInsideTolFrac    = 0.02;         // Tolerance testu "uvnitr kanalu"
input bool            InpAllowBuy         = true;         // Povolit nakupy
input bool            InpAllowSell        = true;         // Povolit prodeje
input int             InpMaxPositions     = 1;            // Max. soucasnych pozic strategie
input int             InpSlippage         = 20;           // Maximalni skluz (body)
input long            InpMagic            = 67205475;     // Magic number
input long            InpAllowedAccount   = 0;            // Povoleny ucet (0 = bez omezeni)

//--- Reliefni primky na vstupnim timeframu
input group "=== Reliefni primky ==="
input bool            InpUseRelief        = true;         // Hlidat reliefni primky na TF vstupu
input ENUM_PUNTIKY_RELIEF InpReliefMode      = PUNTIKY_RELIEF_SKIP; // Co delat, kdyz primka vadi
input int             InpReliefLookback   = 2400;         // Kolik svicek TF vstupu analyzovat
input int             InpReliefSwingDepth = 10;           // Sirka okna pro hlavni swingy
input int             InpReliefScales     = 4;            // Pocet meritek swingu (10/20/40/80)
input int             InpReliefSwingGap   = 20;           // Max. odstup opor (pocet swingu)
input int             InpReliefMinSpan    = 30;           // Minimalni delka primky (bary)
input int             InpReliefMinTouches = 0;            // Min. dotyku primky mimo jeji opory (0 = staci cista spojnice)
input int             InpReliefPierceTol  = 10;           // Proriznuti primky TELEM svicky (body)
input int             InpReliefWickTol    = 150;          // Povoleny presah primky KNOTEM (body)
input int             InpReliefTouchTol   = 25;           // Tolerance dotyku primky (body)
input int             InpReliefDedupTol   = 40;           // Prah shody dvou primek (body)
input double          InpReliefMaxAge     = 0.0;          // Platnost primky za 2. oporou (0 = neomezeno)
input int             InpReliefMaxDrift   = 1200;         // Max. vzdaleni primky od 2. opory (body)
input bool            InpReliefMidTouch   = false;        // Vyzadovat dotyk i uprostred primky
input int             InpReliefMidTol     = 60;           // Tolerance stredniho dotyku (body)
input double          InpReliefMidFrom    = 0.20;         // Stredni usek primky - od (0..1)
input double          InpReliefMidTo      = 0.80;         // Stredni usek primky - do (0..1)
input int             InpMaxReliefLines   = 6;            // Kolik primek ponechat
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
input bool            InpShowPanel        = true;         // Zobrazit informacni panel
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
input int             InpHueRepeatMinutes = 0;             // Opakovat upozorneni po N minutach (0 = jen jednou)
input int             InpHueTimeout       = 1000;          // Timeout HTTP pozadavku (ms)
input bool            InpHueTestButton    = true;          // Zobrazit tlacitko pro test upozorneni

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
#define PUNTIKY_PANEL_BTN_GAP   6     // mezera mezi panelem a tlacitkem (px)

// MT5 zobrazi z textu grafickeho objektu jen prvnich 63 znaku a zbytek
// tise zahodi (i uprostred slova). Delsi radky panelu se proto zalomi.
#define PUNTIKY_PANEL_MAX_CHARS 63
#define PUNTIKY_LABEL_FALLBACK  10.0  // nahradni tolerance slouceni popisku (body)
#define PUNTIKY_VOLUME_EPS      1e-8  // tolerance porovnani objemu
#define PUNTIKY_LOTSTEP_EPS     1e-9  // tolerance deleni objemu krokem

//--- Globalni stav
CTrade        g_trade;                 // obchodni rozhrani
SChannelStats g_stats;                 // statistika posledni detekce kanalu
SReliefStats  g_reliefStats;           // statistika posledniho hledani reliefu
SReliefLine   g_relief[];              // reliefni primky vstupniho TF
SChannel      g_channels[];            // vybrane hlavni kanaly
int           g_atrHandle = INVALID_HANDLE;
double        g_atr       = 0.0;       // ATR TF kanalu, cte se jednou za prepocet

//--- Parametry modulu se plni jednou v OnInit - jsou to same nemenne
//--- vstupy a prepocet bodu na cenu nema smysl delat na kazdem baru
SChannelParams g_chParams;
SReliefParams  g_reliefParams;
double         g_breakBuffer    = 0.0; // InpBreakoutBuffer v cene
double         g_maxLevelOffset = 0.0; // InpMaxLevelOffset v cene

datetime      g_lastChannelBar  = 0;   // cas posledniho zpracovaneho baru TF kanalu
datetime      g_lastBreakoutBar = 0;   // cas posledniho zpracovaneho baru TF prurazu
datetime      g_lastEntryBar    = 0;   // cas posledniho zpracovaneho baru TF vstupu
int           g_barsSinceShot   = 0;   // pocitadlo baru pro periodicky snimek

double        g_breakHigh = 0.0;       // uroven prurazu nahoru (HIGH swingove svicky)
double        g_breakLow  = 0.0;       // uroven prurazu dolu (LOW swingove svicky)
datetime      g_breakHighTime = 0;     // cas svicky, ze ktere uroven pochazi
datetime      g_breakLowTime  = 0;     // cas svicky, ze ktere uroven pochazi
bool          g_buyArmed   = false;    // smer BUY je pripraven (cena je pod urovni)
bool          g_sellArmed  = false;    // smer SELL je pripraven (cena je nad urovni)
bool          g_buyTaken   = false;    // na teto urovni uz bylo nakoupeno
bool          g_sellTaken  = false;    // na teto urovni uz bylo prodano
bool          g_buyBroken  = false;    // uroven prurazu nahoru uz byla prorazena
bool          g_sellBroken = false;    // uroven prurazu dolu uz byla prorazena

SEntryPlan    g_planBuy;               // aktualni navrh nakupu
SEntryPlan    g_planSell;              // aktualni navrh prodeje
string        g_lastEvent = "";        // posledni udalost pro panel
bool          g_tradingAllowed = true; // vysledek kontroly uctu
bool          g_ordersDirty    = false;// navrhy se zmenily, prikazy je treba srovnat
bool          g_needInitCalc   = true; // ceka se na data pro prvni vypocet

//--- Kolik objektu je zrovna v grafu (kresli se na miste, maze se jen prebytek)
int           g_drawnChannels = 0;
int           g_drawnLabels   = 0;
int           g_drawnRelief   = 0;

//--- Stav panelu - kolik radku je vykresleno a kde panel zacina
int           g_panelShown = 0;
int           g_panelY     = -1;

//--- Upozorneni Hue - pamet uz odeslanych upozorneni pro oba smery
double        g_hueBuyLevel  = 0.0;    // uroven, pro kterou uz slo BUY upozorneni
double        g_hueSellLevel = 0.0;    // uroven, pro kterou uz slo SELL upozorneni
datetime      g_hueBuyTime   = 0;      // cas posledniho BUY upozorneni
datetime      g_hueSellTime  = 0;      // cas posledniho SELL upozorneni

//+------------------------------------------------------------------+
//| Inicializace experta                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Nesmyslne zadany vstup se ma projevit hlaskou pri startu, ne
   //--- tichym nefunkcnim chovanim za behu
   if(!ValidateInputs())
      return(INIT_PARAMETERS_INCORRECT);

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

   //--- ATR na TF kanalu slouzi jako filtr minimalni sirky kanalu
   g_atrHandle = iATR(_Symbol, InpChannelTF, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("PUNTIKY: nepodařilo se vytvořit ATR handle.");
      return(INIT_FAILED);
     }

   InitParams();
   ResetPlan(g_planBuy,  true);
   ResetPlan(g_planSell, false);

   PrintPointDiagnostics();

   EventSetTimer(1);

   // Bez povoleni adresy v nastaveni terminalu skonci WebRequest chybou 4014,
   // proto se URL vypise hned pri startu
   if(InpHueEnabled)
      PrintFormat("PUNTIKY: upozornění Hue zapnuto - %d b od úrovně vstupu, %s "
                  "(adresu povol v Nástroje > Nastavení > Expert Advisors > Povolit WebRequest)",
                  InpHueNearPoints, InpHueUrl);

   // Po prepnuti z pending rezimu by na urovnich zustaly lezet GTC
   // prikazy se starym SL/PT - jejich plneni by otevrelo pozici, kterou
   // uz zadny rezim neridi
   if(InpEntryMode != PUNTIKY_ENTRY_PENDING && TradingEnabled())
      CancelPendingOrders();

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
//| Deinicializace - uklid vlastnich objektu a handlu.               |
//|  reason - duvod ukonceni (viz REASON_*)                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);

   // Pri odebrani experta z grafu by GTC prikazy zustaly lezet bez
   // dozoru a jejich plneni by otevrelo neridenou pozici. Pri zmene
   // parametru nebo rekompilaci se expert hned vraci, takze se prikazy
   // nechavaji byt a srovna je nasledny OnInit.
   if(reason == REASON_REMOVE && TradingEnabled())
      CancelPendingOrders();

   PuntikyDeleteObjects();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Hlavni smycka - reaguje na kazdy tick                            |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- Dokud nejsou data pro prvni vypocet, nema smysl pokracovat
   if(g_needInitCalc && !TryInitialCalc())
      return;

   //--- Nove bary se zjistuji najednou na zacatku: vyhodnoceni vstupu
   //--- musi probehnout jeste nad urovnemi platnymi v okamziku
   //--- uzavreni svicky vstupniho TF (viz krok 1)
   const bool newChannelBar  = IsNewBar(InpChannelTF,  g_lastChannelBar);
   const bool newBreakoutBar = IsNewBar(InpBreakoutTF, g_lastBreakoutBar);
   const bool newEntryBar    = IsNewBar(InpEntryTF,    g_lastEntryBar);

   //--- 1) Vstup potvrzeny uzavrenou svickou vstupniho TF.
   //---    Kdyby se urovne prepocitaly driv, na hodinove hranici by se
   //---    prechod pres uroven meril proti uz jine (starsi) urovni a
   //---    platny signal by zmizel.
   if(InpEntryMode == PUNTIKY_ENTRY_M1_CLOSE && newEntryBar)
      CheckEntryOnEntryTF();

   //--- 2) Novy bar TF kanalu -> prepocet a prekresleni kanalu.
   //---    Hrany se posunuly, takze SL i PT navrhu uz neodpovidaji.
   if(newChannelBar)
     {
      RecalcChannels();
      RebuildPlans();
     }

   //--- 3) Novy bar TF vstupu -> prepocet reliefnich primek
   if(newEntryBar)
      RecalcRelief();

   //--- 4) Novy bar TF prurazu -> nove urovne high/low a nove navrhy
   if(newBreakoutBar)
      RefreshBreakoutLevels();

   //--- 5) Pruraz urovne se hlida na kazdem ticku, aby se prikaz na
   //---    spotrebovanou uroven zrusil hned, ne az za minutu
   const bool wasBuyBroken  = g_buyBroken;
   const bool wasSellBroken = g_sellBroken;
   UpdateArming();
   const bool brokenChanged = (g_buyBroken != wasBuyBroken || g_sellBroken != wasSellBroken);

   // Kdyz uroven padla, je spotrebovana - hned se hleda dalsi swing
   // (vcetne prave otevrene svicky TF prurazu), jinak by expert cekal
   // az na otevreni dalsi svicky TF prurazu
   if(brokenChanged)
      RefreshBreakoutLevels();
   else
      if(newEntryBar)
         RebuildPlans();

   //--- 6) Skutecne prikazy se srovnaji s navrhy nejvyse jednou za tick
   if(InpEntryMode == PUNTIKY_ENTRY_PENDING && g_ordersDirty)
      SyncPendingOrders();

   //--- 7) Priblizeni k urovni vstupu rozblika zarovky Hue
   CheckHueAlerts();
  }

//+------------------------------------------------------------------+
//| Obchodni transakce - zachyti otevreni pozice.                    |
//| V pending rezimu se prikaz vyplni bez zasahu experta, takze bez  |
//| teto obsluhy by expert nevedel, ze uz na dane urovni obchodoval, |
//| a dal by nabizel vstup, ktery je davno vyplneny.                 |
//|  trans   - popis transakce                                       |
//|  request - odeslany pozadavek (nepouziva se)                     |
//|  result  - odpoved serveru (nepouziva se)                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   // Zajima nas jen pridani obchodu do historie tohoto symbolu; obchod
   // musi patrit teto strategii (magic) a musi to byt VSTUP do pozice -
   // vystup (DEAL_ENTRY_OUT) zadnou uroven nespotrebovava. Podrobnosti
   // obchodu jdou precist az po jeho vyberu z historie.
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(trans.symbol != _Symbol)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic)
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_IN)
      return;

   const long   dealType  = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   const double dealPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL)
      return;

   const bool isBuy = (dealType == DEAL_TYPE_BUY);
   if(isBuy)
     {
      g_buyTaken = true;
      g_buyArmed = false;
      MarkLevelTaken(true, g_breakHigh);
     }
   else
     {
      g_sellTaken = true;
      g_sellArmed = false;
      MarkLevelTaken(false, g_breakLow);
     }

   g_lastEvent = StringFormat("%s vyplněn @ %s", isBuy ? "BUY" : "SELL",
                              DoubleToString(dealPrice, _Digits));
   Print("PUNTIKY: ", g_lastEvent);

   // Pending prikaz nese absolutni SL a PT spoctene pro nominalni
   // vstupni cenu. Pri plneni se skluzem by pak SL a PT nemely stejnou
   // delku (RRR by nebylo 1:1), proto se dorovnaji na skutecny vstup.
   const ulong posId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   double distance = 0.0;
   if(trans.order != 0 && HistoryOrderSelect(trans.order))
     {
      const double orderPrice = HistoryOrderGetDouble(trans.order, ORDER_PRICE_OPEN);
      const double orderSL    = HistoryOrderGetDouble(trans.order, ORDER_SL);
      if(orderPrice > 0.0 && orderSL > 0.0)
         distance = MathAbs(orderPrice - orderSL);
     }
   if(distance > 0.0)
      AdjustPositionStops(posId, distance);

   // Navrh s otevrenou pozici prestane byt platny, takze rekonciliace
   // zrusi zbyly prikaz druheho smeru (OCO)
   RebuildPlans();
   if(InpEntryMode == PUNTIKY_ENTRY_PENDING)
      SyncPendingOrders();
   UpdatePanel();
  }

//+------------------------------------------------------------------+
//| Timer - drzi panel aktualni i v obdobich bez ticku.              |
//| Panel se z ticku zamerne nekresli: na zlate chodi desitky ticku  |
//| za sekundu a kazde prekresleni je pres sto volani do terminalu.  |
//+------------------------------------------------------------------+
void OnTimer()
  {
   // Kdyz pri startu chybela data indikatoru, zkusi se vypocet i zde -
   // graf bez ticku (zavreny trh) by jinak zustal prazdny
   if(g_needInitCalc)
      TryInitialCalc();

   UpdatePanel();
   CheckScreenshotRequest();
  }

//+------------------------------------------------------------------+
//| Udalosti grafu - obsluha tlacitka pro test upozorneni Hue.       |
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
   if(sparam != PUNTIKY_PREFIX + "BTN_HUETEST")
      return;

   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   ChartRedraw();

   HueSendTest();
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
   if(InpSlippage < 0)           err += "InpSlippage >= 0; ";

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
//| Naplni parametry modulu a prepocty bodu na cenu.                 |
//| Vstupy se za behu nemeni, takze staci jednou pri startu - drive  |
//| se stejne struktury plnily znovu na kazdem baru.                 |
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

   g_needInitCalc = false;

   RecalcChannels();
   RecalcRelief();
   RefreshBreakoutLevels();

   // Casy prave otevrenych svicek se zapisou hned, aby prvni tick po
   // startu neopakoval tentyz vypocet jeste jednou jako "novy bar"
   IsNewBar(InpChannelTF,  g_lastChannelBar);
   IsNewBar(InpBreakoutTF, g_lastBreakoutBar);
   IsNewBar(InpEntryTF,    g_lastEntryBar);

   // V pending rezimu se prikazy zadaji hned - jinak by se cekalo
   // az na otevreni dalsi svicky TF prurazu
   if(InpEntryMode == PUNTIKY_ENTRY_PENDING)
      SyncPendingOrders();

   return(true);
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
//| Cas o zadany pocet baru dopredu - pro pravy konec kreslenych     |
//| usecek a pro projekci hran kanalu.                               |
//|  tf   - timeframe, ze ktereho se bere delka baru                 |
//|  bars - o kolik baru dopredu                                     |
//+------------------------------------------------------------------+
datetime FutureTime(const ENUM_TIMEFRAMES tf, const int bars)
  {
   return(TimeCurrent() + (datetime)(PeriodSeconds(tf) * bars));
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

//--- Pocet kanalu / reliefnich primek. Drive to byly samostatne
//--- citace, ktere se v predcasnych navratech rozesly s obsahem poli.
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
//| Pocet otevrenych pozic strategie na aktualnim symbolu            |
//+------------------------------------------------------------------+
int CountPositions()
  {
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0)
         continue;
      if(IsOurPosition())
         cnt++;
     }
   return(cnt);
  }

//+------------------------------------------------------------------+
//| Pocet aktivnich pending prikazu strategie                        |
//+------------------------------------------------------------------+
int CountOrders()
  {
   int cnt = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderGetTicket(i) == 0)
         continue;
      if(IsOurOrder())
         cnt++;
     }
   return(cnt);
  }

//+------------------------------------------------------------------+
//| Smi expert vubec sahat na obchodni ucet?                         |
//| Zamerne neresi pocet pozic - to je otazka noveho vstupu, ne      |
//| opravneni. Instance jen pro kresleni (InpEnableTrading = false   |
//| nebo jiny ucet) takto nesmi ani rusit cizi prikazy.              |
//+------------------------------------------------------------------+
bool TradingEnabled()
  {
   if(!InpEnableTrading || !g_tradingAllowed)
      return(false);
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return(false);
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      return(false);
   return(true);
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
   pl.lots         = 0.0;
   pl.barrier      = PUNTIKY_BARRIER_NONE;
   pl.barrierPrice = 0.0;
   pl.channelIdx   = -1;
   pl.reason       = "";
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

//--- Stop level brokera prepocteny na cenu
double StopsLevelPrice()
  {
   return((double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point);
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
//| Prepocet bidove ceny na cenu, za kterou se dany smer skutecne    |
//| plni. Graf i historie jsou v BID, ale BuyStop se plni za ASK -   |
//| kdyz se pruraz nahoru meril bidem, nakup se plnil uz o spread    |
//| POD urovni a zadna svicka pak pruraz nezaznamenala.              |
//|  isBuy    - smer obchodu                                         |
//|  bidPrice - cena v bidovem vyjadreni (high svicky, tick, close)  |
//+------------------------------------------------------------------+
double ExecPrice(const bool isBuy, const double bidPrice)
  {
   return(isBuy ? bidPrice + CurrentSpread() : bidPrice);
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
//+------------------------------------------------------------------+
bool PriceBeyondLevel(const bool isBuy, const double bidPrice,
                      const double level, const double buffer)
  {
   if(level <= 0.0 || bidPrice <= 0.0)
      return(false);
   const double price = ExecPrice(isBuy, bidPrice);
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
//|  isBuy - smer obchodu, level - uroven prurazu                    |
//+------------------------------------------------------------------+
bool LevelWasTaken(const bool isBuy, const double level)
  {
   if(level <= 0.0)
      return(false);
   double stored = 0.0;
   if(!GlobalVariableGet(TakenVarName(isBuy), stored))
      return(false);
   return(MathAbs(stored - level) <= _Point);
  }

//+------------------------------------------------------------------+
//| Prepocet kanalu z historie TF kanalu a jejich vykresleni         |
//+------------------------------------------------------------------+
void RecalcChannels()
  {
   MqlRates rates[];
   const int copied = LoadClosedBars(InpChannelTF, InpLookbackBars, rates);
   if(copied < PUNTIKY_MIN_BARS)
     {
      // Bez dat se stary vysledek zahodi. Kdyby v poli zustal, kreslily
      // by se v grafu kanaly, ktere uz nikdo nepocita, a panel by k nim
      // hlasil "zadny kanal".
      ArrayResize(g_channels, 0);
      g_stats.Reset();
      RedrawChannels();
      PrintFormat("PUNTIKY: málo dat %s (%d svíček), kanály zrušeny.",
                  EnumToString(InpChannelTF), copied);
      return;
     }

   // ATR se cte jednou za prepocet - drive se stejna hodnota tahala
   // z terminalu trikrat (vypocet, diagnostika, kresleni)
   RefreshATR();

   // Kanaly se hledaji ve vice meritkach, aby vznikl i kanal v kanalu
   PuntikyBuildChannels(rates, g_chParams, InpSwingDepth, g_channels, g_stats);

   PrintDiagnostics(copied);
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
//| Vypise do logu, kolik kandidatu padlo na kterem filtru a jak     |
//| vypadaji vybrane kanaly. Z rozlozeni zamitnuti je hned videt,    |
//| ktery prah je uzkym hrdlem detekce.                              |
//|  bars - kolik svicek TF kanalu bylo analyzovano                  |
//+------------------------------------------------------------------+
void PrintDiagnostics(const int bars)
  {
   if(!InpDiagnostics)
      return;

   PrintFormat("PUNTIKY diag: %d svíček %s, ATR %.2f, kombinací A-C %d",
               bars, EnumToString(InpChannelTF), g_atr, g_stats.generated);

   PrintFormat("PUNTIKY diag: zamítnuto - bod B %d, délka %d, stáří %d, šířka %d, "
               "cena mimo %d, opory %d, proříznuto/proraženo %d, dotyky %d, uvnitř %d",
               g_stats.noB, g_stats.span, g_stats.age, g_stats.width,
               g_stats.outside, g_stats.anchors, g_stats.pierced, g_stats.touches,
               g_stats.containment);

   PrintFormat("PUNTIKY diag: prošlo %d, vybráno %d", g_stats.passed, g_stats.selected);

   if(InpUseRelief)
     {
      PrintFormat("PUNTIKY diag: reliéfních přímek %s: %d",
                  EnumToString(InpEntryTF), ReliefCount());
      PrintFormat("PUNTIKY diag: reliéf filtr - dvojic %d, délka %d, stáří %d, drift %d, "
                  "proraženo %d, střed %d, dotyky %d -> prošlo %d, vybráno %d",
                  g_reliefStats.pairs, g_reliefStats.span, g_reliefStats.age,
                  g_reliefStats.drift, g_reliefStats.pierced, g_reliefStats.midTouch,
                  g_reliefStats.touches, g_reliefStats.passed, g_reliefStats.selected);
      for(int i = 0; i < ReliefCount(); i++)
         PrintFormat("PUNTIKY diag: reliéf %d (%s) %s @ %s -> %s @ %s, dotyků %d, "
                     "záběr %d barů, stáří %d barů, přilnutí %.0f b, přesah %.0f b, nyní %s",
                     i + 1, g_relief[i].isHigh ? "odpor" : "podpora",
                     DoubleToString(g_relief[i].p1, _Digits),
                     TimeToString(g_relief[i].t1, TIME_DATE | TIME_MINUTES),
                     DoubleToString(g_relief[i].p2, _Digits),
                     TimeToString(g_relief[i].t2, TIME_DATE | TIME_MINUTES),
                     g_relief[i].touches, g_relief[i].spanBars, g_relief[i].ageBars,
                     g_relief[i].meanGap / _Point,
                     g_relief[i].maxOver / _Point,
                     DoubleToString(g_relief[i].ValueAt(TimeCurrent()), _Digits));
     }

   for(int i = 0; i < ChannelCount(); i++)
     {
      PrintFormat("PUNTIKY diag: kanál %d (měřítko %d, %s) A %s @ %s | B %s @ %s | C %s @ %s",
                  i + 1, g_channels[i].scaleIdx,
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
//| Objekty se aktualizuji na miste a maze se jen to, co po zmenseni |
//| poctu kanalu zbylo - drive se pred kazdym prekreslenim prosly    |
//| vsechny objekty grafu a vsechno se vytvorilo znovu.              |
//+------------------------------------------------------------------+
void RedrawChannels()
  {
   const int count = InpShowChannels ? ChannelCount() : 0;

   // Prava hranice usecek - kousek do budoucnosti, aby bylo videt,
   // kam kanal smeruje
   const datetime tEnd = FutureTime(InpChannelTF, InpForwardBars);

   //--- Nejprve usecky vsech kanalu
   for(int i = 0; i < count; i++)
      PuntikyDrawChannel(g_channels[i], i, tEnd, InpColorHigh, InpColorLow);

   //--- Prebytecne kanaly z minuleho prekresleni
   for(int i = count; i < g_drawnChannels; i++)
      PuntikyDeleteObjects("CH" + IntegerToString(i) + "_");
   g_drawnChannels = count;

   //--- Popisky opor se sesbiraji ze vsech kanalu najednou a teprve pak
   //--- vykresli - popisky padnouci na stejne misto se slouci do jednoho
   //--- textu (napr. "E1 E3"), takze se pri sdilene opore neprepisuji
   int labels = 0;
   if(InpShowPoints && count > 0)
     {
      SChannelLabel items[];
      for(int i = 0; i < count; i++)
         PuntikyCollectChannelLabels(g_channels[i], i, items);

      // Tolerance slucovani vychazi z ATR, aby sedela na volatilite trhu
      const double mergeTol = (g_atr > 0.0) ? g_atr * InpLabelMergeATR
                                            : PUNTIKY_LABEL_FALLBACK * _Point;
      labels = PuntikyDrawLabels(items, InpColorPoint, InpPointFontSize, mergeTol);
     }

   PuntikyDeleteIndexed("PT", labels, g_drawnLabels);
   g_drawnLabels = labels;

   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Prepocet reliefnich primek z historie vstupniho timeframu.       |
//| Primky vznikaji z hlavnich swingu M1 a musi cenu obalovat -      |
//| prorazena primka uz neni prekazkou a mezi kandidaty se nedostane.|
//+------------------------------------------------------------------+
void RecalcRelief()
  {
   if(!InpUseRelief)
     {
      ArrayResize(g_relief, 0);
      g_reliefStats.Reset();
      DrawRelief();
      return;
     }

   MqlRates rates[];
   const int copied = LoadClosedBars(InpEntryTF, InpReliefLookback, rates);
   if(copied < PUNTIKY_MIN_BARS)
     {
      // Stejne jako u kanalu: bez dat se stary vysledek zahodi, jinak
      // by v grafu zustaly primky, ktere uz nikdo neprepocitava
      ArrayResize(g_relief, 0);
      g_reliefStats.Reset();
      DrawRelief();
      return;
     }

   PuntikyBuildReliefLines(rates, g_reliefParams, g_relief, g_reliefStats);
   DrawRelief();
  }

//+------------------------------------------------------------------+
//| Vykresleni reliefnich primek                                     |
//+------------------------------------------------------------------+
void DrawRelief()
  {
   const int count = InpShowRelief ? ReliefCount() : 0;
   const datetime tEnd = FutureTime(InpEntryTF, InpReliefForwardBars);

   for(int i = 0; i < count; i++)
      PuntikyTrendLine(PUNTIKY_PREFIX + "REL_" + IntegerToString(i),
                    g_relief[i].t1, g_relief[i].p1, tEnd, g_relief[i].ValueAt(tEnd),
                    InpColorRelief, 1, STYLE_DOT, true,
                    StringFormat("Reliéfní přímka (%s), dotyků %d",
                                 g_relief[i].isHigh ? "odpor" : "podpora",
                                 g_relief[i].touches));

   PuntikyDeleteIndexed("REL_", count, g_drawnRelief);
   g_drawnRelief = count;

   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Vykresleni urovni prurazu (HIGH / LOW svicky TF prurazu)         |
//+------------------------------------------------------------------+
void DrawBreakoutLevels()
  {
   if(!InpShowBreakLevels || g_breakHigh <= 0.0 || g_breakLow <= 0.0)
     {
      PuntikyDeleteObjects("BRK_");
      return;
     }

   const datetime tTo = FutureTime(InpBreakoutTF, 2);

   // Cara zacina u svicky, ze ktere uroven pochazi - u swingoveho
   // rezimu je tak na prvni pohled videt, ktery swing se prorazi
   PuntikyTrendLine(PUNTIKY_PREFIX + "BRK_H", g_breakHighTime, g_breakHigh, tTo, g_breakHigh,
                 InpColorBreak, 1, STYLE_DASH, false,
                 "Úroveň průrazu HIGH " + DoubleToString(g_breakHigh, _Digits));
   PuntikyTrendLine(PUNTIKY_PREFIX + "BRK_L", g_breakLowTime, g_breakLow, tTo, g_breakLow,
                 InpColorBreak, 1, STYLE_DASH, false,
                 "Úroveň průrazu LOW " + DoubleToString(g_breakLow, _Digits));
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
   const datetime tTo   = FutureTime(InpBreakoutTF, 3);

   PuntikyDrawEntryLevels("BUY",  g_planBuy,  tFrom, tTo,
                       InpColorEntry, InpColorSL, InpColorTP, _Digits);
   PuntikyDrawEntryLevels("SELL", g_planSell, tFrom, tTo,
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

   const double ext = isBuy ? iHigh(_Symbol, InpBreakoutTF, 0)
                            : iLow(_Symbol, InpBreakoutTF, 0);
   return(PriceBeyondLevel(isBuy, ext, level, g_breakBuffer));
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
      const double ext = isHigh ? rates[i].high : rates[i].low;
      if(PriceBeyondLevel(isHigh, ext, s.price, buffer))
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

   const datetime oldTime = isBuy ? g_breakHighTime : g_breakLowTime;
   const bool     changed = (levelTime != oldTime);

   if(isBuy)
     {
      g_breakHigh     = price;
      g_breakHighTime = levelTime;
     }
   else
     {
      g_breakLow     = price;
      g_breakLowTime = levelTime;
     }

   if(changed)
     {
      if(isBuy)
        {
         g_buyTaken = LevelWasTaken(true, price);
         g_buyArmed = false;
        }
      else
        {
         g_sellTaken = LevelWasTaken(false, price);
         g_sellArmed = false;
        }
     }

   // Uzavrene svicky TF prurazu uz prosel vyber swingu, zbyva prave
   // otevrena svicka. Pri nezmenene urovni se drzi i to, co mezitim
   // zjistil tick - jinak by se prorazeni pri vypadku dat ztratilo.
   const bool wasBroken = changed ? false : (isBuy ? g_buyBroken : g_sellBroken);
   const bool broken    = wasBroken || LevelBrokenNow(isBuy, price);

   if(isBuy)
      g_buyBroken = broken;
   else
      g_sellBroken = broken;
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

   // Navrhy se prepocitaji vzdy, i kdyz se zadna uroven najit
   // nepodarila - jinak by v grafu i v prikazech zustal navrh
   // postaveny na urovni, kterou uz cena prorazila
   RebuildPlans();
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

   if(PriceBeyondLevel(true, bid, g_breakHigh, g_breakBuffer))
      g_buyBroken = true;
   if(PriceBeyondLevel(false, bid, g_breakLow, g_breakBuffer))
      g_sellBroken = true;

   // Nabiji se proti exekucni cene smeru: nakup se plni za ask, takze
   // dokud je ask jeste pod urovni, ma pruraz teprve prijit
   if(g_breakHigh > 0.0 && ExecPrice(true, bid) <= g_breakHigh)
      g_buyArmed = true;
   if(g_breakLow > 0.0 && bid >= g_breakLow)
      g_sellArmed = true;
  }

//+------------------------------------------------------------------+
//| Prepocita navrhy vstupu pro oba smery a vykresli jejich urovne.  |
//| Navrhy se pocitaji z hypotetickeho vstupu na urovni prurazu,     |
//| takze panel ukazuje parametry obchodu jeste pred jeho vznikem.   |
//+------------------------------------------------------------------+
void RebuildPlans()
  {
   if(g_breakHigh > 0.0)
      g_planBuy = BuildPlan(true, g_breakHigh + g_breakBuffer, g_breakHigh, false);
   else
      ResetPlan(g_planBuy, true);

   if(g_breakLow > 0.0)
      g_planSell = BuildPlan(false, g_breakLow - g_breakBuffer, g_breakLow, false);
   else
      ResetPlan(g_planSell, false);

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
//|             prave probehl, takze se netestuje dosazitelnost ani  |
//|             priznak "prorazeno", zato se hlida odstup od urovne  |
//+------------------------------------------------------------------+
string EntryBlockReason(const bool isBuy, const double entry, const double trigger,
                        const bool atMarket)
  {
   if(isBuy ? !InpAllowBuy : !InpAllowSell)
      return("směr vypnut");

   // Otevrena pozice navrh rusi - dokud bezi obchod, neni co nabizet
   if(CountPositions() >= InpMaxPositions)
      return("pozice již otevřena");

   // Na jedne swingove urovni se obchoduje nejvyse jednou
   if(isBuy ? g_buyTaken : g_sellTaken)
      return("tato úroveň už obchodována");

   // Smer musi byt nabity, tedy cena musela byt na spravne strane
   // urovne - jinak se vstupuje do uz beziciho pohybu
   if(!(isBuy ? g_buyArmed : g_sellArmed))
      return(isBuy ? "čeká na návrat pod úroveň" : "čeká na návrat nad úroveň");

   if(atMarket)
     {
      // Po gapu nebo dlouhe svicce muze byt trh uz stovky bodu za
      // urovni; takovy vstup uz s prurazem nema nic spolecneho a nesl
      // by plnou delku PT z mista, kde uz pohyb probehl
      const double offset = isBuy ? (entry - trigger) : (trigger - entry);
      if(offset > g_maxLevelOffset)
         return(StringFormat("vstup %.0f b od úrovně", offset / _Point));
      return("");
     }

   // Uroven, kterou cena uz jednou prorazila, je spotrebovana -
   // i kdyz se cena mezitim vratila zpatky
   if(isBuy ? g_buyBroken : g_sellBroken)
      return("úroveň už byla proražena");

   // Navrh ma smysl jen dokud pruraz teprve ceka. Kdyz uz cena urovni
   // prosla, STOP prikaz nad/pod trhem by stejne neslo zadat. Zapocitava
   // se i stop level brokera, aby panel nehlasil "pripraven" u navrhu,
   // ktery by broker odmitl.
   const double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double stops = StopsLevelPrice();
   if(isBuy && ask > 0.0 && entry <= ask + stops)
      return(entry <= ask ? "průraz už proběhl" : "blíž než stop-level brokera");
   if(!isBuy && bid > 0.0 && entry >= bid - stops)
      return(entry >= bid ? "průraz už proběhl" : "blíž než stop-level brokera");

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
//+------------------------------------------------------------------+
SEntryPlan BuildPlan(const bool isBuy, const double entryPrice, const double trigger,
                     const bool atMarket)
  {
   SEntryPlan pl;
   ResetPlan(pl, isBuy);
   pl.trigger = trigger;
   pl.entry   = NormalizeDouble(entryPrice, _Digits);

   pl.reason = EntryBlockReason(isBuy, pl.entry, trigger, atMarket);
   if(pl.reason != "")
      return(pl);

   if(ChannelCount() <= 0)
     {
      pl.reason = "žádný platný kanál";
      return(pl);
     }

   const datetime tNow = TimeCurrent();

   //--- Pruraz musi nastat uvnitr kanalu
   const int ci = PuntikyFindContainingChannel(g_channels, tNow, trigger, InpInsideTolFrac);
   if(ci < 0)
     {
      pl.reason = "průraz mimo kanál";
      return(pl);
     }
   pl.channelIdx = ci;

   const double maxDist = InpMaxEntryPoints * _Point;
   const double minDist = InpMinEntryPoints * _Point;
   double dist = maxDist;

   //--- Nejblizsi hrana ve smeru obchodu (vcetne hran vnorenych kanalu).
   //--- Hleda se od SPOUSTECE, tedy od stejne ceny, proti ktere se
   //--- testovalo "pruraz uvnitr kanalu". Kdyz se hledalo az od vstupu,
   //--- hrana lezici mezi spoustecem a vstupem se povazovala za
   //--- neexistujici a PT pak mirilo v plne delce za hranu kanalu -
   //--- presne v pripade, kdy swing sedi na hrane.
   const datetime tProj = FutureTime(InpChannelTF, InpEdgeProjBars);
   double edge = 0.0;
   const double edgeGap = PuntikyDistanceToNextEdge(g_channels, tNow, tProj, trigger, isBuy, edge);
   if(edgeGap >= 0.0)
     {
      // Misto pro PT se ale meri od skutecneho vstupu
      const double avail = MathMax(isBuy ? (edge - pl.entry) : (pl.entry - edge), 0.0)
                           - InpEdgeBuffer * _Point;
      if(avail < dist)
        {
         dist            = MathMax(avail, 0.0);
         pl.barrier      = PUNTIKY_BARRIER_EDGE;
         pl.barrierPrice = edge;
        }
     }

   //--- Reliefni primka ve smeru obchodu.
   //--- Primka blize nez planovany PT stoji prurazu v ceste: bud se
   //--- vstup preskoci, nebo se PT zkrati pred ni (podle InpReliefMode).
   if(InpUseRelief && ReliefCount() > 0)
     {
      double relPrice = 0.0;
      const double relGap = PuntikyNearestRelief(g_relief, tNow, trigger, isBuy, relPrice);
      if(relGap >= 0.0)
        {
         const double relFromEntry = MathMax(isBuy ? (relPrice - pl.entry)
                                                   : (pl.entry - relPrice), 0.0);
         if(relFromEntry < dist)
           {
            if(InpReliefMode == PUNTIKY_RELIEF_SKIP)
              {
               pl.barrier      = PUNTIKY_BARRIER_RELIEF;
               pl.barrierPrice = relPrice;
               pl.reason = StringFormat("v cestě reliéfní přímka (%.0f b, %s)",
                                        relFromEntry / _Point,
                                        DoubleToString(relPrice, _Digits));
               return(pl);
              }

            // Zkraceni PT pred primku, SL se zkrati stejne (RRR 1:1)
            dist            = MathMax(relFromEntry - InpReliefBuffer * _Point, 0.0);
            pl.barrier      = PUNTIKY_BARRIER_RELIEF;
            pl.barrierPrice = relPrice;
           }
        }
     }

   //--- Kontrola minimalni delky vstupu a stop-levelu brokera
   if(dist < minDist)
     {
      pl.reason = StringFormat("málo místa k %s (%.0f b)", BarrierText(pl.barrier),
                               dist / _Point);
      return(pl);
     }
   if(dist <= StopsLevelPrice())
     {
      pl.reason = "délka pod stop-level brokera";
      return(pl);
     }

   pl.distance = dist;
   pl.sl = NormalizeDouble(isBuy ? pl.entry - dist : pl.entry + dist, _Digits);
   pl.tp = NormalizeDouble(isBuy ? pl.entry + dist : pl.entry - dist, _Digits);

   string lotReason = "";
   pl.lots = CalcLot(dist, lotReason);
   if(pl.lots <= 0.0)
     {
      pl.reason = (lotReason == "") ? "nelze určit objem" : lotReason;
      return(pl);
     }

   pl.valid = true;
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
//|  slDistance - vzdalenost stop lossu v cene                       |
//|  reason     - out: duvod, proc objem nelze pouzit                |
//| V rezimu rizika se objem dopocita tak, aby ztrata na SL          |
//| odpovidala zadanemu procentu zustatku uctu. Kdyz na to nestaci   |
//| ani nejmensi dovoleny lot, vraci 0 a obchod se neotevre - drive  |
//| se lot zvedl na minimum a riziko tise preteklo pres zadany limit.|
//| Vraci objem, nebo 0 pri chybe.                                   |
//+------------------------------------------------------------------+
double CalcLot(const double slDistance, string &reason)
  {
   reason = "";

   const double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double lot = InpFixedLot;

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

      lot = (balance * InpRiskPercent / 100.0) / lossPerLot;

      if(lot < minLot)
        {
         reason = StringFormat("riziko %.2f %% nestačí ani na %.2f lot (bylo by %.2f %%)",
                               InpRiskPercent, minLot,
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

   lot = MathMax(lot, minLot);
   lot = MathMin(lot, maxLot);

   return(NormalizeDouble(lot, VolumeDigits(lotStep)));
  }

//--- Shoda dvou cen na uroven jednoho bodu (double se presne neporovnava)
bool SamePrice(const double a, const double b)
  {
   return(MathAbs(a - b) < _Point / 2.0);
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
   const double freeze = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
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
//| Navratovou hodnotu drive nikdo nekontroloval.                    |
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
   bool all = true;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !IsOurOrder())
         continue;
      if(!DeleteOrder(ticket))
         all = false;
     }
   return(all);
  }

//+------------------------------------------------------------------+
//| Zada STOP prikaz podle navrhu vstupu.                            |
//|  pl - navrh vstupu (musi byt platny)                             |
//| Vraci true, kdyz prikaz vznikl. Neuspech se zapise do panelu i   |
//| do logu a dalsi pokus prijde s pristim prepoctem navrhu, tedy    |
//| nejpozdeji s dalsi svickou vstupniho TF.                         |
//+------------------------------------------------------------------+
bool PlaceStopOrder(SEntryPlan &pl)
  {
   const double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double stops = StopsLevelPrice();
   if(ask <= 0.0 || bid <= 0.0)
      return(false);

   // Broker nedovoli STOP prikaz bliz k trhu, nez je jeho stop level.
   // Drive se takovy pripad jen tise preskocil a panel dal hlasil
   // "pripraven", i kdyz na trhu zadny prikaz nelezel.
   if(pl.isBuy ? (pl.entry <= ask + stops) : (pl.entry >= bid - stops))
     {
      g_lastEvent = StringFormat("%s nezadán - blíž než stop-level brokera (%.0f b)",
                                 pl.isBuy ? "BUY" : "SELL", stops / _Point);
      return(false);
     }

   const bool ok = pl.isBuy
                   ? g_trade.BuyStop(pl.lots, pl.entry, _Symbol, pl.sl, pl.tp,
                                     ORDER_TIME_GTC, 0, "PUNTIKY BUYSTOP")
                   : g_trade.SellStop(pl.lots, pl.entry, _Symbol, pl.sl, pl.tp,
                                      ORDER_TIME_GTC, 0, "PUNTIKY SELLSTOP");
   if(!ok)
     {
      g_lastEvent = StringFormat("%s STOP příkaz selhal, retcode %d",
                                 pl.isBuy ? "BUY" : "SELL", g_trade.ResultRetcode());
      Print("PUNTIKY: ", g_lastEvent, " (", g_trade.ResultRetcodeDescription(), ")");
     }
   return(ok);
  }

//+------------------------------------------------------------------+
//| Srovna skutecny prikaz jednoho smeru s navrhem.                  |
//|  pl     - navrh vstupu pro tento smer                            |
//|  ticket - nalezeny prikaz (0 = zadny)                            |
//|  price  - jeho vstupni cena, sl / tp - jeho stopy                |
//|  volume - jeho objem                                             |
//+------------------------------------------------------------------+
void SyncOneDirection(SEntryPlan &pl, const ulong ticket, const double price,
                      const double sl, const double tp, const double volume)
  {
   //--- Navrh neplati -> zadny prikaz lezet nema
   if(!pl.valid)
     {
      if(ticket != 0 && !OrderIsFrozen(pl.isBuy, price))
         DeleteOrder(ticket);
      return;
     }

   //--- Navrh plati a prikaz chybi -> zadat novy
   if(ticket == 0)
     {
      PlaceStopOrder(pl);
      return;
     }

   //--- Lezici prikaz se upravuje jen pri skutecnem rozdilu. Drive se
   //--- rusil a zadaval znovu i beze zmeny (2-4 blokujici pozadavky
   //--- kazdych 15 minut), zatimco zmena SL/PT/objemu bez zmeny
   //--- platnosti navrhu se do nej naopak nepromitla vubec.
   const bool sameVolume = (MathAbs(volume - pl.lots) < PUNTIKY_VOLUME_EPS);
   if(SamePrice(price, pl.entry) && SamePrice(sl, pl.sl) && SamePrice(tp, pl.tp) && sameVolume)
      return;

   if(OrderIsFrozen(pl.isBuy, price))
     {
      PrintFormat("PUNTIKY: příkaz #%I64u je ve freeze zóně brokera, úprava odložena.", ticket);
      return;
     }

   // Objem lezicího prikazu zmenit nelze - musi se zadat znovu
   if(!sameVolume)
     {
      if(DeleteOrder(ticket))
         PlaceStopOrder(pl);
      return;
     }

   if(!g_trade.OrderModify(ticket, pl.entry, pl.sl, pl.tp, ORDER_TIME_GTC, 0, 0.0))
      PrintFormat("PUNTIKY: úpravu příkazu #%I64u se nepodařilo provést, retcode %d (%s)",
                  ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
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

   //--- Prehled skutecnych prikazu strategie (index 0 = BUY, 1 = SELL)
   ulong  ticket[2]  = {0, 0};
   double price[2]   = {0.0, 0.0};
   double slPrice[2] = {0.0, 0.0};
   double tpPrice[2] = {0.0, 0.0};
   double volume[2]  = {0.0, 0.0};

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong t = OrderGetTicket(i);
      if(t == 0 || !IsOurOrder())
         continue;

      const long type = OrderGetInteger(ORDER_TYPE);
      int slot = -1;
      if(type == ORDER_TYPE_BUY_STOP)
         slot = 0;
      if(type == ORDER_TYPE_SELL_STOP)
         slot = 1;

      // Prikaz jineho typu nebo druhy prikaz tehoz smeru (pozustatek po
      // nezdarilem ruseni) - prebytek se rusi, jinak by se vyplnily oba
      if(slot < 0 || ticket[slot] != 0)
        {
         DeleteOrder(t);
         continue;
        }

      ticket[slot]  = t;
      price[slot]   = OrderGetDouble(ORDER_PRICE_OPEN);
      slPrice[slot] = OrderGetDouble(ORDER_SL);
      tpPrice[slot] = OrderGetDouble(ORDER_TP);
      volume[slot]  = OrderGetDouble(ORDER_VOLUME_CURRENT);
     }

   SyncOneDirection(g_planBuy,  ticket[0], price[0], slPrice[0], tpPrice[0], volume[0]);
   SyncOneDirection(g_planSell, ticket[1], price[1], slPrice[1], tpPrice[1], volume[1]);
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
//| Dorovna SL a PT jedne pozice na jeji skutecnou vstupni cenu tak, |
//| aby obe vzdalenosti odpovidaly zadane delce vstupu (RRR 1:1).    |
//| Uprava se provede jen pri rozdilu vetsim nez 1 bod.              |
//| Meni se vyhradne zadana pozice - drive se prepsaly stopy vsech   |
//| pozic strategie, takze druhy soubezny obchod dostal ramec toho   |
//| tretiho a o svuj puvodni prisel.                                 |
//|  ticket   - ticket (ID) upravovane pozice                        |
//|  distance - pozadovana delka SL i PT v cene                      |
//+------------------------------------------------------------------+
void AdjustPositionStops(const ulong ticket, const double distance)
  {
   if(ticket == 0 || distance <= 0.0)
      return;
   if(!PositionSelectByTicket(ticket))
      return;
   if(!IsOurPosition())
      return;

   const bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   const double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   const double sl    = NormalizeDouble(isBuy ? open - distance : open + distance, _Digits);
   const double tp    = NormalizeDouble(isBuy ? open + distance : open - distance, _Digits);

   if(MathAbs(PositionGetDouble(POSITION_SL) - sl) <= _Point &&
      MathAbs(PositionGetDouble(POSITION_TP) - tp) <= _Point)
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
      g_lastEvent = "obchodování vypnuto";
      return(false);
     }

   const string comment = "PUNTIKY " + (pl.isBuy ? "BUY" : "SELL");
   const bool   ok = pl.isBuy
                     ? g_trade.Buy(pl.lots, _Symbol, 0.0, pl.sl, pl.tp, comment)
                     : g_trade.Sell(pl.lots, _Symbol, 0.0, pl.sl, pl.tp, comment);

   if(!ok)
     {
      g_lastEvent = StringFormat("Chyba vstupu %d / %d",
                                 g_trade.ResultRetcode(), GetLastError());
      Print("PUNTIKY: ", g_lastEvent);
      return(false);
     }

   // Skutecna plnici cena se od navrhu lisi o skluz - SL i PT se
   // dorovnaji na realny vstup, aby RRR zustalo presne 1:1
   AdjustPositionStops(ResultPositionId(), pl.distance);

   g_lastEvent = StringFormat("%s %.2f lot @ %s  SL %s  PT %s  (%.0f b%s)",
                              pl.isBuy ? "BUY" : "SELL", pl.lots,
                              DoubleToString(pl.entry, _Digits),
                              DoubleToString(pl.sl, _Digits),
                              DoubleToString(pl.tp, _Digits),
                              pl.distance / _Point,
                              pl.barrier == PUNTIKY_BARRIER_NONE
                              ? "" : ", zkráceno k " + BarrierText(pl.barrier));
   Print("PUNTIKY: ", g_lastEvent);
   return(true);
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

   //--- Obe strany se resi stejnym kodem (0 = BUY, 1 = SELL)
   for(int dir = 0; dir < 2; dir++)
     {
      const bool   isBuy = (dir == 0);
      const double level = isBuy ? g_breakHigh : g_breakLow;
      if(level <= 0.0)
         continue;

      const bool wasBefore = !PriceBeyondLevel(isBuy, prevTF,  level, g_breakBuffer);
      const bool crossed   =  PriceBeyondLevel(isBuy, closeTF, level, g_breakBuffer);
      if(!wasBefore || !crossed)
         continue;

      const double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                 : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(price <= 0.0)
         continue;

      SEntryPlan pl = BuildPlan(isBuy, price, level, true);
      if(!pl.valid)
        {
         g_lastEvent = (isBuy ? "BUY" : "SELL") + " zamítnut: " + pl.reason;
         continue;
        }

      if(!OpenMarket(pl))
         continue;

      // Po vstupu je uroven spotrebovana - dalsi prilezitost prijde
      // az s novym swingem
      if(isBuy)
        {
         g_buyArmed = false;
         g_buyTaken = true;
        }
      else
        {
         g_sellArmed = false;
         g_sellTaken = true;
        }
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

   // V testeru ani pri optimalizaci WebRequest nefunguje
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
      return;

   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return;

   const double nearDist = InpHueNearPoints * _Point;

   //--- BUY: k urovni se cena blizi zespodu
   if(InpAllowBuy && g_planBuy.valid)
      HueCheckDirection(true, g_planBuy.entry, g_planBuy.entry - ask, nearDist,
                        g_hueBuyLevel, g_hueBuyTime);
   else
      g_hueBuyLevel = 0.0;    // navrh zmizel, priznak se uvolni

   //--- SELL: k urovni se cena blizi shora
   if(InpAllowSell && g_planSell.valid)
      HueCheckDirection(false, g_planSell.entry, bid - g_planSell.entry, nearDist,
                        g_hueSellLevel, g_hueSellTime);
   else
      g_hueSellLevel = 0.0;
  }

//+------------------------------------------------------------------+
//| Vyhodnoti jeden smer a pripadne posle upozorneni.                |
//|  isBuy     - smer navrhu                                         |
//|  level     - cena planovaneho vstupu                             |
//|  dist      - vzdalenost ceny k urovni (zaporna = uz je za ni)    |
//|  nearDist  - prah upozorneni v cene                              |
//|  sentLevel - uroven, pro kterou uz upozorneni odeslo (stav)      |
//|  sentTime  - cas posledniho odeslani (stav)                      |
//+------------------------------------------------------------------+
void HueCheckDirection(const bool isBuy, const double level, const double dist,
                       const double nearDist, double &sentLevel, datetime &sentTime)
  {
   // Priznak se uvolni az za hysterezi 25 % nad prahem - pri kolisani
   // presne na hranici pasma by se jinak blikalo porad dokola
   if(dist < 0.0 || dist > nearDist * 1.25)
     {
      sentLevel = 0.0;
      return;
     }

   // Mezipasmo hystereze: uz mimo prah, ale priznak se jeste drzi
   if(dist > nearDist)
      return;

   // Na stejnou uroven se hlasi jen jednou, dokud neni zapnute opakovani
   if(sentLevel > 0.0 && MathAbs(sentLevel - level) <= _Point)
     {
      if(InpHueRepeatMinutes <= 0)
         return;
      if(TimeCurrent() - sentTime < InpHueRepeatMinutes * 60)
         return;
     }

   // Priznak se nastavi i pri neuspechu, aby se pri vypadku sluzby
   // neposilal pozadavek na kazdem ticku
   sentLevel = level;
   sentTime  = TimeCurrent();
   HueSend(isBuy, level, dist);
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
      const int err = GetLastError();
      // 4014 = adresa neni v seznamu povolenych URL v nastaveni terminalu
      if(err == ERR_FUNCTION_NOT_ALLOWED)
         PrintFormat("PUNTIKY: Hue - adresa %s není povolená v Nástroje > Nastavení > "
                     "Expert Advisors > Povolit WebRequest.", InpHueUrl);
      else
         PrintFormat("PUNTIKY: Hue - požadavek na %s selhal, chyba %d", InpHueUrl, err);

      g_lastEvent = (isTest ? "Hue test selhal" : "Hue upozornění selhalo") +
                    " (chyba " + IntegerToString(err) + ")";
      return(false);
     }

   g_lastEvent = isTest
                 ? StringFormat("Hue test: HTTP %d", code)
                 : StringFormat("Hue %s: %.0f b k %s (HTTP %d)",
                                isBuy ? "BUY" : "SELL", dist / _Point,
                                DoubleToString(level, _Digits), code);
   Print("PUNTIKY: ", g_lastEvent, "  tělo: ", body);

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
//| Vykresli tlacitko pro rucni test upozorneni Hue.                 |
//|  y - svisle odsazeni v pixelech (pod poslednim radkem panelu)    |
//+------------------------------------------------------------------+
void DrawHueTestButton(const int y)
  {
   const string name = PUNTIKY_PREFIX + "BTN_HUETEST";

   if(!InpHueTestButton)
     {
      ObjectDelete(0, name);
      return;
     }

   // Vyska tlacitka se ridi pismem panelu, aby sedelo k jeho radkum
   const int h = MathMax(InpPanelFontSize * 2 + 4, 20);
   PuntikyButton(name, InpPanelX, y, 150, h, "TEST Hue",
              InpColorPanel, C'48,48,48', InpPanelFontSize, "Consolas",
              "Odešle testovací upozornění na " + InpHueUrl);
  }

//+------------------------------------------------------------------+
//| Textovy popis stavu jednoho smeru pro panel.                     |
//| Rozlisuje, jestli uz bylo obchodovano, jestli je navrh vubec     |
//| proveditelny a jestli je smer nabity (cena na spravne strane).   |
//|  isBuy - smer, pl - navrh vstupu tohoto smeru                    |
//+------------------------------------------------------------------+
string StateText(const bool isBuy, SEntryPlan &pl)
  {
   const string dir   = isBuy ? "BUY" : "SELL";
   const bool   taken = isBuy ? g_buyTaken : g_sellTaken;
   const bool   armed = isBuy ? g_buyArmed : g_sellArmed;

   if(taken)
      return(dir + " obchodován");
   if(!pl.valid)
      return(dir + " nelze" + (pl.reason == "" ? "" : " (" + pl.reason + ")"));
   if(!armed)
      return(dir + " blokován");
   return(dir + " připraven");
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
   // a delka i objem jsou z pozice v radku zrejme
   return(StringFormat("%s vstup %s  SL %s  PT %s  %.0f b  %.2f lot  k%d%s",
                       dir,
                       DoubleToString(pl.entry, _Digits),
                       DoubleToString(pl.sl, _Digits),
                       DoubleToString(pl.tp, _Digits),
                       pl.distance / _Point,
                       pl.lots,
                       pl.channelIdx + 1,
                       pl.barrier == PUNTIKY_BARRIER_NONE
                       ? "" : "  [PT k " + BarrierText(pl.barrier) + "]"));
  }

//+------------------------------------------------------------------+
//| Textovy popis aktualni pozice strategie pro panel                |
//+------------------------------------------------------------------+
string PositionText()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0)
         continue;
      if(!IsOurPosition())
         continue;

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

   return(StringFormat("pozice: žádná   (pending %d)", CountOrders()));
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
//|  lines - pole radku panelu                                       |
//|  n     - pocet dosud naplnenych radku (in/out)                   |
//|  text  - text radku                                              |
//+------------------------------------------------------------------+
void PanelAdd(string &lines[], int &n, const string text)
  {
   string rest = text;

   while(n < PUNTIKY_PANEL_MAX_LINES)
     {
      if(StringLen(rest) <= PUNTIKY_PANEL_MAX_CHARS)
        {
         lines[n++] = rest;
         return;
        }

      // Hledani mezery zprava, aby se nerezalo uprostred slova
      int cut = PUNTIKY_PANEL_MAX_CHARS;
      while(cut > 0 && StringGetCharacter(rest, cut) != ' ')
         cut--;
      if(cut <= 0)
         cut = PUNTIKY_PANEL_MAX_CHARS;   // jedno dlouhe slovo se ureze natvrdo

      lines[n++] = StringSubstr(rest, 0, cut);
      rest = "     " + StringSubstr(rest, cut + 1);
     }
  }

//+------------------------------------------------------------------+
//| Vykresleni informacniho panelu.                                  |
//| Prekresluji se jen radky, jejichz text se zmenil - panel ma pres |
//| deset radku a kazdy je nekolik volani do terminalu, takze plne   |
//| prekresleni na kazdem ticku stalo tisice volani za sekundu.      |
//+------------------------------------------------------------------+
void UpdatePanel()
  {
   if(!InpShowPanel)
     {
      // Uklid staci jednou, ne na kazdem volani
      if(g_panelShown != 0)
        {
         PuntikyDeleteObjects("PNL_");
         g_panelShown = 0;
        }
      DrawHueTestButton(InpPanelY);
      return;
     }

   string lines[PUNTIKY_PANEL_MAX_LINES];
   int    n = 0;

   PanelAdd(lines, n, "PUNTIKY CHANNEL BREAKOUT  |  " + _Symbol + "  |  účet " +
                      IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)));
   PanelAdd(lines, n, StringFormat("kanály %s   průraz %s   vstup %s   |  max %d b, SL:PT 1:1",
                                   TFText(InpChannelTF), TFText(InpBreakoutTF),
                                   TFText(InpEntryTF), InpMaxEntryPoints));

   //--- Prehled detekovanych kanalu. Kazdy kanal ma dva radky - na
   //--- jeden se pri limitu 63 znaku nevejde ani polovina udaju.
   const int channels = ChannelCount();
   if(channels <= 0)
      PanelAdd(lines, n, "kanály: žádný hlavní kanál nesplnil filtry");
   else
     {
      PanelAdd(lines, n, StringFormat("kanály: %d", channels));
      const datetime tNow = TimeCurrent();
      for(int i = 0; i < channels && n < PUNTIKY_PANEL_MAX_LINES - PUNTIKY_PANEL_RESERVE; i++)
        {
         PanelAdd(lines, n, StringFormat("  kanál %d (%s, měřítko %d)  šířka %.0f b  dotyků %d",
                                         i + 1,
                                         g_channels[i].baseIsLow ? "LOW základna" : "HIGH základna",
                                         g_channels[i].scaleIdx,
                                         g_channels[i].width / _Point,
                                         g_channels[i].touches));
         PanelAdd(lines, n, StringFormat("     uvnitř %.0f %%  body po C %d  hrany %s / %s",
                                         g_channels[i].containment * 100.0,
                                         g_channels[i].extraCount,
                                         DoubleToString(g_channels[i].LowerAt(tNow), _Digits),
                                         DoubleToString(g_channels[i].UpperAt(tNow), _Digits)));
        }
     }

   //--- Urovne prurazu a navrhy vstupu
   PanelAdd(lines, n, StringFormat("průraz %s %s:  H %s  (%s)",
                                   InpUseSwingLevels ? "swing" : "poslední",
                                   TFText(InpBreakoutTF),
                                   DoubleToString(g_breakHigh, _Digits),
                                   ShortTime(g_breakHighTime)));
   PanelAdd(lines, n, StringFormat("                  L %s  (%s)",
                                   DoubleToString(g_breakLow, _Digits),
                                   ShortTime(g_breakLowTime)));
   if(InpUseRelief)
      PanelAdd(lines, n, StringFormat("reliéfní přímky %s: %d  (režim: %s)",
                                      TFText(InpEntryTF), ReliefCount(),
                                      InpReliefMode == PUNTIKY_RELIEF_SKIP ? "přeskočit vstup"
                                                                           : "zkrátit PT"));

   //--- Stav upozorneni na zarovky Hue
   if(InpHueEnabled)
      PanelAdd(lines, n, StringFormat("Hue: upozornění %d b od úrovně vstupu  (BUY %s / SELL %s)",
                                      InpHueNearPoints,
                                      g_hueBuyLevel  > 0.0 ? "posláno" : "-",
                                      g_hueSellLevel > 0.0 ? "posláno" : "-"));

   // Kazdy smer na vlastnim radku - duvody zamitnuti byvaji dlouhe a
   // spolecny radek by se stejne zalomil
   PanelAdd(lines, n, "stav: " + StateText(true,  g_planBuy));
   PanelAdd(lines, n, "      " + StateText(false, g_planSell));
   PanelAdd(lines, n, PlanToText(g_planBuy));
   PanelAdd(lines, n, PlanToText(g_planSell));
   PanelAdd(lines, n, PositionText());

   if(g_lastEvent != "")
      PanelAdd(lines, n, "poslední: " + g_lastEvent);

   //--- Umisteni panelu. Kdyz je zapnuty one-click SELL/BUY panel MT5,
   //--- posune se panel pod nej, aby se s nim neprekryval.
   int panelY = InpPanelY;
   if(ChartGetInteger(0, CHART_SHOW_ONE_CLICK))
      panelY += InpPanelOneClickShift;

   // Vyska radku je samostatny parametr - odvozeni od velikosti pisma
   // nestaci na obrazovkach s vyssim DPI, kde se radky slepuji
   const int lineH = (InpPanelLineHeight > 0) ? InpPanelLineHeight
                                              : (InpPanelFontSize + 5);

   const bool moved = (panelY != g_panelY);
   g_panelY = panelY;

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
      PuntikyLabel(name, InpPanelX, panelY + i * lineH,
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

   //--- Tlacitko testu se kresli pod posledni radek panelu
   DrawHueTestButton(panelY + n * lineH + PUNTIKY_PANEL_BTN_GAP);

   if(changed)
      ChartRedraw();
  }
//+------------------------------------------------------------------+
