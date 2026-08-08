//+------------------------------------------------------------------+
//|                                        DynamicTrendMatrix.mq5     |
//|   MQL5 port of "Uptrick: Dynamic Trend Matrix" (Pine v6)          |
//|   Single-timeframe. CPU-light (O(1) per bar, incremental).       |
//|   Basis + Trail colored by trend (buy=green, sell=magenta).      |
//|   All EA-relevant values exposed as Data Window buffers.         |
//|   License: CC BY-SA 4.0 (inherited from source)                  |
//+------------------------------------------------------------------+
#property copyright "Port of Uptrick: Dynamic Trend Matrix"
#property link      "https://creativecommons.org/licenses/by-sa/4.0/"
#property version   "1.10"
#property indicator_chart_window

#property indicator_buffers 28
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

//--- Inputs (order matters: MTF version passes these via iCustom) ---
input ENUM_APPLIED_PRICE InpSource        = PRICE_CLOSE; // Source
input int                InpFastLen        = 8;          // Fast Length
input int                InpBaseLen        = 21;         // Base Length
input int                InpSlowLen        = 55;         // Slow Length
input int                InpSlopeLen       = 5;          // Slope Length
input int                InpSmoothLen      = 3;          // Smoothing
input int                InpAtrLen         = 10;         // ATR Length
input double             InpAtrMult        = 2.0;        // ATR Multiplier
input bool               InpConfirmOnClose = true;       // Confirm Signals On Bar Close
input ENUM_TP_MODE       InpTPMode         = TP_RISK_FROM_TRAIL; // TP Calculation
input int                InpTPCount        = 3;          // TP Count (1..3)
input double             InpTP1Mult        = 1.0;        // TP1 Multiplier
input double             InpTP2Mult        = 2.0;        // TP2 Multiplier
input double             InpTP3Mult        = 3.0;        // TP3 Multiplier
input bool               InpShowBands      = false;       // Show Bands
input bool               InpShowOuter      = false;       // Show Outer Bands
input bool               InpShowTrail      = false;       // Show Trail
input bool               InpShowArrows     = true;       // Show Signal Arrows

//--- Buffers (data). Color buffers follow their line buffer.
double BasisBuf[];
double BasisColBuf[];   // color index for Basis
double UpperBuf[];
double LowerBuf[];
double UpperOuterBuf[];
double LowerOuterBuf[];
double TrailBuf[];
double TrailColBuf[];   // color index for Trail
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
//--- Buffers (calculation / internal state, hidden from data window)
double FastBuf[];
double SlowBuf[];
double SpreadSmoothBuf[];
double SlopeSmoothBuf[];
double UpperRawBuf[];
double LowerRawBuf[];
double TrailRawBuf[];
double ActiveSideBuf[];

//--- alphas
double aF, aB, aS, aSm;
const double aBand  = 2.0/(4.0+1.0);
const double aTrail = 2.0/(5.0+1.0);
int    tpCount;

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
   //--- calculation buffers
   SetIndexBuffer(20,FastBuf         ,INDICATOR_CALCULATIONS);
   SetIndexBuffer(21,SlowBuf         ,INDICATOR_CALCULATIONS);
   SetIndexBuffer(22,SpreadSmoothBuf ,INDICATOR_CALCULATIONS);
   SetIndexBuffer(23,SlopeSmoothBuf  ,INDICATOR_CALCULATIONS);
   SetIndexBuffer(24,UpperRawBuf     ,INDICATOR_CALCULATIONS);
   SetIndexBuffer(25,LowerRawBuf     ,INDICATOR_CALCULATIONS);
   SetIndexBuffer(26,TrailRawBuf     ,INDICATOR_CALCULATIONS);
   SetIndexBuffer(27,ActiveSideBuf   ,INDICATOR_CALCULATIONS);

   //--- arrows
   PlotIndexSetInteger(6,PLOT_ARROW,233); // up
   PlotIndexSetInteger(7,PLOT_ARROW,234); // down
   PlotIndexSetInteger(6,PLOT_ARROW_SHIFT,10);
   PlotIndexSetInteger(7,PLOT_ARROW_SHIFT,-10);

   //--- empty values for non-drawn points
   for(int p=0;p<18;p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   aF  = 2.0/(InpFastLen +1.0);
   aB  = 2.0/(InpBaseLen +1.0);
   aS  = 2.0/(InpSlowLen +1.0);
   aSm = 2.0/(InpSmoothLen+1.0);
   tpCount = (int)MathMax(1,MathMin(3,InpTPCount));

   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   IndicatorSetString(INDICATOR_SHORTNAME,"DTM");
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

   int start;
   if(prev_calculated==0)
      start=0;
   else
      start=prev_calculated-1; // recompute last (forming) bar each tick

   for(int i=start;i<rates_total;i++)
     {
      double price = GetPrice(i,open,high,low,close);

      if(i==0)
        {
         FastBuf[0]        = price;
         BasisBuf[0]       = price;
         SlowBuf[0]        = price;
         SpreadSmoothBuf[0]= 0.0;
         SlopeSmoothBuf[0] = 0.0;
         AtrBuf[0]         = high[0]-low[0];

         double up  = BasisBuf[0]+AtrBuf[0]*InpAtrMult;
         double lo  = BasisBuf[0]-AtrBuf[0]*InpAtrMult;
         UpperRawBuf[0]=up; LowerRawBuf[0]=lo;
         UpperBuf[0]=up;    LowerBuf[0]=lo;
         UpperOuterBuf[0]=BasisBuf[0]+AtrBuf[0]*InpAtrMult*1.45;
         LowerOuterBuf[0]=BasisBuf[0]-AtrBuf[0]*InpAtrMult*1.45;

         TrendStateBuf[0]=0;
         BasisColBuf[0]=COL_NEUTRAL;
         TrailColBuf[0]=COL_NEUTRAL;
         TrailRawBuf[0]=BasisBuf[0];
         TrailBuf[0]=BasisBuf[0];
         TrendStrengthBuf[0]=0;
         BullPressureBuf[0]=0; BearPressureBuf[0]=0;
         LongSignalBuf[0]=0;   ShortSignalBuf[0]=0;
         LongArrowBuf[0]=EMPTY_VALUE; ShortArrowBuf[0]=EMPTY_VALUE;
         ActiveSideBuf[0]=0;
         TP1Buf[0]=EMPTY_VALUE; TP2Buf[0]=EMPTY_VALUE; TP3Buf[0]=EMPTY_VALUE;
         continue;
        }

      // --- Base EMAs (recursive) ---
      FastBuf[i]  = aF*price + (1.0-aF)*FastBuf[i-1];
      BasisBuf[i] = aB*price + (1.0-aB)*BasisBuf[i-1];
      SlowBuf[i]  = aS*price + (1.0-aS)*SlowBuf[i-1];

      // --- Spread + smoothing ---
      double spreadRaw = FastBuf[i]-SlowBuf[i];
      SpreadSmoothBuf[i] = aSm*spreadRaw + (1.0-aSm)*SpreadSmoothBuf[i-1];

      // --- Slope + smoothing ---
      double slopeRaw = 0.0;
      if(i>=InpSlopeLen)
         slopeRaw = BasisBuf[i]-BasisBuf[i-InpSlopeLen];
      SlopeSmoothBuf[i] = aSm*slopeRaw + (1.0-aSm)*SlopeSmoothBuf[i-1];

      // --- ATR (Wilder/RMA on true range) ---
      double tr = MathMax(high[i]-low[i],
                  MathMax(MathAbs(high[i]-close[i-1]),
                          MathAbs(low[i]-close[i-1])));
      double n = (double)InpAtrLen;
      AtrBuf[i] = (AtrBuf[i-1]*(n-1.0)+tr)/n;
      double atr = AtrBuf[i];

      // --- Strength ---
      double strengthRaw = (atr==0.0)?0.0:MathAbs(SpreadSmoothBuf[i])/atr;
      strengthRaw = MathMax(0.0,MathMin(3.0,strengthRaw));
      TrendStrengthBuf[i] = strengthRaw/3.0;

      // --- Pressure ---
      bool bullP = (FastBuf[i]>BasisBuf[i]) && (BasisBuf[i]>SlowBuf[i]) && (SlopeSmoothBuf[i]>0.0);
      bool bearP = (FastBuf[i]<BasisBuf[i]) && (BasisBuf[i]<SlowBuf[i]) && (SlopeSmoothBuf[i]<0.0);
      BullPressureBuf[i]=bullP?1:0;
      BearPressureBuf[i]=bearP?1:0;

      // --- Raw bands ---
      double upRaw = BasisBuf[i]+atr*InpAtrMult;
      double loRaw = BasisBuf[i]-atr*InpAtrMult;
      UpperRawBuf[i]=upRaw; LowerRawBuf[i]=loRaw;

      // --- Smoothed bands (EMA 4) ---
      UpperBuf[i]      = aBand*upRaw + (1.0-aBand)*UpperBuf[i-1];
      LowerBuf[i]      = aBand*loRaw + (1.0-aBand)*LowerBuf[i-1];
      UpperOuterBuf[i] = aBand*(BasisBuf[i]+atr*InpAtrMult*1.45) + (1.0-aBand)*UpperOuterBuf[i-1];
      LowerOuterBuf[i] = aBand*(BasisBuf[i]-atr*InpAtrMult*1.45) + (1.0-aBand)*LowerOuterBuf[i-1];

      // --- Trail / trend engine ---
      int prevTrend = (int)TrendStateBuf[i-1];
      bool allowed  = (!InpConfirmOnClose) || (i < rates_total-1);

      bool rawLongFlip  = (close[i] > UpperRawBuf[i-1]) && (prevTrend != 1);
      bool rawShortFlip = (close[i] < LowerRawBuf[i-1]) && (prevTrend != -1);
      bool longSig  = rawLongFlip  && allowed;
      bool shortSig = rawShortFlip && allowed;

      int   trend = prevTrend;
      double trailRaw;
      if(longSig)
        { trend=1;  trailRaw=loRaw; }
      else if(shortSig)
        { trend=-1; trailRaw=upRaw; }
      else
        {
         if(prevTrend==1)
            trailRaw = MathMax(TrailRawBuf[i-1],loRaw);
         else if(prevTrend==-1)
            trailRaw = MathMin(TrailRawBuf[i-1],upRaw);
         else
            trailRaw = BasisBuf[i];
        }
      TrendStateBuf[i]=trend;
      TrailRawBuf[i]=trailRaw;
      TrailBuf[i] = aTrail*trailRaw + (1.0-aTrail)*TrailBuf[i-1];

      // --- Trend colors (buy=green, sell=magenta, neutral=gray) ---
      int col = TrendColor(trend);
      BasisColBuf[i] = col;
      TrailColBuf[i] = col;

      // --- Signal flags + arrows ---
      LongSignalBuf[i]  = longSig ?1:0;
      ShortSignalBuf[i] = shortSig?1:0;
      double sigGap = atr*0.75;
      LongArrowBuf[i]  = (InpShowArrows && longSig )? low[i]-sigGap  : EMPTY_VALUE;
      ShortArrowBuf[i] = (InpShowArrows && shortSig)? high[i]+sigGap : EMPTY_VALUE;

      // --- TP engine (levels carried forward while a side is active) ---
      double side = ActiveSideBuf[i-1];
      double t1=TP1Buf[i-1], t2=TP2Buf[i-1], t3=TP3Buf[i-1];
      if(longSig)
        {
         side=1;
         double entry=close[i];
         double risk =(InpTPMode==TP_RISK_FROM_TRAIL)
                      ? MathMax(close[i]-loRaw,_Point) : atr;
         t1=entry+risk*InpTP1Mult;
         t2=entry+risk*InpTP2Mult;
         t3=entry+risk*InpTP3Mult;
        }
      else if(shortSig)
        {
         side=-1;
         double entry=close[i];
         double risk =(InpTPMode==TP_RISK_FROM_TRAIL)
                      ? MathMax(upRaw-close[i],_Point) : atr;
         t1=entry-risk*InpTP1Mult;
         t2=entry-risk*InpTP2Mult;
         t3=entry-risk*InpTP3Mult;
        }
      ActiveSideBuf[i]=side;
      TP1Buf[i]= (tpCount>=1)? t1 : EMPTY_VALUE;
      TP2Buf[i]= (tpCount>=2)? t2 : EMPTY_VALUE;
      TP3Buf[i]= (tpCount>=3)? t3 : EMPTY_VALUE;

      // --- Visual toggles (blank the lines if disabled) ---
      if(!InpShowBands){ UpperBuf[i]=EMPTY_VALUE; LowerBuf[i]=EMPTY_VALUE; }
      if(!InpShowBands || !InpShowOuter){ UpperOuterBuf[i]=EMPTY_VALUE; LowerOuterBuf[i]=EMPTY_VALUE; }
      if(!InpShowTrail){ TrailBuf[i]=EMPTY_VALUE; }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
