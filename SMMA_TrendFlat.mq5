//+------------------------------------------------------------------+
//|                                              SMMA_TrendFlat.mq5   |
//|   Flat trend indicator drawn in a separate sub-window, styled     |
//|   like DynamicTrendMatrixMTF_Flat: a colored horizontal line      |
//|   with flip arrows above / below it.                              |
//|                                                                   |
//|   Trend engine (current timeframe, closed bars only):             |
//|     - Two SMMAs of period InpSmmaPeriod: one on High, one on Low. |
//|     - Flip GREEN: a bullish candle (close>open) closes ABOVE the  |
//|       SMMA(High). Trend stays green even if later closes fall     |
//|       back below the SMMA(High).                                  |
//|     - Flip RED: a bearish candle (close<open) closes BELOW the    |
//|       SMMA(Low). Trend stays red (even for closes between the two |
//|       SMMAs) until a bullish candle closes above the SMMA(High).  |
//|     - Green arrow BELOW the line on a red->green flip.             |
//|     - Red arrow ABOVE the line on a green->red flip.              |
//|   The forming bar is never evaluated, so the trend never repaints.|
//+------------------------------------------------------------------+
#property copyright "SMMA Flat Trend"
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
input int    InpSmmaPeriod = 5;    // SMMA Period (High & Low)
input bool   InpShowArrows = true; // Show Flip Arrows
input double InpLineLevel  = 1.0;  // Trend Line Level
input double InpArrowGap   = 0.3;  // Arrow Gap from Line

//--- Plot buffers
double TrendLineBuf[];
double TrendLineColBuf[];
double LongArrowBuf[];
double ShortArrowBuf[];
//--- Calculation buffers (persist between calls)
double SmmaHighBuf[];
double SmmaLowBuf[];
double TrendStateBuf[];

//--- SMMA indicator handles
int hSmmaHigh = INVALID_HANDLE;
int hSmmaLow  = INVALID_HANDLE;

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

   int per = MathMax(1,InpSmmaPeriod);
   hSmmaHigh = iMA(_Symbol,_Period,per,0,MODE_SMMA,PRICE_HIGH);
   hSmmaLow  = iMA(_Symbol,_Period,per,0,MODE_SMMA,PRICE_LOW);
   if(hSmmaHigh==INVALID_HANDLE || hSmmaLow==INVALID_HANDLE)
     {
      Print("SMMA_TrendFlat: failed to create iMA handle(s)");
      return(INIT_FAILED);
     }

   IndicatorSetInteger(INDICATOR_DIGITS,2);
   IndicatorSetString(INDICATOR_SHORTNAME,"SMMA Flat Trend ("+(string)per+")");
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
   int per = MathMax(1,InpSmmaPeriod);
   if(rates_total < per+2) return(0);

   //--- make sure the SMMA sub-indicators have finished calculating
   if(BarsCalculated(hSmmaHigh) < rates_total ||
      BarsCalculated(hSmmaLow)  < rates_total)
      return(prev_calculated);

   //--- pull SMMA values aligned oldest-first (non-series, like the price arrays)
   if(CopyBuffer(hSmmaHigh,0,0,rates_total,SmmaHighBuf) < rates_total)
      return(prev_calculated);
   if(CopyBuffer(hSmmaLow ,0,0,rates_total,SmmaLowBuf ) < rates_total)
      return(prev_calculated);

   //--- recompute from the last confirmed bar of the previous pass
   int start = (prev_calculated>0) ? prev_calculated-1 : 0;

   for(int i=start;i<rates_total;i++)
     {
      int prevTrend = (i>0) ? (int)TrendStateBuf[i-1] : 0;
      int trend     = prevTrend;

      // Evaluate flips on CLOSED bars only (never the forming last bar),
      // and only once enough history exists for the SMMA to be meaningful.
      bool doEval = (i < rates_total-1) && (i >= per);
      if(doEval)
        {
         bool green = (close[i] > open[i]);
         bool red   = (close[i] < open[i]);

         if(green && close[i] > SmmaHighBuf[i])
            trend = 1;                       // bullish break above SMMA(High)
         else if(red && close[i] < SmmaLowBuf[i])
            trend = -1;                      // bearish break below SMMA(Low)
         // otherwise: hold the previous trend (flat continuation)
        }

      TrendStateBuf[i]   = trend;

      // Flat colored line at the chosen level
      TrendLineBuf[i]    = InpLineLevel;
      TrendLineColBuf[i] = TrendColor(trend);

      // Arrows only on an actual flip to a new (non-neutral) trend, closed bars only
      bool flipToGreen = (trend== 1 && prevTrend!= 1);
      bool flipToRed   = (trend==-1 && prevTrend!=-1);

      LongArrowBuf[i]  = (InpShowArrows && doEval && flipToGreen)
                         ? (InpLineLevel - InpArrowGap)   // green arrow BELOW the line
                         : EMPTY_VALUE;
      ShortArrowBuf[i] = (InpShowArrows && doEval && flipToRed)
                         ? (InpLineLevel + InpArrowGap)   // red arrow ABOVE the line
                         : EMPTY_VALUE;
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
