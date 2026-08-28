//+------------------------------------------------------------------+
//|                                                  SvedSwings.mqh  |
//|      Detekce swingovych bodu (zig-zag) z pole svicek             |
//+------------------------------------------------------------------+
#property copyright "Sved"

#ifndef __SVED_SWINGS_MQH__
#define __SVED_SWINGS_MQH__

#include <Sved\SvedTypes.mqh>

//+------------------------------------------------------------------+
//| Test lokalniho vrcholu: high[i] je nejvyssi v okne +-depth.      |
//|  rates - pole svicek (index 0 = nejstarsi)                       |
//|  i     - testovany index, depth - polovicni sirka okna           |
//+------------------------------------------------------------------+
bool SvedIsPivotHigh(const MqlRates &rates[], const int i, const int depth)
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
//+------------------------------------------------------------------+
bool SvedIsPivotLow(const MqlRates &rates[], const int i, const int depth)
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
//| Detekce swingu se stridanim vrchol / dno.                        |
//| Prochazi svicky od nejstarsi po nejnovejsi, sbira pivoty a       |
//| vynucuje stridani typu - dva stejne typy za sebou se slouci      |
//| do toho extremnejsiho. Vysledkem je zig-zag kostra trhu.         |
//|  rates - svicky (index 0 = nejstarsi), depth - sirka pivot okna  |
//|  out   - vystupni pole swingu serazene chronologicky             |
//| Vraci pocet nalezenych swingu.                                   |
//+------------------------------------------------------------------+
int SvedDetectSwings(const MqlRates &rates[], const int depth, SSwing &out[])
  {
   ArrayResize(out, 0);
   const int n = ArraySize(rates);
   if(n < depth * 2 + 3)
      return(0);

   int count = 0;
   ArrayResize(out, n / 2 + 4);

   for(int i = depth; i < n - depth; i++)
     {
      const bool isHigh = SvedIsPivotHigh(rates, i, depth);
      const bool isLow  = SvedIsPivotLow(rates, i, depth);
      if(!isHigh && !isLow)
         continue;

      // Vnitrni svicka muze byt pivotem obou typu (outside bar) -
      // rozhodne se podle toho, jaky typ jako posledni nechybi
      bool takeHigh = isHigh;
      if(isHigh && isLow)
         takeHigh = (count > 0 && out[count - 1].isHigh) ? false : true;

      SSwing s;
      s.time   = rates[i].time;
      s.index  = i;
      s.isHigh = takeHigh;
      s.price  = takeHigh ? rates[i].high : rates[i].low;

      if(count > 0 && out[count - 1].isHigh == s.isHigh)
        {
         // Stejny typ dvakrat po sobe - ponechame extremnejsi z nich
         const bool replace = s.isHigh ? (s.price > out[count - 1].price)
                                       : (s.price < out[count - 1].price);
         if(replace)
            out[count - 1] = s;
         continue;
        }

      if(count >= ArraySize(out))
         ArrayResize(out, count + 16);
      out[count++] = s;
     }

   ArrayResize(out, count);
   return(count);
  }

#endif // __SVED_SWINGS_MQH__
//+------------------------------------------------------------------+
