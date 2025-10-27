#property copyright "SMC conversion"
#property link      ""
#property version   "1.20"
#property indicator_chart_window

/*
 * 智能交易结构（SMC）指标转换
 * - 识别 BOS / CHoCH / HHHL 等结构，并用虚线标注触发行
 * - 检测 EQH / EQL、订单块与三根蜡烛缺口（FVG）
 * - 所有输出按照既定缓冲区顺序写入数据窗口，方便脚本订阅
 * - 主要逻辑在收盘价确认后执行，避免历史回溯重绘
 */
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
   datetime  endTime;
   int       extendBars;
   bool      mitigated;
   int       id;
  };

//--- 输入参数（中文说明）
input int      InpSwingLength        = 3;   // 摆动判定长度（左右各多少根K线）
input int      InpMinEQTicks         = 3;   // 等高/等低容差（点数）
input bool     InpShowStructure      = true;   // 是否绘制 BOS/CHoCH
input bool     InpShowChoCh          = true;   // 是否显示 CHoCH 标签
input bool     InpShowSwingLabels    = false;  // 是否显示 HH/HL/LH/LL 标签
input bool     InpShowEqualLevels    = true;   // 是否检测 EQH/EQL
input int      InpEqualPivotDepth    = 2;      // EQH/EQL 回溯多少个摆动点进行比较
input int      InpEqualDetectionBars = 30;     // EQH/EQL 两次摆动之间允许的最大 K 线数
input int      InpAtrPeriod          = 200;    // ATR 过滤周期（用于订单块尺寸过滤）
input double   InpMinObAtrMultiplier = 0.5;    // 订单块最小尺寸 = ATR * 倍数，小于该值不记录
input bool     InpShowOrderBlocks    = true;   // 是否绘制订单块
input bool     InpShowFVG            = true;   // 是否绘制 FVG 区域
input int      InpMaxZones           = 3;      // 每类最多保留的区域数量
input int      InpExtendRightBars    = 100;    // 结构虚线向右延伸的 K 线数量
input int      InpFvgExtendBars      = 2;      // FVG 矩形向右延伸的 K 线数量
input color    InpBullStructureColor = clrLimeGreen;   // 多头结构颜色
input color    InpBearStructureColor = clrTomato;      // 空头结构颜色
input color    InpEqualHighColor     = clrTurquoise;   // EQH 颜色
input color    InpEqualLowColor      = clrLightCoral;  // EQL 颜色
input color    InpBearZoneColor      = clrLightPink;   // 看跌区域颜色
input color    InpFvgColor           = clrGainsboro;   // FVG 与看涨订单块颜色
input int      InpZoneOpacityActive  = 60;             // 区域未触发时透明度
input int      InpZoneOpacityMitigated = 25;           // 订单块被回测后的透明度

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
long       gLastBarSeconds      = 0;
int        gAtrHandle           = INVALID_HANDLE;   // ATR 指标句柄（订单块过滤）

Zone       gObZones[];
Zone       gFvgZones[];
SwingPoint gSwingHighHistory[];   // 记录历史摆动高点
SwingPoint gSwingLowHistory[];    // 记录历史摆动低点
double     gAtrValues[];          // ATR 数组缓存

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
   gLastBarSeconds     = 0;
   ResetSwingPoint(gLastSwingHigh);
   ResetSwingPoint(gPrevSwingHigh);
   ResetSwingPoint(gLastSwingLow);
   ResetSwingPoint(gPrevSwingLow);
   ArrayResize(gObZones,0);
   ArrayResize(gFvgZones,0);
   ArrayResize(gSwingHighHistory,0);
   ArrayResize(gSwingLowHistory,0);
   ArrayResize(gAtrValues,0);
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

void DrawStructureLine(const string prefix,const int id,const datetime fromTime,const datetime toTime,const double price,const color clr)
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
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

void RenderZone(const Zone &zone,const string prefix,const color baseColor,const int opacity,const datetime rightTime,const long barSeconds)
  {
   string rectName = BuildName(prefix+"RECT",zone.id);
   string labelName = BuildName(prefix+"LBL",zone.id);
   datetime zoneRight = rightTime;
   if(zone.extendBars>0 && barSeconds>0)
     {
      zoneRight = zone.startTime + (datetime)(barSeconds*zone.extendBars);
      if(zoneRight<=zone.startTime)
         zoneRight = zone.startTime + barSeconds;
     }
   if(zone.endTime>0)
      zoneRight = zone.endTime;
   if(ObjectFind(0,rectName)<0)
      ObjectCreate(0,rectName,OBJ_RECTANGLE,0,zone.startTime,zone.top,zoneRight,zone.bottom);
   ObjectSetInteger(0,rectName,OBJPROP_TIME,0,zone.startTime);
   ObjectSetInteger(0,rectName,OBJPROP_TIME,1,zoneRight);
   ObjectSetDouble(0,rectName,OBJPROP_PRICE,0,zone.top);
   ObjectSetDouble(0,rectName,OBJPROP_PRICE,1,zone.bottom);
   ObjectSetInteger(0,rectName,OBJPROP_FILL,true);
   ObjectSetInteger(0,rectName,OBJPROP_BACK,true);
   ObjectSetInteger(0,rectName,OBJPROP_COLOR,ColorToARGB(baseColor,opacity));
   ObjectSetInteger(0,rectName,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,rectName,OBJPROP_HIDDEN,true);

   double mid = 0.5*(zone.top+zone.bottom);
   if(ObjectFind(0,labelName)<0)
      ObjectCreate(0,labelName,OBJ_TEXT,0,zoneRight,mid);
   ObjectSetInteger(0,labelName,OBJPROP_TIME,0,zoneRight);
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

//--- 存储摆动点历史，便于 EQH/EQL 检测
void StoreSwingHistory(SwingPoint &history[],const SwingPoint &pt)
  {
   int size = ArraySize(history);
   ArrayResize(history,size+1);
   history[size] = pt;
   int maxKeep = MathMax(InpEqualPivotDepth*3,10);
   if(ArraySize(history)>maxKeep)
     {
      int shift = ArraySize(history)-maxKeep;
      for(int i=0;i<maxKeep;i++)
         history[i] = history[i+shift];
      ArrayResize(history,maxKeep);
     }
  }

//--- 检查是否形成等高结构
void CheckEqualHigh(const SwingPoint &current,const int rates_total)
  {
   if(!InpShowEqualLevels)
      return;
   double tolerance = InpMinEQTicks * _Point;
   int comparisons = 0;
   for(int i=ArraySize(gSwingHighHistory)-1; i>=0 && comparisons<InpEqualPivotDepth; --i)
     {
      const SwingPoint &candidate = gSwingHighHistory[i];
      if(InpEqualDetectionBars>0 && (current.index - candidate.index) > InpEqualDetectionBars)
         continue;
      double diff = MathAbs(candidate.price - current.price);
      if(diff <= tolerance)
        {
         RegisterEqualLevel(candidate,current,true,rates_total);
         break;
        }
      ++comparisons;
     }
  }

//--- 检查是否形成等低结构
void CheckEqualLow(const SwingPoint &current,const int rates_total)
  {
   if(!InpShowEqualLevels)
      return;
   double tolerance = InpMinEQTicks * _Point;
   int comparisons = 0;
   for(int i=ArraySize(gSwingLowHistory)-1; i>=0 && comparisons<InpEqualPivotDepth; --i)
     {
      const SwingPoint &candidate = gSwingLowHistory[i];
      if(InpEqualDetectionBars>0 && (current.index - candidate.index) > InpEqualDetectionBars)
         continue;
      double diff = MathAbs(candidate.price - current.price);
      if(diff <= tolerance)
        {
         RegisterEqualLevel(candidate,current,false,rates_total);
         break;
        }
      ++comparisons;
     }
  }

//--- 记录等高/等低结构并同步缓冲区
void RegisterEqualLevel(const SwingPoint &first,const SwingPoint &second,const bool highLevel,const int rates_total)
  {
   ++gEqualLabelId;
   color clr = highLevel ? InpEqualHighColor : InpEqualLowColor;
   DrawTextLabel("SMC_EQ",gEqualLabelId,second.time,second.price,clr,highLevel?"EQH":"EQL",highLevel?ANCHOR_UPPER:ANCHOR_LOWER);
   double levelPrice = second.price;
   if(highLevel)
     {
      SetBufferValue(gEqualHighBuffer,rates_total,first.index,levelPrice);
      SetBufferValue(gEqualHighBuffer,rates_total,second.index,levelPrice);
      gLastEqualHighPrice = levelPrice;
      gLastEqualHighIndex = second.index;
     }
   else
     {
      SetBufferValue(gEqualLowBuffer,rates_total,first.index,levelPrice);
      SetBufferValue(gEqualLowBuffer,rates_total,second.index,levelPrice);
      gLastEqualLowPrice = levelPrice;
      gLastEqualLowIndex = second.index;
     }
  }

//--- 在图表上写入结构文字并绘制触发基准的水平虚线
void MarkStructure(const SwingPoint &pivot,const datetime eventTime,const bool bullish,const bool choch)
  {
   if(!InpShowStructure)
      return;
   ++gStructureLabelId;
   color clr = bullish ? InpBullStructureColor : InpBearStructureColor;
   string text = choch?"CHoCH":"BOS";
   datetime labelTime = pivot.time + (eventTime - pivot.time)/2;
   DrawStructureLine("SMC_STRLINE",gStructureLabelId,pivot.time,eventTime,pivot.price,clr);
   DrawTextLabel("SMC_STRLBL",gStructureLabelId,labelTime,pivot.price,clr,text,bullish?ANCHOR_LOWER:ANCHOR_UPPER);
  }

//--- 根据最新结构突破生成订单块
void AddOrderBlock(const int chronoIndex,const bool bullish,const double &opens[],const double &closes[],const datetime &times[],const double &atrValues[],const int rates_total)
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
         z.endTime = 0;
         z.extendBars = InpExtendRightBars;
         z.mitigated = false;
         z.id = gNextZoneId++;
         z.top = MathMax(opens[idx],closes[idx]);
         z.bottom = MathMin(opens[idx],closes[idx]);
         double zoneSize = MathAbs(z.top - z.bottom);             // 计算订单块实体高度
         double atrValue = (idx<ArraySize(atrValues)) ? atrValues[idx] : 0.0; // 取对应 ATR
         if(atrValue>0 && zoneSize < atrValue*InpMinObAtrMultiplier)         // 如果过小则忽略
            continue;
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
         z.endTime = 0;
         z.extendBars = InpExtendRightBars;
         z.mitigated = false;
         z.id = gNextZoneId++;
         z.top = MathMax(opens[idx],closes[idx]);
         z.bottom = MathMin(opens[idx],closes[idx]);
         double zoneSize = MathAbs(z.top - z.bottom);
         double atrValue = (idx<ArraySize(atrValues)) ? atrValues[idx] : 0.0;
         if(atrValue>0 && zoneSize < atrValue*InpMinObAtrMultiplier)
            continue;
         PushZone(gObZones,z,"OB_");
         SetBufferValue(gBearishOBHighBuffer,rates_total,chronoIndex,z.top);
         SetBufferValue(gBearishOBLowBuffer,rates_total,chronoIndex,z.bottom);
         return;
        }
     }
  }

//--- 在检测到三根蜡烛缺口时登记 FVG 区域
void AddFvg(const int chronoIndex,const bool bullish,const double top,const double bottom,const datetime startTime,const datetime &times[],const int rates_total)
  {
   if(!InpShowFVG)
      return;
   Zone z;
   z.bullish = bullish;
   z.top = top;
   z.bottom = bottom;
   z.startTime = startTime;
   int startIndex = MathMax(chronoIndex-2,0);
   int extendBars = InpFvgExtendBars;
   if(extendBars<=0)
      extendBars = 1;
   int extendIndex = startIndex + extendBars;
   if(extendIndex>=rates_total)
      extendIndex = rates_total-1;
   z.endTime = times[extendIndex];
   z.extendBars = extendBars;
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

//--- 更新订单块是否被回测
void UpdateOrderBlocks(const double high,const double low,const double close)
  {
   for(int i=ArraySize(gObZones)-1;i>=0;--i)
     {
      bool remove = false;
      if(gObZones[i].bullish)
        {
         if(low <= gObZones[i].top && high >= gObZones[i].bottom)
            gObZones[i].mitigated = true;
         if(close < gObZones[i].bottom)
            remove = true;
        }
      else
        {
         if(high >= gObZones[i].bottom && low <= gObZones[i].top)
            gObZones[i].mitigated = true;
         if(close > gObZones[i].top)
            remove = true;
        }
      if(remove)
        {
         RemoveZone(gObZones,i,"OB_");
        }
     }
  }

//--- FVG 被价格回补后立即移除
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

//--- 根据最新时间绘制订单块与 FVG 矩形
void RenderZones(const datetime latestTime,const long barSeconds)
  {
   datetime rightTime = latestTime + (datetime)(InpExtendRightBars*barSeconds);
  if(InpShowFVG)
    {
      for(int i=0;i<ArraySize(gFvgZones);++i)
         RenderZone(gFvgZones[i],"FVG_",InpFvgColor,InpZoneOpacityActive,rightTime,barSeconds);
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
         RenderZone(gObZones[i],"OB_",zoneColor,opacity,rightTime,barSeconds);
        }
    }
   else
     {
      DeleteObjectByPrefix("OB_");
      ArrayResize(gObZones,0);
     }
  }

//--- indicator configuration -------------------------------------------------
//--- 配置指标缓冲区并保持数据窗口可见
void ConfigureBuffer(const int plot_index,double &buffer[],const string label,const color plotColor)
  {
   // 将数组绑定到指定的绘图索引，允许数据窗口读取值
   SetIndexBuffer(plot_index,buffer,INDICATOR_DATA);
   // 设置数组方向与时间序列一致（最新在前）
   ArraySetAsSeries(buffer,true);
   // 指定绘图类型为折线（即便实际不在图上显示，数据窗口仍可展示）
   PlotIndexSetInteger(plot_index,PLOT_DRAW_TYPE,DRAW_LINE);
   // 设置线条颜色，便于在数据窗口区分
   PlotIndexSetInteger(plot_index,PLOT_LINE_COLOR,plotColor);
   // 使用点状线型，避免在图表上形成实体线段
   PlotIndexSetInteger(plot_index,PLOT_LINE_STYLE,STYLE_DOT);
   // 线宽保持为 1，降低对图表的干扰
   PlotIndexSetInteger(plot_index,PLOT_LINE_WIDTH,1);
   // 在数据窗口显示友好名称
   PlotIndexSetString(plot_index,PLOT_LABEL,label);
   // 强制在数据窗口显示该绘图值
   PlotIndexSetInteger(plot_index,PLOT_SHOW_DATA,true);
   // 设置空值标记，用于未触发时隐藏数据
   PlotIndexSetDouble(plot_index,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   // 与上方一致，确保指标核心函数也识别空值
   SetIndexEmptyValue(plot_index,EMPTY_VALUE);
  }

int OnInit()
  {
   // 设置指标短名称，方便在图表与数据窗口显示
   IndicatorSetString(INDICATOR_SHORTNAME,"SMC Structure");
   // 指定输出小数位与当前品种一致
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);

   // 创建 ATR 指标句柄，用于后续订单块尺寸过滤
   gAtrHandle = iATR(_Symbol,_Period,InpAtrPeriod);
   if(gAtrHandle==INVALID_HANDLE)
     {
      Print("无法创建 ATR 句柄，错误码=",GetLastError());
      return(INIT_FAILED);
     }

   // 依次配置所有 16 个缓冲区，保证数据窗口顺序与规范一致
   ConfigureBuffer(BUFFER_BULLISH_BOS,gBullishBosBuffer,"Bullish BOS",InpBullStructureColor);      // 多头结构突破
   ConfigureBuffer(BUFFER_BEARISH_BOS,gBearishBosBuffer,"Bearish BOS",InpBearStructureColor);      // 空头结构突破
   ConfigureBuffer(BUFFER_BULLISH_CHOCH,gBullishChochBuffer,"Bullish CHoCH",InpBullStructureColor); // 多头 CHoCH
   ConfigureBuffer(BUFFER_BEARISH_CHOCH,gBearishChochBuffer,"Bearish CHoCH",InpBearStructureColor); // 空头 CHoCH
   ConfigureBuffer(BUFFER_BULLISH_OB_HIGH,gBullishOBHighBuffer,"Bull OB High",InpFvgColor);         // 多头订单块上沿
   ConfigureBuffer(BUFFER_BULLISH_OB_LOW,gBullishOBLowBuffer,"Bull OB Low",InpFvgColor);            // 多头订单块下沿
   ConfigureBuffer(BUFFER_BEARISH_OB_HIGH,gBearishOBHighBuffer,"Bear OB High",InpBearZoneColor);    // 空头订单块上沿
   ConfigureBuffer(BUFFER_BEARISH_OB_LOW,gBearishOBLowBuffer,"Bear OB Low",InpBearZoneColor);       // 空头订单块下沿
   ConfigureBuffer(BUFFER_BULLISH_FVG_HIGH,gBullishFvgHighBuffer,"Bullish FVG High",InpFvgColor);   // 看涨 FVG 上沿
   ConfigureBuffer(BUFFER_BULLISH_FVG_LOW,gBullishFvgLowBuffer,"Bullish FVG Low",InpFvgColor);      // 看涨 FVG 下沿
   ConfigureBuffer(BUFFER_BEARISH_FVG_HIGH,gBearishFvgHighBuffer,"Bearish FVG High",InpFvgColor);   // 看跌 FVG 上沿
   ConfigureBuffer(BUFFER_BEARISH_FVG_LOW,gBearishFvgLowBuffer,"Bearish FVG Low",InpFvgColor);      // 看跌 FVG 下沿
   ConfigureBuffer(BUFFER_EQ_HIGHS,gEqualHighBuffer,"Equal High",InpEqualHighColor);                // 等高价位
   ConfigureBuffer(BUFFER_EQ_LOWS,gEqualLowBuffer,"Equal Low",InpEqualLowColor);                   // 等低价位
   ConfigureBuffer(BUFFER_LIQUIDITY_GRAB_HIGH,gLgHighBuffer,"Liquidity Grab High",InpBearStructureColor); // 流动性抓取高点
   ConfigureBuffer(BUFFER_LIQUIDITY_GRAB_LOW,gLgLowBuffer,"Liquidity Grab Low",InpBullStructureColor);   // 流动性抓取低点

   // 重置内部状态，确保指标从干净的缓存开始运行
   ResetState();
   // 返回初始化成功
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   // 删除结构相关的文字与虚线，避免在移除指标后残留
   DeleteObjectByPrefix("SMC_STRLINE");
   DeleteObjectByPrefix("SMC_STRLBL");
   // 删除等高/等低文本标签
   DeleteObjectByPrefix("SMC_EQ");
   // 删除等高/等低辅助矩形或线段（旧版本遗留）
   DeleteObjectByPrefix("SMC_EQR");
   DeleteObjectByPrefix("SMC_EQD");
   DeleteObjectByPrefix("SMC_EQL");
   // 删除摆动点标签
   DeleteObjectByPrefix("SMC_SWING");
   // 删除流动性抓取提示
   DeleteObjectByPrefix("SMC_LG");
   // 删除订单块矩形
   DeleteObjectByPrefix("OB_");
   // 删除 FVG 矩形
   DeleteObjectByPrefix("FVG_");
   // 释放 ATR 指标资源
   if(gAtrHandle!=INVALID_HANDLE)
     {
      IndicatorRelease(gAtrHandle);
      gAtrHandle = INVALID_HANDLE;
     }
  }

//--- main calculation -------------------------------------------------------
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const int begin,
                const double &price[])
  {
   // 如果总柱数不足以计算摆动点，则直接退出
   if(rates_total<=InpSwingLength*2)
      return(0);

   // 读取历史数据（开高低收与时间）
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   if(CopyRates(_Symbol,_Period,0,rates_total,rates)<=0)
      return(prev_calculated);

   // 构造独立数组便于访问
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
   ArraySetAsSeries(gAtrValues,false);
   ArrayResize(gAtrValues,rates_total);

   // 复制数据并将索引转换为从旧到新的顺序
   for(int c=0;c<rates_total;++c)
     {
      int idx = rates_total-1-c;                         // 从末尾向前读取得到旧数据
      highs[c]  = rates[idx].high;                       // 保存最高价
      lows[c]   = rates[idx].low;                        // 保存最低价
      opens[c]  = rates[idx].open;                       // 保存开盘价
      closes[c] = rates[idx].close;                      // 保存收盘价
      times[c]  = rates[idx].time;                       // 保存时间戳
      gAtrValues[c] = 0.0;                               // 预设 ATR 值
     }

   if(gAtrHandle!=INVALID_HANDLE)
     {
      double atrRaw[];
      ArraySetAsSeries(atrRaw,true);
      int copied = CopyBuffer(gAtrHandle,0,0,rates_total,atrRaw);
      if(copied>0)
        {
         for(int c=0;c<rates_total && c<copied;++c)
           {
            int target = rates_total-1-c;         // 将最新 ATR 映射到数组末尾（对应最新 K 线）
            gAtrValues[target] = atrRaw[c];       // 其余索引依次向前排布
           }
        }
      else
         ArrayInitialize(gAtrValues,0.0);
     }

   int lastClosed = rates_total-2;
   if(lastClosed<0)
      return(prev_calculated);

   long barSeconds = PeriodSeconds(_Period);
   if(barSeconds<=0 && lastClosed>0)
      barSeconds = (long)(times[lastClosed] - times[lastClosed-1]);
   if(barSeconds<=0)
      barSeconds = 60;
   gLastBarSeconds = barSeconds;

   if(lastClosed<InpSwingLength)
      return(prev_calculated);

   if(prev_calculated==0)
     {
      ResetState();
      DeleteObjectByPrefix("SMC_STRLINE");
      DeleteObjectByPrefix("SMC_STRLBL");
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
           SwingPoint newHigh;
           newHigh.index = pivot;
           newHigh.price = highs[pivot];
           newHigh.time  = times[pivot];
           gLastSwingHigh = newHigh;
           double prevPrice = (gPrevSwingHigh.index>=0) ? gPrevSwingHigh.price : 0.0;
           RegisterSwingLabel(newHigh,true,prevPrice);
           CheckEqualHigh(newHigh,rates_total);
           StoreSwingHistory(gSwingHighHistory,newHigh);
          }
        if(IsSwingLow(lows,pivot,InpSwingLength,rates_total))
          {
           gPrevSwingLow = gLastSwingLow;
           SwingPoint newLow;
           newLow.index = pivot;
           newLow.price = lows[pivot];
           newLow.time  = times[pivot];
           gLastSwingLow = newLow;
           double prevPrice = (gPrevSwingLow.index>=0) ? gPrevSwingLow.price : 0.0;
           RegisterSwingLabel(newLow,false,prevPrice);
           CheckEqualLow(newLow,rates_total);
           StoreSwingHistory(gSwingLowHistory,newLow);
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
         AddOrderBlock(chrono,true,opens,closes,times,gAtrValues,rates_total);
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
         AddOrderBlock(chrono,false,opens,closes,times,gAtrValues,rates_total);
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
            AddFvg(chrono,true,lows[chrono],high2,times[chrono-2],times,rates_total);
         if(bearGap)
            AddFvg(chrono,false,low2,highs[chrono],times[chrono-2],times,rates_total);
        }

      UpdateOrderBlocks(high,low,close);
      UpdateFvgs(high,low);

      gLastProcessedIndex = chrono;
     }

   datetime latestTime = times[lastClosed];
   RenderZones(latestTime,gLastBarSeconds);

   return(rates_total);
  }
