//+------------------------------------------------------------------+
//|                                                 PuntikyDraw.mqh  |
//|      Vykresleni grafickych objektu strategie.                    |
//|      Kresli se kanaly (HIGH a LOW usecky) a jejich opory         |
//|      A-B-C-D, urovne prurazu, reliefni primky, urovne            |
//|      planovaneho vstupu (vstup / SL / PT) a informacni panel.    |
//|      Vsechny objekty nesou prefix PUNTIKY_, aby sly uklidit bez  |
//|      dopadu na cizi grafiku v grafu.                             |
//+------------------------------------------------------------------+
#property copyright "Puntiky"

#ifndef __PUNTIKY_DRAW_MQH__
#define __PUNTIKY_DRAW_MQH__

#include <Puntiky\PuntikyTypes.mqh>

//--- Spolecny prefix vsech objektu strategie (kvuli uklidu grafu)
#define PUNTIKY_PREFIX "PUNTIKY_"

//+------------------------------------------------------------------+
//| Smaze objekty strategie z grafu.                                 |
//| Maze pouze objekty s vlastnim prefixem, cizi grafiku nechava.    |
//| Pouziva se ObjectsDeleteAll - jedno volani terminalu misto       |
//| rucniho pruchodu vsemi objekty grafu pro kazdy prefix zvlast.    |
//|  sub - upresneni prefixu (napr. "REL_"), prazdne = vse strategie |
//+------------------------------------------------------------------+
void PuntikyDeleteObjects(const string sub = "")
  {
   ObjectsDeleteAll(0, PUNTIKY_PREFIX + sub, -1, -1);
  }

//+------------------------------------------------------------------+
//| Smaze prebytecne objekty s cislovanym jmenem.                    |
//| Objekty se pri prekresleni aktualizuji na miste, takze se maze   |
//| jen to, co po zmenseni poctu utvaru zbylo navic - graf pak       |
//| pri kazdem prekresleni nebliká.                                  |
//|  sub  - upresneni prefixu (napr. "REL_")                         |
//|  from - prvni mazany index, to - prvni uz nemazany index         |
//+------------------------------------------------------------------+
void PuntikyDeleteIndexed(const string sub, const int from, const int to)
  {
   for(int i = from; i < to; i++)
      ObjectDelete(0, PUNTIKY_PREFIX + sub + IntegerToString(i));
  }

//+------------------------------------------------------------------+
//| Vytvori nebo aktualizuje usecku (trendline) mezi dvema body.     |
//|  name    - jmeno objektu (vcetne prefixu strategie)              |
//|  t1, p1  - cas a cena prvniho bodu                               |
//|  t2, p2  - cas a cena druheho bodu                               |
//|  clr     - barva usecky, width - tloustka v pixelech             |
//|  style   - styl cary (plna, carkovana, teckovana)                |
//|  ray     - prodlouzeni usecky doprava do budoucnosti             |
//|  tooltip - text bubliny po najeti mysi                           |
//+------------------------------------------------------------------+
void PuntikyTrendLine(const string name, const datetime t1, const double p1,
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
//| Vytvori nebo aktualizuje textovou znacku ukotvenou k cene a casu.|
//|  name     - jmeno objektu (vcetne prefixu strategie)             |
//|  t, p     - cas a cena ukotveni                                  |
//|  text     - vypisovany text                                      |
//|  clr      - barva textu, fontSize - velikost pisma               |
//|  anchor   - ke kteremu rohu textu se bod vztahuje                |
//|  font     - nazev pisma (vychozi tucny Arial kvuli citelnosti    |
//|             popisku opor pres svicky)                            |
//+------------------------------------------------------------------+
void PuntikyText(const string name, const datetime t, const double p, const string text,
              const color clr, const int fontSize, const ENUM_ANCHOR_POINT anchor,
              const string font = "Arial Bold")
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, p);

   ObjectMove(0, name, 0, t, p);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
//| Vytvori nebo aktualizuje textovy popisek panelu (pixelove        |
//| ukotveny k levemu hornimu rohu grafu).                           |
//|  name     - jmeno objektu (vcetne prefixu strategie)             |
//|  x, y     - odsazeni od rohu v pixelech                          |
//|  text     - vypisovany text                                      |
//|  clr      - barva textu, fontSize - velikost pisma               |
//|  font     - nazev pisma (panel pouziva neproporcionalni)         |
//+------------------------------------------------------------------+
void PuntikyLabel(const string name, const int x, const int y, const string text,
               const color clr, const int fontSize, const string font)
  {
   // Staticke vlastnosti staci nastavit pri vzniku objektu - panel se
   // prekresluje casto a kazdy ObjectSet* je volani do terminalu
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, font);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
     }

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
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
//|  name     - jmeno objektu (vcetne prefixu strategie)             |
//|  x, y     - odsazeni od leveho horniho rohu v pixelech           |
//|  w, h     - rozmery tlacitka v pixelech                          |
//|  text     - popisek tlacitka                                     |
//|  clr, bg  - barva textu a pozadi                                 |
//|  fontSize - velikost pisma, font - nazev pisma                   |
//|  tooltip  - text bubliny po najeti mysi                          |
//| Tlacitko se po kliknuti vraci do nestisknuteho stavu az v        |
//| obsluze udalosti - MT5 ho jinak necha "zamacknute".              |
//+------------------------------------------------------------------+
void PuntikyButton(const string name, const int x, const int y, const int w, const int h,
                const string text, const color clr, const color bg,
                const int fontSize, const string font, const string tooltip)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_STATE, false);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, font);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
     }

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
  }

//+------------------------------------------------------------------+
//| Vykresli jeden kanal: LOW usecku a HIGH usecku.                  |
//| Popisky opor se kresli zvlast pres PuntikyDrawLabels.            |
//| Usecka se kotvi bodem A a barem tEnd / barEnd. MT5 interpoluje   |
//| mezi kotvami v prostoru INDEXU baru a kanal je v indexech i      |
//| pocitany, takze nakreslena cara sedi na spoctenych hodnotach     |
//| presne - i pres vikendove mezery, kde se driv (sklon na sekundu) |
//| rozchazela o velkou cast sirky kanalu.                           |
//|  ch      - kresleny kanal                                        |
//|  idx     - poradi kanalu (0 = hlavni, vyssi = mene vyznamny)     |
//|  tEnd    - cas praveho konce usecek                              |
//|  barEnd  - index baru, ktery tomuto casu odpovida                |
//|  clrHigh - barva HIGH usecky, clrLow - barva LOW usecky          |
//+------------------------------------------------------------------+
void PuntikyDrawChannel(SChannel &ch, const int idx, const datetime tEnd, const double barEnd,
                     const color clrHigh, const color clrLow)
  {
   const string id  = PUNTIKY_PREFIX + "CH" + IntegerToString(idx) + "_";
   const string num = IntegerToString(idx + 1);   // kanaly cislujeme od 1
   // Hlavni kanal kreslime silneji nez vnorene / mene vyznamne
   const int    w   = (idx == 0) ? 2 : 1;
   const double barA = (double)ch.iA;

   //--- HIGH usecka (horni hrana kanalu)
   PuntikyTrendLine(id + "HIGH", ch.tA, ch.UpperAtBar(barA), tEnd, ch.UpperAtBar(barEnd),
                 clrHigh, w, STYLE_SOLID, true,
                 "Kanál " + num + " - HIGH úsečka");

   //--- LOW usecka (spodni hrana kanalu)
   PuntikyTrendLine(id + "LOW", ch.tA, ch.LowerAtBar(barA), tEnd, ch.LowerAtBar(barEnd),
                 clrLow, w, STYLE_SOLID, true,
                 "Kanál " + num + " - LOW úsečka");
  }

//+------------------------------------------------------------------+
//| Pripoji popisky opor jednoho kanalu do sberneho pole.            |
//| Body se popisuji pismenem a cislem kanalu (A1, B1, C1, D1 ...),  |
//| takze je na prvni pohled videt, co ke kteremu kanalu patri.      |
//| Body D, E, F ... jsou skutecne probehle dotyky hran za bodem C.  |
//|  ch  - kanal, jehoz opory se popisuji                            |
//|  idx - poradi kanalu (cislo v popisku je idx + 1)                |
//|  out - sberne pole popisku (in/out)                              |
//+------------------------------------------------------------------+
void PuntikyCollectChannelLabels(SChannel &ch, const int idx, SChannelLabel &out[])
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

   for(int k = 0; k < ch.extraCount && k < PUNTIKY_MAX_TOUCH_POINTS; k++)
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
//|  items    - sesbirane popisky vsech kanalu                       |
//|  clr      - barva textu, fontSize - velikost pisma               |
//|  mergeTol - tolerance slouceni v cene                            |
//| Vraci pocet skutecne vykreslenych (slouceni) popisku.            |
//+------------------------------------------------------------------+
int PuntikyDrawLabels(SChannelLabel &items[], const color clr, const int fontSize,
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
      PuntikyText(PUNTIKY_PREFIX + "PT" + IntegerToString(i), merged[i].time, merged[i].price,
               merged[i].text, clr, fontSize,
               merged[i].above ? ANCHOR_LOWER : ANCHOR_UPPER);

   return(m);
  }

//+------------------------------------------------------------------+
//| Vykresli urovne planovaneho vstupu (vstup, SL, PT).              |
//| Usecky vedou od casu tFrom doprava, aby byly citelne i pri zoomu.|
//|  tag       - oznaceni smeru v nazvu objektu ("BUY" / "SELL")     |
//|  plan      - navrh vstupu; neplatny navrh se jen smaze           |
//|  tFrom     - levy konec usecek, tTo - pravy konec                |
//|  clrEntry  - barva urovne vstupu                                 |
//|  clrSL     - barva stop lossu, clrTP - barva take profitu        |
//|  digits    - pocet desetinnych mist pro popisky                  |
//+------------------------------------------------------------------+
void PuntikyDrawEntryLevels(const string tag, SEntryPlan &plan, const datetime tFrom, const datetime tTo,
                         const color clrEntry, const color clrSL, const color clrTP, const int digits)
  {
   const string id = PUNTIKY_PREFIX + "ENT_" + tag + "_";
   if(!plan.valid)
     {
      PuntikyDeleteObjects("ENT_" + tag + "_");
      return;
     }

   const string dir = plan.isBuy ? "BUY" : "SELL";

   PuntikyTrendLine(id + "E", tFrom, plan.entry, tTo, plan.entry, clrEntry, 1, STYLE_DOT, false,
                 dir + " vstup " + DoubleToString(plan.entry, digits));
   PuntikyTrendLine(id + "SL", tFrom, plan.sl, tTo, plan.sl, clrSL, 1, STYLE_DOT, false,
                 dir + " SL " + DoubleToString(plan.sl, digits));
   PuntikyTrendLine(id + "TP", tFrom, plan.tp, tTo, plan.tp, clrTP, 1, STYLE_DOT, false,
                 dir + " PT " + DoubleToString(plan.tp, digits));

   // Popisky primo u urovni: PT na cilove, SL na stopove care
   PuntikyText(id + "TXT", tTo, plan.tp, "PT", clrTP, 8, ANCHOR_RIGHT_LOWER);
   PuntikyText(id + "TXT2", tTo, plan.sl, "SL", clrSL, 8, ANCHOR_RIGHT_LOWER);
  }

#endif // __PUNTIKY_DRAW_MQH__
//+------------------------------------------------------------------+
