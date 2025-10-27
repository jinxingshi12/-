#property copyright "Converted from LuxAlgo Smart Money Concepts"
#property link      "https://www.luxalgo.com"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 16
#property indicator_plots   0

enum eLegDirection
  {
   LEG_BEARISH = 0,
   LEG_BULLISH = 1
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

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   IndicatorSetString(INDICATOR_SHORTNAME,"LuxAlgo SMC");
   SetIndexStyle(0,DRAW_NONE);
   SetIndexBuffer(0,gBullishBOSBuffer,INDICATOR_DATA);
   SetIndexStyle(1,DRAW_NONE);
   SetIndexBuffer(1,gBearishBOSBuffer,INDICATOR_DATA);
   SetIndexStyle(2,DRAW_NONE);
   SetIndexBuffer(2,gBullishChoChBuffer,INDICATOR_DATA);
   SetIndexStyle(3,DRAW_NONE);
   SetIndexBuffer(3,gBearishChoChBuffer,INDICATOR_DATA);
   SetIndexStyle(4,DRAW_NONE);
   SetIndexBuffer(4,gBullishOBHighBuffer,INDICATOR_DATA);
   SetIndexStyle(5,DRAW_NONE);
   SetIndexBuffer(5,gBullishOBLowBuffer,INDICATOR_DATA);
   SetIndexStyle(6,DRAW_NONE);
   SetIndexBuffer(6,gBearishOBHighBuffer,INDICATOR_DATA);
   SetIndexStyle(7,DRAW_NONE);
   SetIndexBuffer(7,gBearishOBLowBuffer,INDICATOR_DATA);
   SetIndexStyle(8,DRAW_NONE);
   SetIndexBuffer(8,gBullishFVGHighBuffer,INDICATOR_DATA);
   SetIndexStyle(9,DRAW_NONE);
   SetIndexBuffer(9,gBullishFVGLowBuffer,INDICATOR_DATA);
   SetIndexStyle(10,DRAW_NONE);
   SetIndexBuffer(10,gBearishFVGHighBuffer,INDICATOR_DATA);
   SetIndexStyle(11,DRAW_NONE);
   SetIndexBuffer(11,gBearishFVGLowBuffer,INDICATOR_DATA);
   SetIndexStyle(12,DRAW_NONE);
   SetIndexBuffer(12,gEqualHighsBuffer,INDICATOR_DATA);
   SetIndexStyle(13,DRAW_NONE);
   SetIndexBuffer(13,gEqualLowsBuffer,INDICATOR_DATA);
   SetIndexStyle(14,DRAW_NONE);
   SetIndexBuffer(14,gLiquidityGrabHighBuffer,INDICATOR_DATA);
   SetIndexStyle(15,DRAW_NONE);
   SetIndexBuffer(15,gLiquidityGrabLowBuffer,INDICATOR_DATA);
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
      if(i>=InpEqualLength && gSwingHigh.barIndex>=0 && MathAbs(highsChron[i]-gSwingHigh.currentLevel) <= InpEqualThreshold*gATRValue[i])
        {
         SetBufferValue(gEqualHighsBuffer,rates_total,i,gSwingHigh.currentLevel);
        }
      if(i>=InpEqualLength && gSwingLow.barIndex>=0 && MathAbs(lowsChron[i]-gSwingLow.currentLevel) <= InpEqualThreshold*gATRValue[i])
        {
         SetBufferValue(gEqualLowsBuffer,rates_total,i,gSwingLow.currentLevel);
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
