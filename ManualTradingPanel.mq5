//+------------------------------------------------------------------+
//|                                           ManualTradePanelEA.mq5  |
//|   Manual trading panel EA (does NOT auto-trade).                  |
//|   - BUY / SELL / CLOSE buttons on the chart (always top-most).    |
//|   - Works in the Strategy Tester Visual Mode.                     |
//|   - Adjustable dashboard: winrate, profit factor, R:R, max DD.   |
//|   - Stochastic indicator attached.                               |
//+------------------------------------------------------------------+
#property copyright "ManualTradePanelEA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//============================ INPUTS ================================//
input string  h1              = "===== Trade Settings =====";
input long    InpMagic        = 20260731;   // Magic number
input double  InpLot          = 0.10;       // Lot size
input int     InpStopLossPts  = 600;        // Stop Loss (points, 0 = none)
input int     InpTakeProfitPts= 100;        // Take Profit (points, 0 = none)
input int     InpSlippage     = 20;         // Max deviation (points)

input string  h2              = "===== Stochastic =====";
input int            InpKPeriod    = 21;              // %K period
input int            InpDPeriod    = 1;              // %D period
input int            InpSlowing    = 3;              // Slowing
input ENUM_MA_METHOD InpStochMA    = MODE_SMA;       // MA method
input ENUM_STO_PRICE InpStochPrice = STO_LOWHIGH;    // Price field
input bool           InpShowStoch  = true;           // Attach Stochastic to chart

input string  h3              = "===== Buttons =====";
input int     InpBtnWidth     = 120;        // Button width (px)
input int     InpBtnHeight    = 36;         // Button height (px)
input int     InpBtnX         = 12;         // Buttons X from left (px)
input int     InpBtnY         = 26;         // Buttons Y from top (px)
input int     InpBtnGap       = 6;          // Gap between buttons (px)

input string  h4              = "===== Dashboard =====";
input bool             InpShowDash   = true;                 // Show dashboard
input ENUM_BASE_CORNER InpDashCorner = CORNER_LEFT_UPPER;    // Dashboard corner
input int              InpDashX      = 145;                  // Dashboard X offset (px)
input int              InpDashY      = 26;                   // Dashboard Y offset (px)

//============================ GLOBALS ===============================//
CTrade  trade;
int     hStoch = INVALID_HANDLE;
int     handle_dtm, handle_dtm_mtf, hmaHandle;

#define PREFIX      "MTP_"
#define BTN_BUY     PREFIX"btnBuy"
#define BTN_SELL    PREFIX"btnSell"
#define BTN_CLOSE   PREFIX"btnClose"
#define EDIT_LOT    PREFIX"editLot"
#define EDIT_SL     PREFIX"editSL"
#define EDIT_TP     PREFIX"editTP"
#define LBL_LOT     PREFIX"lblLot"
#define LBL_SL      PREFIX"lblSL"
#define LBL_TP      PREFIX"lblTP"
#define STATUS_LBL  PREFIX"status"
#define DASH_BG     PREFIX"dashBG"
#define DASH_LBL    PREFIX"dashLbl_"     // + index

#define BTN_ZORDER  1000                 // keep buttons above everything
#define ROW_H       22                   // height of an input row
#define FLBL_W      52                   // width of a field label

// dashboard geometry
#define DASH_W      240
#define DASH_LINEH  20
#define DASH_PAD    10
#define DASH_LINES  8
#define DASH_H      (DASH_PAD*2 + DASH_LINEH*DASH_LINES)

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   //--- Stochastic handle
   hStoch = iStochastic(_Symbol, _Period, InpKPeriod, InpDPeriod,
                        InpSlowing, InpStochMA, InpStochPrice);
                        
   handle_dtm_mtf = iCustom(_Symbol,_Period,"new//dtm_multitime");
   handle_dtm     = iCustom(_Symbol,_Period,"new//dtm");
   hmaHandle = iCustom(_Symbol, _Period, "zero-lag-hull-average", 600,4);
   //if(hStoch == INVALID_HANDLE)
   //   Print("Failed to create Stochastic handle");
   //else if(InpShowStoch)
   //   AddStochOnce();          // remove any existing copy, then add exactly one

   CreateButtons();
   CreateDashboard();
   RefreshDashboard();

   EventSetTimer(1);          // refresh stats / re-assert z-order once per second
   ChartRedraw();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   RemoveStoch();                    // take our indicator off the chart
   if(hStoch != INVALID_HANDLE)
      IndicatorRelease(hStoch);
   ObjectsDeleteAll(0, PREFIX);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Remove every Stochastic instance from the chart's subwindows     |
//+------------------------------------------------------------------+
void RemoveStoch()
  {
   int wins = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
   for(int w = wins - 1; w >= 1; w--)          // subwindow 0 is the price chart
     {
      int cnt = ChartIndicatorsTotal(0, w);
      for(int k = cnt - 1; k >= 0; k--)
        {
         string sname = ChartIndicatorName(0, w, k);
         if(StringFind(sname, "Stochastic") >= 0 || StringFind(sname, "Stoch") >= 0)
            ChartIndicatorDelete(0, w, sname);
        }
     }
  }

//+------------------------------------------------------------------+
//| Ensure exactly one Stochastic is on the chart                    |
//+------------------------------------------------------------------+
//void AddStochOnce()
//  {
//   RemoveStoch();                              // clear leftovers from prior init
//   int sub = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);   // next free subwindow
//   ChartIndicatorAdd(0, sub, hStoch);
//  }

//+------------------------------------------------------------------+
//| Tick — poll button state (OnChartEvent doesn't fire in tester)   |
//+------------------------------------------------------------------+
void OnTick()
  {
   PollButtons();
   RefreshDashboard();
  }

//+------------------------------------------------------------------+
//| Poll the latched button state and act on it                      |
//| This is how the working reference EA does it — checking          |
//| OBJPROP_STATE each tick works in the visual Strategy Tester,     |
//| whereas OnChartEvent clicks do NOT fire there.                   |
//+------------------------------------------------------------------+
void PollButtons()
  {
   bool acted = false;

   if(ObjectGetInteger(0, BTN_BUY, OBJPROP_STATE))
     {
      OpenTrade(ORDER_TYPE_BUY);
      ObjectSetInteger(0, BTN_BUY, OBJPROP_STATE, false);
      acted = true;
     }

   if(ObjectGetInteger(0, BTN_SELL, OBJPROP_STATE))
     {
      OpenTrade(ORDER_TYPE_SELL);
      ObjectSetInteger(0, BTN_SELL, OBJPROP_STATE, false);
      acted = true;
     }

   if(ObjectGetInteger(0, BTN_CLOSE, OBJPROP_STATE))
     {
      CloseTrades();
      ObjectSetInteger(0, BTN_CLOSE, OBJPROP_STATE, false);
      acted = true;
     }

   if(acted)
      ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Timer — works in the tester too; re-assert top-most z-order      |
//+------------------------------------------------------------------+
void OnTimer()
  {
   AssertButtonsTopMost();
   PollButtons();          // catch presses even when ticks are sparse
   RefreshDashboard();
  }

//+------------------------------------------------------------------+
//| Chart events — used on LIVE charts for instant response and to    |
//| normalize edit fields. In the tester, PollButtons() does the work.|
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
  {
   //--- normalize field text after the user finishes editing
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
     {
      if(sparam == EDIT_LOT)
         ObjectSetString(0, EDIT_LOT, OBJPROP_TEXT, DoubleToString(GetFieldLot(), 2));
      else if(sparam == EDIT_SL)
         ObjectSetString(0, EDIT_SL, OBJPROP_TEXT, (string)GetFieldSL());
      else if(sparam == EDIT_TP)
         ObjectSetString(0, EDIT_TP, OBJPROP_TEXT, (string)GetFieldTP());
      ChartRedraw();
      return;
     }

   //--- on a live chart, react to the click immediately
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      PollButtons();
      RefreshDashboard();
     }
  }

//+------------------------------------------------------------------+
//| Open a market trade with robust filling mode                     |
//+------------------------------------------------------------------+
void OpenTrade(const ENUM_ORDER_TYPE type)
  {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = 0.0, tp = 0.0;
   bool ok = false;

   //--- read live values from the on-chart fields
   double lot   = GetFieldLot();
   int    slPts = GetFieldSL();
   int    tpPts = GetFieldTP();

   //--- try both FOK and IOC filling modes (common tester/broker issue)
   ENUM_ORDER_TYPE_FILLING fillModes[] = {ORDER_FILLING_FOK, ORDER_FILLING_IOC, ORDER_FILLING_RETURN};

   for(int attempt = 0; attempt < ArraySize(fillModes) && !ok; attempt++)
     {
      trade.SetTypeFilling(fillModes[attempt]);

      if(type == ORDER_TYPE_BUY)
        {
         if(slPts > 0) sl = NormalizeDouble(ask - slPts * point, _Digits);
         if(tpPts > 0) tp = NormalizeDouble(ask + tpPts * point, _Digits);
         ok = trade.Buy(lot, _Symbol, ask, sl, tp, "Manual BUY");
        }
      else if(type == ORDER_TYPE_SELL)
        {
         if(slPts > 0) sl = NormalizeDouble(bid + slPts * point, _Digits);
         if(tpPts > 0) tp = NormalizeDouble(bid - tpPts * point, _Digits);
         ok = trade.Sell(lot, _Symbol, bid, sl, tp, "Manual SELL");
        }

      if(ok) break;   // success, stop trying
     }

   //--- show result on chart
   string status = "";
   color  clr    = clrWhite;
   if(ok)
     {
      status = StringFormat("%s %.2f @ %.5f  #%I64u",
                           type == ORDER_TYPE_BUY ? "BUY" : "SELL",
                           lot, type == ORDER_TYPE_BUY ? ask : bid,
                           trade.ResultOrder());
      clr = clrLime;
     }
   else
     {
      status = StringFormat("FAILED: %d - %s", trade.ResultRetcode(),
                           trade.ResultRetcodeDescription());
      clr = clrRed;
      Print(status);   // also to journal for debugging
     }
   ShowStatus(status, clr);
  }

//+------------------------------------------------------------------+
//| Close all positions for this symbol + magic                      |
//+------------------------------------------------------------------+
void CloseTrades()
  {
   int closed = 0, failed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)  continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagic) continue;

      //--- try each filling mode for the close too
      bool ok = false;
      ENUM_ORDER_TYPE_FILLING fillModes[] = {ORDER_FILLING_FOK, ORDER_FILLING_IOC, ORDER_FILLING_RETURN};
      for(int a = 0; a < ArraySize(fillModes) && !ok; a++)
        {
         trade.SetTypeFilling(fillModes[a]);
         ok = trade.PositionClose(ticket);
        }

      if(ok) closed++;
      else
        {
         failed++;
         PrintFormat("Close failed ticket=%I64u retcode=%d (%s)", ticket,
                     trade.ResultRetcode(), trade.ResultRetcodeDescription());
        }
     }

   if(closed == 0 && failed == 0)
      ShowStatus("No open trades to close", clrSilver);
   else if(failed == 0)
      ShowStatus(StringFormat("Closed %d position(s)", closed), clrLime);
   else
      ShowStatus(StringFormat("Closed %d, %d failed (see Journal)", closed, failed), clrOrange);
  }

//+==================================================================+
//|                        UI  CONSTRUCTION                          |
//+==================================================================+
void CreateButtons()
  {
   int y = InpBtnY;

   //--- editable input fields (Lot / SL / TP)
   int fieldX = InpBtnX + FLBL_W + 4;
   int fieldW = InpBtnWidth - FLBL_W - 4;
   MakeFieldLabel(LBL_LOT, "Lot",     InpBtnX, y);
   MakeEdit      (EDIT_LOT, DoubleToString(InpLot, 2),       fieldX, y, fieldW);  y += ROW_H + 2;
   MakeFieldLabel(LBL_SL,  "SL pts",  InpBtnX, y);
   MakeEdit      (EDIT_SL,  (string)InpStopLossPts,          fieldX, y, fieldW);  y += ROW_H + 2;
   MakeFieldLabel(LBL_TP,  "TP pts",  InpBtnX, y);
   MakeEdit      (EDIT_TP,  (string)InpTakeProfitPts,        fieldX, y, fieldW);  y += ROW_H + InpBtnGap + 4;

   //--- action buttons
   MakeButton(BTN_BUY,   "BUY",        InpBtnX, y, clrWhite, C'0,153,76');   y += InpBtnHeight + InpBtnGap;
   MakeButton(BTN_SELL,  "SELL",       InpBtnX, y, clrWhite, C'204,0,0');    y += InpBtnHeight + InpBtnGap;
   MakeButton(BTN_CLOSE, "CLOSE TRADE",InpBtnX, y, clrWhite, C'80,80,80');
   y += InpBtnHeight + InpBtnGap;

   //--- status line (last action result)
   ObjectDelete(0, STATUS_LBL);
   ObjectCreate(0, STATUS_LBL, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, STATUS_LBL, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, STATUS_LBL, OBJPROP_XDISTANCE,  InpBtnX);
   ObjectSetInteger(0, STATUS_LBL, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, STATUS_LBL, OBJPROP_ANCHOR,     ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, STATUS_LBL, OBJPROP_COLOR,      clrSilver);
   ObjectSetInteger(0, STATUS_LBL, OBJPROP_FONTSIZE,   8);
   ObjectSetString (0, STATUS_LBL, OBJPROP_FONT,       "Arial");
   ObjectSetString (0, STATUS_LBL, OBJPROP_TEXT,       "Ready");
   ObjectSetInteger(0, STATUS_LBL, OBJPROP_BACK,       false);
   ObjectSetInteger(0, STATUS_LBL, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, STATUS_LBL, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, STATUS_LBL, OBJPROP_ZORDER,     BTN_ZORDER);

   AssertButtonsTopMost();
  }

//--- update the on-chart status line
void ShowStatus(const string text, const color clr)
  {
   if(ObjectFind(0, STATUS_LBL) < 0) return;
   ObjectSetString (0, STATUS_LBL, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, STATUS_LBL, OBJPROP_COLOR, clr);
   ChartRedraw();
  }

//--- small caption to the left of an edit field
void MakeFieldLabel(const string name, const string text, const int x, const int y)
  {
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y + 3);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,     ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clrGainsboro);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   9);
   ObjectSetString (0, name, OBJPROP_FONT,       "Arial");
   ObjectSetString (0, name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,     BTN_ZORDER);
  }

//--- editable text field
void MakeEdit(const string name, const string text, const int x, const int y, const int w)
  {
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,      ROW_H);
   ObjectSetString (0, name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clrBlack);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrDimGray);
   ObjectSetInteger(0, name, OBJPROP_ALIGN,      ALIGN_CENTER);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   10);
   ObjectSetString (0, name, OBJPROP_FONT,       "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_READONLY,   false);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,     BTN_ZORDER);
  }

//--- read + validate the current field values (fall back to inputs)
double GetFieldLot()
  {
   double v = (double)StringToDouble(ObjectGetString(0, EDIT_LOT, OBJPROP_TEXT));
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(v <= 0.0) v = InpLot;
   if(stepLot > 0.0) v = MathRound(v / stepLot) * stepLot;
   if(minLot  > 0.0 && v < minLot) v = minLot;
   if(maxLot  > 0.0 && v > maxLot) v = maxLot;
   return v;
  }

int GetFieldSL()
  {
   int v = (int)StringToInteger(ObjectGetString(0, EDIT_SL, OBJPROP_TEXT));
   return (v < 0) ? 0 : v;
  }

int GetFieldTP()
  {
   int v = (int)StringToInteger(ObjectGetString(0, EDIT_TP, OBJPROP_TEXT));
   return (v < 0) ? 0 : v;
  }

void MakeButton(const string name, const string text, const int x, const int y,
                const color txtColor, const color bgColor)
  {
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,     InpBtnWidth);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,     InpBtnHeight);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     txtColor);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,   bgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  10);
   ObjectSetString (0, name, OBJPROP_FONT,      "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_STATE,     false);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);   // foreground element
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,    true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,    BTN_ZORDER);
  }

//--- re-assert that buttons sit on top of any later chart drawings
void AssertButtonsTopMost()
  {
   string names[] = {BTN_BUY, BTN_SELL, BTN_CLOSE,
                     EDIT_LOT, EDIT_SL, EDIT_TP,
                     LBL_LOT, LBL_SL, LBL_TP};
   for(int i = 0; i < ArraySize(names); i++)
     {
      if(ObjectFind(0, names[i]) < 0) continue;
      ObjectSetInteger(0, names[i], OBJPROP_BACK,   false);
      ObjectSetInteger(0, names[i], OBJPROP_ZORDER, BTN_ZORDER);
     }
  }

//+------------------------------------------------------------------+
//| Dashboard construction                                           |
//+------------------------------------------------------------------+
void CreateDashboard()
  {
   ObjectsDeleteAll(0, DASH_BG);
   ObjectsDeleteAll(0, DASH_LBL);
   if(!InpShowDash)
      return;

   bool rightSide  = (InpDashCorner == CORNER_RIGHT_UPPER || InpDashCorner == CORNER_RIGHT_LOWER);

   // background panel
   ObjectCreate(0, DASH_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, DASH_BG, OBJPROP_CORNER,     InpDashCorner);
   ObjectSetInteger(0, DASH_BG, OBJPROP_XDISTANCE,  InpDashX);
   ObjectSetInteger(0, DASH_BG, OBJPROP_YDISTANCE,  InpDashY);
   ObjectSetInteger(0, DASH_BG, OBJPROP_XSIZE,      DASH_W);
   ObjectSetInteger(0, DASH_BG, OBJPROP_YSIZE,      DASH_H);
   ObjectSetInteger(0, DASH_BG, OBJPROP_BGCOLOR,    C'25,25,35');
   ObjectSetInteger(0, DASH_BG, OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0, DASH_BG, OBJPROP_COLOR,      C'90,90,120');
   ObjectSetInteger(0, DASH_BG, OBJPROP_BACK,       false);
   ObjectSetInteger(0, DASH_BG, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, DASH_BG, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, DASH_BG, OBJPROP_ZORDER,     0);

   // text lines
   for(int i = 0; i < DASH_LINES; i++)
     {
      string nm = DASH_LBL + (string)i;
      int    x  = InpDashX + DASH_PAD;
      int    y  = InpDashY + DASH_PAD + i * DASH_LINEH;
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER,     InpDashCorner);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE,  x);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE,  y);
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR,     rightSide ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,      clrGainsboro);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,   9);
      ObjectSetString (0, nm, OBJPROP_FONT,       "Consolas");
      ObjectSetInteger(0, nm, OBJPROP_BACK,       false);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER,     1);
      ObjectSetString (0, nm, OBJPROP_TEXT,       "");
     }
  }

void SetDashLine(const int idx, const string text, const color clr)
  {
   string nm = DASH_LBL + (string)idx;
   if(ObjectFind(0, nm) < 0) return;
   ObjectSetString (0, nm, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
  }

//+------------------------------------------------------------------+
//| Refresh dashboard values                                         |
//+------------------------------------------------------------------+
void RefreshDashboard()
  {
   if(!InpShowDash)
      return;
   if(ObjectFind(0, DASH_BG) < 0)     // (re)build if missing
      CreateDashboard();

   //--- gather statistics from closed deals
   int    trades = 0, wins = 0, losses = 0;
   double grossProfit = 0.0, grossLoss = 0.0;
   double sumWin = 0.0, sumLoss = 0.0;
   double balance = 0.0, peak = 0.0, maxDD = 0.0, maxDDpct = 0.0;

   if(HistorySelect(0, TimeCurrent()))
     {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;

         long   type   = HistoryDealGetInteger(ticket, DEAL_TYPE);
         double profit = HistoryDealGetDouble (ticket, DEAL_PROFIT);
         double swap   = HistoryDealGetDouble (ticket, DEAL_SWAP);
         double comm   = HistoryDealGetDouble (ticket, DEAL_COMMISSION);
         double net    = profit + swap + comm;

         //--- balance/equity curve for drawdown (all account deals)
         balance += net;
         if(balance > peak) peak = balance;
         double dd = peak - balance;
         if(dd > maxDD) maxDD = dd;
         if(peak > 0.0)
           {
            double ddp = dd / peak * 100.0;
            if(ddp > maxDDpct) maxDDpct = ddp;
           }

         //--- trade win/loss stats for this symbol + magic
         if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) continue;               // skip balance ops
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;   // only closes
         if(HistoryDealGetString (ticket, DEAL_SYMBOL) != _Symbol)  continue;
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC)  != InpMagic) continue;

         trades++;
         if(net >= 0.0) { wins++;   grossProfit += net;      sumWin  += net;      }
         else           { losses++; grossLoss   += -net;     sumLoss += -net;     }
        }
     }

   double winrate = (trades > 0) ? (100.0 * wins / trades) : 0.0;
   double pf      = (grossLoss > 0.0) ? (grossProfit / grossLoss)
                                      : (grossProfit > 0.0 ? 999.99 : 0.0);
   double avgWin  = (wins   > 0) ? (sumWin  / wins)   : 0.0;
   double avgLoss = (losses > 0) ? (sumLoss / losses) : 0.0;
   double rr      = (avgLoss > 0.0) ? (avgWin / avgLoss)
                                    : (avgWin > 0.0 ? 999.99 : 0.0);

   //--- stochastic current values
   double kv[1], dv[1];
   double kVal = 0.0, dVal = 0.0;
   if(hStoch != INVALID_HANDLE)
     {
      if(CopyBuffer(hStoch, 0, 0, 1, kv) == 1) kVal = kv[0];
      if(CopyBuffer(hStoch, 1, 0, 1, dv) == 1) dVal = dv[0];
     }

   //--- paint lines
   SetDashLine(0, "  MANUAL TRADE PANEL",                              clrWhite);
   SetDashLine(1, StringFormat("Trades       : %d", trades),           clrGainsboro);
   SetDashLine(2, StringFormat("Win rate     : %.1f %%", winrate),     winrate >= 50 ? clrLime : clrOrange);
   SetDashLine(3, StringFormat("Profit factor: %.2f", pf),            pf >= 1.0 ? clrLime : clrOrange);
   SetDashLine(4, StringFormat("Risk:Reward  : 1 : %.2f", rr),         clrAqua);
   SetDashLine(5, StringFormat("Max drawdown : %.2f (%.1f%%)", maxDD, maxDDpct), clrTomato);
   SetDashLine(6, StringFormat("Open P/L     : %.2f", OpenPnL()),      clrGold);
   SetDashLine(7, StringFormat("Stoch  K:%.1f  D:%.1f", kVal, dVal),   clrCornflowerBlue);
  }

//+------------------------------------------------------------------+
//| Floating P/L of currently open positions (symbol + magic)        |
//+------------------------------------------------------------------+
double OpenPnL()
  {
   double p = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)  continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagic) continue;
      p += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return p;
  }
//+------------------------------------------------------------------+
