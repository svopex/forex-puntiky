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
   int               touches;   // pocet potvrzenych dotyku (bez opor primky)
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
   //--- Odstup svicky od uz spoctene hodnoty primky: kladny = svicka
   //--- primku nedosahla, zaporny = knot ji presahl. Jedna definice pro
   //--- vsechny testy - driv byla tataz nerovnost opsana ve ctyrech
   //--- funkcich a jejich kopie se rozesly.
   double            GapFrom(const double v, const double high, const double low)
     {
      return isHigh ? (v - high) : (low - v);
     }
   //--- Odstup svicky od primky v case t
   double            GapTo(const datetime t, const double high, const double low)
     {
      return GapFrom(ValueAt(t), high, low);
     }
   //--- Dotyk primky: svicka je v tolerancnim pasmu kolem ni
   bool              IsTouch(const double gap, const double tol)
     {
      return (gap >= -tol && gap <= tol);
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
   int               minTouches;   // minimalni pocet dotyku (bez opor primky)
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
//| Jediny pruchod svickami primky - kontrola prorazeni, dotyky,     |
//| prilnuti a dotyk uprostred najednou.                             |
//|                                                                  |
//| Rozlisuji se tela a knoty - stejne, jako kdyz se trendline       |
//| kresli rucne:                                                    |
//|   - TELO svicky (open/close) nesmi primku prekrocit vubec        |
//|     (tolerance pierceTol); telo za primkou = prorazeni,          |
//|   - KNOT smi primku presahnout az o wickTol, ale JEN MEZI        |
//|     oporami - prostrel knotem uvnitr utvaru trendline nerusi.    |
//|   - ZA druhou oporou je primka tvrda hranice: i knot pres ni     |
//|     znamena novy extrem, primka prestava platit a kotva patri    |
//|     na novou svicku (viz docs/iScreen ... 091142.png).           |
//|                                                                  |
//| Dotyky se pocitaji BEZ oporovych baru: kazda primka svymi        |
//| oporami prochazi z definice, takze by jinak mela dva dotyky      |
//| zadarmo a filtr minTouches by nic nefiltroval (libovolna cista   |
//| spojnice dvou swingu by pak v rezimu SKIP blokovala vstupy).     |
//| Dotyky blize nez SVED_TOUCH_GAP baru se pocitaji jako jeden,     |
//| aby jedna delsi epizoda nenafoukla skore.                        |
//|  rates    - svicky vstupniho TF (index 0 = nejstarsi)            |
//|  ln       - primka; zapisuji se do ni maxOver, touches, meanGap  |
//|  p        - parametry (tolerance a stredni usek)                 |
//|  midTouch - out: nasel se dotyk ve stredni casti primky?         |
//| Vraci false, kdyz je primka prorazena.                           |
//+------------------------------------------------------------------+
bool SvedReliefScan(const MqlRates &rates[], SReliefLine &ln, const SReliefParams &p,
                    bool &midTouch)
  {
   const int n     = ArraySize(rates);
   const int from  = MathMax(ln.i1, 0);
   const int toGap = MathMin(ln.i2, n - 1);

   ln.maxOver = 0.0;
   ln.touches = 0;
   ln.meanGap = 0.0;

   // Stredni usek primky - u velmi kratke primky nema smysl a bere se
   // jako splneny
   const int span    = ln.i2 - ln.i1;
   const int midFrom = ln.i1 + (int)(p.midFrom * (double)span);
   const int midTo   = ln.i1 + (int)(p.midTo   * (double)span);
   midTouch = (span <= 2);

   double gapSum    = 0.0;
   int    gapCount  = 0;
   int    lastTouch = -SVED_TOUCH_GAP;   // zadny dotyk zatim

   for(int i = from; i < n; i++)
     {
      // Hodnota primky se pocita jednou za bar - je to nejcastejsi
      // operace cele detekce
      const double v   = ln.ValueAt(rates[i].time);
      const double gap = ln.GapFrom(v, rates[i].high, rates[i].low);

      //--- Telo svicky nesmi primku prekrocit
      if(ln.isHigh)
        {
         if(MathMax(rates[i].open, rates[i].close) > v + p.pierceTol)
            return(false);
        }
      else
        {
         if(MathMin(rates[i].open, rates[i].close) < v - p.pierceTol)
            return(false);
        }

      //--- Knot smi presahnout jen mezi oporami, za druhou oporou ne
      const double over    = -gap;
      const double tolWick = (i <= ln.i2) ? p.wickTol : p.pierceTol;
      if(over > tolWick)
         return(false);
      if(over > ln.maxOver)
         ln.maxOver = over;

      //--- Prilnuti primky k cene se meri jen mezi oporami
      if(i <= toGap)
        {
         gapSum += MathMax(gap, 0.0);
         gapCount++;
        }

      //--- Dotyk ve stredni casti primky
      if(!midTouch && i >= midFrom && i <= midTo && ln.IsTouch(gap, p.midTol))
         midTouch = true;

      //--- Potvrzeny dotyk. Opory se nepocitaji (primka jimi prochazi
      //--- z definice), ale zaraz epizody na nich nastavujeme - bar tesne
      //--- vedle opory patri do teze dotykove epizody a nesmi ji zdvojit.
      const bool isAnchor = (i == ln.i1 || i == ln.i2);
      if(ln.IsTouch(gap, p.touchTol) && (isAnchor || i - lastTouch >= SVED_TOUCH_GAP))
        {
         if(!isAnchor)
            ln.touches++;
         lastTouch = i;
        }
     }

   ln.meanGap = (gapCount > 0) ? gapSum / (double)gapCount : 0.0;
   return(true);
  }

//+------------------------------------------------------------------+
//| Jsou dve primky prakticky totozne?                               |
//| Porovnava se ve DVOU casech - dve primky s ruznym sklonem se u   |
//| posledni svicky muzou zrovna krizit a pri porovnani jedinym      |
//| okamzikem by se chybne slily (stejnou past resi i dedup kanalu). |
//|  a, b   - porovnavane primky                                     |
//|  t1, t2 - dva ruzne casove okamziky porovnani                    |
//|  tol    - prah shody v cene                                      |
//+------------------------------------------------------------------+
bool SvedReliefSimilar(SReliefLine &a, SReliefLine &b, const datetime t1, const datetime t2,
                       const double tol)
  {
   if(a.isHigh != b.isHigh)
      return(false);
   if(MathAbs(a.ValueAt(t1) - b.ValueAt(t1)) >= tol)
      return(false);
   if(MathAbs(a.ValueAt(t2) - b.ValueAt(t2)) >= tol)
      return(false);
   return(true);
  }

//+------------------------------------------------------------------+
//| Sestavi reliefni primky z hlavnich swingu vstupniho timeframu.   |
//| Kazda dvojice swingu stejneho typu dava kandidata; projdou jen   |
//| primky, ktere cenu obaluji a maji dost dotyku. Vysledek je       |
//| serazen podle vyznamnosti a zbaven duplicit.                     |
//| Filtry jsou serazene od nejlevnejsiho k nejdrazsimu - pruchod    |
//| svickami dostane az kandidat, ktery prosel testy delky, stari a  |
//| driftu (drive bezel pruchod jako prvni pro kazdou dvojici).      |
//|  rates - svicky vstupniho TF (index 0 = nejstarsi)               |
//|  p     - parametry hledani                                       |
//|  out   - vystupni pole vybranych primek                          |
//|  st    - statistika zamitnuti (in/out)                           |
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
      const int depth = SvedScaleDepth(p.swingDepth, sc);
      if(!SvedScaleFits(depth, n))
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
            ln.maxOver = 0.0; ln.meanGap = 0.0;
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

            // Jak daleko primka ujela od sve druhe opory. Strma cara se
            // za par hodin vzdali desitky dolaru od ceny, kde uz se
            // niceho nedotyka - takova primka neni reliefem, ale artefaktem.
            // Test je O(1), proto bezi jeste pred pruchodem svickami.
            if(p.maxDrift > 0.0)
              {
               const double drift = MathAbs(ln.ValueAt(rates[n - 1].time) - ln.p2);
               if(drift > p.maxDrift)
                 {
                  st.drift++;
                  continue;
                 }
              }

            bool midTouch = false;
            if(!SvedReliefScan(rates, ln, p, midTouch))
              {
               st.pierced++;
               continue;
              }

            // Primka musi sedet na cenove akci i mimo sve opory
            if(p.needMidTouch && !midTouch)
              {
               st.midTouch++;
               continue;
              }

            if(ln.touches < p.minTouches)
              {
               st.touches++;
               continue;
              }

            st.passed++;

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

            ArrayResize(cand, nc + 1, 128);
            cand[nc++] = ln;
           }
        }
     }   // konec smycky pres meritka

   if(nc == 0)
      return(0);

   //--- Serazeni podle vyznamnosti
   SvedSortByScoreDesc(cand);

   //--- Vyber s odstranenim prakticky totoznych primek.
   //--- Odpory a podpory se stridaji, aby jeden typ neobsadil vsechny
   //--- sloty - jinak by silna serie podpor zastinila platny odpor.
   const datetime tLast    = rates[n - 1].time;
   const int      backBars = MathMin(SVED_DEDUP_BACK_BARS, n - 1);
   const datetime tPast    = rates[n - 1 - backBars].time;
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

         bool dup = false;
         for(int j = 0; j < taken; j++)
            if(SvedReliefSimilar(out[j], cand[i], tLast, tPast, p.dedupTol))
              {
               dup = true;
               break;
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
//| tedy ty, ktere by prurazu staly v ceste.                         |
//|  lines     - aktivni reliefni primky                             |
//|  t         - cas, ke kteremu se primky pocitaji                  |
//|  price     - vychozi cena (planovany vstup)                      |
//|  isBuy     - smer obchodu                                        |
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

      // Primka za zady obchodu nevadi - prekazkou je jen ta ve smeru
      if(isBuy ? (v <= price) : (v >= price))
         continue;

      const double d = isBuy ? (v - price) : (price - v);
      if(best < 0.0 || d < best)
        {
         best      = d;
         linePrice = v;
        }
     }

   return(best);
  }

#endif // __SVED_RELIEF_MQH__
//+------------------------------------------------------------------+
