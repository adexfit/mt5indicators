//+------------------------------------------------------------------+
//|                                           SessionBackground.mq5 |
//|  Draws a light, low-height rectangle behind price candles,      |
//|  colored per forex session. Rectangle bounds = session's        |
//|  high/low range so far, and its right edge extends as new       |
//|  candles print within the same session. CPU-light: historical   |
//|  bars are processed once (prev_calculated), and each tick only  |
//|  touches the single in-progress rectangle.                      |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0
#property strict

//--- Session UTC hour ranges (edit GmtOffsetHours below to match your broker)
input group "=== Broker Time Alignment ==="
input int    GmtOffsetHours   = 0;      // Broker server time minus UTC (e.g. 2 or 3)

input group "=== Session Hours (UTC, 0-23) ==="
input int    AsianStartHour   = 23;     // Asian session start (wraps past midnight)
input int    AsianEndHour     = 8;      // Asian session end
input int    LondonStartHour  = 7;      // London session start
input int    LondonEndHour    = 16;     // London session end
input int    NYStartHour      = 12;     // New York session start
input int    NYEndHour        = 21;     // New York session end

enum ENUM_DISPLAY_MODE
{
   MODE_FILLED      = 0,   // Filled tint (blends with dark background)
   MODE_BORDER_ONLY = 1    // Colored stroke outline only, no fill
};

input group "=== Appearance ==="
input ENUM_DISPLAY_MODE DisplayMode = MODE_FILLED;   // how sessions are drawn

input color  AsianColor       = C'22,36,62';    // muted indigo-blue  (fill mode)
input color  LondonColor      = C'20,52,44';    // muted emerald      (fill mode)
input color  NYColor          = C'60,40,20';    // muted amber/copper (fill mode)

input color  AsianBorderColor  = C'70,130,255';  // vivid blue    (border-only mode)
input color  LondonBorderColor = C'46,204,113';  // vivid emerald (border-only mode)
input color  NYBorderColor     = C'255,159,28';  // vivid amber   (border-only mode)
input int    BorderWidth       = 1;              // stroke thickness in border-only mode

input double VerticalPaddingPct = 3.0;             // % of session range added top/bottom (0 = none)

input group "=== Housekeeping ==="
input int    MaxRectangles    = 300;    // delete oldest boxes beyond this count
input string ObjPrefix        = "SessBG_";

//--- runtime state (persists across OnCalculate calls)
int      g_lastSession   = -999;   // session id of previously processed bar (-1 = none, -999 = unset)
datetime g_blockStart    = 0;
double   g_blockHigh     = 0.0;
double   g_blockLow      = 0.0;
string   g_curRectName   = "";

//+------------------------------------------------------------------+
int OnInit()
{
   g_lastSession = -999;
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, ObjPrefix);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Returns 0=Asian, 1=London, 2=NewYork, -1=none. Checked in that   |
//| order, so an overlap (e.g. London/NY) is colored by the first    |
//| match — Asian, then London, then NY.                             |
//+------------------------------------------------------------------+
int GetSession(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   int h = (dt.hour - GmtOffsetHours + 24) % 24;

   if(InRange(h, AsianStartHour,  AsianEndHour))  return 0;
   if(InRange(h, LondonStartHour, LondonEndHour)) return 1;
   if(InRange(h, NYStartHour,     NYEndHour))     return 2;
   return -1;
}

bool InRange(int h, int startH, int endH)
{
   if(startH == endH) return false;
   if(startH < endH)
      return (h >= startH && h < endH);
   // wraps past midnight
   return (h >= startH || h < endH);
}

color SessionColor(int sess)
{
   if(sess == 0) return AsianColor;
   if(sess == 1) return LondonColor;
   if(sess == 2) return NYColor;
   return clrNONE;
}

color SessionBorderColor(int sess)
{
   if(sess == 0) return AsianBorderColor;
   if(sess == 1) return LondonBorderColor;
   if(sess == 2) return NYBorderColor;
   return clrNONE;
}

//+------------------------------------------------------------------+
//| Create the rectangle object if it doesn't exist yet               |
//+------------------------------------------------------------------+
void EnsureRectExists(const string name, int sess)
{
   if(ObjectFind(0, name) >= 0) return;

   bool  isBorderOnly = (DisplayMode == MODE_BORDER_ONLY);
   color c = isBorderOnly ? SessionBorderColor(sess) : SessionColor(sess);

   ObjectCreate(0, name, OBJ_RECTANGLE, 0, g_blockStart, g_blockHigh, g_blockStart, g_blockLow);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, isBorderOnly ? BorderWidth : 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);            // behind candles
   ObjectSetInteger(0, name, OBJPROP_FILL, !isBorderOnly);   // filled tint, or stroke-only
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);          // keep it out of the object list
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
}

//+------------------------------------------------------------------+
//| Update a rectangle's extent to the current block's bounds         |
//+------------------------------------------------------------------+
void UpdateRect(const string name, datetime t2)
{
   double range = g_blockHigh - g_blockLow;
   double pad   = (VerticalPaddingPct > 0.0) ? range * VerticalPaddingPct / 100.0 : 0.0;

   ObjectSetInteger(0, name, OBJPROP_TIME,  0, g_blockStart);
   ObjectSetInteger(0, name, OBJPROP_TIME,  1, t2);
   ObjectSetDouble (0, name, OBJPROP_PRICE, 0, g_blockHigh + pad);
   ObjectSetDouble (0, name, OBJPROP_PRICE, 1, g_blockLow  - pad);
}

//+------------------------------------------------------------------+
//| Trim oldest rectangles beyond MaxRectangles (cheap, runs rarely)  |
//+------------------------------------------------------------------+
void TrimOldRectangles()
{
   int total = ObjectsTotal(0, 0, OBJ_RECTANGLE);
   int prefixLen = StringLen(ObjPrefix);

   // collect matching names
   string names[];
   int n = 0;
   for(int i = 0; i < total; i++)
   {
      string nm = ObjectName(0, i, 0, OBJ_RECTANGLE);
      if(StringSubstr(nm, 0, prefixLen) == ObjPrefix)
      {
         ArrayResize(names, n + 1);
         names[n] = nm;
         n++;
      }
   }
   if(n <= MaxRectangles) return;

   // names embed the block start time, so ascending string/number sort = chronological
   ArraySort(names);
   int toDelete = n - MaxRectangles;
   for(int i = 0; i < toDelete; i++)
      ObjectDelete(0, names[i]);
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
   if(rates_total < 1) return 0;

   int start = (prev_calculated <= 1) ? 0 : prev_calculated - 1;
   if(prev_calculated <= 1) g_lastSession = -999; // full recalc: reset state

   datetime periodSecs = (datetime)PeriodSeconds();
   bool createdNewBlock = false;

   for(int i = start; i < rates_total; i++)
   {
      int sess = GetSession(time[i]);

      if(sess != g_lastSession)
      {
         // session changed -> start a new block
         g_lastSession = sess;
         g_blockStart  = time[i];
         g_blockHigh   = high[i];
         g_blockLow    = low[i];
         g_curRectName = ObjPrefix + IntegerToString((long)time[i]);
         if(sess >= 0)
         {
            EnsureRectExists(g_curRectName, sess);
            createdNewBlock = true;
         }
      }
      else
      {
         if(high[i] > g_blockHigh) g_blockHigh = high[i];
         if(low[i]  < g_blockLow)  g_blockLow  = low[i];
      }

      if(sess >= 0)
         UpdateRect(g_curRectName, time[i] + periodSecs);
   }

   if(createdNewBlock)
      TrimOldRectangles();

   return rates_total;
}
//+------------------------------------------------------------------+
