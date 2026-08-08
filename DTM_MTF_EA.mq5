//+------------------------------------------------------------------+
//|                                        DTM_MTF_EA.mq5             |
//|  Production EA meant to run on an M1 chart. It creates two        |
//|  instances of the multi-timeframe DynamicTrendMatrixMTF indicator,|
//|  BOTH bound to the M1 chart, each told to resample a different    |
//|  timeframe internally via the indicator's InpTimeframe input:     |
//|    * Trend instance  -> InpTimeframe = M15 (default)              |
//|    * Signal instance -> InpTimeframe = M5  (default)              |
//|                                                                  |
//|  A BUY is generated when the trend instance's TrendState is bull |
//|  (+1) AND the signal instance's LongSignal flips to 1 on the     |
//|  just-closed M5 bar. Mirror logic for SELL.                      |
//|                                                                  |
//|  Because both handles are bound to the M1 chart, their buffers   |
//|  are indexed by M1 bars: the indicator maps each higher-TF bar's |
//|  value onto every M1 bar inside it. The EA therefore reads each  |
//|  buffer at the M1 bar that falls inside the last CLOSED M15/M5   |
//|  bar (see ReadDTM). The indicator is non-repainting when         |
//|  Confirm-On-Close is true.                                       |
//|                                                                  |
//|  SL/TP can be taken from the DTM indicator itself (Trail / ATR   |
//|  band + TP1/TP2/TP3 levels) OR computed independently            |
//|  (None/Fixed/ATR stop, None/Fixed/RRR target). Production trade  |
//|  management: break-even, trailing, partial-TP+BE, session/spread |
//|  /trades-per-day filters, multiple lot-sizing modes.             |
//+------------------------------------------------------------------+
#property copyright "DTM MTF EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//====================================================================
// DTM indicator buffer indices (must match DynamicTrendMatrixMTF.mq5)
//====================================================================
#define DTM_BUF_TRENDSTATE   10
#define DTM_BUF_LONGSIGNAL   14
#define DTM_BUF_SHORTSIGNAL  15
#define DTM_BUF_ATR          16
#define DTM_BUF_TP1          17
#define DTM_BUF_TP2          18
#define DTM_BUF_TP3          19
#define DTM_BUF_TRAIL        6

//====================================================================
// ENUMS
//====================================================================
enum ENUM_SLTP_SOURCE
  {
   SLTP_INDEPENDENT = 0,    // Independent (ATR/RRR/Fixed) modes below
   SLTP_DTM_NATIVE  = 1     // Use DTM Trail (SL) + TP1/2/3 levels (TP)
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
   SL_ATR    = 2            // ATR based (EA's own iATR)
  };

enum ENUM_TP_MODE
  {
   TP_NONE   = 0,           // No take profit
   TP_FIXED  = 1,           // Fixed points
   TP_RRR    = 2            // Risk:Reward multiple of stop distance
  };

enum ENUM_DTM_TP_PICK
  {
   DTMTP_TP1 = 0,           // Use TP1 level
   DTMTP_TP2 = 1,           // Use TP2 level
   DTMTP_TP3 = 2            // Use TP3 level
  };

//====================================================================
// INPUTS
//====================================================================
input group "=== DTM Indicator (shared params for both instances) ==="
input string             InpDTMName        = "DynamicTrendMatrixMTF"; // DTM indicator file name
input ENUM_TIMEFRAMES    InpTrendTF        = PERIOD_M15;  // Trend instance timeframe (indicator InpTimeframe)
input ENUM_TIMEFRAMES    InpSignalTF       = PERIOD_M5;   // Signal instance timeframe (indicator InpTimeframe)
input ENUM_APPLIED_PRICE InpDTM_Source     = PRICE_CLOSE; // DTM: Source
input int                InpDTM_FastLen     = 8;          // DTM: Fast Length
input int                InpDTM_BaseLen     = 21;         // DTM: Base Length
input int                InpDTM_SlowLen     = 55;         // DTM: Slow Length
input int                InpDTM_SlopeLen    = 5;          // DTM: Slope Length
input int                InpDTM_SmoothLen   = 3;          // DTM: Smoothing
input int                InpDTM_AtrLen      = 10;         // DTM: ATR Length
input double             InpDTM_AtrMult     = 2.0;        // DTM: ATR Multiplier
input bool               InpDTM_ConfirmClose= true;       // DTM: Confirm Signals On Bar Close
input int                InpDTM_TPModeInt   = 0;          // DTM: TP Calc (0=RiskFromTrail,1=ATRFromEntry)
input int                InpDTM_TPCount     = 3;          // DTM: TP Count (1..3)
input double             InpDTM_TP1Mult     = 1.0;        // DTM: TP1 Multiplier
input double             InpDTM_TP2Mult     = 2.0;        // DTM: TP2 Multiplier
input double             InpDTM_TP3Mult     = 3.0;        // DTM: TP3 Multiplier

input group "=== Signal ==="
input bool               InpRequireFlip     = true;       // Require signal flip on just-closed bar
input bool               InpRequireTrendState = true;     // Also require signal-TF trend agrees with entry
input bool               InpCloseOnOppositeFlip = false;  // Close open trade on an opposite signal flip

input group "=== SL / TP source ==="
input ENUM_SLTP_SOURCE   InpSLTPSource      = SLTP_INDEPENDENT; // Where SL/TP come from
input ENUM_DTM_TP_PICK   InpDTMTPPick       = DTMTP_TP2;   // Which DTM TP level to use (native mode)
input double             InpDTM_SLBufferPts = 20;          // Extra SL buffer beyond Trail (points, native mode)

input group "=== Independent Stop Loss ==="
input ENUM_SL_MODE       InpSLMode          = SL_ATR;     // Stop loss mode (independent)
input int                InpSLFixedPoints   = 300;        // Fixed SL (points)
input int                InpSL_ATRPeriod    = 14;         // ATR period for SL
input double             InpSL_ATRMult      = 1.5;        // ATR multiplier for SL

input group "=== Independent Take Profit ==="
input ENUM_TP_MODE       InpTPMode          = TP_RRR;     // Take profit mode (independent)
input int                InpTPFixedPoints   = 600;        // Fixed TP (points)
input double             InpTP_RRR          = 2.0;        // Reward:Risk ratio (RRR mode)

input group "=== Money Management: Lots ==="
input ENUM_LOT_MODE      InpLotMode         = LOT_FIXED;  // Lot sizing mode
input double             InpFixedLot        = 0.10;       // Fixed lot size
input double             InpRiskPercent     = 1.0;        // Risk % of balance (RISK_PCT mode)
input double             InpMoneyRisk       = 100.0;      // Money risk per trade (MONEY mode)

input group "=== Break Even ==="
input bool               InpUseBreakEven    = true;       // Enable break-even
input int                InpBE_TriggerPoints= 200;        // Profit (points) to trigger BE
input int                InpBE_OffsetPoints = 20;         // BE offset (points, locked profit)

input group "=== Trailing Stop ==="
input bool               InpUseTrailing     = true;       // Enable trailing stop
input int                InpTrailStartPoints= 250;        // Profit (points) to start trailing
input int                InpTrailDistPoints = 200;        // Trailing distance (points)
input int                InpTrailStepPoints = 20;         // Trailing step (points)

input group "=== Partial Take Profit ==="
input bool               InpUsePartial      = false;      // Enable partial TP
input int                InpPartialTrigPoints= 250;       // Profit (points) to take partial
input double             InpPartialPercent  = 50.0;       // % of position to close
input bool               InpPartialThenBE   = true;       // Move remainder to BE after partial

input group "=== Filters ==="
input bool               InpUseSession      = true;       // Enable session filter
input int                InpSessionStartHour= 7;          // Session start hour (server time)
input int                InpSessionEndHour  = 20;         // Session end hour (server time)
input bool               InpUseSpreadFilter = false;      // Enable spread filter (OFF by default)
input int                InpMaxSpreadPoints = 30;         // Max spread (points)
input int                InpMaxTradesPerDay = 5;          // Max trades per day (0 = unlimited)

input group "=== Misc ==="
input long               InpMagic           = 990022;     // Magic number
input int                InpSlippagePoints  = 20;         // Max deviation / slippage (points)
input string             InpTradeComment    = "DTM_MTF";  // Order comment

//====================================================================
// GLOBALS
//====================================================================
CTrade         g_trade;
CPositionInfo  g_pos;
CSymbolInfo    g_sym;

int      g_trendHandle = INVALID_HANDLE;
int      g_signalHandle= INVALID_HANDLE;
int      g_slAtrHandle = INVALID_HANDLE;

datetime g_lastSignalBarTime = 0; // new-bar detector on the SIGNAL timeframe
datetime g_lastTradedBarTime = 0; // guards duplicate entry on same signal bar

int      g_tradesToday = 0;
int      g_dayOfYear   = -1;
ulong    g_partialDoneTicket = 0;

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

   // Both instances are bound to the CURRENT (M1) chart; each is told to
   // internally resample its target timeframe via the indicator's InpTimeframe.
   g_trendHandle = CreateDTM(InpTrendTF);
   if(g_trendHandle==INVALID_HANDLE)
     {
      Print("Failed to create TREND DTM handle. Check '",InpDTMName,".ex5' is in the Indicators folder.");
      return(INIT_FAILED);
     }

   g_signalHandle = CreateDTM(InpSignalTF);
   if(g_signalHandle==INVALID_HANDLE)
     {
      Print("Failed to create SIGNAL DTM handle.");
      return(INIT_FAILED);
     }

   if(InpSLTPSource==SLTP_INDEPENDENT && InpSLMode==SL_ATR)
     {
      g_slAtrHandle = iATR(_Symbol,_Period,InpSL_ATRPeriod);
      if(g_slAtrHandle==INVALID_HANDLE)
        {
         Print("Failed to create ATR handle for SL");
         return(INIT_FAILED);
        }
     }

   if((InpLotMode==LOT_RISK_PCT || InpLotMode==LOT_MONEY) &&
      InpSLTPSource==SLTP_INDEPENDENT && InpSLMode==SL_NONE)
      Print("WARNING: Risk-based lot sizing needs a stop. Will fall back to fixed lot when SL distance is 0.");

   ResetDailyCounterIfNeeded();
   Print("DTM_MTF_EA initialised. Trend TF=",EnumToString(InpTrendTF),
         " Signal TF=",EnumToString(InpSignalTF));
   return(INIT_SUCCEEDED);
  }

// Build a DTM iCustom handle bound to the CURRENT (M1) chart, telling the
// indicator to internally resample the given timeframe via its InpTimeframe
// input. Parameter order MUST match DynamicTrendMatrixMTF.mq5 input order.
int CreateDTM(ENUM_TIMEFRAMES resampleTF)
  {
   return iCustom(_Symbol,_Period,InpDTMName,
                  resampleTF,              // InpTimeframe: indicator resamples this TF onto the M1 chart
                  InpDTM_Source,
                  InpDTM_FastLen,
                  InpDTM_BaseLen,
                  InpDTM_SlowLen,
                  InpDTM_SlopeLen,
                  InpDTM_SmoothLen,
                  InpDTM_AtrLen,
                  InpDTM_AtrMult,
                  InpDTM_ConfirmClose,
                  InpDTM_TPModeInt,
                  InpDTM_TPCount,
                  InpDTM_TP1Mult,
                  InpDTM_TP2Mult,
                  InpDTM_TP3Mult,
                  false,   // InpShowBands
                  false,   // InpShowOuter
                  true,    // InpShowTrail
                  true);   // InpShowArrows
  }

//====================================================================
// DEINIT
//====================================================================
void OnDeinit(const int reason)
  {
   if(g_trendHandle !=INVALID_HANDLE) IndicatorRelease(g_trendHandle);
   if(g_signalHandle!=INVALID_HANDLE) IndicatorRelease(g_signalHandle);
   if(g_slAtrHandle !=INVALID_HANDLE) IndicatorRelease(g_slAtrHandle);
  }

//====================================================================
// NEW BAR ON SIGNAL TIMEFRAME
//====================================================================
bool IsNewSignalBar()
  {
   datetime t = iTime(_Symbol,InpSignalTF,0);
   if(t==0) return false;
   if(t!=g_lastSignalBarTime)
     {
      g_lastSignalBarTime=t;
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
   return (h>=InpSessionStartHour || h<InpSessionEndHour); // wrap-around
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
// INDICATOR READ HELPERS
//   Both DTM handles are bound to the M1 chart, so their buffers are
//   indexed by M1 bars: the indicator stamps each higher-TF bar's value
//   onto every M1 bar that falls inside it. To read the value "as of the
//   last CLOSED bar of timeframe tf", we locate an M1 bar that lies inside
//   that closed HTF bar and read there.
//====================================================================

// M1 shift of a bar lying inside the last CLOSED bar of timeframe tf.
// Returns -1 if history is not ready. We use the OPEN time of the last
// closed HTF bar (iTime(tf,1)) and map it to an M1 bar via iBarShift.
int ClosedTFShiftM1(ENUM_TIMEFRAMES tf)
  {
   datetime htfOpen = iTime(_Symbol,tf,1);   // open time of last closed HTF bar
   if(htfOpen==0) return -1;
   int sh = iBarShift(_Symbol,_Period,htfOpen,false); // M1 bar at/after that time
   if(sh<0) return -1;
   return sh;
  }

// Read one value from a DTM handle's buffer at the given M1 shift.
bool ReadBuf(int handle,int buf,int shift,double &out)
  {
   if(shift<0) return false;
   double tmp[];
   if(CopyBuffer(handle,buf,shift,1,tmp)<=0) return false;
   out=tmp[0];
   return true;
  }

// Read a DTM buffer as of the last CLOSED bar of timeframe tf.
bool ReadDTM(int handle,int buf,ENUM_TIMEFRAMES tf,double &out)
  {
   int sh = ClosedTFShiftM1(tf);
   if(sh<0) return false;
   return ReadBuf(handle,buf,sh,out);
  }

//====================================================================
// SIGNAL DETECTION
//   +1 buy, -1 sell, 0 none. Evaluated once per new M5 bar. Signal
//   values are read as of the last CLOSED M5 bar; the trend gate as of
//   the last CLOSED M15 bar (both mapped from M1 buffers via ReadDTM).
//====================================================================
int DetectSignal()
  {
   // --- Signal-TF flip on the last closed M5 bar ---
   double longSig=0, shortSig=0;
   if(!ReadDTM(g_signalHandle,DTM_BUF_LONGSIGNAL ,InpSignalTF,longSig))  return 0;
   if(!ReadDTM(g_signalHandle,DTM_BUF_SHORTSIGNAL,InpSignalTF,shortSig)) return 0;

   bool wantBuy  = (longSig >0.5);
   bool wantSell = (shortSig>0.5);

   if(!InpRequireFlip)
     {
      // Alternative: use current signal-TF trend state instead of a flip.
      double sigTrend=0;
      if(!ReadDTM(g_signalHandle,DTM_BUF_TRENDSTATE,InpSignalTF,sigTrend)) return 0;
      wantBuy  = (sigTrend> 0.5);
      wantSell = (sigTrend<-0.5);
     }

   if(!wantBuy && !wantSell) return 0;

   // --- Optional signal-TF trend agreement ---
   if(InpRequireTrendState)
     {
      double sigTrend=0;
      if(!ReadDTM(g_signalHandle,DTM_BUF_TRENDSTATE,InpSignalTF,sigTrend)) return 0;
      if(wantBuy  && sigTrend< 0.5) return 0;
      if(wantSell && sigTrend>-0.5) return 0;
     }

   // --- Higher-TF trend gate (last closed M15 bar) ---
   double trendState=0;
   if(!ReadDTM(g_trendHandle,DTM_BUF_TRENDSTATE,InpTrendTF,trendState)) return 0;

   if(wantBuy  && trendState> 0.5) return +1;
   if(wantSell && trendState<-0.5) return -1;
   return 0;
  }

// Raw signal-TF flip on the last closed signal bar, WITHOUT the trend gate or
// trend-agreement checks. +1 long flip, -1 short flip, 0 none. Used for the
// optional close-on-opposite-flip exit, which should react to the flip itself
// regardless of the higher-TF trend.
int RawSignalFlip()
  {
   double longSig=0, shortSig=0;
   if(!ReadDTM(g_signalHandle,DTM_BUF_LONGSIGNAL ,InpSignalTF,longSig))  return 0;
   if(!ReadDTM(g_signalHandle,DTM_BUF_SHORTSIGNAL,InpSignalTF,shortSig)) return 0;
   if(longSig >0.5) return +1;
   if(shortSig>0.5) return -1;
   return 0;
  }

// Close our open position because an opposite flip occurred. Returns true if a
// close was issued (position was open and flipped against us).
bool CloseOnOppositeFlip()
  {
   ulong ticket; long type; double volume,entry,sl,tp;
   if(!GetOurPosition(ticket,type,volume,entry,sl,tp)) return false;

   int flip=RawSignalFlip();
   if(flip==0) return false;

   bool opposite = (type==POSITION_TYPE_BUY  && flip<0) ||
                   (type==POSITION_TYPE_SELL && flip>0);
   if(!opposite) return false;

   if(g_trade.PositionClose(ticket))
     {
      PrintFormat("Closed %s ticket %I64u on opposite flip (%s)",
                  (type==POSITION_TYPE_BUY?"BUY":"SELL"),ticket,
                  (flip>0?"long flip":"short flip"));
      return true;
     }
   PrintFormat("Opposite-flip close failed: retcode=%d %s",
               g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
   return false;
  }

//====================================================================
// STOP / TAKE PROFIT
//====================================================================
double CurrentATR_SL()
  {
   if(g_slAtrHandle==INVALID_HANDLE) return 0.0;
   double a[];
   if(CopyBuffer(g_slAtrHandle,0,0,2,a)<=0) return 0.0;
   return a[0];
  }

// Native SL/TP from the DTM signal instance (Trail as stop, TPx as target).
void ComputeSLTP_Native(int dir,double entry,double &slPrice,double &tpPrice,double &slDistPrice)
  {
   slPrice=0.0; tpPrice=0.0; slDistPrice=0.0;

   double trail=0;
   if(ReadDTM(g_signalHandle,DTM_BUF_TRAIL,InpSignalTF,trail) && trail!=EMPTY_VALUE && trail>0.0)
     {
      double buf = InpDTM_SLBufferPts*_Point;
      if(dir>0) slPrice = trail - buf;
      else      slPrice = trail + buf;
      slDistPrice = MathAbs(entry-slPrice);
     }

   int tpBuf = DTM_BUF_TP1;
   if(InpDTMTPPick==DTMTP_TP2) tpBuf=DTM_BUF_TP2;
   if(InpDTMTPPick==DTMTP_TP3) tpBuf=DTM_BUF_TP3;

   double tpLvl=0;
   if(ReadDTM(g_signalHandle,tpBuf,InpSignalTF,tpLvl) && tpLvl!=EMPTY_VALUE && tpLvl>0.0)
     {
      // Only accept a TP that is on the correct side of entry.
      if(dir>0 && tpLvl>entry) tpPrice=tpLvl;
      if(dir<0 && tpLvl<entry) tpPrice=tpLvl;
     }
  }

// Independent SL/TP (same framework as the OB+Spearman EA).
void ComputeSLTP_Independent(int dir,double entry,double &slPrice,double &tpPrice,double &slDistPrice)
  {
   double point=_Point;
   slPrice=0.0; tpPrice=0.0; slDistPrice=0.0;

   if(InpSLMode==SL_FIXED)
      slDistPrice = InpSLFixedPoints*point;
   else if(InpSLMode==SL_ATR)
      slDistPrice = CurrentATR_SL()*InpSL_ATRMult;

   if(InpSLMode!=SL_NONE && slDistPrice>0.0)
     {
      if(dir>0) slPrice=entry-slDistPrice;
      else      slPrice=entry+slDistPrice;
     }

   double tpDistPrice=0.0;
   if(InpTPMode==TP_FIXED)
      tpDistPrice = InpTPFixedPoints*point;
   else if(InpTPMode==TP_RRR && slDistPrice>0.0)
      tpDistPrice = slDistPrice*InpTP_RRR;

   if(InpTPMode!=TP_NONE && tpDistPrice>0.0)
     {
      if(dir>0) tpPrice=entry+tpDistPrice;
      else      tpPrice=entry-tpDistPrice;
     }
  }

void ComputeSLTP(int dir,double entry,double &slPrice,double &tpPrice,double &slDistPrice)
  {
   if(InpSLTPSource==SLTP_DTM_NATIVE)
      ComputeSLTP_Native(dir,entry,slPrice,tpPrice,slDistPrice);
   else
      ComputeSLTP_Independent(dir,entry,slPrice,tpPrice,slDistPrice);
  }

//====================================================================
// LOT SIZING
//====================================================================
double NormalizeVolume(double vol)
  {
   double minV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0) step=0.01;
   vol=MathRound(vol/step)*step;
   if(vol<minV) vol=minV;
   if(vol>maxV) vol=maxV;
   return NormalizeDouble(vol,2);
  }

double ComputeLot(double slDistPrice)
  {
   if(InpLotMode==LOT_FIXED || slDistPrice<=0.0)
      return NormalizeVolume(InpFixedLot);

   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize =SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickValue<=0 || tickSize<=0)
      return NormalizeVolume(InpFixedLot);

   double slTicks=slDistPrice/tickSize;
   double lossPerLot=slTicks*tickValue;
   if(lossPerLot<=0.0)
      return NormalizeVolume(InpFixedLot);

   double riskMoney;
   if(InpLotMode==LOT_RISK_PCT)
      riskMoney=AccountInfoDouble(ACCOUNT_BALANCE)*InpRiskPercent/100.0;
   else
      riskMoney=InpMoneyRisk;

   return NormalizeVolume(riskMoney/lossPerLot);
  }

//====================================================================
// MARGIN CHECK
//====================================================================
bool MarginOK(int dir,double lot,double price)
  {
   double margin=0.0;
   ENUM_ORDER_TYPE ot=(dir>0)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcMargin(ot,_Symbol,lot,price,margin)) return false;
   return (margin<=AccountInfoDouble(ACCOUNT_MARGIN_FREE));
  }

//====================================================================
// STOP-LEVEL SANITISER
//====================================================================
void RespectStops(int dir,double price,double &sl,double &tp)
  {
   long stopsLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double minDist=stopsLevel*_Point;
   if(minDist>0)
     {
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
     }
   sl=(sl>0.0)?NormalizeDouble(sl,_Digits):0.0;
   tp=(tp>0.0)?NormalizeDouble(tp,_Digits):0.0;
  }

//====================================================================
// OPEN TRADE
//====================================================================
bool OpenTrade(int dir)
  {
   g_sym.RefreshRates();
   double price=(dir>0)?g_sym.Ask():g_sym.Bid();
   if(price<=0.0) return false;

   double sl,tp,slDist;
   ComputeSLTP(dir,price,sl,tp,slDist);
   RespectStops(dir,price,sl,tp);

   double lot=ComputeLot(slDist);
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
      g_partialDoneTicket=0;
      PrintFormat("%s opened: lot=%.2f price=%.5f sl=%.5f tp=%.5f",
                  (dir>0?"BUY":"SELL"),lot,price,sl,tp);
     }
   else
      PrintFormat("Order send failed: retcode=%d %s",
                  g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
   return ok;
  }

//====================================================================
// SL MODIFY HELPER (keeps TP intact)
//====================================================================
void ModifySL(ulong ticket,double newSL)
  {
   if(!PositionSelectByTicket(ticket)) return;
   double tp=PositionGetDouble(POSITION_TP);
   long   type=PositionGetInteger(POSITION_TYPE);
   double price=(type==POSITION_TYPE_BUY)?g_sym.Bid():g_sym.Ask();

   int dir=(type==POSITION_TYPE_BUY)?1:-1;
   double slAdj=newSL, tpAdj=tp;
   RespectStops(dir,price,slAdj,tpAdj);

   g_trade.PositionModify(ticket,slAdj,tp); // non-fatal on reject; retries next tick
  }

//====================================================================
// TRADE MANAGEMENT
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
         if(sl<newSL-point*0.5) ModifySL(ticket,newSL);
        }
     }
   else if(type==POSITION_TYPE_SELL)
     {
      double profitPts=(entry-g_sym.Ask())/point;
      if(profitPts>=InpBE_TriggerPoints)
        {
         double newSL=NormalizeDouble(entry-InpBE_OffsetPoints*point,_Digits);
         if(sl>newSL+point*0.5 || sl==0.0) ModifySL(ticket,newSL);
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
      if(newSL>sl+InpTrailStepPoints*point) ModifySL(ticket,newSL);
     }
   else if(type==POSITION_TYPE_SELL)
     {
      double profitPts=(entry-g_sym.Ask())/point;
      if(profitPts<InpTrailStartPoints) return;
      double newSL=NormalizeDouble(g_sym.Ask()+InpTrailDistPoints*point,_Digits);
      if(sl==0.0 || newSL<sl-InpTrailStepPoints*point) ModifySL(ticket,newSL);
     }
  }

void ManagePartial(ulong ticket,long type,double volume,double entry)
  {
   if(!InpUsePartial) return;
   if(g_partialDoneTicket==ticket) return;
   g_sym.RefreshRates();
   double point=_Point;

   double profitPts;
   if(type==POSITION_TYPE_BUY) profitPts=(g_sym.Bid()-entry)/point;
   else                        profitPts=(entry-g_sym.Ask())/point;
   if(profitPts<InpPartialTrigPoints) return;

   double closeVol=NormalizeVolume(volume*InpPartialPercent/100.0);
   double minV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(closeVol<minV || closeVol>=volume) return;

   if(g_trade.PositionClosePartial(ticket,closeVol))
     {
      g_partialDoneTicket=ticket;
      PrintFormat("Partial close %.2f lots on ticket %I64u",closeVol,ticket);
      if(InpPartialThenBE)
        {
         double newSL=(type==POSITION_TYPE_BUY)
                      ? NormalizeDouble(entry+InpBE_OffsetPoints*point,_Digits)
                      : NormalizeDouble(entry-InpBE_OffsetPoints*point,_Digits);
         ModifySL(ticket,newSL);
        }
     }
  }

void ManageOpenPosition()
  {
   ulong ticket; long type; double volume,entry,sl,tp;
   if(!GetOurPosition(ticket,type,volume,entry,sl,tp)) return;

   ManagePartial(ticket,type,volume,entry);
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
   if(HasOpenPosition())
      ManageOpenPosition();

   if(!IsNewSignalBar())
      return;

   ResetDailyCounterIfNeeded();

   // Optional: close the open trade if the signal TF flips against it, then
   // wait for a fresh entry signal on a later bar (no same-bar re-entry).
   if(InpCloseOnOppositeFlip && HasOpenPosition())
     {
      if(CloseOnOppositeFlip())
         return;
     }

   // Single position, no stacking; opposite signal ignored while in trade.
   if(HasOpenPosition())
      return;

   if(!SessionOK())      return;
   if(!SpreadOK())       return;
   if(!TradesPerDayOK()) return;

   int sig=DetectSignal();
   if(sig==0) return;

   // Guard against duplicate entry on the same signal bar.
   datetime sigBar=iTime(_Symbol,InpSignalTF,1);
   if(sigBar==g_lastTradedBarTime) return;
   g_lastTradedBarTime=sigBar;

   OpenTrade(sig);
  }
//+------------------------------------------------------------------+
