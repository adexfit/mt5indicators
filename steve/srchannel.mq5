#property copyright "Pine Script original by LonesomeTheBlue; MT5 conversion"
#property link      "https://www.mozilla.org/MPL/2.0/"
#property version   "1.10"
#property indicator_chart_window
#property indicator_buffers 32
#property indicator_plots   32

input ENUM_TIMEFRAMES InpHigherTimeframe = PERIOD_D1;
input int             InpPivotPeriod = 5;
input int             InpLookback = 250;
input double          InpMaxChannelWidthPercent = 6.0;
input int             InpMinimumStrength = 2;
input int             InpMaximumChannels = 6;
input bool            InpShowZones = true;
// Kept for input compatibility. Zones are always drawn so they remain visible
// while scrolling, changing timeframe, and running the visual tester.
input bool            InpShowOnlyVisibleZones = false;
input bool            InpShowTable = true;
input ENUM_BASE_CORNER InpTableCorner = CORNER_LEFT_LOWER;
input color           InpResistanceColor = C'72,38,48';
input color           InpSupportColor = C'28,66,55';
input color           InpInsideChannelColor = C'54,58,70';
input bool            InpEnableBreakAlerts = false;

double Buffer00[], Buffer01[], Buffer02[], Buffer03[], Buffer04[], Buffer05[];
double Buffer06[], Buffer07[], Buffer08[], Buffer09[], Buffer10[], Buffer11[];
double Buffer12[], Buffer13[], Buffer14[], Buffer15[], Buffer16[], Buffer17[];
double Buffer18[], Buffer19[], Buffer20[], Buffer21[], Buffer22[], Buffer23[];
double Buffer24[], Buffer25[], Buffer26[], Buffer27[], Buffer28[], Buffer29[];
double ResistanceBreakBuffer[], SupportBreakBuffer[];

double   g_upper[10], g_lower[10], g_strength[10];
int      g_channel_count = 0;
bool     g_calculation_ready = false;
datetime g_last_chart_bar = 0;
datetime g_last_source_bar = 0;
ENUM_TIMEFRAMES g_last_chart_period = PERIOD_CURRENT;
double   g_last_chart_high = EMPTY_VALUE;
double   g_last_chart_low = EMPTY_VALUE;
double   g_last_source_high = EMPTY_VALUE;
double   g_last_source_low = EMPTY_VALUE;
datetime g_last_resistance_alert_bar = 0;
datetime g_last_support_alert_bar = 0;
string   g_object_prefix;

int ClampInt(const int value, const int minimum, const int maximum)
{
   return (int)MathMax(minimum, MathMin(maximum, value));
}

void BindBuffer(const int index, double &buffer[])
{
   SetIndexBuffer(index, buffer, INDICATOR_DATA);
   ArraySetAsSeries(buffer, true);
   PlotIndexSetInteger(index, PLOT_DRAW_TYPE, DRAW_NONE);
   PlotIndexSetDouble(index, PLOT_EMPTY_VALUE, EMPTY_VALUE);
}

void InitialiseBuffers()
{
   ArrayInitialize(Buffer00, EMPTY_VALUE); ArrayInitialize(Buffer01, EMPTY_VALUE);
   ArrayInitialize(Buffer02, EMPTY_VALUE); ArrayInitialize(Buffer03, EMPTY_VALUE);
   ArrayInitialize(Buffer04, EMPTY_VALUE); ArrayInitialize(Buffer05, EMPTY_VALUE);
   ArrayInitialize(Buffer06, EMPTY_VALUE); ArrayInitialize(Buffer07, EMPTY_VALUE);
   ArrayInitialize(Buffer08, EMPTY_VALUE); ArrayInitialize(Buffer09, EMPTY_VALUE);
   ArrayInitialize(Buffer10, EMPTY_VALUE); ArrayInitialize(Buffer11, EMPTY_VALUE);
   ArrayInitialize(Buffer12, EMPTY_VALUE); ArrayInitialize(Buffer13, EMPTY_VALUE);
   ArrayInitialize(Buffer14, EMPTY_VALUE); ArrayInitialize(Buffer15, EMPTY_VALUE);
   ArrayInitialize(Buffer16, EMPTY_VALUE); ArrayInitialize(Buffer17, EMPTY_VALUE);
   ArrayInitialize(Buffer18, EMPTY_VALUE); ArrayInitialize(Buffer19, EMPTY_VALUE);
   ArrayInitialize(Buffer20, EMPTY_VALUE); ArrayInitialize(Buffer21, EMPTY_VALUE);
   ArrayInitialize(Buffer22, EMPTY_VALUE); ArrayInitialize(Buffer23, EMPTY_VALUE);
   ArrayInitialize(Buffer24, EMPTY_VALUE); ArrayInitialize(Buffer25, EMPTY_VALUE);
   ArrayInitialize(Buffer26, EMPTY_VALUE); ArrayInitialize(Buffer27, EMPTY_VALUE);
   ArrayInitialize(Buffer28, EMPTY_VALUE); ArrayInitialize(Buffer29, EMPTY_VALUE);
   ArrayInitialize(ResistanceBreakBuffer, 0.0);
   ArrayInitialize(SupportBreakBuffer, 0.0);
}

void SetChannelBuffer(const int channel, const double upper, const double lower, const double strength)
{
   switch(channel)
   {
      case 0: Buffer00[0]=upper; Buffer01[0]=lower; Buffer02[0]=strength; break;
      case 1: Buffer03[0]=upper; Buffer04[0]=lower; Buffer05[0]=strength; break;
      case 2: Buffer06[0]=upper; Buffer07[0]=lower; Buffer08[0]=strength; break;
      case 3: Buffer09[0]=upper; Buffer10[0]=lower; Buffer11[0]=strength; break;
      case 4: Buffer12[0]=upper; Buffer13[0]=lower; Buffer14[0]=strength; break;
      case 5: Buffer15[0]=upper; Buffer16[0]=lower; Buffer17[0]=strength; break;
      case 6: Buffer18[0]=upper; Buffer19[0]=lower; Buffer20[0]=strength; break;
      case 7: Buffer21[0]=upper; Buffer22[0]=lower; Buffer23[0]=strength; break;
      case 8: Buffer24[0]=upper; Buffer25[0]=lower; Buffer26[0]=strength; break;
      case 9: Buffer27[0]=upper; Buffer28[0]=lower; Buffer29[0]=strength; break;
   }
}

void PublishChannels()
{
   for(int channel=0; channel<10; channel++)
   {
      if(channel < g_channel_count)
         SetChannelBuffer(channel, g_upper[channel], g_lower[channel], g_strength[channel]);
      else
         SetChannelBuffer(channel, EMPTY_VALUE, EMPTY_VALUE, EMPTY_VALUE);
   }
}

bool CalculateChannels()
{
   double previous_upper[10], previous_lower[10], previous_strength[10];
   ArrayCopy(previous_upper, g_upper);
   ArrayCopy(previous_lower, g_lower);
   ArrayCopy(previous_strength, g_strength);
   const int previous_channel_count = g_channel_count;

   g_channel_count = 0;
   ArrayInitialize(g_upper, 0.0);
   ArrayInitialize(g_lower, 0.0);
   ArrayInitialize(g_strength, 0.0);

   const int pivot_period = ClampInt(InpPivotPeriod, 1, 30);
   const int lookback = ClampInt(InpLookback, 50, 400);
   const int minimum_required = pivot_period * 10;

   MqlRates source_rates[];
   ArraySetAsSeries(source_rates, true);
   const int copied = CopyRates(_Symbol, InpHigherTimeframe, 0, lookback, source_rates);
   if(copied < minimum_required)
   {
      ArrayCopy(g_upper, previous_upper);
      ArrayCopy(g_lower, previous_lower);
      ArrayCopy(g_strength, previous_strength);
      g_channel_count = previous_channel_count;
      return false;
   }

   double pivots[];
   ArrayResize(pivots, copied * 2);
   int pivot_count = 0;

   for(int x=pivot_period; x<copied-pivot_period; x++)
   {
      bool is_high = true;
      bool is_low = true;
      for(int offset=1; offset<=pivot_period && (is_high || is_low); offset++)
      {
         if(source_rates[x].high < source_rates[x-offset].high ||
            source_rates[x].high < source_rates[x+offset].high)
            is_high = false;
         if(source_rates[x].low > source_rates[x-offset].low ||
            source_rates[x].low > source_rates[x+offset].low)
            is_low = false;
      }
      if(is_high)
         pivots[pivot_count++] = source_rates[x].high;
      if(is_low)
         pivots[pivot_count++] = source_rates[x].low;
   }

   if(pivot_count == 0)
   {
      ArrayCopy(g_upper, previous_upper);
      ArrayCopy(g_lower, previous_lower);
      ArrayCopy(g_strength, previous_strength);
      g_channel_count = previous_channel_count;
      return false;
   }

   double highest = pivots[0];
   double lowest = pivots[0];
   for(int i=1; i<pivot_count; i++)
   {
      highest = MathMax(highest, pivots[i]);
      lowest = MathMin(lowest, pivots[i]);
   }
   const double width_percent = MathMax(1.0, MathMin(15.0, InpMaxChannelWidthPercent));
   const double channel_width = (highest - lowest) * width_percent / 100.0;

   double candidate_upper[], candidate_lower[], candidate_strength[];
   ArrayResize(candidate_upper, pivot_count);
   ArrayResize(candidate_lower, pivot_count);
   ArrayResize(candidate_strength, pivot_count);

   for(int x=0; x<pivot_count; x++)
   {
      double upper = pivots[x];
      double lower = pivots[x];
      double strength = 0.0;
      for(int y=0; y<pivot_count; y++)
      {
         const double pivot = pivots[y];
         const double width = (pivot <= upper) ? upper - pivot : pivot - lower;
         if(width <= channel_width)
         {
            if(pivot <= upper)
               lower = MathMin(lower, pivot);
            else
               upper = MathMax(upper, pivot);
            strength += 20.0;
         }
      }
      candidate_upper[x] = upper;
      candidate_lower[x] = lower;
      candidate_strength[x] = strength;
   }

   MqlRates chart_rates[];
   ArraySetAsSeries(chart_rates, true);
   const int touch_bars = CopyRates(_Symbol, _Period, 0, 500, chart_rates);
   if(touch_bars > 0)
   {
      for(int x=0; x<pivot_count; x++)
      {
         int touches = 0;
         const double upper = candidate_upper[x];
         const double lower = candidate_lower[x];
         for(int y=0; y<touch_bars; y++)
         {
            if((chart_rates[y].high  <= upper && chart_rates[y].high  >= lower) ||
               (chart_rates[y].low   <= upper && chart_rates[y].low   >= lower) ||
               (chart_rates[y].open  <= upper && chart_rates[y].open  >= lower) ||
               (chart_rates[y].close <= upper && chart_rates[y].close >= lower))
               touches++;
         }
         candidate_strength[x] += touches;
      }
   }

   const int maximum_channels = ClampInt(InpMaximumChannels, 1, 10);
   const double minimum_strength = MathMax(1, InpMinimumStrength) * 20.0;
   for(int slot=0; slot<maximum_channels && g_channel_count<10; slot++)
   {
      int strongest_index = -1;
      double strongest_value = -1.0;
      for(int candidate=0; candidate<pivot_count; candidate++)
      {
         if(candidate_strength[candidate] > strongest_value &&
            candidate_strength[candidate] >= minimum_strength)
         {
            strongest_index = candidate;
            strongest_value = candidate_strength[candidate];
         }
      }
      if(strongest_index < 0)
         break;

      const double selected_upper = candidate_upper[strongest_index];
      const double selected_lower = candidate_lower[strongest_index];
      g_upper[g_channel_count] = selected_upper;
      g_lower[g_channel_count] = selected_lower;
      g_strength[g_channel_count] = strongest_value;
      g_channel_count++;

      for(int candidate=0; candidate<pivot_count; candidate++)
      {
         if((candidate_upper[candidate] <= selected_upper && candidate_upper[candidate] >= selected_lower) ||
            (candidate_lower[candidate] <= selected_upper && candidate_lower[candidate] >= selected_lower))
            candidate_strength[candidate] = -1.0;
      }
   }
   return true;
}

color ZoneColor(const int channel, const double price)
{
   if(g_upper[channel] > price && g_lower[channel] > price)
      return InpResistanceColor;
   if(g_upper[channel] < price && g_lower[channel] < price)
      return InpSupportColor;
   return InpInsideChannelColor;
}

void DeleteZone(const int channel)
{
   ObjectDelete(0, g_object_prefix + "Zone" + IntegerToString(channel + 1));
}

void GetZoneTimeRange(datetime &left_time, datetime &right_time)
{
   left_time = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_FIRSTDATE);
   const datetime latest_bar = iTime(_Symbol, _Period, 0);
   if(left_time <= 0)
      left_time = latest_bar;
   if(left_time <= 0)
      left_time = TimeCurrent();

   int seconds = PeriodSeconds(_Period);
   if(seconds <= 0)
      seconds = 60;
   // The left anchor covers all currently loaded history. The right anchor is
   // kept in the future so the zone is visible on the live edge as well.
   datetime current_time = TimeCurrent();
   datetime right_base = MathMax(current_time, latest_bar);
   if(right_base <= left_time)
      right_base = left_time + (datetime)seconds;
   right_time = right_base + (datetime)((long)seconds * 100);
}

void DrawZones(const double price)
{
   datetime left_time, right_time;
   GetZoneTimeRange(left_time, right_time);

   for(int channel=0; channel<10; channel++)
   {
      bool visible = channel < g_channel_count && InpShowZones;
      if(!visible)
      {
         DeleteZone(channel);
         continue;
      }

      string name = g_object_prefix + "Zone" + IntegerToString(channel + 1);
      if(ObjectFind(0, name) < 0)
      {
         if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, left_time, g_upper[channel], right_time, g_lower[channel]))
            continue;
      }
      else
      {
         if(!ObjectMove(0, name, 0, left_time, g_upper[channel]) ||
            !ObjectMove(0, name, 1, right_time, g_lower[channel]))
         {
            ObjectDelete(0, name);
            if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, left_time, g_upper[channel], right_time, g_lower[channel]))
               continue;
         }
      }
      ObjectSetInteger(0, name, OBJPROP_COLOR, ZoneColor(channel, price));
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
}

void UpdateZoneColors(const double price)
{
   for(int channel=0; channel<g_channel_count; channel++)
   {
      string name = g_object_prefix + "Zone" + IntegerToString(channel + 1);
      if(ObjectFind(0, name) >= 0)
         ObjectSetInteger(0, name, OBJPROP_COLOR, ZoneColor(channel, price));
   }
}

void UpdateTable(const double price)
{
   string name = g_object_prefix + "Table";
   if(!InpShowTable)
   {
      ObjectDelete(0, name);
      return;
   }

   string text = EnumToString(InpHigherTimeframe) + "  S/R channels\n";
   for(int channel=0; channel<g_channel_count; channel++)
   {
      string kind = (g_lower[channel] > price) ? "Resistance" :
                    (g_upper[channel] < price) ? "Support" : "In channel";
      text += IntegerToString(channel + 1) + "  " + kind + "  " +
              DoubleToString(g_lower[channel], _Digits) + " - " +
              DoubleToString(g_upper[channel], _Digits) + "  (" +
              DoubleToString(g_strength[channel], 0) + ")\n";
   }

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, InpTableCorner);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,
                    (InpTableCorner == CORNER_LEFT_LOWER) ? ANCHOR_LEFT_LOWER :
                    (InpTableCorner == CORNER_RIGHT_LOWER) ? ANCHOR_RIGHT_LOWER :
                    (InpTableCorner == CORNER_RIGHT_UPPER) ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 8);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 18);
   ObjectSetInteger(0, name, OBJPROP_COLOR, C'176,184,196');
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

int OnInit()
{
   BindBuffer(0, Buffer00); BindBuffer(1, Buffer01); BindBuffer(2, Buffer02);
   BindBuffer(3, Buffer03); BindBuffer(4, Buffer04); BindBuffer(5, Buffer05);
   BindBuffer(6, Buffer06); BindBuffer(7, Buffer07); BindBuffer(8, Buffer08);
   BindBuffer(9, Buffer09); BindBuffer(10, Buffer10); BindBuffer(11, Buffer11);
   BindBuffer(12, Buffer12); BindBuffer(13, Buffer13); BindBuffer(14, Buffer14);
   BindBuffer(15, Buffer15); BindBuffer(16, Buffer16); BindBuffer(17, Buffer17);
   BindBuffer(18, Buffer18); BindBuffer(19, Buffer19); BindBuffer(20, Buffer20);
   BindBuffer(21, Buffer21); BindBuffer(22, Buffer22); BindBuffer(23, Buffer23);
   BindBuffer(24, Buffer24); BindBuffer(25, Buffer25); BindBuffer(26, Buffer26);
   BindBuffer(27, Buffer27); BindBuffer(28, Buffer28); BindBuffer(29, Buffer29);
   BindBuffer(30, ResistanceBreakBuffer); BindBuffer(31, SupportBreakBuffer);

   for(int channel=0; channel<10; channel++)
   {
      PlotIndexSetString(channel * 3, PLOT_LABEL, "Channel " + IntegerToString(channel + 1) + " Upper");
      PlotIndexSetString(channel * 3 + 1, PLOT_LABEL, "Channel " + IntegerToString(channel + 1) + " Lower");
      PlotIndexSetString(channel * 3 + 2, PLOT_LABEL, "Channel " + IntegerToString(channel + 1) + " Strength");
   }
   PlotIndexSetString(30, PLOT_LABEL, "Resistance Break");
   PlotIndexSetString(31, PLOT_LABEL, "Support Break");

   IndicatorSetString(INDICATOR_SHORTNAME, "SR Channel MTF (" + EnumToString(InpHigherTimeframe) + ")");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   g_object_prefix = "SRChannel_" + IntegerToString((int)ChartID()) + "_" +
                     IntegerToString((int)GetTickCount()) + "_";
   return INIT_SUCCEEDED;
}

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
   if(rates_total < 2)
      return 0;
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   if(prev_calculated == 0)
      InitialiseBuffers();

   const datetime source_bar = iTime(_Symbol, InpHigherTimeframe, 0);
   const double source_high = iHigh(_Symbol, InpHigherTimeframe, 0);
   const double source_low = iLow(_Symbol, InpHigherTimeframe, 0);
   const bool chart_data_changed = (high[0] != g_last_chart_high ||
                                    low[0] != g_last_chart_low);
   const bool source_data_changed = (source_high != g_last_source_high ||
                                     source_low != g_last_source_low);
   const bool must_recalculate = (!g_calculation_ready || time[0] != g_last_chart_bar ||
                                  _Period != g_last_chart_period ||
                                  source_bar != g_last_source_bar || chart_data_changed ||
                                  source_data_changed);
   if(must_recalculate)
   {
      g_calculation_ready = CalculateChannels();
      g_last_chart_bar = time[0];
      g_last_chart_period = _Period;
      g_last_source_bar = source_bar;
      g_last_chart_high = high[0];
      g_last_chart_low = low[0];
      g_last_source_high = source_high;
      g_last_source_low = source_low;
      DrawZones(close[0]);
      UpdateTable(close[0]);
   }
   else
      UpdateZoneColors(close[0]);

   PublishChannels();

   bool in_channel = false;
   for(int channel=0; channel<g_channel_count; channel++)
   {
      if(close[0] <= g_upper[channel] && close[0] >= g_lower[channel])
      {
         in_channel = true;
         break;
      }
   }

   bool resistance_broken = false;
   bool support_broken = false;
   if(!in_channel)
   {
      for(int channel=0; channel<g_channel_count; channel++)
      {
         if(close[1] <= g_upper[channel] && close[0] > g_upper[channel])
            resistance_broken = true;
         if(close[1] >= g_lower[channel] && close[0] < g_lower[channel])
            support_broken = true;
      }
   }
   ResistanceBreakBuffer[0] = resistance_broken ? 1.0 : 0.0;
   SupportBreakBuffer[0] = support_broken ? 1.0 : 0.0;

   if(InpEnableBreakAlerts && resistance_broken && g_last_resistance_alert_bar != time[0])
   {
      Alert(_Symbol, " ", EnumToString(_Period), ": resistance broken");
      g_last_resistance_alert_bar = time[0];
   }
   if(InpEnableBreakAlerts && support_broken && g_last_support_alert_bar != time[0])
   {
      Alert(_Symbol, " ", EnumToString(_Period), ": support broken");
      g_last_support_alert_bar = time[0];
   }
   return rates_total;
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE && g_channel_count > 0)
   {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      DrawZones(price);
      UpdateTable(price);
   }
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, g_object_prefix);
}
