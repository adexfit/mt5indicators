//+------------------------------------------------------------------+
//|                                                   SuperSlope.mq5 |
//|                                  Copyright 2016, Paul Geirnaerdt |
//|                                           http://www.delabron.nl |
//+------------------------------------------------------------------+
#property copyright "Copyright 2016, Paul Geirnaerdt"
#property link      "http://www.delabron.nl"
#property indicator_separate_window
#property indicator_buffers 8
#property indicator_plots   8

#property indicator_type1   DRAW_LINE
#property indicator_type2   DRAW_LINE
#property indicator_type3   DRAW_NONE
#property indicator_type4   DRAW_NONE
#property indicator_type5   DRAW_NONE
#property indicator_type6   DRAW_NONE
#property indicator_type7   DRAW_NONE
#property indicator_type8   DRAW_NONE
#property indicator_label1  "Slope1"
#property indicator_label2  "Slope2"
#property indicator_label3  "BuySignal"
#property indicator_label4  "SellSignal"
#property indicator_label5  "BuyExit"
#property indicator_label6  "SellExit"
#property indicator_label7  "BuyRegime"
#property indicator_label8  "SellRegime"
#property indicator_color1  clrRed
#property indicator_color2  clrDeepSkyBlue
#property indicator_color3  clrLime
#property indicator_color4  clrRed
#property indicator_color5  clrDodgerBlue
#property indicator_color6  clrOrangeRed
#property indicator_color7  clrLime
#property indicator_color8  clrRed

#define version        "v2.0-MQL5"
#define CURRENCYCOUNT  9

//--- General Inputs
input string  gen                  = "----General Inputs----";
input int     maxBars              = 0;
input string  nonPropFont          = "Lucida Console";
input string  spac751              = "----";
input bool    autoTimeFrame        = false;
input string  ind_tf               = "timeFrame M1,M5,M15,M30,H1,H4,D1,W1,MN";
input string  timeFrame            = "D1";
input string  extraTimeFrame       = "W1";
input string  extraTimeFrame2      = "MN";
input int     NoOfTimeFrames       = 3;
input string  spac756              = "---- Slope Inputs ----";
input double  differenceThreshold  = 0.0;
input double  levelCrossValue      = 2.0;
input int     SlopeMAPeriod        = 7;
input int     SlopeATRPeriod       = 50;
input string  spac754              = "---- Send Alerts ----";
input bool    sendCrossAlerts      = true;
input bool    sendLevelCrossAlerts = true;
input bool    sendExitCrossAlerts  = true;
input bool    sendMTFAgreeAlerts   = true;
input string  spac754a             = "----";
input bool    PopupAlert           = true;
input bool    EmailAlert           = true;
input bool    PushAlert            = true;

//--- Display Inputs
input string  disp                     = "----Display Inputs----";
input int     displayTextSize          = 10;
input int     horizontalOffset         = 10;
input int     verticalOffset           = 5;
input int     horizontalShift          = 20;
input int     verticalShift            = 15;
input string  spc1134                  = "---- Multiple Indis ----";
input bool    showSlopeValues          = true;
input bool    showCurrencyLines        = true;
input bool    showLevelCrossLines      = true;
input bool    showBackgroundColor      = true;
input bool    showDifferenceThreshold  = true;
input color   differenceThresholdColor = clrYellow;
input string  spac8574                 = "----";
input int     levelCrossLineSize       = 2;
input int     backgroundLineWidth      = 8;

//--- Arrow Display on Price Chart
input string  gen2                 = "----Arrow Display----";
input bool    showArrowsOnChart    = true;
input color   BuyArrowColor        = clrDarkGreen;
input int     BuyArrowFontSize     = 14;
input color   SellArrowColor       = clrMaroon;
input int     SellArrowFontSize    = 14;
input string  spac456              = "----";
input bool    showSignalLine       = true;
input color   SignalLineBuyColor   = clrDarkGreen;
input color   SignalLineSellColor  = clrDeepPink;
input int     SignalLineSize       = 1;

//--- Read Delay
input string  rede              = "---- Read Delay ----";
input bool    EveryTickMode     = true;
input bool    ReadEveryNewBar   = false;
input int     ReadEveryXSeconds = 5;

//--- Colour Inputs
input string  colour             = "----Colo(u)r inputs----";
input color   Color_USD          = clrRed;
input color   Color_EUR          = clrDeepSkyBlue;
input color   Color_GBP          = clrRoyalBlue;
input color   Color_CHF          = clrPaleTurquoise;
input color   Color_JPY          = clrGold;
input color   Color_AUD          = clrDarkOrange;
input color   Color_CAD          = clrPink;
input color   Color_NZD          = clrTan;
input color   Color_default      = clrWhite;
input int     line_width_USD     = 3;
input int     line_style_USD     = 0;
input int     line_width_EUR     = 3;
input int     line_style_EUR     = 0;
input int     line_width_GBP     = 3;
input int     line_style_GBP     = 0;
input int     line_width_JPY     = 3;
input int     line_style_JPY     = 0;
input int     line_width_AUD     = 3;
input int     line_style_AUD     = 0;
input int     line_width_CAD     = 3;
input int     line_style_CAD     = 0;
input int     line_width_NZD     = 3;
input int     line_style_NZD     = 0;
input int     line_width_CHF     = 3;
input int     line_style_CHF     = 0;
input color   colorWeakCross     = clrGold;
input color   colorNormalCross   = clrGold;
input color   colorStrongCross   = clrGold;
//--- Muted regime colors that remain visible without overpowering a dark chart.
input color   colorDifferenceUp  = C'24,96,54';
input color   colorDifferenceDn  = C'128,42,48';
input color   colorDifferenceLo  = C'48,54,58';
input color   colorTimeframe     = clrWhite;
input color   colorLevelHigh     = clrLimeGreen;
input color   colorLevelLow      = clrCrimson;

//--- Internal
int    ATRPeriodArrows     = 20;
double ATRMultiplierArrows = 1.0;
uchar  BuyArrowStyle       = 225;
uchar  SellArrowStyle      = 226;
bool   TradeLong=false, TradeShort=false;
bool   BuyArrowActive=false, SellArrowActive=false;
bool   OnlyDrawArrowsOnNewBar = true;

bool     IsItNewBar=false, userEveryTickMode, userReadEveryNewBar;
datetime lastBarTime = 0, nextReadTime = 0, lastBarTime2 = 0;
int      userReadEveryXSeconds;
int      leftBarPrev=0, rightBarPrev=0;
bool     _BrokerHasSundayCandles=false;
int      userNoOfTimeFrames;

string   indicatorName="SuperSlope";
string   shortName, almostUniqueIndex;
int      windex=0;
string   ObjSuff, ObjSuff2;
ENUM_TIMEFRAMES userTimeFrame;
ENUM_TIMEFRAMES userExtraTimeFrame;
ENUM_TIMEFRAMES userExtraTimeFrame2;
bool     IsInit=false;
string   objectName="";
double   Slope_2=0, Slope_3=0;

//--- Buffers
double   Slope1[];        // 0 primary slope
double   Slope2[];        // 1 inverse slope
double   BuySignal[];     // 2 1.0 on buy entry bar
double   SellSignal[];    // 3 1.0 on sell entry bar
double   BuyExitSig[];    // 4 1.0 on buy exit bar
double   SellExitSig[];   // 5 1.0 on sell exit bar
double   BuyRegime[];     // 6 1.0 while in long regime
double   SellRegime[];    // 7 1.0 while in short regime

string   currencyNames[CURRENCYCOUNT]={"USD","EUR","GBP","JPY","AUD","CAD","NZD","CHF",""};
int      cline_width[CURRENCYCOUNT];
int      cline_style[CURRENCYCOUNT];
color    currencyColors[CURRENCYCOUNT];
int      cindex=0, cindex2=0;

int hMA_userTF    = INVALID_HANDLE;
int hATR_userTF   = INVALID_HANDLE;
int hMA_extraTF   = INVALID_HANDLE;
int hATR_extraTF  = INVALID_HANDLE;
int hMA_extraTF2  = INVALID_HANDLE;
int hATR_extraTF2 = INVALID_HANDLE;
int hATR_arrows   = INVALID_HANDLE;

//+------------------------------------------------------------------+
void DeleteArrowObjects()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, "Buy Arrow ",  0) >= 0 && StringFind(nm, ObjSuff, 0) > 0)
         ObjectDelete(0, nm);
      else if(StringFind(nm, "Sell Arrow ", 0) >= 0 && StringFind(nm, ObjSuff, 0) > 0)
         ObjectDelete(0, nm);
      else if(StringFind(nm, "Buy Signal Line ",  0) >= 0 && StringFind(nm, ObjSuff, 0) > 0)
         ObjectDelete(0, nm);
      else if(StringFind(nm, "Sell Signal Line ", 0) >= 0 && StringFind(nm, ObjSuff, 0) > 0)
         ObjectDelete(0, nm);
   }
}

int MyTimeDayOfWeek(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.day_of_week;
}

int MyBarShift(string symbol, ENUM_TIMEFRAMES tf, datetime tTime)
{
   datetime currentBarTime = iTime(symbol, tf, 0);
   if(currentBarTime == 0) return 0;
   int shift = Bars(symbol, tf, tTime, currentBarTime);
   if(shift <= 0) return 0;
   return shift - 1;
}

string StringUpperMQL5(string str)
{
   string result = str;
   StringToUpper(result);
   return result;
}

ENUM_TIMEFRAMES StrToTF(string str)
{
   str = StringUpperMQL5(str);
   StringTrimLeft(str);
   StringTrimRight(str);
   if(str == "M1")   return PERIOD_M1;
   if(str == "M5")   return PERIOD_M5;
   if(str == "M15")  return PERIOD_M15;
   if(str == "M30")  return PERIOD_M30;
   if(str == "H1")   return PERIOD_H1;
   if(str == "H4")   return PERIOD_H4;
   if(str == "D1")   return PERIOD_D1;
   if(str == "W1")   return PERIOD_W1;
   if(str == "MN" || str == "MN1") return PERIOD_MN1;
   return PERIOD_CURRENT;
}

string TFToString(ENUM_TIMEFRAMES tf)
{
   if(tf == PERIOD_M1)  return "M1";
   if(tf == PERIOD_M5)  return "M5";
   if(tf == PERIOD_M15) return "M15";
   if(tf == PERIOD_M30) return "M30";
   if(tf == PERIOD_H1)  return "H1";
   if(tf == PERIOD_H4)  return "H4";
   if(tf == PERIOD_D1)  return "D1";
   if(tf == PERIOD_W1)  return "W1";
   if(tf == PERIOD_MN1) return "MN";
   return TFToString(Period());
}

string StringSubstrOld(string x, int a, int b=-1)
{
   if(a < 0) a = 0;
   if(b <= 0) b = -1;
   return StringSubstr(x, a, b);
}

bool CSS_Available(string symbol2check)
{
   for(int i = 0; i < ArraySize(currencyNames); i++)
      if(StringSubstr(symbol2check, 0, 3) == currencyNames[i])
         return true;
   return false;
}

int getCurrencyIndex(string currency)
{
   for(int i = 0; i < CURRENCYCOUNT; i++)
      if(currencyNames[i] == currency)
         return i;
   return -1;
}

int GetDecimalValue(double val)
{
   int i = 0, count = 1, decval = 0;
   int slen = 0, leftofdec = 0;
   string str = DoubleToString(val);
   slen = StringLen(str);
   leftofdec = StringFind(str, ".") + 1;
   for(i = slen - 1; i >= 1; i--)
   {
      if(StringSubstrOld(str, i - 1, 1) == "0") count++;
      else break;
   }
   decval = slen - count - leftofdec;
   if(decval < 1) decval = 1;
   return decval;
}

void initTimeFrames()
{
   if(!autoTimeFrame)
   {
      userTimeFrame       = StrToTF(timeFrame);
      userExtraTimeFrame  = StrToTF(extraTimeFrame);
      userExtraTimeFrame2 = StrToTF(extraTimeFrame2);
   }
   else
   {
      userTimeFrame = Period();
      if(userTimeFrame == PERIOD_M1)  userExtraTimeFrame = PERIOD_M5;
      else if(userTimeFrame == PERIOD_M5)  userExtraTimeFrame = PERIOD_M15;
      else if(userTimeFrame == PERIOD_M15) userExtraTimeFrame = PERIOD_M30;
      else if(userTimeFrame == PERIOD_M30) userExtraTimeFrame = PERIOD_H1;
      else if(userTimeFrame == PERIOD_H1)  userExtraTimeFrame = PERIOD_H4;
      else if(userTimeFrame == PERIOD_H4)  userExtraTimeFrame = PERIOD_D1;
      else if(userTimeFrame == PERIOD_D1)  userExtraTimeFrame = PERIOD_W1;
      else if(userTimeFrame == PERIOD_W1)  userExtraTimeFrame = PERIOD_MN1;
      else                                  userExtraTimeFrame = PERIOD_MN1;

      if(userTimeFrame == PERIOD_M1)  userExtraTimeFrame2 = PERIOD_M1;
      else if(userTimeFrame == PERIOD_M5)  userExtraTimeFrame2 = PERIOD_M1;
      else if(userTimeFrame == PERIOD_M15) userExtraTimeFrame2 = PERIOD_M5;
      else if(userTimeFrame == PERIOD_M30) userExtraTimeFrame2 = PERIOD_M15;
      else if(userTimeFrame == PERIOD_H1)  userExtraTimeFrame2 = PERIOD_M30;
      else if(userTimeFrame == PERIOD_H4)  userExtraTimeFrame2 = PERIOD_H1;
      else if(userTimeFrame == PERIOD_D1)  userExtraTimeFrame2 = PERIOD_H4;
      else if(userTimeFrame == PERIOD_W1)  userExtraTimeFrame2 = PERIOD_D1;
      else                                  userExtraTimeFrame2 = PERIOD_W1;
   }
}

double GetSlope(int hMA, int hATR, ENUM_TIMEFRAMES tf, int pShift)
{
   int shiftWithoutSunday = pShift;
   if(_BrokerHasSundayCandles && Period() == PERIOD_D1)
      if(MyTimeDayOfWeek(iTime(_Symbol, PERIOD_D1, pShift)) == 0)
         shiftWithoutSunday++;

   double atrArr[];
   ArraySetAsSeries(atrArr, true);
   if(CopyBuffer(hATR, 0, shiftWithoutSunday + 10, 1, atrArr) <= 0) return 0.0;
   double atr = atrArr[0] / 10.0;
   if(atr == 0) return 0.0;

   double maArr[];
   ArraySetAsSeries(maArr, true);
   if(CopyBuffer(hMA, 0, shiftWithoutSunday, 2, maArr) < 2) return 0.0;

   double dblTma   = maArr[0];
   double dblPrev1 = maArr[1];
   double closeVal = iClose(_Symbol, tf, shiftWithoutSunday);
   double dblPrev  = (dblPrev1 * 231.0 + closeVal * 20.0) / 251.0;
   return (dblTma - dblPrev) / atr;
}

void fireAlerts(string sMsg)
{
   if(PopupAlert)  Alert(sMsg);
   if(EmailAlert)  SendMail("CSS Alert ", sMsg);
   if(PushAlert)   SendNotification(sMsg);
}

void ArrowCreate(const string pName, datetime pTime, double pPrice,
                 const string pText, const color pClr,
                 const ENUM_ANCHOR_POINT pAnchor, const string pFont, int pFontSize)
{
   if(ObjectFind(0, pName) < 0)
      if(!ObjectCreate(0, pName, OBJ_TEXT, 0, pTime, pPrice))
         { Print(__FUNCTION__, ": failed! Error=", GetLastError()); return; }
   ObjectSetString(0, pName, OBJPROP_TEXT, pText);
   ObjectSetString(0, pName, OBJPROP_FONT, pFont);
   ObjectSetInteger(0, pName, OBJPROP_FONTSIZE, pFontSize);
   ObjectSetInteger(0, pName, OBJPROP_ANCHOR, pAnchor);
   ObjectSetInteger(0, pName, OBJPROP_COLOR, pClr);
   ObjectSetInteger(0, pName, OBJPROP_BACK, false);
   ObjectSetInteger(0, pName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, pName, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, pName, OBJPROP_HIDDEN, true);
}

void TextCreate(const string pName, datetime pTime, double pPrice,
                const string pText, const color pClr,
                const ENUM_ANCHOR_POINT pAnchor, const string pFont, int pFontSize)
{
   if(ObjectFind(0, pName) < 0)
      if(!ObjectCreate(0, pName, OBJ_TEXT, 0, pTime, pPrice))
         { Print(__FUNCTION__, ": failed! Error=", GetLastError()); return; }
   ObjectSetString(0, pName, OBJPROP_TEXT, pText);
   ObjectSetString(0, pName, OBJPROP_FONT, pFont);
   ObjectSetInteger(0, pName, OBJPROP_FONTSIZE, pFontSize);
   ObjectSetInteger(0, pName, OBJPROP_ANCHOR, pAnchor);
   ObjectSetInteger(0, pName, OBJPROP_COLOR, pClr);
   ObjectSetInteger(0, pName, OBJPROP_BACK, true);
   ObjectSetInteger(0, pName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, pName, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, pName, OBJPROP_HIDDEN, true);
}

void ShowCurrencyTable(ENUM_TIMEFRAMES tf, int column, int rightBar2)
{
   string showText = "";
   int diffdigits = GetDecimalValue(differenceThreshold);
   bool OkToSendAlerts = (!IsInit && column == 1 && rightBar2 == 0 && IsItNewBar);

   if(showSlopeValues)
   {
      if(column == 1)
      {
         objectName = almostUniqueIndex + "_css_obj_column1_tf" + ObjSuff;
         if(ObjectFind(0, objectName) < 0)
            if(ObjectCreate(0, objectName, OBJ_LABEL, windex, 0, 0))
            {
               ObjectSetInteger(0, objectName, OBJPROP_CORNER, 1);
               ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE, horizontalOffset + 10 + horizontalShift * 6);
               ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, verticalOffset);
               ObjectSetInteger(0, objectName, OBJPROP_HIDDEN, true);
            }
         ObjectSetString(0, objectName, OBJPROP_TEXT, TFToString(userTimeFrame));
         ObjectSetString(0, objectName, OBJPROP_FONT, nonPropFont);
         ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, displayTextSize);
         ObjectSetInteger(0, objectName, OBJPROP_COLOR, colorTimeframe);

         objectName = almostUniqueIndex + "_css_obj_column1_value1" + ObjSuff;
         if(ObjectFind(0, objectName) < 0)
            if(ObjectCreate(0, objectName, OBJ_LABEL, windex, 0, 0))
            {
               ObjectSetInteger(0, objectName, OBJPROP_CORNER, 1);
               ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE, horizontalOffset + horizontalShift * 6);
               ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, (int)(verticalOffset + verticalShift * 1.5));
               ObjectSetInteger(0, objectName, OBJPROP_HIDDEN, true);
            }
         showText = DoubleToString(Slope1[rightBar2], 2);
         ObjectSetString(0, objectName, OBJPROP_TEXT, showText);
         ObjectSetString(0, objectName, OBJPROP_FONT, nonPropFont);
         ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, displayTextSize);
         ObjectSetInteger(0, objectName, OBJPROP_COLOR, currencyColors[cindex]);
      }
      if(column == 2)
      {
         objectName = almostUniqueIndex + "_css_obj_column2_tf" + ObjSuff;
         if(ObjectFind(0, objectName) < 0)
            if(ObjectCreate(0, objectName, OBJ_LABEL, windex, 0, 0))
            {
               ObjectSetInteger(0, objectName, OBJPROP_CORNER, 1);
               ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE, horizontalOffset + 10 + horizontalShift * 3);
               ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, verticalOffset);
               ObjectSetInteger(0, objectName, OBJPROP_HIDDEN, true);
            }
         ObjectSetString(0, objectName, OBJPROP_TEXT, TFToString(userExtraTimeFrame));
         ObjectSetString(0, objectName, OBJPROP_FONT, nonPropFont);
         ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, displayTextSize);
         ObjectSetInteger(0, objectName, OBJPROP_COLOR, colorTimeframe);

         objectName = almostUniqueIndex + "_css_obj_column2_value1" + ObjSuff;
         if(ObjectFind(0, objectName) < 0)
            if(ObjectCreate(0, objectName, OBJ_LABEL, windex, 0, 0))
            {
               ObjectSetInteger(0, objectName, OBJPROP_CORNER, 1);
               ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE, horizontalOffset + horizontalShift * 3);
               ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, (int)(verticalOffset + verticalShift * 1.5));
               ObjectSetInteger(0, objectName, OBJPROP_HIDDEN, true);
            }
         showText = DoubleToString(Slope_2, 2);
         ObjectSetString(0, objectName, OBJPROP_TEXT, showText);
         ObjectSetString(0, objectName, OBJPROP_FONT, nonPropFont);
         ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, displayTextSize);
         ObjectSetInteger(0, objectName, OBJPROP_COLOR, currencyColors[cindex]);
      }
      if(column == 3)
      {
         objectName = almostUniqueIndex + "_css_obj_column3_tf" + ObjSuff;
         if(ObjectFind(0, objectName) < 0)
            if(ObjectCreate(0, objectName, OBJ_LABEL, windex, 0, 0))
            {
               ObjectSetInteger(0, objectName, OBJPROP_CORNER, 1);
               ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE, horizontalOffset + 10);
               ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, verticalOffset);
               ObjectSetInteger(0, objectName, OBJPROP_HIDDEN, true);
            }
         ObjectSetString(0, objectName, OBJPROP_TEXT, TFToString(userExtraTimeFrame2));
         ObjectSetString(0, objectName, OBJPROP_FONT, nonPropFont);
         ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, displayTextSize);
         ObjectSetInteger(0, objectName, OBJPROP_COLOR, colorTimeframe);

         objectName = almostUniqueIndex + "_css_obj_column3_value1" + ObjSuff;
         if(ObjectFind(0, objectName) < 0)
            if(ObjectCreate(0, objectName, OBJ_LABEL, windex, 0, 0))
            {
               ObjectSetInteger(0, objectName, OBJPROP_CORNER, 1);
               ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE, horizontalOffset);
               ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, (int)(verticalOffset + verticalShift * 1.5));
               ObjectSetInteger(0, objectName, OBJPROP_HIDDEN, true);
            }
         showText = DoubleToString(Slope_3, 2);
         ObjectSetString(0, objectName, OBJPROP_TEXT, showText);
         ObjectSetString(0, objectName, OBJPROP_FONT, nonPropFont);
         ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, displayTextSize);
         ObjectSetInteger(0, objectName, OBJPROP_COLOR, currencyColors[cindex]);
      }
   }

   if(showDifferenceThreshold && column == 4)
   {
      objectName = almostUniqueIndex + "_css_obj_diff" + ObjSuff;
      if(ObjectFind(0, objectName) < 0)
         if(ObjectCreate(0, objectName, OBJ_LABEL, windex, 0, 0))
         {
            ObjectSetInteger(0, objectName, OBJPROP_CORNER, 1);
            ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE, (int)(horizontalOffset + horizontalShift * 0.25));
            ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, (int)(verticalOffset + verticalShift * 3.75));
            ObjectSetInteger(0, objectName, OBJPROP_HIDDEN, true);
         }
      showText = StringSubstr(_Symbol, 0, 6) + " thresh = " + DoubleToString(differenceThreshold, diffdigits);
      ObjectSetString(0, objectName, OBJPROP_TEXT, showText);
      ObjectSetString(0, objectName, OBJPROP_FONT, nonPropFont);
      ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, objectName, OBJPROP_COLOR, differenceThresholdColor);
   }

   if(OkToSendAlerts)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int ai = 0;
      if(sendCrossAlerts)
      {
         if(Slope1[ai+1] < differenceThreshold*0.5 && Slope1[ai] > differenceThreshold*0.5)
            fireAlerts(_Symbol+" cross up  "+TFToString(tf)+" @"+DoubleToString(bid,_Digits)+"__"+TimeToString(TimeCurrent(),TIME_MINUTES));
         if(Slope1[ai+1] > -differenceThreshold*0.5 && Slope1[ai] < -differenceThreshold*0.5)
            fireAlerts(_Symbol+" cross down  "+TFToString(tf)+" @"+DoubleToString(bid,_Digits)+"__"+TimeToString(TimeCurrent(),TIME_MINUTES));
      }
      if(sendLevelCrossAlerts)
      {
         if(Slope1[ai+1] < levelCrossValue && Slope1[ai] > levelCrossValue)
            fireAlerts(_Symbol+" cross up "+DoubleToString(levelCrossValue,2)+"  "+TFToString(tf)+" @"+DoubleToString(bid,_Digits)+"__"+TimeToString(TimeCurrent(),TIME_MINUTES));
         if(Slope1[ai+1] > -levelCrossValue && Slope1[ai] < -levelCrossValue)
            fireAlerts(_Symbol+" cross down "+DoubleToString(-levelCrossValue,2)+"  "+TFToString(tf)+" @"+DoubleToString(bid,_Digits)+"__"+TimeToString(TimeCurrent(),TIME_MINUTES));
      }
      if(sendExitCrossAlerts)
      {
         if(Slope1[ai+1] > levelCrossValue && Slope1[ai] < levelCrossValue)
            fireAlerts(_Symbol+" 'exit buy' cross down "+DoubleToString(levelCrossValue,2)+"  "+TFToString(tf)+" @"+DoubleToString(bid,_Digits)+"__"+TimeToString(TimeCurrent(),TIME_MINUTES));
         if(Slope1[ai+1] < -levelCrossValue && Slope1[ai] > -levelCrossValue)
            fireAlerts(_Symbol+" 'exit sell' cross up "+DoubleToString(-levelCrossValue,2)+"  "+TFToString(tf)+" @"+DoubleToString(bid,_Digits)+"__"+TimeToString(TimeCurrent(),TIME_MINUTES));
      }
      if(sendMTFAgreeAlerts)
      {
         if(Slope_2>differenceThreshold*0.5 && Slope_3>differenceThreshold*0.5 && Slope1[ai+1]<differenceThreshold*0.5 && Slope1[ai]>differenceThreshold*0.5)
            fireAlerts(_Symbol+" MTF agree cross up  "+TFToString(tf)+" @"+DoubleToString(bid,_Digits)+"__"+TimeToString(TimeCurrent(),TIME_MINUTES));
         if(Slope_2<-differenceThreshold*0.5 && Slope_3<-differenceThreshold*0.5 && Slope1[ai+1]>-differenceThreshold*0.5 && Slope1[ai]<-differenceThreshold*0.5)
            fireAlerts(_Symbol+" MTF agree cross down  "+TFToString(tf)+" @"+DoubleToString(bid,_Digits)+"__"+TimeToString(TimeCurrent(),TIME_MINUTES));
      }
   }
}

bool IsNewReadTime()
{
   bool NewReadTime = false;
   bool IsReadEveryNewBar = false;
   if(userEveryTickMode) { NewReadTime = true; }
   else
   {
      if(userReadEveryNewBar)
      {
         if(lastBarTime < iTime(_Symbol, Period(), 0))
         { lastBarTime = iTime(_Symbol, Period(), 0) + 1; IsReadEveryNewBar = true; }
      }
      else IsReadEveryNewBar = true;
      if(nextReadTime <= TimeCurrent() || IsReadEveryNewBar)
      { nextReadTime = TimeCurrent() + userReadEveryXSeconds; NewReadTime = true; }
   }
   return NewReadTime;
}

bool IsNewBar()
{
   bool newBar = false;
   if(lastBarTime2 < iTime(_Symbol, Period(), 0))
   { lastBarTime2 = iTime(_Symbol, Period(), 0) + 1; newBar = true; }
   return newBar;
}

//+------------------------------------------------------------------+
int OnInit()
{
   IsInit = true;
   initTimeFrames();

   hMA_userTF   = iMA(_Symbol, userTimeFrame,      SlopeMAPeriod, 0, MODE_LWMA, PRICE_CLOSE);
   hATR_userTF  = iATR(_Symbol, userTimeFrame,      SlopeATRPeriod);
   hMA_extraTF  = iMA(_Symbol, userExtraTimeFrame,  SlopeMAPeriod, 0, MODE_LWMA, PRICE_CLOSE);
   hATR_extraTF = iATR(_Symbol, userExtraTimeFrame,  SlopeATRPeriod);
   hMA_extraTF2 = iMA(_Symbol, userExtraTimeFrame2, SlopeMAPeriod, 0, MODE_LWMA, PRICE_CLOSE);
   hATR_extraTF2= iATR(_Symbol, userExtraTimeFrame2, SlopeATRPeriod);
   hATR_arrows  = iATR(_Symbol, Period(), ATRPeriodArrows);

   if(hMA_userTF==INVALID_HANDLE || hATR_userTF==INVALID_HANDLE ||
      hMA_extraTF==INVALID_HANDLE || hATR_extraTF==INVALID_HANDLE ||
      hMA_extraTF2==INVALID_HANDLE || hATR_extraTF2==INVALID_HANDLE ||
      hATR_arrows==INVALID_HANDLE)
   { Print("Error creating indicator handles!"); return(INIT_FAILED); }

   string now = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS);
   string nowClean = now;
   StringReplace(nowClean, ":", ""); StringReplace(nowClean, ".", ""); StringReplace(nowClean, " ", "");
   almostUniqueIndex = (StringLen(nowClean)>3 ? StringSubstr(nowClean,StringLen(nowClean)-3) : nowClean) + IntegerToString(ChartID()%10000);
   shortName = indicatorName + " - " + version + " - id" + almostUniqueIndex;
   IndicatorSetString(INDICATOR_SHORTNAME, shortName);

   windex = ChartWindowFind(0, shortName);
   if(windex < 0) windex = 0;
   ObjSuff  = "_" + almostUniqueIndex + "_BSS";
   ObjSuff2 = "_" + almostUniqueIndex + "_objdel";

   currencyColors[0]=Color_USD; cline_width[0]=line_width_USD; cline_style[0]=line_style_USD;
   currencyColors[1]=Color_EUR; cline_width[1]=line_width_EUR; cline_style[1]=line_style_EUR;
   currencyColors[2]=Color_GBP; cline_width[2]=line_width_GBP; cline_style[2]=line_style_GBP;
   currencyColors[3]=Color_JPY; cline_width[3]=line_width_JPY; cline_style[3]=line_style_JPY;
   currencyColors[4]=Color_AUD; cline_width[4]=line_width_AUD; cline_style[4]=line_style_AUD;
   currencyColors[5]=Color_CAD; cline_width[5]=line_width_CAD; cline_style[5]=line_style_CAD;
   currencyColors[6]=Color_NZD; cline_width[6]=line_width_NZD; cline_style[6]=line_style_NZD;
   currencyColors[7]=Color_CHF; cline_width[7]=line_width_CHF; cline_style[7]=line_style_CHF;
   currencyColors[8]=Color_default; cline_width[8]=line_width_USD; cline_style[8]=line_style_USD;

   if(CSS_Available(StringSubstr(_Symbol,0,3)) && CSS_Available(StringSubstr(_Symbol,3,3)))
   { cindex = getCurrencyIndex(StringSubstr(_Symbol,0,3)); cindex2 = getCurrencyIndex(StringSubstr(_Symbol,3,3)); }
   else { cindex = 8; cindex2 = 8; }

   SetIndexBuffer(0, Slope1,     INDICATOR_DATA);
   SetIndexBuffer(1, Slope2,     INDICATOR_DATA);
   SetIndexBuffer(2, BuySignal,  INDICATOR_DATA);
   SetIndexBuffer(3, SellSignal, INDICATOR_DATA);
   SetIndexBuffer(4, BuyExitSig, INDICATOR_DATA);
   SetIndexBuffer(5, SellExitSig,INDICATOR_DATA);
   SetIndexBuffer(6, BuyRegime,  INDICATOR_DATA);
   SetIndexBuffer(7, SellRegime, INDICATOR_DATA);

   PlotIndexSetString(0, PLOT_LABEL, currencyNames[cindex]);
   PlotIndexSetString(1, PLOT_LABEL, currencyNames[cindex2]);
   PlotIndexSetString(2, PLOT_LABEL, "BuySignal");
   PlotIndexSetString(3, PLOT_LABEL, "SellSignal");
   PlotIndexSetString(4, PLOT_LABEL, "BuyExit");
   PlotIndexSetString(5, PLOT_LABEL, "SellExit");
   PlotIndexSetString(6, PLOT_LABEL, "BuyRegime");
   PlotIndexSetString(7, PLOT_LABEL, "SellRegime");

   if(showCurrencyLines)
   {
      PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_LINE);
      PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_LINE);
      PlotIndexSetInteger(0, PLOT_LINE_STYLE, cline_style[cindex]);
      PlotIndexSetInteger(0, PLOT_LINE_WIDTH, cline_width[cindex]);
      PlotIndexSetInteger(0, PLOT_LINE_COLOR, currencyColors[cindex]);
      PlotIndexSetInteger(1, PLOT_LINE_STYLE, cline_style[cindex2]);
      PlotIndexSetInteger(1, PLOT_LINE_WIDTH, cline_width[cindex2]);
      PlotIndexSetInteger(1, PLOT_LINE_COLOR, currencyColors[cindex2]);
   }
   else
   {
      PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE);
   }
   for(int b=2; b<8; b++)
      PlotIndexSetInteger(b, PLOT_DRAW_TYPE, DRAW_NONE);

   _BrokerHasSundayCandles = false;
   for(int i=0; i<8; i++)
      if(MyTimeDayOfWeek(iTime(_Symbol, PERIOD_D1, i)) == 0)
      { _BrokerHasSundayCandles = true; break; }

   userNoOfTimeFrames = NoOfTimeFrames;
   userEveryTickMode  = EveryTickMode;
   userReadEveryNewBar = ReadEveryNewBar;
   userReadEveryXSeconds = ReadEveryXSeconds;
   if(userNoOfTimeFrames>3) userNoOfTimeFrames=3;
   if(userNoOfTimeFrames<1) userNoOfTimeFrames=1;

   if(!showArrowsOnChart) DeleteArrowObjects();

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(hMA_userTF   !=INVALID_HANDLE) IndicatorRelease(hMA_userTF);
   if(hATR_userTF  !=INVALID_HANDLE) IndicatorRelease(hATR_userTF);
   if(hMA_extraTF  !=INVALID_HANDLE) IndicatorRelease(hMA_extraTF);
   if(hATR_extraTF !=INVALID_HANDLE) IndicatorRelease(hATR_extraTF);
   if(hMA_extraTF2 !=INVALID_HANDLE) IndicatorRelease(hMA_extraTF2);
   if(hATR_extraTF2!=INVALID_HANDLE) IndicatorRelease(hATR_extraTF2);
   if(hATR_arrows  !=INVALID_HANDLE) IndicatorRelease(hATR_arrows);
   for(int i=ObjectsTotal(0)-1; i>=0; i--)
   { string nm=ObjectName(0,i); if(StringFind(nm,ObjSuff,0)>0) ObjectDelete(0,nm); }
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
   if(rates_total < 51) return(0);

   ArraySetAsSeries(time,       true);
   ArraySetAsSeries(high,       true);
   ArraySetAsSeries(low,        true);
   ArraySetAsSeries(close,      true);
   ArraySetAsSeries(Slope1,     true);
   ArraySetAsSeries(Slope2,     true);
   ArraySetAsSeries(BuySignal,  true);
   ArraySetAsSeries(SellSignal, true);
   ArraySetAsSeries(BuyExitSig, true);
   ArraySetAsSeries(SellExitSig,true);
   ArraySetAsSeries(BuyRegime,  true);
   ArraySetAsSeries(SellRegime, true);

   if(windex<=0) { windex=ChartWindowFind(0,shortName); if(windex<0) windex=0; }
   if(!showArrowsOnChart) DeleteArrowObjects();

   if(IsNewReadTime())
   {
      IsItNewBar = IsNewBar();
      int leftBar=0, rightBar=0;

       if(maxBars>0)
       {
          leftBar = MathMin(maxBars, rates_total-10);
          rightBar = 0;
          if(maxBars>300) { userEveryTickMode=false; userReadEveryNewBar=false; userReadEveryXSeconds=86400; }
       }
       else
       {
          leftBar  = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
          rightBar = leftBar - (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
          if(leftBar < 0) leftBar = rates_total-1;
          if(leftBar > rates_total-1) leftBar = rates_total-1;
          if(rightBar<0) rightBar=0;
          if(rightBar > leftBar) rightBar=leftBar;
       }

       //--- Calculate every loaded bar.  The visible range is only for
       //--- chart objects; using it as the calculation range leaves gaps
       //--- when the chart is subsequently scrolled into older history.
       int calculationLeft = (maxBars>0 ? leftBar : rates_total-1);
       if(calculationLeft > rates_total-1) calculationLeft = rates_total-1;
       if(calculationLeft < 0) calculationLeft = 0;

      //--- Pre-copy indicator buffers (bulk copy for CPU efficiency)
       int maxShiftTF = (int)((double)calculationLeft * PeriodSeconds() / PeriodSeconds(userTimeFrame)) + 20;
      int barsOnTF = Bars(_Symbol, userTimeFrame);
      if(maxShiftTF>barsOnTF) maxShiftTF=barsOnTF;
      if(maxShiftTF<20) maxShiftTF=20;

      double maBuf[], atrBuf[];
      ArraySetAsSeries(maBuf,  true);
      ArraySetAsSeries(atrBuf, true);
      int maCopied  = CopyBuffer(hMA_userTF,  0, 0, maxShiftTF, maBuf);
      int atrCopied = CopyBuffer(hATR_userTF, 0, 0, maxShiftTF, atrBuf);

       double atrArrowsBuf[];
       ArraySetAsSeries(atrArrowsBuf, true);
       CopyBuffer(hATR_arrows, 0, 0, leftBar+1, atrArrowsBuf);

       //--- This branch can be entered after a history refresh, so discard
       //--- values from the previous calculation before rebuilding the range.
       ArrayInitialize(Slope1,     EMPTY_VALUE);
       ArrayInitialize(Slope2,     EMPTY_VALUE);
       ArrayInitialize(BuySignal,  0.0);
       ArrayInitialize(SellSignal, 0.0);
       ArrayInitialize(BuyExitSig, 0.0);
       ArrayInitialize(SellExitSig,0.0);
       ArrayInitialize(BuyRegime,  0.0);
       ArrayInitialize(SellRegime, 0.0);

       //--- Arrow state tracking for BuySignal/SellSignal buffers
      bool stateBuyActive  = false;
      bool stateSellActive = false;
      // Pre-seed state from bar before leftBar
      if(leftBar+1 < rates_total && Slope1[leftBar+1]!=EMPTY_VALUE)
      {
         if(Slope1[leftBar+1] > differenceThreshold*0.5)       stateBuyActive  = true;
         else if(Slope1[leftBar+1] < -differenceThreshold*0.5) stateSellActive = true;
      }

       //--- Main loop: walk from the oldest bar toward the current bar so
       //--- state-transition signals are reconstructed in chronological order.
       for(int i=calculationLeft; i>=0; i--)
       {
          //--- ====== SLOPE + SIGNALS for every bar ======
         int bar = MyBarShift(_Symbol, userTimeFrame, time[i]);
         int shiftWithoutSunday = bar;
         if(_BrokerHasSundayCandles && Period()==PERIOD_D1)
            if(MyTimeDayOfWeek(iTime(_Symbol, PERIOD_D1, bar))==0)
               shiftWithoutSunday++;

         int sws = shiftWithoutSunday;
         bool slopeOK = false;

         if(maCopied>0 && atrCopied>0 &&
            sws+10 < ArraySize(atrBuf) && sws+1 < ArraySize(maBuf))
         {
            double atrVal = atrBuf[sws+10] / 10.0;
            if(atrVal!=0)
            {
               double dblTma   = maBuf[sws];
               double dblPrev1 = maBuf[sws+1];
               double closeVal = iClose(_Symbol, userTimeFrame, sws);
               double dblPrev  = (dblPrev1*231.0 + closeVal*20.0) / 251.0;
               Slope1[i] = (dblTma - dblPrev) / atrVal;
               Slope2[i] = -Slope1[i];
               slopeOK = true;
            }
         }

         //--- Trade direction
         TradeLong = false; TradeShort = false;
         if(slopeOK)
         {
            if(Slope1[i] > differenceThreshold*0.5)  TradeLong  = true;
            if(Slope1[i] < -differenceThreshold*0.5) TradeShort = true;
         }

         //--- Entry signals (state-transition arrows)
         bool isBuyArrow  = false;
         bool isSellArrow = false;
         if(TradeLong  && !stateBuyActive)  isBuyArrow  = true;
         if(TradeShort && !stateSellActive) isSellArrow = true;
         if(TradeLong)       { stateBuyActive=true;  stateSellActive=false; }
         else if(TradeShort) { stateBuyActive=false; stateSellActive=true;  }
         else                { stateBuyActive=false; stateSellActive=false; }

         BuySignal[i]  = isBuyArrow  ? 1.0 : 0.0;
         SellSignal[i] = isSellArrow ? 1.0 : 0.0;

         //--- Exit signals (level cross)
         BuyExitSig[i]  = 0.0;
         SellExitSig[i] = 0.0;
         if(slopeOK && i+1 < rates_total && Slope1[i+1]!=EMPTY_VALUE)
         {
            // Buy exit: slope crosses DOWN through +levelCrossValue
            if(Slope1[i+1] >= levelCrossValue  && Slope1[i] < levelCrossValue)  BuyExitSig[i]  = 1.0;
            // Sell exit: slope crosses UP through -levelCrossValue
            if(Slope1[i+1] <= -levelCrossValue && Slope1[i] > -levelCrossValue) SellExitSig[i] = 1.0;
         }

         //--- Regime signals (continuous state)
         BuyRegime[i]  = TradeLong  ? 1.0 : 0.0;
         SellRegime[i] = TradeShort ? 1.0 : 0.0;

          //--- ====== VISUAL ELEMENTS (visible bars only) ======
          if(i >= rightBar && i < leftBar)
         {
            double ATR=0, ArrowHigh=0, ArrowLow=0;
            if(i < ArraySize(atrArrowsBuf)) ATR = atrArrowsBuf[i];
            ArrowHigh = high[i] + ATR*ATRMultiplierArrows;
            ArrowLow  = low[i]  - ATR*ATRMultiplierArrows;

            //--- Tables at rightBar
            if(i==rightBar)
            {
               if(userNoOfTimeFrames>1 || (sendMTFAgreeAlerts && rightBar==0))
                  Slope_2 = GetSlope(hMA_extraTF, hATR_extraTF, userExtraTimeFrame, rightBar);
               if(userNoOfTimeFrames>2 || (sendMTFAgreeAlerts && rightBar==0))
                  Slope_3 = GetSlope(hMA_extraTF2, hATR_extraTF2, userExtraTimeFrame2, rightBar);

               if(userNoOfTimeFrames==1)
               { ShowCurrencyTable(userTimeFrame,1,rightBar); ShowCurrencyTable(userTimeFrame,4,rightBar); }
               else if(userNoOfTimeFrames==2)
               { ShowCurrencyTable(userTimeFrame,1,rightBar); ShowCurrencyTable(userExtraTimeFrame,2,rightBar); ShowCurrencyTable(userTimeFrame,4,rightBar); }
               else if(userNoOfTimeFrames==3)
               { ShowCurrencyTable(userTimeFrame,1,rightBar); ShowCurrencyTable(userExtraTimeFrame,2,rightBar); ShowCurrencyTable(userExtraTimeFrame2,3,rightBar); ShowCurrencyTable(userTimeFrame,4,rightBar); }
            }

            //--- Delete stale arrow objects when visible range changes (NO buffer clearing!)
            if(!IsInit && i==leftBar-1)
            {
               if(leftBar!=leftBarPrev || leftBar-rightBar!=leftBarPrev-rightBarPrev)
               {
                  for(int j=ObjectsTotal(0)-1; j>=0; j--)
                  { string nm=ObjectName(0,j); if(StringFind(nm,ObjSuff2,0)>0) ObjectDelete(0,nm); }
               }
            }

            //--- Background VLINE
            if(showBackgroundColor)
            {
               objectName = almostUniqueIndex+"_diff_"+TimeToString(time[i])+ObjSuff+ObjSuff2;
               if(ObjectFind(0,objectName)<0)
                  if(ObjectCreate(0,objectName,OBJ_VLINE,windex,time[i],0))
                  { ObjectSetInteger(0,objectName,OBJPROP_BACK,true); ObjectSetInteger(0,objectName,OBJPROP_HIDDEN,true); ObjectSetInteger(0,objectName,OBJPROP_WIDTH,backgroundLineWidth); }
               if(MathAbs(Slope1[i])>differenceThreshold*0.5)
               {
                  if(TradeLong)  ObjectSetInteger(0,objectName,OBJPROP_COLOR,colorDifferenceUp);
                  if(TradeShort) ObjectSetInteger(0,objectName,OBJPROP_COLOR,colorDifferenceDn);
               }
               else ObjectSetInteger(0,objectName,OBJPROP_COLOR,colorDifferenceLo);
            }

            //--- Arrows on price chart
            if(showArrowsOnChart)
            {
               bool OkToDrawArrows = false;
               if(OnlyDrawArrowsOnNewBar) { if(IsItNewBar) OkToDrawArrows=true; }
               else OkToDrawArrows=true;

               if(OkToDrawArrows)
               {
                  if(TradeLong && !BuyArrowActive)
                  {
                     objectName = "Buy Arrow "+IntegerToString((int)time[i])+ObjSuff+ObjSuff2;
                     ArrowCreate(objectName, time[i], ArrowLow, CharToString(BuyArrowStyle), BuyArrowColor, ANCHOR_LOWER, "Wingdings", BuyArrowFontSize);
                     if(showSignalLine && i==0)
                     {
                        objectName = "Buy Signal Line "+IntegerToString((int)time[i])+ObjSuff;
                        if(ObjectFind(0,objectName)<0)
                           if(ObjectCreate(0,objectName,OBJ_TREND,0,time[i+1],close[0],time[i]+PeriodSeconds(),close[0]))
                           { ObjectSetInteger(0,objectName,OBJPROP_BACK,true); ObjectSetInteger(0,objectName,OBJPROP_WIDTH,SignalLineSize); ObjectSetInteger(0,objectName,OBJPROP_COLOR,SignalLineBuyColor); ObjectSetInteger(0,objectName,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,objectName,OBJPROP_HIDDEN,true); }
                     }
                     BuyArrowActive=true; SellArrowActive=false;
                  }
                  if(TradeShort && !SellArrowActive)
                  {
                     objectName = "Sell Arrow "+IntegerToString((int)time[i])+ObjSuff+ObjSuff2;
                     ArrowCreate(objectName, time[i], ArrowHigh, CharToString(SellArrowStyle), SellArrowColor, ANCHOR_UPPER, "Wingdings", SellArrowFontSize);
                     if(showSignalLine && i==0)
                     {
                        objectName = "Sell Signal Line "+IntegerToString((int)time[i])+ObjSuff;
                        if(ObjectFind(0,objectName)<0)
                           if(ObjectCreate(0,objectName,OBJ_TREND,0,time[i+1],close[0],time[i]+PeriodSeconds(),close[0]))
                           { ObjectSetInteger(0,objectName,OBJPROP_BACK,true); ObjectSetInteger(0,objectName,OBJPROP_WIDTH,SignalLineSize); ObjectSetInteger(0,objectName,OBJPROP_COLOR,SignalLineSellColor); ObjectSetInteger(0,objectName,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,objectName,OBJPROP_HIDDEN,true); }
                     }
                     BuyArrowActive=false; SellArrowActive=true;
                  }
                  if(!TradeLong && !TradeShort)
                  { BuyArrowActive=false; SellArrowActive=false; }
               }
            }

         }// if(i < leftBar) — visual elements only

      }// for(i)

      //--- Level cross lines
      if(showLevelCrossLines)
      {
         objectName = almostUniqueIndex+"_high"+ObjSuff;
         ObjectDelete(0,objectName);
         if(ObjectCreate(0,objectName,OBJ_TREND,windex,time[leftBar],levelCrossValue,time[rightBar],levelCrossValue))
         { ObjectSetInteger(0,objectName,OBJPROP_BACK,true); ObjectSetInteger(0,objectName,OBJPROP_WIDTH,levelCrossLineSize); ObjectSetInteger(0,objectName,OBJPROP_COLOR,colorLevelHigh); ObjectSetInteger(0,objectName,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,objectName,OBJPROP_HIDDEN,true); }

         objectName = almostUniqueIndex+"_low"+ObjSuff;
         ObjectDelete(0,objectName);
         if(ObjectCreate(0,objectName,OBJ_TREND,windex,time[leftBar],-levelCrossValue,time[rightBar],-levelCrossValue))
         { ObjectSetInteger(0,objectName,OBJPROP_BACK,true); ObjectSetInteger(0,objectName,OBJPROP_WIDTH,levelCrossLineSize); ObjectSetInteger(0,objectName,OBJPROP_COLOR,colorLevelLow); ObjectSetInteger(0,objectName,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,objectName,OBJPROP_HIDDEN,true); }
      }

   }// if(IsNewReadTime())

   IsInit = false;
   leftBarPrev  = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   rightBarPrev = leftBarPrev - (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
   if(rightBarPrev<0) rightBarPrev=0;

   return(rates_total);
}
//+------------------------------------------------------------------+
