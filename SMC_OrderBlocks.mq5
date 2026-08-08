//+------------------------------------------------------------------+
//|                                          SMC_OrderBlocks.mq5      |
//|  Standalone Order Block indicator extracted from the "Smart Money |
//|  Concepts" signals port (original concept & Pine Script by        |
//|  LuxAlgo, CC BY-NC-SA 4.0). This indicator isolates ONLY the      |
//|  order-block creation / mitigation logic and preserves the        |
//|  original visualization: bullish/bearish order blocks are drawn   |
//|  as circular dots (arrow code 108) and their mitigation ("break") |
//|  is drawn with arrow code 251, exactly as in the source.          |
//+------------------------------------------------------------------+
#property copyright "Standalone OB extraction. Original concept (c) LuxAlgo, CC BY-NC-SA 4.0"
#property link      "https://creativecommons.org/licenses/by-nc-sa/4.0/"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   8

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
input group "=== Order Blocks ==="
input bool                InpShowInternalOB           = true;
input bool                InpShowSwingOB              = false;
input ENUM_OB_FILTER      InpOBFilter                 = OBFILTER_ATR;
input ENUM_OB_MITIGATION  InpOBMitigation             = OBMIT_HIGHLOW;

input group "=== Structure Lengths (drive OB detection) ==="
input int                 InpInternalLength           = 5;
input int                 InpSwingLength              = 50;

input group "=== Volatility ==="
input int                 InpATRPeriod                = 200;

input group "=== Colors / Arrow Codes ==="
input color  InpColorBullOB     = clrLime;   // bullish order block dot
input color  InpColorBearOB     = clrRed;    // bearish order block dot
input color  InpColorOBBreak    = clrYellow;

//====================================================================
// BUFFERS
//====================================================================
double BufIntBullOB[];
double BufIntBearOB[];
double BufIntBullOBBreak[];
double BufIntBearOBBreak[];
double BufSwBullOB[];
double BufSwBearOB[];
double BufSwBullOBBreak[];
double BufSwBearOBBreak[];

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
   PivotPoint      swingHigh, swingLow;
   PivotPoint      internalHigh, internalLow;
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
   SetIndexBuffer(0,BufIntBullOB      ,INDICATOR_DATA);
   SetIndexBuffer(1,BufIntBearOB      ,INDICATOR_DATA);
   SetIndexBuffer(2,BufIntBullOBBreak ,INDICATOR_DATA);
   SetIndexBuffer(3,BufIntBearOBBreak ,INDICATOR_DATA);
   SetIndexBuffer(4,BufSwBullOB       ,INDICATOR_DATA);
   SetIndexBuffer(5,BufSwBearOB       ,INDICATOR_DATA);
   SetIndexBuffer(6,BufSwBullOBBreak  ,INDICATOR_DATA);
   SetIndexBuffer(7,BufSwBearOBBreak  ,INDICATOR_DATA);

   ArraySetAsSeries(BufIntBullOB,false);
   ArraySetAsSeries(BufIntBearOB,false);
   ArraySetAsSeries(BufIntBullOBBreak,false);
   ArraySetAsSeries(BufIntBearOBBreak,false);
   ArraySetAsSeries(BufSwBullOB,false);
   ArraySetAsSeries(BufSwBearOB,false);
   ArraySetAsSeries(BufSwBullOBBreak,false);
   ArraySetAsSeries(BufSwBearOBBreak,false);
   ArraySetAsSeries(g_parsedHigh,false);
   ArraySetAsSeries(g_parsedLow,false);

   SetupArrowPlot(0,"Internal Bull OB"      ,108,InpColorBullOB);
   SetupArrowPlot(1,"Internal Bear OB"      ,108,InpColorBearOB);
   SetupArrowPlot(2,"Internal Bull OB Break",251,InpColorOBBreak);
   SetupArrowPlot(3,"Internal Bear OB Break",251,InpColorOBBreak);
   SetupArrowPlot(4,"Swing Bull OB"         ,108,InpColorBullOB);
   SetupArrowPlot(5,"Swing Bear OB"         ,108,InpColorBearOB);
   SetupArrowPlot(6,"Swing Bull OB Break"   ,251,InpColorOBBreak);
   SetupArrowPlot(7,"Swing Bear OB Break"   ,251,InpColorOBBreak);

   IndicatorSetString(INDICATOR_SHORTNAME,"SMC Order Blocks");
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
   ResetPivot(st.swingHigh);
   ResetPivot(st.swingLow);
   ResetPivot(st.internalHigh);
   ResetPivot(st.internalLow);
   st.swingTrendBias=0;
   st.internalTrendBias=0;
   st.internalOBCount=0;
   st.swingOBCount=0;
   st.atr=0.0;
   st.atrSum=0.0;
   st.atrCount=0;
   st.cumTR=0.0;
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
   BufIntBullOB[i]=EMPTY_VALUE;
   BufIntBearOB[i]=EMPTY_VALUE;
   BufIntBullOBBreak[i]=EMPTY_VALUE;
   BufIntBearOBBreak[i]=EMPTY_VALUE;
   BufSwBullOB[i]=EMPTY_VALUE;
   BufSwBearOB[i]=EMPTY_VALUE;
   BufSwBullOBBreak[i]=EMPTY_VALUE;
   BufSwBearOBBreak[i]=EMPTY_VALUE;
  }

//====================================================================
// VOLATILITY (manual incremental ATR + cumulative TR, no iATR handle)
// Produces the "parsed" high/low used by order-block extreme detection.
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
// PIVOT / LEG DETECTION  (two independent instances: swing / internal)
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
// Order blocks are stored whenever a pivot high/low is crossed. This
// mirrors the source: only the OB-relevant side effects are kept
// (no BOS/CHoCH arrows are drawn here — this is an OB-only indicator).
//====================================================================
void ProcessDisplayStructure(SmcState &st,int i,bool internal,
                              const double &open[],const double &high[],const double &low[],const double &close[])
  {
   if(i<1) return;

   //--- bullish side (High pivot break) ---
   PivotPoint pHigh = internal ? st.internalHigh : st.swingHigh;
   bool extraBull = internal ? (st.internalHigh.currentLevel != st.swingHigh.currentLevel) : true;

   if(pHigh.valid && !pHigh.crossed && extraBull &&
      close[i-1] <= pHigh.currentLevel && close[i] > pHigh.currentLevel)
     {
      if(internal){ st.internalHigh.crossed=true; st.internalTrendBias=BULLISH; }
      else        { st.swingHigh.crossed=true;     st.swingTrendBias=BULLISH; }

      bool obToggle = internal ? InpShowInternalOB : InpShowSwingOB;
      if(obToggle) StoreOrderBlock(st,i,internal,BULLISH,pHigh.barIndex);
     }

   //--- bearish side (Low pivot break) ---
   PivotPoint pLow = internal ? st.internalLow : st.swingLow;
   bool extraBear = internal ? (st.internalLow.currentLevel != st.swingLow.currentLevel) : true;

   if(pLow.valid && !pLow.crossed && extraBear &&
      close[i-1] >= pLow.currentLevel && close[i] < pLow.currentLevel)
     {
      if(internal){ st.internalLow.crossed=true; st.internalTrendBias=BEARISH; }
      else        { st.swingLow.crossed=true;     st.swingTrendBias=BEARISH; }

      bool obToggle = internal ? InpShowInternalOB : InpShowSwingOB;
      if(obToggle) StoreOrderBlock(st,i,internal,BEARISH,pLow.barIndex);
     }
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

   if(InpShowInternalOB) ProcessDisplayStructure(st,i,true ,open,high,low,close);
   if(InpShowSwingOB)    ProcessDisplayStructure(st,i,false,open,high,low,close);

   if(InpShowInternalOB) ProcessOBMitigation(st,i,true ,close,high,low);
   if(InpShowSwingOB)    ProcessOBMitigation(st,i,false,close,high,low);
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
