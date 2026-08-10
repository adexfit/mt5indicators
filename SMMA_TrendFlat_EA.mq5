//+------------------------------------------------------------------+
//|                                            SMMA_TrendFlat_EA.mq5  |
//|   Production-grade Expert Advisor built on three SMMA_TrendFlat    |
//|   indicators:                                                     |
//|                                                                   |
//|     1. SMMA_TrendFlat      (current chart TF, e.g. M1)  -> SIGNAL  |
//|          A flip of its trend line to GREEN is a BUY signal,       |
//|          a flip to RED is a SELL signal.                          |
//|                                                                   |
//|     2. SMMA_TrendFlat_MTF  (e.g. M5 trend on the M1 chart)        |
//|          Optional trend confirmation #1.                          |
//|                                                                   |
//|     3. SMMA_TrendFlat_MTF  (e.g. H1 trend on the M1 chart)        |
//|          Optional trend confirmation #2.                          |
//|                                                                   |
//|   A BUY is taken only when the signal flips bullish AND every     |
//|   ENABLED confirmation is bullish. A SELL is the mirror image.    |
//|   The two confirmation filters are independent and may be used    |
//|   individually or together.                                       |
//|                                                                   |
//|   Trend is read from the indicators' COLOR_INDEX buffer (#1) at   |
//|   shift 1 (the last CLOSED bar) so signals never repaint.         |
//|                                                                   |
//|   Trade management: fixed / risk-% sizing, fixed-pip / ATR stop,  |
//|   fixed-pip / ATR / RRR take-profit, break-even, fixed & ATR      |
//|   trailing stop, spread filter, session filter, daily-loss guard, |
//|   close/reverse on opposite signal.                               |
//+------------------------------------------------------------------+
#property copyright "SMMA TrendFlat EA"
#property link      ""
#property version   "1.00"
#property description "Three-indicator SMMA TrendFlat EA (signal + 2 optional MTF trend filters)"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//====================================================================
//  ENUMS
//====================================================================
enum ENUM_MM_MODE
  {
   MM_FIXED_LOT   = 0,   // Fixed lot
   MM_RISK_PERCENT= 1    // Risk % of balance (needs a Stop Loss)
  };

enum ENUM_SL_MODE
  {
   SL_NONE       = 0,    // No stop loss
   SL_FIXED_PIPS = 1,    // Fixed pips
   SL_ATR        = 2     // ATR multiple
  };

enum ENUM_TP_MODE
  {
   TP_NONE       = 0,    // No take profit
   TP_FIXED_PIPS = 1,    // Fixed pips
   TP_ATR        = 2,    // ATR multiple
   TP_RRR        = 3     // Risk/Reward ratio (needs a Stop Loss)
  };

enum ENUM_TRAIL_MODE
  {
   TRAIL_FIXED_PIPS = 0, // Fixed pips distance
   TRAIL_ATR        = 1  // ATR multiple distance
  };

//====================================================================
//  INPUTS
//====================================================================
input group "=== Signal indicator (current TF) ==="
input string          InpSignalName      = "SMMA_TrendFlat";     // Signal indicator file name
input int             InpSigPeriod       = 5;                    // Signal: SMMA period
input double          InpSigMinBreakPips = 0.0;                  // Signal: min break (pips)

input group "=== Confirmation #1 (MTF) ==="
input bool            InpUseConf1        = true;                 // Enable confirmation #1
input ENUM_TIMEFRAMES InpConf1TF         = PERIOD_M5;            // Confirmation #1 timeframe
input int             InpConf1Period     = 5;                    // Confirmation #1: SMMA period
input double          InpConf1MinBreak   = 0.0;                  // Confirmation #1: min break (pips)

input group "=== Confirmation #2 (MTF) ==="
input bool            InpUseConf2        = true;                 // Enable confirmation #2
input ENUM_TIMEFRAMES InpConf2TF         = PERIOD_H1;            // Confirmation #2 timeframe
input int             InpConf2Period     = 5;                    // Confirmation #2: SMMA period
input double          InpConf2MinBreak   = 0.0;                  // Confirmation #2: min break (pips)
input string          InpMTFName         = "SMMA_TrendFlat_MTF"; // MTF indicator file name

input group "=== Trade direction / execution ==="
input bool            InpAllowBuys       = true;                 // Allow BUY trades
input bool            InpAllowSells      = true;                 // Allow SELL trades
input int             InpMaxPositions    = 1;                    // Max open positions (this EA)
input bool            InpCloseOnOpposite = true;                 // Close position on opposite signal
input long            InpMagic           = 770101;              // Magic number
input ulong           InpDeviationPts    = 20;                   // Max slippage (points)
input string          InpComment         = "SMMA_TF_EA";         // Order comment

input group "=== Money management ==="
input ENUM_MM_MODE    InpMMMode          = MM_FIXED_LOT;         // Position sizing mode
input double          InpFixedLots       = 0.10;                // Fixed lot size
input double          InpRiskPercent     = 1.0;                  // Risk % per trade (risk mode)

input group "=== Stop loss ==="
input ENUM_SL_MODE    InpSLMode          = SL_FIXED_PIPS;        // Stop-loss mode
input double          InpSLFixedPips     = 15.0;                // SL fixed distance (pips)
input double          InpSLAtrMult       = 1.5;                  // SL ATR multiple

input group "=== Take profit ==="
input ENUM_TP_MODE    InpTPMode          = TP_RRR;               // Take-profit mode
input double          InpTPFixedPips     = 30.0;                // TP fixed distance (pips)
input double          InpTPAtrMult       = 3.0;                  // TP ATR multiple
input double          InpTP_RRR          = 2.0;                  // TP risk/reward ratio

input group "=== ATR (for ATR-based SL/TP/trail) ==="
input int             InpAtrPeriod       = 14;                   // ATR period
input ENUM_TIMEFRAMES InpAtrTF           = PERIOD_CURRENT;       // ATR timeframe

input group "=== Break-even ==="
input bool            InpUseBreakEven    = true;                 // Enable break-even
input double          InpBETriggerPips   = 10.0;                // BE trigger profit (pips)
input double          InpBEOffsetPips    = 1.0;                  // BE locked profit (pips)

input group "=== Trailing stop ==="
input bool            InpUseTrailing     = true;                 // Enable trailing stop
input ENUM_TRAIL_MODE InpTrailMode       = TRAIL_FIXED_PIPS;     // Trailing mode
input double          InpTrailStartPips  = 12.0;                // Trailing start profit (pips)
input double          InpTrailDistPips   = 10.0;                // Trailing distance (pips)
input double          InpTrailAtrMult    = 1.5;                  // Trailing distance (ATR mult)
input double          InpTrailStepPips   = 2.0;                  // Min step to move SL (pips)

input group "=== Filters ==="
input long            InpMaxSpreadPts    = 30;                   // Max spread (points, 0 = off)
input bool            InpUseTimeFilter   = false;                // Enable session time filter
input int             InpStartHour       = 0;                    // Session start hour (server)
input int             InpStartMin        = 0;                    // Session start minute
input int             InpEndHour         = 24;                   // Session end hour (server)
input int             InpEndMin          = 0;                    // Session end minute

input group "=== Risk guard ==="
input bool            InpUseDailyLoss    = false;                // Enable daily loss limit
input double          InpDailyLossPct    = 5.0;                  // Daily loss limit (% of day-start balance)
input bool            InpCloseOnDailyLoss= false;                // Close all when daily loss hit

input group "=== Misc ==="
input bool            InpNewBarOnly      = true;                 // Evaluate signals on new bar only
input bool            InpShowPanel       = true;                 // Show status comment on chart

//====================================================================
//  GLOBALS
//====================================================================
CTrade         trade;
CPositionInfo  pos;

//--- COLOR_INDEX buffer palette (must match the indicators)
#define BUF_COLOR   1     // SetIndexBuffer index of the COLOR_INDEX buffer
#define COL_BULL    0
#define COL_BEAR    1
#define COL_NEUTRAL 2

int      hSignal = INVALID_HANDLE;
int      hConf1  = INVALID_HANDLE;
int      hConf2  = INVALID_HANDLE;
int      hATR    = INVALID_HANDLE;

double   g_pip     = 0.0;      // pip size in price
datetime g_lastBar = 0;        // last processed bar time (new-bar gate)
datetime g_lastSig = 0;        // bar time of the last acted-on signal

datetime g_dayStamp     = 0;   // start-of-day (date) anchor
double   g_dayStartBal  = 0.0; // balance at start of the trading day
bool     g_dailyBlocked = false;

//====================================================================
//  INIT
//====================================================================
int OnInit()
  {
   g_pip = PipSize();

   //--- signal indicator on the current chart timeframe
   hSignal = iCustom(_Symbol,_Period,InpSignalName,
                     InpSigPeriod,InpSigMinBreakPips,false,1.0,0.3);
   if(hSignal==INVALID_HANDLE)
     {
      Print("EA: failed to create signal indicator handle (",InpSignalName,
            "). Ensure it is compiled in MQL5\\Indicators.");
      return(INIT_FAILED);
     }

   //--- optional confirmation #1
   if(InpUseConf1)
     {
      hConf1 = iCustom(_Symbol,_Period,InpMTFName,
                       InpConf1TF,InpConf1Period,InpConf1MinBreak,false,1.0,0.3);
      if(hConf1==INVALID_HANDLE)
        {
         Print("EA: failed to create confirmation #1 handle (",InpMTFName,")");
         return(INIT_FAILED);
        }
     }

   //--- optional confirmation #2
   if(InpUseConf2)
     {
      hConf2 = iCustom(_Symbol,_Period,InpMTFName,
                       InpConf2TF,InpConf2Period,InpConf2MinBreak,false,1.0,0.3);
      if(hConf2==INVALID_HANDLE)
        {
         Print("EA: failed to create confirmation #2 handle (",InpMTFName,")");
         return(INIT_FAILED);
        }
     }

   //--- ATR (only needed for ATR-based SL/TP/trailing)
   if(NeedATR())
     {
      ENUM_TIMEFRAMES atf = (InpAtrTF==PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpAtrTF;
      hATR = iATR(_Symbol,atf,MathMax(1,InpAtrPeriod));
      if(hATR==INVALID_HANDLE)
        {
         Print("EA: failed to create ATR handle");
         return(INIT_FAILED);
        }
     }

   //--- trade object setup
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   //--- sanity warnings
   if(InpMMMode==MM_RISK_PERCENT && InpSLMode==SL_NONE)
      Print("EA warning: risk-% sizing needs a Stop Loss. Falling back to fixed lots.");
   if(InpTPMode==TP_RRR && InpSLMode==SL_NONE)
      Print("EA warning: RRR take-profit needs a Stop Loss. TP will be disabled.");

   UpdateDayAnchor(true);

   g_lastBar = iTime(_Symbol,_Period,0);
   Print("SMMA_TrendFlat_EA initialised on ",_Symbol," ",EnumToString((ENUM_TIMEFRAMES)_Period));
   return(INIT_SUCCEEDED);
  }

//====================================================================
//  DEINIT
//====================================================================
void OnDeinit(const int reason)
  {
   if(hSignal!=INVALID_HANDLE) IndicatorRelease(hSignal);
   if(hConf1 !=INVALID_HANDLE) IndicatorRelease(hConf1);
   if(hConf2 !=INVALID_HANDLE) IndicatorRelease(hConf2);
   if(hATR   !=INVALID_HANDLE) IndicatorRelease(hATR);
   if(InpShowPanel) Comment("");
  }

//====================================================================
//  MAIN
//====================================================================
void OnTick()
  {
   UpdateDayAnchor(false);

   //--- manage open positions on every tick (BE + trailing)
   ManageOpenPositions();

   //--- daily-loss guard
   if(DailyLossHit())
     {
      if(!g_dailyBlocked)
        {
         g_dailyBlocked=true;
         Print("EA: daily loss limit hit - new entries blocked for today.");
         if(InpCloseOnDailyLoss) CloseAll("daily-loss");
        }
      if(InpShowPanel) ShowPanel("DAILY LOSS BLOCK");
      return;
     }

   //--- new-bar gate (signals evaluate on closed bars only)
   datetime bt = iTime(_Symbol,_Period,0);
   bool newBar = (bt!=g_lastBar);
   if(newBar) g_lastBar = bt;
   if(InpNewBarOnly && !newBar)
     {
      if(InpShowPanel) ShowPanel("");
      return;
     }

   //--- read the signal (last closed bar = shift 1)
   int cSig1=0, cSig2=0;
   if(!ReadColor(hSignal,1,cSig1) || !ReadColor(hSignal,2,cSig2))
     {
      if(InpShowPanel) ShowPanel("indicator not ready");
      return; // indicators not ready yet
     }

   bool bullFlip = (cSig1==COL_BULL && cSig2!=COL_BULL);
   bool bearFlip = (cSig1==COL_BEAR && cSig2!=COL_BEAR);

   //--- act once per signal bar
   if((bullFlip || bearFlip) && bt==g_lastSig)
      { bullFlip=false; bearFlip=false; }

   //--- close on opposite raw signal (independent of confirmations)
   if(InpCloseOnOpposite)
     {
      if(bullFlip) CloseDirection(false,"opposite-signal"); // close sells
      if(bearFlip) CloseDirection(true ,"opposite-signal"); // close buys
     }

   //--- confirmations
   bool conf1Bull=true, conf1Bear=true, conf2Bull=true, conf2Bear=true;
   if(InpUseConf1)
     {
      int c=0;
      if(!ReadColor(hConf1,1,c)) { if(InpShowPanel) ShowPanel("conf1 not ready"); return; }
      conf1Bull=(c==COL_BULL);
      conf1Bear=(c==COL_BEAR);
     }
   if(InpUseConf2)
     {
      int c=0;
      if(!ReadColor(hConf2,1,c)) { if(InpShowPanel) ShowPanel("conf2 not ready"); return; }
      conf2Bull=(c==COL_BULL);
      conf2Bear=(c==COL_BEAR);
     }

   bool buySignal  = bullFlip && conf1Bull && conf2Bull;
   bool sellSignal = bearFlip && conf1Bear && conf2Bear;

   //--- entry filters
   if((buySignal || sellSignal) && EntryAllowed())
     {
      if(buySignal  && InpAllowBuys  && CountPositions(POSITION_TYPE_BUY,false)<InpMaxPositions)
        { if(OpenTrade(true))  g_lastSig=bt; }
      if(sellSignal && InpAllowSells && CountPositions(POSITION_TYPE_SELL,false)<InpMaxPositions)
        { if(OpenTrade(false)) g_lastSig=bt; }
     }

   if(InpShowPanel)
      ShowPanel(buySignal?"BUY signal":(sellSignal?"SELL signal":""));
  }

//====================================================================
//  SIGNAL / INDICATOR HELPERS
//====================================================================
//--- read the COLOR_INDEX buffer of an iCustom handle at a given shift
bool ReadColor(const int handle,const int shift,int &colorOut)
  {
   if(handle==INVALID_HANDLE) return false;
   if(BarsCalculated(handle)<=shift+1) return false;
   double a[];
   ArraySetAsSeries(a,true);
   if(CopyBuffer(handle,BUF_COLOR,shift,1,a)!=1) return false;
   colorOut=(int)MathRound(a[0]);
   return true;
  }

//====================================================================
//  ORDER OPENING
//====================================================================
bool OpenTrade(const bool isBuy)
  {
   double ask   = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(ask<=0.0 || bid<=0.0) return false;
   double entry = isBuy ? ask : bid;

   //--- ATR value (closed bar) if needed
   double atr = 0.0;
   if(NeedATR() && !GetATR(atr)) { Print("EA: ATR not ready, entry skipped."); return false; }

   //--- stop-loss distance
   double slDist = 0.0;
   switch(InpSLMode)
     {
      case SL_FIXED_PIPS: slDist = InpSLFixedPips * g_pip;  break;
      case SL_ATR:        slDist = atr * InpSLAtrMult;      break;
      case SL_NONE:       slDist = 0.0;                     break;
     }

   //--- take-profit distance
   double tpDist = 0.0;
   switch(InpTPMode)
     {
      case TP_FIXED_PIPS: tpDist = InpTPFixedPips * g_pip;  break;
      case TP_ATR:        tpDist = atr * InpTPAtrMult;      break;
      case TP_RRR:        tpDist = (slDist>0.0) ? slDist * InpTP_RRR : 0.0; break;
      case TP_NONE:       tpDist = 0.0;                     break;
     }

   //--- respect the broker minimum stop distance
   double minDist = MinStopDistance();
   if(slDist>0.0 && slDist<minDist) slDist = minDist;
   if(tpDist>0.0 && tpDist<minDist) tpDist = minDist;

   //--- absolute SL/TP prices
   double sl=0.0, tp=0.0;
   if(slDist>0.0) sl = isBuy ? entry-slDist : entry+slDist;
   if(tpDist>0.0) tp = isBuy ? entry+tpDist : entry-tpDist;
   if(sl>0.0) sl = NormalizeDouble(sl,_Digits);
   if(tp>0.0) tp = NormalizeDouble(tp,_Digits);

   //--- position size
   double lots = CalcLots(slDist);
   if(lots<=0.0) { Print("EA: computed lot size <= 0, entry skipped."); return false; }

   bool ok = isBuy ? trade.Buy(lots,_Symbol,0.0,sl,tp,InpComment)
                   : trade.Sell(lots,_Symbol,0.0,sl,tp,InpComment);

   if(!ok)
     {
      PrintFormat("EA: %s failed. retcode=%d (%s)",
                  isBuy?"BUY":"SELL",trade.ResultRetcode(),trade.ResultRetcodeDescription());
      return false;
     }

   PrintFormat("EA: %s %.2f lots @ ~%.*f  SL=%.*f  TP=%.*f",
               isBuy?"BUY":"SELL",lots,_Digits,entry,_Digits,sl,_Digits,tp);
   return true;
  }

//--- lot sizing (fixed or risk-percent based on SL distance in price)
double CalcLots(const double slDistPrice)
  {
   double lots = InpFixedLots;

   if(InpMMMode==MM_RISK_PERCENT && slDistPrice>0.0)
     {
      double tickVal = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
      double tickSz  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tickVal>0.0 && tickSz>0.0)
        {
         double riskMoney  = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent/100.0;
         double lossPerLot = slDistPrice / tickSz * tickVal;
         if(lossPerLot>0.0) lots = riskMoney / lossPerLot;
        }
     }
   return NormalizeLots(lots);
  }

//--- clamp/round a lot value to the symbol's volume constraints
double NormalizeLots(double lots)
  {
   double minL = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0.0) step=0.01;
   lots = MathFloor(lots/step+0.5)*step;
   if(lots<minL) lots=minL;
   if(lots>maxL) lots=maxL;
   return NormalizeDouble(lots,2);
  }

//====================================================================
//  POSITION MANAGEMENT (break-even + trailing)
//====================================================================
void ManageOpenPositions()
  {
   if(!InpUseBreakEven && !InpUseTrailing) return;

   double atr=0.0;
   bool haveAtr = (!InpUseTrailing || InpTrailMode!=TRAIL_ATR) ? true : GetATR(atr);

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(!pos.SelectByTicket(ticket)) continue;
      if(pos.Symbol()!=_Symbol || pos.Magic()!=InpMagic) continue;

      bool   isBuy = (pos.PositionType()==POSITION_TYPE_BUY);
      double entry = pos.PriceOpen();
      double curSL = pos.StopLoss();
      double curTP = pos.TakeProfit();
      double bid   = SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double ask   = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double px    = isBuy ? bid : ask;                 // current close price for this side
      double profit= isBuy ? (bid-entry) : (entry-ask); // profit distance in price
      double minD  = MinStopDistance();
      double step  = InpTrailStepPips * g_pip;

      double desired = curSL; // start from current stop

      //--- break-even
      if(InpUseBreakEven && profit >= InpBETriggerPips*g_pip)
        {
         double beSL = isBuy ? entry + InpBEOffsetPips*g_pip
                             : entry - InpBEOffsetPips*g_pip;
         desired = ImproveStop(isBuy,desired,beSL);
        }

      //--- trailing
      if(InpUseTrailing && profit >= InpTrailStartPips*g_pip)
        {
         double dist = (InpTrailMode==TRAIL_ATR) ? (haveAtr?atr*InpTrailAtrMult:0.0)
                                                 : InpTrailDistPips*g_pip;
         if(dist>0.0)
           {
            double trSL = isBuy ? px - dist : px + dist;
            desired = ImproveStop(isBuy,desired,trSL);
           }
        }

      if(desired<=0.0) continue;

      //--- keep the stop a valid distance away from the market
      if(isBuy  && desired > bid-minD) desired = bid-minD;
      if(!isBuy && desired < ask+minD) desired = ask+minD;
      desired = NormalizeDouble(desired,_Digits);

      //--- only modify on a meaningful improvement
      bool improve = (curSL<=0.0)
                     ? (isBuy ? desired<bid-minD : desired>ask+minD)
                     : (isBuy ? desired>=curSL+step : desired<=curSL-step);
      if(!improve) continue;
      if(MathAbs(desired-curSL) < _Point) continue;

      if(!trade.PositionModify(ticket,desired,curTP))
         PrintFormat("EA: modify SL failed #%I64u retcode=%d (%s)",
                     ticket,trade.ResultRetcode(),trade.ResultRetcodeDescription());
     }
  }

//--- return the more protective of two stops for the given side
double ImproveStop(const bool isBuy,const double current,const double candidate)
  {
   if(candidate<=0.0) return current;
   if(current<=0.0)   return candidate;
   return isBuy ? MathMax(current,candidate) : MathMin(current,candidate);
  }

//====================================================================
//  CLOSING HELPERS
//====================================================================
//--- close every position of one side (true=buys, false=sells)
void CloseDirection(const bool buys,const string why)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!pos.SelectByTicket(ticket)) continue;
      if(pos.Symbol()!=_Symbol || pos.Magic()!=InpMagic) continue;
      bool isBuy=(pos.PositionType()==POSITION_TYPE_BUY);
      if(isBuy!=buys) continue;
      if(!trade.PositionClose(ticket))
         PrintFormat("EA: close (%s) failed #%I64u retcode=%d",why,ticket,trade.ResultRetcode());
     }
  }

void CloseAll(const string why)
  {
   CloseDirection(true ,why);
   CloseDirection(false,why);
  }

//--- count this EA's positions (dirFilter ignored when any=true)
int CountPositions(const ENUM_POSITION_TYPE dir,const bool any)
  {
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!pos.SelectByTicket(ticket)) continue;
      if(pos.Symbol()!=_Symbol || pos.Magic()!=InpMagic) continue;
      if(any || pos.PositionType()==dir) n++;
     }
   return n;
  }

//====================================================================
//  FILTERS / GUARDS
//====================================================================
bool EntryAllowed()
  {
   //--- spread
   if(InpMaxSpreadPts>0)
     {
      long spread=(long)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
      if(spread>InpMaxSpreadPts) return false;
     }
   //--- session
   if(!WithinSession()) return false;
   return true;
  }

bool WithinSession()
  {
   if(!InpUseTimeFilter) return true;
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   int cur   = t.hour*60 + t.min;
   int start = InpStartHour*60 + InpStartMin;
   int end   = InpEndHour*60   + InpEndMin;
   if(start==end) return true;                 // 0==0 / equal -> all day
   if(start<end)  return (cur>=start && cur<end);
   return (cur>=start || cur<end);             // wraps midnight
  }

//--- daily-loss guard bookkeeping
void UpdateDayAnchor(const bool force)
  {
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   datetime day = StringToTime(StringFormat("%04d.%02d.%02d",t.year,t.mon,t.day));
   if(force || day!=g_dayStamp)
     {
      g_dayStamp     = day;
      g_dayStartBal  = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dailyBlocked = false;
     }
  }

bool DailyLossHit()
  {
   if(!InpUseDailyLoss) return false;
   if(g_dayStartBal<=0.0) return false;
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double loss = g_dayStartBal - eq;
   return (loss >= g_dayStartBal*InpDailyLossPct/100.0);
  }

//====================================================================
//  SMALL UTILITIES
//====================================================================
bool NeedATR()
  {
   if(InpSLMode==SL_ATR) return true;
   if(InpTPMode==TP_ATR) return true;
   if(InpUseTrailing && InpTrailMode==TRAIL_ATR) return true;
   return false;
  }

bool GetATR(double &atrOut)
  {
   atrOut=0.0;
   if(hATR==INVALID_HANDLE) return false;
   if(BarsCalculated(hATR)<2) return false;
   double a[];
   ArraySetAsSeries(a,true);
   if(CopyBuffer(hATR,0,1,1,a)!=1) return false; // closed bar
   atrOut=a[0];
   return (atrOut>0.0);
  }

//--- pip size: 10*point on 3/5-digit symbols, else point
double PipSize()
  {
   int d=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   return ((d==3||d==5)?10.0:1.0)*pt;
  }

//--- broker minimum stop / freeze distance in price
double MinStopDistance()
  {
   long stops =SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double d=(double)MathMax(stops,freeze)*_Point;
   if(d<=0.0) d=_Point; // guarantee a non-zero guard
   return d;
  }

//--- lightweight status panel
void ShowPanel(const string note)
  {
   long spread=(long)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   int cS=-1,cC1=-1,cC2=-1;
   ReadColor(hSignal,1,cS);
   if(InpUseConf1) ReadColor(hConf1,1,cC1);
   if(InpUseConf2) ReadColor(hConf2,1,cC2);

   string txt="SMMA_TrendFlat_EA  ["+_Symbol+" "+EnumToString((ENUM_TIMEFRAMES)_Period)+"]\n";
   txt+="Signal trend : "+ColName(cS)+"\n";
   txt+="Confirm #1   : "+(InpUseConf1?(EnumToString(InpConf1TF)+" "+ColName(cC1)):"off")+"\n";
   txt+="Confirm #2   : "+(InpUseConf2?(EnumToString(InpConf2TF)+" "+ColName(cC2)):"off")+"\n";
   txt+="Open pos     : "+(string)CountPositions(POSITION_TYPE_BUY,true)+"   Spread: "+(string)spread+" pts\n";
   if(note!="") txt+=">> "+note+"\n";
   Comment(txt);
  }

string ColName(const int c)
  {
   if(c==COL_BULL)    return "BULL";
   if(c==COL_BEAR)    return "BEAR";
   if(c==COL_NEUTRAL) return "neutral";
   return "-";
  }
//+------------------------------------------------------------------+
