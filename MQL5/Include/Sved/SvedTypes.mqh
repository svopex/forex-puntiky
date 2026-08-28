//+------------------------------------------------------------------+
//|                                                   SvedTypes.mqh  |
//|          Spolecne datove struktury a vyctove typy strategie      |
//|          "Sved Channel Breakout" (ABCD kanaly + prurazy H1)      |
//+------------------------------------------------------------------+
#property copyright "Sved"
#property link      ""

#ifndef __SVED_TYPES_MQH__
#define __SVED_TYPES_MQH__

//--- Rezim vstupu do obchodu
enum ENUM_SVED_ENTRY
  {
   SVED_ENTRY_M1_CLOSE = 0, // Potvrzeni uzavrenim svicky vstupniho TF (M1)
   SVED_ENTRY_PENDING  = 1  // Pending STOP prikazy na urovnich TF pruzazu (H1)
  };

//--- Co delat, kdyz prurazu stoji v ceste reliefni primka
enum ENUM_SVED_RELIEF
  {
   SVED_RELIEF_SKIP    = 0, // Vstup preskocit
   SVED_RELIEF_SHORTEN = 1  // Zkratit PT k primce (SL stejne, RRR 1:1)
  };

//--- Rezim vypoctu objemu pozice
enum ENUM_SVED_LOT
  {
   SVED_LOT_FIXED = 0,      // Pevny lot
   SVED_LOT_RISK  = 1       // Lot dopocteny z % rizika uctu
  };

//+------------------------------------------------------------------+
//| Swingovy bod (lokalni extrem) detekovany na pracovnim TF.        |
//|  time  - cas otevreni svicky s extremem                          |
//|  price - hodnota extremu (high pro vrchol, low pro dno)          |
//|  index - poradi baru v analyzovanem poli (0 = nejstarsi)         |
//|  isHigh- true = swingovy vrchol, false = swingove dno            |
//+------------------------------------------------------------------+
struct SSwing
  {
   datetime          time;
   double            price;
   int               index;
   bool              isHigh;
  };

//--- Maximalni pocet potvrzenych dotyku za bodem C (D, E, F, ...)
#define SVED_MAX_TOUCH_POINTS 8

//+------------------------------------------------------------------+
//| ABCD kanal.                                                      |
//| Kanal vznika ze tri po sobe jdoucich swingu A-B-C:               |
//|   - baseIsLow = true : A a C jsou dna  -> zakladni je LOW usecka,|
//|                        horni hrana je rovnobezka vedena bodem B  |
//|   - baseIsLow = false: A a C jsou vrcholy -> zakladni je HIGH    |
//|                        usecka, spodni hrana je rovnobezka bodem B|
//| Body D, E, F ... jsou dalsi potvrzene dotyky hran za bodem C -   |
//| zapisuji se az ve chvili, kdy k dotyku skutecne dojde.           |
//+------------------------------------------------------------------+
struct SChannel
  {
   bool              valid;        // kanal prosel filtry a je pouzitelny
   bool              baseIsLow;    // orientace zakladni usecky

   //--- opory kanalu
   datetime          tA, tB, tC;
   double            pA, pB, pC;
   int               iA, iB, iC;   // indexy baru v analyzovanem poli

   //--- dalsi potvrzene dotyky hran za bodem C (D, E, F, ...)
   int               extraCount;
   datetime          tExtra[SVED_MAX_TOUCH_POINTS];
   double            pExtra[SVED_MAX_TOUCH_POINTS];
   bool              extraUpper[SVED_MAX_TOUCH_POINTS];   // dotyk horni hrany?

   //--- geometrie
   double            slope;        // zmena ceny za 1 sekundu na zakladni usecce
   double            width;        // vertikalni sirka kanalu v cene

   //--- hodnoceni kvality
   int               touches;      // pocet potvrzenych dotyku obou hran
   double            containment;  // podil svicek uzavrenych uvnitr kanalu
   int               spanBars;     // delka kanalu v barech (A -> C)
   int               ageBars;      // stari bodu C v barech
   int               scaleIdx;     // meritko detekce (0 = nejjemnejsi swingy)
   double            score;        // vysledne skore pro vyber hlavnich kanalu

   //--- Hodnota zakladni (base) usecky v case t
   double            BaseAt(const datetime t)
     {
      return pA + slope * (double)(t - tA);
     }
   //--- Hodnota spodni hrany kanalu v case t
   double            LowerAt(const datetime t)
     {
      return baseIsLow ? BaseAt(t) : BaseAt(t) - width;
     }
   //--- Hodnota horni hrany kanalu v case t
   double            UpperAt(const datetime t)
     {
      return baseIsLow ? BaseAt(t) + width : BaseAt(t);
     }
   //--- Test, zda cena lezi uvnitr kanalu v case t (s toleranci v cene)
   bool              Contains(const datetime t, const double price, const double tol)
     {
      return (price >= LowerAt(t) - tol && price <= UpperAt(t) + tol);
     }
  };

//+------------------------------------------------------------------+
//| Parametry detekce a filtrovani kanalu (predavane do modulu)      |
//+------------------------------------------------------------------+
struct SChannelParams
  {
   int               minSpanBars;      // minimalni delka A->C v barech
   double            minWidthPrice;    // minimalni sirka kanalu v cene
   double            minWidthATR;      // minimalni sirka jako nasobek ATR
   double            atr;              // aktualni ATR pracovniho TF
   int               minTouches;       // minimalni pocet dotyku hran
   double            touchTolFrac;     // tolerance dotyku jako zlomek sirky
   double            minContainment;   // minimalni podil svicek uvnitr
   int               maxChannels;      // kolik hlavnich kanalu ponechat
   int               maxAgeBars;       // maximalni stari bodu C
   int               maxSwingGap;      // max. odstup swingu A a C (v poctu swingu)
   int               scales;           // pocet meritek detekce
   double            pierceTolFrac;    // povolene proriznuti hran (zlomek sirky)
   double            invalidTolFrac;   // prah invalidace kanalu (zlomek sirky)
   int               backCheckBars;    // kolik baru pred bodem A jeste kontrolovat
   int               anchorWindow;     // okno, ve kterem musi byt A a C extremem
   double            dedupFrac;        // prah shody dvou kanalu (zlomek sirky)
   bool              requireInside;    // vyzadovat, aby cena byla uvnitr
  };

//+------------------------------------------------------------------+
//| Statistika detekce kanalu - kolik kandidatu padlo na kterem      |
//| filtru. Slouzi k ladeni prahu na realnych datech: z rozlozeni    |
//| zamitnuti je videt, ktery filtr je uzkym hrdlem.                 |
//+------------------------------------------------------------------+
struct SChannelStats
  {
   int               generated;    // vygenerovanych kombinaci A-C
   int               noB;          // chybi protilehly swing / lezi spatne
   int               span;         // prilis kratky kanal
   int               age;          // prilis stary bod C
   int               width;        // prilis uzky kanal
   int               anchors;      // opora neni vyraznym extremem
   int               pierced;      // hrana reze cenu / kanal prorazen
   int               touches;      // malo dotyku hran
   int               containment;  // malo svicek uvnitr
   int               outside;      // cena uz neni uvnitr kanalu
   int               passed;       // proslo vsemi filtry
   int               selected;     // vybrano jako hlavni kanal

   void              Reset()
     {
      generated = 0; noB = 0; span = 0; age = 0; width = 0; anchors = 0;
      pierced = 0; touches = 0; containment = 0; outside = 0;
      passed = 0; selected = 0;
     }
  };

//+------------------------------------------------------------------+
//| Vypocteny navrh vstupu pro jeden smer                            |
//+------------------------------------------------------------------+
struct SEntryPlan
  {
   bool              valid;        // navrh je obchodovatelny
   bool              isBuy;        // smer
   double            trigger;      // urovena pruraz (high/low H1 svicky)
   double            entry;        // cena vstupu vcetne bufferu
   double            sl;           // stop loss
   double            tp;           // take profit
   double            distance;     // delka vstupu v cene (SL = TP = distance)
   double            lots;         // navrzeny objem
   bool              limitedByEdge;// TP byl zkracen kvuli hrane kanalu
   double            edgePrice;    // cena nejblizsi hrany ve smeru obchodu
   bool              blockedByRelief; // vstup zablokovala reliefni primka
   double            reliefPrice;  // cena reliefni primky ve smeru obchodu
   int               channelIdx;   // index kanalu, uvnitr ktereho vstupujeme
   string            reason;       // duvod pripadneho zamitnuti
  };

#endif // __SVED_TYPES_MQH__
//+------------------------------------------------------------------+
