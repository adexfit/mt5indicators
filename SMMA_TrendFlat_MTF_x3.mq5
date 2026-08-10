//+------------------------------------------------------------------+
//|                                       SMMA_TrendFlat_MTF_x3.mq5   |
//|   Three stacked SMMA flat-trend rows in one separate sub-window.  |
//|   Each row is an independent multi-timeframe trend (own iMA        |
//|   handles on its timeframe), mapped onto the current chart bars.   |
//|     Row 1 (top,    level 5) - default M1  (signal row)            |
//|     Row 2 (middle, level 3) - default M5                          |
//|     Row 3 (bottom, level 1) - default H1                          |
//|                                                                   |
//|   Per-row engine == SMMA_TrendFlat_MTF.mq5 (closed bars only):    |
//|     - SMMA(High) & SMMA(Low), period InpSmmaPeriod (MODE_SMMA)    |
//|     - green candle closing > SMMA(High)+thr -> trend green        |
//|     - red   candle closing < SMMA(Low)-thr  -> trend red, else hold|
//|     - green arrow below the line on red->green flip               |
//|     - red   arrow above the line on green->red flip               |
//|                                                                   |
//|   Alert: fires once when Row 1 (M1) flips and Row 2 & Row 3 are   |
//|   already aligned in that same direction (e.g. M1 flips bullish   |
//|   while M5 and H1 are both bullish). No repaint - the forming bar |
//|   of every timeframe is never evaluated.                          |
//+------------------------------------------------------------------+
#property copyright "SMMA Flat Trend MTF x3"
#property link      ""
#property version   "1.00"
#property indicator_separate_window

#property indicator_buffers 12
#property indicator_plots   9

//--- Row 1
#property indicator_label1  "R1 Trend"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrLime,clrRed,clrGray
#property indicator_width1  3
#property indicator_label2  "R1 Up"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_width2  2
#property indicator_label3  "R1 Dn"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrRed
#property indicator_width3  2
//--- Row 2
#property indicator_label4  "R2 Trend"
#property indicator_type4   DRAW_COLOR_LINE
#property indicator_color4  clrLime,clrRed,clrGray
#property indicator_width4  3
#property indicator_label5  "R2 Up"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrLime
#property indicator_width5  2
#property indicator_label6  "R2 Dn"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrRed
#property indicator_width6  2
//--- Row 3
#property indicator_label7  "R3 Trend"
#property indicator_type7   DRAW_COLOR_LINE
#property indicator_color7  clrLime,clrRed,clrGray
#property indicator_width7  3
#property indicator_label8  "R3 Up"
#property indicator_type8   DRAW_ARROW
#property indicator_color8  clrLime
#property indicator_width8  2
#property indicator_label9  "R3 Dn"
#property indicator_type9   DRAW_ARROW
#property indicator_color9  clrRed
#property indicator_width9  2

//--- color index convention (bull=green, bear=red, neutral=gray)
#define COL_BULL    0
#define COL_BEAR    1
#define COL_NEUTRAL 2

//--- Inputs ---
input ENUM_TIMEFRAMES InpTF1          = PERIOD_M1;  // Row 1 Timeframe (signal)
input ENUM_TIMEFRAMES InpTF2          = PERIOD_M5;  // Row 2 Timeframe
input ENUM_TIMEFRAMES InpTF3          = PERIOD_H1;  // Row 3 Timeframe
input int             InpSmmaPeriod   = 5;          // SMMA Period (High & Low)
input double          InpMinBreakPips = 0.0;        // Min Break (pips) beyond SMMA
input bool            InpShowArrows   = true;       // Show Flip Arrows
input double          InpArrowGap     = 0.4;        // Arrow Gap from Line
input bool            InpEnableAlert  = true;       // Enable Alignment Alert
input bool            InpAlertPopup   = true;       // Alert: Popup
input bool            InpAlertPush    = false;      // Alert: Push Notification
input bool            InpAlertPrint   = true;       // Alert: Print to Log

//--- Plot buffers (12; order must match SetIndexBuffer below)
double Line1[],Line1Col[],Up1[],Dn1[];
double Line2[],Line2Col[],Up2[],Dn2[];
double Line3[],Line3Col[],Up3[],Dn3[];

//--- pip size (digits-aware)
double g_pip = 0.0;

//--- alignment-alert state: time of the last Row-1 closed bar we processed
datetime g_row1LastClosed = 0;

//--- stacked line levels (top -> bottom)
const double LVL1 = 5.0;
const double LVL2 = 3.0;
const double LVL3 = 1.0;

//+------------------------------------------------------------------+
//| Per-row state: timeframe, SMMA handles and ascending working sets |
//+------------------------------------------------------------------+
struct RowState
  {
   ENUM_TIMEFRAMES tf;
   int             handleHigh;
   int             handleLow;
   int             n;            // bars in the working arrays this pass
   datetime        aTime[];
   double          aOpen[],aHigh[],aLow[],aClose[];
   double          aSmH[],aSmL[];
   double          aTrend[],aLongFlip[],aShortFlip[];
  };
RowState rows[3];

//+------------------------------------------------------------------+
ENUM_TIMEFRAMES ResolveTF(const ENUM_TIMEFRAMES tf)
  { return (tf==PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : tf; }

string TFToStr(const ENUM_TIMEFRAMES tf)
  { string s=EnumToString(tf); return StringSubstr(s,7); } // strip "PERIOD_"

int TrendColor(const int trend)
  {
   if(trend==1)  return COL_BULL;
   if(trend==-1) return COL_BEAR;
   return COL_NEUTRAL;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0 ,Line1   ,INDICATOR_DATA);
   SetIndexBuffer(1 ,Line1Col,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2 ,Up1     ,INDICATOR_DATA);
   SetIndexBuffer(3 ,Dn1     ,INDICATOR_DATA);
   SetIndexBuffer(4 ,Line2   ,INDICATOR_DATA);
   SetIndexBuffer(5 ,Line2Col,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(6 ,Up2     ,INDICATOR_DATA);
   SetIndexBuffer(7 ,Dn2     ,INDICATOR_DATA);
   SetIndexBuffer(8 ,Line3   ,INDICATOR_DATA);
   SetIndexBuffer(9 ,Line3Col,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(10,Up3     ,INDICATOR_DATA);
   SetIndexBuffer(11,Dn3     ,INDICATOR_DATA);

   //--- arrow codes: up plots 1/4/7 = 233, down plots 2/5/8 = 234
   int upPlots[3] = {1,4,7};
   int dnPlots[3] = {2,5,8};
   for(int k=0;k<3;k++)
     {
      PlotIndexSetInteger(upPlots[k],PLOT_ARROW,233);
      PlotIndexSetInteger(dnPlots[k],PLOT_ARROW,234);
      PlotIndexSetInteger(upPlots[k],PLOT_ARROW_SHIFT,0);
      PlotIndexSetInteger(dnPlots[k],PLOT_ARROW_SHIFT,0);
     }
   for(int p=0;p<9;p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   g_pip = ((_Digits==3 || _Digits==5) ? 10.0 : 1.0) * _Point;

   //--- configure rows
   rows[0].tf = ResolveTF(InpTF1);
   rows[1].tf = ResolveTF(InpTF2);
   rows[2].tf = ResolveTF(InpTF3);

   int per = MathMax(1,InpSmmaPeriod);
   for(int r=0;r<3;r++)
     {
      rows[r].handleHigh = iMA(_Symbol,rows[r].tf,per,0,MODE_SMMA,PRICE_HIGH);
      rows[r].handleLow  = iMA(_Symbol,rows[r].tf,per,0,MODE_SMMA,PRICE_LOW);
      rows[r].n = 0;
      if(rows[r].handleHigh==INVALID_HANDLE || rows[r].handleLow==INVALID_HANDLE)
        {
         Print("SMMA_TrendFlat_MTF_x3: failed iMA handle(s) for row ",r+1);
         return(INIT_FAILED);
        }
     }

   //--- label lines in the Data Window with their timeframe
   PlotIndexSetString(0,PLOT_LABEL,"R1 "+TFToStr(rows[0].tf));
   PlotIndexSetString(3,PLOT_LABEL,"R2 "+TFToStr(rows[1].tf));
   PlotIndexSetString(6,PLOT_LABEL,"R3 "+TFToStr(rows[2].tf));

   g_row1LastClosed = 0;

   IndicatorSetInteger(INDICATOR_DIGITS,0);
   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("SMMA Flat x3 [%s/%s/%s] (%d)",
                   TFToStr(rows[0].tf),TFToStr(rows[1].tf),TFToStr(rows[2].tf),per));
   IndicatorSetDouble(INDICATOR_MINIMUM,0.0);
   IndicatorSetDouble(INDICATOR_MAXIMUM,6.0);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   for(int r=0;r<3;r++)
     {
      if(rows[r].handleHigh!=INVALID_HANDLE) IndicatorRelease(rows[r].handleHigh);
      if(rows[r].handleLow !=INVALID_HANDLE) IndicatorRelease(rows[r].handleLow);
     }
  }

//+------------------------------------------------------------------+
//| Greatest index in ascending t[] with t[idx] <= tt (-1 if before). |
//+------------------------------------------------------------------+
int FindHtfIndex(const datetime &t[],const int n,const datetime tt)
  {
   if(n<=0 || tt<t[0]) return -1;
   int lo=0, hi=n-1, ans=0;
   while(lo<=hi)
     {
      int mid=(lo+hi)/2;
      if(t[mid]<=tt){ ans=mid; lo=mid+1; }
      else hi=mid-1;
     }
   return ans;
  }

//+------------------------------------------------------------------+
//| Shared trend rule for one bar.                                    |
//+------------------------------------------------------------------+
int EvalTrend(const int prevTrend,const bool allowed,
              const double o,const double c,
              const double smH,const double smL,const double thr)
  {
   if(!allowed) return prevTrend;
   bool green = (c > o);
   bool red   = (c < o);
   if(green && c > smH + thr) return  1;
   if(red   && c < smL - thr) return -1;
   return prevTrend;
  }

//+------------------------------------------------------------------+
//| Compute one row on its timeframe and map it onto the chart bars.  |
//+------------------------------------------------------------------+
void ProcessRow(RowState &R,const double level,const double thr,const int per,
                const int rates_total,const int prev_calculated,
                const datetime &time[],
                double &lineBuf[],double &colBuf[],double &upBuf[],double &dnBuf[])
  {
   int barsTf = Bars(_Symbol,R.tf);
   int calcH  = BarsCalculated(R.handleHigh);
   int calcL  = BarsCalculated(R.handleLow);
   int n = (int)MathMin((double)barsTf,MathMin((double)calcH,(double)calcL));

   int start = (prev_calculated>0) ? prev_calculated-1 : 0;

   if(n <= per+1)   // not enough data yet: blank this row's redraw range
     {
      for(int i=start;i<rates_total;i++)
        { lineBuf[i]=EMPTY_VALUE; colBuf[i]=COL_NEUTRAL; upBuf[i]=EMPTY_VALUE; dnBuf[i]=EMPTY_VALUE; }
      R.n=0;
      return;
     }

   ArrayResize(R.aTime,n);  ArrayResize(R.aOpen,n);  ArrayResize(R.aHigh,n);
   ArrayResize(R.aLow,n);   ArrayResize(R.aClose,n); ArrayResize(R.aSmH,n);
   ArrayResize(R.aSmL,n);   ArrayResize(R.aTrend,n);
   ArrayResize(R.aLongFlip,n); ArrayResize(R.aShortFlip,n);

   //--- copy row-TF data as series, then reverse into ascending arrays
   datetime tT[]; double tO[],tH[],tL[],tC[],tSH[],tSL[];
   ArraySetAsSeries(tT,true);  ArraySetAsSeries(tO,true);  ArraySetAsSeries(tH,true);
   ArraySetAsSeries(tL,true);  ArraySetAsSeries(tC,true);
   ArraySetAsSeries(tSH,true); ArraySetAsSeries(tSL,true);

   if(CopyTime (_Symbol,R.tf,0,n,tT) != n) { R.n=0; return; }
   if(CopyOpen (_Symbol,R.tf,0,n,tO) != n) { R.n=0; return; }
   if(CopyHigh (_Symbol,R.tf,0,n,tH) != n) { R.n=0; return; }
   if(CopyLow  (_Symbol,R.tf,0,n,tL) != n) { R.n=0; return; }
   if(CopyClose(_Symbol,R.tf,0,n,tC) != n) { R.n=0; return; }
   if(CopyBuffer(R.handleHigh,0,0,n,tSH) != n) { R.n=0; return; }
   if(CopyBuffer(R.handleLow ,0,0,n,tSL) != n) { R.n=0; return; }

   for(int k=0;k<n;k++)
     {
      int d=n-1-k;
      R.aTime[d]=tT[k]; R.aOpen[d]=tO[k]; R.aHigh[d]=tH[k];
      R.aLow[d]=tL[k];  R.aClose[d]=tC[k]; R.aSmH[d]=tSH[k]; R.aSmL[d]=tSL[k];
     }

   //--- trend engine over row bars (closed bars only; last bar is forming)
   for(int j=0;j<n;j++)
     {
      int  prevT   = (j>0) ? (int)R.aTrend[j-1] : 0;
      bool allowed = (j<n-1) && (j>=per);
      int  t       = EvalTrend(prevT,allowed,R.aOpen[j],R.aClose[j],
                               R.aSmH[j],R.aSmL[j],thr);
      R.aTrend[j]     = t;
      R.aLongFlip[j]  = (t== 1 && prevT!= 1) ? 1 : 0;
      R.aShortFlip[j] = (t==-1 && prevT!=-1) ? 1 : 0;
     }
   R.n = n;

   //--- map onto chart bars (redraw the last two row bars + incremental tail)
   datetime redrawFrom = R.aTime[MathMax(0,n-2)];
   int dispStart = start;
   while(dispStart>0 && time[dispStart-1] >= redrawFrom)
      dispStart--;

   int prevMapped = (dispStart>0) ? FindHtfIndex(R.aTime,n,time[dispStart-1]) : -2;
   for(int i=dispStart;i<rates_total;i++)
     {
      int  hIdx       = FindHtfIndex(R.aTime,n,time[i]);
      bool firstOfBar = (hIdx != prevMapped);
      if(hIdx<0)
        {
         lineBuf[i]=EMPTY_VALUE; colBuf[i]=COL_NEUTRAL;
         upBuf[i]=EMPTY_VALUE;   dnBuf[i]=EMPTY_VALUE;
        }
      else
        {
         lineBuf[i]=level;
         colBuf[i]=TrendColor((int)R.aTrend[hIdx]);
         upBuf[i] = (InpShowArrows && firstOfBar && R.aLongFlip[hIdx] >0.5)
                    ? (level - InpArrowGap) : EMPTY_VALUE;   // green arrow BELOW
         dnBuf[i] = (InpShowArrows && firstOfBar && R.aShortFlip[hIdx]>0.5)
                    ? (level + InpArrowGap) : EMPTY_VALUE;   // red arrow ABOVE
        }
      prevMapped = hIdx;
     }
  }

//+------------------------------------------------------------------+
void FireAlert(const bool bull)
  {
   string dir = bull ? "BULLISH" : "BEARISH";
   string msg = StringFormat("%s %s: %s flip aligned with %s & %s",
                _Symbol,dir,TFToStr(rows[0].tf),TFToStr(rows[1].tf),TFToStr(rows[2].tf));
   if(InpAlertPopup) Alert(msg);
   if(InpAlertPush)  SendNotification(msg);
   if(InpAlertPrint) Print(msg);
  }

//+------------------------------------------------------------------+
//| Fire once when Row1 flips and Row2 & Row3 are already aligned.    |
//+------------------------------------------------------------------+
void CheckAlignmentAlert(const int prev_calculated)
  {
   if(!InpEnableAlert) return;
   if(rows[0].n<2 || rows[1].n<1 || rows[2].n<1) return;

   int n1 = rows[0].n;
   datetime closedT = rows[0].aTime[n1-2];   // most recent CLOSED Row-1 bar

   if(g_row1LastClosed==0)                    // prime on first load, do not alert
     { g_row1LastClosed = closedT; return; }
   if(closedT == g_row1LastClosed) return;    // no new Row-1 bar has closed
   g_row1LastClosed = closedT;

   if(prev_calculated==0) return;             // skip history recalculation

   bool flipUp = rows[0].aLongFlip [n1-2] > 0.5;
   bool flipDn = rows[0].aShortFlip[n1-2] > 0.5;
   int  t2 = (int)rows[1].aTrend[rows[1].n-1];
   int  t3 = (int)rows[2].aTrend[rows[2].n-1];

   if(flipUp && t2==1  && t3==1 ) FireAlert(true);
   else if(flipDn && t2==-1 && t3==-1) FireAlert(false);
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
   if(rates_total < 3) return(0);

   ProcessRow(rows[0],LVL1,thr,per,rates_total,prev_calculated,time,Line1,Line1Col,Up1,Dn1);
   ProcessRow(rows[1],LVL2,thr,per,rates_total,prev_calculated,time,Line2,Line2Col,Up2,Dn2);
   ProcessRow(rows[2],LVL3,thr,per,rates_total,prev_calculated,time,Line3,Line3Col,Up3,Dn3);

   CheckAlignmentAlert(prev_calculated);

   return(rates_total);
  }
//+------------------------------------------------------------------+
