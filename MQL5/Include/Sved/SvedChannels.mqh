//+------------------------------------------------------------------+
//|                                                SvedChannels.mqh  |
//|      Sestaveni, ohodnoceni a vyber hlavnich ABCD kanalu          |
//+------------------------------------------------------------------+
#property copyright "Sved"

#ifndef __SVED_CHANNELS_MQH__
#define __SVED_CHANNELS_MQH__

#include <Sved\SvedTypes.mqh>
#include <Sved\SvedSwings.mqh>

//--- Minimalni odstup dvou zapocitanych dotyku tehoz okraje (v barech)
#define SVED_TOUCH_GAP 3

//+------------------------------------------------------------------+
//| Test, zda kanal cenu obaluje a zda nebyl prorazen.               |
//| Obe hrany se posuzuji ruzne, protoze maji jiny vyznam:           |
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
//+------------------------------------------------------------------+
bool SvedChannelIsClean(const MqlRates &rates[], SChannel &ch,
                        const double pierceTolFrac, const double invalidTolFrac,
                        const int backCheckBars)
  {
   const int    n          = ArraySize(rates);
   const double tolBase    = pierceTolFrac  * ch.width;
   const double tolOutside = invalidTolFrac * ch.width;
   const int    from       = MathMax(ch.iA - MathMax(backCheckBars, 0), 0);

   for(int i = from; i < n; i++)
     {
      const datetime t = rates[i].time;

      // Pred bodem A kanal jeste "neexistuje" - kontroluje se tam
      // pouze zakladni usecka, protejsi hrana ne
      const bool beforeA = (i < ch.iA);

      // Protejsi hrana: mezi A a C prisne, za C volneji
      const double tolOpp = (i <= ch.iC) ? tolBase : tolOutside;

      if(ch.baseIsLow)
        {
         // Zakladni usecka je spodni hrana
         if(rates[i].low < ch.LowerAt(t) - tolBase)
            return(false);
         if(!beforeA && rates[i].high > ch.UpperAt(t) + tolOpp)
            return(false);
        }
      else
        {
         // Zakladni usecka je horni hrana
         if(rates[i].high > ch.UpperAt(t) + tolBase)
            return(false);
         if(!beforeA && rates[i].low < ch.LowerAt(t) - tolOpp)
            return(false);
        }
     }
   return(true);
  }

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
//+------------------------------------------------------------------+
bool SvedAnchorsAreExtremes(const MqlRates &rates[], SChannel &ch, const int window)
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
//| Ohodnoti kandidatni kanal na useku od bodu A do posledni svicky. |
//| Spocita pocet dotyku hran, podil svicek uzavrenych uvnitr kanalu |
//| a vysledne skore. Vraci false, pokud kanal neprosel filtry.      |
//|  rates - svicky kreslici TF (index 0 = nejstarsi)                |
//|  ch    - kanal (in/out), p - parametry filtrovani                |
//+------------------------------------------------------------------+
bool SvedEvaluateChannel(const MqlRates &rates[], SChannel &ch, const SChannelParams &p,
                         SChannelStats &st)
  {
   const int n = ArraySize(rates);
   if(n <= 0 || ch.width <= 0.0)
      return(false);

   //--- Tvrde geometricke filtry
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

   //--- Opory A a C musi byt vyraznymi extremy sveho okoli
   if(!SvedAnchorsAreExtremes(rates, ch, p.anchorWindow))
     {
      st.anchors++;
      return(false);
     }

   //--- Kanal musi cenu obalovat a nesmi byt prorazen - jinak neplati
   if(!SvedChannelIsClean(rates, ch, p.pierceTolFrac, p.invalidTolFrac, p.backCheckBars))
     {
      st.pierced++;
      return(false);
     }

   const double tol = p.touchTolFrac * ch.width;

   //--- Pruchod svickami od bodu A az po posledni uzavrenou svicku
   int inside      = 0;
   int total       = 0;
   int touches     = 0;
   int lastUpTouch = -1000;
   int lastLoTouch = -1000;

   for(int i = ch.iA; i < n; i++)
     {
      const datetime t  = rates[i].time;
      const double   up = ch.UpperAt(t);
      const double   lo = ch.LowerAt(t);

      total++;
      if(rates[i].close >= lo - tol && rates[i].close <= up + tol)
         inside++;

      // Dotyk horni hrany - high zasahl do tolerancniho pasma u hrany
      if(rates[i].high >= up - tol && rates[i].high <= up + tol * 2.0)
        {
         if(i - lastUpTouch >= SVED_TOUCH_GAP)
           {
            touches++;
            lastUpTouch = i;
           }
        }
      // Dotyk spodni hrany
      if(rates[i].low <= lo + tol && rates[i].low >= lo - tol * 2.0)
        {
         if(i - lastLoTouch >= SVED_TOUCH_GAP)
           {
            touches++;
            lastLoTouch = i;
           }
        }
     }

   ch.touches     = touches;
   ch.containment = (total > 0) ? (double)inside / (double)total : 0.0;

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

   //--- Volitelny pozadavek: aktualni cena musi byt stale uvnitr kanalu
   if(p.requireInside)
     {
      const datetime tLast = rates[n - 1].time;
      if(!ch.Contains(tLast, rates[n - 1].close, tol))
        {
         st.outside++;
         return(false);
        }
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
   ch.valid = true;
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
//+------------------------------------------------------------------+
void SvedCollectTouchPoints(const MqlRates &rates[], SChannel &ch, const double tolFrac)
  {
   ch.extraCount = 0;
   const int    n   = ArraySize(rates);
   const double tol = tolFrac * ch.width;

   // Po bodu C se ceka dotyk protejsi hrany (tam, kde lezi bod B)
   bool expectUpper = ch.baseIsLow;

   int i = ch.iC + 1;
   while(i < n && ch.extraCount < SVED_MAX_TOUCH_POINTS)
     {
      const datetime t = rates[i].time;
      bool touched = false;

      if(expectUpper)
         touched = (rates[i].high >= ch.UpperAt(t) - tol);
      else
         touched = (rates[i].low <= ch.LowerAt(t) + tol);

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
         const datetime tk = rates[k].time;
         const bool still = expectUpper ? (rates[k].high >= ch.UpperAt(tk) - tol)
                                        : (rates[k].low  <= ch.LowerAt(tk) + tol);
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
//| Hrany se porovnavaji ve DVOU casovych okamzicich - stoupajici a  |
//| klesajici kanal se muzou v jedinem bode zrovna protinat a pri    |
//| porovnani jednim okamzikem by se chybne slily do jednoho         |
//| (viz docs/iScreen ... 085407.png). Duplicita je jen tehdy,       |
//| kdyz obe hrany souhlasi v obou casech.                           |
//+------------------------------------------------------------------+
bool SvedChannelsSimilar(SChannel &a, SChannel &b, const datetime t1, const datetime t2,
                         const double frac)
  {
   const double w = MathMax(a.width, b.width);
   if(w <= 0.0)
      return(false);

   if(MathAbs(a.UpperAt(t1) - b.UpperAt(t1)) >= frac * w)
      return(false);
   if(MathAbs(a.LowerAt(t1) - b.LowerAt(t1)) >= frac * w)
      return(false);
   if(MathAbs(a.UpperAt(t2) - b.UpperAt(t2)) >= frac * w)
      return(false);
   if(MathAbs(a.LowerAt(t2) - b.LowerAt(t2)) >= frac * w)
      return(false);
   return(true);
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
//| cenu prorezavaji, zahodi az filtr v SvedEvaluateChannel.         |
//|  scaleIdx - poradi meritka, ve kterem kandidati vznikaji         |
//| Vraci celkovy pocet kandidatu v poli cand[].                     |
//+------------------------------------------------------------------+
int SvedCollectCandidates(const MqlRates &rates[], const SSwing &sw[], const SChannelParams &p,
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
         ch.valid     = false;
         ch.scaleIdx  = scaleIdx;
         ch.baseIsLow = !sw[i].isHigh;   // A,C jsou dna -> zakladni je LOW usecka
         ch.tA = sw[i].time; ch.pA = sw[i].price; ch.iA = sw[i].index;
         ch.tC = sw[j].time; ch.pC = sw[j].price; ch.iC = sw[j].index;
         ch.touches = 0; ch.containment = 0.0; ch.spanBars = 0; ch.ageBars = 0;
         ch.score = 0.0; ch.extraCount = 0;

         const double dt = (double)(ch.tC - ch.tA);
         if(dt <= 0.0)
            continue;

         // Zakladni usecka je dana body A a C, proto ji lze sestrojit
         // jeste pred vyberem bodu B
         ch.slope = (ch.pC - ch.pA) / dt;

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
            const double base = ch.BaseAt(sw[k].time);
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

         if(!SvedEvaluateChannel(rates, ch, p, st))
            continue;

         // Dalsi dotyky hran (D, E, F, ...) se dohledavaji az u kandidata,
         // ktery prosel filtry - zapisuji se jen skutecne probehle dotyky
         SvedCollectTouchPoints(rates, ch, p.touchTolFrac);

         ArrayResize(cand, nc + 1);
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
//| Vraci pocet vybranych kanalu ulozenych do out[].                 |
//+------------------------------------------------------------------+
int SvedSelectChannels(const MqlRates &rates[], SChannel &cand[], const SChannelParams &p, SChannel &out[])
  {
   ArrayResize(out, 0);
   const int n  = ArraySize(rates);
   const int nc = ArraySize(cand);
   if(n < 10 || nc == 0)
      return(0);

   //--- Serazeni podle skore sestupne (pole je male, staci prime razeni)
   for(int a = 0; a < nc - 1; a++)
      for(int b = a + 1; b < nc; b++)
         if(cand[b].score > cand[a].score)
           {
            SChannel tmp = cand[a];
            cand[a] = cand[b];
            cand[b] = tmp;
           }

   const datetime tLast = rates[n - 1].time;
   // Druhy porovnavaci okamzik pro deduplikaci - dost daleko, aby se
   // projevil rozdilny sklon kanalu
   const datetime tPast = rates[MathMax(n - 51, 0)].time;
   int taken = 0;
   ArrayResize(out, p.maxChannels);

   //--- 1. faze: z kazdeho meritka se vezme jeho nejlepsi kanal.
   //--- Hrube meritko dava velky kanal, jemne ten vnoreny - jinak by
   //--- vsechna mista obsadily varianty jedineho nejsilnejsiho kanalu
   //--- a "kanal v kanalu" by se nikdy nevykreslil.
   for(int s = 0; s < MathMax(p.scales, 1) && taken < p.maxChannels; s++)
     {
      for(int i = 0; i < nc; i++)
        {
         if(cand[i].scaleIdx != s)
            continue;

         bool dup = false;
         for(int j = 0; j < taken; j++)
            if(SvedChannelsSimilar(cand[i], out[j], tLast, tPast, p.dedupFrac))
              {
               dup = true;
               break;
              }
         if(dup)
            continue;

         out[taken++] = cand[i];
         break;   // z tohoto meritka staci nejlepsi kandidat
        }
     }

   //--- 2. faze: zbyla mista se doplni podle skore bez ohledu na meritko
   for(int i = 0; i < nc && taken < p.maxChannels; i++)
     {
      bool dup = false;
      for(int j = 0; j < taken; j++)
         if(SvedChannelsSimilar(cand[i], out[j], tLast, tPast, p.dedupFrac))
           {
            dup = true;
            break;
           }
      if(dup)
         continue;
      out[taken++] = cand[i];
     }

   ArrayResize(out, taken);

   //--- Vysledek seradime podle skore, aby index 0 byl hlavni kanal
   //--- (kresli se silnejsi carou nez ostatni)
   for(int a = 0; a < taken - 1; a++)
      for(int b = a + 1; b < taken; b++)
         if(out[b].score > out[a].score)
           {
            SChannel tmp = out[a];
            out[a] = out[b];
            out[b] = tmp;
           }

   return(taken);
  }

//+------------------------------------------------------------------+
//| Sestavi hlavni kanaly ve vice meritkach najednou.                |
//| Swingova kostra se hleda opakovane s ruzne sirokym pivot oknem   |
//| (baseDepth, 2x, 4x ...) - jemne okno najde male kanaly, hrube    |
//| okno velke. Prave diky tomu vznika i "kanal v kanalu".           |
//| Vysledne kandidaty ze vsech meritek hodnoti a vybira spolecne    |
//| SvedSelectChannels, takze se meritka mezi sebou poctive porovnaji|
//| a totozne nalezy se slouci.                                      |
//|  baseDepth - nejjemnejsi sirka pivot okna                        |
//|  scales    - pocet meritek (1 = jen zakladni okno)               |
//| Vraci pocet vybranych kanalu ulozenych do out[].                 |
//+------------------------------------------------------------------+
int SvedBuildChannels(const MqlRates &rates[], const SChannelParams &p,
                      const int baseDepth, const int scales, SChannel &out[],
                      SChannelStats &st)
  {
   st.Reset();

   SChannel cand[];
   ArrayResize(cand, 0);

   const int n = ArraySize(rates);
   for(int s = 0; s < MathMax(scales, 1); s++)
     {
      const int depth = baseDepth * (1 << s);
      if(depth * 2 + 3 >= n)
         break;   // okno uz je sirsi nez dostupna historie

      SSwing sw[];
      SvedDetectSwings(rates, depth, sw);
      SvedCollectCandidates(rates, sw, p, s, cand, st);
     }

   st.selected = SvedSelectChannels(rates, cand, p, out);
   return(st.selected);
  }

//+------------------------------------------------------------------+
//| Najde nejblizsi hranu kanalu ve smeru obchodu a vrati vzdalenost |
//| od zadane ceny k teto hrane.                                     |
//| Prochazi obe hrany vsech aktivnich kanalu (tedy i vnorenych),    |
//| takze "dalsi hrana" muze patrit i mensimu kanalu uvnitr vetsiho. |
//| Kvuli sklonu hran se bere konzervativnejsi hodnota z casu vstupu |
//| a z casu projekce (tProj) - pro BUY nizsi, pro SELL vyssi.       |
//|  price - vychozi cena (planovany vstup), isBuy - smer            |
//|  edgePrice - out: cena nalezene hrany                            |
//| Vraci vzdalenost v cene, nebo -1 pokud zadna hrana ve smeru      |
//| obchodu neexistuje.                                              |
//+------------------------------------------------------------------+
double SvedDistanceToNextEdge(SChannel &ch[], const datetime t, const datetime tProj,
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
         const double vNow  = (e == 0) ? ch[i].UpperAt(t)     : ch[i].LowerAt(t);
         const double vProj = (e == 0) ? ch[i].UpperAt(tProj) : ch[i].LowerAt(tProj);

         if(isBuy)
           {
            if(vNow <= price)
               continue;                            // hrana neni nad vstupem
            const double v = MathMin(vNow, vProj);  // konzervativni odhad
            const double d = MathMax(v - price, 0.0);
            if(best < 0.0 || d < best)
              {
               best      = d;
               edgePrice = v;
              }
           }
         else
           {
            if(vNow >= price)
               continue;                            // hrana neni pod vstupem
            const double v = MathMax(vNow, vProj);
            const double d = MathMax(price - v, 0.0);
            if(best < 0.0 || d < best)
              {
               best      = d;
               edgePrice = v;
              }
           }
        }
     }

   return(best);
  }

//+------------------------------------------------------------------+
//| Vrati index kanalu, uvnitr ktereho lezi zadana cena v case t,    |
//| nebo -1. Pri vice vyhovujicich kanalech vraci ten s nejlepsim    |
//| skore (pole je jiz serazene sestupne).                           |
//+------------------------------------------------------------------+
int SvedFindContainingChannel(SChannel &ch[], const datetime t, const double price, const double tolFrac)
  {
   const int cnt = ArraySize(ch);
   for(int i = 0; i < cnt; i++)
      if(ch[i].Contains(t, price, tolFrac * ch[i].width))
         return(i);
   return(-1);
  }

#endif // __SVED_CHANNELS_MQH__
//+------------------------------------------------------------------+
