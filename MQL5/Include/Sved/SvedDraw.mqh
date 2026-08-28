//+------------------------------------------------------------------+
//|                                                    SvedDraw.mqh  |
//|      Vykresleni kanalu a informaci o vstupu do grafu             |
//|      Do grafu se kresli VYHRADNE kanaly (HIGH a LOW usecky),     |
//|      jejich opory A-B-C-D a informacni panel o vstupu.           |
//+------------------------------------------------------------------+
#property copyright "Sved"

#ifndef __SVED_DRAW_MQH__
#define __SVED_DRAW_MQH__

#include <Sved\SvedTypes.mqh>

//--- Spolecny prefix vsech objektu strategie (kvuli uklidu grafu)
#define SVED_PREFIX "SVED_"

//+------------------------------------------------------------------+
//| Smaze vsechny objekty strategie z grafu.                         |
//| Maze pouze objekty s vlastnim prefixem, cizi grafiku nechava.    |
//+------------------------------------------------------------------+
void SvedDeleteObjects(const string sub = "")
  {
   const string pref = SVED_PREFIX + sub;
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
     {
      const string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, pref, 0) == 0)
         ObjectDelete(0, name);
     }
  }

//+------------------------------------------------------------------+
//| Vytvori nebo aktualizuje usecku (trendline) mezi dvema body.     |
//|  ray - prodlouzeni usecky doprava do budoucnosti                 |
//+------------------------------------------------------------------+
void SvedTrendLine(const string name, const datetime t1, const double p1,
                   const datetime t2, const double p2,
                   const color clr, const int width, const ENUM_LINE_STYLE style,
                   const bool ray, const string tooltip)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);

   ObjectMove(0, name, 0, t1, p1);
   ObjectMove(0, name, 1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, ray);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
  }

//+------------------------------------------------------------------+
//| Vytvori nebo aktualizuje textovou znacku ukotvenou k cene a casu |
//+------------------------------------------------------------------+
void SvedText(const string name, const datetime t, const double p, const string text,
              const color clr, const int fontSize, const ENUM_ANCHOR_POINT anchor)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, p);

   ObjectMove(0, name, 0, t, p);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
//| Vytvori nebo aktualizuje textovy popisek panelu (pixelove ukotveny)|
//+------------------------------------------------------------------+
void SvedLabel(const string name, const int x, const int y, const string text,
               const color clr, const int fontSize, const string font)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

//+------------------------------------------------------------------+
//| Polozka popisku opory kanalu.                                    |
//| Popisky se nejprve sesbiraji ze vsech kanalu a teprve pak kresli,|
//| aby se daly slucovat - jeden bar totiz muze byt oporou vice      |
//| kanalu a texty by se jinak prekryly.                             |
//+------------------------------------------------------------------+
struct SChannelLabel
  {
   datetime          time;
   double            price;
   string            text;
   bool              above;   // text se kresli nad bodem
  };

//+------------------------------------------------------------------+
//| Vytvori nebo aktualizuje tlacitko ukotvene k rohu grafu.         |
//|  x, y     - odsazeni od leveho horniho rohu v pixelech           |
//|  w, h     - rozmery tlacitka v pixelech                          |
//|  text     - popisek tlacitka                                     |
//|  clr, bg  - barva textu a pozadi                                 |
//| Tlacitko se po kliknuti vraci do nestisknuteho stavu az v        |
//| obsluze udalosti - MT5 ho jinak necha "zamacknute".              |
//+------------------------------------------------------------------+
void SvedButton(const string name, const int x, const int y, const int w, const int h,
                const string text, const color clr, const color bg,
                const int fontSize, const string font, const string tooltip)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_STATE, false);
     }

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
  }

//+------------------------------------------------------------------+
//| Vykresli jeden kanal: LOW usecku a HIGH usecku.                  |
//| Popisky opor se kresli zvlast pres SvedDrawLabels.               |
//|  idx  - poradi kanalu (0 = hlavni, vyssi = mene vyznamny)        |
//|  tEnd - cas praveho konce usecek                                 |
//+------------------------------------------------------------------+
void SvedDrawChannel(SChannel &ch, const int idx, const datetime tEnd,
                     const color clrHigh, const color clrLow)
  {
   const string id  = SVED_PREFIX + "CH" + IntegerToString(idx) + "_";
   const string num = IntegerToString(idx + 1);   // kanaly cislujeme od 1
   // Hlavni kanal kreslime silneji nez vnorene / mene vyznamne
   const int    w   = (idx == 0) ? 2 : 1;

   //--- HIGH usecka (horni hrana kanalu)
   SvedTrendLine(id + "HIGH", ch.tA, ch.UpperAt(ch.tA), tEnd, ch.UpperAt(tEnd),
                 clrHigh, w, STYLE_SOLID, true,
                 "Kanál " + num + " - HIGH úsečka");

   //--- LOW usecka (spodni hrana kanalu)
   SvedTrendLine(id + "LOW", ch.tA, ch.LowerAt(ch.tA), tEnd, ch.LowerAt(tEnd),
                 clrLow, w, STYLE_SOLID, true,
                 "Kanál " + num + " - LOW úsečka");
  }

//+------------------------------------------------------------------+
//| Pripoji popisky opor jednoho kanalu do sberneho pole.            |
//| Body se popisuji pismenem a cislem kanalu (A1, B1, C1, D1 ...),  |
//| takze je na prvni pohled videt, co ke kteremu kanalu patri.      |
//| Body D, E, F ... jsou skutecne probehle dotyky hran za bodem C.  |
//+------------------------------------------------------------------+
void SvedCollectChannelLabels(SChannel &ch, const int idx, SChannelLabel &out[])
  {
   const string num = IntegerToString(idx + 1);
   int n = ArraySize(out);
   ArrayResize(out, n + 3 + ch.extraCount);

   // A a C lezi na zakladni usecce, B na protejsi - popisek se vzdy
   // umistuje vne kanalu, aby neprekryval svicky
   const bool aboveBase = !ch.baseIsLow;

   out[n].time = ch.tA; out[n].price = ch.pA; out[n].text = "A" + num; out[n].above = aboveBase;  n++;
   out[n].time = ch.tB; out[n].price = ch.pB; out[n].text = "B" + num; out[n].above = !aboveBase; n++;
   out[n].time = ch.tC; out[n].price = ch.pC; out[n].text = "C" + num; out[n].above = aboveBase;  n++;

   for(int k = 0; k < ch.extraCount && k < SVED_MAX_TOUCH_POINTS; k++)
     {
      out[n].time  = ch.tExtra[k];
      out[n].price = ch.pExtra[k];
      out[n].text  = CharToString((uchar)('D' + k)) + num;
      out[n].above = ch.extraUpper[k];
      n++;
     }

   ArrayResize(out, n);
  }

//+------------------------------------------------------------------+
//| Vykresli sesbirane popisky opor.                                 |
//| Popisky, ktere by padly na stejne misto (stejna svicka, stejna   |
//| strana a cena blizsi nez mergeTol), se slouci do jednoho textu - |
//| napr. "E1 E3". Jinak by se pri sdilene opore prepisovaly.        |
//+------------------------------------------------------------------+
void SvedDrawLabels(SChannelLabel &items[], const color clr, const int fontSize,
                    const double mergeTol)
  {
   const int cnt = ArraySize(items);

   SChannelLabel merged[];
   ArrayResize(merged, 0);
   int m = 0;

   for(int i = 0; i < cnt; i++)
     {
      int hit = -1;
      for(int j = 0; j < m; j++)
        {
         if(merged[j].time != items[i].time || merged[j].above != items[i].above)
            continue;
         if(MathAbs(merged[j].price - items[i].price) <= mergeTol)
           {
            hit = j;
            break;
           }
        }

      if(hit >= 0)
        {
         merged[hit].text = merged[hit].text + " " + items[i].text;
         // Slouceny popisek se posadi na vyraznejsi z obou cen
         merged[hit].price = merged[hit].above
                             ? MathMax(merged[hit].price, items[i].price)
                             : MathMin(merged[hit].price, items[i].price);
        }
      else
        {
         ArrayResize(merged, m + 1);
         merged[m] = items[i];
         m++;
        }
     }

   for(int i = 0; i < m; i++)
      SvedText(SVED_PREFIX + "PT" + IntegerToString(i), merged[i].time, merged[i].price,
               merged[i].text, clr, fontSize,
               merged[i].above ? ANCHOR_LOWER : ANCHOR_UPPER);
  }

//+------------------------------------------------------------------+
//| Vykresli urovne planovaneho vstupu (spoust, vstup, SL, PT).      |
//| Usecky vedou od casu ta doprava, aby byly citelne i pri zoomu.   |
//+------------------------------------------------------------------+
void SvedDrawEntryLevels(const string tag, SEntryPlan &plan, const datetime tFrom, const datetime tTo,
                         const color clrEntry, const color clrSL, const color clrTP, const int digits)
  {
   const string id = SVED_PREFIX + "ENT_" + tag + "_";
   if(!plan.valid)
     {
      SvedDeleteObjects("ENT_" + tag + "_");
      return;
     }

   const string dir = plan.isBuy ? "BUY" : "SELL";

   SvedTrendLine(id + "E", tFrom, plan.entry, tTo, plan.entry, clrEntry, 1, STYLE_DOT, false,
                 dir + " vstup " + DoubleToString(plan.entry, digits));
   SvedTrendLine(id + "SL", tFrom, plan.sl, tTo, plan.sl, clrSL, 1, STYLE_DOT, false,
                 dir + " SL " + DoubleToString(plan.sl, digits));
   SvedTrendLine(id + "TP", tFrom, plan.tp, tTo, plan.tp, clrTP, 1, STYLE_DOT, false,
                 dir + " PT " + DoubleToString(plan.tp, digits));

   // Popisky primo u urovni: PT na cilove, SL na stopove care
   SvedText(id + "TXT", tTo, plan.tp, "PT", clrTP, 8, ANCHOR_RIGHT_LOWER);
   SvedText(id + "TXT2", tTo, plan.sl, "SL", clrSL, 8, ANCHOR_RIGHT_LOWER);
  }

#endif // __SVED_DRAW_MQH__
//+------------------------------------------------------------------+
