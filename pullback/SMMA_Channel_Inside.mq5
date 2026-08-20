//+------------------------------------------------------------------+
//|                                         SMMA_Channel_Inside.mq5   |
//|   Two-SMMA price channel with inside-candle markers.              |
//+------------------------------------------------------------------+
#property copyright "SMMA Channel Inside"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

#property indicator_label1  "SMMA High"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "SMMA Low"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrTomato
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

#property indicator_label3  "Inside Channel"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrGold
#property indicator_width3  1

enum ENUM_INSIDE_CHANNEL_MODE
  {
   INSIDE_FULL_CANDLE = 0, // High and low must be inside the channel
   INSIDE_CANDLE_BODY = 1  // Open and close must be inside the channel
  };

input int                      InpSmmaPeriod     = 21;                 // SMMA period
input ENUM_INSIDE_CHANNEL_MODE InpContainmentMode = INSIDE_FULL_CANDLE; // Signal mode
input color                    InpUpperColor     = clrDodgerBlue;      // Upper channel color
input color                    InpLowerColor     = clrTomato;          // Lower channel color
input int                      InpChannelWidth   = 1;                  // Channel line width
input color                    InpDotColor       = clrGold;            // Signal dot color
input int                      InpDotSize        = 2;                  // Signal dot size
input int                      InpDotGapPixels   = 8;                  // Dot gap above candle (pixels)

double UpperBuffer[];
double LowerBuffer[];
double DotBuffer[];

int g_smma_high = INVALID_HANDLE;
int g_smma_low  = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpSmmaPeriod < 1 || InpChannelWidth < 1 || InpChannelWidth > 5 ||
      InpDotSize < 1 || InpDotSize > 5 || InpDotGapPixels < 0)
     {
      Print("SMMA Channel Inside: invalid input parameters");
      return(INIT_PARAMETERS_INCORRECT);
     }

   SetIndexBuffer(0,UpperBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,LowerBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,DotBuffer,INDICATOR_DATA);
   ArraySetAsSeries(UpperBuffer,false);
   ArraySetAsSeries(LowerBuffer,false);
   ArraySetAsSeries(DotBuffer,false);

   PlotIndexSetInteger(0,PLOT_LINE_COLOR,InpUpperColor);
   PlotIndexSetInteger(1,PLOT_LINE_COLOR,InpLowerColor);
   PlotIndexSetInteger(0,PLOT_LINE_WIDTH,InpChannelWidth);
   PlotIndexSetInteger(1,PLOT_LINE_WIDTH,InpChannelWidth);
   PlotIndexSetInteger(2,PLOT_LINE_COLOR,InpDotColor);
   PlotIndexSetInteger(2,PLOT_LINE_WIDTH,InpDotSize);
   PlotIndexSetInteger(2,PLOT_ARROW,159); // Wingdings filled circle
   PlotIndexSetInteger(2,PLOT_ARROW_SHIFT,-InpDotGapPixels);

   for(int plot=0; plot<3; plot++)
     {
      PlotIndexSetDouble(plot,PLOT_EMPTY_VALUE,EMPTY_VALUE);
      PlotIndexSetInteger(plot,PLOT_DRAW_BEGIN,InpSmmaPeriod-1);
     }

   g_smma_high=iMA(_Symbol,_Period,InpSmmaPeriod,0,MODE_SMMA,PRICE_HIGH);
   g_smma_low =iMA(_Symbol,_Period,InpSmmaPeriod,0,MODE_SMMA,PRICE_LOW);
   if(g_smma_high==INVALID_HANDLE || g_smma_low==INVALID_HANDLE)
     {
      Print("SMMA Channel Inside: failed to create SMMA handles. Error ",GetLastError());
      return(INIT_FAILED);
     }

   IndicatorSetString(INDICATOR_SHORTNAME,
                      "SMMA Channel Inside ("+(string)InpSmmaPeriod+")");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_smma_high!=INVALID_HANDLE)
      IndicatorRelease(g_smma_high);
   if(g_smma_low!=INVALID_HANDLE)
      IndicatorRelease(g_smma_low);
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
   if(rates_total < InpSmmaPeriod)
      return(0);

   if(BarsCalculated(g_smma_high) < rates_total ||
      BarsCalculated(g_smma_low) < rates_total)
      return(prev_calculated);

   ArraySetAsSeries(open,false);
   ArraySetAsSeries(high,false);
   ArraySetAsSeries(low,false);
   ArraySetAsSeries(close,false);

   if(CopyBuffer(g_smma_high,0,0,rates_total,UpperBuffer)!=rates_total ||
      CopyBuffer(g_smma_low,0,0,rates_total,LowerBuffer)!=rates_total)
      return(prev_calculated);

   int start=(prev_calculated>0) ? prev_calculated-1 : 0;
   for(int i=start; i<rates_total; i++)
     {
      DotBuffer[i]=EMPTY_VALUE;
      if(i < InpSmmaPeriod-1)
         continue;

      bool is_inside=false;
      if(InpContainmentMode==INSIDE_FULL_CANDLE)
         is_inside=(high[i]<=UpperBuffer[i] && low[i]>=LowerBuffer[i]);
      else
        {
         const double body_top=MathMax(open[i],close[i]);
         const double body_bottom=MathMin(open[i],close[i]);
         is_inside=(body_top<=UpperBuffer[i] && body_bottom>=LowerBuffer[i]);
        }

      if(is_inside)
         DotBuffer[i]=high[i];
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
