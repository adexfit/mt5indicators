//+------------------------------------------------------------------+
//|                              DynamicTrendMatrixMTF_Flat.mq5       |
//|   Flat trend version - shows trend as a colored horizontal line   |
//|   in a separate sub-window with arrows above/below the line.      |
//|   Uses the same trend detection logic as DynamicTrendMatrixMTF.   |
//+------------------------------------------------------------------+
#property copyright "Flat Trend Version of DTM MTF"
#property link      "https://creativecommons.org/licenses/by-sa/4.0/"
#property version   "1.00"
#property indicator_separate_window

#property indicator_buffers 14
#property indicator_plots   3

//--- Plot 0: Flat trend line - COLOR by trend
#property indicator_label1  "TrendLine"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrLime,clrRed,clrGray
#property indicator_width1  3
//--- Plot 1: Long arrow
#property indicator_label2  "LongArrow"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_width2  2
//--- Plot 2: Short arrow
#property indicator_label3  "ShortArrow"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrRed
#property indicator_width3  2

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
input bool               InpShowArrows     = true;           // Show Signal Arrows
input double             InpLineLevel      = 1.0;            // Trend Line Level
input double             InpArrowGap       = 0.3;            // Arrow Gap from Line

//--- Display buffers (drawn / Data Window) ---
double TrendLineBuf[];
double TrendLineColBuf[];
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

//--- Engine (internal calculation) buffers
double E_Fast[], E_Basis[], E_Slow[], E_SpreadSm[], E_SlopeSm[], E_Atr[];
double E_UpperRaw[], E_LowerRaw[], E_Upper[], E_Lower[];
double E_TrailRaw[], E_Trail[];
double E_TrendState[], E_TrendStrength[], E_BullP[], E_BearP[];
double E_LongSig[], E_ShortSig[], E_ActiveSide[];
double E_TP1[], E_TP2[], E_TP3[];

//--- Higher-timeframe source bars
datetime hTime[];
double   hOpen[], hHigh[], hLow[], hClose[];

//--- alphas / derived params
double aF, aB, aS, aSm;
const double aBand  = 2.0/(4.0+1.0);
const double aTrail = 2.0/(5.0+1.0);
int    tpCount;

//--- mode state
ENUM_TIMEFRAMES g_tf;
bool            g_sameTF;
int             g_srcPrevCalculated = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0 ,TrendLineBuf    ,INDICATOR_DATA);
   SetIndexBuffer(1 ,TrendLineColBuf ,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2 ,LongArrowBuf    ,INDICATOR_DATA);
   SetIndexBuffer(3 ,ShortArrowBuf   ,INDICATOR_DATA);
   SetIndexBuffer(4 ,TrendStateBuf   ,INDICATOR_DATA);
   SetIndexBuffer(5 ,TrendStrengthBuf,INDICATOR_DATA);
   SetIndexBuffer(6 ,BullPressureBuf ,INDICATOR_DATA);
   SetIndexBuffer(7 ,BearPressureBuf ,INDICATOR_DATA);
   SetIndexBuffer(8 ,LongSignalBuf   ,INDICATOR_DATA);
   SetIndexBuffer(9 ,ShortSignalBuf  ,INDICATOR_DATA);
   SetIndexBuffer(10,AtrBuf          ,INDICATOR_DATA);
   SetIndexBuffer(11,TP1Buf          ,INDICATOR_DATA);
   SetIndexBuffer(12,TP2Buf          ,INDICATOR_DATA);
   SetIndexBuffer(13,TP3Buf          ,INDICATOR_DATA);

   PlotIndexSetInteger(1,PLOT_ARROW,233); // up arrow
   PlotIndexSetInteger(2,PLOT_ARROW,234); // down arrow
   PlotIndexSetInteger(1,PLOT_ARROW_SHIFT,0);
   PlotIndexSetInteger(2,PLOT_ARROW_SHIFT,0);
   for(int p=0;p<3;p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   aF  = 2.0/(InpFastLen +1.0);
   aB  = 2.0/(InpBaseLen +1.0);
   aS  = 2.0/(InpSlowLen +1.0);
   aSm = 2.0/(InpSmoothLen+1.0);
   tpCount = (int)MathMax(1,MathMin(3,InpTPCount));

   g_tf = InpTimeframe;
   if(g_tf==PERIOD_CURRENT) g_tf=_Period;
   if(PeriodSeconds(g_tf) < PeriodSeconds(_Period)) g_tf=_Period;
   g_sameTF = (g_tf==_Period);
   g_srcPrevCalculated = 0;

   IndicatorSetInteger(INDICATOR_DIGITS,2);
   string nm = g_sameTF ? "DTM Flat" : ("DTM Flat MTF ["+EnumToString(g_tf)+"]");
   if(!g_sameTF && g_tf!=InpTimeframe && InpTimeframe!=PERIOD_CURRENT)
      nm = "DTM Flat MTF ["+EnumToString(g_tf)+", fallback from "+EnumToString(InpTimeframe)+"]";
   IndicatorSetString(INDICATOR_SHORTNAME,nm);

   IndicatorSetDouble(INDICATOR_MINIMUM,0.0);
   IndicatorSetDouble(INDICATOR_MAXIMUM,2.0);

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
void ResizeEngine(const int n)
  {
   ArrayResize(E_Fast,n);      ArrayResize(E_Basis,n);     ArrayResize(E_Slow,n);
   ArrayResize(E_SpreadSm,n);  ArrayResize(E_SlopeSm,n);   ArrayResize(E_Atr,n);
   ArrayResize(E_UpperRaw,n);  ArrayResize(E_LowerRaw,n);
   ArrayResize(E_Upper,n);     ArrayResize(E_Lower,n);
   ArrayResize(E_TrailRaw,n);  ArrayResize(E_Trail,n);
   ArrayResize(E_TrendState,n);ArrayResize(E_TrendStrength,n);
   ArrayResize(E_BullP,n);     ArrayResize(E_BearP,n);
   ArrayResize(E_LongSig,n);   ArrayResize(E_ShortSig,n);  ArrayResize(E_ActiveSide,n);
   ArrayResize(E_TP1,n);       ArrayResize(E_TP2,n);       ArrayResize(E_TP3,n);
  }

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

      E_TrendState[0]=0;
      E_TrailRaw[0]=E_Basis[0];
      E_Trail[0]=E_Basis[0];
      E_TrendStrength[0]=0;
      E_BullP[0]=0; E_BearP[0]=0;
      E_LongSig[0]=0; E_ShortSig[0]=0;
      E_ActiveSide[0]=0;
      E_TP1[0]=EMPTY_VALUE; E_TP2[0]=EMPTY_VALUE; E_TP3[0]=EMPTY_VALUE;
      return;
     }

   // Base EMAs
   E_Fast[i]  = aF*price + (1.0-aF)*E_Fast[i-1];
   E_Basis[i] = aB*price + (1.0-aB)*E_Basis[i-1];
   E_Slow[i]  = aS*price + (1.0-aS)*E_Slow[i-1];

   // Spread + smoothing
   double spreadRaw = E_Fast[i]-E_Slow[i];
   E_SpreadSm[i] = aSm*spreadRaw + (1.0-aSm)*E_SpreadSm[i-1];

   // Slope + smoothing
   double slopeRaw = 0.0;
   if(i>=InpSlopeLen)
      slopeRaw = E_Basis[i]-E_Basis[i-InpSlopeLen];
   E_SlopeSm[i] = aSm*slopeRaw + (1.0-aSm)*E_SlopeSm[i-1];

   // ATR
   double tr = MathMax(h[i]-l[i],
               MathMax(MathAbs(h[i]-c[i-1]),
                       MathAbs(l[i]-c[i-1])));
   double n = (double)InpAtrLen;
   E_Atr[i] = (E_Atr[i-1]*(n-1.0)+tr)/n;
   double atr = E_Atr[i];

   // Strength
   double strengthRaw = (atr==0.0)?0.0:MathAbs(E_SpreadSm[i])/atr;
   strengthRaw = MathMax(0.0,MathMin(3.0,strengthRaw));
   E_TrendStrength[i] = strengthRaw/3.0;

   // Pressure
   bool bullP = (E_Fast[i]>E_Basis[i]) && (E_Basis[i]>E_Slow[i]) && (E_SlopeSm[i]>0.0);
   bool bearP = (E_Fast[i]<E_Basis[i]) && (E_Basis[i]<E_Slow[i]) && (E_SlopeSm[i]<0.0);
   E_BullP[i]=bullP?1:0;
   E_BearP[i]=bearP?1:0;

   // Raw bands
   double upRaw = E_Basis[i]+atr*InpAtrMult;
   double loRaw = E_Basis[i]-atr*InpAtrMult;
   E_UpperRaw[i]=upRaw; E_LowerRaw[i]=loRaw;

   // Smoothed bands
   E_Upper[i] = aBand*upRaw + (1.0-aBand)*E_Upper[i-1];
   E_Lower[i] = aBand*loRaw + (1.0-aBand)*E_Lower[i-1];

   // Trail / trend engine
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

   // Signal flags
   E_LongSig[i]  = longSig ?1:0;
   E_ShortSig[i] = shortSig?1:0;

   // TP engine
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
void WriteDisplay(const int i,const int srcIdx,const bool firstOfBar)
  {
   if(srcIdx<0)
     {
      TrendLineBuf[i]=EMPTY_VALUE;
      TrendLineColBuf[i]=COL_NEUTRAL;
      LongArrowBuf[i]=EMPTY_VALUE;
      ShortArrowBuf[i]=EMPTY_VALUE;
      TrendStateBuf[i]=0;
      TrendStrengthBuf[i]=0;
      BullPressureBuf[i]=0;
      BearPressureBuf[i]=0;
      LongSignalBuf[i]=0;
      ShortSignalBuf[i]=0;
      AtrBuf[i]=EMPTY_VALUE;
      TP1Buf[i]=EMPTY_VALUE;
      TP2Buf[i]=EMPTY_VALUE;
      TP3Buf[i]=EMPTY_VALUE;
      return;
     }

   // Draw flat line at the specified level with trend color
   TrendLineBuf[i] = InpLineLevel;
   TrendLineColBuf[i] = TrendColor((int)E_TrendState[srcIdx]);

   // Data buffers for EA access
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

   // Position arrows relative to the flat line
   bool showLong  = InpShowArrows && firstOfBar && E_LongSig[srcIdx] >0.5;
   bool showShort = InpShowArrows && firstOfBar && E_ShortSig[srcIdx]>0.5;
   LongArrowBuf[i]  = showLong ? (InpLineLevel+InpArrowGap) : EMPTY_VALUE;
   ShortArrowBuf[i] = showShort? (InpLineLevel-InpArrowGap) : EMPTY_VALUE;
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

   // MODE A: same timeframe
   if(g_sameTF)
     {
      ResizeEngine(rates_total);
      for(int i=start;i<rates_total;i++)
        {
         bool allowed = (!InpConfirmOnClose) || (i<rates_total-1);
         ComputeEngineBar(i,open,high,low,close,allowed);
        }
      for(int i=start;i<rates_total;i++)
         WriteDisplay(i,i,true);

      return(rates_total);
     }

   // MODE B: higher timeframe
   int htfBarsNow = Bars(_Symbol,g_tf);
   if(htfBarsNow<=1)
      return(prev_calculated);

   int oldBars   = ArraySize(hTime);
   int copyFrom  = (oldBars>0) ? oldBars-1 : 0;
   int copyCount = htfBarsNow - copyFrom;

   ArrayResize(hTime ,htfBarsNow);
   ArrayResize(hOpen ,htfBarsNow);
   ArrayResize(hHigh ,htfBarsNow);
   ArrayResize(hLow  ,htfBarsNow);
   ArrayResize(hClose,htfBarsNow);

   if(!CopyHtfTail(g_tf,copyCount))
      return(prev_calculated);

   ResizeEngine(htfBarsNow);
   int hStart = (g_srcPrevCalculated==0) ? 0 : MathMin(g_srcPrevCalculated-1,htfBarsNow-1);
   for(int j=hStart;j<htfBarsNow;j++)
     {
      bool allowed = (!InpConfirmOnClose) || (j<htfBarsNow-1);
      ComputeEngineBar(j,hOpen,hHigh,hLow,hClose,allowed);
     }
   g_srcPrevCalculated = htfBarsNow;

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
      WriteDisplay(i,hIdx,firstOfBar);
      prevMappedIdx = hIdx;
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
