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
   SVED_ENTRY_PENDING  = 1  // Pending STOP prikazy na urovnich TF prurazu (H1)
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
//| Druh prekazky, ktera zkratila PT navrhu.                         |
//| Bez tohoto rozliseni by se typ prekazky rekonstruoval porovnanim |
//| doublu (edgePrice == reliefPrice) a panel by hlasil "zkraceno    |
//| hranou" i tam, kde PT zkratila reliefni primka.                  |
//+------------------------------------------------------------------+
enum ENUM_SVED_BARRIER
  {
   SVED_BARRIER_NONE   = 0, // PT je v plne delce
   SVED_BARRIER_EDGE   = 1, // PT zkracen hranou kanalu
   SVED_BARRIER_RELIEF = 2  // PT zkracen reliefni primkou
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

//--- Minimalni odstup dvou zapocitanych dotyku teze hrany / primky
//--- (v barech). Jedna delsi dotykova epizoda se tak pocita jako
//--- jeden dotyk a nenafoukne skore.
#define SVED_TOUCH_GAP 3

//--- O kolik baru zpet lezi druhy porovnavaci okamzik pri deduplikaci.
//--- Musi byt dost daleko, aby se projevil rozdilny sklon dvou utvaru,
//--- ktere se prave ted krizi.
#define SVED_DEDUP_BACK_BARS 50

//+------------------------------------------------------------------+
//| Seradi pole struktur sestupne podle pole .score.                 |
//| Radi se pole indexu, ne samotne struktury - prohozeni indexu je   |
//| par bajtu, kdezto SChannel ma pres 300 B a prime razeni prehazelo |
//| pri stovkach kandidatu desitky MB. Razeni je stabilni, takze pri  |
//| shode skore rozhoduje poradi vzniku kandidata.                    |
//|  arr - razene pole (in/out); typ musi mit clen score              |
//+------------------------------------------------------------------+
template<typename T>
void SvedSortByScoreDesc(T &arr[])
  {
   const int n = ArraySize(arr);
   if(n < 2)
      return;

   int    idx[];
   double sc[];
   ArrayResize(idx, n);
   ArrayResize(sc,  n);
   for(int i = 0; i < n; i++)
     {
      idx[i] = i;
      sc[i]  = arr[i].score;
     }

   // Insertion sort - pole byva male a castecne serazene
   for(int i = 1; i < n; i++)
     {
      const int    key   = idx[i];
      const double value = sc[key];
      int j = i - 1;
      while(j >= 0 && sc[idx[j]] < value)
        {
         idx[j + 1] = idx[j];
         j--;
        }
      idx[j + 1] = key;
     }

   T sorted[];
   ArrayResize(sorted, n);
   for(int i = 0; i < n; i++)
      sorted[i] = arr[idx[i]];
   for(int i = 0; i < n; i++)
      arr[i] = sorted[i];
  }

//+------------------------------------------------------------------+
//| ABCD kanal.                                                      |
//| Kanal vznika ze tri po sobe jdoucich swingu A-B-C:               |
//|   - baseIsLow = true : A a C jsou dna  -> zakladni je LOW usecka,|
//|                        horni hrana je rovnobezka vedena bodem B  |
//|   - baseIsLow = false: A a C jsou vrcholy -> zakladni je HIGH    |
//|                        usecka, spodni hrana je rovnobezka bodem B|
//| Body D, E, F ... jsou dalsi potvrzene dotyky hran za bodem C -   |
//| zapisuji se az ve chvili, kdy k dotyku skutecne dojde.           |
//|                                                                  |
//| Vsechny testy vzdalenosti od hran (dotyk, proriznuti, "uvnitr")  |
//| vedou pres metody nize, aby mely jednu definici - drive to byly  |
//| ctyri ad-hoc nerovnosti roztroušene po modulech, ktere si        |
//| navzajem odporovaly (bod D zapsany bez horni meze vs. dotyk s ni)|
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
   int               touches;      // pocet potvrzenych dotyku hran (bez opor A B C)
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
   //--- Dotyk horni hrany: high dosahl do tolerancniho pasma u hrany.
   //--- Horni mez je zamerne volnejsi (2x tol) - knot smi hranu lehce
   //--- presahnout, porad je to dotyk, ne proriznuti.
   bool              TouchesUpper(const datetime t, const double high, const double tol)
     {
      const double up = UpperAt(t);
      return (high >= up - tol && high <= up + tol * 2.0);
     }
   //--- Dotyk spodni hrany (zrcadlove k TouchesUpper)
   bool              TouchesLower(const datetime t, const double low, const double tol)
     {
      const double lo = LowerAt(t);
      return (low <= lo + tol && low >= lo - tol * 2.0);
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
   int               minTouches;       // minimalni pocet dotyku hran (bez opor)
   double            touchTolFrac;     // tolerance dotyku jako zlomek sirky
   double            insideTolFrac;    // tolerance testu "uvnitr" (zlomek sirky)
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
   double            trigger;      // uroven prurazu (high/low svicky TF prurazu)
   double            entry;        // cena vstupu vcetne bufferu
   double            sl;           // stop loss
   double            tp;           // take profit
   double            distance;     // delka vstupu v cene (SL i PT maji tuto delku)
   double            lots;         // navrzeny objem
   ENUM_SVED_BARRIER barrier;      // co PT zkratilo (hrana kanalu / reliefni primka)
   double            barrierPrice; // cena teto prekazky
   int               channelIdx;   // index kanalu, uvnitr ktereho vstupujeme
   string            reason;       // duvod pripadneho zamitnuti
  };

#endif // __SVED_TYPES_MQH__
//+------------------------------------------------------------------+
