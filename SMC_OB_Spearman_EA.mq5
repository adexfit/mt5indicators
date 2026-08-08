//+------------------------------------------------------------------+
//|                                        SMC_OB_Spearman_EA.mq5     |
//|  Production EA trading the SMC Order Block indicator confirmed by |
//|  the Spearman Rank Correlation histogram.                        |
//|                                                                  |
//|  Signal logic:                                                   |
//|   * A BUY  is taken when a *bullish* order-block dot appears AND  |
//|     the Spearman value at the exact candle where the dot was     |
//|     placed is < 0.                                               |
//|   * A SELL is taken when a *bearish* order-block dot appears AND  |
//|     the Spearman value at the exact candle where the dot was     |
//|     placed is > 0.                                               |
//|                                                                  |
//|  The dot is drawn retroactively on the order-block candle but is |
//|  only KNOWN once price breaks the pivot ("break bar"); the EA    |
//|  therefore evaluates on closed bars and enters at the break bar, |
//|  while reading the Spearman gate at the dot's own candle index.  |
//+------------------------------------------------------------------+
#property copyright "SMC OB + Spearman EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//====================================================================
// ENUMS
//====================================================================
enum ENUM_OB_STREAM
  {
   OBSTREAM_INTERNAL = 0,   // Internal order blocks only
   OBSTREAM_SWING    = 1,   // Swing order blocks only
   OBSTREAM_BOTH     = 2    // Both internal + swing
  };

enum ENUM_LOT_MODE
  {
   LOT_FIXED    = 0,        // Fixed lot
   LOT_RISK_PCT = 1,        // Risk % of balance (needs a stop)
   LOT_MONEY    = 2         // Fixed money risk (needs a stop)
  };

enum ENUM_SL_MODE
  {
   SL_NONE   = 0,           // No stop loss
   SL_FIXED  = 1,           // Fixed points
   SL_ATR    = 2            // ATR based
  };

enum ENUM_TP_MODE
  {
   TP_NONE   = 0,           // No take profit
   TP_FIXED  = 1,           // Fixed points
   TP_RRR    = 2            // Risk:Reward multiple of stop distance
  };

//====================================================================
// INPUTS
//====================================================================
input group "=== Order Block Indicator (SMC_OrderBlocks) ==="
input string             InpOBName            = "SMC_OrderBlocks"; // OB indicator file name (in Indicators folder)
input ENUM_OB_STREAM     InpOBStream          = OBSTREAM_INTERNAL; // Which OB stream to trade
input bool               InpOB_ShowInternalOB = true;   // OB input: show internal OB
input bool               InpOB_ShowSwingOB    = false;  // OB input: show swing OB
input int                InpOB_OBFilter       = 0;      // OB input: filter (0=ATR,1=Range)
input int                InpOB_OBMitigation   = 1;      // OB input: mitigation (0=Close,1=HighLow)
input int                InpOB_InternalLength = 5;      // OB input: internal length
input int                InpOB_SwingLength    = 50;     // OB input: swing length
input int                InpOB_ATRPeriod      = 200;    // OB input: ATR period

input group "=== Spearman Indicator ==="
input string             InpSpName            = "spearman-rank-correlation-histogram"; // Spearman file name
input int                InpSp_rangeN         = 14;     // Spearman: rangeN
input int                InpSp_CalculatedBars = 0;      // Spearman: CalculatedBars
input int                InpSp_Maxrange       = 30;     // Spearman: Maxrange
input bool               InpSp_direction      = true;   // Spearman: direction
input double             InpSp_inHighLevel    = 0.8;    // Spearman: high level
input double             InpSp_inLowLevel     = -0.8;   // Spearman: low level
input ENUM_APPLIED_PRICE InpSp_AppliedPrice   = PRICE_CLOSE; // Spearman: applied price

input group "=== Signal ==="
input int                InpMaxDotAgeBars     = 30;     // Ignore dots whose break bar is older than N bars
input int                InpScanBars          = 300;    // How many closed bars to scan for dots

input group "=== Money Management: Lots ==="
input ENUM_LOT_MODE      InpLotMode           = LOT_FIXED; // Lot sizing mode
input double             InpFixedLot          = 0.10;   // Fixed lot size
input double             InpRiskPercent       = 1.0;    // Risk % of balance (RISK_PCT mode)
input double             InpMoneyRisk         = 100.0;  // Money risk per trade (MONEY mode)

input group "=== Stop Loss ==="
input ENUM_SL_MODE       InpSLMode            = SL_ATR; // Stop loss mode
input int                InpSLFixedPoints     = 300;    // Fixed SL (points)
input int                InpSL_ATRPeriod      = 14;     // ATR period for SL
input double             InpSL_ATRMult        = 1.5;    // ATR multiplier for SL

input group "=== Take Profit ==="
input ENUM_TP_MODE       InpTPMode            = TP_RRR; // Take profit mode
input int                InpTPFixedPoints     = 600;    // Fixed TP (points)
input double             InpTP_RRR            = 2.0;    // Reward:Risk ratio (RRR mode)

input group "=== Break Even ==="
input bool               InpUseBreakEven      = true;   // Enable break-even
input int                InpBE_TriggerPoints  = 200;    // Profit (points) to trigger BE
input int                InpBE_OffsetPoints   = 20;     // BE offset (points, locked profit)

input group "=== Trailing Stop ==="
input bool               InpUseTrailing       = true;   // Enable trailing stop
input int                InpTrailStartPoints  = 250;    // Profit (points) to start trailing
input int                InpTrailDistPoints   = 200;    // Trailing distance (points)
input int                InpTrailStepPoints   = 20;     // Trailing step (points)

input group "=== Partial Take Profit ==="
input bool               InpUsePartial        = false;  // Enable partial TP
input int                InpPartialTrigPoints = 250;    // Profit (points) to take partial
input double             InpPartialPercent    = 50.0;   // % of position to close
input bool               InpPartialThenBE     = true;   // Move remainder to BE after partial

input group "=== Filters ==="
input bool               InpUseSession        = true;   // Enable session filter
input int                InpSessionStartHour  = 7;      // Session start hour (server time)
input int                InpSessionEndHour    = 20;     // Session end hour (server time)
input bool               InpUseSpreadFilter   = false;  // Enable spread filter (OFF by default)
input int                InpMaxSpreadPoints   = 30;     // Max spread (points)
input int                InpMaxTradesPerDay   = 5;      // Max trades per day (0 = unlimited)

input group "=== Misc ==="
input long               InpMagic             = 990011; // Magic number
input int                InpSlippagePoints    = 20;     // Max deviation / slippage (points)
input string             InpTradeComment      = "SMC_OB_Sp"; // Order comment

//====================================================================
// GLOBALS
//====================================================================
CTrade         g_trade;
CPositionInfo  g_pos;
CSymbolInfo    g_sym;

int      g_obHandle    = INVALID_HANDLE;
int      g_spHandle    = INVALID_HANDLE;
int      g_slAtrHandle = INVALID_HANDLE;

datetime g_lastBarTime = 0;    // new-bar detector
datetime g_lastSignalDotTime = 0; // guards against duplicate entry on same dot

// trades-per-day tracking
int      g_tradesToday = 0;
int      g_dayOfYear   = -1;

// partial-TP bookkeeping (per open position ticket)
ulong    g_partialDoneTicket = 0;

// OB indicator buffer indices (must match SMC_OrderBlocks.mq5 plot order)
#define OB_BUF_INT_BULL   0
#define OB_BUF_INT_BEAR   1
#define OB_BUF_SW_BULL    4
#define OB_BUF_SW_BEAR    5

//====================================================================
// INIT
//====================================================================
int OnInit()
  {
   if(!g_sym.Name(_Symbol))
     {
      Print("Failed to init symbol info");
      return(INIT_FAILED);
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);

   //--- Order Block indicator: parameters must match SMC_OrderBlocks.mq5 input order
   g_obHandle = iCustom(_Symbol,_Period,InpOBName,
                        InpOB_ShowInternalOB,
                        InpOB_ShowSwingOB,
                        InpOB_OBFilter,
                        InpOB_OBMitigation,
                        InpOB_InternalLength,
                        InpOB_SwingLength,
                        InpOB_ATRPeriod);
   if(g_obHandle==INVALID_HANDLE)
     {
      Print("Failed to create OB indicator handle. Check that '",InpOBName,".ex5' is in the Indicators folder.");
      return(INIT_FAILED);
     }

   //--- Spearman indicator: it is a single-price indicator, so the applied price
   //    is passed as the LAST parameter after its own inputs.
   g_spHandle = iCustom(_Symbol,_Period,InpSpName,
                        InpSp_rangeN,
                        InpSp_CalculatedBars,
                        InpSp_Maxrange,
                        InpSp_direction,
                        InpSp_inHighLevel,
                        InpSp_inLowLevel,
                        InpSp_AppliedPrice);
   if(g_spHandle==INVALID_HANDLE)
     {
      Print("Failed to create Spearman indicator handle. Check that '",InpSpName,".ex5' is in the Indicators folder.");
      return(INIT_FAILED);
     }

   //--- ATR handle for SL (only if needed)
   if(InpSLMode==SL_ATR)
     {
      g_slAtrHandle = iATR(_Symbol,_Period,InpSL_ATRPeriod);
      if(g_slAtrHandle==INVALID_HANDLE)
        {
         Print("Failed to create ATR handle for SL");
         return(INIT_FAILED);
        }
     }

   //--- validate inputs that could produce nonsense
   if((InpLotMode==LOT_RISK_PCT || InpLotMode==LOT_MONEY) && InpSLMode==SL_NONE)
      Print("WARNING: Risk-based lot sizing requires a stop loss. Falling back to fixed lot when SL is None.");

   ResetDailyCounterIfNeeded();

   Print("SMC_OB_Spearman_EA initialised on ",_Symbol," ",EnumToString((ENUM_TIMEFRAMES)_Period));
   return(INIT_SUCCEEDED);
  }

//====================================================================
// DEINIT
//====================================================================
void OnDeinit(const int reason)
  {
   if(g_obHandle!=INVALID_HANDLE)    IndicatorRelease(g_obHandle);
   if(g_spHandle!=INVALID_HANDLE)    IndicatorRelease(g_spHandle);
   if(g_slAtrHandle!=INVALID_HANDLE) IndicatorRelease(g_slAtrHandle);
  }

//====================================================================
// NEW BAR DETECTOR
//====================================================================
bool IsNewBar()
  {
   datetime t = iTime(_Symbol,_Period,0);
   if(t==0) return false;
   if(t!=g_lastBarTime)
     {
      g_lastBarTime=t;
      return true;
     }
   return false;
  }

//====================================================================
// DAILY TRADE COUNTER
//====================================================================
void ResetDailyCounterIfNeeded()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   if(dt.day_of_year!=g_dayOfYear)
     {
      g_dayOfYear   = dt.day_of_year;
      g_tradesToday = 0;
     }
  }

//====================================================================
// FILTERS
//====================================================================
bool SessionOK()
  {
   if(!InpUseSession) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   int h=dt.hour;
   if(InpSessionStartHour<=InpSessionEndHour)
      return (h>=InpSessionStartHour && h<InpSessionEndHour);
   // wrap-around session (e.g. 22 -> 6)
   return (h>=InpSessionStartHour || h<InpSessionEndHour);
  }

bool SpreadOK()
  {
   if(!InpUseSpreadFilter) return true;
   long spread = SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   return (spread<=InpMaxSpreadPoints);
  }

bool TradesPerDayOK()
  {
   if(InpMaxTradesPerDay<=0) return true;
   return (g_tradesToday<InpMaxTradesPerDay);
  }

//====================================================================
// POSITION HELPERS
//====================================================================
bool HasOpenPosition()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
         PositionGetInteger(POSITION_MAGIC)==InpMagic)
         return true;
     }
   return false;
  }

// Returns true and fills refs if our position is open on this symbol
bool GetOurPosition(ulong &ticket,long &type,double &volume,double &entry,double &sl,double &tp)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
         PositionGetInteger(POSITION_MAGIC)==InpMagic)
        {
         ticket=t;
         type  =PositionGetInteger(POSITION_TYPE);
         volume=PositionGetDouble(POSITION_VOLUME);
         entry =PositionGetDouble(POSITION_PRICE_OPEN);
         sl    =PositionGetDouble(POSITION_SL);
         tp    =PositionGetDouble(POSITION_TP);
         return true;
        }
     }
   return false;
  }

//====================================================================
// SIGNAL DETECTION
//   Scans closed bars (shift 1..InpScanBars) for a freshly-confirmed OB dot.
//   A dot is a non-empty value in the corresponding OB buffer at index d.
//   We read the Spearman buffer 0 at that SAME index d for the gate.
//   Direction: +1 buy, -1 sell, 0 none. Also returns the dot's bar time.
//====================================================================
int DetectSignal(datetime &dotTime)
  {
   dotTime=0;

   int scan = InpScanBars;
   int bars = Bars(_Symbol,_Period);
   if(scan > bars-2) scan = bars-2;
   if(scan < 2)      return 0;

   // Pull Spearman buffer once (aligned as series: index 0 = current bar)
   double sp[];
   if(CopyBuffer(g_spHandle,0,0,scan+2,sp)<=0) return 0;
   ArraySetAsSeries(sp,true);

   // Helper macro-like reads via lambda-ish inline: we copy each OB buffer we need.
   // Buffers to scan depend on the chosen stream.
   bool useInt = (InpOBStream==OBSTREAM_INTERNAL || InpOBStream==OBSTREAM_BOTH);
   bool useSw  = (InpOBStream==OBSTREAM_SWING    || InpOBStream==OBSTREAM_BOTH);

   double intBull[],intBear[],swBull[],swBear[];
   if(useInt)
     {
      if(CopyBuffer(g_obHandle,OB_BUF_INT_BULL,0,scan+2,intBull)<=0) return 0;
      if(CopyBuffer(g_obHandle,OB_BUF_INT_BEAR,0,scan+2,intBear)<=0) return 0;
      ArraySetAsSeries(intBull,true);
      ArraySetAsSeries(intBear,true);
     }
   if(useSw)
     {
      if(CopyBuffer(g_obHandle,OB_BUF_SW_BULL,0,scan+2,swBull)<=0) return 0;
      if(CopyBuffer(g_obHandle,OB_BUF_SW_BEAR,0,scan+2,swBear)<=0) return 0;
      ArraySetAsSeries(swBull,true);
      ArraySetAsSeries(swBear,true);
     }

   // Walk from the most recent CLOSED bar (shift 1) back into history.
   // The first (newest) qualifying, not-yet-traded dot wins.
   for(int d=1; d<=scan; d++)
     {
      if(d>=InpMaxDotAgeBars+1) break;   // dot too old to act on

      datetime bt = iTime(_Symbol,_Period,d);
      if(bt==0) continue;
      if(bt==g_lastSignalDotTime) return 0; // already handled this or newer dot

      double spVal = sp[d];
      if(spVal==EMPTY_VALUE) continue;

      bool bull=false, bear=false;
      if(useInt)
        {
         if(intBull[d]!=EMPTY_VALUE && intBull[d]!=0.0) bull=true;
         if(intBear[d]!=EMPTY_VALUE && intBear[d]!=0.0) bear=true;
        }
      if(useSw)
        {
         if(swBull[d]!=EMPTY_VALUE && swBull[d]!=0.0) bull=true;
         if(swBear[d]!=EMPTY_VALUE && swBear[d]!=0.0) bear=true;
        }

      if(!bull && !bear) continue;

      // Apply the Spearman gate read at the dot's own candle index d.
      if(bull && spVal<0.0){ dotTime=bt; return +1; }
      if(bear && spVal>0.0){ dotTime=bt; return -1; }

      // A dot existed here but the gate failed -> this dot is spent; stop so we
      // don't reach further back and re-open on stale structure.
      return 0;
     }
   return 0;
  }

//====================================================================
// STOP / TAKE PROFIT CALCULATION
//   Returns SL and TP prices (0.0 = none). direction: +1 buy, -1 sell.
//====================================================================
double CurrentATR()
  {
   if(g_slAtrHandle==INVALID_HANDLE) return 0.0;
   double a[];
   if(CopyBuffer(g_slAtrHandle,0,0,2,a)<=0) return 0.0;
   return a[0];
  }

void ComputeSLTP(int dir,double entry,double &slPrice,double &tpPrice,double &slDistPrice)
  {
   double point = _Point;
   slPrice=0.0; tpPrice=0.0; slDistPrice=0.0;

   //--- STOP LOSS
   if(InpSLMode==SL_FIXED)
      slDistPrice = InpSLFixedPoints*point;
   else if(InpSLMode==SL_ATR)
      slDistPrice = CurrentATR()*InpSL_ATRMult;

   if(InpSLMode!=SL_NONE && slDistPrice>0.0)
     {
      if(dir>0) slPrice = entry - slDistPrice;
      else      slPrice = entry + slDistPrice;
     }

   //--- TAKE PROFIT
   double tpDistPrice=0.0;
   if(InpTPMode==TP_FIXED)
      tpDistPrice = InpTPFixedPoints*point;
   else if(InpTPMode==TP_RRR)
     {
      if(slDistPrice>0.0) tpDistPrice = slDistPrice*InpTP_RRR;
      // If no stop distance available, RRR TP cannot be computed -> leave as none.
     }

   if(InpTPMode!=TP_NONE && tpDistPrice>0.0)
     {
      if(dir>0) tpPrice = entry + tpDistPrice;
      else      tpPrice = entry - tpDistPrice;
     }
  }

//====================================================================
// LOT SIZING
//====================================================================
double NormalizeVolume(double vol)
  {
   double minV = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0) step=0.01;
   vol = MathRound(vol/step)*step;
   if(vol<minV) vol=minV;
   if(vol>maxV) vol=maxV;
   return NormalizeDouble(vol,2);
  }

double ComputeLot(double slDistPrice)
  {
   // Fixed lot, or risk-based when a stop distance is available.
   if(InpLotMode==LOT_FIXED || slDistPrice<=0.0)
      return NormalizeVolume(InpFixedLot);

   double tickValue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickValue<=0 || tickSize<=0)
      return NormalizeVolume(InpFixedLot);

   double slTicks   = slDistPrice/tickSize;
   double lossPerLot= slTicks*tickValue;   // account currency loss for 1.0 lot
   if(lossPerLot<=0.0)
      return NormalizeVolume(InpFixedLot);

   double riskMoney;
   if(InpLotMode==LOT_RISK_PCT)
      riskMoney = AccountInfoDouble(ACCOUNT_BALANCE)*InpRiskPercent/100.0;
   else // LOT_MONEY
      riskMoney = InpMoneyRisk;

   double lot = riskMoney/lossPerLot;
   return NormalizeVolume(lot);
  }

//====================================================================
// MARGIN CHECK
//====================================================================
bool MarginOK(int dir,double lot,double price)
  {
   double margin=0.0;
   ENUM_ORDER_TYPE ot = (dir>0)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcMargin(ot,_Symbol,lot,price,margin))
      return false;
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   return (margin<=freeMargin);
  }

//====================================================================
// STOP-LEVEL SANITISER
//   Ensures SL/TP respect the broker's minimum stops distance.
//====================================================================
void RespectStops(int dir,double price,double &sl,double &tp)
  {
   long stopsLevel = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double minDist  = stopsLevel*_Point;
   if(minDist<=0) return;

   if(sl>0.0)
     {
      if(dir>0 && (price-sl)<minDist) sl=price-minDist;
      if(dir<0 && (sl-price)<minDist) sl=price+minDist;
     }
   if(tp>0.0)
     {
      if(dir>0 && (tp-price)<minDist) tp=price+minDist;
      if(dir<0 && (price-tp)<minDist) tp=price-minDist;
     }
   sl = (sl>0.0)?NormalizeDouble(sl,_Digits):0.0;
   tp = (tp>0.0)?NormalizeDouble(tp,_Digits):0.0;
  }

//====================================================================
// OPEN TRADE
//====================================================================
bool OpenTrade(int dir)
  {
   g_sym.RefreshRates();
   double price = (dir>0)?g_sym.Ask():g_sym.Bid();
   if(price<=0.0) return false;

   double sl,tp,slDist;
   ComputeSLTP(dir,price,sl,tp,slDist);
   RespectStops(dir,price,sl,tp);

   double lot = ComputeLot(slDist);
   if(lot<=0.0){ Print("Computed lot <= 0, abort"); return false; }

   if(!MarginOK(dir,lot,price))
     {
      Print("Not enough free margin for ",lot," lots. Abort.");
      return false;
     }

   bool ok;
   if(dir>0) ok=g_trade.Buy (lot,_Symbol,price,sl,tp,InpTradeComment);
   else      ok=g_trade.Sell(lot,_Symbol,price,sl,tp,InpTradeComment);

   if(ok)
     {
      g_tradesToday++;
      g_partialDoneTicket=0; // reset partial flag for the new position
      PrintFormat("%s opened: lot=%.2f price=%.5f sl=%.5f tp=%.5f",
                  (dir>0?"BUY":"SELL"),lot,price,sl,tp);
     }
   else
      PrintFormat("Order send failed: retcode=%d %s",g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());

   return ok;
  }

//====================================================================
// TRADE MANAGEMENT (per tick, on open position)
//====================================================================
void ManageBreakEven(ulong ticket,long type,double entry,double sl)
  {
   if(!InpUseBreakEven) return;
   g_sym.RefreshRates();
   double point=_Point;

   if(type==POSITION_TYPE_BUY)
     {
      double profitPts=(g_sym.Bid()-entry)/point;
      if(profitPts>=InpBE_TriggerPoints)
        {
         double newSL=NormalizeDouble(entry+InpBE_OffsetPoints*point,_Digits);
         if(sl<newSL-point*0.5) // only move up, avoid redundant modify
            ModifySL(ticket,newSL);
        }
     }
   else if(type==POSITION_TYPE_SELL)
     {
      double profitPts=(entry-g_sym.Ask())/point;
      if(profitPts>=InpBE_TriggerPoints)
        {
         double newSL=NormalizeDouble(entry-InpBE_OffsetPoints*point,_Digits);
         if(sl>newSL+point*0.5 || sl==0.0)
            ModifySL(ticket,newSL);
        }
     }
  }

void ManageTrailing(ulong ticket,long type,double sl)
  {
   if(!InpUseTrailing) return;
   g_sym.RefreshRates();
   double point=_Point;
   double entry=PositionGetDouble(POSITION_PRICE_OPEN);

   if(type==POSITION_TYPE_BUY)
     {
      double profitPts=(g_sym.Bid()-entry)/point;
      if(profitPts<InpTrailStartPoints) return;
      double newSL=NormalizeDouble(g_sym.Bid()-InpTrailDistPoints*point,_Digits);
      if(newSL>sl+InpTrailStepPoints*point)
         ModifySL(ticket,newSL);
     }
   else if(type==POSITION_TYPE_SELL)
     {
      double profitPts=(entry-g_sym.Ask())/point;
      if(profitPts<InpTrailStartPoints) return;
      double newSL=NormalizeDouble(g_sym.Ask()+InpTrailDistPoints*point,_Digits);
      if(sl==0.0 || newSL<sl-InpTrailStepPoints*point)
         ModifySL(ticket,newSL);
     }
  }

void ManagePartial(ulong ticket,long type,double volume,double entry,double sl)
  {
   if(!InpUsePartial) return;
   if(g_partialDoneTicket==ticket) return; // already taken partial on this position
   g_sym.RefreshRates();
   double point=_Point;

   double profitPts;
   if(type==POSITION_TYPE_BUY) profitPts=(g_sym.Bid()-entry)/point;
   else                        profitPts=(entry-g_sym.Ask())/point;

   if(profitPts<InpPartialTrigPoints) return;

   double closeVol=NormalizeVolume(volume*InpPartialPercent/100.0);
   double minV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(closeVol<minV) return;                 // too small to close partially
   if(closeVol>=volume) return;              // would close everything; skip

   if(g_trade.PositionClosePartial(ticket,closeVol))
     {
      g_partialDoneTicket=ticket;
      PrintFormat("Partial close %.2f lots on ticket %I64u",closeVol,ticket);

      if(InpPartialThenBE)
        {
         double newSL = (type==POSITION_TYPE_BUY)
                        ? NormalizeDouble(entry+InpBE_OffsetPoints*point,_Digits)
                        : NormalizeDouble(entry-InpBE_OffsetPoints*point,_Digits);
         ModifySL(ticket,newSL);
        }
     }
  }

//--- SL/TP modify helper (keeps TP intact)
void ModifySL(ulong ticket,double newSL)
  {
   if(!PositionSelectByTicket(ticket)) return;
   double tp = PositionGetDouble(POSITION_TP);
   long   type = PositionGetInteger(POSITION_TYPE);
   double price = (type==POSITION_TYPE_BUY)?g_sym.Bid():g_sym.Ask();

   // respect broker stops level before sending
   int dir = (type==POSITION_TYPE_BUY)?1:-1;
   double slAdj=newSL, tpAdj=tp;
   RespectStops(dir,price,slAdj,tpAdj);

   if(!g_trade.PositionModify(ticket,slAdj,tp))
     {
      // Non-fatal: broker may reject if inside freeze level; will retry next tick.
     }
  }

void ManageOpenPosition()
  {
   ulong ticket; long type; double volume,entry,sl,tp;
   if(!GetOurPosition(ticket,type,volume,entry,sl,tp)) return;

   // Order matters: partial first (may move to BE), then BE, then trailing.
   ManagePartial(ticket,type,volume,entry,sl);

   // refresh sl after possible partial-driven modify
   if(PositionSelectByTicket(ticket)) sl=PositionGetDouble(POSITION_SL);
   ManageBreakEven(ticket,type,entry,sl);

   if(PositionSelectByTicket(ticket)) sl=PositionGetDouble(POSITION_SL);
   ManageTrailing(ticket,type,sl);
  }

//====================================================================
// MAIN TICK
//====================================================================
void OnTick()
  {
   // Manage any open position on every tick for responsive stops.
   if(HasOpenPosition())
      ManageOpenPosition();

   // Signal evaluation only on a new (closed) bar.
   if(!IsNewBar())
      return;

   ResetDailyCounterIfNeeded();

   // Single position, no stacking: if we already hold one, do nothing more.
   if(HasOpenPosition())
      return;

   // Filters
   if(!SessionOK())      return;
   if(!SpreadOK())       return;
   if(!TradesPerDayOK()) return;

   datetime dotTime=0;
   int sig = DetectSignal(dotTime);
   if(sig==0) return;

   // Guard: don't re-fire on the same dot.
   if(dotTime==g_lastSignalDotTime) return;
   g_lastSignalDotTime = dotTime;

   OpenTrade(sig);
  }
//+------------------------------------------------------------------+
