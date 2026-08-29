//+------------------------------------------------------------------+
//|                                               PuntikyRelief.mqh  |
//|      Reliefni primky na vstupnim timeframu (M1)                  |
//|                                                                  |
//|  Reliefni primka je trendlinie vedena dvema hlavnimi swingy      |
//|  stejneho typu - dvema vrcholy (odpor) nebo dvema dny (podpora). |
//|  Musi cenu obalovat, tedy zadna svicka ji nesmi prorazit, jinak  |
//|  uz prestala platit. Takova primka stoji prurazu v ceste a       |
//|  strategie ji hlida pri planovani vstupu (viz docs/relief_1.png).|
//+------------------------------------------------------------------+
#property copyright "Puntiky"

#ifndef __PUNTIKY_RELIEF_MQH__
#define __PUNTIKY_RELIEF_MQH__

#include <Puntiky\PuntikyTypes.mqh>
#include <Puntiky\PuntikySwings.mqh>

//+------------------------------------------------------------------+
//| Reliefni primka                                                  |
//+------------------------------------------------------------------+
struct SReliefLine
  {
   bool              isHigh;    // true = odpor (nad cenou), false = podpora
   datetime          t1, t2;    // opory primky
   double            p1, p2;
   int               i1, i2;    // indexy baru v analyzovanem poli
   double            slope;     // zmena ceny na 1 bar
   int               touches;   // pocet potvrzenych dotyku (bez opor primky)
   int               spanBars;  // delka primky v barech
   int               ageBars;   // stari druhe opory v barech
   double            meanGap;   // prumerny odstup od ceny mezi oporami
   double            maxOver;   // nejvetsi presah knotu pres primku
   double            score;     // pro vyber nejvyznamnejsich primek

   //--- Hodnota primky na baru s indexem idx.
   //--- Stejne jako u kanalu se pocita v INDEXECH baru, ne v case:
   //--- MT5 kresli usecku v prostoru indexu, takze primka vedena pres
   //--- vikendovou mezeru by se v grafu ohnula mimo hodnotu, se kterou
   //--- expert zkracuje PT (viz hlavicka SChannel).
   double            ValueAtBar(const double idx)
     {
      return p1 + slope * (idx - (double)i1);
     }
   //--- Odstup svicky od uz spoctene hodnoty primky: kladny = svicka
   //--- primku nedosahla, zaporny = knot ji presahl. Jedna definice pro
   //--- vsechny testy - driv byla tataz nerovnost opsana ve ctyrech
   //--- funkcich a jejich kopie se rozesly.
   double            GapFrom(const double v, const double high, const double low)
     {
      return isHigh ? (v - high) : (low - v);
     }
   //--- Odstup svicky od primky na baru idx
   double            GapAtBar(const double idx, const double high, const double low)
     {
      return GapFrom(ValueAtBar(idx), high, low);
     }
   //--- Dotyk primky: svicka je v tolerancnim pasmu kolem ni
   bool              IsTouch(const double gap, const double tol)
     {
      return (gap >= -tol && gap <= tol);
     }
   //--- Prorazi svicka primku? Rozhoduje se z uz spoctene hodnoty
   //--- primky a odstupu svicky, aby se v nejcastejsi smycce cele
   //--- detekce nepocitaly znovu. Telo primku prekrocit nesmi vubec
   //--- (tolerance pierceTol), knot ji smi presahnout az o wickTol,
   //--- ale JEN MEZI oporami - za druhou oporou je primka tvrda
   //--- hranice a novy extrem ji rusi.
   //---  idx        - index baru (rozliseni "za druhou oporou")
   //---  v          - hodnota primky na tomto baru
   //---  gap        - odstup svicky od primky (viz GapFrom)
   //---  open,close - telo svicky
   //---  pierceTol  - povolene proriznuti telem
   //---  wickTol    - povoleny presah knotem mezi oporami
   bool              PiercedAt(const double idx, const double v, const double gap,
                               const double open, const double close,
                               const double pierceTol, const double wickTol)
     {
      if(isHigh ? (MathMax(open, close) > v + pierceTol)
                : (MathMin(open, close) < v - pierceTol))
         return(true);
      return(-gap > ((idx <= (double)i2) ? wickTol : pierceTol));
     }
   //--- Totez pro bar, jehoz hodnotu primky volajici jeste nema
   bool              BarPierces(const double idx, const double open, const double high,
                                const double low, const double close,
                                const double pierceTol, const double wickTol)
     {
      const double v = ValueAtBar(idx);
      return(PiercedAt(idx, v, GapFrom(v, high, low), open, close, pierceTol, wickTol));
     }
   //--- Ujela primka od sve druhe opory pres povoleny prah?
   //--- (0 = filtr vypnuty; prah viz PuntikyReliefDriftLimit)
   bool              Drifted(const double idx, const double driftLimit)
     {
      return(driftLimit > 0.0 && MathAbs(ValueAtBar(idx) - p2) > driftLimit);
     }
   //--- Je druha opora uz prilis stara? (0 = filtr vypnuty)
   bool              Expired(const double idx, const double maxAgeFactor)
     {
      return(maxAgeFactor > 0.0 &&
             (idx - (double)i2) > maxAgeFactor * (double)spanBars);
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
   int               merged;     // proslo filtry, ale splynulo s primkou od teze kotvy
   int               passed;     // proslo filtry a stalo se samostatnym kandidatem
   int               selected;   // vybrano

   void              Reset()
     {
      pairs = 0; span = 0; age = 0; drift = 0; pierced = 0;
      midTouch = 0; touches = 0; merged = 0; passed = 0; selected = 0;
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
   double            maxDrift;     // jak daleko smi primka ujet od druhe opory (v cene)
   double            maxDriftATR;  // totez jako nasobek ATR (0 = jen bodova mez)
   double            atr;          // aktualni ATR pracovniho TF
   bool              needMidTouch; // vyzadovat dotyk i uprostred primky
   double            midTol;       // tolerance stredniho dotyku (v cene)
   double            midFrom;      // zacatek stredniho useku (0..1)
   double            midTo;        // konec stredniho useku (0..1)
   int               maxLines;     // kolik primek ponechat
  };

//+------------------------------------------------------------------+
//| Prah, za kterym uz primka od sve druhe opory ujela prilis.       |
//| Bere se VETSI z bodove meze a nasobku ATR. Samotna bodova mez se |
//| totiz neprizpusobi nastroji: zadani 3000 b znamena na zlate      |
//| primerenych par ATR, kdezto na BTCUSD (ATR M15 kolem 84 USD) jen |
//| 0.36 ATR - filtr tam zahazoval 99 % kandidatu a zbyly jen         |
//| vodorovne nebo cerstve primky. Sirka kanalu se meri stejne, tedy |
//| bodova mez vedle nasobku ATR.                                    |
//| Nula v bodove mezi znamena vypnuty filtr, i kdyz je nasobek ATR  |
//| zadany - "bez omezeni" musi zustat bez omezeni.                  |
//|  p - parametry hledani (vcetne aktualniho ATR)                   |
//+------------------------------------------------------------------+
double PuntikyReliefDriftLimit(const SReliefParams &p)
  {
   if(p.maxDrift <= 0.0)
      return(0.0);
   if(p.atr > 0.0 && p.maxDriftATR > 0.0)
      return(MathMax(p.maxDrift, p.maxDriftATR * p.atr));
   return(p.maxDrift);
  }

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
//| Dotyky blize nez PUNTIKY_TOUCH_GAP baru se pocitaji jako jeden,  |
//| aby jedna delsi epizoda nenafoukla skore.                        |
//|  rates    - svicky vstupniho TF (index 0 = nejstarsi)            |
//|  ln       - primka; zapisuji se do ni maxOver, touches, meanGap  |
//|  p        - parametry (tolerance a stredni usek)                 |
//|  midTouch - out: nasel se dotyk ve stredni casti primky?         |
//| Vraci false, kdyz je primka prorazena.                           |
//+------------------------------------------------------------------+
bool PuntikyReliefScan(const MqlRates &rates[], SReliefLine &ln, const SReliefParams &p,
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
   int    lastTouch = -PUNTIKY_TOUCH_GAP;   // zadny dotyk zatim

   for(int i = from; i < n; i++)
     {
      // Hodnota primky se pocita jednou za bar - je to nejcastejsi
      // operace cele detekce
      const double v   = ln.ValueAtBar((double)i);
      const double gap = ln.GapFrom(v, rates[i].high, rates[i].low);

      //--- Telo pres primku i knot za druhou oporou znamenaji
      //--- prorazeni - predikat je spolecny s revalidaci drzenych
      //--- primek v expertovi, aby se obe cesty nemohly rozejit
      if(ln.PiercedAt((double)i, v, gap, rates[i].open, rates[i].close,
                      p.pierceTol, p.wickTol))
         return(false);

      const double over = -gap;
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
      if(ln.IsTouch(gap, p.touchTol) && (isAnchor || i - lastTouch >= PUNTIKY_TOUCH_GAP))
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
//| Porovnava se ve DVOU okamzicich - dve primky s ruznym sklonem se |
//| u posledni svicky muzou zrovna krizit a pri porovnani jedinym    |
//| okamzikem by se chybne slily (stejnou past resi i dedup kanalu). |
//|  a, b   - porovnavane primky                                     |
//|  b1, b2 - dva ruzne indexy baru pro porovnani                    |
//|  tol    - prah shody v cene                                      |
//+------------------------------------------------------------------+
bool PuntikyReliefSimilar(SReliefLine &a, SReliefLine &b, const double b1, const double b2,
                       const double tol)
  {
   if(a.isHigh != b.isHigh)
      return(false);
   if(MathAbs(a.ValueAtBar(b1) - b.ValueAtBar(b1)) >= tol)
      return(false);
   if(MathAbs(a.ValueAtBar(b2) - b.ValueAtBar(b2)) >= tol)
      return(false);
   return(true);
  }

//+------------------------------------------------------------------+
//| Sestavi reliefni primky z hlavnich swingu vstupniho timeframu.   |
//| Kazda dvojice swingu stejneho typu dava kandidata; projdou jen   |
//| primky, ktere cenu obaluji a maji dost dotyku. Vysledek je       |
//| serazen podle vyznamnosti a zbaven duplicit.                     |
//| Filtry jsou serazene od nejlevnejsiho k nejdrazsimu: pruchod     |
//| celou historii dostane az kandidat, ktery prosel testy delky,     |
//| stari, driftu a predfiltrem pres swingove extremy.               |
//|  rates - svicky vstupniho TF (index 0 = nejstarsi)               |
//|  p     - parametry hledani                                       |
//|  out   - vystupni pole vybranych primek                          |
//|  st    - statistika zamitnuti (in/out)                           |
//| Vraci pocet primek ulozenych do out[].                           |
//+------------------------------------------------------------------+
int PuntikyBuildReliefLines(const MqlRates &rates[], const SReliefParams &p, SReliefLine &out[],
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

   // Prah driftu se spocita jednou - zavisi jen na parametrech a ATR
   const double driftLimit = PuntikyReliefDriftLimit(p);

   //--- Swingy se hledaji ve vice meritkach - jemne okno da cerstve
   //--- lokalni primky, hrube okno vidi jen hlavni vrcholy/dna, takze
   //--- pres omezeny odstup opor dosahne i na vzdalene swingy (vejir
   //--- trendlinii z hlavnich vrcholu; viz docs/uprava_2.png).
   //--- Stejna dvojice oporovych baru z ruznych meritek se slouci
   //--- pres vyber "nejlepsi primka na oporu" nize.
   for(int sc = 0; sc < MathMax(p.scales, 1); sc++)
     {
      const int depth = PuntikyScaleDepth(p.swingDepth, sc);
      if(!PuntikyScaleFits(depth, n))
         break;

      SSwing sw[];
      const int ns = PuntikyDetectSwings(rates, depth, sw);
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

            // Sklon na BAR, ne na sekundu (viz hlavicka SReliefLine)
            const double dBars = (double)(ln.i2 - ln.i1);
            if(dBars <= 0.0)
               continue;
            ln.slope = (ln.p2 - ln.p1) / dBars;

            // Jak daleko primka ujela od sve druhe opory. Strma cara se
            // za par hodin vzdali od ceny nekolik ATR, kde uz se niceho
            // nedotyka - takova primka neni reliefem, ale artefaktem.
            // Test je O(1), proto bezi jeste pred pruchodem svickami.
            if(driftLimit > 0.0)
              {
               const double drift = MathAbs(ln.ValueAtBar((double)(n - 1)) - ln.p2);
               if(drift > driftLimit)
                 {
                  st.drift++;
                  continue;
                 }
              }

            // Levny predfiltr pred pruchodem celou historii: swing
            // tehoz typu ZA druhou oporou, ktery primku presahuje vic
            // nez pierceTol, ji prorazi urcite (tam uz je primka tvrdou
            // hranici i pro knot). Je to nutna podminka testu ve
            // PuntikyReliefScan, takze vysledek zustava stejny - jen se
            // beznadejny kandidat zahodi za O(pocet swingu) misto
            // O(pocet baru), coz je nejdrazsi cast cele detekce.
            bool pierced = false;
            for(int k = j + 1; k < ns; k++)
              {
               if(sw[k].isHigh != ln.isHigh)
                  continue;
               const double vs = ln.ValueAtBar((double)sw[k].index);
               if(ln.GapFrom(vs, sw[k].price, sw[k].price) < -p.pierceTol)
                 {
                  pierced = true;
                  break;
                 }
              }
            if(pierced)
              {
               st.pierced++;
               continue;
              }

            bool midTouch = false;
            if(!PuntikyReliefScan(rates, ln, p, midTouch))
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
               // Vejir primek z jedne kotvy da jednoho kandidata, at uz
               // vyhraje kterakoli z nich - do "proslo" se proto pocita
               // az skutecne vznikly kandidat nize. Drive se zapocitaly
               // vsechny a diagnostika hlasila radove vic primek, nez
               // kolik jich doopravdy bylo.
               st.merged++;

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

            st.passed++;
            ArrayResize(cand, nc + 1, 128);
            cand[nc++] = ln;
           }
        }
     }   // konec smycky pres meritka

   if(nc == 0)
      return(0);

   //--- Serazeni podle vyznamnosti
   PuntikySortByScoreDesc(cand);

   //--- Vyber s odstranenim prakticky totoznych primek.
   //--- Odpory a podpory se stridaji, aby jeden typ neobsadil vsechny
   //--- sloty - jinak by silna serie podpor zastinila platny odpor.
   const double barLast = (double)(n - 1);
   const double barPast = (double)(n - 1 - MathMin(PUNTIKY_DEDUP_BACK_BARS, n - 1));
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
            if(PuntikyReliefSimilar(out[j], cand[i], barLast, barPast, p.dedupTol))
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
//| Stejne jako u hran kanalu se bere KONZERVATIVNEJSI z hodnoty na  |
//| aktualnim baru a na baru projekce (pro BUY nizsi, pro SELL       |
//| vyssi). Drive se primka merila jen "ted", takze strma cara       |
//| (InpReliefMaxDrift pripousti i velmi strme) zkracovala PT podle  |
//| polohy, kterou uz v okamziku vyplneni prikazu davno nemela.      |
//|  lines     - aktivni reliefni primky                             |
//|  barNow    - index baru, ke kteremu se primky pocitaji           |
//|  barProj   - index baru projekce primek dopredu                  |
//|  price     - vychozi cena (planovany vstup)                      |
//|  isBuy     - smer obchodu                                        |
//|  linePrice - out: konzervativni cena nalezene primky             |
//| Vraci vzdalenost v cene, nebo -1 pokud zadna primka nevadi.      |
//+------------------------------------------------------------------+
double PuntikyNearestRelief(SReliefLine &lines[], const double barNow, const double barProj,
                         const double price, const bool isBuy, double &linePrice)
  {
   const int cnt = ArraySize(lines);
   double best = -1.0;
   linePrice = 0.0;

   for(int i = 0; i < cnt; i++)
     {
      const double vNow  = lines[i].ValueAtBar(barNow);
      const double vProj = lines[i].ValueAtBar(barProj);

      // Primka za zady obchodu nevadi - prekazkou je jen ta ve smeru
      if(isBuy ? (vNow <= price) : (vNow >= price))
         continue;

      // Konzervativni odhad polohy primky v case obchodu
      const double v = isBuy ? MathMin(vNow, vProj) : MathMax(vNow, vProj);
      const double d = MathMax(isBuy ? (v - price) : (price - v), 0.0);

      if(best < 0.0 || d < best)
        {
         best      = d;
         linePrice = v;
        }
     }

   return(best);
  }

#endif // __PUNTIKY_RELIEF_MQH__
//+------------------------------------------------------------------+
