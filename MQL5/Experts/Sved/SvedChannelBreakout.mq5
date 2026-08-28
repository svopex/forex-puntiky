//+------------------------------------------------------------------+
//|                                        SvedChannelBreakout.mq5   |
//|                                                                  |
//|  Strategie "Sved Channel Breakout":                              |
//|   - kanaly ABCD se detekuji a kresli na M15, vcetne vnorenych    |
//|   - urovne pruzazu jsou HIGH / LOW swingove H1 svicky            |
//|     (bezna hodinova svicka signal nedava)                        |
//|   - vstup se vyhodnocuje na M1                                   |
//|   - delka vstupu max. 300 bodu, SL:PT = 1:1                      |
//|   - pokud je hrana kanalu bliz, PT se zkrati k teto hrane        |
//|     a SL se zkrati se stejne (RRR zustava 1:1)                   |
//|   - do grafu se kresli pouze kanaly a informace o vstupu         |
//+------------------------------------------------------------------+
#property copyright "Sved"
#property version   "1.11"
#property description "Prurazy swingovych H1 urovni uvnitr ABCD kanalu (kanaly M15, vstup M1)"

#include <Trade\Trade.mqh>
#include <Sved\SvedTypes.mqh>
#include <Sved\SvedSwings.mqh>
#include <Sved\SvedChannels.mqh>
#include <Sved\SvedRelief.mqh>
#include <Sved\SvedDraw.mqh>

//--- Timeframy
input group "=== Timeframy ==="
input ENUM_TIMEFRAMES InpChannelTF        = PERIOD_M15;   // TF pro detekci a kresleni kanalu
input ENUM_TIMEFRAMES InpBreakoutTF       = PERIOD_H1;    // TF urovni pruzazu (high/low svicky)
input ENUM_TIMEFRAMES InpEntryTF          = PERIOD_M1;    // TF vyhodnoceni vstupu

//--- Urovne pruzazu
input group "=== Urovne pruzazu ==="
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
input int             InpMinTouches       = 4;            // Minimalni pocet dotyku hran
input double          InpTouchTolFrac     = 0.15;         // Tolerance dotyku (zlomek sirky)
input double          InpMinContainment   = 0.85;         // Min. podil svicek uvnitr kanalu
input int             InpMaxChannels      = 3;            // Kolik hlavnich kanalu ponechat
input double          InpPierceTolFrac    = 0.05;         // Povolene proriznuti hran (zlomek sirky)
input double          InpInvalidTolFrac   = 0.15;         // Prah invalidace kanalu (zlomek sirky)
input int             InpBackCheckBars    = 20;           // Kolik baru pred bodem A jeste kontrolovat
input int             InpAnchorWindow     = 5;            // Okno, ve kterem musi byt A a C extremem
input double          InpDedupFrac        = 0.25;         // Prah shody dvou kanalu (zlomek sirky)
input bool            InpRequireInside    = true;         // Vyzadovat cenu uvnitr kanalu

//--- Vstup a rizeni obchodu
input group "=== Vstup ==="
input bool            InpEnableTrading    = true;         // Povolit obchodovani (false = jen kresleni)
input ENUM_SVED_ENTRY InpEntryMode        = SVED_ENTRY_PENDING;  // Rezim vstupu
input int             InpMaxEntryPoints   = 300;          // Maximalni delka vstupu (body)
input int             InpMinEntryPoints   = 100;          // Minimalni delka vstupu (body)
input int             InpBreakoutBuffer   = 10;           // Buffer nad/pod urovni pruzazu (body)
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
input ENUM_SVED_RELIEF InpReliefMode      = SVED_RELIEF_SKIP; // Co delat, kdyz primka vadi
input int             InpReliefLookback   = 2400;         // Kolik svicek TF vstupu analyzovat
input int             InpReliefSwingDepth = 10;           // Sirka okna pro hlavni swingy
input int             InpReliefScales     = 4;            // Pocet meritek swingu (10/20/40/80)
input int             InpReliefSwingGap   = 20;           // Max. odstup opor (pocet swingu)
input int             InpReliefMinSpan    = 30;           // Minimalni delka primky (bary)
input int             InpReliefMinTouches = 2;            // Minimalni pocet dotyku primky
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
input ENUM_SVED_LOT   InpLotMode          = SVED_LOT_RISK;  // Rezim vypoctu objemu (vychozi: dopocet z rizika)
input double          InpFixedLot         = 0.10;         // Pevny lot
input double          InpRiskPercent      = 1.0;          // Riziko na obchod (% uctu)

//--- Zobrazeni
input group "=== Zobrazeni ==="
input bool            InpShowChannels     = true;         // Kreslit kanaly
input bool            InpShowPoints       = true;         // Kreslit opory A B C D
input bool            InpShowBreakLevels  = true;         // Kreslit urovne pruzazu H1
input bool            InpShowEntryLevels  = true;         // Kreslit urovne planovaneho vstupu
input bool            InpShowRelief       = true;         // Kreslit reliefni primky
input bool            InpShowPanel        = true;         // Zobrazit informacni panel
input int             InpForwardBars      = 30;           // Prodlouzeni kanalu doprava (bary)
input color           InpColorHigh        = clrTomato;    // Barva HIGH usecky
input color           InpColorLow         = clrDodgerBlue;// Barva LOW usecky
input color           InpColorPoint       = clrSilver;    // Barva popisku A B C D
input color           InpColorBreak       = clrGoldenrod; // Barva urovni pruzazu
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
input string          InpShotFileName     = "SvedShot.png";      // Soubor snimku (MQL5/Files)
input string          InpShotRequestFile  = "SvedShot.request";  // Soubor pozadavku o snimek

//--- Globalni stav
CTrade        g_trade;                 // obchodni rozhrani
SChannelStats g_stats;                 // statistika posledni detekce kanalu
SReliefStats  g_reliefStats;           // statistika posledniho hledani reliefu
SReliefLine   g_relief[];              // reliefni primky vstupniho TF
int           g_reliefCount = 0;       // pocet reliefnich primek
int           g_lastPlanState = -1;    // stav platnosti navrhu (pro pending prikazy)
int           g_barsSinceShot = 0;     // pocitadlo baru pro periodicky snimek
SChannel      g_channels[];            // vybrane hlavni kanaly
int           g_channelCount = 0;      // pocet vybranych kanalu
int           g_atrHandle    = INVALID_HANDLE;

datetime      g_lastChannelBar  = 0;   // cas posledniho zpracovaneho baru TF kanalu
datetime      g_lastBreakoutBar = 0;   // cas posledniho zpracovaneho baru TF pruzazu
datetime      g_lastEntryBar    = 0;   // cas posledniho zpracovaneho baru TF vstupu

double        g_breakHigh = 0.0;       // uroven pruzazu nahoru (HIGH swingove svicky)
double        g_breakLow  = 0.0;       // uroven pruzazu dolu (LOW swingove svicky)
datetime      g_breakHighTime = 0;     // cas svicky, ze ktere uroven pochazi
datetime      g_breakLowTime  = 0;     // cas svicky, ze ktere uroven pochazi
bool          g_buyArmed   = false;    // smer BUY je pripraven (cena je pod urovni)
bool          g_sellArmed  = false;    // smer SELL je pripraven (cena je nad urovni)
bool          g_buyTaken   = false;    // v ramci teto svicky pruzazu jiz bylo nakoupeno
bool          g_sellTaken  = false;    // v ramci teto svicky pruzazu jiz bylo prodano
bool          g_buyBroken  = false;    // uroven pruzazu nahoru uz byla prorazena
bool          g_sellBroken = false;    // uroven pruzazu dolu uz byla prorazena

SEntryPlan    g_planBuy;               // aktualni navrh nakupu
SEntryPlan    g_planSell;              // aktualni navrh prodeje
string        g_lastEvent = "";        // posledni udalost pro panel
bool          g_tradingAllowed = true; // vysledek kontroly uctu

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
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);

   //--- Pojistka proti spusteni na jinem nez povolenem uctu
   g_tradingAllowed = true;
   if(InpAllowedAccount != 0 && AccountInfoInteger(ACCOUNT_LOGIN) != InpAllowedAccount)
     {
      g_tradingAllowed = false;
      Print("SVED: ucet ", AccountInfoInteger(ACCOUNT_LOGIN),
            " neodpovida povolenemu uctu ", InpAllowedAccount, " - obchodovani vypnuto.");
     }

   //--- ATR na TF kanalu slouzi jako filtr minimalni sirky kanalu
   g_atrHandle = iATR(_Symbol, InpChannelTF, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("SVED: nepodarilo se vytvorit ATR handle.");
      return(INIT_FAILED);
     }

   ResetPlan(g_planBuy,  true);
   ResetPlan(g_planSell, false);

   // Kontrolni vypis prepoctu bodu na cenu - u zlata se pocet desetinnych
   // mist mezi brokery lisi a maximalni delka vstupu se tim posouva
   PrintFormat("SVED: %s  digits=%d  point=%s  max. délka vstupu %d b = %s",
               _Symbol, _Digits, DoubleToString(_Point, _Digits),
               InpMaxEntryPoints, DoubleToString(InpMaxEntryPoints * _Point, _Digits));

   EventSetTimer(1);

   // Bez povoleni adresy v nastaveni terminalu skonci WebRequest chybou 4014,
   // proto se URL vypise hned pri startu
   if(InpHueEnabled)
      PrintFormat("SVED: upozornění Hue zapnuto - %d b od úrovně vstupu, %s "
                  "(adresu povol v Nástroje > Nastavení > Expert Advisors > Povolit WebRequest)",
                  InpHueNearPoints, InpHueUrl);

   //--- Prvni vypocet hned pri startu, aby byl graf ihned popsany
   RecalcChannels();
   RecalcRelief();
   RefreshBreakoutLevels();

   // V pending rezimu se prikazy zadaji hned - jinak by se cekalo
   // az na otevreni dalsi svicky TF pruzazu
   if(InpEntryMode == SVED_ENTRY_PENDING)
      PlacePendingOrders();

   UpdatePanel();
   ChartRedraw();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinicializace - uklid vlastnich objektu a handlu                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   SvedDeleteObjects();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Hlavni smycka - reaguje na kazdy tick                            |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- 1) Novy bar TF kanalu -> prepocet a prekresleni kanalu
   if(IsNewBar(InpChannelTF, g_lastChannelBar))
     {
      RecalcChannels();
      RebuildPlans();

      // Hrany kanalu se posunuly, takze SL i PT pending prikazu
      // uz neodpovidaji - prikazy se prepocitaji
      if(InpEntryMode == SVED_ENTRY_PENDING)
         PlacePendingOrders();
     }

   //--- 2) Novy bar TF pruzazu -> nove urovne high/low a nove navrhy
   if(IsNewBar(InpBreakoutTF, g_lastBreakoutBar))
     {
      RefreshBreakoutLevels();
      if(InpEntryMode == SVED_ENTRY_PENDING)
         PlacePendingOrders();
     }

   //--- 3) Pruraz urovne se hlida na kazdem ticku, aby se prikaz na
   //---    spotrebovanou uroven zrusil hned, ne az za minutu
   const bool wasBuyBroken  = g_buyBroken;
   const bool wasSellBroken = g_sellBroken;
   UpdateArming();
   const bool brokenChanged = (g_buyBroken != wasBuyBroken || g_sellBroken != wasSellBroken);

   //--- 4) Novy bar TF vstupu -> reliefni primky a prepocet navrhu
   const bool newEntryBar = IsNewBar(InpEntryTF, g_lastEntryBar);
   if(newEntryBar)
      RecalcRelief();

   // Kdyz uroven padla, je spotrebovana - hned se hleda dalsi swing,
   // jinak by expert cekal az na otevreni dalsi svicky TF pruzazu
   if(brokenChanged)
      RefreshBreakoutLevels();
   else
      if(newEntryBar)
         RebuildPlans();

   //--- 5) Vyhodnoceni vstupu
   if(InpEntryMode == SVED_ENTRY_M1_CLOSE)
     {
      if(newEntryBar)
         CheckEntryOnEntryTF();
     }
   else
     {
      // Kdyz se zmeni platnost navrhu (napr. do cesty vstoupila reliefni
      // primka nebo naopak zmizela), pending prikazy se prepocitaji
      const int planState = (g_planBuy.valid ? 1 : 0) + (g_planSell.valid ? 2 : 0);
      if(planState != g_lastPlanState)
        {
         g_lastPlanState = planState;
         PlacePendingOrders();
        }
      ManagePendingOrders();
     }

   //--- 6) Priblizeni k urovni vstupu rozblika zarovky Hue
   CheckHueAlerts();

   UpdatePanel();
  }

//+------------------------------------------------------------------+
//| Obchodni transakce - zachyti otevreni pozice.                    |
//| V pending rezimu se prikaz vyplni bez zasahu experta, takze bez  |
//| teto obsluhy by expert nevedel, ze uz na dane urovni obchodoval, |
//| a dal by nabizel vstup, ktery je davno vyplneny.                 |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
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

   const long dealType = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   if(dealType == DEAL_TYPE_BUY)
     {
      g_buyTaken = true;
      g_buyArmed = false;
      g_lastEvent = "BUY vyplněn @ " +
                    DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PRICE), _Digits);
     }
   else
      if(dealType == DEAL_TYPE_SELL)
        {
         g_sellTaken = true;
         g_sellArmed = false;
         g_lastEvent = "SELL vyplněn @ " +
                       DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PRICE), _Digits);
        }

   Print("SVED: ", g_lastEvent);

   // Navrhy uz neplati a druhy pending prikaz se rusi (OCO)
   RebuildPlans();
   ManagePendingOrders();
   UpdatePanel();
  }

//+------------------------------------------------------------------+
//| Timer - drzi panel aktualni i v obdobich bez ticku               |
//+------------------------------------------------------------------+
void OnTimer()
  {
   UpdatePanel();
   CheckScreenshotRequest();
  }

//+------------------------------------------------------------------+
//| Udalosti grafu - obsluha tlacitka pro test upozorneni Hue.       |
//| MT5 necha tlacitko po kliknuti zamacknute, proto se stav vraci   |
//| do puvodni polohy rucne.                                         |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam,
                  const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;
   if(sparam != SVED_PREFIX + "BTN_HUETEST")
      return;

   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   ChartRedraw();

   HueSendTest();
   UpdatePanel();
  }

//+------------------------------------------------------------------+
//| Detekce nove svicky na zadanem timeframu.                        |
//| Vraci true prave jednou pri otevreni nove svicky.                |
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
//| Vynuluje navrh vstupu                                            |
//+------------------------------------------------------------------+
void ResetPlan(SEntryPlan &pl, const bool isBuy)
  {
   pl.valid         = false;
   pl.isBuy         = isBuy;
   pl.trigger       = 0.0;
   pl.entry         = 0.0;
   pl.sl            = 0.0;
   pl.tp            = 0.0;
   pl.distance      = 0.0;
   pl.lots          = 0.0;
   pl.limitedByEdge = false;
   pl.edgePrice     = 0.0;
   pl.blockedByRelief = false;
   pl.reliefPrice   = 0.0;
   pl.channelIdx    = -1;
   pl.reason        = "";
  }

//+------------------------------------------------------------------+
//| Aktualni hodnota ATR na TF kanalu (0 pri chybe)                  |
//+------------------------------------------------------------------+
double GetATR()
  {
   double buf[];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, buf) != 1)
      return(0.0);
   return(buf[0]);
  }

//+------------------------------------------------------------------+
//| Prepocet kanalu z historie TF kanalu a jejich vykresleni         |
//+------------------------------------------------------------------+
void RecalcChannels()
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, false);   // index 0 = nejstarsi svicka

   // Bereme jen uzavrene svicky (od shiftu 1), aby se kanaly nemenily
   // uvnitr rozpracovane svicky
   const int copied = CopyRates(_Symbol, InpChannelTF, 1, InpLookbackBars, rates);
   if(copied < 50)
     {
      g_channelCount = 0;
      return;
     }

   SChannelParams p;
   p.minSpanBars    = InpMinSpanBars;
   p.minWidthPrice  = InpMinWidthPoints * _Point;
   p.minWidthATR    = InpMinWidthATR;
   p.atr            = GetATR();
   p.minTouches     = InpMinTouches;
   p.touchTolFrac   = InpTouchTolFrac;
   p.minContainment = InpMinContainment;
   p.maxChannels    = MathMax(InpMaxChannels, 1);
   p.maxAgeBars     = InpMaxAgeBars;
   p.maxSwingGap    = InpMaxSwingGap;
   p.scales         = MathMax(InpSwingScales, 1);
   p.pierceTolFrac  = InpPierceTolFrac;
   p.invalidTolFrac = InpInvalidTolFrac;
   p.backCheckBars  = InpBackCheckBars;
   p.anchorWindow   = InpAnchorWindow;
   p.dedupFrac      = InpDedupFrac;
   p.requireInside  = InpRequireInside;

   // Kanaly se hledaji ve vice meritkach, aby vznikl i kanal v kanalu
   g_channelCount = SvedBuildChannels(rates, p, InpSwingDepth, InpSwingScales,
                                      g_channels, g_stats);

   PrintDiagnostics(copied);
   RedrawChannels();

   //--- Periodicky snimek grafu pro ladeni
   if(InpShotEveryBars > 0)
     {
      g_barsSinceShot++;
      if(g_barsSinceShot >= InpShotEveryBars)
        {
         g_barsSinceShot = 0;
         SaveScreenshot("periodicky");
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

   PrintFormat("SVED diag: %d svíček %s, ATR %.2f, kombinací A-C %d",
               bars, EnumToString(InpChannelTF), GetATR(), g_stats.generated);

   PrintFormat("SVED diag: zamítnuto - bod B %d, délka %d, stáří %d, šířka %d, "
               "opory %d, proříznuto/proraženo %d, dotyky %d, uvnitř %d, cena mimo %d",
               g_stats.noB, g_stats.span, g_stats.age, g_stats.width,
               g_stats.anchors, g_stats.pierced, g_stats.touches,
               g_stats.containment, g_stats.outside);

   PrintFormat("SVED diag: prošlo %d, vybráno %d", g_stats.passed, g_stats.selected);

   if(InpUseRelief)
     {
      PrintFormat("SVED diag: reliéfních přímek %s: %d", 
                  EnumToString(InpEntryTF), g_reliefCount);
      PrintFormat("SVED diag: reliéf filtr - dvojic %d, délka %d, stáří %d, drift %d, "
                  "proraženo %d, střed %d, dotyky %d -> prošlo %d, vybráno %d",
                  g_reliefStats.pairs, g_reliefStats.span, g_reliefStats.age,
                  g_reliefStats.drift, g_reliefStats.pierced, g_reliefStats.midTouch,
                  g_reliefStats.touches, g_reliefStats.passed, g_reliefStats.selected);
      for(int i = 0; i < g_reliefCount; i++)
         PrintFormat("SVED diag: reliéf %d (%s) %s @ %s -> %s @ %s, dotyků %d, "
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

   for(int i = 0; i < g_channelCount; i++)
     {
      PrintFormat("SVED diag: kanál %d (měřítko %d, %s) A %s @ %s | B %s @ %s | C %s @ %s",
                  i + 1, g_channels[i].scaleIdx,
                  g_channels[i].baseIsLow ? "LOW základna" : "HIGH základna",
                  DoubleToString(g_channels[i].pA, _Digits),
                  TimeToString(g_channels[i].tA, TIME_DATE | TIME_MINUTES),
                  DoubleToString(g_channels[i].pB, _Digits),
                  TimeToString(g_channels[i].tB, TIME_DATE | TIME_MINUTES),
                  DoubleToString(g_channels[i].pC, _Digits),
                  TimeToString(g_channels[i].tC, TIME_DATE | TIME_MINUTES));

      PrintFormat("SVED diag: kanál %d - šířka %.0f b, dotyků %d, uvnitř %.0f %%, "
                  "délka %d barů, stáří %d barů, skóre %.2f, body po C %d",
                  i + 1, g_channels[i].width / _Point, g_channels[i].touches,
                  g_channels[i].containment * 100.0, g_channels[i].spanBars,
                  g_channels[i].ageBars, g_channels[i].score, g_channels[i].extraCount);
     }
  }

//+------------------------------------------------------------------+
//| Ulozi snimek grafu do MQL5/Files pro ladeni                      |
//+------------------------------------------------------------------+
void SaveScreenshot(const string reason)
  {
   const int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   const int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(w <= 0 || h <= 0)
      return;

   if(ChartScreenShot(0, InpShotFileName, w, h, ALIGN_RIGHT))
      PrintFormat("SVED: snímek grafu uložen (%s) -> MQL5/Files/%s  [%dx%d]",
                  reason, InpShotFileName, w, h);
   else
      PrintFormat("SVED: snímek grafu se nepodařilo uložit, chyba %d", GetLastError());
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
//| Prekresleni vsech kanalu (HIGH a LOW usecky + opory A B C D)     |
//+------------------------------------------------------------------+
void RedrawChannels()
  {
   SvedDeleteObjects("CH");
   SvedDeleteObjects("PT");
   if(!InpShowChannels || g_channelCount <= 0)
     {
      ChartRedraw();
      return;
     }

   // Prava hranice usecek - kousek do budoucnosti, aby bylo videt,
   // kam kanal smeruje
   const datetime tEnd = TimeCurrent() + (datetime)(PeriodSeconds(InpChannelTF) * InpForwardBars);

   //--- Nejprve usecky vsech kanalu
   for(int i = 0; i < g_channelCount; i++)
      SvedDrawChannel(g_channels[i], i, tEnd, InpColorHigh, InpColorLow);

   //--- Popisky opor se sesbiraji ze vsech kanalu najednou a teprve pak
   //--- vykresli - popisky padnouci na stejne misto se slouci do jednoho
   //--- textu (napr. "E1 E3"), takze se pri sdilene opore neprepisuji
   if(InpShowPoints)
     {
      SChannelLabel labels[];
      ArrayResize(labels, 0);
      for(int i = 0; i < g_channelCount; i++)
         SvedCollectChannelLabels(g_channels[i], i, labels);

      // Tolerance slucovani vychazi z ATR, aby sedela na volatilite trhu
      const double atr = GetATR();
      const double mergeTol = (atr > 0.0) ? atr * InpLabelMergeATR
                                          : 10.0 * _Point;
      SvedDrawLabels(labels, InpColorPoint, InpPointFontSize, mergeTol);
     }

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
      g_reliefCount = 0;
      DrawRelief();
      return;
     }

   MqlRates rates[];
   ArraySetAsSeries(rates, false);   // index 0 = nejstarsi svicka

   const int copied = CopyRates(_Symbol, InpEntryTF, 1, InpReliefLookback, rates);
   if(copied < 50)
     {
      g_reliefCount = 0;
      return;
     }

   SReliefParams rp;
   rp.swingDepth  = InpReliefSwingDepth;
   rp.scales      = InpReliefScales;
   rp.maxSwingGap = InpReliefSwingGap;
   rp.minSpanBars = InpReliefMinSpan;
   rp.minTouches  = InpReliefMinTouches;
   rp.pierceTol   = InpReliefPierceTol * _Point;
   rp.wickTol     = InpReliefWickTol * _Point;
   rp.touchTol    = InpReliefTouchTol * _Point;
   rp.dedupTol    = InpReliefDedupTol * _Point;
   rp.maxAgeFactor = InpReliefMaxAge;
   rp.maxDrift     = InpReliefMaxDrift * _Point;
   rp.needMidTouch = InpReliefMidTouch;
   rp.midTol       = InpReliefMidTol * _Point;
   rp.midFrom      = InpReliefMidFrom;
   rp.midTo        = InpReliefMidTo;
   rp.maxLines    = MathMax(InpMaxReliefLines, 1);

   g_reliefCount = SvedBuildReliefLines(rates, rp, g_relief, g_reliefStats);
   DrawRelief();
  }

//+------------------------------------------------------------------+
//| Vykresleni reliefnich primek                                     |
//+------------------------------------------------------------------+
void DrawRelief()
  {
   SvedDeleteObjects("REL_");
   if(!InpShowRelief || g_reliefCount <= 0)
      return;

   const datetime tEnd = TimeCurrent() +
                         (datetime)(PeriodSeconds(InpEntryTF) * InpReliefForwardBars);

   for(int i = 0; i < g_reliefCount; i++)
      SvedTrendLine(SVED_PREFIX + "REL_" + IntegerToString(i),
                    g_relief[i].t1, g_relief[i].p1, tEnd, g_relief[i].ValueAt(tEnd),
                    InpColorRelief, 1, STYLE_DOT, true,
                    StringFormat("Reliéfní přímka (%s), dotyků %d",
                                 g_relief[i].isHigh ? "odpor" : "podpora",
                                 g_relief[i].touches));
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Nacte HIGH / LOW posledni uzavrene svicky TF pruzazu, resetuje   |
//| priznaky a prekresli urovne pruzazu.                             |
//+------------------------------------------------------------------+
void RefreshBreakoutLevels()
  {
   double   h = 0.0, l = 0.0;
   datetime th = 0, tl = 0;

   if(InpUseSwingLevels)
     {
      // Proraz se jen swingovy vrchol / dno, ne kazda hodinova svicka
      if(!FindBreakoutSwings(h, th, l, tl))
         return;
     }
   else
     {
      // Zalozni rezim: high/low posledni uzavrene svicky TF pruzazu
      h  = iHigh(_Symbol, InpBreakoutTF, 1);
      l  = iLow(_Symbol, InpBreakoutTF, 1);
      th = iTime(_Symbol, InpBreakoutTF, 1);
      tl = th;
     }

   if(h <= 0.0 || l <= 0.0)
      return;

   // Priznaky se resetuji jen pri zmene urovne - na jednom swingu
   // se tedy obchoduje nejvyse jednou
   if(th != g_breakHighTime)
     {
      g_buyTaken = false;
      g_buyArmed = false;
     }
   if(tl != g_breakLowTime)
     {
      g_sellTaken = false;
      g_sellArmed = false;
     }

   g_breakHigh     = h;
   g_breakLow      = l;
   g_breakHighTime = th;
   g_breakLowTime  = tl;

   // Uroven mohla byt prorazena jeste pred timto prepoctem (nebo pred
   // startem experta) - dohleda se to zpetne z historie vstupniho TF
   g_buyBroken  = LevelAlreadyBroken(true, g_breakHigh, g_breakHighTime);
   g_sellBroken = LevelAlreadyBroken(false, g_breakLow, g_breakLowTime);

   UpdateArming();
   RebuildPlans();
   DrawBreakoutLevels();
  }

//+------------------------------------------------------------------+
//| Najde posledni swingovy vrchol a posledni swingove dno na TF     |
//| pruzazu. Prorazi se tedy jen H1 svicka, ktera je zaroven          |
//| swingovym bodem - beznou hodinovou svicku strategie ignoruje.     |
//|  hi, hiTime - cena a cas posledniho swingoveho vrcholu            |
//|  lo, loTime - cena a cas posledniho swingoveho dna                |
//| Vraci false, pokud se oba typy swingu nepodarilo najit.           |
//+------------------------------------------------------------------+
bool FindBreakoutSwings(double &hi, datetime &hiTime, double &lo, datetime &loTime)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, false);   // index 0 = nejstarsi svicka

   // Jen uzavrene svicky - swing se potvrdi az svickami za nim
   const int copied = CopyRates(_Symbol, InpBreakoutTF, 1, InpBreakLookback, rates);
   if(copied < InpBreakSwingDepth * 2 + 3)
      return(false);

   SSwing sw[];
   const int ns = SvedDetectSwings(rates, InpBreakSwingDepth, sw);
   if(ns < 2)
      return(false);

   const double buffer = InpBreakoutBuffer * _Point;

   // Hleda se posledni swing, ktery cena jeste neprorazila. Prorazena
   // uroven je spotrebovana, takze se pokracuje k predchozimu swingu -
   // typicky vyraznejsimu, ktery je stale platnou hranici.
   bool foundHi = false, foundLo = false;
   for(int i = ns - 1; i >= 0; i--)
     {
      if(sw[i].isHigh && !foundHi && !SwingBroken(rates, sw[i], true, buffer))
        {
         hi = sw[i].price;
         hiTime = sw[i].time;
         foundHi = true;
        }
      if(!sw[i].isHigh && !foundLo && !SwingBroken(rates, sw[i], false, buffer))
        {
         lo = sw[i].price;
         loTime = sw[i].time;
         foundLo = true;
        }
      if(foundHi && foundLo)
         break;
     }

   return(foundHi && foundLo);
  }

//+------------------------------------------------------------------+
//| Test, zda cena swingovou uroven po jejim vzniku uz prorazila.     |
//| Pracuje nad svickami TF pruzazu, ktere uz ma volajici nactene.    |
//+------------------------------------------------------------------+
bool SwingBroken(const MqlRates &rates[], const SSwing &s, const bool isHigh,
                 const double buffer)
  {
   const int n = ArraySize(rates);
   for(int i = s.index + 1; i < n; i++)
     {
      if(isHigh && rates[i].high > s.price + buffer)
         return(true);
      if(!isHigh && rates[i].low < s.price - buffer)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Nastavi priznaky pripravenosti smeru.                            |
//| Smer je "nabity" teprve tehdy, kdyz je cena na spravne strane    |
//| urovne - zabranuje vstupu do jiz probehleho pruzazu (napr. po    |
//| vikendovem gapu nebo pri startu experta uprostred pohybu).       |
//+------------------------------------------------------------------+
void UpdateArming()
  {
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0.0)
      return;

   const double buffer = InpBreakoutBuffer * _Point;

   // Jakmile cena uroven jednou prorazi, je smer vycerpany - dalsi
   // prilezitost prijde az s novym swingem. Bez teto pameti by se
   // prikaz zadal znovu pokazde, kdyz se cena k urovni vrati.
   if(bid > g_breakHigh + buffer)
      g_buyBroken = true;
   if(bid < g_breakLow - buffer)
      g_sellBroken = true;

   if(bid <= g_breakHigh)
      g_buyArmed = true;
   if(bid >= g_breakLow)
      g_sellArmed = true;
  }

//+------------------------------------------------------------------+
//| Zjisti, zda cena uroven prorazila uz driv - od okamziku, kdy     |
//| svingova svicka skoncila, do soucasnosti.                        |
//| Bez teto kontroly by expert po restartu ozivil davno spotrebovane|
//| urovne a zadal na ne prikazy.                                    |
//+------------------------------------------------------------------+
bool LevelAlreadyBroken(const bool isBuy, const double level, const datetime levelTime)
  {
   if(level <= 0.0 || levelTime <= 0)
      return(false);

   // Swingova svicka sama urovni tvori, sleduje se az to, co bylo po ni
   const datetime from = levelTime + (datetime)PeriodSeconds(InpBreakoutTF);
   const datetime to   = TimeCurrent();
   if(from >= to)
      return(false);

   MqlRates r[];
   ArraySetAsSeries(r, false);
   const int copied = CopyRates(_Symbol, InpEntryTF, from, to, r);
   if(copied <= 0)
      return(false);

   const double buffer = InpBreakoutBuffer * _Point;
   for(int i = 0; i < copied; i++)
     {
      if(isBuy && r[i].high > level + buffer)
         return(true);
      if(!isBuy && r[i].low < level - buffer)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Prepocita navrhy vstupu pro oba smery a vykresli jejich urovne.  |
//| Navrhy se pocitaji z hypotetickeho vstupu na urovni pruzazu,     |
//| takze panel ukazuje parametry obchodu jeste pred jeho vznikem.   |
//+------------------------------------------------------------------+
void RebuildPlans()
  {
   const double buffer = InpBreakoutBuffer * _Point;

   if(g_breakHigh > 0.0)
      g_planBuy = BuildPlan(true, g_breakHigh + buffer, g_breakHigh, true);
   if(g_breakLow > 0.0)
      g_planSell = BuildPlan(false, g_breakLow - buffer, g_breakLow, true);

   DrawEntryLevels();
  }

//+------------------------------------------------------------------+
//| Sestavi navrh vstupu pro jeden smer.                             |
//|  isBuy      - smer obchodu                                       |
//|  entryPrice - predpokladana cena vstupu                          |
//|  trigger    - uroven pruzazu (high/low svicky TF pruzazu)        |
//| Delka vstupu je min(450 bodu, vzdalenost k nejblizsi hrane       |
//| kanalu ve smeru obchodu); SL ma vzdy stejnou delku jako PT.      |
//+------------------------------------------------------------------+
SEntryPlan BuildPlan(const bool isBuy, const double entryPrice, const double trigger,
                     const bool checkReachable)
  {
   SEntryPlan pl;
   ResetPlan(pl, isBuy);
   pl.trigger = trigger;
   pl.entry   = NormalizeDouble(entryPrice, _Digits);

   //--- Navrh ma smysl jen dokud pruraz teprve ceka. Kdyz uz cena
   //--- urovni prosla, neni co prorazit a STOP prikaz nad/pod trhem
   //--- by stejne neslo zadat - takovy navrh se nekresli ani nenabizi.
   if(checkReachable)
     {
      // Otevrena pozice navrh rusi - dokud bezi obchod, neni co nabizet
      if(CountPositions() >= InpMaxPositions)
        {
         pl.reason = "pozice již otevřena";
         return(pl);
        }

      // Na jedne swingove urovni se obchoduje nejvyse jednou
      if(isBuy ? g_buyTaken : g_sellTaken)
        {
         pl.reason = "tato úroveň už obchodována";
         return(pl);
        }

      // Uroven, kterou cena uz jednou prorazila, je spotrebovana -
      // i kdyz se cena mezitim vratila zpatky
      if(isBuy ? g_buyBroken : g_sellBroken)
        {
         pl.reason = "úroveň už byla proražena";
         return(pl);
        }

      const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(isBuy && ask > 0.0 && pl.entry <= ask)
        {
         pl.reason = "průraz už proběhl";
         return(pl);
        }
      if(!isBuy && bid > 0.0 && pl.entry >= bid)
        {
         pl.reason = "průraz už proběhl";
         return(pl);
        }
     }

   if(g_channelCount <= 0)
     {
      pl.reason = "žádný platný kanál";
      return(pl);
     }

   const datetime tNow = TimeCurrent();

   //--- Pruraz musi nastat uvnitr kanalu
   const int ci = SvedFindContainingChannel(g_channels, tNow, trigger, InpInsideTolFrac);
   if(ci < 0)
     {
      pl.reason = "průraz mimo kanál";
      return(pl);
     }
   pl.channelIdx = ci;

   const double maxDist = InpMaxEntryPoints * _Point;
   const double minDist = InpMinEntryPoints * _Point;

   //--- Nejblizsi hrana ve smeru obchodu (vcetne hran vnorenych kanalu)
   const datetime tProj = tNow + (datetime)(PeriodSeconds(InpChannelTF) * InpEdgeProjBars);
   double edge = 0.0;
   const double edgeDist = SvedDistanceToNextEdge(g_channels, tNow, tProj, pl.entry, isBuy, edge);

   double dist = maxDist;
   if(edgeDist >= 0.0)
     {
      pl.edgePrice = edge;
      // Neni-li k hrane dost mista, zkratime PT tak, aby se pred ni vesel
      const double avail = edgeDist - InpEdgeBuffer * _Point;
      if(avail < dist)
        {
         dist = avail;
         pl.limitedByEdge = true;
        }
     }

   //--- Reliefni primka ve smeru obchodu.
   //--- Primka blize nez planovany PT stoji prurazu v ceste: bud se
   //--- vstup preskoci, nebo se PT zkrati pred ni (podle InpReliefMode).
   if(InpUseRelief && g_reliefCount > 0)
     {
      double relPrice = 0.0;
      const double relDist = SvedNearestRelief(g_relief, tNow, pl.entry, isBuy, relPrice);

      if(relDist >= 0.0 && relDist < dist)
        {
         pl.reliefPrice = relPrice;

         if(InpReliefMode == SVED_RELIEF_SKIP)
           {
            pl.blockedByRelief = true;
            pl.reason = StringFormat("v cestě reliéfní přímka (%.0f b, %s)",
                                     relDist / _Point,
                                     DoubleToString(relPrice, _Digits));
            return(pl);
           }

         // Zkraceni PT pred primku, SL se zkrati stejne (RRR 1:1)
         const double avail = relDist - InpReliefBuffer * _Point;
         if(avail < dist)
           {
            dist = avail;
            pl.limitedByEdge = true;
            pl.edgePrice = relPrice;
           }
        }
     }

   //--- Kontrola minimalni delky vstupu a stop-levelu brokera
   const double stopsLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(dist < minDist)
     {
      // Rozlisime, co misto ubralo - hrana kanalu nebo reliefni primka
      const string barrier = (pl.reliefPrice > 0.0 && pl.edgePrice == pl.reliefPrice)
                             ? "reliéfní přímce" : "hraně";
      pl.reason = StringFormat("málo místa k %s (%.0f b)", barrier, dist / _Point);
      return(pl);
     }
   if(dist <= stopsLevel)
     {
      pl.reason = "délka pod stop-level brokera";
      return(pl);
     }

   pl.distance = dist;
   pl.sl = NormalizeDouble(isBuy ? pl.entry - dist : pl.entry + dist, _Digits);
   pl.tp = NormalizeDouble(isBuy ? pl.entry + dist : pl.entry - dist, _Digits);
   pl.lots = CalcLot(dist);

   if(pl.lots <= 0.0)
     {
      pl.reason = "nelze určit objem";
      return(pl);
     }

   pl.valid = true;
   return(pl);
  }

//+------------------------------------------------------------------+
//| Vypocet objemu pozice.                                           |
//|  slDistance - vzdalenost stop lossu v cene                       |
//| V rezimu rizika se objem dopocita tak, aby ztrata na SL          |
//| odpovidala zadanemu procentu zustatku uctu.                      |
//+------------------------------------------------------------------+
double CalcLot(const double slDistance)
  {
   const double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double lot = InpFixedLot;

   if(InpLotMode == SVED_LOT_RISK)
     {
      const double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
      const double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      const double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

      if(balance > 0.0 && tickValue > 0.0 && tickSize > 0.0 && slDistance > 0.0)
        {
         // Ztrata na 1 lot pri zasazeni SL
         const double lossPerLot = (slDistance / tickSize) * tickValue;
         if(lossPerLot > 0.0)
            lot = (balance * InpRiskPercent / 100.0) / lossPerLot;
        }
     }

   //--- Zaokrouhleni na krok objemu a orezani do povoleneho rozsahu
   if(lotStep > 0.0)
      lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(lot, minLot);
   lot = MathMin(lot, maxLot);

   return(NormalizeDouble(lot, 2));
  }

//+------------------------------------------------------------------+
//| Pocet otevrenych pozic strategie na aktualnim symbolu            |
//+------------------------------------------------------------------+
int CountPositions()
  {
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
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
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_MAGIC) == InpMagic)
         cnt++;
     }
   return(cnt);
  }

//+------------------------------------------------------------------+
//| Zrusi vsechny pending prikazy strategie                          |
//+------------------------------------------------------------------+
void CancelPendingOrders()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_MAGIC) == InpMagic)
         g_trade.OrderDelete(ticket);
     }
  }

//+------------------------------------------------------------------+
//| Spolecne podminky, za kterych smi strategie otevrit obchod       |
//+------------------------------------------------------------------+
bool CanTrade()
  {
   if(!InpEnableTrading || !g_tradingAllowed)
      return(false);
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return(false);
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      return(false);
   if(CountPositions() >= InpMaxPositions)
      return(false);
   return(true);
  }

//+------------------------------------------------------------------+
//| Vyhodnoceni pruzazu na TF vstupu (M1).                           |
//| Pruraz je potvrzen az uzavrenim svicky vstupniho TF za urovni    |
//| HIGH / LOW posledni uzavrene svicky TF pruzazu (H1).             |
//+------------------------------------------------------------------+
void CheckEntryOnEntryTF()
  {
   if(g_breakHigh <= 0.0 || g_breakLow <= 0.0)
      return;
   if(!CanTrade())
      return;

   const double closeM1 = iClose(_Symbol, InpEntryTF, 1);
   const double prevM1  = iClose(_Symbol, InpEntryTF, 2);
   if(closeM1 <= 0.0 || prevM1 <= 0.0)
      return;

   const double buffer = InpBreakoutBuffer * _Point;

   // Vstupuje se jen na skutecnem prechodu pres uroven - predchozi
   // svicka musi byt jeste pod ni. Bez toho by expert vstoupil i dlouho
   // po pruzazu, treba az potom, co pominula prekazka v podobe reliefu.
   const bool crossedUp   = (prevM1 <= g_breakHigh + buffer && closeM1 > g_breakHigh + buffer);
   const bool crossedDown = (prevM1 >= g_breakLow - buffer && closeM1 < g_breakLow - buffer);

   //--- Pruraz nahoru
   if(InpAllowBuy && g_buyArmed && !g_buyTaken && crossedUp)
     {
      const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      SEntryPlan pl = BuildPlan(true, ask, g_breakHigh, false);
      if(pl.valid)
        {
         // Po vstupu se smer uzavre az do nove svicky TF pruzazu
         if(OpenMarket(pl))
           {
            g_buyArmed = false;
            g_buyTaken = true;
           }
        }
      else
        {
         g_lastEvent = "BUY zamítnut: " + pl.reason;
        }
     }

   //--- Pruraz dolu
   if(InpAllowSell && g_sellArmed && !g_sellTaken && crossedDown)
     {
      const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      SEntryPlan pl = BuildPlan(false, bid, g_breakLow, false);
      if(pl.valid)
        {
         if(OpenMarket(pl))
           {
            g_sellArmed = false;
            g_sellTaken = true;
           }
        }
      else
        {
         g_lastEvent = "SELL zamítnut: " + pl.reason;
        }
     }
  }

//+------------------------------------------------------------------+
//| Otevreni pozice podle navrhu vstupu                              |
//+------------------------------------------------------------------+
bool OpenMarket(SEntryPlan &pl)
  {
   const string comment = "SVED " + (pl.isBuy ? "BUY" : "SELL");
   bool ok = false;

   if(pl.isBuy)
      ok = g_trade.Buy(pl.lots, _Symbol, 0.0, pl.sl, pl.tp, comment);
   else
      ok = g_trade.Sell(pl.lots, _Symbol, 0.0, pl.sl, pl.tp, comment);

   // Skutecna plnici cena se od navrhu lisi o skluz - SL i PT se
   // dorovnaji na realny vstup, aby RRR zustalo presne 1:1
   if(ok)
      AdjustPositionStops(pl.distance);

   if(ok)
      g_lastEvent = StringFormat("%s %.2f lot @ %s  SL %s  PT %s  (%.0f b%s)",
                                 pl.isBuy ? "BUY" : "SELL", pl.lots,
                                 DoubleToString(pl.entry, _Digits),
                                 DoubleToString(pl.sl, _Digits),
                                 DoubleToString(pl.tp, _Digits),
                                 pl.distance / _Point,
                                 pl.limitedByEdge ? ", zkráceno hranou" : "");
   else
      g_lastEvent = StringFormat("Chyba vstupu %d / %d", g_trade.ResultRetcode(), GetLastError());

   Print("SVED: ", g_lastEvent);
   return(ok);
  }

//+------------------------------------------------------------------+
//| Dorovna SL a PT otevrene pozice na skutecnou vstupni cenu tak,   |
//| aby obe vzdalenosti odpovidaly zadane delce vstupu (RRR 1:1).    |
//| Uprava se provede jen pri rozdilu vetsim nez 1 bod.              |
//+------------------------------------------------------------------+
void AdjustPositionStops(const double distance)
  {
   if(distance <= 0.0)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      const bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      const double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      const double sl    = NormalizeDouble(isBuy ? open - distance : open + distance, _Digits);
      const double tp    = NormalizeDouble(isBuy ? open + distance : open - distance, _Digits);

      if(MathAbs(PositionGetDouble(POSITION_SL) - sl) > _Point ||
         MathAbs(PositionGetDouble(POSITION_TP) - tp) > _Point)
         g_trade.PositionModify(ticket, sl, tp);
     }
  }

//+------------------------------------------------------------------+
//| Umisteni pending STOP prikazu na urovne pruzazu.                 |
//| Pouziva se v rezimu SVED_ENTRY_PENDING - prikazy se pri kazde    |
//| nove svicce TF pruzazu prepocitaji na aktualni high / low.       |
//+------------------------------------------------------------------+
void PlacePendingOrders()
  {
   CancelPendingOrders();
   if(!CanTrade())
      return;

   // Buffer nad/pod urovni pruzazu je jiz zapocten v navrzich vstupu
   const double ask        = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double stopsLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   //--- BuyStop nad HIGH svicky TF pruzazu
   if(InpAllowBuy && g_planBuy.valid && g_planBuy.entry > ask + stopsLevel)
     {
      if(!g_trade.BuyStop(g_planBuy.lots, g_planBuy.entry, _Symbol,
                          g_planBuy.sl, g_planBuy.tp, ORDER_TIME_GTC, 0, "SVED BUYSTOP"))
         Print("SVED: BuyStop selhal, retcode ", g_trade.ResultRetcode());
     }

   //--- SellStop pod LOW svicky TF pruzazu
   if(InpAllowSell && g_planSell.valid && g_planSell.entry < bid - stopsLevel)
     {
      if(!g_trade.SellStop(g_planSell.lots, g_planSell.entry, _Symbol,
                           g_planSell.sl, g_planSell.tp, ORDER_TIME_GTC, 0, "SVED SELLSTOP"))
         Print("SVED: SellStop selhal, retcode ", g_trade.ResultRetcode());
     }
  }

//+------------------------------------------------------------------+
//| Sprava pending prikazu - po vzniku pozice zrusi zbyle prikazy,   |
//| aby oba smery nebezely soucasne (OCO).                           |
//+------------------------------------------------------------------+
void ManagePendingOrders()
  {
   if(CountPositions() > 0 && CountOrders() > 0)
      CancelPendingOrders();
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
         PrintFormat("SVED: Hue - adresa %s není povolená v Nástroje > Nastavení > "
                     "Expert Advisors > Povolit WebRequest.", InpHueUrl);
      else
         PrintFormat("SVED: Hue - požadavek na %s selhal, chyba %d", InpHueUrl, err);

      g_lastEvent = (isTest ? "Hue test selhal" : "Hue upozornění selhalo") +
                    " (chyba " + IntegerToString(err) + ")";
      return(false);
     }

   g_lastEvent = isTest
                 ? StringFormat("Hue test: HTTP %d", code)
                 : StringFormat("Hue %s: %.0f b k %s (HTTP %d)",
                                isBuy ? "BUY" : "SELL", dist / _Point,
                                DoubleToString(level, _Digits), code);
   Print("SVED: ", g_lastEvent, "  tělo: ", body);

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

   PrintFormat("SVED: Hue - ruční test, cíl %s", InpHueUrl);
   HueSend(true, level, 0.0, true);
  }

//+------------------------------------------------------------------+
//| Vykresli tlacitko pro rucni test upozorneni Hue.                 |
//|  y - svisle odsazeni v pixelech (pod poslednim radkem panelu)    |
//+------------------------------------------------------------------+
void DrawHueTestButton(const int y)
  {
   const string name = SVED_PREFIX + "BTN_HUETEST";

   if(!InpHueTestButton)
     {
      ObjectDelete(0, name);
      return;
     }

   // Vyska tlacitka se ridi pismem panelu, aby sedelo k jeho radkum
   const int h = MathMax(InpPanelFontSize * 2 + 4, 20);
   SvedButton(name, InpPanelX, y, 150, h, "TEST Hue",
              InpColorPanel, C'48,48,48', InpPanelFontSize, "Consolas",
              "Odešle testovací upozornění na " + InpHueUrl);
  }

//+------------------------------------------------------------------+
//| Vykresleni urovni pruzazu (HIGH / LOW svicky TF pruzazu)         |
//+------------------------------------------------------------------+
void DrawBreakoutLevels()
  {
   SvedDeleteObjects("BRK_");
   if(!InpShowBreakLevels || g_breakHigh <= 0.0)
      return;

   const datetime tTo = TimeCurrent() + (datetime)(PeriodSeconds(InpBreakoutTF) * 2);

   // Cara zacina u svicky, ze ktere uroven pochazi - u swingoveho
   // rezimu je tak na prvni pohled videt, ktery swing se prorazi
   SvedTrendLine(SVED_PREFIX + "BRK_H", g_breakHighTime, g_breakHigh, tTo, g_breakHigh,
                 InpColorBreak, 1, STYLE_DASH, false,
                 "Úroveň průrazu HIGH " + DoubleToString(g_breakHigh, _Digits));
   SvedTrendLine(SVED_PREFIX + "BRK_L", g_breakLowTime, g_breakLow, tTo, g_breakLow,
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
      SvedDeleteObjects("ENT_");
      return;
     }

   const datetime tFrom = iTime(_Symbol, InpBreakoutTF, 0);
   const datetime tTo   = TimeCurrent() + (datetime)(PeriodSeconds(InpBreakoutTF) * 3);

   SvedDrawEntryLevels("BUY",  g_planBuy,  tFrom, tTo,
                       InpColorEntry, InpColorSL, InpColorTP, _Digits);
   SvedDrawEntryLevels("SELL", g_planSell, tFrom, tTo,
                       InpColorEntry, InpColorSL, InpColorTP, _Digits);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Textovy popis stavu jednoho smeru pro panel.                     |
//| Rozlisuje, jestli uz bylo obchodovano, jestli je navrh vubec     |
//| proveditelny a jestli je smer nabity (cena na spravne strane).   |
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
//| Textovy popis navrhu vstupu pro panel                            |
//+------------------------------------------------------------------+
string PlanToText(SEntryPlan &pl)
  {
   const string dir = pl.isBuy ? "BUY " : "SELL";

   if(!pl.valid)
      return(StringFormat("%s  spouštěč %s  -  %s", dir,
                          DoubleToString(pl.trigger, _Digits),
                          pl.reason == "" ? "čeká na kanál" : pl.reason));

   return(StringFormat("%s  vstup %s  SL %s  PT %s  délka %.0f b  %.2f lot  kanál %d%s",
                       dir,
                       DoubleToString(pl.entry, _Digits),
                       DoubleToString(pl.sl, _Digits),
                       DoubleToString(pl.tp, _Digits),
                       pl.distance / _Point,
                       pl.lots,
                       pl.channelIdx + 1,
                       pl.limitedByEdge ? "  [zkráceno k hraně]" : ""));
  }

//+------------------------------------------------------------------+
//| Vykresleni informacniho panelu                                   |
//+------------------------------------------------------------------+
void UpdatePanel()
  {
   if(!InpShowPanel)
     {
      SvedDeleteObjects("PNL_");
      DrawHueTestButton(InpPanelY);
      return;
     }

   string lines[24];
   int    n = 0;

   lines[n++] = "SVED CHANNEL BREAKOUT  |  " + _Symbol + "  |  účet " +
                IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   lines[n++] = StringFormat("kanály %s   průraz %s   vstup %s   |  max %d b, SL:PT 1:1",
                             EnumToString(InpChannelTF), EnumToString(InpBreakoutTF),
                             EnumToString(InpEntryTF), InpMaxEntryPoints);

   //--- Prehled detekovanych kanalu
   if(g_channelCount <= 0)
      lines[n++] = "kanály: žádný hlavní kanál nesplnil filtry";
   else
     {
      lines[n++] = StringFormat("kanály: %d", g_channelCount);
      const datetime tNow = TimeCurrent();
      for(int i = 0; i < g_channelCount && n < 12; i++)
         lines[n++] = StringFormat("  kanál %d (měřítko %d, %s)  šířka %.0f b  dotyků %d  body po C: %d  uvnitř %.0f%%  hrany %s / %s",
                                   i + 1,
                                   g_channels[i].scaleIdx,
                                   g_channels[i].baseIsLow ? "LOW základna" : "HIGH základna",
                                   g_channels[i].width / _Point,
                                   g_channels[i].touches,
                                   g_channels[i].extraCount,
                                   g_channels[i].containment * 100.0,
                                   DoubleToString(g_channels[i].LowerAt(tNow), _Digits),
                                   DoubleToString(g_channels[i].UpperAt(tNow), _Digits));
     }

   //--- Urovne pruzazu a navrhy vstupu
   lines[n++] = StringFormat("průraz %s: H %s (%s)   L %s (%s)",
                             InpUseSwingLevels ? "swing " + EnumToString(InpBreakoutTF)
                                               : "poslední " + EnumToString(InpBreakoutTF),
                             DoubleToString(g_breakHigh, _Digits),
                             TimeToString(g_breakHighTime, TIME_DATE | TIME_MINUTES),
                             DoubleToString(g_breakLow, _Digits),
                             TimeToString(g_breakLowTime, TIME_DATE | TIME_MINUTES));
   if(InpUseRelief)
      lines[n++] = StringFormat("reliéfní přímky %s: %d  (režim: %s)",
                                EnumToString(InpEntryTF), g_reliefCount,
                                InpReliefMode == SVED_RELIEF_SKIP ? "přeskočit vstup"
                                                                 : "zkrátit PT");

   //--- Stav upozorneni na zarovky Hue
   if(InpHueEnabled)
      lines[n++] = StringFormat("Hue: upozornění %d b od úrovně vstupu  (BUY %s / SELL %s)",
                                InpHueNearPoints,
                                g_hueBuyLevel  > 0.0 ? "posláno" : "-",
                                g_hueSellLevel > 0.0 ? "posláno" : "-");

   lines[n++] = "stav: " + StateText(true, g_planBuy) + " / " + StateText(false, g_planSell);
   lines[n++] = PlanToText(g_planBuy);
   lines[n++] = PlanToText(g_planSell);

   //--- Stav pozice
   lines[n++] = PositionText();

   if(g_lastEvent != "" && n < 24)
      lines[n++] = "poslední: " + g_lastEvent;

   //--- Vykresleni radku panelu a uklid prebytecnych
   // Kdyz je zapnuty one-click SELL/BUY panel MT5, posune se panel pod nej,
   // aby se s nim nepřekrýval
   int panelY = InpPanelY;
   if(ChartGetInteger(0, CHART_SHOW_ONE_CLICK))
      panelY += InpPanelOneClickShift;

   // Vyska radku je samostatny parametr - odvozeni od velikosti pisma
   // nestaci na obrazovkach s vyssim DPI, kde se radky slepuji
   const int lineH = (InpPanelLineHeight > 0) ? InpPanelLineHeight
                                              : (InpPanelFontSize + 5);

   for(int i = 0; i < n; i++)
      SvedLabel(SVED_PREFIX + "PNL_" + IntegerToString(i),
                InpPanelX, panelY + i * lineH,
                lines[i], InpColorPanel, InpPanelFontSize, "Consolas");

   for(int i = n; i < 24; i++)
      ObjectDelete(0, SVED_PREFIX + "PNL_" + IntegerToString(i));

   //--- Tlacitko testu se kresli pod posledni radek panelu
   DrawHueTestButton(panelY + n * lineH + 6);

   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Textovy popis aktualni pozice strategie pro panel                |
//+------------------------------------------------------------------+
string PositionText()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != InpMagic)
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
