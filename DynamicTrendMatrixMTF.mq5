//+------------------------------------------------------------------+
//|                                  DynamicTrendMatrixMTF.mq5        |
//|   Standalone multi-timeframe "Uptrick: Dynamic Trend Matrix".     |
//|   Contains its OWN copy of the full calculation engine (no        |
//|   iCustom, no dependency on any other compiled indicator).        |
//|                                                                    |
//|   - Select any timeframe via InpTimeframe.                        |
//|   - If InpTimeframe is LOWER than the chart's period, the chart's |
//|     own period is used instead (never errors, never downsamples). |
//|   - If InpTimeframe is HIGHER than the chart's period, the engine |
//|     is run natively on that higher timeframe's own bars (fetched  |
//|     via CopyTime/Open/High/Low/Close) and the results are mapped  |
//|     onto the current chart 1 HTF-bar -> N chart-bars.             |
//|   - Because the SAME engine code runs in both cases, output is    |
//|     bit-for-bit identical to running the single-timeframe DTM     |
//|     indicator directly on that timeframe's chart.                 |
//|   - All EA-relevant values (incl. buy/sell arrows + trend state)  |
//|     are exposed as Data Window buffers.                           |
//|   License: CC BY-SA 4.0 (inherited from source)                   |
//+------------------------------------------------------------------+
#property copyright "Port of Uptrick: Dynamic Trend Matrix (Standalone MTF)"
#property link      "https://creativecommons.org/licenses/by-sa/4.0/"
#property version   "1.00"
#property indicator_chart_window

#property indicator_buffers 20
#property indicator_plots   18

//--- Plot 0: Basis (adaptive trend basis) - COLOR by trend
#property indicator_label1  "Basis"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  C'92,240,215',C'179,42,195',clrGray
#property indicator_width1  1
//--- Plot 1: Upper band
#property indicator_label2  "UpperBand"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDimGray
#property indicator_style2  STYLE_DOT
//--- Plot 2: Lower band
#property indicator_label3  "LowerBand"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDimGray
#property indicator_style3  STYLE_DOT
//--- Plot 3: Upper outer band
#property indicator_label4  "UpperOuter"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrGray
#property indicator_style4  STYLE_DOT
//--- Plot 4: Lower outer band
#property indicator_label5  "LowerOuter"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrGray
#property indicator_style5  STYLE_DOT
//--- Plot 5: Trail - COLOR by trend
#property indicator_label6  "Trail"
#property indicator_type6   DRAW_COLOR_LINE
#property indicator_color6  C'92,240,215',C'179,42,195',clrGray
#property indicator_width6  2
//--- Plot 6: Long arrow
#property indicator_label7  "LongArrow"
#property indicator_type7   DRAW_ARROW
#property indicator_color7  C'92,240,215'
#property indicator_width7  2
//--- Plot 7: Short arrow
#property indicator_label8  "ShortArrow"
#property indicator_type8   DRAW_ARROW
#property indicator_color8  C'179,42,195'
#property indicator_width8  2
//--- Plots 8-17: DRAW_NONE data-window buffers (EA read)
#property indicator_label9  "TrendState"
#property indicator_type9   DRAW_NONE
#property indicator_label10 "TrendStrength"
#property indicator_type10  DRAW_NONE
#property indicator_label11 "BullPressure"
#property indicator_type11  DRAW_NONE
#property indicator_label12 "BearPressure"
#property indicator_type12  DRAW_NONE
#property indicator_label13 "LongSignal"
#property indicator_type13  DRAW_NONE
#property indicator_label14 "ShortSignal"
#property indicator_type14  DRAW_NONE
#property indicator_label15 "ATR"
#property indicator_type15  DRAW_NONE
#property indicator_label16 "TP1"
#property indicator_type16  DRAW_NONE
#property indicator_label17 "TP2"
#property indicator_type17  DRAW_NONE
#property indicator_label18 "TP3"
#property indicator_type18  DRAW_NONE

//--- color index convention (buy=green, sell=magenta, neutral=gray)
#define COL_BULL    0
#define COL_BEAR    1
#define COL_NEUTRAL 2

//--- TP mode enum
enum ENUM_TP_MODE
  {
   TP_RISK_FROM_TRAIL = 0, // Risk From Trail
   TP_ATR_FROM_ENTRY  = 1  // ATR From Entry
  };

//--- Inputs ---
input ENUM_TIMEFRAMES    InpTimeframe      = PERIOD_CURRENT; // Indicator Timeframe
input ENUM_APPLIED_PRICE InpSource         = PRICE_CLOSE;    // Source
input int                InpFastLen        = 8;              // Fast Length
input int                InpBaseLen        = 21;             // Base Length
input int                InpSlowLen        = 55;             // Slow Length
input int                InpSlopeLen       = 5;              // Slope Length
input int                InpSmoothLen      = 3;              // Smoothing
input int                InpAtrLen         = 10;             // ATR Length
input double             InpAtrMult        = 2.0;            // ATR Multiplier
input bool               InpConfirmOnClose = true;           // Confirm Signals On Bar Close
input ENUM_TP_MODE       InpTPMode         = TP_RISK_FROM_TRAIL; // TP Calculation
input int                InpTPCount        = 3;              // TP Count (1..3)
input double             InpTP1Mult        = 1.0;            // TP1 Multiplier
input double             InpTP2Mult        = 2.0;            // TP2 Multiplier
input double             InpTP3Mult        = 3.0;            // TP3 Multiplier
input bool               InpShowBands      = false;          // Show Bands
input bool               InpShowOuter      = false;          // Show Outer Bands
input bool               InpShowTrail      = true;           // Show Trail
input bool               InpShowArrows     = true;           // Show Signal Arrows

//--- Display buffers (drawn / Data Window) ---
double BasisBuf[];
double BasisColBuf[];
double UpperBuf[];
double LowerBuf[];
double UpperOuterBuf[];
double LowerOuterBuf[];
double TrailBuf[];
double TrailColBuf[];
double LongArrowBuf[];
double ShortArrowBuf[];
double TrendStateBuf[];
double TrendStrengthBuf[];
double BullPressureBuf[];
double BearPressureBuf[];
double LongSignalBuf[];
double ShortSignalBuf[];
double AtrBuf[];
double TP1Buf[];
double TP2Buf[];
double TP3Buf[];

//--- Engine (internal calculation) buffers. NOT indicator buffers -----
//--- these hold the full recursive state for whichever "source" bars  -
//--- the engine is running on (either the chart's own bars, or the    -
//--- higher timeframe's own bars).                                    -
double E_Fast[], E_Basis[], E_Slow[], E_SpreadSm[], E_SlopeSm[], E_Atr[];
double E_UpperRaw[], E_LowerRaw[], E_Upper[], E_Lower[], E_UpperOuter[], E_LowerOuter[];
double E_TrailRaw[], E_Trail[];
double E_TrendState[], E_TrendStrength[], E_BullP[], E_BearP[];
double E_LongSig[], E_ShortSig[], E_ActiveSide[];
double E_TP1[], E_TP2[], E_TP3[];
double E_BasisCol[], E_TrailCol[];

//--- Higher-timeframe source bars (only populated/used when the        -
//--- effective timeframe differs from the chart's own period) ---------
datetime hTime[];
double   hOpen[], hHigh[], hLow[], hClose[];

//--- alphas / derived params
double aF, aB, aS, aSm;
const double aBand  = 2.0/(4.0+1.0);
const double aTrail = 2.0/(5.0+1.0);
int    tpCount;

//--- mode state
ENUM_TIMEFRAMES g_tf;       // effective source timeframe (never lower than chart period)
bool            g_sameTF;   // true => engine runs directly on chart bars
int             g_srcPrevCalculated = 0; // engine's own incremental cursor for HTF mode

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0 ,BasisBuf        ,INDICATOR_DATA);
   SetIndexBuffer(1 ,BasisColBuf     ,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2 ,UpperBuf        ,INDICATOR_DATA);
   SetIndexBuffer(3 ,LowerBuf        ,INDICATOR_DATA);
   SetIndexBuffer(4 ,UpperOuterBuf   ,INDICATOR_DATA);
   SetIndexBuffer(5 ,LowerOuterBuf   ,INDICATOR_DATA);
   SetIndexBuffer(6 ,TrailBuf        ,INDICATOR_DATA);
   SetIndexBuffer(7 ,TrailColBuf     ,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(8 ,LongArrowBuf    ,INDICATOR_DATA);
   SetIndexBuffer(9 ,ShortArrowBuf   ,INDICATOR_DATA);
   SetIndexBuffer(10,TrendStateBuf   ,INDICATOR_DATA);
   SetIndexBuffer(11,TrendStrengthBuf,INDICATOR_DATA);
   SetIndexBuffer(12,BullPressureBuf ,INDICATOR_DATA);
   SetIndexBuffer(13,BearPressureBuf ,INDICATOR_DATA);
   SetIndexBuffer(14,LongSignalBuf   ,INDICATOR_DATA);
   SetIndexBuffer(15,ShortSignalBuf  ,INDICATOR_DATA);
   SetIndexBuffer(16,AtrBuf          ,INDICATOR_DATA);
   SetIndexBuffer(17,TP1Buf          ,INDICATOR_DATA);
   SetIndexBuffer(18,TP2Buf          ,INDICATOR_DATA);
   SetIndexBuffer(19,TP3Buf          ,INDICATOR_DATA);

   PlotIndexSetInteger(6,PLOT_ARROW,233); // up
   PlotIndexSetInteger(7,PLOT_ARROW,234); // down
   PlotIndexSetInteger(6,PLOT_ARROW_SHIFT,10);
   PlotIndexSetInteger(7,PLOT_ARROW_SHIFT,-10);
   for(int p=0;p<18;p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   aF  = 2.0/(InpFastLen +1.0);
   aB  = 2.0/(InpBaseLen +1.0);
   aS  = 2.0/(InpSlowLen +1.0);
   aSm = 2.0/(InpSmoothLen+1.0);
   tpCount = (int)MathMax(1,MathMin(3,InpTPCount));

   //--- Resolve effective source timeframe once (guard: never lower than chart) ---
   g_tf = InpTimeframe;
   if(g_tf==PERIOD_CURRENT) g_tf=_Period;
   if(PeriodSeconds(g_tf) < PeriodSeconds(_Period)) g_tf=_Period;
   g_sameTF = (g_tf==_Period);
   g_srcPrevCalculated = 0;

   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   string nm = g_sameTF ? "DTM" : ("DTM MTF ["+EnumToString(g_tf)+"]");
   if(!g_sameTF && g_tf!=InpTimeframe && InpTimeframe!=PERIOD_CURRENT)
      nm = "DTM MTF ["+EnumToString(g_tf)+", fallback from "+EnumToString(InpTimeframe)+"]";
   IndicatorSetString(INDICATOR_SHORTNAME,nm);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
int TrendColor(const int trend)
  {
   if(trend==1)  return COL_BULL;
   if(trend==-1) return COL_BEAR;
   return COL_NEUTRAL;
  }

//+------------------------------------------------------------------+
double GetPrice(const int i,const double &o[],const double &h[],
                const double &l[],const double &c[])
  {
   switch(InpSource)
     {
      case PRICE_OPEN:     return o[i];
      case PRICE_HIGH:     return h[i];
      case PRICE_LOW:      return l[i];
      case PRICE_MEDIAN:   return (h[i]+l[i])/2.0;
      case PRICE_TYPICAL:  return (h[i]+l[i]+c[i])/3.0;
      case PRICE_WEIGHTED: return (h[i]+l[i]+2.0*c[i])/4.0;
      default:             return c[i];
     }
  }

//+------------------------------------------------------------------+
//| Resize all engine (internal state) arrays to n. ArrayResize       |
//| preserves existing content when growing, so recursion (i-1)       |
//| across calls stays intact.                                        |
//+------------------------------------------------------------------+
void ResizeEngine(const int n)
  {
   ArrayResize(E_Fast,n);      ArrayResize(E_Basis,n);     ArrayResize(E_Slow,n);
   ArrayResize(E_SpreadSm,n);  ArrayResize(E_SlopeSm,n);   ArrayResize(E_Atr,n);
   ArrayResize(E_UpperRaw,n);  ArrayResize(E_LowerRaw,n);
   ArrayResize(E_Upper,n);     ArrayResize(E_Lower,n);
   ArrayResize(E_UpperOuter,n);ArrayResize(E_LowerOuter,n);
   ArrayResize(E_TrailRaw,n);  ArrayResize(E_Trail,n);
   ArrayResize(E_TrendState,n);ArrayResize(E_TrendStrength,n);
   ArrayResize(E_BullP,n);     ArrayResize(E_BearP,n);
   ArrayResize(E_LongSig,n);   ArrayResize(E_ShortSig,n);  ArrayResize(E_ActiveSide,n);
   ArrayResize(E_TP1,n);       ArrayResize(E_TP2,n);       ArrayResize(E_TP3,n);
   ArrayResize(E_BasisCol,n);  ArrayResize(E_TrailCol,n);
  }

//+------------------------------------------------------------------+
//| Core engine step, computed for source-bar index i. This is a      |
//| verbatim port of the single-timeframe engine's per-bar logic, so  |
//| output is identical regardless of which "source" (chart bars or   |
//| HTF bars) it is fed.                                               |
//+------------------------------------------------------------------+
void ComputeEngineBar(const int i,const double &o[],const double &h[],
                      const double &l[],const double &c[],const bool allowed)
  {
   double price = GetPrice(i,o,h,l,c);

   if(i==0)
     {
      E_Fast[0]=price; E_Basis[0]=price; E_Slow[0]=price;
      E_SpreadSm[0]=0.0; E_SlopeSm[0]=0.0;
      E_Atr[0]=h[0]-l[0];

      double up = E_Basis[0]+E_Atr[0]*InpAtrMult;
      double lo = E_Basis[0]-E_Atr[0]*InpAtrMult;
      E_UpperRaw[0]=up; E_LowerRaw[0]=lo;
      E_Upper[0]=up;    E_Lower[0]=lo;
      E_UpperOuter[0]=E_Basis[0]+E_Atr[0]*InpAtrMult*1.45;
      E_LowerOuter[0]=E_Basis[0]-E_Atr[0]*InpAtrMult*1.45;

      E_TrendState[0]=0;
      E_BasisCol[0]=COL_NEUTRAL;
      E_TrailCol[0]=COL_NEUTRAL;
      E_TrailRaw[0]=E_Basis[0];
      E_Trail[0]=E_Basis[0];
      E_TrendStrength[0]=0;
      E_BullP[0]=0; E_BearP[0]=0;
      E_LongSig[0]=0; E_ShortSig[0]=0;
      E_ActiveSide[0]=0;
      E_TP1[0]=EMPTY_VALUE; E_TP2[0]=EMPTY_VALUE; E_TP3[0]=EMPTY_VALUE;
      return;
     }

   // --- Base EMAs (recursive) ---
   E_Fast[i]  = aF*price + (1.0-aF)*E_Fast[i-1];
   E_Basis[i] = aB*price + (1.0-aB)*E_Basis[i-1];
   E_Slow[i]  = aS*price + (1.0-aS)*E_Slow[i-1];

   // --- Spread + smoothing ---
   double spreadRaw = E_Fast[i]-E_Slow[i];
   E_SpreadSm[i] = aSm*spreadRaw + (1.0-aSm)*E_SpreadSm[i-1];

   // --- Slope + smoothing ---
   double slopeRaw = 0.0;
   if(i>=InpSlopeLen)
      slopeRaw = E_Basis[i]-E_Basis[i-InpSlopeLen];
   E_SlopeSm[i] = aSm*slopeRaw + (1.0-aSm)*E_SlopeSm[i-1];

   // --- ATR (Wilder/RMA on true range) ---
   double tr = MathMax(h[i]-l[i],
               MathMax(MathAbs(h[i]-c[i-1]),
                       MathAbs(l[i]-c[i-1])));
   double n = (double)InpAtrLen;
   E_Atr[i] = (E_Atr[i-1]*(n-1.0)+tr)/n;
   double atr = E_Atr[i];

   // --- Strength ---
   double strengthRaw = (atr==0.0)?0.0:MathAbs(E_SpreadSm[i])/atr;
   strengthRaw = MathMax(0.0,MathMin(3.0,strengthRaw));
   E_TrendStrength[i] = strengthRaw/3.0;

   // --- Pressure ---
   bool bullP = (E_Fast[i]>E_Basis[i]) && (E_Basis[i]>E_Slow[i]) && (E_SlopeSm[i]>0.0);
   bool bearP = (E_Fast[i]<E_Basis[i]) && (E_Basis[i]<E_Slow[i]) && (E_SlopeSm[i]<0.0);
   E_BullP[i]=bullP?1:0;
   E_BearP[i]=bearP?1:0;

   // --- Raw bands ---
   double upRaw = E_Basis[i]+atr*InpAtrMult;
   double loRaw = E_Basis[i]-atr*InpAtrMult;
   E_UpperRaw[i]=upRaw; E_LowerRaw[i]=loRaw;

   // --- Smoothed bands (EMA 4) ---
   E_Upper[i]      = aBand*upRaw + (1.0-aBand)*E_Upper[i-1];
   E_Lower[i]      = aBand*loRaw + (1.0-aBand)*E_Lower[i-1];
   E_UpperOuter[i] = aBand*(E_Basis[i]+atr*InpAtrMult*1.45) + (1.0-aBand)*E_UpperOuter[i-1];
   E_LowerOuter[i] = aBand*(E_Basis[i]-atr*InpAtrMult*1.45) + (1.0-aBand)*E_LowerOuter[i-1];

   // --- Trail / trend engine ---
   int prevTrend = (int)E_TrendState[i-1];

   bool rawLongFlip  = (c[i] > E_UpperRaw[i-1]) && (prevTrend != 1);
   bool rawShortFlip = (c[i] < E_LowerRaw[i-1]) && (prevTrend != -1);
   bool longSig  = rawLongFlip  && allowed;
   bool shortSig = rawShortFlip && allowed;

   int    trend = prevTrend;
   double trailRaw;
   if(longSig)
     { trend=1;  trailRaw=loRaw; }
   else if(shortSig)
     { trend=-1; trailRaw=upRaw; }
   else
     {
      if(prevTrend==1)
         trailRaw = MathMax(E_TrailRaw[i-1],loRaw);
      else if(prevTrend==-1)
         trailRaw = MathMin(E_TrailRaw[i-1],upRaw);
      else
         trailRaw = E_Basis[i];
     }
   E_TrendState[i]=trend;
   E_TrailRaw[i]=trailRaw;
   E_Trail[i] = aTrail*trailRaw + (1.0-aTrail)*E_Trail[i-1];

   // --- Trend colors (buy=green, sell=magenta, neutral=gray) ---
   int col = TrendColor(trend);
   E_BasisCol[i] = col;
   E_TrailCol[i] = col;

   // --- Signal flags ---
   E_LongSig[i]  = longSig ?1:0;
   E_ShortSig[i] = shortSig?1:0;

   // --- TP engine (levels carried forward while a side is active) ---
   double side = E_ActiveSide[i-1];
   double t1=E_TP1[i-1], t2=E_TP2[i-1], t3=E_TP3[i-1];
   if(longSig)
     {
      side=1;
      double entry=c[i];
      double risk =(InpTPMode==TP_RISK_FROM_TRAIL)
                   ? MathMax(c[i]-loRaw,_Point) : atr;
      t1=entry+risk*InpTP1Mult;
      t2=entry+risk*InpTP2Mult;
      t3=entry+risk*InpTP3Mult;
     }
   else if(shortSig)
     {
      side=-1;
      double entry=c[i];
      double risk =(InpTPMode==TP_RISK_FROM_TRAIL)
                   ? MathMax(upRaw-c[i],_Point) : atr;
      t1=entry-risk*InpTP1Mult;
      t2=entry-risk*InpTP2Mult;
      t3=entry-risk*InpTP3Mult;
     }
   E_ActiveSide[i]=side;
   E_TP1[i]= (tpCount>=1)? t1 : EMPTY_VALUE;
   E_TP2[i]= (tpCount>=2)? t2 : EMPTY_VALUE;
   E_TP3[i]= (tpCount>=3)? t3 : EMPTY_VALUE;
  }

//+------------------------------------------------------------------+
//| Copy the most recent `count` bars of tf into the tail of the      |
//| ascending (oldest-first) destination arrays, which are already    |
//| sized to their final length.                                      |
//+------------------------------------------------------------------+
bool CopyHtfTail(const ENUM_TIMEFRAMES tf,const int count)
  {
   if(count<=0) return true;
   datetime tt[]; double oo[],hh[],ll[],cc[];
   ArraySetAsSeries(tt,true); ArraySetAsSeries(oo,true);
   ArraySetAsSeries(hh,true); ArraySetAsSeries(ll,true); ArraySetAsSeries(cc,true);

   if(CopyTime(_Symbol,tf,0,count,tt)  !=count) return false;
   if(CopyOpen(_Symbol,tf,0,count,oo)  !=count) return false;
   if(CopyHigh(_Symbol,tf,0,count,hh)  !=count) return false;
   if(CopyLow(_Symbol,tf,0,count,ll)   !=count) return false;
   if(CopyClose(_Symbol,tf,0,count,cc) !=count) return false;

   int total = ArraySize(hTime);
   for(int k=0;k<count;k++)
     {
      int dst = total-1-k; // tt[0] is the most recent bar -> goes to the last index
      hTime[dst]=tt[k]; hOpen[dst]=oo[k]; hHigh[dst]=hh[k]; hLow[dst]=ll[k]; hClose[dst]=cc[k];
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Binary search: greatest index in ascending hTime[] with           |
//| hTime[idx] <= t. Returns -1 if t precedes the first source bar.   |
//+------------------------------------------------------------------+
int FindHtfIndex(const datetime t,const int n)
  {
   if(n<=0 || t<hTime[0]) return -1;
   int lo=0, hi=n-1, ans=0;
   while(lo<=hi)
     {
      int mid=(lo+hi)/2;
      if(hTime[mid]<=t){ ans=mid; lo=mid+1; }
      else hi=mid-1;
     }
   return ans;
  }

//+------------------------------------------------------------------+
//| Write engine output at source index srcIdx into display buffers   |
//| at chart index i. loPrice/hiPrice are the CURRENT chart bar's     |
//| low/high, used for arrow placement (so arrows always sit on the   |
//| chart's own candle even when sourced from a higher timeframe).    |
//+------------------------------------------------------------------+
void WriteDisplay(const int i,const int srcIdx,const bool firstOfBar,
                  const double loPrice,const double hiPrice)
  {
   if(srcIdx<0)
     {
      BasisBuf[i]=EMPTY_VALUE; UpperBuf[i]=EMPTY_VALUE; LowerBuf[i]=EMPTY_VALUE;
      UpperOuterBuf[i]=EMPTY_VALUE; LowerOuterBuf[i]=EMPTY_VALUE; TrailBuf[i]=EMPTY_VALUE;
      BasisColBuf[i]=COL_NEUTRAL; TrailColBuf[i]=COL_NEUTRAL;
      LongArrowBuf[i]=EMPTY_VALUE; ShortArrowBuf[i]=EMPTY_VALUE;
      TrendStateBuf[i]=0; TrendStrengthBuf[i]=0;
      BullPressureBuf[i]=0; BearPressureBuf[i]=0;
      LongSignalBuf[i]=0; ShortSignalBuf[i]=0; AtrBuf[i]=EMPTY_VALUE;
      TP1Buf[i]=EMPTY_VALUE; TP2Buf[i]=EMPTY_VALUE; TP3Buf[i]=EMPTY_VALUE;
      return;
     }

   BasisBuf[i]        = E_Basis[srcIdx];
   UpperBuf[i]        = E_Upper[srcIdx];
   LowerBuf[i]        = E_Lower[srcIdx];
   UpperOuterBuf[i]   = E_UpperOuter[srcIdx];
   LowerOuterBuf[i]   = E_LowerOuter[srcIdx];
   TrailBuf[i]        = E_Trail[srcIdx];
   BasisColBuf[i]     = E_BasisCol[srcIdx];
   TrailColBuf[i]     = E_TrailCol[srcIdx];
   TrendStateBuf[i]   = E_TrendState[srcIdx];
   TrendStrengthBuf[i]= E_TrendStrength[srcIdx];
   BullPressureBuf[i] = E_BullP[srcIdx];
   BearPressureBuf[i] = E_BearP[srcIdx];
   LongSignalBuf[i]   = E_LongSig[srcIdx];
   ShortSignalBuf[i]  = E_ShortSig[srcIdx];
   AtrBuf[i]          = E_Atr[srcIdx];
   TP1Buf[i]          = E_TP1[srcIdx];
   TP2Buf[i]          = E_TP2[srcIdx];
   TP3Buf[i]          = E_TP3[srcIdx];

   double atr = E_Atr[srcIdx];
   double gap = atr*0.75;
   bool showLong  = InpShowArrows && firstOfBar && E_LongSig[srcIdx] >0.5;
   bool showShort = InpShowArrows && firstOfBar && E_ShortSig[srcIdx]>0.5;
   LongArrowBuf[i]  = showLong ? (loPrice-gap) : EMPTY_VALUE;
   ShortArrowBuf[i] = showShort? (hiPrice+gap) : EMPTY_VALUE;

   if(!InpShowBands){ UpperBuf[i]=EMPTY_VALUE; LowerBuf[i]=EMPTY_VALUE; }
   if(!InpShowBands || !InpShowOuter){ UpperOuterBuf[i]=EMPTY_VALUE; LowerOuterBuf[i]=EMPTY_VALUE; }
   if(!InpShowTrail){ TrailBuf[i]=EMPTY_VALUE; }
  }

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
   if(rates_total<2) return(0);

   int start = (prev_calculated==0) ? 0 : prev_calculated-1;

   //================================================================
   // MODE A: effective source timeframe == chart's own period.
   // Engine runs directly on the chart's own bars -> output is
   // identical to the single-timeframe indicator by construction.
   //================================================================
   if(g_sameTF)
     {
      ResizeEngine(rates_total);
      for(int i=start;i<rates_total;i++)
        {
         bool allowed = (!InpConfirmOnClose) || (i<rates_total-1);
         ComputeEngineBar(i,open,high,low,close,allowed);
        }
      for(int i=start;i<rates_total;i++)
         WriteDisplay(i,i,true,low[i],high[i]);

      return(rates_total);
     }

   //================================================================
   // MODE B: effective source timeframe is HIGHER than the chart.
   // Fetch/refresh the HTF's own bars, run the SAME engine on them,
   // then map each chart bar to the HTF bar whose period it falls
   // inside of.
   //================================================================
   int htfBarsNow = Bars(_Symbol,g_tf);
   if(htfBarsNow<=1)
      return(prev_calculated); // HTF history not ready yet, retry next tick

   int oldBars   = ArraySize(hTime);
   int copyFrom  = (oldBars>0) ? oldBars-1 : 0; // always refresh the last (possibly forming) bar
   int copyCount = htfBarsNow - copyFrom;

   ArrayResize(hTime ,htfBarsNow);
   ArrayResize(hOpen ,htfBarsNow);
   ArrayResize(hHigh ,htfBarsNow);
   ArrayResize(hLow  ,htfBarsNow);
   ArrayResize(hClose,htfBarsNow);

   if(!CopyHtfTail(g_tf,copyCount))
      return(prev_calculated); // data momentarily unavailable, retry next tick

   ResizeEngine(htfBarsNow);
   int hStart = (g_srcPrevCalculated==0) ? 0 : MathMin(g_srcPrevCalculated-1,htfBarsNow-1);
   for(int j=hStart;j<htfBarsNow;j++)
     {
      bool allowed = (!InpConfirmOnClose) || (j<htfBarsNow-1);
      ComputeEngineBar(j,hOpen,hHigh,hLow,hClose,allowed);
     }
   g_srcPrevCalculated = htfBarsNow;

   // Re-stamp every chart bar that maps to a recomputed HTF bar. Signals are
   // confirmed on the HTF bar's CLOSE (allowed = j<htfBarsNow-1), which only
   // becomes true AFTER that bar's chart bars were first drawn while it was
   // still forming (flag=0). Without walking the display start back to the
   // first chart bar of the earliest recomputed HTF bar, confirm-on-close
   // flips (arrows + Long/Short signal flags) would never reach the chart
   // buffers -> no arrows on the chart and nothing for an EA to read.
   int dispStart = start;
   datetime redrawOpen = hTime[hStart];
   while(dispStart>0 && time[dispStart-1]>=redrawOpen)
      dispStart--;

   int prevMappedIdx = -2;
   if(dispStart>0)
      prevMappedIdx = FindHtfIndex(time[dispStart-1],htfBarsNow);

   for(int i=dispStart;i<rates_total;i++)
     {
      int hIdx = FindHtfIndex(time[i],htfBarsNow);
      bool firstOfBar = (hIdx!=prevMappedIdx);
      WriteDisplay(i,hIdx,firstOfBar,low[i],high[i]);
      prevMappedIdx = hIdx;
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
