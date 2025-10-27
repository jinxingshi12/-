#property copyright "SMC conversion"
#property link      ""
#property version   "1.10"
#property indicator_chart_window
#property indicator_buffers 16
#property indicator_plots   16

#property indicator_type1   DRAW_NONE
#property indicator_type2   DRAW_NONE
#property indicator_type3   DRAW_NONE
#property indicator_type4   DRAW_NONE
#property indicator_type5   DRAW_NONE
#property indicator_type6   DRAW_NONE
#property indicator_type7   DRAW_NONE
#property indicator_type8   DRAW_NONE
#property indicator_type9   DRAW_NONE
#property indicator_type10  DRAW_NONE
#property indicator_type11  DRAW_NONE
#property indicator_type12  DRAW_NONE
#property indicator_type13  DRAW_NONE
#property indicator_type14  DRAW_NONE
#property indicator_type15  DRAW_NONE
#property indicator_type16  DRAW_NONE

enum BufferIndex
  {
   BUFFER_BULLISH_BOS = 0,
   BUFFER_BEARISH_BOS = 1,
   BUFFER_BULLISH_CHOCH = 2,
   BUFFER_BEARISH_CHOCH = 3,
   BUFFER_BULLISH_OB_HIGH = 4,
   BUFFER_BULLISH_OB_LOW = 5,
   BUFFER_BEARISH_OB_HIGH = 6,
   BUFFER_BEARISH_OB_LOW = 7,
   BUFFER_BULLISH_FVG_HIGH = 8,
   BUFFER_BULLISH_FVG_LOW = 9,
   BUFFER_BEARISH_FVG_HIGH = 10,
   BUFFER_BEARISH_FVG_LOW = 11,
   BUFFER_EQ_HIGHS = 12,
   BUFFER_EQ_LOWS = 13,
   BUFFER_LIQUIDITY_GRAB_HIGH = 14,
   BUFFER_LIQUIDITY_GRAB_LOW = 15
  };

struct SwingPoint
  {
   int       index;
   double    price;
   datetime  time;
  };

struct Zone
  {
   bool      bullish;
   double    top;
   double    bottom;
   datetime  startTime;
   bool      mitigated;
   int       id;
  };

//--- inputs
input int      InpSwingLength        = 3;
input int      InpMinEQTicks         = 3;
input bool     InpShowStructure      = true;
input bool     InpShowChoCh          = true;
input bool     InpShowSwingLabels    = false;
input bool     InpShowEqualLevels    = true;
input bool     InpShowOrderBlocks    = true;
input bool     InpShowFVG            = true;
input int      InpMaxZones           = 3;
input int      InpExtendRightBars    = 100;
input color    InpBullStructureColor = clrLimeGreen;
input color    InpBearStructureColor = clrTomato;
input color    InpEqualHighColor     = clrTurquoise;
input color    InpEqualLowColor      = clrLightCoral;
input color    InpBearZoneColor      = clrLightPink;
input color    InpFvgColor           = clrGainsboro;
input int      InpZoneOpacityActive  = 60;
input int      InpZoneOpacityMitigated = 25;

//--- buffers
 double gBullishBosBuffer[];
 double gBearishBosBuffer[];
 double gBullishChochBuffer[];
 double gBearishChochBuffer[];
 double gBullishOBHighBuffer[];
 double gBullishOBLowBuffer[];
 double gBearishOBHighBuffer[];
 double gBearishOBLowBuffer[];
 double gBullishFvgHighBuffer[];
 double gBullishFvgLowBuffer[];
 double gBearishFvgHighBuffer[];
 double gBearishFvgLowBuffer[];
 double gEqualHighBuffer[];
 double gEqualLowBuffer[];
 double gLgHighBuffer[];
 double gLgLowBuffer[];

//--- runtime state
int        gLastProcessedIndex = -1;
int        gTrendDirection     = 0;
SwingPoint gLastSwingHigh;
SwingPoint gPrevSwingHigh;
SwingPoint gLastSwingLow;
SwingPoint gPrevSwingLow;
int        gLastBrokenHighSource = -1;
int        gLastBrokenLowSource  = -1;
double     gLastEqualHighPrice  = 0.0;
int        gLastEqualHighIndex  = -1;
double     gLastEqualLowPrice   = 0.0;
int        gLastEqualLowIndex   = -1;
int        gStructureLabelId    = 0;
int        gEqualLabelId        = 0;
int        gSwingLabelId        = 0;
int        gNextZoneId          = 0;

Zone       gObZones[];
Zone       gFvgZones[];

//--- helpers -----------------------------------------------------------------
void ResetSwingPoint(SwingPoint &p)
  {
   p.index = -1;
   p.price = 0.0;
   p.time  = 0;
  }

void ResetState()
  {
   gLastProcessedIndex = -1;
   gTrendDirection     = 0;
   gLastEqualHighPrice = 0.0;
   gLastEqualLowPrice  = 0.0;
   gLastEqualHighIndex = -1;
   gLastEqualLowIndex  = -1;
   gStructureLabelId   = 0;
   gEqualLabelId       = 0;
   gSwingLabelId       = 0;
   gNextZoneId         = 0;
   gLastBrokenHighSource = -1;
   gLastBrokenLowSource  = -1;
   ResetSwingPoint(gLastSwingHigh);
   ResetSwingPoint(gPrevSwingHigh);
   ResetSwingPoint(gLastSwingLow);
   ResetSwingPoint(gPrevSwingLow);
   ArrayResize(gObZones,0);
   ArrayResize(gFvgZones,0);
  }

string BuildName(const string prefix,const int id)
  {
   return prefix+"_"+IntegerToString(id);
  }

int SeriesIndex(const int rates_total,const int chronoIndex)
  {
   return rates_total-1-chronoIndex;
  }

void SetBufferValue(double &buffer[],const int rates_total,const int chronoIndex,const double value)
  {
   if(chronoIndex<0 || chronoIndex>=rates_total)
      return;
   int shift = SeriesIndex(rates_total,chronoIndex);
   int bufferSize = ArraySize(buffer);
   if(shift>=0 && shift<bufferSize)
      buffer[shift] = value;
  }

void ClearBuffersAtIndex(const int rates_total,const int chronoIndex)
  {
   SetBufferValue(gBullishBosBuffer,rates_total,chronoIndex,EMPTY_VALUE);
   SetBufferValue(gBearishBosBuffer,rates_total,chronoIndex,EMPTY_VALUE);
   SetBufferValue(gBullishChochBuffer,rates_total,chronoIndex,EMPTY_VALUE);
   SetBufferValue(gBearishChochBuffer,rates_total,chronoIndex,EMPTY_VALUE);
   SetBufferValue(gBullishOBHighBuffer,rates_total,chronoIndex,EMPTY_VALUE);
   SetBufferValue(gBullishOBLowBuffer,rates_total,chronoIndex,EMPTY_VALUE);
   SetBufferValue(gBearishOBHighBuffer,rates_total,chronoIndex,EMPTY_VALUE);
   SetBufferValue(gBearishOBLowBuffer,rates_total,chronoIndex,EMPTY_VALUE);
   SetBufferValue(gBullishFvgHighBuffer,rates_total,chronoIndex,EMPTY_VALUE);
   SetBufferValue(gBullishFvgLowBuffer,rates_total,chronoIndex,EMPTY_VALUE);
   SetBufferValue(gBearishFvgHighBuffer,rates_total,chronoIndex,EMPTY_VALUE);
   SetBufferValue(gBearishFvgLowBuffer,rates_total,chronoIndex,EMPTY_VALUE);
   SetBufferValue(gEqualHighBuffer,rates_total,chronoIndex,EMPTY_VALUE);
   SetBufferValue(gEqualLowBuffer,rates_total,chronoIndex,EMPTY_VALUE);
   SetBufferValue(gLgHighBuffer,rates_total,chronoIndex,EMPTY_VALUE);
   SetBufferValue(gLgLowBuffer,rates_total,chronoIndex,EMPTY_VALUE);
  }

void DeleteObjectByPrefix(const string prefix)
  {
   for(int i=ObjectsTotal(0,-1,-1)-1; i>=0; --i)
     {
      string name = ObjectName(0,i);
      if(StringFind(name,prefix)==0)
         ObjectDelete(0,name);
     }
  }

void DrawTextLabel(const string prefix,const int id,const datetime t,const double price,const color clr,const string text,const int anchor)
  {
   string name = BuildName(prefix,id);
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_TEXT,0,t,price);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,anchor);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
  }

void DrawDottedLine(const string prefix,const int id,const datetime fromTime,const datetime toTime,const double price,const color clr)
  {
   string name = BuildName(prefix,id);
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_TREND,0,fromTime,price,toTime,price);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,fromTime);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,toTime);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,price);
   ObjectSetDouble(0,name,OBJPROP_PRICE,1,price);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,true);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

void RenderZone(const Zone &zone,const string prefix,const color baseColor,const int opacity,const datetime rightTime)
  {
   string rectName = BuildName(prefix+"RECT",zone.id);
   string labelName = BuildName(prefix+"LBL",zone.id);
   if(ObjectFind(0,rectName)<0)
      ObjectCreate(0,rectName,OBJ_RECTANGLE,0,zone.startTime,zone.top,rightTime,zone.bottom);
   ObjectSetInteger(0,rectName,OBJPROP_TIME,0,zone.startTime);
   ObjectSetInteger(0,rectName,OBJPROP_TIME,1,rightTime);
   ObjectSetDouble(0,rectName,OBJPROP_PRICE,0,zone.top);
   ObjectSetDouble(0,rectName,OBJPROP_PRICE,1,zone.bottom);
   ObjectSetInteger(0,rectName,OBJPROP_FILL,true);
   ObjectSetInteger(0,rectName,OBJPROP_BACK,true);
   ObjectSetInteger(0,rectName,OBJPROP_COLOR,ColorToARGB(baseColor,opacity));
   ObjectSetInteger(0,rectName,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,rectName,OBJPROP_HIDDEN,true);

   double mid = 0.5*(zone.top+zone.bottom);
   if(ObjectFind(0,labelName)<0)
      ObjectCreate(0,labelName,OBJ_TEXT,0,rightTime,mid);
   ObjectSetInteger(0,labelName,OBJPROP_TIME,0,rightTime);
   ObjectSetDouble(0,labelName,OBJPROP_PRICE,0,mid);
   ObjectSetInteger(0,labelName,OBJPROP_COLOR,baseColor);
   ObjectSetInteger(0,labelName,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,labelName,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,labelName,OBJPROP_HIDDEN,true);
   string text = prefix=="OB_" ? (zone.bullish?"Bull OB":"Bear OB") : (zone.bullish?"Bull FVG":"Bear FVG");
   if(zone.mitigated && prefix=="OB_")
      text += " \xE2\x9C\x93";
   ObjectSetString(0,labelName,OBJPROP_TEXT,text);
  }

void DeleteZoneObjects(const string prefix,const int id)
  {
   ObjectDelete(0,BuildName(prefix+"RECT",id));
   ObjectDelete(0,BuildName(prefix+"LBL",id));
  }

void RemoveZone(Zone &zones[],const int index,const string prefix)
  {
   if(index<0 || index>=ArraySize(zones))
      return;
   DeleteZoneObjects(prefix,zones[index].id);
   for(int i=index;i<ArraySize(zones)-1;++i)
      zones[i]=zones[i+1];
   ArrayResize(zones,ArraySize(zones)-1);
  }

void PushZone(Zone &zones[],const Zone &zone,const string prefix)
  {
   int size = ArraySize(zones);
   ArrayResize(zones,size+1);
   zones[size]=zone;
   if(ArraySize(zones)>InpMaxZones)
      RemoveZone(zones,0,prefix);
  }

//--- detection --------------------------------------------------------------
bool IsSwingHigh(const double &highs[],int pivot,const int swingLen,const int total)
  {
   if(pivot<swingLen || pivot>=total-swingLen)
      return false;
   double price = highs[pivot];
   for(int i=pivot-swingLen;i<pivot;i++)
      if(highs[i] >= price)
         return false;
   for(int i=pivot+1;i<=pivot+swingLen;i++)
      if(highs[i] > price)
         return false;
   return true;
  }

bool IsSwingLow(const double &lows[],int pivot,const int swingLen,const int total)
  {
   if(pivot<swingLen || pivot>=total-swingLen)
      return false;
   double price = lows[pivot];
   for(int i=pivot-swingLen;i<pivot;i++)
      if(lows[i] <= price)
         return false;
   for(int i=pivot+1;i<=pivot+swingLen;i++)
      if(lows[i] < price)
         return false;
   return true;
  }

void RegisterSwingLabel(const SwingPoint &pt,const bool isHigh,const double prevPrice)
  {
   if(!InpShowSwingLabels || pt.index<0)
      return;
   ++gSwingLabelId;
   string text;
   if(prevPrice==0.0)
      text = isHigh ? "HH" : "LL";
   else if(isHigh)
      text = (pt.price>prevPrice) ? "HH" : "LH";
   else
      text = (pt.price>prevPrice) ? "HL" : "LL";
   color clr = isHigh ? InpBearStructureColor : InpBullStructureColor;
   DrawTextLabel("SMC_SWING",gSwingLabelId,pt.time,pt.price,clr,text,isHigh?ANCHOR_LOWER:ANCHOR_UPPER);
  }

void RegisterEqualLevel(const SwingPoint &first,const SwingPoint &second,const bool highLevel,const int rates_total)
  {
   ++gEqualLabelId;
   color clr = highLevel ? InpEqualHighColor : InpEqualLowColor;
   DrawTextLabel("SMC_EQ",gEqualLabelId,second.time,second.price,clr,highLevel?"EQH":"EQL",highLevel?ANCHOR_UPPER:ANCHOR_LOWER);
   double levelPrice = second.price;
   if(highLevel)
     {
      SetBufferValue(gEqualHighBuffer,rates_total,second.index,levelPrice);
      gLastEqualHighPrice = levelPrice;
      gLastEqualHighIndex = second.index;
     }
   else
     {
      SetBufferValue(gEqualLowBuffer,rates_total,second.index,levelPrice);
      gLastEqualLowPrice = levelPrice;
      gLastEqualLowIndex = second.index;
     }
  }

void MarkStructure(const SwingPoint &pivot,const datetime eventTime,const bool bullish,const bool choch)
  {
   if(!InpShowStructure)
      return;
   ++gStructureLabelId;
   color clr = bullish ? InpBullStructureColor : InpBearStructureColor;
   string text = choch?"CHoCH":"BOS";
   DrawTextLabel("SMC_STR",gStructureLabelId,eventTime,pivot.price,clr,text,bullish?ANCHOR_LOWER:ANCHOR_UPPER);
   DrawDottedLine("SMC_STR",gStructureLabelId,pivot.time,eventTime,pivot.price,clr);
  }

void AddOrderBlock(const int chronoIndex,const bool bullish,const double &opens[],const double &closes[],const datetime &times[],const int rates_total)
  {
   if(!InpShowOrderBlocks)
      return;
   for(int idx=chronoIndex-1; idx>=0; --idx)
     {
      bool candleBear = closes[idx] < opens[idx];
      bool candleBull = closes[idx] > opens[idx];
      if(bullish && candleBear)
        {
         Zone z;
         z.bullish = true;
         z.startTime = times[idx];
         z.mitigated = false;
         z.id = gNextZoneId++;
         z.top = MathMax(opens[idx],closes[idx]);
         z.bottom = MathMin(opens[idx],closes[idx]);
         PushZone(gObZones,z,"OB_");
         SetBufferValue(gBullishOBHighBuffer,rates_total,chronoIndex,z.top);
         SetBufferValue(gBullishOBLowBuffer,rates_total,chronoIndex,z.bottom);
         return;
        }
      if(!bullish && candleBull)
        {
         Zone z;
         z.bullish = false;
         z.startTime = times[idx];
         z.mitigated = false;
         z.id = gNextZoneId++;
         z.top = MathMax(opens[idx],closes[idx]);
         z.bottom = MathMin(opens[idx],closes[idx]);
         PushZone(gObZones,z,"OB_");
         SetBufferValue(gBearishOBHighBuffer,rates_total,chronoIndex,z.top);
         SetBufferValue(gBearishOBLowBuffer,rates_total,chronoIndex,z.bottom);
         return;
        }
     }
  }

void AddFvg(const int chronoIndex,const bool bullish,const double top,const double bottom,const datetime startTime,const int rates_total)
  {
   if(!InpShowFVG)
      return;
   Zone z;
   z.bullish = bullish;
   z.top = top;
   z.bottom = bottom;
   z.startTime = startTime;
   z.mitigated = false;
   z.id = gNextZoneId++;
   PushZone(gFvgZones,z,"FVG_");
   if(bullish)
     {
      SetBufferValue(gBullishFvgHighBuffer,rates_total,chronoIndex,top);
      SetBufferValue(gBullishFvgLowBuffer,rates_total,chronoIndex,bottom);
     }
   else
     {
      SetBufferValue(gBearishFvgHighBuffer,rates_total,chronoIndex,top);
      SetBufferValue(gBearishFvgLowBuffer,rates_total,chronoIndex,bottom);
     }
  }

void UpdateOrderBlocks(const double high,const double low)
  {
   for(int i=ArraySize(gObZones)-1;i>=0;--i)
     {
      if(gObZones[i].mitigated)
         continue;
      if(gObZones[i].bullish)
        {
         if(low <= gObZones[i].top && high >= gObZones[i].bottom)
            gObZones[i].mitigated = true;
        }
      else
        {
         if(high >= gObZones[i].bottom && low <= gObZones[i].top)
            gObZones[i].mitigated = true;
        }
     }
  }

void UpdateFvgs(const double high,const double low)
  {
   for(int i=ArraySize(gFvgZones)-1;i>=0;--i)
     {
      bool remove = false;
      if(gFvgZones[i].bullish)
        {
         if(low <= gFvgZones[i].bottom)
            remove = true;
        }
      else
        {
         if(high >= gFvgZones[i].top)
            remove = true;
        }
      if(remove)
         RemoveZone(gFvgZones,i,"FVG_");
     }
  }

void RenderZones(const datetime latestTime,const long barSeconds)
  {
   datetime rightTime = latestTime + (datetime)(InpExtendRightBars*barSeconds);
  if(InpShowFVG)
    {
      for(int i=0;i<ArraySize(gFvgZones);++i)
         RenderZone(gFvgZones[i],"FVG_",InpFvgColor,InpZoneOpacityActive,rightTime);
    }
   else
     {
      DeleteObjectByPrefix("FVG_");
      ArrayResize(gFvgZones,0);
     }

  if(InpShowOrderBlocks)
    {
      for(int i=0;i<ArraySize(gObZones);++i)
        {
         int opacity = gObZones[i].mitigated ? InpZoneOpacityMitigated : InpZoneOpacityActive;
         color zoneColor = gObZones[i].bullish ? InpFvgColor : InpBearZoneColor;
         RenderZone(gObZones[i],"OB_",zoneColor,opacity,rightTime);
        }
    }
   else
     {
      DeleteObjectByPrefix("OB_");
      ArrayResize(gObZones,0);
     }
  }

//--- indicator configuration -------------------------------------------------
void ConfigureBuffer(const int index,double &buffer[],const string label)
  {
   SetIndexBuffer(index,buffer,INDICATOR_DATA);
   ArraySetAsSeries(buffer,true);
   PlotIndexSetInteger(index,PLOT_DRAW_TYPE,DRAW_NONE);
   PlotIndexSetString(index,PLOT_LABEL,label);
   PlotIndexSetInteger(index,PLOT_SHOW_DATA,true);
   PlotIndexSetDouble(index,PLOT_EMPTY_VALUE,EMPTY_VALUE);
  }

int OnInit()
  {
   IndicatorSetString(INDICATOR_SHORTNAME,"SMC Structure");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);

   ConfigureBuffer(BUFFER_BULLISH_BOS,gBullishBosBuffer,"Bullish BOS");
   ConfigureBuffer(BUFFER_BEARISH_BOS,gBearishBosBuffer,"Bearish BOS");
   ConfigureBuffer(BUFFER_BULLISH_CHOCH,gBullishChochBuffer,"Bullish CHoCH");
   ConfigureBuffer(BUFFER_BEARISH_CHOCH,gBearishChochBuffer,"Bearish CHoCH");
   ConfigureBuffer(BUFFER_BULLISH_OB_HIGH,gBullishOBHighBuffer,"Bull OB High");
   ConfigureBuffer(BUFFER_BULLISH_OB_LOW,gBullishOBLowBuffer,"Bull OB Low");
   ConfigureBuffer(BUFFER_BEARISH_OB_HIGH,gBearishOBHighBuffer,"Bear OB High");
   ConfigureBuffer(BUFFER_BEARISH_OB_LOW,gBearishOBLowBuffer,"Bear OB Low");
   ConfigureBuffer(BUFFER_BULLISH_FVG_HIGH,gBullishFvgHighBuffer,"Bullish FVG High");
   ConfigureBuffer(BUFFER_BULLISH_FVG_LOW,gBullishFvgLowBuffer,"Bullish FVG Low");
   ConfigureBuffer(BUFFER_BEARISH_FVG_HIGH,gBearishFvgHighBuffer,"Bearish FVG High");
   ConfigureBuffer(BUFFER_BEARISH_FVG_LOW,gBearishFvgLowBuffer,"Bearish FVG Low");
   ConfigureBuffer(BUFFER_EQ_HIGHS,gEqualHighBuffer,"Equal High");
   ConfigureBuffer(BUFFER_EQ_LOWS,gEqualLowBuffer,"Equal Low");
   ConfigureBuffer(BUFFER_LIQUIDITY_GRAB_HIGH,gLgHighBuffer,"Liquidity Grab High");
   ConfigureBuffer(BUFFER_LIQUIDITY_GRAB_LOW,gLgLowBuffer,"Liquidity Grab Low");

   ResetState();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   DeleteObjectByPrefix("SMC_STR");
   DeleteObjectByPrefix("SMC_EQ");
   DeleteObjectByPrefix("SMC_EQR");
   DeleteObjectByPrefix("SMC_EQD");
   DeleteObjectByPrefix("SMC_EQL");
   DeleteObjectByPrefix("SMC_SWING");
   DeleteObjectByPrefix("SMC_LG");
   DeleteObjectByPrefix("OB_");
   DeleteObjectByPrefix("FVG_");
  }

//--- main calculation -------------------------------------------------------
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const int begin,
                const double &price[])
  {
   if(rates_total<=InpSwingLength*2)
      return(0);

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   if(CopyRates(_Symbol,_Period,0,rates_total,rates)<=0)
      return(prev_calculated);

   double highs[];
   double lows[];
   double opens[];
   double closes[];
   datetime times[];

   ArrayResize(highs,rates_total);
   ArrayResize(lows,rates_total);
   ArrayResize(opens,rates_total);
   ArrayResize(closes,rates_total);
   ArrayResize(times,rates_total);

   for(int c=0;c<rates_total;++c)
     {
      int idx = rates_total-1-c;
      highs[c]  = rates[idx].high;
      lows[c]   = rates[idx].low;
      opens[c]  = rates[idx].open;
      closes[c] = rates[idx].close;
      times[c]  = rates[idx].time;
     }

   int lastClosed = rates_total-2;
   if(lastClosed<InpSwingLength)
      return(prev_calculated);

   if(prev_calculated==0)
     {
      ResetState();
      DeleteObjectByPrefix("SMC_STR");
      DeleteObjectByPrefix("SMC_EQ");
      DeleteObjectByPrefix("SMC_EQR");
      DeleteObjectByPrefix("SMC_EQD");
      DeleteObjectByPrefix("SMC_EQL");
      DeleteObjectByPrefix("SMC_SWING");
      DeleteObjectByPrefix("SMC_LG");
      DeleteObjectByPrefix("OB_");
      DeleteObjectByPrefix("FVG_");
     }

   int startIndex = MathMax(gLastProcessedIndex+1,InpSwingLength);
   if(startIndex<InpSwingLength)
      startIndex = InpSwingLength;
   if(startIndex>lastClosed)
      return(rates_total);

   for(int chrono=startIndex; chrono<=lastClosed; ++chrono)
     {
      ClearBuffersAtIndex(rates_total,chrono);

      int pivot = chrono - InpSwingLength;
      if(pivot>=0)
        {
         if(IsSwingHigh(highs,pivot,InpSwingLength,rates_total))
           {
            gPrevSwingHigh = gLastSwingHigh;
            gLastSwingHigh.index = pivot;
            gLastSwingHigh.price = highs[pivot];
            gLastSwingHigh.time  = times[pivot];
            double prevPrice = (gPrevSwingHigh.index>=0) ? gPrevSwingHigh.price : 0.0;
            RegisterSwingLabel(gLastSwingHigh,true,prevPrice);
            if(gPrevSwingHigh.index>=0 && InpShowEqualLevels)
              {
               double diff = MathAbs(gPrevSwingHigh.price - gLastSwingHigh.price);
               if(diff <= InpMinEQTicks*_Point)
                  RegisterEqualLevel(gPrevSwingHigh,gLastSwingHigh,true,rates_total);
              }
           }
         if(IsSwingLow(lows,pivot,InpSwingLength,rates_total))
           {
            gPrevSwingLow = gLastSwingLow;
            gLastSwingLow.index = pivot;
            gLastSwingLow.price = lows[pivot];
            gLastSwingLow.time  = times[pivot];
            double prevPrice = (gPrevSwingLow.index>=0) ? gPrevSwingLow.price : 0.0;
            RegisterSwingLabel(gLastSwingLow,false,prevPrice);
            if(gPrevSwingLow.index>=0 && InpShowEqualLevels)
              {
               double diff = MathAbs(gPrevSwingLow.price - gLastSwingLow.price);
               if(diff <= InpMinEQTicks*_Point)
                  RegisterEqualLevel(gPrevSwingLow,gLastSwingLow,false,rates_total);
              }
           }
        }

      double close = closes[chrono];
      double high  = highs[chrono];
      double low   = lows[chrono];

      if(gLastSwingHigh.index>=0 && close>gLastSwingHigh.price && gLastSwingHigh.index!=gLastBrokenHighSource)
        {
         bool choch = (gTrendDirection<=0);
         if(choch && !InpShowChoCh)
            choch = false;
         gTrendDirection = 1;
         if(choch)
            SetBufferValue(gBullishChochBuffer,rates_total,chrono,gLastSwingHigh.price);
         else
            SetBufferValue(gBullishBosBuffer,rates_total,chrono,gLastSwingHigh.price);
         MarkStructure(gLastSwingHigh,times[chrono],true,choch);
         AddOrderBlock(chrono,true,opens,closes,times,rates_total);
         gLastBrokenHighSource = gLastSwingHigh.index;
        }
      if(gLastSwingLow.index>=0 && close<gLastSwingLow.price && gLastSwingLow.index!=gLastBrokenLowSource)
        {
         bool choch = (gTrendDirection>=0);
         if(choch && !InpShowChoCh)
            choch = false;
         gTrendDirection = -1;
         if(choch)
            SetBufferValue(gBearishChochBuffer,rates_total,chrono,gLastSwingLow.price);
         else
            SetBufferValue(gBearishBosBuffer,rates_total,chrono,gLastSwingLow.price);
         MarkStructure(gLastSwingLow,times[chrono],false,choch);
         AddOrderBlock(chrono,false,opens,closes,times,rates_total);
         gLastBrokenLowSource = gLastSwingLow.index;
        }

      if(gLastEqualHighIndex>=0 && high>gLastEqualHighPrice && close<gLastEqualHighPrice)
        {
         SetBufferValue(gLgHighBuffer,rates_total,chrono,gLastEqualHighPrice);
         DrawTextLabel("SMC_LG",chrono,times[chrono],gLastEqualHighPrice,InpBearStructureColor,"LG",ANCHOR_LOWER);
         gLastEqualHighIndex = -1;
        }
      if(gLastEqualLowIndex>=0 && low<gLastEqualLowPrice && close>gLastEqualLowPrice)
        {
         SetBufferValue(gLgLowBuffer,rates_total,chrono,gLastEqualLowPrice);
         DrawTextLabel("SMC_LG",chrono,times[chrono],gLastEqualLowPrice,InpBullStructureColor,"LG",ANCHOR_UPPER);
         gLastEqualLowIndex = -1;
        }

      if(InpShowFVG && chrono>=2)
        {
         double low2 = lows[chrono-2];
         double high2 = highs[chrono-2];
         bool bullGap = lows[chrono] > high2 && closes[chrono-1] > high2;
         bool bearGap = highs[chrono] < low2 && closes[chrono-1] < low2;
         if(bullGap)
            AddFvg(chrono,true,lows[chrono],high2,times[chrono-2],rates_total);
         if(bearGap)
            AddFvg(chrono,false,low2,highs[chrono],times[chrono-2],rates_total);
        }

      UpdateOrderBlocks(high,low);
      UpdateFvgs(high,low);

      gLastProcessedIndex = chrono;
     }

   datetime latestTime = times[lastClosed];
   long barSeconds = PeriodSeconds(_Period);
   if(barSeconds<=0 && lastClosed>0)
      barSeconds = (long)(times[lastClosed]-times[lastClosed-1]);
   RenderZones(latestTime,barSeconds);

   return(rates_total);
  }
