//+------------------------------------------------------------------+
//|                                             PuntikyChannels.mqh  |
//|      Sestaveni, ohodnoceni a vyber hlavnich ABCD kanalu          |
//+------------------------------------------------------------------+
#property copyright "Puntiky"

#ifndef __PUNTIKY_CHANNELS_MQH__
#define __PUNTIKY_CHANNELS_MQH__

#include <Puntiky\PuntikyTypes.mqh>
#include <Puntiky\PuntikySwings.mqh>

//+------------------------------------------------------------------+
//| Test, zda jsou opory A a C skutecne vyraznymi extremy.           |
//| V okne +-window baru kolem nich nesmi lezet vyraznejsi extrem    |
//| tehoz typu (vyssi high u HIGH zakladny, nizsi low u LOW).        |
//|                                                                  |
//| Tohle je jina podminka nez neproriznuta usecka: zakladni usecka  |
//| je sikma, takze sousedni vyssi vrchol muze lezet cenove vys, a   |
//| pritom porad POD prodlouzenou carou. Bez teto kontroly by pak    |
//| usecka zacinala na druhem nejvyssim vrcholu misto na tom         |
//| nejvyssim - presne to je pripad z docs/abcd 5.png.               |
//|  rates  - svicky TF kanalu (index 0 = nejstarsi)                 |
//|  ch     - kandidatni kanal                                       |
//|  window - polovicni sirka okna v barech (0 = test vypnuty)       |
//+------------------------------------------------------------------+
bool PuntikyAnchorsAreExtremes(const MqlRates &rates[], SChannel &ch, const int window)
  {
   if(window <= 0)
      return(true);

   const int n = ArraySize(rates);

   // pass 0 = bod A, pass 1 = bod C
   for(int pass = 0; pass < 2; pass++)
     {
      const int    idx  = (pass == 0) ? ch.iA : ch.iC;
      const double ref  = (pass == 0) ? ch.pA : ch.pC;
      const int    from = MathMax(idx - window, 0);
      const int    to   = MathMin(idx + window, n - 1);

      for(int i = from; i <= to; i++)
        {
         if(ch.baseIsLow)
           {
            if(rates[i].low < ref)
               return(false);   // v okoli lezi hlubsi dno
           }
         else
           {
            if(rates[i].high > ref)
               return(false);   // v okoli lezi vyssi vrchol
           }
        }
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Jediny pruchod svickami kanalu: kontrola proriznuti, podil       |
//| svicek uvnitr a pocet dotyku hran.                               |
//|                                                                  |
//| Obe hrany se pri kontrole proriznuti posuzuji ruzne, protoze     |
//| maji jiny vyznam:                                                |
//|                                                                  |
//|  ZAKLADNI usecka (nese body A a C) nesmi byt proriznuta NIKDY -  |
//|  ani za bodem C. Kdyz ji pozdejsi swing protne, neni to          |
//|  invalidace kanalu, ale znameni, ze je usecka vedena spatne a    |
//|  bod C patri prave na ten pozdejsi extrem. Kandidat proto        |
//|  vypadne a projde jiny, se spravne posunutym C (a tedy i         |
//|  odpovidajicim sklonem protejsi hrany).                          |
//|                                                                  |
//|  PROTEJSI hrana (rovnobezka bodem B) musi drzet jen mezi A a C.  |
//|  Za bodem C se toleruje invalidTolFrac - vetsi prekroceni uz     |
//|  znamena prorazeny, tedy neplatny kanal.                         |
//|                                                                  |
//| Zakladni usecka se navic kontroluje i backCheckBars svicek PRED  |
//| bodem A. Kdyz tesne pred A lezi jeste vyraznejsi extrem, patri   |
//| bod A na nej - jinak by usecka zacinala na druhem nejvyssim      |
//| vrcholu a ten vyssi by ji zleva prorazel.                        |
//|                                                                  |
//| Kvalita (dotyky, containment) se pocita az od bodu A dal a bez   |
//| oporovych baru A, B a C - ty na hranach lezi z definice, takze   |
//| by kazdemu kanalu daly tri dotyky zadarmo a filtr minTouches by  |
//| prakticky nic nefiltroval.                                       |
//|  rates - svicky TF kanalu (index 0 = nejstarsi)                  |
//|  ch    - kandidatni kanal; zapisuji se do nej touches a          |
//|          containment                                             |
//|  p     - parametry filtrovani (tolerance)                        |
//| Vraci false, kdyz je kanal proriznuty nebo prorazeny.            |
//+------------------------------------------------------------------+
bool PuntikyChannelScan(const MqlRates &rates[], SChannel &ch, const SChannelParams &p)
  {
   const int    n          = ArraySize(rates);
   const double tolBase    = p.pierceTolFrac  * ch.width;
   const double tolOutside = p.invalidTolFrac * ch.width;
   const double tolTouch   = p.touchTolFrac   * ch.width;
   const double tolInside  = p.insideTolFrac  * ch.width;
   const int    from       = MathMax(ch.iA - MathMax(p.backCheckBars, 0), 0);

   int inside  = 0;
   int total   = 0;
   int touches = 0;

   // Zadny dotyk zatim - prvni bar tak vzdy projde testem odstupu
   int lastUpTouch = -PUNTIKY_TOUCH_GAP;
   int lastLoTouch = -PUNTIKY_TOUCH_GAP;

   for(int i = from; i < n; i++)
     {
      // Kanal je vedeny v indexech baru, testuje se tedy proti indexu
      const double bar = (double)i;

      // Pred bodem A kanal jeste "neexistuje" - kontroluje se tam
      // pouze zakladni usecka, protejsi hrana ne
      const bool beforeA = (i < ch.iA);

      // Protejsi hrana: mezi A a C prisne, za C volneji
      const double tolOpp = (i <= ch.iC) ? tolBase : tolOutside;

      if(ch.baseIsLow)
        {
         // Zakladni usecka je spodni hrana
         if(rates[i].low < ch.LowerAtBar(bar) - tolBase)
            return(false);
         if(!beforeA && rates[i].high > ch.UpperAtBar(bar) + tolOpp)
            return(false);
        }
      else
        {
         // Zakladni usecka je horni hrana
         if(rates[i].high > ch.UpperAtBar(bar) + tolBase)
            return(false);
         if(!beforeA && rates[i].low < ch.LowerAtBar(bar) - tolOpp)
            return(false);
        }

      if(beforeA)
         continue;

      total++;
      if(ch.ContainsAtBar(bar, rates[i].close, tolInside))
         inside++;

      // Opory se jako dotyk nepocitaji (viz hlavicka), ale nastavuji zaraz
      // epizody na sve hrane - bar tesne vedle opory patri do teze
      // dotykove epizody a nesmi ji zdvojit. A a C lezi na zakladni
      // usecce, B na protejsi.
      if(i == ch.iA || i == ch.iC)
        {
         if(ch.baseIsLow)
            lastLoTouch = i;
         else
            lastUpTouch = i;
         continue;
        }
      if(i == ch.iB)
        {
         if(ch.baseIsLow)
            lastUpTouch = i;
         else
            lastLoTouch = i;
         continue;
        }

      if(ch.TouchesUpperAtBar(bar, rates[i].high, tolTouch) && i - lastUpTouch >= PUNTIKY_TOUCH_GAP)
        {
         touches++;
         lastUpTouch = i;
        }
      if(ch.TouchesLowerAtBar(bar, rates[i].low, tolTouch) && i - lastLoTouch >= PUNTIKY_TOUCH_GAP)
        {
         touches++;
         lastLoTouch = i;
        }
     }

   ch.touches     = touches;
   ch.containment = (total > 0) ? (double)inside / (double)total : 0.0;
   return(true);
  }

//+------------------------------------------------------------------+
//| Ohodnoti kandidatni kanal na useku od bodu A do posledni svicky. |
//| Filtry jsou serazene od nejlevnejsiho k nejdrazsimu, aby drahy   |
//| pruchod svickami dostali jen kandidati, kteri maji sanci projit. |
//| Vraci false, pokud kanal neprosel filtry.                        |
//|  rates - svicky TF kanalu (index 0 = nejstarsi)                  |
//|  ch    - kanal (in/out), p - parametry filtrovani                |
//|  st    - statistika zamitnuti (in/out)                           |
//+------------------------------------------------------------------+
bool PuntikyEvaluateChannel(const MqlRates &rates[], SChannel &ch, const SChannelParams &p,
                         SChannelStats &st)
  {
   const int n = ArraySize(rates);
   if(n <= 0 || ch.width <= 0.0)
      return(false);

   //--- Tvrde geometricke filtry (O(1))
   ch.spanBars = ch.iC - ch.iA;
   ch.ageBars  = (n - 1) - ch.iC;
   if(ch.spanBars < p.minSpanBars)
     {
      st.span++;
      return(false);
     }
   if(ch.ageBars > p.maxAgeBars)
     {
      st.age++;
      return(false);
     }
   if(ch.width < p.minWidthPrice)
     {
      st.width++;
      return(false);
     }
   if(p.atr > 0.0 && ch.width < p.minWidthATR * p.atr)
     {
      st.width++;
      return(false);
     }

   //--- Volitelny pozadavek: aktualni cena musi byt stale uvnitr kanalu.
   //--- Je to test jedine svicky, proto bezi jeste pred pruchody polem.
   if(p.requireInside)
     {
      if(!ch.ContainsAtBar((double)(n - 1), rates[n - 1].close, p.insideTolFrac * ch.width))
        {
         st.outside++;
         return(false);
        }
     }

   //--- Opory A a C musi byt vyraznymi extremy sveho okoli (O(okno))
   if(!PuntikyAnchorsAreExtremes(rates, ch, p.anchorWindow))
     {
      st.anchors++;
      return(false);
     }

   //--- Jediny pruchod svickami: proriznuti, dotyky, containment
   if(!PuntikyChannelScan(rates, ch, p))
     {
      st.pierced++;
      return(false);
     }

   if(ch.touches < p.minTouches)
     {
      st.touches++;
      return(false);
     }
   if(ch.containment < p.minContainment)
     {
      st.containment++;
      return(false);
     }

   //--- Skore rozhoduje, ktery kanal je "hlavni a dulezity".
   //--- Vahy jsou volene tak, aby se jednotlive slozky nesecetly rychle
   //--- do stropu - jinak by mely vsechny slusne kanaly stejne skore
   //--- a vyber hlavniho kanalu by byl nahodny.
   double sc = 0.0;
   sc += ch.containment * 6.0;                                        // 0 az 6
   sc += (double)MathMin(ch.touches, 15) * 1.0;                       // 0 az 15
   sc += MathMin((double)ch.spanBars / (double)MathMax(p.minSpanBars, 1), 6.0);
   if(p.atr > 0.0)
      sc += MathMin(ch.width / p.atr, 6.0) * 0.6;                     // 0 az 3.6
   sc -= MathMin((double)ch.ageBars / (double)MathMax(p.maxAgeBars, 1), 1.0) * 2.0;

   ch.score = sc;
   st.passed++;
   return(true);
  }

//+------------------------------------------------------------------+
//| Dohleda potvrzene dotyky hran za bodem C a ulozi je do kanalu    |
//| jako body D, E, F ...                                            |
//| Body A a C lezi na zakladni usecce, B na protejsi - dalsi dotyk  |
//| se proto ceka stridave, vzdy na opacne hrane nez ten predchozi.  |
//| Bod se zapisuje az ve chvili, kdy k dotyku skutecne doslo;       |
//| nic se nepredikuje dopredu. Z jedne dotykove epizody se bere     |
//| jeji nejzazsi svicka.                                            |
//|                                                                  |
//| Dotyk se testuje TYMZ predikatem jako pri pocitani skore, ale    |
//| POCITA SE JINA MNOZINA a obe cisla se rovnat nemaji:             |
//|   ch.touches (skore)  - obe hrany nezavisle, uz od bodu A,       |
//|                         bez horniho omezeni poctu,               |
//|   ch.extraCount (zde) - jen dotyky ZA bodem C, striktne stridave |
//|                         a nejvyse PUNTIKY_MAX_TOUCH_POINTS.      |
//| Panel proto vypisuje obe hodnoty zvlast ("dotyku od A" a "body   |
//| po C"), aby pocet pismen v grafu odpovidal tomu druhemu.         |
//|  rates   - svicky TF kanalu (index 0 = nejstarsi)                |
//|  ch      - kanal, do ktereho se body zapisou                     |
//|  tolFrac - tolerance dotyku jako zlomek sirky kanalu             |
//+------------------------------------------------------------------+
void PuntikyCollectTouchPoints(const MqlRates &rates[], SChannel &ch, const double tolFrac)
  {
   ch.extraCount = 0;
   const int    n   = ArraySize(rates);
   const double tol = tolFrac * ch.width;

   // Po bodu C se ceka dotyk protejsi hrany (tam, kde lezi bod B)
   bool expectUpper = ch.baseIsLow;

   int i = ch.iC + 1;
   while(i < n && ch.extraCount < PUNTIKY_MAX_TOUCH_POINTS)
     {
      const double bar = (double)i;
      const bool touched = expectUpper ? ch.TouchesUpperAtBar(bar, rates[i].high, tol)
                                       : ch.TouchesLowerAtBar(bar, rates[i].low,  tol);
      if(!touched)
        {
         i++;
         continue;
        }

      // Dotykova epizoda muze trvat vic svicek - vybere se ta nejzazsi
      int    bestIdx   = i;
      double bestPrice = expectUpper ? rates[i].high : rates[i].low;
      int    k         = i + 1;

      while(k < n)
        {
         const double barK = (double)k;
         const bool still = expectUpper ? ch.TouchesUpperAtBar(barK, rates[k].high, tol)
                                        : ch.TouchesLowerAtBar(barK, rates[k].low,  tol);
         if(!still)
            break;
         if(expectUpper ? (rates[k].high > bestPrice) : (rates[k].low < bestPrice))
           {
            bestPrice = expectUpper ? rates[k].high : rates[k].low;
            bestIdx   = k;
           }
         k++;
        }

      ch.tExtra[ch.extraCount]     = rates[bestIdx].time;
      ch.pExtra[ch.extraCount]     = bestPrice;
      ch.extraUpper[ch.extraCount] = expectUpper;
      ch.extraCount++;

      expectUpper = !expectUpper;   // dalsi dotyk se ceka na opacne hrane
      i = k;
     }
  }

//+------------------------------------------------------------------+
//| Test, zda jsou dva kanaly prakticky totozne.                     |
//| Hrany se porovnavaji ve DVOU okamzicich - stoupajici a klesajici |
//| kanal se muzou v jedinem bode zrovna protinat a pri porovnani    |
//| jednim okamzikem by se chybne slily do jednoho                   |
//| (viz docs/iScreen ... 085407.png). Duplicita je jen tehdy,       |
//| kdyz obe hrany souhlasi v obou okamzicich.                       |
//|  a, b     - porovnavane kanaly                                   |
//|  b1, b2   - dva ruzne indexy baru pro porovnani                  |
//|  frac     - prah shody jako zlomek sirky sirsiho z kanalu        |
//+------------------------------------------------------------------+
bool PuntikyChannelsSimilar(SChannel &a, SChannel &b, const double b1, const double b2,
                         const double frac)
  {
   const double w = MathMax(a.width, b.width);
   if(w <= 0.0)
      return(false);

   if(MathAbs(a.UpperAtBar(b1) - b.UpperAtBar(b1)) >= frac * w)
      return(false);
   if(MathAbs(a.LowerAtBar(b1) - b.LowerAtBar(b1)) >= frac * w)
      return(false);
   if(MathAbs(a.UpperAtBar(b2) - b.UpperAtBar(b2)) >= frac * w)
      return(false);
   if(MathAbs(a.LowerAtBar(b2) - b.LowerAtBar(b2)) >= frac * w)
      return(false);
   return(true);
  }

//+------------------------------------------------------------------+
//| Je kandidat prakticky totozny s nekterym uz vybranym kanalem?    |
//|  cand   - testovany kandidat                                     |
//|  out    - dosud vybrane kanaly, taken - kolik jich je            |
//|  b1, b2 - indexy baru pro porovnani, frac - prah shody           |
//+------------------------------------------------------------------+
bool PuntikyChannelIsDuplicate(SChannel &cand, SChannel &out[], const int taken,
                            const double b1, const double b2, const double frac)
  {
   for(int j = 0; j < taken; j++)
      if(PuntikyChannelsSimilar(cand, out[j], b1, b2, frac))
         return(true);
   return(false);
  }

//+------------------------------------------------------------------+
//| Vygeneruje kandidatni kanaly z jedne swingove kostry a pripoji   |
//| je na konec pole cand[].                                         |
//| Zakladni useckou je spojnice dvou swingu stejneho typu (A a C),  |
//| protejsi hrana je jeji rovnobezka vedena bodem B (docs/abcd.png).|
//| Mezi A a C smi lezet dalsi swingy - zkousi se vsechny odstupy    |
//| az do p.maxSwingGap. Jako B se bere protilehly swing nejdal od   |
//| zakladni usecky, takze kanal cenovou akci skutecne obali -       |
//| stejne, jako kdyz se kresli rucne. Kandidaty, jejichz hrany      |
//| cenu prorezavaji, zahodi az filtr v PuntikyEvaluateChannel.      |
//|  rates    - svicky TF kanalu (index 0 = nejstarsi)               |
//|  sw       - swingova kostra jednoho meritka                      |
//|  p        - parametry filtrovani                                 |
//|  scaleIdx - poradi meritka, ve kterem kandidati vznikaji         |
//|  cand     - sberne pole kandidatu (in/out)                       |
//|  st       - statistika zamitnuti (in/out)                        |
//| Vraci celkovy pocet kandidatu v poli cand[].                     |
//+------------------------------------------------------------------+
int PuntikyCollectCandidates(const MqlRates &rates[], const SSwing &sw[], const SChannelParams &p,
                          const int scaleIdx, SChannel &cand[], SChannelStats &st)
  {
   const int n  = ArraySize(rates);
   const int ns = ArraySize(sw);
   int       nc = ArraySize(cand);
   if(n < 10 || ns < 3)
      return(nc);

   const int maxGap = MathMax(p.maxSwingGap, 2);

   for(int i = 0; i + 2 < ns; i++)
     {
      // Sudy odstup zarucuje, ze A i C jsou swingy stejneho typu
      for(int gap = 2; gap <= maxGap && i + gap < ns; gap += 2)
        {
         const int j = i + gap;
         st.generated++;

         SChannel ch;
         ch.scaleIdx  = scaleIdx;
         ch.baseIsLow = !sw[i].isHigh;   // A,C jsou dna -> zakladni je LOW usecka
         ch.tA = sw[i].time; ch.pA = sw[i].price; ch.iA = sw[i].index;
         ch.tC = sw[j].time; ch.pC = sw[j].price; ch.iC = sw[j].index;
         ch.touches = 0; ch.containment = 0.0; ch.spanBars = 0; ch.ageBars = 0;
         ch.score = 0.0; ch.extraCount = 0;

         // Sklon se pocita na BAR, ne na sekundu - stejne, jako kanal
         // kresli MT5 v grafu (viz hlavicka SChannel)
         const double dBars = (double)(ch.iC - ch.iA);
         if(dBars <= 0.0)
            continue;

         // Zakladni usecka je dana body A a C, proto ji lze sestrojit
         // jeste pred vyberem bodu B
         ch.slope = (ch.pC - ch.pA) / dBars;

         // B = protilehly swing nejdal od zakladni usecky. Meri se
         // odstup OD USECKY, ne absolutni cena - usecka je sikma,
         // takze cenove nejnizsi swing nemusi byt ten, ktery
         // rovnobezku odtlaci nejdal.
         int    bIdx  = -1;
         double bDist = 0.0;
         for(int k = i + 1; k < j; k++)
           {
            if(sw[k].isHigh == sw[i].isHigh)
               continue;
            const double base = ch.BaseAtBar((double)sw[k].index);
            const double d    = ch.baseIsLow ? (sw[k].price - base) : (base - sw[k].price);
            if(bIdx < 0 || d > bDist)
              {
               bIdx  = k;
               bDist = d;
              }
           }
         if(bIdx < 0 || bDist <= 0.0)
           {
            st.noB++;
            continue;   // zadny protilehly swing, nebo lezi na spatne strane
           }

         ch.tB = sw[bIdx].time; ch.pB = sw[bIdx].price; ch.iB = sw[bIdx].index;
         ch.width = bDist;      // sirka kanalu = odstup bodu B od zakladni usecky

         if(!PuntikyEvaluateChannel(rates, ch, p, st))
            continue;

         // Dalsi dotyky hran (D, E, F, ...) se dohledavaji az u kandidata,
         // ktery prosel filtry - zapisuji se jen skutecne probehle dotyky
         PuntikyCollectTouchPoints(rates, ch, p.touchTolFrac);

         // Rezerva pri zvetsovani - kandidatu byvaji stovky a kazda
         // realokace kopiruje cele pole struktur
         ArrayResize(cand, nc + 1, 256);
         cand[nc++] = ch;
        }
     }

   return(nc);
  }

//+------------------------------------------------------------------+
//| Z kandidatu vybere hlavni kanaly: seradi je podle skore,         |
//| odstrani prakticky totozne a ponecha nejvyse p.maxChannels.      |
//| Kanal v kanalu zustava zachovan - zahazuji se jen kanaly,        |
//| jejichz obe hrany lezi prakticky na sobe.                        |
//|  rates - svicky TF kanalu (kvuli casum porovnani)                |
//|  cand  - kandidati (pole se pri razeni prehazi)                  |
//|  p     - parametry vyberu                                        |
//|  out   - vystupni pole vybranych kanalu                          |
//| Vraci pocet vybranych kanalu ulozenych do out[].                 |
//+------------------------------------------------------------------+
int PuntikySelectChannels(const MqlRates &rates[], SChannel &cand[], const SChannelParams &p, SChannel &out[])
  {
   ArrayResize(out, 0);
   const int n  = ArraySize(rates);
   const int nc = ArraySize(cand);
   if(n < 10 || nc == 0)
      return(0);

   PuntikySortByScoreDesc(cand);

   // Dva porovnavaci indexy pro deduplikaci - druhy dost daleko, aby
   // se projevil rozdilny sklon kanalu
   const double barLast = (double)(n - 1);
   const double barPast = (double)(n - 1 - MathMin(PUNTIKY_DEDUP_BACK_BARS, n - 1));
   int taken = 0;
   ArrayResize(out, p.maxChannels);

   //--- 1. faze: z kazdeho meritka se vezme jeho nejlepsi kanal.
   //--- Hrube meritko dava velky kanal, jemne ten vnoreny - jinak by
   //--- vsechna mista obsadily varianty jedineho nejsilnejsiho kanalu
   //--- a "kanal v kanalu" by se nikdy nevykreslil.
   //--- Kandidati se nejprve posbiraji a teprve pak radi podle skore:
   //--- pri maxChannels < scales by jinak sloty rozebrala meritka v
   //--- poradi, v jakem jdou za sebou (tedy od nejjemnejsiho), a
   //--- globalne nejlepsi kanal hrubeho meritka - tedy prave ten velky,
   //--- kvuli kteremu se meritka pocitaji - by se do vyberu nedostal.
   SChannel best[];
   int nb = 0;
   ArrayResize(best, MathMax(p.scales, 1));
   for(int s = 0; s < MathMax(p.scales, 1); s++)
      for(int i = 0; i < nc; i++)
         if(cand[i].scaleIdx == s)
           {
            best[nb++] = cand[i];   // kandidati jsou serazeni, prvni je nejlepsi
            break;
           }
   ArrayResize(best, nb);
   PuntikySortByScoreDesc(best);

   for(int i = 0; i < nb && taken < p.maxChannels; i++)
     {
      if(PuntikyChannelIsDuplicate(best[i], out, taken, barLast, barPast, p.dedupFrac))
         continue;
      out[taken++] = best[i];
     }

   //--- 2. faze: zbyla mista se doplni podle skore bez ohledu na meritko
   for(int i = 0; i < nc && taken < p.maxChannels; i++)
     {
      if(PuntikyChannelIsDuplicate(cand[i], out, taken, barLast, barPast, p.dedupFrac))
         continue;
      out[taken++] = cand[i];
     }

   ArrayResize(out, taken);

   //--- Vysledek seradime podle skore, aby index 0 byl hlavni kanal
   //--- (kresli se silnejsi carou nez ostatni)
   PuntikySortByScoreDesc(out);

   return(taken);
  }

//+------------------------------------------------------------------+
//| Sestavi hlavni kanaly ve vice meritkach najednou.                |
//| Swingova kostra se hleda opakovane s ruzne sirokym pivot oknem   |
//| (baseDepth, 2x, 4x ...) - jemne okno najde male kanaly, hrube    |
//| okno velke. Prave diky tomu vznika i "kanal v kanalu".           |
//| Vysledne kandidaty ze vsech meritek hodnoti a vybira spolecne    |
//| PuntikySelectChannels, takze se meritka poctive porovnaji        |
//| a totozne nalezy se slouci.                                      |
//| Pocet meritek se bere z p.scales - drive chodil jeste jednou     |
//| zvlast argumentem a obe hodnoty se mohly rozejit (detekce podle  |
//| jedne, vyber podle druhe).                                       |
//|  rates     - svicky TF kanalu (index 0 = nejstarsi)              |
//|  p         - parametry detekce a vyberu                          |
//|  baseDepth - nejjemnejsi sirka pivot okna                        |
//|  out       - vystupni pole vybranych kanalu                      |
//|  st        - statistika detekce (in/out)                         |
//| Vraci pocet vybranych kanalu ulozenych do out[].                 |
//+------------------------------------------------------------------+
int PuntikyBuildChannels(const MqlRates &rates[], const SChannelParams &p,
                      const int baseDepth, SChannel &out[], SChannelStats &st)
  {
   st.Reset();

   SChannel cand[];
   const int n = ArraySize(rates);

   for(int s = 0; s < MathMax(p.scales, 1); s++)
     {
      const int depth = PuntikyScaleDepth(baseDepth, s);
      if(!PuntikyScaleFits(depth, n))
         break;   // okno uz je sirsi nez dostupna historie

      SSwing sw[];
      PuntikyDetectSwings(rates, depth, sw);
      PuntikyCollectCandidates(rates, sw, p, s, cand, st);
     }

   st.selected = PuntikySelectChannels(rates, cand, p, out);
   return(st.selected);
  }

//+------------------------------------------------------------------+
//| Najde nejblizsi hranu kanalu ve smeru obchodu a vrati vzdalenost |
//| od zadane ceny k teto hrane.                                     |
//| Prochazi obe hrany vsech aktivnich kanalu (tedy i vnorenych),    |
//| takze "dalsi hrana" muze patrit i mensimu kanalu uvnitr vetsiho. |
//| Kvuli sklonu hran se bere konzervativnejsi hodnota z aktualniho  |
//| baru a z baru projekce (barProj) - pro BUY nizsi, pro SELL vyssi.|
//|                                                                  |
//| Test "hrana lezi ve smeru obchodu" je ZAMERNE bez tolerance, na   |
//| rozdil od pasma v SChannel::TouchesUpperAtBar. Obe cisla resi     |
//| jinou otazku: dotyk s tolerancni zonou je hodnoceni kvality       |
//| kanalu (knot smi hranu lehce presahnout a porad je to dotyk),     |
//| kdezto tady jde o planovani obchodu - hrana pod referencni cenou  |
//| uz je prorazena a prekazkou neni, hrana nad ni prekazkou je.      |
//| Tolerance kolem reference by tu udelala pasmo, ve kterem by hrana |
//| nebyla ani prekazkou, ani prorazenou - PT by pak mirilo v plne    |
//| delce skrz hranu, na ktere spoustec sedi.                        |
//| Kdyz sikma hrana do casu projekce klesne az za zadanou cenu,     |
//| vraci se vzdalenost 0 (misto pro PT uz neni zadne) - zaporna     |
//| delka by se jinak protlacila do panelu i do vypoctu. Do          |
//| edgePrice se i v tom pripade vraci poloha HRANY, ne zadana cena: |
//| volajici ji vypisuje jako "hranu kanalu" a driv v ni mel ulozeny |
//| vlastni spoustec, tedy cenu, ktera zadnou hranici kanalu neni.   |
//|  ch        - aktivni kanaly                                      |
//|  barNow    - index baru, ke kteremu se hrany pocitaji            |
//|  barProj   - index baru projekce hran dopredu                    |
//|  price     - vychozi cena (referencni uroven obchodu)            |
//|  isBuy     - smer obchodu                                        |
//|  edgePrice - out: cena nalezene hrany                            |
//| Vraci vzdalenost v cene, nebo -1 pokud zadna hrana ve smeru      |
//| obchodu neexistuje.                                              |
//+------------------------------------------------------------------+
double PuntikyDistanceToNextEdge(SChannel &ch[], const double barNow, const double barProj,
                              const double price, const bool isBuy, double &edgePrice)
  {
   const int cnt = ArraySize(ch);
   double best = -1.0;
   edgePrice = 0.0;

   for(int i = 0; i < cnt; i++)
     {
      // Obe hrany kazdeho kanalu jsou platnym cilem
      for(int e = 0; e < 2; e++)
        {
         const double vNow  = (e == 0) ? ch[i].UpperAtBar(barNow)  : ch[i].LowerAtBar(barNow);
         const double vProj = (e == 0) ? ch[i].UpperAtBar(barProj) : ch[i].LowerAtBar(barProj);

         // Hrana musi lezet ve smeru obchodu, jinak neni cilem
         if(isBuy ? (vNow <= price) : (vNow >= price))
            continue;

         // Konzervativni odhad polohy hrany v case obchodu
         const double v = isBuy ? MathMin(vNow, vProj) : MathMax(vNow, vProj);
         const double d = isBuy ? (v - price) : (price - v);

         const double dist = MathMax(d, 0.0);

         if(best < 0.0 || dist < best)
           {
            best      = dist;
            edgePrice = v;   // vzdy poloha hrany, i kdyz uz cenu minula
           }
        }
     }

   return(best);
  }

//+------------------------------------------------------------------+
//| Vrati index kanalu, uvnitr ktereho lezi zadana cena na baru bar, |
//| nebo -1. Pri vice vyhovujicich kanalech vraci ten s nejlepsim    |
//| skore (pole je jiz serazene sestupne).                           |
//|  ch      - aktivni kanaly                                        |
//|  bar     - index baru, ke kteremu se testuje                     |
//|  price   - testovana cena                                        |
//|  tolFrac - tolerance testu jako zlomek sirky kanalu              |
//+------------------------------------------------------------------+
int PuntikyFindContainingChannel(SChannel &ch[], const double bar, const double price, const double tolFrac)
  {
   const int cnt = ArraySize(ch);
   for(int i = 0; i < cnt; i++)
      if(ch[i].ContainsAtBar(bar, price, tolFrac * ch[i].width))
         return(i);
   return(-1);
  }

#endif // __PUNTIKY_CHANNELS_MQH__
//+------------------------------------------------------------------+
