//+------------------------------------------------------------------+
//|                                               PuntikySwings.mqh  |
//|      Detekce swingovych bodu (zig-zag) z pole svicek             |
//+------------------------------------------------------------------+
#property copyright "Puntiky"

#ifndef __PUNTIKY_SWINGS_MQH__
#define __PUNTIKY_SWINGS_MQH__

#include <Puntiky\PuntikyTypes.mqh>

//+------------------------------------------------------------------+
//| Sirka pivot okna pro dane meritko detekce.                       |
//| Kanaly i reliefni primky se hledaji ve vice meritkach - jemne    |
//| okno najde male utvary, hrube ty velke. Vypocet je spolecny,     |
//| aby se obe mista nerozesla.                                      |
//|  baseDepth - nejjemnejsi sirka okna (meritko 0)                  |
//|  scaleIdx  - poradi meritka (0 = zakladni, dal 2x, 4x, 8x ...)   |
//+------------------------------------------------------------------+
int PuntikyScaleDepth(const int baseDepth, const int scaleIdx)
  {
   return(MathMax(baseDepth, 1) * (1 << scaleIdx));
  }

//+------------------------------------------------------------------+
//| Vejde se pivot okno dane sirky do historie n baru?               |
//| Pivot potrebuje depth baru vlevo i vpravo, jinak nema co         |
//| potvrdit a detekce v tomto meritku nema smysl.                   |
//+------------------------------------------------------------------+
bool PuntikyScaleFits(const int depth, const int n)
  {
   return(depth * 2 + 3 < n);
  }

//+------------------------------------------------------------------+
//| Test lokalniho vrcholu: high[i] je nejvyssi v okne +-depth.      |
//|  rates - pole svicek (index 0 = nejstarsi)                       |
//|  i     - testovany index, depth - polovicni sirka okna           |
//+------------------------------------------------------------------+
bool PuntikyIsPivotHigh(const MqlRates &rates[], const int i, const int depth)
  {
   const int n = ArraySize(rates);
   if(i - depth < 0 || i + depth >= n)
      return(false);

   const double h = rates[i].high;
   for(int k = 1; k <= depth; k++)
     {
      // Leve rameno musi byt striktne nizsi, prave smi byt rovne
      // (potlaci duplicitni pivoty na plochych vrcholech)
      if(rates[i - k].high >= h)
         return(false);
      if(rates[i + k].high > h)
         return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Test lokalniho dna: low[i] je nejnizsi v okne +-depth.           |
//|  rates - pole svicek (index 0 = nejstarsi)                       |
//|  i     - testovany index, depth - polovicni sirka okna           |
//+------------------------------------------------------------------+
bool PuntikyIsPivotLow(const MqlRates &rates[], const int i, const int depth)
  {
   const int n = ArraySize(rates);
   if(i - depth < 0 || i + depth >= n)
      return(false);

   const double l = rates[i].low;
   for(int k = 1; k <= depth; k++)
     {
      if(rates[i - k].low <= l)
         return(false);
      if(rates[i + k].low < l)
         return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Prida jeden extrem do kostry swingu.                             |
//| Kdyz je posledni ulozeny swing tehoz typu, ponecha se ten        |
//| extremnejsi z obou (klasicke slouceni zig-zagu), jinak se novy   |
//| swing pripoji na konec.                                          |
//|  rates - pole svicek (index 0 = nejstarsi)                       |
//|  i     - index baru s extremem                                   |
//|  isHigh- typ ukladaneho extremu (true = vrchol)                  |
//|  out   - vystupni pole swingu                                    |
//|  count - pocet dosud ulozenych swingu (in/out)                   |
//+------------------------------------------------------------------+
void PuntikyPushSwing(const MqlRates &rates[], const int i, const bool isHigh,
                   SSwing &out[], int &count)
  {
   SSwing s;
   s.time   = rates[i].time;
   s.index  = i;
   s.isHigh = isHigh;
   s.price  = isHigh ? rates[i].high : rates[i].low;

   if(count > 0 && out[count - 1].isHigh == s.isHigh)
     {
      // Stejny typ dvakrat po sobe - ponechame extremnejsi z nich
      const bool replace = s.isHigh ? (s.price > out[count - 1].price)
                                    : (s.price < out[count - 1].price);
      if(replace)
         out[count - 1] = s;
      return;
     }

   // Rezerva pri zvetsovani setri realokace u dlouhych historii
   if(count >= ArraySize(out))
      ArrayResize(out, count + 64, 256);
   out[count++] = s;
  }

//+------------------------------------------------------------------+
//| Detekce swingu se stridanim vrchol / dno.                        |
//| Prochazi svicky od nejstarsi po nejnovejsi, sbira pivoty a       |
//| vynucuje stridani typu - dva stejne typy za sebou se slouci      |
//| do toho extremnejsiho. Vysledkem je zig-zag kostra trhu.         |
//|  rates - svicky (index 0 = nejstarsi), depth - sirka pivot okna  |
//|  out   - vystupni pole swingu serazene chronologicky             |
//| Vraci pocet nalezenych swingu.                                   |
//+------------------------------------------------------------------+
int PuntikyDetectSwings(const MqlRates &rates[], const int depth, SSwing &out[])
  {
   ArrayResize(out, 0);
   const int n = ArraySize(rates);
   if(n < depth * 2 + 3)
      return(0);

   int count = 0;
   ArrayResize(out, n / 2 + 4);

   for(int i = depth; i < n - depth; i++)
     {
      const bool isHigh = PuntikyIsPivotHigh(rates, i, depth);
      const bool isLow  = PuntikyIsPivotLow(rates, i, depth);
      if(!isHigh && !isLow)
         continue;

      // Vnitrni svicka muze byt pivotem obou typu naraz (outside bar).
      // Ulozi se OBA extremy - kdyby se zapsal jen jeden, skutecny
      // vrchol (nebo dno) by z kostry zmizel a uroven prurazu by pak
      // sedla na nizsi swing, ktery uz cena davno prosla.
      // Poradi urcuje stridani: nejdriv typ, ktery po poslednim
      // ulozenem swingu ve stridani chybi.
      bool firstHigh = isHigh;
      if(isHigh && isLow)
         firstHigh = !(count > 0 && out[count - 1].isHigh);

      PuntikyPushSwing(rates, i, firstHigh, out, count);
      if(isHigh && isLow)
         PuntikyPushSwing(rates, i, !firstHigh, out, count);
     }

   ArrayResize(out, count);
   return(count);
  }

#endif // __PUNTIKY_SWINGS_MQH__
//+------------------------------------------------------------------+
