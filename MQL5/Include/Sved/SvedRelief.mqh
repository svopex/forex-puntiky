//+------------------------------------------------------------------+
//|                                                  SvedRelief.mqh  |
//|      Reliefni primky na vstupnim timeframu (M1)                  |
//|                                                                  |
//|  Reliefni primka je trendlinie vedena dvema hlavnimi swingy      |
//|  stejneho typu - dvema vrcholy (odpor) nebo dvema dny (podpora). |
//|  Musi cenu obalovat, tedy zadna svicka ji nesmi prorazit, jinak  |
//|  uz prestala platit. Takova primka stoji prurazu v ceste a       |
//|  strategie ji hlida pri planovani vstupu (viz docs/relief_1.png).|
//+------------------------------------------------------------------+
#property copyright "Sved"

#ifndef __SVED_RELIEF_MQH__
#define __SVED_RELIEF_MQH__

#include <Sved\SvedTypes.mqh>
#include <Sved\SvedSwings.mqh>

//--- Minimalni odstup dvou zapocitanych dotyku primky (v barech)
#define SVED_RELIEF_TOUCH_GAP 3

//+------------------------------------------------------------------+
//| Reliefni primka                                                  |
//+------------------------------------------------------------------+
struct SReliefLine
  {
   bool              isHigh;    // true = odpor (nad cenou), false = podpora
   datetime          t1, t2;    // opory primky
   double            p1, p2;
   int               i1, i2;    // indexy baru v analyzovanem poli
   double            slope;     // zmena ceny za 1 sekundu
   int               touches;   // pocet potvrzenych dotyku
   int               spanBars;  // delka primky v barech
   int               ageBars;   // stari druhe opory v barech
   double            meanGap;   // prumerny odstup od ceny mezi oporami
   double            maxOver;   // nejvetsi presah knotu pres primku
   double            score;     // pro vyber nejvyznamnejsich primek

   //--- Hodnota primky v case t
   double            ValueAt(const datetime t)
     {
      return p1 + slope * (double)(t - t1);
     }
  };

//+------------------------------------------------------------------+
//| Statistika hledani reliefnich primek - kolik kandidatu padlo     |
//| na kterem filtru. Bez ni se prahy ladi naslepo.                  |
//+------------------------------------------------------------------+
struct SReliefStats
  {
   int               pairs;      // vygenerovanych dvojic swingu
   int               span;       // prilis kratka primka
   int               age;        // prilis stara druha opora
   int               drift;      // primka ujela od opory
   int               pierced;    // primka prorazena cenou
   int               midTouch;   // chybi dotyk uprostred
   int               touches;    // malo dotyku celkem
   int               passed;     // proslo vsemi filtry
   int               selected;   // vybrano

   void              Reset()
     {
      pairs = 0; span = 0; age = 0; drift = 0; pierced = 0;
      midTouch = 0; touches = 0; passed = 0; selected = 0;
     }
  };

//+------------------------------------------------------------------+
//| Parametry hledani reliefnich primek                              |
//+------------------------------------------------------------------+
struct SReliefParams
  {
   int               swingDepth;   // sirka okna pro hlavni swingy
   int               scales;       // pocet meritek detekce swingu
   int               maxSwingGap;  // max. odstup opor (v poctu swingu)
   int               minSpanBars;  // minimalni delka primky v barech
   int               minTouches;   // minimalni pocet dotyku
   double            pierceTol;    // povolene proriznuti primky TELEM svicky (v cene)
   double            wickTol;      // povoleny presah primky KNOTEM (v cene)
   double            touchTol;     // tolerance dotyku (v cene)
   double            dedupTol;     // prah shody dvou primek (v cene)
   double            maxAgeFactor; // jak dlouho primka plati za druhou oporou
   double            maxDrift;     // jak daleko smi primka ujet od druhe opory
   bool              needMidTouch; // vyzadovat dotyk i uprostred primky
   double            midTol;       // tolerance stredniho dotyku (v cene)
   double            midFrom;      // zacatek stredniho useku (0..1)
   double            midTo;        // konec stredniho useku (0..1)
   int               maxLines;     // kolik primek ponechat
  };

//+------------------------------------------------------------------+
//| Test, zda primka cenu obaluje a nebyla prorazena.                |
//| Rozlisuji se tela a knoty - stejne, jako kdyz se trendline       |
//| kresli rucne:                                                    |
//|   - TELO svicky (open/close) nesmi primku prekrocit vubec        |
//|     (tolerance bodyTol); telo za primkou = prorazeni,            |
//|   - KNOT smi primku presahnout az o wickTol, ale JEN MEZI        |
//|     oporami - prostrel knotem uvnitr utvaru trendline nerusi.    |
//|   - ZA druhou oporou je primka tvrda hranice: i knot pres ni     |
//|     znamena novy extrem, primka prestava platit a kotva patri    |
//|     na novou svicku (viz docs/iScreen ... 091142.png).           |
//| Do maxOver se uklada nejvetsi zaznamenany presah knotu; nulovy   |
//| presah znamena skutecnou tecnu vedenou pres spicky svicek.       |
//+------------------------------------------------------------------+
bool SvedReliefIsClean(const MqlRates &rates[], SReliefLine &ln,
                       const double bodyTol, const double wickTol)
  {
   const int n = ArraySize(rates);
   ln.maxOver = 0.0;

   for(int i = MathMax(ln.i1, 0); i < n; i++)
     {
      const datetime t = rates[i].time;
      const double   v = ln.ValueAt(t);

      // Mezi oporami je knotum povolen prostrel, za druhou oporou ne
      const double tolWick = (i <= ln.i2) ? wickTol : bodyTol;

      if(ln.isHigh)
        {
         const double bodyTop = MathMax(rates[i].open, rates[i].close);
         if(bodyTop > v + bodyTol)
            return(false);
         const double over = rates[i].high - v;
         if(over > tolWick)
            return(false);
         if(over > ln.maxOver)
            ln.maxOver = over;
        }
      else
        {
         const double bodyBot = MathMin(rates[i].open, rates[i].close);
         if(bodyBot < v - bodyTol)
            return(false);
         const double over = v - rates[i].low;
         if(over > tolWick)
            return(false);
         if(over > ln.maxOver)
            ln.maxOver = over;
        }
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Spocita potvrzene dotyky primky na useku od prvni opory dal.     |
//| Dotyky blize nez SVED_RELIEF_TOUCH_GAP baru se pocitaji jako     |
//| jeden, aby jedna delsi epizoda nenafoukla skore.                 |
//+------------------------------------------------------------------+
int SvedReliefCountTouches(const MqlRates &rates[], SReliefLine &ln, const double tol)
  {
   const int n = ArraySize(rates);
   int touches = 0;
   int last    = -1000;

   for(int i = MathMax(ln.i1, 0); i < n; i++)
     {
      const datetime t = rates[i].time;
      const double   v = ln.ValueAt(t);
      const double   d = ln.isHigh ? (v - rates[i].high) : (rates[i].low - v);

      // Zaporna vzdalenost = presah, ten uz osetril SvedReliefIsClean
      if(d >= -tol && d <= tol)
        {
         if(i - last >= SVED_RELIEF_TOUCH_GAP)
           {
            touches++;
            last = i;
           }
        }
     }
   return(touches);
  }

//+------------------------------------------------------------------+
//| Prumerny odstup primky od cenove akce mezi oporami.              |
//| Mala hodnota znamena, ze primka na cene "sedi"; velka, ze se     |
//| klene pres udoli/vrchol. Neslouzi jako filtr - obe varianty jsou |
//| platne reliefni primky - ale rozhoduje mezi variantami se        |
//| stejnou prvni oporou (viz vyber nize).                           |
//+------------------------------------------------------------------+
double SvedReliefMeanGap(const MqlRates &rates[], SReliefLine &ln)
  {
   const int from = MathMax(ln.i1, 0);
   const int to   = MathMin(ln.i2, ArraySize(rates) - 1);
   if(to <= from)
      return(0.0);

   double sum = 0.0;
   for(int i = from; i <= to; i++)
     {
      const double v = ln.ValueAt(rates[i].time);
      const double d = ln.isHigh ? (v - rates[i].high) : (rates[i].low - v);
      sum += MathMax(d, 0.0);
     }
   return(sum / (double)(to - from + 1));
  }

//+------------------------------------------------------------------+
//| Test, zda se primka dotyka ceny i ve sve stredni casti.          |
//| Kazda primka se z definice dotyka svych dvou opor, takze same    |
//| krajni dotyky nic nedokazuji - primka muze mezi nimi "viset"     |
//| daleko nad (resp. pod) cenovou akci a niceho se nedotykat.       |
//| Vyzaduje se proto aspon jeden dotyk v prostredni casti useku.    |
//+------------------------------------------------------------------+
bool SvedReliefHasMidTouch(const MqlRates &rates[], SReliefLine &ln, const double tol,
                           const double midFrom, const double midTo)
  {
   const int span = ln.i2 - ln.i1;
   if(span <= 2)
      return(true);

   const int from = ln.i1 + (int)(midFrom * (double)span);
   const int to   = ln.i1 + (int)(midTo   * (double)span);

   for(int i = from; i <= to && i < ArraySize(rates); i++)
     {
      const datetime t = rates[i].time;
      const double   v = ln.ValueAt(t);
      const double   d = ln.isHigh ? (v - rates[i].high) : (rates[i].low - v);

      if(d >= -tol && d <= tol)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Sestavi reliefni primky z hlavnich swingu vstupniho timeframu.   |
//| Kazda dvojice swingu stejneho typu dava kandidata; projdou jen   |
//| primky, ktere cenu obaluji a maji dost dotyku. Vysledek je       |
//| serazen podle vyznamnosti a zbaven duplicit.                     |
//| Vraci pocet primek ulozenych do out[].                           |
//+------------------------------------------------------------------+
int SvedBuildReliefLines(const MqlRates &rates[], const SReliefParams &p, SReliefLine &out[],
                         SReliefStats &st)
  {
   st.Reset();
   ArrayResize(out, 0);
   const int n = ArraySize(rates);
   if(n < 20)
      return(0);

   SReliefLine cand[];
   ArrayResize(cand, 0);
   int nc = 0;

   const int maxGap = MathMax(p.maxSwingGap, 2);

   //--- Swingy se hledaji ve vice meritkach - jemne okno da cerstve
   //--- lokalni primky, hrube okno vidi jen hlavni vrcholy/dna, takze
   //--- pres omezeny odstup opor dosahne i na vzdalene swingy (vejir
   //--- trendlinii z hlavnich vrcholu; viz docs/uprava_2.png).
   //--- Stejna dvojice oporovych baru z ruznych meritek se slouci
   //--- pres vyber "nejlepsi primka na oporu" nize.
   for(int sc = 0; sc < MathMax(p.scales, 1); sc++)
     {
   const int depth = p.swingDepth * (1 << sc);
   if(depth * 2 + 3 >= n)
      break;

   SSwing sw[];
   const int ns = SvedDetectSwings(rates, depth, sw);
   if(ns < 2)
      continue;

   //--- Kandidati ze vsech dvojic swingu stejneho typu
   for(int i = 0; i < ns; i++)
     {
      for(int gap = 2; gap <= maxGap && i + gap < ns; gap += 2)
        {
         const int j = i + gap;

         st.pairs++;

         SReliefLine ln;
         ln.isHigh = sw[i].isHigh;
         ln.t1 = sw[i].time; ln.p1 = sw[i].price; ln.i1 = sw[i].index;
         ln.t2 = sw[j].time; ln.p2 = sw[j].price; ln.i2 = sw[j].index;
         ln.touches = 0; ln.score = 0.0; ln.ageBars = 0;
         ln.spanBars = ln.i2 - ln.i1;

         if(ln.spanBars < p.minSpanBars)
           {
            st.span++;
            continue;
           }

         // Primka plati jen omezenou dobu za svou druhou oporou.
         // Bez toho se kratka strma cara prodlouzi do vzduchoprazdna
         // stovky bodu od ceny, kde uz se niceho nedotyka.
         ln.ageBars = (n - 1) - ln.i2;
         if(p.maxAgeFactor > 0.0 &&
            (double)ln.ageBars > p.maxAgeFactor * (double)ln.spanBars)
           {
            st.age++;
            continue;
           }

         const double dt = (double)(ln.t2 - ln.t1);
         if(dt <= 0.0)
            continue;
         ln.slope = (ln.p2 - ln.p1) / dt;

         if(!SvedReliefIsClean(rates, ln, p.pierceTol, p.wickTol))
           {
            st.pierced++;
            continue;
           }

         // Jak daleko primka ujela od sve druhe opory. Strma cara se
         // za par hodin vzdali desitky dolaru od ceny, kde uz se
         // niceho nedotyka - takova primka neni reliefem, ale artefaktem.
         if(p.maxDrift > 0.0)
           {
            const double drift = MathAbs(ln.ValueAt(rates[n - 1].time) - ln.p2);
            if(drift > p.maxDrift)
              {
               st.drift++;
               continue;
              }
           }

         // Primka musi sedet na cenove akci i mimo sve opory
         if(p.needMidTouch &&
            !SvedReliefHasMidTouch(rates, ln, p.midTol, p.midFrom, p.midTo))
           {
            st.midTouch++;
            continue;
           }

         ln.touches = SvedReliefCountTouches(rates, ln, p.touchTol);
         if(ln.touches < p.minTouches)
           {
            st.touches++;
            continue;
           }

         st.passed++;

         ln.meanGap = SvedReliefMeanGap(rates, ln);

         // Vyznamnejsi je primka s vice dotyky a delsim zaberem;
         // cim starsi je druha opora, tim mene je primka aktualni
         ln.score = (double)ln.touches * 2.0
                    + (double)ln.spanBars / 100.0
                    - (double)ln.ageBars / 200.0;

         // Z primek se stejnou prvni oporou a smerem se drzi jen ta
         // nejlepsi: vic dotyku vitezi, pri shode rozhoduje mensi
         // prumerny odstup od ceny (primka ma na cene "sedet", ne
         // pod ni viset - viz docs/2.png), pak delsi zaber.
         int same = -1;
         for(int c = 0; c < nc; c++)
            if(cand[c].i1 == ln.i1 && cand[c].isHigh == ln.isHigh)
              {
               same = c;
               break;
              }

         if(same >= 0)
           {
            // Skutecna tecna (mensi presah knotu) ma prednost - primka
            // ma prochazet spickami svicek, ne je rezat. Teprve pri
            // srovnatelnem presahu rozhoduji dotyky, prilnuti a zaber.
            bool better = false;
            if(MathAbs(ln.maxOver - cand[same].maxOver) > p.pierceTol)
               better = (ln.maxOver < cand[same].maxOver);
            else
               if(ln.touches != cand[same].touches)
                  better = (ln.touches > cand[same].touches);
               else
                  if(MathAbs(ln.meanGap - cand[same].meanGap) > 0.0001)
                     better = (ln.meanGap < cand[same].meanGap);
                  else
                     better = (ln.spanBars > cand[same].spanBars);
            if(better)
               cand[same] = ln;
            continue;
           }

         ArrayResize(cand, nc + 1);
         cand[nc++] = ln;
        }
     }
     }   // konec smycky pres meritka

   if(nc == 0)
      return(0);

   //--- Serazeni podle vyznamnosti
   for(int a = 0; a < nc - 1; a++)
      for(int b = a + 1; b < nc; b++)
         if(cand[b].score > cand[a].score)
           {
            SReliefLine tmp = cand[a];
            cand[a] = cand[b];
            cand[b] = tmp;
           }

   //--- Vyber s odstranenim prakticky totoznych primek.
   //--- Odpory a podpory se stridaji, aby jeden typ neobsadil vsechny
   //--- sloty - jinak by silna serie podpor zastinila platny odpor.
   const datetime tLast = rates[n - 1].time;
   int taken = 0;
   ArrayResize(out, p.maxLines);

   bool wantHigh = true;   // zacina se odporem
   for(int round = 0; round < 2 * p.maxLines && taken < p.maxLines; round++)
     {
      int pick = -1;
      for(int i = 0; i < nc; i++)
        {
         if(cand[i].isHigh != wantHigh)
            continue;

         bool used = false;
         for(int j = 0; j < taken; j++)
            if(out[j].i1 == cand[i].i1 && out[j].i2 == cand[i].i2)
              {
               used = true;
               break;
              }
         if(used)
            continue;

         bool dup = false;
         for(int j = 0; j < taken; j++)
           {
            if(out[j].isHigh != cand[i].isHigh)
               continue;
            if(MathAbs(out[j].ValueAt(tLast) - cand[i].ValueAt(tLast)) < p.dedupTol)
              {
               dup = true;
               break;
              }
           }
         if(dup)
            continue;

         pick = i;     // kandidati jsou serazeni, prvni vyhovujici je nejlepsi
         break;
        }

      if(pick >= 0)
         out[taken++] = cand[pick];

      wantHigh = !wantHigh;   // pristi kolo opacny typ
     }

   ArrayResize(out, taken);
   st.selected = taken;
   return(taken);
  }

//+------------------------------------------------------------------+
//| Najde nejblizsi reliefni primku ve smeru obchodu.                |
//| Pro nakup se hledaji primky nad cenou, pro prodej pod ni -       |
//| tedy ty, ktere by prurazu stály v ceste.                         |
//|  linePrice - out: cena nalezene primky v case t                  |
//| Vraci vzdalenost v cene, nebo -1 pokud zadna primka nevadi.      |
//+------------------------------------------------------------------+
double SvedNearestRelief(SReliefLine &lines[], const datetime t, const double price,
                         const bool isBuy, double &linePrice)
  {
   const int cnt = ArraySize(lines);
   double best = -1.0;
   linePrice = 0.0;

   for(int i = 0; i < cnt; i++)
     {
      const double v = lines[i].ValueAt(t);

      if(isBuy)
        {
         if(v <= price)
            continue;              // primka je pod vstupem, necha nas projit
         const double d = v - price;
         if(best < 0.0 || d < best)
           {
            best = d;
            linePrice = v;
           }
        }
      else
        {
         if(v >= price)
            continue;
         const double d = price - v;
         if(best < 0.0 || d < best)
           {
            best = d;
            linePrice = v;
           }
        }
     }

   return(best);
  }

#endif // __SVED_RELIEF_MQH__
//+------------------------------------------------------------------+
