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

void ResizeBuffer(double &buffer[],const int size)
  {
   ArrayResize(buffer,size);
   ArrayInitialize(buffer,EMPTY_VALUE);
   ArraySetAsSeries(buffer,true);
  }

void ResetBuffers(const int rates_total)
  {
   ResizeBuffer(gBullishBOSBuffer,rates_total);
   ResizeBuffer(gBearishBOSBuffer,rates_total);
   ResizeBuffer(gBullishChoChBuffer,rates_total);
   ResizeBuffer(gBearishChoChBuffer,rates_total);
   ResizeBuffer(gBullishOBHighBuffer,rates_total);
   ResizeBuffer(gBullishOBLowBuffer,rates_total);
   ResizeBuffer(gBearishOBHighBuffer,rates_total);
   ResizeBuffer(gBearishOBLowBuffer,rates_total);
   ResizeBuffer(gBullishFVGHighBuffer,rates_total);
   ResizeBuffer(gBullishFVGLowBuffer,rates_total);
   ResizeBuffer(gBearishFVGHighBuffer,rates_total);
   ResizeBuffer(gBearishFVGLowBuffer,rates_total);
   ResizeBuffer(gEqualHighsBuffer,rates_total);
   ResizeBuffer(gEqualLowsBuffer,rates_total);
   ResizeBuffer(gLiquidityGrabHighBuffer,rates_total);
   ResizeBuffer(gLiquidityGrabLowBuffer,rates_total);
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

   ConfigureBuffer(BUFFER_BULLISH_BOS,gBullishBOSBuffer,DRAW_ARROW,clrLime,1,233,"Bullish BOS");
   ConfigureBuffer(BUFFER_BEARISH_BOS,gBearishBOSBuffer,DRAW_ARROW,clrRed,1,234,"Bearish BOS");
   ConfigureBuffer(BUFFER_BULLISH_CHOCH,gBullishChoChBuffer,DRAW_ARROW,clrSpringGreen,1,233,"Bullish CHoCH");
   ConfigureBuffer(BUFFER_BEARISH_CHOCH,gBearishChoChBuffer,DRAW_ARROW,clrTomato,1,234,"Bearish CHoCH");

   ConfigureBuffer(BUFFER_BULLISH_OB_HIGH,gBullishOBHighBuffer,DRAW_LINE,clrDeepSkyBlue,2,0,"Bullish OB High");
   ConfigureBuffer(BUFFER_BULLISH_OB_LOW,gBullishOBLowBuffer,DRAW_LINE,clrDeepSkyBlue,2,0,"Bullish OB Low");
   ConfigureBuffer(BUFFER_BEARISH_OB_HIGH,gBearishOBHighBuffer,DRAW_LINE,clrOrangeRed,2,0,"Bearish OB High");
   ConfigureBuffer(BUFFER_BEARISH_OB_LOW,gBearishOBLowBuffer,DRAW_LINE,clrOrangeRed,2,0,"Bearish OB Low");

   ConfigureBuffer(BUFFER_BULLISH_FVG_HIGH,gBullishFVGHighBuffer,DRAW_LINE,clrMediumSeaGreen,1,0,"Bullish FVG High");
   ConfigureBuffer(BUFFER_BULLISH_FVG_LOW,gBullishFVGLowBuffer,DRAW_LINE,clrMediumSeaGreen,1,0,"Bullish FVG Low");
   ConfigureBuffer(BUFFER_BEARISH_FVG_HIGH,gBearishFVGHighBuffer,DRAW_LINE,clrCrimson,1,0,"Bearish FVG High");
   ConfigureBuffer(BUFFER_BEARISH_FVG_LOW,gBearishFVGLowBuffer,DRAW_LINE,clrCrimson,1,0,"Bearish FVG Low");

   ConfigureBuffer(BUFFER_EQ_HIGHS,gEqualHighsBuffer,DRAW_ARROW,clrDodgerBlue,1,234,"Equal Highs");
   ConfigureBuffer(BUFFER_EQ_LOWS,gEqualLowsBuffer,DRAW_ARROW,clrDodgerBlue,1,233,"Equal Lows");
   ConfigureBuffer(BUFFER_LIQUIDITY_GRAB_HIGH,gLiquidityGrabHighBuffer,DRAW_ARROW,clrGold,1,234,"Liquidity Grab High");
   ConfigureBuffer(BUFFER_LIQUIDITY_GRAB_LOW,gLiquidityGrabLowBuffer,DRAW_ARROW,clrGold,1,233,"Liquidity Grab Low");
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

   ResetBuffers(rates_total);

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

   ResetState();

   for(int i=0;i<rates_total;++i)
     {
      int swingLeg    = LegDirection(highsChron,lowsChron,i,InpSwingLength);
      int internalLeg = LegDirection(highsChron,lowsChron,i,InpInternalLength);

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
         gInternalHigh.crossed = true;
         gInternalTrend.bias   = 1;
         SetBufferValue(gBullishBOSBuffer,rates_total,i,gInternalHigh.currentLevel);
        }
      if(gInternalLow.barIndex>=0 && !gInternalLow.crossed && closesChron[i] < gInternalLow.currentLevel)
        {
         gInternalLow.crossed = true;
         gInternalTrend.bias  = -1;
         SetBufferValue(gBearishBOSBuffer,rates_total,i,gInternalLow.currentLevel);
        }

      // Swing structures
      if(gSwingHigh.barIndex>=0 && !gSwingHigh.crossed && closesChron[i] > gSwingHigh.currentLevel)
        {
         gSwingHigh.crossed = true;
         bool choch = (gSwingTrend.bias==-1);
         gSwingTrend.bias = 1;
         if(choch)
            SetBufferValue(gBullishChoChBuffer,rates_total,i,gSwingHigh.currentLevel);
         else
            SetBufferValue(gBullishBOSBuffer,rates_total,i,gSwingHigh.currentLevel);

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
               SetBufferValue(gBullishOBHighBuffer,rates_total,i,obHigh);
               SetBufferValue(gBullishOBLowBuffer,rates_total,i,obLow);
              }
           }
        }

      if(gSwingLow.barIndex>=0 && !gSwingLow.crossed && closesChron[i] < gSwingLow.currentLevel)
        {
         gSwingLow.crossed = true;
         bool choch = (gSwingTrend.bias==1);
         gSwingTrend.bias = -1;
         if(choch)
            SetBufferValue(gBearishChoChBuffer,rates_total,i,gSwingLow.currentLevel);
         else
            SetBufferValue(gBearishBOSBuffer,rates_total,i,gSwingLow.currentLevel);

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
               SetBufferValue(gBearishOBHighBuffer,rates_total,i,obHigh);
               SetBufferValue(gBearishOBLowBuffer,rates_total,i,obLow);
              }
           }
        }

      // Equal highs / lows detection
      bool equalHighDetected = false;
      bool equalLowDetected  = false;
      if(i>=InpEqualLength && gSwingHigh.barIndex>=0 && MathAbs(highsChron[i]-gSwingHigh.currentLevel) <= InpEqualThreshold*gATRValue[i])
        {
         SetBufferValue(gEqualHighsBuffer,rates_total,i,gSwingHigh.currentLevel);
         gLastEqualHigh      = gSwingHigh.currentLevel;
         gLastEqualHighIndex = i;
         equalHighDetected   = true;
        }
      if(i>=InpEqualLength && gSwingLow.barIndex>=0 && MathAbs(lowsChron[i]-gSwingLow.currentLevel) <= InpEqualThreshold*gATRValue[i])
        {
         SetBufferValue(gEqualLowsBuffer,rates_total,i,gSwingLow.currentLevel);
         gLastEqualLow      = gSwingLow.currentLevel;
         gLastEqualLowIndex = i;
         equalLowDetected   = true;
        }

      if(!equalHighDetected && gLastEqualHighIndex>=0 && highsChron[i] > gLastEqualHigh && closesChron[i] < gLastEqualHigh)
        {
         SetBufferValue(gLiquidityGrabHighBuffer,rates_total,i,gLastEqualHigh);
         gLastEqualHighIndex = -1;
        }
      if(!equalLowDetected && gLastEqualLowIndex>=0 && lowsChron[i] < gLastEqualLow && closesChron[i] > gLastEqualLow)
        {
         SetBufferValue(gLiquidityGrabLowBuffer,rates_total,i,gLastEqualLow);
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
         int    extendBars = (int)MathMax(0,InpFVGExtend);

         bool bullishFVG = currLow > last2High && lastClose > last2High && (lastClose-lastOpen) > threshold;
         bool bearishFVG = currHigh < last2Low && lastClose < last2Low && (lastOpen-lastClose) > threshold;

         if(bullishFVG)
           {
            for(int k=0;k<=extendBars && i+k<rates_total;++k)
              {
               SetBufferValue(gBullishFVGHighBuffer,rates_total,i+k,currLow);
               SetBufferValue(gBullishFVGLowBuffer,rates_total,i+k,last2High);
              }
           }
         if(bearishFVG)
           {
            for(int k=0;k<=extendBars && i+k<rates_total;++k)
              {
               SetBufferValue(gBearishFVGHighBuffer,rates_total,i+k,currHigh);
               SetBufferValue(gBearishFVGLowBuffer,rates_total,i+k,last2Low);
              }
           }
        }
     }

   return(rates_total);
  }

//+------------------------------------------------------------------+
