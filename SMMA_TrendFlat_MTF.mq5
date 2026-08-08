//+------------------------------------------------------------------+
//|                                          SMMA_TrendFlat_MTF.mq5   |
//|   Multi-timeframe version of SMMA_TrendFlat.                       |
//|   Flat trend line in a separate sub-window with flip arrows,       |
//|   styled like DynamicTrendMatrixMTF_Flat. The trend is computed    |
//|   on InpTimeframe and mapped onto the current chart's bars.        |
//|                                                                   |
//|   Trend engine (target timeframe, closed bars only):              |
//|     - Two SMMAs of period InpSmmaPeriod: one on High, one on Low. |
//|       (built-in MODE_SMMA, same as the single-TF version)         |
//|     - Flip GREEN: a bullish candle (close>open) closes ABOVE the  |
//|       SMMA(High) by >= InpMinBreakPips. Trend stays green even if  |
//|       later closes fall back below the SMMA(High).                 |
//|     - Flip RED: a bearish candle (close<open) closes BELOW the     |
//|       SMMA(Low) by >= InpMinBreakPips. Trend stays red (even for   |
//|       closes between the two SMMAs) until a bullish candle closes  |
//|       above the SMMA(High) again.                                  |
//|     - Green arrow BELOW the line on a red->green flip.             |
//|     - Red arrow ABOVE the line on a green->red flip.              |
//|   Only closed (target-TF) candles are evaluated -> no repaint.    |
//+------------------------------------------------------------------+
#property copyright "SMMA Flat Trend MTF"
#property link      ""
#property version   "1.00"
#property indicator_separate_window

#property indicator_buffers 7
#property indicator_plots   3

//--- Plot 0: Flat trend line - COLOR by trend
#property indicator_label1  "TrendLine"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrLime,clrRed,clrGray
#property indicator_width1  3
//--- Plot 1: flip-to-green arrow (below the line)
#property indicator_label2  "LongArrow"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_width2  2
//--- Plot 2: flip-to-red arrow (above the line)
#property indicator_label3  "ShortArrow"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrRed
#property indicator_width3  2

//--- color index convention (bull=green, bear=red, neutral=gray)
#define COL_BULL    0
#define COL_BEAR    1
#define COL_NEUTRAL 2

//--- Inputs ---
input ENUM_TIMEFRAMES InpTimeframe    = PERIOD_CURRENT; // Indicator Timeframe
input int             InpSmmaPeriod   = 5;              // SMMA Period (High & Low)
input double          InpMinBreakPips = 0.0;            // Min Break (pips) beyond SMMA to signal
input bool            InpShowArrows   = true;           // Show Flip Arrows
input double          InpLineLevel    = 1.0;            // Trend Line Level
input double          InpArrowGap     = 0.3;            // Arrow Gap from Line

//--- Plot buffers
double TrendLineBuf[];
double TrendLineColBuf[];
double LongArrowBuf[];
double ShortArrowBuf[];
//--- Calculation buffers (same-TF path)
double SmmaHighBuf[];
double SmmaLowBuf[];
double TrendStateBuf[];

//--- SMMA indicator handles (created on the target timeframe)
int hSmmaHigh = INVALID_HANDLE;
int hSmmaLow  = INVALID_HANDLE;

//--- pip size (digits-aware: 10*Point on 3/5-digit symbols, else Point)
double g_pip = 0.0;

//--- resolved timeframe / mode
ENUM_TIMEFRAMES g_tf;
bool            g_sameTF;

//--- target-timeframe working arrays (ascending: index 0 = oldest)
datetime hTime[];
double   hOpen[], hHigh[], hLow[], hClose[];
double   hSmH[], hSmL[];
double   hTrend[], hLongFlip[], hShortFlip[];

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0,TrendLineBuf   ,INDICATOR_DATA);
   SetIndexBuffer(1,TrendLineColBuf,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,LongArrowBuf   ,INDICATOR_DATA);
   SetIndexBuffer(3,ShortArrowBuf  ,INDICATOR_DATA);
   SetIndexBuffer(4,SmmaHighBuf    ,INDICATOR_CALCULATIONS);
   SetIndexBuffer(5,SmmaLowBuf     ,INDICATOR_CALCULATIONS);
   SetIndexBuffer(6,TrendStateBuf  ,INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(1,PLOT_ARROW,233); // up arrow   (flip to green)
   PlotIndexSetInteger(2,PLOT_ARROW,234); // down arrow (flip to red)
   PlotIndexSetInteger(1,PLOT_ARROW_SHIFT,0);
   PlotIndexSetInteger(2,PLOT_ARROW_SHIFT,0);
   for(int p=0;p<3;p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   g_pip = ((_Digits==3 || _Digits==5) ? 10.0 : 1.0) * _Point;

   //--- resolve target timeframe (never lower than the chart timeframe)
   g_tf = InpTimeframe;
   if(g_tf==PERIOD_CURRENT) g_tf=_Period;
   if(PeriodSeconds(g_tf) < PeriodSeconds(_Period)) g_tf=_Period;
   g_sameTF = (g_tf==_Period);

   int per = MathMax(1,InpSmmaPeriod);
   hSmmaHigh = iMA(_Symbol,g_tf,per,0,MODE_SMMA,PRICE_HIGH);
   hSmmaLow  = iMA(_Symbol,g_tf,per,0,MODE_SMMA,PRICE_LOW);
   if(hSmmaHigh==INVALID_HANDLE || hSmmaLow==INVALID_HANDLE)
     {
      Print("SMMA_TrendFlat_MTF: failed to create iMA handle(s)");
      return(INIT_FAILED);
     }

   IndicatorSetInteger(INDICATOR_DIGITS,2);
   string nm = g_sameTF ? "SMMA Flat ("+(string)per+")"
                        : "SMMA Flat MTF ["+EnumToString(g_tf)+"] ("+(string)per+")";
   if(!g_sameTF && g_tf!=InpTimeframe && InpTimeframe!=PERIOD_CURRENT)
      nm = "SMMA Flat MTF ["+EnumToString(g_tf)+", fallback from "+EnumToString(InpTimeframe)+"]";
   IndicatorSetString(INDICATOR_SHORTNAME,nm);
   IndicatorSetDouble(INDICATOR_MINIMUM,0.0);
   IndicatorSetDouble(INDICATOR_MAXIMUM,2.0);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hSmmaHigh!=INVALID_HANDLE) IndicatorRelease(hSmmaHigh);
   if(hSmmaLow !=INVALID_HANDLE) IndicatorRelease(hSmmaLow);
  }

//+------------------------------------------------------------------+
int TrendColor(const int trend)
  {
   if(trend==1)  return COL_BULL;
   if(trend==-1) return COL_BEAR;
   return COL_NEUTRAL;
  }

//+------------------------------------------------------------------+
//| Greatest index in ascending hTime[] with hTime[idx] <= t.         |
//| Returns -1 if t precedes the first target-TF bar.                 |
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
//| Shared trend rule for one bar. Returns +1 / -1 / prevTrend.       |
//+------------------------------------------------------------------+
int EvalTrend(const int prevTrend,const bool allowed,
              const double o,const double h,const double l,const double c,
              const double smH,const double smL,const double thr)
  {
   if(!allowed) return prevTrend;
   bool green = (c > o);
   bool red   = (c < o);
   if(green && c > smH + thr) return  1;   // bullish break above SMMA(High)
   if(red   && c < smL - thr) return -1;   // bearish break below SMMA(Low)
   return prevTrend;                        // hold (flat continuation)
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
   int    per = MathMax(1,InpSmmaPeriod);
   double thr = InpMinBreakPips * g_pip;
   if(rates_total < per+2) return(0);

   //==================================================================
   // MODE A: target timeframe == chart timeframe (identical to single-TF)
   //==================================================================
   if(g_sameTF)
     {
      if(BarsCalculated(hSmmaHigh) < rates_total ||
         BarsCalculated(hSmmaLow)  < rates_total)
         return(prev_calculated);
      if(CopyBuffer(hSmmaHigh,0,0,rates_total,SmmaHighBuf) < rates_total)
         return(prev_calculated);
      if(CopyBuffer(hSmmaLow ,0,0,rates_total,SmmaLowBuf ) < rates_total)
         return(prev_calculated);

      int start = (prev_calculated>0) ? prev_calculated-1 : 0;
      for(int i=start;i<rates_total;i++)
        {
         int prevTrend = (i>0) ? (int)TrendStateBuf[i-1] : 0;
         bool doEval   = (i < rates_total-1) && (i >= per);
         int trend     = EvalTrend(prevTrend,doEval,
                                   open[i],high[i],low[i],close[i],
                                   SmmaHighBuf[i],SmmaLowBuf[i],thr);

         TrendStateBuf[i]   = trend;
         TrendLineBuf[i]    = InpLineLevel;
         TrendLineColBuf[i] = TrendColor(trend);

         bool flipToGreen = (trend== 1 && prevTrend!= 1);
         bool flipToRed   = (trend==-1 && prevTrend!=-1);
         LongArrowBuf[i]  = (InpShowArrows && doEval && flipToGreen)
                            ? (InpLineLevel - InpArrowGap) : EMPTY_VALUE;
         ShortArrowBuf[i] = (InpShowArrows && doEval && flipToRed)
                            ? (InpLineLevel + InpArrowGap) : EMPTY_VALUE;
        }
      return(rates_total);
     }

   //==================================================================
   // MODE B: higher timeframe -> compute on g_tf, map onto chart bars
   //==================================================================
   int htfN = (int)MathMin((double)Bars(_Symbol,g_tf),
                MathMin((double)BarsCalculated(hSmmaHigh),
                        (double)BarsCalculated(hSmmaLow)));
   if(htfN <= per+1) return(prev_calculated);

   ArrayResize(hTime,htfN);   ArrayResize(hOpen,htfN);   ArrayResize(hHigh,htfN);
   ArrayResize(hLow,htfN);    ArrayResize(hClose,htfN);
   ArrayResize(hSmH,htfN);    ArrayResize(hSmL,htfN);
   ArrayResize(hTrend,htfN);  ArrayResize(hLongFlip,htfN); ArrayResize(hShortFlip,htfN);

   //--- copy target-TF data (series temp, then reverse into ascending)
   datetime tT[]; double tO[],tH[],tL[],tC[],tSH[],tSL[];
   ArraySetAsSeries(tT,true);  ArraySetAsSeries(tO,true);  ArraySetAsSeries(tH,true);
   ArraySetAsSeries(tL,true);  ArraySetAsSeries(tC,true);
   ArraySetAsSeries(tSH,true); ArraySetAsSeries(tSL,true);

   if(CopyTime (_Symbol,g_tf,0,htfN,tT) != htfN) return(prev_calculated);
   if(CopyOpen (_Symbol,g_tf,0,htfN,tO) != htfN) return(prev_calculated);
   if(CopyHigh (_Symbol,g_tf,0,htfN,tH) != htfN) return(prev_calculated);
   if(CopyLow  (_Symbol,g_tf,0,htfN,tL) != htfN) return(prev_calculated);
   if(CopyClose(_Symbol,g_tf,0,htfN,tC) != htfN) return(prev_calculated);
   if(CopyBuffer(hSmmaHigh,0,0,htfN,tSH) != htfN) return(prev_calculated);
   if(CopyBuffer(hSmmaLow ,0,0,htfN,tSL) != htfN) return(prev_calculated);

   for(int k=0;k<htfN;k++)
     {
      int d = htfN-1-k; // tT[0] is the most recent bar -> last ascending index
      hTime[d]=tT[k]; hOpen[d]=tO[k]; hHigh[d]=tH[k]; hLow[d]=tL[k]; hClose[d]=tC[k];
      hSmH[d]=tSH[k]; hSmL[d]=tSL[k];
     }

   //--- trend engine over target-TF bars (oldest -> newest), closed bars only
   for(int j=0;j<htfN;j++)
     {
      int  prevT   = (j>0) ? (int)hTrend[j-1] : 0;
      bool allowed = (j < htfN-1) && (j >= per);   // last htf bar is still forming
      int  t       = EvalTrend(prevT,allowed,
                               hOpen[j],hHigh[j],hLow[j],hClose[j],
                               hSmH[j],hSmL[j],thr);
      hTrend[j]     = t;
      hLongFlip[j]  = (t== 1 && prevT!= 1) ? 1 : 0;
      hShortFlip[j] = (t==-1 && prevT!=-1) ? 1 : 0;
     }

   //--- map onto chart bars. Redraw the region covered by the last two
   //    target-TF bars (a just-closed htf bar can create a new flip),
   //    plus the normal incremental tail.
   int start = (prev_calculated>0) ? prev_calculated-1 : 0;
   datetime redrawFrom = hTime[MathMax(0,htfN-2)];
   int dispStart = start;
   while(dispStart>0 && time[dispStart-1] >= redrawFrom)
      dispStart--;

   int prevMapped = (dispStart>0) ? FindHtfIndex(time[dispStart-1],htfN) : -2;

   for(int i=dispStart;i<rates_total;i++)
     {
      int  hIdx       = FindHtfIndex(time[i],htfN);
      bool firstOfBar = (hIdx != prevMapped);

      if(hIdx<0)
        {
         TrendLineBuf[i]    = EMPTY_VALUE;
         TrendLineColBuf[i] = COL_NEUTRAL;
         LongArrowBuf[i]    = EMPTY_VALUE;
         ShortArrowBuf[i]   = EMPTY_VALUE;
        }
      else
        {
         TrendLineBuf[i]    = InpLineLevel;
         TrendLineColBuf[i] = TrendColor((int)hTrend[hIdx]);
         LongArrowBuf[i]  = (InpShowArrows && firstOfBar && hLongFlip[hIdx] >0.5)
                            ? (InpLineLevel - InpArrowGap) : EMPTY_VALUE;
         ShortArrowBuf[i] = (InpShowArrows && firstOfBar && hShortFlip[hIdx]>0.5)
                            ? (InpLineLevel + InpArrowGap) : EMPTY_VALUE;
        }
      prevMapped = hIdx;
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
