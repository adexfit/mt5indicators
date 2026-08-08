//+------------------------------------------------------------------+
//|                                              SMC_Signals.mq5     |
//|  MT5 port of "Smart Money Concepts" (original concept & Pine     |
//|  Script by LuxAlgo, CC BY-NC-SA 4.0). This is an independent,    |
//|  signals-only re-implementation: no boxes/zones/MTF levels are   |
//|  drawn. Every event is exposed as an arrow buffer so it is both  |
//|  visible on chart AND readable by an EA via iCustom/CopyBuffer.  |
//+------------------------------------------------------------------+
#property copyright "Signals-only MT5 port. Original concept (c) LuxAlgo, CC BY-NC-SA 4.0"
#property link      "https://creativecommons.org/licenses/by-nc-sa/4.0/"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 24
#property indicator_plots   22

//====================================================================
// CONSTANTS
//====================================================================
#define BULLISH_LEG 1
#define BEARISH_LEG 0
#define BULLISH     1
#define BEARISH    -1
#define MAX_OB      100   // capped history of tracked (unmitigated) order blocks

//====================================================================
// ENUMS
//====================================================================
enum ENUM_STRUCT_FILTER
  {
   FILTER_ALL = 0,
   FILTER_BOS = 1,
   FILTER_CHOCH = 2
  };

enum ENUM_OB_FILTER
  {
   OBFILTER_ATR = 0,
   OBFILTER_RANGE = 1
  };

enum ENUM_OB_MITIGATION
  {
   OBMIT_CLOSE = 0,
   OBMIT_HIGHLOW = 1
  };

//====================================================================
// INPUTS
//====================================================================
input group "=== Internal Structure ==="
input bool                InpShowInternal            = true;
input ENUM_STRUCT_FILTER  InpInternalBullFilter       = FILTER_ALL;
input ENUM_STRUCT_FILTER  InpInternalBearFilter       = FILTER_ALL;
input bool                InpInternalConfluenceFilter = false;
input int                 InpInternalLength           = 5;

input group "=== Swing Structure ==="
input bool                InpShowSwing               = true;
input ENUM_STRUCT_FILTER  InpSwingBullFilter          = FILTER_ALL;
input ENUM_STRUCT_FILTER  InpSwingBearFilter          = FILTER_ALL;
input int                 InpSwingLength              = 50;

input group "=== Swing Points (HH/LL/HL/LH) ==="
input bool                InpShowSwingPoints          = false;

input group "=== Order Blocks ==="
input bool                InpShowInternalOB           = true;
input bool                InpShowSwingOB              = false;
input ENUM_OB_FILTER      InpOBFilter                 = OBFILTER_ATR;
input ENUM_OB_MITIGATION  InpOBMitigation             = OBMIT_HIGHLOW;

input group "=== Equal Highs / Lows ==="
input bool                InpShowEqualHL              = true;
input int                 InpEqualHLLength            = 3;
input double              InpEqualHLThreshold         = 0.1;

input group "=== Fair Value Gaps ==="
input bool                InpShowFVG                  = false;
input bool                InpFVGAutoThreshold         = true;

input group "=== Volatility ==="
input int                 InpATRPeriod                = 200;

input group "=== Colors / Arrow Codes ==="
input color  InpColorBullBOS    = clrLime;
input color  InpColorBullCHoCH  = clrDodgerBlue;
input color  InpColorBearBOS    = clrRed;
input color  InpColorBearCHoCH  = clrOrange;
input color  InpColorSwingHigh  = clrRed;
input color  InpColorSwingLow   = clrLime;
input color  InpColorBullOB     = clrLime;   // bullish order block dot
input color  InpColorBearOB     = clrRed;    // bearish order block dot
input color  InpColorOBBreak    = clrYellow;
input color  InpColorEqualHL    = clrSilver;
input color  InpColorFVGBull    = clrAqua;
input color  InpColorFVGBear    = clrMagenta;

//====================================================================
// BUFFERS  (0..21 = visible arrow signals, 22..23 = EA-only, hidden)
//====================================================================
double BufIntBullBOS[];
double BufIntBullCHoCH[];
double BufIntBearBOS[];
double BufIntBearCHoCH[];
double BufSwBullBOS[];
double BufSwBullCHoCH[];
double BufSwBearBOS[];
double BufSwBearCHoCH[];
double BufSwingHighPivot[];
double BufSwingLowPivot[];
double BufIntBullOB[];
double BufIntBearOB[];
double BufIntBullOBBreak[];
double BufIntBearOBBreak[];
double BufSwBullOB[];
double BufSwBearOB[];
double BufSwBullOBBreak[];
double BufSwBearOBBreak[];
double BufEQH[];
double BufEQL[];
double BufBullFVG[];
double BufBearFVG[];
double BufInternalTrend[];   // -1 / 0 / +1, EA use only (not plotted)
double BufSwingTrend[];      // -1 / 0 / +1, EA use only (not plotted)

//====================================================================
// DATA STRUCTURES
//====================================================================
struct PivotPoint
  {
   double   currentLevel;
   double   lastLevel;
   bool     crossed;
   datetime barTime;
   int      barIndex;
   bool     valid;
  };

struct OrderBlockInfo
  {
   double   high;
   double   low;
   datetime barTime;
   int      bias;
  };

struct SmcState
  {
   int             legSwing;
   int             legInternal;
   int             legEqual;
   PivotPoint      swingHigh, swingLow;
   PivotPoint      internalHigh, internalLow;
   PivotPoint      equalHigh, equalLow;
   int             swingTrendBias;
   int             internalTrendBias;
   OrderBlockInfo  internalOBs[MAX_OB];
   int             internalOBCount;
   OrderBlockInfo  swingOBs[MAX_OB];
   int             swingOBCount;
   double          atr;
   double          atrSum;
   int             atrCount;
   double          cumTR;
   double          cumAbsDelta;
  };

SmcState g_confirmed;   // permanent state, as of the last fully closed bar
SmcState g_working;     // scratch copy re-derived from g_confirmed every tick
                         // for the still-forming bar (never permanently committed
                         // until the bar actually closes)
int      g_prevRatesTotal = 0;

double   g_parsedHigh[];
double   g_parsedLow[];

//====================================================================
// INIT
//====================================================================
void SetupArrowPlot(int idx,const string label,int arrowCode,color clr)
  {
   PlotIndexSetInteger(idx,PLOT_DRAW_TYPE,DRAW_ARROW);
   PlotIndexSetInteger(idx,PLOT_ARROW,arrowCode);
   PlotIndexSetInteger(idx,PLOT_LINE_COLOR,clr);
   PlotIndexSetInteger(idx,PLOT_LINE_WIDTH,1);
   PlotIndexSetString(idx,PLOT_LABEL,label);
   PlotIndexSetDouble(idx,PLOT_EMPTY_VALUE,EMPTY_VALUE);
  }

int OnInit()
  {
   SetIndexBuffer(0 ,BufIntBullBOS     ,INDICATOR_DATA);
   SetIndexBuffer(1 ,BufIntBullCHoCH   ,INDICATOR_DATA);
   SetIndexBuffer(2 ,BufIntBearBOS     ,INDICATOR_DATA);
   SetIndexBuffer(3 ,BufIntBearCHoCH   ,INDICATOR_DATA);
   SetIndexBuffer(4 ,BufSwBullBOS      ,INDICATOR_DATA);
   SetIndexBuffer(5 ,BufSwBullCHoCH    ,INDICATOR_DATA);
   SetIndexBuffer(6 ,BufSwBearBOS      ,INDICATOR_DATA);
   SetIndexBuffer(7 ,BufSwBearCHoCH    ,INDICATOR_DATA);
   SetIndexBuffer(8 ,BufSwingHighPivot ,INDICATOR_DATA);
   SetIndexBuffer(9 ,BufSwingLowPivot  ,INDICATOR_DATA);
   SetIndexBuffer(10,BufIntBullOB      ,INDICATOR_DATA);
   SetIndexBuffer(11,BufIntBearOB      ,INDICATOR_DATA);
   SetIndexBuffer(12,BufIntBullOBBreak ,INDICATOR_DATA);
   SetIndexBuffer(13,BufIntBearOBBreak ,INDICATOR_DATA);
   SetIndexBuffer(14,BufSwBullOB       ,INDICATOR_DATA);
   SetIndexBuffer(15,BufSwBearOB       ,INDICATOR_DATA);
   SetIndexBuffer(16,BufSwBullOBBreak  ,INDICATOR_DATA);
   SetIndexBuffer(17,BufSwBearOBBreak  ,INDICATOR_DATA);
   SetIndexBuffer(18,BufEQH            ,INDICATOR_DATA);
   SetIndexBuffer(19,BufEQL            ,INDICATOR_DATA);
   SetIndexBuffer(20,BufBullFVG        ,INDICATOR_DATA);
   SetIndexBuffer(21,BufBearFVG        ,INDICATOR_DATA);
   SetIndexBuffer(22,BufInternalTrend  ,INDICATOR_CALCULATIONS);
   SetIndexBuffer(23,BufSwingTrend     ,INDICATOR_CALCULATIONS);

   ArraySetAsSeries(BufIntBullBOS,false);
   ArraySetAsSeries(BufIntBullCHoCH,false);
   ArraySetAsSeries(BufIntBearBOS,false);
   ArraySetAsSeries(BufIntBearCHoCH,false);
   ArraySetAsSeries(BufSwBullBOS,false);
   ArraySetAsSeries(BufSwBullCHoCH,false);
   ArraySetAsSeries(BufSwBearBOS,false);
   ArraySetAsSeries(BufSwBearCHoCH,false);
   ArraySetAsSeries(BufSwingHighPivot,false);
   ArraySetAsSeries(BufSwingLowPivot,false);
   ArraySetAsSeries(BufIntBullOB,false);
   ArraySetAsSeries(BufIntBearOB,false);
   ArraySetAsSeries(BufIntBullOBBreak,false);
   ArraySetAsSeries(BufIntBearOBBreak,false);
   ArraySetAsSeries(BufSwBullOB,false);
   ArraySetAsSeries(BufSwBearOB,false);
   ArraySetAsSeries(BufSwBullOBBreak,false);
   ArraySetAsSeries(BufSwBearOBBreak,false);
   ArraySetAsSeries(BufEQH,false);
   ArraySetAsSeries(BufEQL,false);
   ArraySetAsSeries(BufBullFVG,false);
   ArraySetAsSeries(BufBearFVG,false);
   ArraySetAsSeries(BufInternalTrend,false);
   ArraySetAsSeries(BufSwingTrend,false);
   ArraySetAsSeries(g_parsedHigh,false);
   ArraySetAsSeries(g_parsedLow,false);

   SetupArrowPlot(0 ,"Internal Bull BOS"   ,233,InpColorBullBOS);
   SetupArrowPlot(1 ,"Internal Bull CHoCH" ,233,InpColorBullCHoCH);
   SetupArrowPlot(2 ,"Internal Bear BOS"   ,234,InpColorBearBOS);
   SetupArrowPlot(3 ,"Internal Bear CHoCH" ,234,InpColorBearCHoCH);
   SetupArrowPlot(4 ,"Swing Bull BOS"      ,233,InpColorBullBOS);
   SetupArrowPlot(5 ,"Swing Bull CHoCH"    ,233,InpColorBullCHoCH);
   SetupArrowPlot(6 ,"Swing Bear BOS"      ,234,InpColorBearBOS);
   SetupArrowPlot(7 ,"Swing Bear CHoCH"    ,234,InpColorBearCHoCH);
   SetupArrowPlot(8 ,"Swing High Point"    ,159,InpColorSwingHigh);
   SetupArrowPlot(9 ,"Swing Low Point"     ,159,InpColorSwingLow);
   SetupArrowPlot(10,"Internal Bull OB"    ,108,InpColorBullOB);
   SetupArrowPlot(11,"Internal Bear OB"    ,108,InpColorBearOB);
   SetupArrowPlot(12,"Internal Bull OB Break",251,InpColorOBBreak);
   SetupArrowPlot(13,"Internal Bear OB Break",251,InpColorOBBreak);
   SetupArrowPlot(14,"Swing Bull OB"       ,108,InpColorBullOB);
   SetupArrowPlot(15,"Swing Bear OB"       ,108,InpColorBearOB);
   SetupArrowPlot(16,"Swing Bull OB Break" ,251,InpColorOBBreak);
   SetupArrowPlot(17,"Swing Bear OB Break" ,251,InpColorOBBreak);
   SetupArrowPlot(18,"Equal High (EQH)"    ,158,InpColorEqualHL);
   SetupArrowPlot(19,"Equal Low (EQL)"     ,158,InpColorEqualHL);
   SetupArrowPlot(20,"Bullish FVG"         ,116,InpColorFVGBull);
   SetupArrowPlot(21,"Bearish FVG"         ,116,InpColorFVGBear);

   IndicatorSetString(INDICATOR_SHORTNAME,"SMC Signals");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);

   ResetState(g_confirmed);
   g_prevRatesTotal = 0;

   return(INIT_SUCCEEDED);
  }

//====================================================================
// STATE RESET
//====================================================================
void ResetPivot(PivotPoint &p)
  {
   p.currentLevel=0.0;
   p.lastLevel=0.0;
   p.crossed=false;
   p.barTime=0;
   p.barIndex=-1;
   p.valid=false;
  }

void ResetState(SmcState &st)
  {
   st.legSwing=0;
   st.legInternal=0;
   st.legEqual=0;
   ResetPivot(st.swingHigh);
   ResetPivot(st.swingLow);
   ResetPivot(st.internalHigh);
   ResetPivot(st.internalLow);
   ResetPivot(st.equalHigh);
   ResetPivot(st.equalLow);
   st.swingTrendBias=0;
   st.internalTrendBias=0;
   st.internalOBCount=0;
   st.swingOBCount=0;
   st.atr=0.0;
   st.atrSum=0.0;
   st.atrCount=0;
   st.cumTR=0.0;
   st.cumAbsDelta=0.0;
  }

//====================================================================
// SMALL HELPERS
//====================================================================
double Highest(const double &arr[],int startIdx,int endIdx)
  {
   double m=arr[startIdx];
   for(int k=startIdx+1;k<=endIdx;k++) if(arr[k]>m) m=arr[k];
   return m;
  }

double Lowest(const double &arr[],int startIdx,int endIdx)
  {
   double m=arr[startIdx];
   for(int k=startIdx+1;k<=endIdx;k++) if(arr[k]<m) m=arr[k];
   return m;
  }

void ClearBar(int i)
  {
   BufIntBullBOS[i]=EMPTY_VALUE;
   BufIntBullCHoCH[i]=EMPTY_VALUE;
   BufIntBearBOS[i]=EMPTY_VALUE;
   BufIntBearCHoCH[i]=EMPTY_VALUE;
   BufSwBullBOS[i]=EMPTY_VALUE;
   BufSwBullCHoCH[i]=EMPTY_VALUE;
   BufSwBearBOS[i]=EMPTY_VALUE;
   BufSwBearCHoCH[i]=EMPTY_VALUE;
   BufSwingHighPivot[i]=EMPTY_VALUE;
   BufSwingLowPivot[i]=EMPTY_VALUE;
   BufIntBullOB[i]=EMPTY_VALUE;
   BufIntBearOB[i]=EMPTY_VALUE;
   BufIntBullOBBreak[i]=EMPTY_VALUE;
   BufIntBearOBBreak[i]=EMPTY_VALUE;
   BufSwBullOB[i]=EMPTY_VALUE;
   BufSwBearOB[i]=EMPTY_VALUE;
   BufSwBullOBBreak[i]=EMPTY_VALUE;
   BufSwBearOBBreak[i]=EMPTY_VALUE;
   BufEQH[i]=EMPTY_VALUE;
   BufEQL[i]=EMPTY_VALUE;
   BufBullFVG[i]=EMPTY_VALUE;
   BufBearFVG[i]=EMPTY_VALUE;
   BufInternalTrend[i]=0.0;
   BufSwingTrend[i]=0.0;
  }

//====================================================================
// VOLATILITY (manual incremental ATR + cumulative TR, no iATR handle)
//====================================================================
void UpdateVolatility(SmcState &st,int i,const double &high[],const double &low[],const double &close[])
  {
   double tr;
   if(i==0)
      tr=high[i]-low[i];
   else
      tr=MathMax(high[i]-low[i],MathMax(MathAbs(high[i]-close[i-1]),MathAbs(low[i]-close[i-1])));

   st.cumTR += tr;

   if(st.atrCount < InpATRPeriod)
     {
      st.atrSum += tr;
      st.atrCount++;
      st.atr = st.atrSum/st.atrCount;
     }
   else
     {
      st.atr = (st.atr*(InpATRPeriod-1)+tr)/InpATRPeriod;
     }

   double volatilityMeasure = (InpOBFilter==OBFILTER_ATR) ? st.atr : (i>0 ? st.cumTR/i : st.atr);
   bool highVolatilityBar = (high[i]-low[i]) >= (2.0*volatilityMeasure);

   g_parsedHigh[i] = highVolatilityBar ? low[i]  : high[i];
   g_parsedLow[i]  = highVolatilityBar ? high[i] : low[i];
  }

//====================================================================
// PIVOT / LEG DETECTION  (three independent instances: swing / internal / equal)
//====================================================================
int ComputeLegAfter(int legBefore,int i,int size,const double &high[],const double &low[])
  {
   double hh=Highest(high,i-size+1,i);
   double ll=Lowest(low,i-size+1,i);
   bool newLegHigh = high[i-size] > hh;
   bool newLegLow  = low[i-size]  < ll;
   int leg=legBefore;
   if(newLegHigh) leg=BEARISH_LEG;
   else if(newLegLow) leg=BULLISH_LEG;
   return leg;
  }

void ProcessSwingPivot(SmcState &st,int i,const double &high[],const double &low[],const datetime &time[])
  {
   int size=InpSwingLength;
   if(i<size) return;
   int legBefore=st.legSwing;
   int legAfter=ComputeLegAfter(legBefore,i,size,high,low);
   bool newPivot=(legAfter!=legBefore);
   if(newPivot)
     {
      if(legAfter==BULLISH_LEG)
        {
         PivotPoint p=st.swingLow;
         p.lastLevel=p.currentLevel;
         p.currentLevel=low[i-size];
         p.crossed=false;
         p.barTime=time[i-size];
         p.barIndex=i-size;
         if(InpShowSwingPoints && p.valid)
            BufSwingLowPivot[i-size]=p.currentLevel;
         p.valid=true;
         st.swingLow=p;
        }
      else
        {
         PivotPoint p=st.swingHigh;
         p.lastLevel=p.currentLevel;
         p.currentLevel=high[i-size];
         p.crossed=false;
         p.barTime=time[i-size];
         p.barIndex=i-size;
         if(InpShowSwingPoints && p.valid)
            BufSwingHighPivot[i-size]=p.currentLevel;
         p.valid=true;
         st.swingHigh=p;
        }
     }
   st.legSwing=legAfter;
  }

void ProcessInternalPivot(SmcState &st,int i,const double &high[],const double &low[],const datetime &time[])
  {
   int size=InpInternalLength;
   if(i<size) return;
   int legBefore=st.legInternal;
   int legAfter=ComputeLegAfter(legBefore,i,size,high,low);
   bool newPivot=(legAfter!=legBefore);
   if(newPivot)
     {
      if(legAfter==BULLISH_LEG)
        {
         PivotPoint p=st.internalLow;
         p.lastLevel=p.currentLevel;
         p.currentLevel=low[i-size];
         p.crossed=false;
         p.barTime=time[i-size];
         p.barIndex=i-size;
         p.valid=true;
         st.internalLow=p;
        }
      else
        {
         PivotPoint p=st.internalHigh;
         p.lastLevel=p.currentLevel;
         p.currentLevel=high[i-size];
         p.crossed=false;
         p.barTime=time[i-size];
         p.barIndex=i-size;
         p.valid=true;
         st.internalHigh=p;
        }
     }
   st.legInternal=legAfter;
  }

void ProcessEqualPivot(SmcState &st,int i,const double &high[],const double &low[],const datetime &time[])
  {
   int size=InpEqualHLLength;
   if(i<size) return;
   int legBefore=st.legEqual;
   int legAfter=ComputeLegAfter(legBefore,i,size,high,low);
   bool newPivot=(legAfter!=legBefore);
   if(newPivot)
     {
      if(legAfter==BULLISH_LEG)
        {
         PivotPoint p=st.equalLow;
         if(p.valid && MathAbs(p.currentLevel-low[i-size]) < InpEqualHLThreshold*st.atr)
            BufEQL[i]=low[i-size];
         p.lastLevel=p.currentLevel;
         p.currentLevel=low[i-size];
         p.crossed=false;
         p.barTime=time[i-size];
         p.barIndex=i-size;
         p.valid=true;
         st.equalLow=p;
        }
      else
        {
         PivotPoint p=st.equalHigh;
         if(p.valid && MathAbs(p.currentLevel-high[i-size]) < InpEqualHLThreshold*st.atr)
            BufEQH[i]=high[i-size];
         p.lastLevel=p.currentLevel;
         p.currentLevel=high[i-size];
         p.crossed=false;
         p.barTime=time[i-size];
         p.barIndex=i-size;
         p.valid=true;
         st.equalHigh=p;
        }
     }
   st.legEqual=legAfter;
  }

//====================================================================
// ORDER BLOCKS
//====================================================================
void InsertOB(OrderBlockInfo &arr[],int &count,const OrderBlockInfo &ob)
  {
   if(count>=MAX_OB) count=MAX_OB-1; // drop oldest (last slot) to make room
   for(int k=count;k>0;k--) arr[k]=arr[k-1];
   arr[0]=ob;
   count++;
  }

void StoreOrderBlock(SmcState &st,int i,bool internal,int bias,int pivotBarIndex)
  {
   if(pivotBarIndex<0 || pivotBarIndex>i) return;
   int extremeIdx=pivotBarIndex;
   if(bias==BEARISH)
     {
      double best=g_parsedHigh[pivotBarIndex];
      for(int k=pivotBarIndex;k<=i;k++)
         if(g_parsedHigh[k]>best){ best=g_parsedHigh[k]; extremeIdx=k; }
     }
   else
     {
      double best=g_parsedLow[pivotBarIndex];
      for(int k=pivotBarIndex;k<=i;k++)
         if(g_parsedLow[k]<best){ best=g_parsedLow[k]; extremeIdx=k; }
     }

   OrderBlockInfo ob;
   ob.high=g_parsedHigh[extremeIdx];
   ob.low=g_parsedLow[extremeIdx];
   ob.bias=bias;

   if(internal)
     {
      InsertOB(st.internalOBs,st.internalOBCount,ob);
      if(bias==BULLISH) BufIntBullOB[extremeIdx]=ob.low;
      else               BufIntBearOB[extremeIdx]=ob.high;
     }
   else
     {
      InsertOB(st.swingOBs,st.swingOBCount,ob);
      if(bias==BULLISH) BufSwBullOB[extremeIdx]=ob.low;
      else               BufSwBearOB[extremeIdx]=ob.high;
     }
  }

void ProcessOBMitigation(SmcState &st,int i,bool internal,const double &close[],const double &high[],const double &low[])
  {
   double bearSrc = (InpOBMitigation==OBMIT_CLOSE) ? close[i] : high[i];
   double bullSrc = (InpOBMitigation==OBMIT_CLOSE) ? close[i] : low[i];

   if(internal)
     {
      OrderBlockInfo survivors[MAX_OB];
      int survCount=0;
      for(int k=0;k<st.internalOBCount;k++)
        {
         OrderBlockInfo ob=st.internalOBs[k];
         bool mitigated=false;
         if(ob.bias==BEARISH && bearSrc>ob.high){ mitigated=true; BufIntBearOBBreak[i]=ob.high; }
         else if(ob.bias==BULLISH && bullSrc<ob.low){ mitigated=true; BufIntBullOBBreak[i]=ob.low; }
         if(!mitigated){ survivors[survCount]=ob; survCount++; }
        }
      for(int k=0;k<survCount;k++) st.internalOBs[k]=survivors[k];
      st.internalOBCount=survCount;
     }
   else
     {
      OrderBlockInfo survivors[MAX_OB];
      int survCount=0;
      for(int k=0;k<st.swingOBCount;k++)
        {
         OrderBlockInfo ob=st.swingOBs[k];
         bool mitigated=false;
         if(ob.bias==BEARISH && bearSrc>ob.high){ mitigated=true; BufSwBearOBBreak[i]=ob.high; }
         else if(ob.bias==BULLISH && bullSrc<ob.low){ mitigated=true; BufSwBullOBBreak[i]=ob.low; }
         if(!mitigated){ survivors[survCount]=ob; survCount++; }
        }
      for(int k=0;k<survCount;k++) st.swingOBs[k]=survivors[k];
      st.swingOBCount=survCount;
     }
  }

//====================================================================
// STRUCTURE BREAKS (BOS / CHoCH)
//====================================================================
void ProcessDisplayStructure(SmcState &st,int i,bool internal,
                              const double &open[],const double &high[],const double &low[],const double &close[])
  {
   if(i<1) return;

   bool bullishBar=true, bearishBar=true;
   if(InpInternalConfluenceFilter)
     {
      double wick = high[i]-MathMax(close[i],open[i]);
      double ref  = MathMin(close[i], open[i]-low[i]);
      bullishBar = wick > ref;
      bearishBar = wick < ref;
     }

   //--- bullish side (High pivot break) ---
   PivotPoint pHigh = internal ? st.internalHigh : st.swingHigh;
   int trendBias      = internal ? st.internalTrendBias : st.swingTrendBias;
   bool extraBull = internal ? (st.internalHigh.currentLevel != st.swingHigh.currentLevel && bullishBar) : true;

   if(pHigh.valid && !pHigh.crossed && extraBull &&
      close[i-1] <= pHigh.currentLevel && close[i] > pHigh.currentLevel)
     {
      bool isCHoCH = (trendBias==BEARISH);
      if(internal){ st.internalHigh.crossed=true; st.internalTrendBias=BULLISH; }
      else        { st.swingHigh.crossed=true;     st.swingTrendBias=BULLISH; }

      bool showIt = internal ? InpShowInternal : InpShowSwing;
      ENUM_STRUCT_FILTER filt = internal ? InpInternalBullFilter : InpSwingBullFilter;
      bool passFilter = (filt==FILTER_ALL) || (filt==FILTER_BOS && !isCHoCH) || (filt==FILTER_CHOCH && isCHoCH);

      if(showIt && passFilter)
        {
         if(internal) { if(isCHoCH) BufIntBullCHoCH[i]=pHigh.currentLevel; else BufIntBullBOS[i]=pHigh.currentLevel; }
         else         { if(isCHoCH) BufSwBullCHoCH[i]=pHigh.currentLevel;  else BufSwBullBOS[i]=pHigh.currentLevel;  }
        }

      bool obToggle = internal ? InpShowInternalOB : InpShowSwingOB;
      if(obToggle) StoreOrderBlock(st,i,internal,BULLISH,pHigh.barIndex);
     }

   //--- bearish side (Low pivot break) ---
   PivotPoint pLow = internal ? st.internalLow : st.swingLow;
   trendBias = internal ? st.internalTrendBias : st.swingTrendBias;
   bool extraBear = internal ? (st.internalLow.currentLevel != st.swingLow.currentLevel && bearishBar) : true;

   if(pLow.valid && !pLow.crossed && extraBear &&
      close[i-1] >= pLow.currentLevel && close[i] < pLow.currentLevel)
     {
      bool isCHoCH = (trendBias==BULLISH);
      if(internal){ st.internalLow.crossed=true; st.internalTrendBias=BEARISH; }
      else        { st.swingLow.crossed=true;     st.swingTrendBias=BEARISH; }

      bool showIt = internal ? InpShowInternal : InpShowSwing;
      ENUM_STRUCT_FILTER filt = internal ? InpInternalBearFilter : InpSwingBearFilter;
      bool passFilter = (filt==FILTER_ALL) || (filt==FILTER_BOS && !isCHoCH) || (filt==FILTER_CHOCH && isCHoCH);

      if(showIt && passFilter)
        {
         if(internal) { if(isCHoCH) BufIntBearCHoCH[i]=pLow.currentLevel; else BufIntBearBOS[i]=pLow.currentLevel; }
         else         { if(isCHoCH) BufSwBearCHoCH[i]=pLow.currentLevel;  else BufSwBearBOS[i]=pLow.currentLevel;  }
        }

      bool obToggle = internal ? InpShowInternalOB : InpShowSwingOB;
      if(obToggle) StoreOrderBlock(st,i,internal,BEARISH,pLow.barIndex);
     }
  }

//====================================================================
// FAIR VALUE GAPS (current timeframe only, formation signal only)
//====================================================================
void ProcessFVG(SmcState &st,int i,const double &open[],const double &high[],const double &low[],const double &close[])
  {
   if(i<2) return;
   double lastClose=close[i-1], lastOpen=open[i-1];
   double currentHigh=high[i], currentLow=low[i];
   double last2High=high[i-2], last2Low=low[i-2];

   double barDeltaPercent = (lastOpen!=0.0) ? (lastClose-lastOpen)/(lastOpen*100.0) : 0.0;
   st.cumAbsDelta += MathAbs(barDeltaPercent);
   double threshold = InpFVGAutoThreshold ? (st.cumAbsDelta/(double)MathMax(i,1)*2.0) : 0.0;

   bool bullFVG = (currentLow>last2High) && (lastClose>last2High) && (barDeltaPercent>threshold);
   bool bearFVG = (currentHigh<last2Low) && (lastClose<last2Low) && ((-barDeltaPercent)>threshold);

   if(bullFVG) BufBullFVG[i] = (currentLow+last2High)/2.0;
   if(bearFVG) BufBearFVG[i] = (currentHigh+last2Low)/2.0;
  }

//====================================================================
// PER-BAR ORCHESTRATION (mirrors the original script's execution order)
//====================================================================
void ProcessBar(SmcState &st,int i,const datetime &time[],
                 const double &open[],const double &high[],const double &low[],const double &close[])
  {
   UpdateVolatility(st,i,high,low,close);

   ProcessSwingPivot(st,i,high,low,time);
   ProcessInternalPivot(st,i,high,low,time);
   if(InpShowEqualHL) ProcessEqualPivot(st,i,high,low,time);

   if(InpShowInternal || InpShowInternalOB) ProcessDisplayStructure(st,i,true ,open,high,low,close);
   if(InpShowSwing    || InpShowSwingOB)    ProcessDisplayStructure(st,i,false,open,high,low,close);

   if(InpShowInternalOB) ProcessOBMitigation(st,i,true ,close,high,low);
   if(InpShowSwingOB)    ProcessOBMitigation(st,i,false,close,high,low);

   if(InpShowFVG) ProcessFVG(st,i,open,high,low,close);

   BufInternalTrend[i] = (double)st.internalTrendBias;
   BufSwingTrend[i]    = (double)st.swingTrendBias;
  }

//====================================================================
// MAIN CALCULATION
//====================================================================
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
   if(rates_total<3) return(0);

   ArrayResize(g_parsedHigh,rates_total);
   ArrayResize(g_parsedLow,rates_total);

   int startClosed;

   if(prev_calculated==0)
     {
      ResetState(g_confirmed);
      g_prevRatesTotal=0;
      startClosed=0;
      for(int i=0;i<rates_total;i++) ClearBar(i);
     }
   else
     {
      startClosed = prev_calculated;
      if(startClosed>rates_total) startClosed=rates_total;

      bool newBarFormed = (g_prevRatesTotal>0 && rates_total>g_prevRatesTotal);
      if(newBarFormed)
         g_confirmed = g_working; // promote the bar that just closed
     }

   // Process any fully-closed bars not yet committed to g_confirmed
   for(int i=startClosed;i<rates_total-1;i++)
     {
      ClearBar(i);
      ProcessBar(g_confirmed,i,time,open,high,low,close);
     }

   // Process the still-forming last bar on a scratch copy, every tick,
   // without ever permanently mutating g_confirmed until the bar closes.
   int last=rates_total-1;
   ClearBar(last);
   g_working = g_confirmed;
   ProcessBar(g_working,last,time,open,high,low,close);

   g_prevRatesTotal = rates_total;

   return(rates_total);
  }
//+------------------------------------------------------------------+
