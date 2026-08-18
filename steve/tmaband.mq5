//+------------------------------------------------------------------+
//|                                                macd_optimized.mq5|
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//  OPTIMIZED VERSION
//  ------------------
//  Changes vs original:
//   1) TMA weighted sum is now updated incrementally in O(1) per bar
//      instead of re-summing HalfLength+1 prices every bar (classic
//      LWMA rolling-sum trick: S = simple rolling sum, WS = weighted
//      rolling sum, updated with WS(i) = WS(i-1) + n*price[i] - S(i-1)).
//   2) Manual ATR-style band width (Band_ATR, UseBuiltInATR=false) is
//      now a rolling sum instead of an AtrPeriod-length loop per bar.
//   3) StdDev band width is now a rolling sum / sum-of-squares instead
//      of CalculateStdDev()'s O(period) loop per bar.
//   4) UseBuiltInATR is now actually wired up (previously computed via
//      CopyBuffer but never used) -- when enabled it uses the native
//      iATR handle instead of any manual loop at all.
//   5) The outer recompute loop now starts at prev_calculated-1
//      (this is a causal/backward-looking indicator, so it never
//      needed to rewalk the last HalfLength bars on every tick).
//   6) Fixed a bug where the Caution-arrow ATR offset always used an
//      outer `atr` variable that was shadowed to 0 inside the
//      Band_ATR case, so Caution arrows never actually reflected ATR.
//+------------------------------------------------------------------+

#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   7

#property indicator_label1  "Centered TMA"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrLightSkyBlue,clrPink
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2
#property indicator_label2  "Centered TMA upper band"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrLightSkyBlue
#property indicator_style2  STYLE_DOT
#property indicator_label3  "Centered TMA lower band"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrPink
#property indicator_style3  STYLE_DOT
#property indicator_label4  "Rebound down"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrPink
#property indicator_width4  2
#property indicator_label5  "Rebound up"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrLightSkyBlue
#property indicator_width5  2
#property indicator_label6  "Centered TMA angle caution"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrGold
#property indicator_width6  3
#property indicator_label7  "Trend State"
#property indicator_type7   DRAW_NONE

enum enPrices
{
   pr_close,      // Close
   pr_open,       // Open
   pr_high,       // High
   pr_low,        // Low
   pr_median,     // Median
   pr_typical,    // Typical
   pr_weighted,   // Weighted
   pr_average,    // Average (high+low+oprn+close)/4
   pr_haclose,    // Heiken ashi close
   pr_haopen ,    // Heiken ashi open
   pr_hahigh,     // Heiken ashi high
   pr_halow,      // Heiken ashi low
   pr_hamedian,   // Heiken ashi median
   pr_hatypical,  // Heiken ashi typical
   pr_haweighted, // Heiken ashi weighted
   pr_haaverage   // Heiken ashi average
};

enum BandMode
{
   Band_ATR = 0,
   Band_StdDev = 1,
   Band_FixedPips = 2
};

input BandMode  BandsType        = Band_ATR;
input int       StdDevPeriod     = 100;
input double    StdDevMultiplier = 2.0;
input double    FixedBandPips    = 50;
input int       HalfLength       = 600;        // Centered TMA half period
input enPrices  Price            = pr_weighted; // Price to use
input int       AtrPeriod        = 100;        // Average true range period
input double    AtrMultiplier    = 2;          // Average true range multiplier
input int       TMAangle         = 4;          // Centered TMA angle caution. In pips
input bool      ShowReboundArrows = false;
input bool      ShowCautionArrows = false;
input bool      UseBuiltInATR     = false;      // Use native iATR instead of manual loop (fastest)

//------------------------------------------------------------------
// Indicator buffers
//------------------------------------------------------------------
int ATRHandle = INVALID_HANDLE;
double tmac[];
double tmau[];
double tmad[];
double colorBuffer[];
double TrendState[];
double ReboundD[], ReboundU[], Caution[];

//------------------------------------------------------------------
// Scratch / rolling-state arrays (not plotted, persist across calls)
//------------------------------------------------------------------
double prices[];   // cached source price per bar
double gS[];       // rolling simple sum for TMA window   (S)
double gWS[];      // rolling weighted sum for TMA window  (WS)
double gAtrSum[];  // rolling sum for manual ATR-style band width
double gStdSx[];   // rolling sum of price for stddev
double gStdSxx[];  // rolling sum of price^2 for stddev

int OnInit()
{
   SetIndexBuffer(0,tmac,INDICATOR_DATA);
   SetIndexBuffer(1,colorBuffer,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,tmau,INDICATOR_DATA);
   SetIndexBuffer(3,tmad,INDICATOR_DATA);
   SetIndexBuffer(4,ReboundD,INDICATOR_DATA); PlotIndexSetInteger(3, PLOT_ARROW, 226);
   SetIndexBuffer(5,ReboundU,INDICATOR_DATA); PlotIndexSetInteger(4, PLOT_ARROW, 225);
   SetIndexBuffer(6,Caution,INDICATOR_DATA);  PlotIndexSetInteger(5, PLOT_ARROW, 251);
   SetIndexBuffer(7,TrendState,INDICATOR_DATA); PlotIndexSetDouble(6, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   if(UseBuiltInATR)
   {
      ATRHandle = iATR(_Symbol,_Period,AtrPeriod);
      if(ATRHandle == INVALID_HANDLE)
         return(INIT_FAILED);
   }

   IndicatorSetString(INDICATOR_SHORTNAME," TMA centered ("+string(HalfLength)+")");
   return(0);
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime& time[],
                const double& open[],
                const double& high[],
                const double& low[],
                const double& close[],
                const long& tick_volume[],
                const long& volume[],
                const int& spread[])
{
   const int n = HalfLength + 1;                 // TMA full window length
   const double sumwFull = (double)n*(n+1)/2.0;   // constant once window is full

   //--- resize persistent scratch arrays only when needed ---
   if(ArraySize(prices)!=rates_total) ArrayResize(prices,rates_total);
   if(ArraySize(gS)!=rates_total)     ArrayResize(gS,rates_total);
   if(ArraySize(gWS)!=rates_total)    ArrayResize(gWS,rates_total);

   bool needManualAtr = (BandsType==Band_ATR && !UseBuiltInATR);
   bool needStdDev    = (BandsType==Band_StdDev);

   if(needManualAtr && ArraySize(gAtrSum)!=rates_total) ArrayResize(gAtrSum,rates_total);
   if(needStdDev)
   {
      if(ArraySize(gStdSx)!=rates_total)  ArrayResize(gStdSx,rates_total);
      if(ArraySize(gStdSxx)!=rates_total) ArrayResize(gStdSxx,rates_total);
   }

   //--- native ATR handle (only copied when actually used) ---
   double ATRValues[];
   if(BandsType==Band_ATR && UseBuiltInATR)
   {
      ArraySetAsSeries(ATRValues,false);
      ArrayResize(ATRValues,rates_total);
      CopyBuffer(ATRHandle,0,0,rates_total,ATRValues);
   }

   // Causal indicator: only the newest bar (plus the possibly-still-forming
   // last bar) ever needs recomputation. No need to rewalk HalfLength bars.
   int start = (int)MathMax(prev_calculated-1,0);

   for(int i=start; i<rates_total; i++)
   {
      prices[i] = getPrice(Price,open,close,high,low,i,rates_total);

      //--- band width for this bar ---
      double bandWidth = 0.0;
      double atrVal     = 0.0; // used for Caution arrow offset (Band_ATR only)

      switch(BandsType)
      {
         case Band_ATR:
         {
            if(UseBuiltInATR)
            {
               atrVal = ATRValues[i];
            }
            else
            {
               // term(m) is 0 (excluded) when m-11 < 0, exactly like the original loop
               double t = 0.0;
               if(i-11>=0)
                  t = MathMax(high[i-10],close[i-11]) - MathMin(low[i-10],close[i-11]);

               double prevSum = (i>0) ? gAtrSum[i-1] : 0.0;
               double outTerm = 0.0;
               int outIdx = i - AtrPeriod;
               if(outIdx>=0 && (outIdx-11)>=0)
                  outTerm = MathMax(high[outIdx-10],close[outIdx-11]) - MathMin(low[outIdx-10],close[outIdx-11]);

               gAtrSum[i] = prevSum + t - outTerm;
               atrVal = gAtrSum[i] / AtrPeriod; // same fixed-divisor behavior as original
            }
            bandWidth = atrVal * AtrMultiplier;
            break;
         }

         case Band_StdDev:
         {
            double addP = prices[i];
            double remP = (i-StdDevPeriod>=0) ? prices[i-StdDevPeriod] : 0.0;
            double sx  = (i>0 ? gStdSx[i-1]  : 0.0) + addP - remP;
            double sxx = (i>0 ? gStdSxx[i-1] : 0.0) + addP*addP - remP*remP;
            gStdSx[i]=sx; gStdSxx[i]=sxx;

            if(i < StdDevPeriod-1)
            {
               bandWidth = 0.0; // matches original: insufficient data -> 0
            }
            else
            {
               double mean = sx/StdDevPeriod;
               double variance = sxx/StdDevPeriod - mean*mean;
               if(variance<0) variance=0; // guard against fp rounding
               bandWidth = MathSqrt(variance) * StdDevMultiplier;
            }
            break;
         }

         case Band_FixedPips:
         {
            bandWidth = FixedBandPips * _Point;
            break;
         }
      }

      //--- Centered (causal) TMA, O(1) after warm-up ---
      if(i < HalfLength)
      {
         // Warm-up region: only the first HalfLength bars ever pay this
         // cost, and only once (start skips past already-computed bars).
         double sum  = (double)n * prices[i];
         double sumw = (double)n;
         for(int j=1,k=HalfLength; j<=HalfLength; j++,k--)
         {
            if(i-j>=0){ sum += k*prices[i-j]; sumw += k; }
         }
         tmac[i] = sum/sumw;
      }
      else if(i == HalfLength)
      {
         // First full window: one-time direct calc to seed the rolling sums.
         double s=0.0, ws=0.0;
         for(int j=0;j<n;j++)
         {
            s  += prices[i-j];
            ws += (double)(n-j)*prices[i-j];
         }
         gS[i]=s; gWS[i]=ws;
         tmac[i] = ws/sumwFull;
      }
      else
      {
         double ws = gWS[i-1] + (double)n*prices[i] - gS[i-1];
         double s  = gS[i-1] + prices[i] - prices[i-n];
         gWS[i]=ws; gS[i]=s;
         tmac[i] = ws/sumwFull;
      }

      //--- color / trend state ---
      if(i>0)
      {
         colorBuffer[i] = colorBuffer[i-1];
         if(tmac[i] > tmac[i-1]) colorBuffer[i] = 0;
         if(tmac[i] < tmac[i-1]) colorBuffer[i] = 1;

         if(tmac[i] > tmac[i-1])      TrendState[i] = 1;
         else if(tmac[i] < tmac[i-1]) TrendState[i] = -1;
         else                          TrendState[i] = TrendState[i-1];
      }
      else
      {
         colorBuffer[i] = 0;
         TrendState[i]  = 0;
      }

      tmau[i] = tmac[i] + bandWidth;
      tmad[i] = tmac[i] - bandWidth;

      //--- rebound / caution arrows ---
      ReboundD[i] = EMPTY_VALUE;
      ReboundU[i] = EMPTY_VALUE;
      Caution[i]  = EMPTY_VALUE;

      if(i>0)
      {
         if(high[i-1] > tmau[i-1] && close[i-1] > open[i-1] && close[i] < open[i])
         {
            if(ShowReboundArrows)
               ReboundD[i] = high[i] + bandWidth/2.0;

            if(ShowCautionArrows && tmac[i]-tmac[i-1] > TMAangle*_Point)
               Caution[i] = high[i] + AtrMultiplier*atrVal/2 + 10*_Point;
         }

         if(low[i-1] < tmad[i-1] && close[i-1] < open[i-1] && close[i] > open[i])
         {
            if(ShowReboundArrows)
               ReboundU[i] = low[i] - bandWidth/2.0;

            if(ShowCautionArrows && tmac[i-1]-tmac[i] > TMAangle*_Point)
               Caution[i] = low[i] - AtrMultiplier*atrVal/2 - 10*_Point;
         }
      }
   }

   return(rates_total);
}

//------------------------------------------------------------------
double workHa[][4];
double getPrice(enPrices price, const double& open[], const double& close[], const double& high[], const double& low[], int i, int bars)
{
   if(price>=pr_haclose && price<=pr_haaverage)
   {
      if(ArrayRange(workHa,0)!=bars) ArrayResize(workHa,bars);

      double haOpen;
      if(i>0) haOpen = (workHa[i-1][2] + workHa[i-1][3])/2.0;
      else    haOpen = open[i]+close[i];
      double haClose = (open[i] + high[i] + low[i] + close[i]) / 4.0;
      double haHigh  = MathMax(high[i], MathMax(haOpen,haClose));
      double haLow   = MathMin(low[i] , MathMin(haOpen,haClose));

      if(haOpen < haClose) { workHa[i][0]=haLow;  workHa[i][1]=haHigh; }
      else                 { workHa[i][0]=haHigh; workHa[i][1]=haLow;  }
      workHa[i][2] = haOpen;
      workHa[i][3] = haClose;

      switch(price)
      {
         case pr_haclose:    return(haClose);
         case pr_haopen:     return(haOpen);
         case pr_hahigh:     return(haHigh);
         case pr_halow:      return(haLow);
         case pr_hamedian:   return((haHigh+haLow)/2.0);
         case pr_hatypical:  return((haHigh+haLow+haClose)/3.0);
         case pr_haweighted: return((haHigh+haLow+haClose+haClose)/4.0);
         case pr_haaverage:  return((haHigh+haLow+haClose+haOpen)/4.0);
      }
   }

   switch(price)
   {
      case pr_close:    return(close[i]);
      case pr_open:     return(open[i]);
      case pr_high:     return(high[i]);
      case pr_low:      return(low[i]);
      case pr_median:   return((high[i]+low[i])/2.0);
      case pr_typical:  return((high[i]+low[i]+close[i])/3.0);
      case pr_weighted: return((high[i]+low[i]+close[i]+close[i])/4.0);
      case pr_average:  return((high[i]+low[i]+close[i]+open[i])/4.0);
   }
   return(0);
}

void OnDeinit(const int reason)
{
   if(ATRHandle != INVALID_HANDLE)
      IndicatorRelease(ATRHandle);
}
