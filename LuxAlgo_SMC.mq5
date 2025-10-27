#property copyright "Converted from LuxAlgo Smart Money Concepts"
#property link      "https://www.luxalgo.com"
#property version   "1.00"
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

enum eLegDirection
  {
   LEG_BEARISH = 0,
   LEG_BULLISH = 1
  };

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

struct Pivot
  {
   double    currentLevel;
   double    lastLevel;
   bool      crossed;
   datetime  barTime;
   int       barIndex;

   void Reset()
     {
      currentLevel = 0.0;
      lastLevel    = 0.0;
      crossed      = false;
      barTime      = 0;
      barIndex     = -1;
     }
  };

struct TrendBias
  {
   int bias;

   void Reset()
     {
      bias = 0;
     }
  };

struct FVGEvent
  {
   bool      bullish;
   bool      active;
   double    top;
   double    bottom;
   datetime  leftTime;
   int       startIndex;
  };

input int      InpSwingLength             = 50;
input int      InpInternalLength          = 5;
input int      InpEqualLength             = 3;
input double   InpEqualThreshold          = 0.1;
input int      InpATRPeriod               = 200;
input bool     InpShowOrderBlocks         = true;
input bool     InpShowFairValueGaps       = false;
input bool     InpAutoFVGThreshold        = true;
input ENUM_TIMEFRAMES InpFVGTimeframe     = PERIOD_CURRENT;
input int      InpFVGExtend               = 1;

// Style colors (approximation of TradingView palette)
input color    InpBullStructureColor      = clrLimeGreen;
input color    InpBearStructureColor      = clrTomato;
input color    InpEqualLevelColor         = clrDodgerBlue;
input color    InpBullOrderBlockColor     = clrCornflowerBlue;
input color    InpBearOrderBlockColor     = clrCrimson;
input color    InpBullFVGColor            = clrMediumSeaGreen;
input color    InpBearFVGColor            = clrLightSalmon;

// Indicator buffers
double        gBullishBOSBuffer[];
double        gBearishBOSBuffer[];
double        gBullishChoChBuffer[];
double        gBearishChoChBuffer[];
double        gBullishOBHighBuffer[];
double        gBullishOBLowBuffer[];
double        gBearishOBHighBuffer[];
double        gBearishOBLowBuffer[];
double        gBullishFVGHighBuffer[];
double        gBullishFVGLowBuffer[];
double        gBearishFVGHighBuffer[];
double        gBearishFVGLowBuffer[];
double        gEqualHighsBuffer[];
double        gEqualLowsBuffer[];
double        gLiquidityGrabHighBuffer[];
double        gLiquidityGrabLowBuffer[];

// Working state
Pivot       gSwingHigh;
Pivot       gSwingLow;
Pivot       gInternalHigh;
Pivot       gInternalLow;
TrendBias   gSwingTrend;
TrendBias   gInternalTrend;

double      gATRValue[];
double      gLastEqualHigh = 0.0;
int         gLastEqualHighIndex = -1;
double      gLastEqualLow = 0.0;
int         gLastEqualLowIndex = -1;
double      gPointSize = 0.0;

int         gLastBufferSize     = 0;

//+------------------------------------------------------------------+
//| Helper functions                                                |
//+------------------------------------------------------------------+
int HighestIndex(const double &arr[], int start, int length)
  {
   int index = start;
   double maxVal = arr[start];
   for(int i=start+1; i<start+length; ++i)
     {
      if(arr[i] > maxVal)
        {
         maxVal = arr[i];
         index = i;
        }
     }
   return index;
  }

int LowestIndex(const double &arr[], int start, int length)
  {
   int index = start;
   double minVal = arr[start];
   for(int i=start+1; i<start+length; ++i)
     {
      if(arr[i] < minVal)
        {
         minVal = arr[i];
         index = i;
        }
     }
   return index;
  }

double Highest(const double &arr[], int start, int length)
  {
   return arr[HighestIndex(arr,start,length)];
  }

double Lowest(const double &arr[], int start, int length)
  {
   return arr[LowestIndex(arr,start,length)];
  }

int LegDirection(const double &highs[], const double &lows[], int index, int length)
  {
   if(index < length)
      return LEG_BEARISH;

   double newHigh = highs[index] > Highest(highs,index-length,length);
   double newLow  = lows[index]  < Lowest(lows,index-length,length);

   if(newHigh)
      return LEG_BEARISH;
   if(newLow)
      return LEG_BULLISH;
   return LEG_BEARISH;
  }

bool StartOfNewLeg(int prevLeg, int currLeg)
  {
   return (currLeg != prevLeg);
  }

bool StartOfBullishLeg(int prevLeg, int currLeg)
  {
   return (prevLeg == LEG_BEARISH && currLeg == LEG_BULLISH);
  }

bool StartOfBearishLeg(int prevLeg, int currLeg)
  {
   return (prevLeg == LEG_BULLISH && currLeg == LEG_BEARISH);
  }

void ResetState()
  {
   gSwingHigh.Reset();
   gSwingLow.Reset();
   gInternalHigh.Reset();
   gInternalLow.Reset();
   gSwingTrend.Reset();
   gInternalTrend.Reset();
   gLastEqualHigh      = 0.0;
   gLastEqualHighIndex = -1;
   gLastEqualLow       = 0.0;
   gLastEqualLowIndex  = -1;
  }

void EnsureBufferSize(double &buffer[],const int newSize)
  {
   int currentSize = ArraySize(buffer);
   if(currentSize == newSize)
      return;

   bool initialize = (currentSize == 0);
   ArrayResize(buffer,newSize);
   ArraySetAsSeries(buffer,true);

   if(initialize)
      ArrayInitialize(buffer,EMPTY_VALUE);
   else if(newSize > currentSize)
     {
      for(int i=currentSize;i<newSize;++i)
         buffer[i] = EMPTY_VALUE;
     }
  }

void EnsureAllBuffers(const int rates_total)
  {
   if(gLastBufferSize == rates_total)
      return;

   EnsureBufferSize(gBullishBOSBuffer,rates_total);
   EnsureBufferSize(gBearishBOSBuffer,rates_total);
   EnsureBufferSize(gBullishChoChBuffer,rates_total);
   EnsureBufferSize(gBearishChoChBuffer,rates_total);
   EnsureBufferSize(gBullishOBHighBuffer,rates_total);
   EnsureBufferSize(gBullishOBLowBuffer,rates_total);
   EnsureBufferSize(gBearishOBHighBuffer,rates_total);
   EnsureBufferSize(gBearishOBLowBuffer,rates_total);
   EnsureBufferSize(gBullishFVGHighBuffer,rates_total);
   EnsureBufferSize(gBullishFVGLowBuffer,rates_total);
   EnsureBufferSize(gBearishFVGHighBuffer,rates_total);
   EnsureBufferSize(gBearishFVGLowBuffer,rates_total);
   EnsureBufferSize(gEqualHighsBuffer,rates_total);
   EnsureBufferSize(gEqualLowsBuffer,rates_total);
   EnsureBufferSize(gLiquidityGrabHighBuffer,rates_total);
   EnsureBufferSize(gLiquidityGrabLowBuffer,rates_total);

   gLastBufferSize = rates_total;
  }

void PushBufferValue(const int bufferIndex,const int rates_total,const int chronologicalIndex,const double value)
  {
   switch(bufferIndex)
     {
      case BUFFER_BULLISH_BOS:            SetBufferValue(gBullishBOSBuffer,rates_total,chronologicalIndex,value);      break;
      case BUFFER_BEARISH_BOS:            SetBufferValue(gBearishBOSBuffer,rates_total,chronologicalIndex,value);      break;
      case BUFFER_BULLISH_CHOCH:          SetBufferValue(gBullishChoChBuffer,rates_total,chronologicalIndex,value);    break;
      case BUFFER_BEARISH_CHOCH:          SetBufferValue(gBearishChoChBuffer,rates_total,chronologicalIndex,value);    break;
      case BUFFER_BULLISH_OB_HIGH:        SetBufferValue(gBullishOBHighBuffer,rates_total,chronologicalIndex,value);   break;
      case BUFFER_BULLISH_OB_LOW:         SetBufferValue(gBullishOBLowBuffer,rates_total,chronologicalIndex,value);    break;
      case BUFFER_BEARISH_OB_HIGH:        SetBufferValue(gBearishOBHighBuffer,rates_total,chronologicalIndex,value);   break;
      case BUFFER_BEARISH_OB_LOW:         SetBufferValue(gBearishOBLowBuffer,rates_total,chronologicalIndex,value);    break;
      case BUFFER_BULLISH_FVG_HIGH:       SetBufferValue(gBullishFVGHighBuffer,rates_total,chronologicalIndex,value);  break;
      case BUFFER_BULLISH_FVG_LOW:        SetBufferValue(gBullishFVGLowBuffer,rates_total,chronologicalIndex,value);   break;
      case BUFFER_BEARISH_FVG_HIGH:       SetBufferValue(gBearishFVGHighBuffer,rates_total,chronologicalIndex,value);  break;
      case BUFFER_BEARISH_FVG_LOW:        SetBufferValue(gBearishFVGLowBuffer,rates_total,chronologicalIndex,value);   break;
      case BUFFER_EQ_HIGHS:               SetBufferValue(gEqualHighsBuffer,rates_total,chronologicalIndex,value);      break;
      case BUFFER_EQ_LOWS:                SetBufferValue(gEqualLowsBuffer,rates_total,chronologicalIndex,value);       break;
      case BUFFER_LIQUIDITY_GRAB_HIGH:    SetBufferValue(gLiquidityGrabHighBuffer,rates_total,chronologicalIndex,value); break;
      case BUFFER_LIQUIDITY_GRAB_LOW:     SetBufferValue(gLiquidityGrabLowBuffer,rates_total,chronologicalIndex,value);  break;
     }
  }

string BuildObjectName(const string prefix,const int index)
  {
   return prefix + "_" + IntegerToString(index);
  }

double PriceOffset(const double price,const bool above)
  {
   double offset = 6.0 * gPointSize;
   if(offset == 0.0)
      offset = 6.0 * SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   return above ? price + offset : price - offset;
  }

void DrawStructureLabel(const string prefix,const int index,const datetime t,const double price,const color clr,const string text,const bool above)
  {
   string name = BuildObjectName(prefix,index);
   double positionedPrice = PriceOffset(price,above);
   if(ObjectFind(0,name) < 0)
      ObjectCreate(0,name,OBJ_TEXT,0,t,positionedPrice);

   ObjectSetInteger(0,name,OBJPROP_TIME,0,t);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,positionedPrice);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,above ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
  }

void DrawStructureLine(const string prefix,const int index,const datetime fromTime,const datetime toTime,const double price,const color clr)
  {
   string name = BuildObjectName(prefix,index);
   if(ObjectFind(0,name) < 0)
      ObjectCreate(0,name,OBJ_TREND,0,fromTime,price,toTime,price);

   ObjectSetInteger(0,name,OBJPROP_TIME,0,fromTime);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,toTime);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,price);
   ObjectSetDouble(0,name,OBJPROP_PRICE,1,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,true);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

void DrawEqualLevel(const string prefix,const int index,const datetime startTime,const datetime currentTime,const double level,const string labelText,const color clr,const bool isHigh)
  {
   DrawStructureLine(prefix + "_LINE",index,startTime,currentTime,level,clr);
   DrawStructureLabel(prefix + "_LBL",index,currentTime,level,clr,labelText,isHigh);
  }

void DrawRectangleZone(const string prefix,const int index,const datetime startTime,const datetime endTime,const double top,const double bottom,const color baseColor)
  {
   string name = BuildObjectName(prefix,index);
   if(ObjectFind(0,name) < 0)
      ObjectCreate(0,name,OBJ_RECTANGLE,0,startTime,top,endTime,bottom);

   ObjectSetInteger(0,name,OBJPROP_TIME,0,startTime);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,endTime);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,top);
   ObjectSetDouble(0,name,OBJPROP_PRICE,1,bottom);
   ObjectSetInteger(0,name,OBJPROP_COLOR,ColorToARGB(baseColor,50));
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

void DrawZoneLabel(const string prefix,const int index,const datetime t,const double price,const color clr,const string text)
  {
   string name = BuildObjectName(prefix,index);
   if(ObjectFind(0,name) < 0)
      ObjectCreate(0,name,OBJ_TEXT,0,t,price);

   ObjectSetInteger(0,name,OBJPROP_TIME,0,t);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_CENTER);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
  }

void UpdatePivot(Pivot &ref,const double level,const datetime t,const int index)
  {
   ref.lastLevel    = ref.currentLevel;
   ref.currentLevel = level;
   ref.crossed      = false;
   ref.barTime      = t;
   ref.barIndex     = index;
  }

void SetBufferValue(double &buffer[],int rates_total,int chronologicalIndex,double value)
  {
   if(chronologicalIndex<0 || chronologicalIndex>=rates_total)
      return;
   int shift = rates_total - 1 - chronologicalIndex;
   if(shift>=0 && shift<rates_total)
      buffer[shift] = value;
  }

void ConfigureBuffer(const int bufferIndex,
                     double &buffer[],
                     ENUM_DRAW_TYPE drawType,
                     color lineColor,
                     int lineWidth=1,
                     int arrowCode=0,
                     const string label="")
  {
   SetIndexBuffer(bufferIndex,buffer,INDICATOR_DATA);
   PlotIndexSetInteger(bufferIndex,PLOT_DRAW_TYPE,drawType);
   PlotIndexSetInteger(bufferIndex,PLOT_LINE_STYLE,STYLE_SOLID);
   PlotIndexSetInteger(bufferIndex,PLOT_LINE_WIDTH,lineWidth);
   PlotIndexSetInteger(bufferIndex,PLOT_LINE_COLOR,0,lineColor);
   PlotIndexSetDouble(bufferIndex,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   if(drawType==DRAW_ARROW && arrowCode!=0)
      PlotIndexSetInteger(bufferIndex,PLOT_ARROW,arrowCode);
   if(label!="")
      PlotIndexSetString(bufferIndex,PLOT_LABEL,label);
   PlotIndexSetInteger(bufferIndex,PLOT_SHOW_DATA,true);
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   IndicatorSetString(INDICATOR_SHORTNAME,"LuxAlgo SMC");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);

   gPointSize = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   gLastBufferSize     = 0;

   ConfigureBuffer(BUFFER_BULLISH_BOS,gBullishBOSBuffer,DRAW_NONE,InpBullStructureColor,1,0,"Bullish BOS");
   ConfigureBuffer(BUFFER_BEARISH_BOS,gBearishBOSBuffer,DRAW_NONE,InpBearStructureColor,1,0,"Bearish BOS");
   ConfigureBuffer(BUFFER_BULLISH_CHOCH,gBullishChoChBuffer,DRAW_NONE,InpBullStructureColor,1,0,"Bullish CHoCH");
   ConfigureBuffer(BUFFER_BEARISH_CHOCH,gBearishChoChBuffer,DRAW_NONE,InpBearStructureColor,1,0,"Bearish CHoCH");

   ConfigureBuffer(BUFFER_BULLISH_OB_HIGH,gBullishOBHighBuffer,DRAW_NONE,InpBullOrderBlockColor,1,0,"Bullish OB High");
   ConfigureBuffer(BUFFER_BULLISH_OB_LOW,gBullishOBLowBuffer,DRAW_NONE,InpBullOrderBlockColor,1,0,"Bullish OB Low");
   ConfigureBuffer(BUFFER_BEARISH_OB_HIGH,gBearishOBHighBuffer,DRAW_NONE,InpBearOrderBlockColor,1,0,"Bearish OB High");
   ConfigureBuffer(BUFFER_BEARISH_OB_LOW,gBearishOBLowBuffer,DRAW_NONE,InpBearOrderBlockColor,1,0,"Bearish OB Low");

   ConfigureBuffer(BUFFER_BULLISH_FVG_HIGH,gBullishFVGHighBuffer,DRAW_NONE,InpBullFVGColor,1,0,"Bullish FVG High");
   ConfigureBuffer(BUFFER_BULLISH_FVG_LOW,gBullishFVGLowBuffer,DRAW_NONE,InpBullFVGColor,1,0,"Bullish FVG Low");
   ConfigureBuffer(BUFFER_BEARISH_FVG_HIGH,gBearishFVGHighBuffer,DRAW_NONE,InpBearFVGColor,1,0,"Bearish FVG High");
   ConfigureBuffer(BUFFER_BEARISH_FVG_LOW,gBearishFVGLowBuffer,DRAW_NONE,InpBearFVGColor,1,0,"Bearish FVG Low");

   ConfigureBuffer(BUFFER_EQ_HIGHS,gEqualHighsBuffer,DRAW_NONE,InpEqualLevelColor,1,0,"Equal Highs");
   ConfigureBuffer(BUFFER_EQ_LOWS,gEqualLowsBuffer,DRAW_NONE,InpEqualLevelColor,1,0,"Equal Lows");
   ConfigureBuffer(BUFFER_LIQUIDITY_GRAB_HIGH,gLiquidityGrabHighBuffer,DRAW_NONE,InpBearStructureColor,1,0,"Liquidity Grab High");
   ConfigureBuffer(BUFFER_LIQUIDITY_GRAB_LOW,gLiquidityGrabLowBuffer,DRAW_NONE,InpBullStructureColor,1,0,"Liquidity Grab Low");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total <= MathMax(InpSwingLength,InpInternalLength)+5)
      return(0);

   EnsureAllBuffers(rates_total);
   ArrayResize(gATRValue,rates_total);

   // Build chronological arrays
   static double highsChron[];
   static double lowsChron[];
   static double opensChron[];
   static double closesChron[];
   static datetime timesChron[];

   ArrayResize(highsChron,rates_total);
   ArrayResize(lowsChron,rates_total);
   ArrayResize(opensChron,rates_total);
   ArrayResize(closesChron,rates_total);
   ArrayResize(timesChron,rates_total);

   for(int i=0;i<rates_total;++i)
     {
      int shift = rates_total-1-i;
      highsChron[i]  = high[shift];
      lowsChron[i]   = low[shift];
      opensChron[i]  = open[shift];
      closesChron[i] = close[shift];
      timesChron[i]  = time[shift];
     }

   if(gPointSize<=0.0)
      gPointSize = SymbolInfoDouble(_Symbol,SYMBOL_POINT);

   // ATR calculation (simple Wilder smoothing)
   double prevATR = 0.0;
   for(int i=0;i<rates_total;++i)
     {
      double tr = highsChron[i]-lowsChron[i];
      if(i>0)
        {
         double tr1 = MathAbs(highsChron[i]-closesChron[i-1]);
         double tr2 = MathAbs(lowsChron[i]-closesChron[i-1]);
         tr = MathMax(tr,MathMax(tr1,tr2));
        }
      if(i==0)
         prevATR = tr;
      else
         prevATR = (prevATR*(InpATRPeriod-1)+tr)/InpATRPeriod;
      gATRValue[i] = prevATR;
     }

   int previousSwingLeg    = LEG_BEARISH;
   int previousInternalLeg = LEG_BEARISH;

   datetime latestBarTime = timesChron[rates_total-1];

   FVGEvent fvgEvents[];
   ArrayResize(fvgEvents,0);

   if(prev_calculated==0 && InpShowFairValueGaps)
     {
      ObjectsDeleteAll(0,"SMC_FVG_BULL");
      ObjectsDeleteAll(0,"SMC_FVG_BEAR");
     }

   ResetState();

   for(int i=0;i<rates_total;++i)
     {
      int swingLeg    = LegDirection(highsChron,lowsChron,i,InpSwingLength);
      int internalLeg = LegDirection(highsChron,lowsChron,i,InpInternalLength);

      if(InpShowFairValueGaps)
        {
         int fvgCount = ArraySize(fvgEvents);
         for(int f=0; f<fvgCount; ++f)
           {
            if(!fvgEvents[f].active)
               continue;
            if(fvgEvents[f].bullish)
              {
               if(lowsChron[i] <= fvgEvents[f].bottom)
                  fvgEvents[f].active = false;
              }
            else
              {
               if(highsChron[i] >= fvgEvents[f].top)
                  fvgEvents[f].active = false;
              }
           }
        }

      bool newSwingPivot    = StartOfNewLeg(previousSwingLeg,swingLeg);
      bool newInternalPivot = StartOfNewLeg(previousInternalLeg,internalLeg);

      if(newSwingPivot)
        {
         if(StartOfBullishLeg(previousSwingLeg,swingLeg))
           {
            UpdatePivot(gSwingLow,lowsChron[i],timesChron[i],i);
           }
         else if(StartOfBearishLeg(previousSwingLeg,swingLeg))
           {
            UpdatePivot(gSwingHigh,highsChron[i],timesChron[i],i);
           }
        }

      if(newInternalPivot)
        {
         if(StartOfBullishLeg(previousInternalLeg,internalLeg))
            UpdatePivot(gInternalLow,lowsChron[i],timesChron[i],i);
         else if(StartOfBearishLeg(previousInternalLeg,internalLeg))
            UpdatePivot(gInternalHigh,highsChron[i],timesChron[i],i);
        }

      previousSwingLeg    = swingLeg;
      previousInternalLeg = internalLeg;

      // Structure detection for internal trend
      if(gInternalHigh.barIndex>=0 && !gInternalHigh.crossed && closesChron[i] > gInternalHigh.currentLevel)
        {
         bool choch = (gInternalTrend.bias == -1);
         gInternalHigh.crossed = true;
         gInternalTrend.bias   = 1;
         if(choch)
            PushBufferValue(BUFFER_BULLISH_CHOCH,rates_total,i,gInternalHigh.currentLevel);
         else
            PushBufferValue(BUFFER_BULLISH_BOS,rates_total,i,gInternalHigh.currentLevel);
        }
      if(gInternalLow.barIndex>=0 && !gInternalLow.crossed && closesChron[i] < gInternalLow.currentLevel)
        {
         bool choch = (gInternalTrend.bias == 1);
         gInternalLow.crossed = true;
         gInternalTrend.bias  = -1;
         if(choch)
            PushBufferValue(BUFFER_BEARISH_CHOCH,rates_total,i,gInternalLow.currentLevel);
         else
            PushBufferValue(BUFFER_BEARISH_BOS,rates_total,i,gInternalLow.currentLevel);
        }

      // Swing structures
      if(gSwingHigh.barIndex>=0 && !gSwingHigh.crossed && closesChron[i] > gSwingHigh.currentLevel)
        {
         gSwingHigh.crossed = true;
         bool choch = (gSwingTrend.bias==-1);
         gSwingTrend.bias = 1;
         double level     = gSwingHigh.currentLevel;
         datetime pivotTime = timesChron[gSwingHigh.barIndex];
         datetime eventTime = timesChron[i];

         if(choch)
           {
            PushBufferValue(BUFFER_BULLISH_CHOCH,rates_total,i,level);
            DrawStructureLabel("SMC_CHOCH_BULL_LBL",i,eventTime,level,InpBullStructureColor,"CHoCH",true);
            DrawStructureLine("SMC_CHOCH_BULL_LINE",gSwingHigh.barIndex,pivotTime,latestBarTime,level,InpBullStructureColor);
           }
         else
           {
            PushBufferValue(BUFFER_BULLISH_BOS,rates_total,i,level);
            DrawStructureLabel("SMC_BOS_BULL_LBL",i,eventTime,level,InpBullStructureColor,"BOS",true);
            DrawStructureLine("SMC_BOS_BULL_LINE",gSwingHigh.barIndex,pivotTime,latestBarTime,level,InpBullStructureColor);
           }

         if(InpShowOrderBlocks)
           {
            int startIndex = gSwingHigh.barIndex;
            if(startIndex<0)
               startIndex = 0;
            int endIndex = i;
            if(endIndex<startIndex)
               endIndex = startIndex;
            int length = endIndex - startIndex + 1;
            if(length>0)
              {
               int maxIndex = HighestIndex(highsChron,startIndex,length);
               int minIndex = LowestIndex(lowsChron,startIndex,length);
               double obHigh = highsChron[maxIndex];
               double obLow  = lowsChron[minIndex];
               PushBufferValue(BUFFER_BULLISH_OB_HIGH,rates_total,i,obHigh);
               PushBufferValue(BUFFER_BULLISH_OB_LOW,rates_total,i,obLow);
               DrawRectangleZone("SMC_OB_BULL",startIndex,timesChron[startIndex],latestBarTime,obHigh,obLow,InpBullOrderBlockColor);
               DrawZoneLabel("SMC_OB_BULL_TAG",startIndex,latestBarTime,0.5*(obHigh+obLow),InpBullOrderBlockColor,"Bull OB");
              }
           }
        }

      if(gSwingLow.barIndex>=0 && !gSwingLow.crossed && closesChron[i] < gSwingLow.currentLevel)
        {
         gSwingLow.crossed = true;
         bool choch = (gSwingTrend.bias==1);
         gSwingTrend.bias = -1;
         double level      = gSwingLow.currentLevel;
         datetime pivotTime = timesChron[gSwingLow.barIndex];
         datetime eventTime = timesChron[i];

         if(choch)
           {
            PushBufferValue(BUFFER_BEARISH_CHOCH,rates_total,i,level);
            DrawStructureLabel("SMC_CHOCH_BEAR_LBL",i,eventTime,level,InpBearStructureColor,"CHoCH",false);
            DrawStructureLine("SMC_CHOCH_BEAR_LINE",gSwingLow.barIndex,pivotTime,latestBarTime,level,InpBearStructureColor);
           }
         else
           {
            PushBufferValue(BUFFER_BEARISH_BOS,rates_total,i,level);
            DrawStructureLabel("SMC_BOS_BEAR_LBL",i,eventTime,level,InpBearStructureColor,"BOS",false);
            DrawStructureLine("SMC_BOS_BEAR_LINE",gSwingLow.barIndex,pivotTime,latestBarTime,level,InpBearStructureColor);
           }

         if(InpShowOrderBlocks)
           {
            int startIndex = gSwingLow.barIndex;
            if(startIndex<0)
               startIndex = 0;
            int endIndex = i;
            if(endIndex<startIndex)
               endIndex = startIndex;
            int length = endIndex - startIndex + 1;
            if(length>0)
              {
               int maxIndex = HighestIndex(highsChron,startIndex,length);
               int minIndex = LowestIndex(lowsChron,startIndex,length);
               double obHigh = highsChron[maxIndex];
               double obLow  = lowsChron[minIndex];
               PushBufferValue(BUFFER_BEARISH_OB_HIGH,rates_total,i,obHigh);
               PushBufferValue(BUFFER_BEARISH_OB_LOW,rates_total,i,obLow);
               DrawRectangleZone("SMC_OB_BEAR",startIndex,timesChron[startIndex],latestBarTime,obHigh,obLow,InpBearOrderBlockColor);
               DrawZoneLabel("SMC_OB_BEAR_TAG",startIndex,latestBarTime,0.5*(obHigh+obLow),InpBearOrderBlockColor,"Bear OB");
              }
           }
        }

      // Equal highs / lows detection
      bool equalHighDetected = false;
      bool equalLowDetected  = false;
      if(i>=InpEqualLength && gSwingHigh.barIndex>=0 && MathAbs(highsChron[i]-gSwingHigh.currentLevel) <= InpEqualThreshold*gATRValue[i])
        {
         PushBufferValue(BUFFER_EQ_HIGHS,rates_total,i,gSwingHigh.currentLevel);
         DrawEqualLevel("SMC_EQ_HIGH",gSwingHigh.barIndex,timesChron[gSwingHigh.barIndex],timesChron[i],gSwingHigh.currentLevel,"EQH",InpEqualLevelColor,true);
         gLastEqualHigh      = gSwingHigh.currentLevel;
         gLastEqualHighIndex = i;
         equalHighDetected   = true;
        }
      if(i>=InpEqualLength && gSwingLow.barIndex>=0 && MathAbs(lowsChron[i]-gSwingLow.currentLevel) <= InpEqualThreshold*gATRValue[i])
        {
         PushBufferValue(BUFFER_EQ_LOWS,rates_total,i,gSwingLow.currentLevel);
         DrawEqualLevel("SMC_EQ_LOW",gSwingLow.barIndex,timesChron[gSwingLow.barIndex],timesChron[i],gSwingLow.currentLevel,"EQL",InpEqualLevelColor,false);
         gLastEqualLow      = gSwingLow.currentLevel;
         gLastEqualLowIndex = i;
         equalLowDetected   = true;
        }

      if(!equalHighDetected && gLastEqualHighIndex>=0 && highsChron[i] > gLastEqualHigh && closesChron[i] < gLastEqualHigh)
        {
         PushBufferValue(BUFFER_LIQUIDITY_GRAB_HIGH,rates_total,i,gLastEqualHigh);
         DrawStructureLabel("SMC_LG_HIGH",i,timesChron[i],gLastEqualHigh,InpBearStructureColor,"LG",true);
         gLastEqualHighIndex = -1;
        }
      if(!equalLowDetected && gLastEqualLowIndex>=0 && lowsChron[i] < gLastEqualLow && closesChron[i] > gLastEqualLow)
        {
         PushBufferValue(BUFFER_LIQUIDITY_GRAB_LOW,rates_total,i,gLastEqualLow);
         DrawStructureLabel("SMC_LG_LOW",i,timesChron[i],gLastEqualLow,InpBullStructureColor,"LG",false);
         gLastEqualLowIndex = -1;
        }

      // Fair Value Gaps (simplified)
      if(InpShowFairValueGaps && i>=2)
        {
         double lastClose = closesChron[i-1];
         double lastOpen  = opensChron[i-1];
         double last2High = highsChron[i-2];
         double last2Low  = lowsChron[i-2];
         double currHigh  = highsChron[i];
         double currLow   = lowsChron[i];
         double timeframeFactor = 1.0;
         int chartSeconds = PeriodSeconds(Period());
         int fvgSeconds   = PeriodSeconds(InpFVGTimeframe);
         if(InpFVGTimeframe!=PERIOD_CURRENT && chartSeconds>0 && fvgSeconds>0)
           timeframeFactor = (double)fvgSeconds/chartSeconds;
         double threshold = InpAutoFVGThreshold ? gATRValue[i]*0.05*timeframeFactor : 0.0;

         bool bullishFVG = currLow > last2High && lastClose > last2High && (lastClose-lastOpen) > threshold;
         bool bearishFVG = currHigh < last2Low && lastClose < last2Low && (lastOpen-lastClose) > threshold;

         if(bullishFVG)
           {
            PushBufferValue(BUFFER_BULLISH_FVG_HIGH,rates_total,i,currLow);
            PushBufferValue(BUFFER_BULLISH_FVG_LOW,rates_total,i,last2High);
            int newIndex = ArraySize(fvgEvents);
            ArrayResize(fvgEvents,newIndex+1);
            fvgEvents[newIndex].bullish    = true;
            fvgEvents[newIndex].active     = true;
            fvgEvents[newIndex].top        = currLow;
            fvgEvents[newIndex].bottom     = last2High;
            fvgEvents[newIndex].leftTime   = timesChron[i-1];
            fvgEvents[newIndex].startIndex = i;
           }
         if(bearishFVG)
           {
            PushBufferValue(BUFFER_BEARISH_FVG_HIGH,rates_total,i,last2Low);
            PushBufferValue(BUFFER_BEARISH_FVG_LOW,rates_total,i,currHigh);
            int newIndex = ArraySize(fvgEvents);
            ArrayResize(fvgEvents,newIndex+1);
            fvgEvents[newIndex].bullish    = false;
            fvgEvents[newIndex].active     = true;
            fvgEvents[newIndex].top        = last2Low;
            fvgEvents[newIndex].bottom     = currHigh;
            fvgEvents[newIndex].leftTime   = timesChron[i-1];
            fvgEvents[newIndex].startIndex = i;
          }
        }
     }

   // Render fair value gaps after processing all bars
   if(InpShowFairValueGaps)
     {
      int fvgCount = ArraySize(fvgEvents);
      int extendBars = (int)MathMax(0,InpFVGExtend);
      long barSpacing = 0;
      if(rates_total>1)
         barSpacing = (long)(timesChron[rates_total-1]-timesChron[rates_total-2]);
      if(barSpacing<=0)
         barSpacing = PeriodSeconds(Period());

      for(int f=0; f<fvgCount; ++f)
        {
         string rectPrefix  = fvgEvents[f].bullish ? "SMC_FVG_BULL" : "SMC_FVG_BEAR";
         string labelPrefix = fvgEvents[f].bullish ? "SMC_FVG_BULL_TAG" : "SMC_FVG_BEAR_TAG";

         if(fvgEvents[f].active)
           {
            datetime rightTime = latestBarTime;
            if(extendBars>0 && barSpacing>0)
               rightTime += (datetime)(extendBars*barSpacing);

            double top    = fvgEvents[f].top;
            double bottom = fvgEvents[f].bottom;
            if(top < bottom)
              {
               double tmp = top;
               top        = bottom;
               bottom     = tmp;
              }

            color zoneColor = fvgEvents[f].bullish ? InpBullFVGColor : InpBearFVGColor;
            DrawRectangleZone(rectPrefix,f,fvgEvents[f].leftTime,rightTime,top,bottom,zoneColor);
            DrawZoneLabel(labelPrefix,f,rightTime,0.5*(top+bottom),zoneColor,fvgEvents[f].bullish ? "Bull FVG" : "Bear FVG");
           }
         else
           {
            ObjectDelete(0,BuildObjectName(rectPrefix,f));
            ObjectDelete(0,BuildObjectName(labelPrefix,f));
           }
        }
     }
   else
     {
      ObjectsDeleteAll(0,"SMC_FVG_BULL");
      ObjectsDeleteAll(0,"SMC_FVG_BEAR");
     }

   return(rates_total);
  }

//+------------------------------------------------------------------+
