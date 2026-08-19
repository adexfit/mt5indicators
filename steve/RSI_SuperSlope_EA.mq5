//+------------------------------------------------------------------+
//|                                             RSI_SuperSlope_EA.mq5 |
//| Production EA: RSI Arrow Out of Zone signal + SuperSlope regime. |
//+------------------------------------------------------------------+
#property copyright "RSI SuperSlope EA"
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

enum ENUM_MONEY_MODE { MONEY_FIXED_LOTS=0, MONEY_RISK_PERCENT=1 };
enum ENUM_SL_MODE { STOP_NONE=0, STOP_FIXED_PIPS=1 };
enum ENUM_TP_MODE { TARGET_NONE=0, TARGET_FIXED_PIPS=1, TARGET_RRR=2 };
enum ENUM_TRAIL_MODE { TRAIL_FIXED_PIPS=0, TRAIL_ATR=1 };
enum ENUM_DISTANCE_UNIT { DISTANCE_AUTO=0, DISTANCE_POINT=1, DISTANCE_TICK=2, DISTANCE_FOREX_PIP=3 };

input group "=== RSI Arrow Out of Zone ==="
input string InpRSIName             = "RSI Arrow Out of Zone";
input int    InpRSIPeriod            = 14;
input ENUM_APPLIED_PRICE InpRSIPrice = PRICE_CLOSE;
input int    InpRSIDownLevel         = 35;
input double InpRSIUpLevel           = 65.0;

input group "=== SuperSlope ==="
input string InpSuperSlopeName       = "SuperSlope";
input bool   InpSuperAutoTimeFrame   = false;
input string InpSuperTimeFrame       = "D1";
input string InpSuperExtraTimeFrame  = "W1";
input string InpSuperExtraTimeFrame2 = "MN";
input int    InpSuperNoOfTimeFrames  = 1;
input double InpDifferenceThreshold  = 0.0;
input double InpLevelCrossValue      = 2.0;
input int    InpSlopeMAPeriod        = 7;
input int    InpSlopeATRPeriod       = 50;
input bool   InpUseFormingCandles    = false; // false = confirmed SuperSlope signals only
input bool   InpRequireSlopeRegime   = true;
input bool   InpUseSuperSlopeExits   = true;
input bool   InpCloseOnOppositeRSI   = false;

input group "=== Execution ==="
input bool   InpAllowBuys            = true;
input bool   InpAllowSells           = true;
input int    InpMaxPositions         = 1;
input long   InpMagic                = 26081901;
input ulong  InpDeviationPoints      = 20;
input string InpComment              = "RSI_SuperSlope";
input bool   InpNewBarOnly           = true;

input group "=== Price Distance Units ==="
input ENUM_DISTANCE_UNIT InpDistanceUnit = DISTANCE_AUTO; // Auto: conventional pip, never below trade tick

input group "=== Money Management ==="
input ENUM_MONEY_MODE InpMoneyMode   = MONEY_FIXED_LOTS;
input double InpFixedLots             = 0.10;
input double InpRiskPercent           = 1.0;

input group "=== Stop Loss ==="
input ENUM_SL_MODE InpSLMode          = STOP_FIXED_PIPS;
input double InpFixedSLPips           = 30.0; // Distance units selected above

input group "=== Take Profit ==="
input ENUM_TP_MODE InpTPMode          = TARGET_RRR;
input double InpFixedTPPips           = 60.0; // Distance units selected above
input double InpRRR                    = 2.0;

input group "=== Break-even ==="
input bool   InpUseBreakEven          = true;
input double InpBETriggerPips         = 20.0;
input double InpBEOffsetPips          = 1.0;

input group "=== Trailing Stop ==="
input bool   InpUseTrailing           = true;
input ENUM_TRAIL_MODE InpTrailMode    = TRAIL_FIXED_PIPS;
input double InpTrailStartPips        = 30.0;
input double InpTrailDistancePips     = 20.0;
input double InpTrailStepPips         = 2.0;
input int    InpTrailATRPeriod        = 14;
input double InpTrailATRMultiplier    = 1.5;

input group "=== Partial Close ==="
input bool   InpUsePartialClose       = false;
input double InpPartialTriggerPips    = 40.0;
input double InpPartialClosePercent   = 50.0;
input bool   InpPartialThenBreakEven  = true;

input group "=== Filters and Risk Guards ==="
input bool   InpUseSessionFilter      = false;
input int    InpSessionStartHour      = 7;
input int    InpSessionStartMinute    = 0;
input int    InpSessionEndHour        = 20;
input int    InpSessionEndMinute      = 0;
input bool   InpUseSpreadFilter       = false;
input int    InpMaxSpreadPoints       = 30;
input int    InpMaxTradesPerDay       = 0;
input bool   InpUseDailyLossGuard     = false;
input double InpDailyLossPercent      = 5.0;
input bool   InpCloseOnDailyLoss      = false;

#define RSI_BUY_BUFFER  0
#define RSI_SELL_BUFFER 1
#define SS_BUY_EXIT     4
#define SS_SELL_EXIT    5
#define SS_BUY_REGIME   6
#define SS_SELL_REGIME  7

CTrade trade;
CPositionInfo position;
int hRSI=INVALID_HANDLE, hSlope=INVALID_HANDLE, hATR=INVALID_HANDLE;
datetime lastChartBar=0, lastSignalBar=0, dayStamp=0;
double dayStartBalance=0.0;
int tradesToday=0;

int OnInit()
  {
   if(InpRSIPeriod<1 || InpSlopeMAPeriod<1 || InpSlopeATRPeriod<2) return INIT_PARAMETERS_INCORRECT;
   if(SymbolPoint()<=0.0 || SymbolTickSize()<=0.0)
     { Print("Invalid symbol point or tick size for ",_Symbol); return INIT_FAILED; }
   hRSI=iCustom(_Symbol,_Period,InpRSIName,InpRSIPeriod,InpRSIPrice,InpRSIDownLevel,InpRSIUpLevel);
   if(hRSI==INVALID_HANDLE)
     { Print("Failed to create RSI indicator: ",InpRSIName," error ",GetLastError()); return INIT_FAILED; }

   // Parameter order through useFormingCandles matches SuperSlope.mq5; all
   // later alert/display inputs retain their indicator defaults.
   hSlope=iCustom(_Symbol,_Period,InpSuperSlopeName,
                  "----General Inputs----",0,"Lucida Console","----",
                  InpSuperAutoTimeFrame,"ind_tf M1,M5,M15,M30,H1,H4,D1,W1,MN",
                  InpSuperTimeFrame,InpSuperExtraTimeFrame,InpSuperExtraTimeFrame2,
                  InpSuperNoOfTimeFrames,"---- Slope Inputs ----",
                  InpDifferenceThreshold,InpLevelCrossValue,InpSlopeMAPeriod,InpSlopeATRPeriod,
                  InpUseFormingCandles);
   if(hSlope==INVALID_HANDLE)
     { Print("Failed to create SuperSlope indicator: ",InpSuperSlopeName," error ",GetLastError()); return INIT_FAILED; }

   if(InpUseTrailing && InpTrailMode==TRAIL_ATR)
     {
      hATR=iATR(_Symbol,_Period,MathMax(1,InpTrailATRPeriod));
      if(hATR==INVALID_HANDLE) return INIT_FAILED;
     }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);
   trade.LogLevel(LOG_LEVEL_ERRORS);
   UpdateDayAnchor(true);
   lastChartBar=iTime(_Symbol,_Period,0);
   if(InpMoneyMode==MONEY_RISK_PERCENT && InpSLMode==STOP_NONE)
      Print("Warning: risk-percent sizing requires a stop; fixed lots will be used.");
   PrintFormat("%s pricing: digits=%d point=%s tick=%s distance-unit=%s",
               _Symbol,SymbolDigits(),PriceText(SymbolPoint()),PriceText(SymbolTickSize()),PriceText(DistanceUnit()));
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(hRSI!=INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hSlope!=INVALID_HANDLE) IndicatorRelease(hSlope);
   if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR);
   Comment("");
  }

void OnTick()
  {
   UpdateDayAnchor(false);
   ManagePositions();
   datetime currentBar=iTime(_Symbol,_Period,0);
   bool newBar=(currentBar!=lastChartBar);
   if(newBar) lastChartBar=currentBar;
   if(InpNewBarOnly && !newBar) return;

   int direction=0;
   bool buyArrow=false,sellArrow=false;
   if(!ReadSignal(1,buyArrow,sellArrow)) return;
   if(buyArrow) direction=1;
   if(sellArrow) direction=-1;

   if(InpUseSuperSlopeExits)
     {
      double buyExit=0,sellExit=0;
      if(ReadBuffer(hSlope,SS_BUY_EXIT,1,buyExit) && buyExit>0.5) CloseDirection(POSITION_TYPE_BUY,"SuperSlope BuyExit");
      if(ReadBuffer(hSlope,SS_SELL_EXIT,1,sellExit) && sellExit>0.5) CloseDirection(POSITION_TYPE_SELL,"SuperSlope SellExit");
     }
   if(InpCloseOnOppositeRSI)
     {
      if(buyArrow) CloseDirection(POSITION_TYPE_SELL,"opposite RSI signal");
      if(sellArrow) CloseDirection(POSITION_TYPE_BUY,"opposite RSI signal");
     }
   if(DailyLossHit())
     {
      if(InpCloseOnDailyLoss) CloseOurPositions("daily loss");
      return;
     }
   datetime signalBar=iTime(_Symbol,_Period,1);
   if(direction==0 || signalBar==0 || lastSignalBar==signalBar) return;

   double regime=0;
   if(!ReadBuffer(hSlope,direction>0?SS_BUY_REGIME:SS_SELL_REGIME,1,regime)) return;
   lastSignalBar=signalBar;
   if(InpRequireSlopeRegime && regime<0.5) return;
   if(direction>0 && !InpAllowBuys) return;
   if(direction<0 && !InpAllowSells) return;
   if(!EntryAllowed() || CountOurPositions()>=MathMax(1,InpMaxPositions)) return;
   if(OpenPosition(direction)) tradesToday++;
  }

bool ReadSignal(const int shift,bool &buy,bool &sell)
  {
   buy=false; sell=false;
   double a=0,b=0;
   if(!ReadBuffer(hRSI,RSI_BUY_BUFFER,shift,a) || !ReadBuffer(hRSI,RSI_SELL_BUFFER,shift,b)) return false;
   buy=(a>0.0); sell=(b>0.0);
   return true;
  }

bool ReadBuffer(const int handle,const int buffer,const int shift,double &value)
  {
   value=0.0;
   if(handle==INVALID_HANDLE || BarsCalculated(handle)<=shift) return false;
   double data[]; ArraySetAsSeries(data,true);
   if(CopyBuffer(handle,buffer,shift,1,data)!=1) return false;
   value=data[0]; return true;
  }

bool OpenPosition(const int direction)
  {
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return false;
   double entry=direction>0?tick.ask:tick.bid;
   double unit=DistanceUnit(), slDist=0,tpDist=0;
   if(InpSLMode==STOP_FIXED_PIPS && InpFixedSLPips>0) slDist=InpFixedSLPips*unit;
   if(InpTPMode==TARGET_FIXED_PIPS && InpFixedTPPips>0) tpDist=InpFixedTPPips*unit;
   if(InpTPMode==TARGET_RRR && slDist>0 && InpRRR>0) tpDist=slDist*InpRRR;
   double minDist=MinimumStopDistance();
   if(slDist>0 && slDist<minDist) slDist=minDist;
   if(tpDist>0 && tpDist<minDist) tpDist=minDist;
   double sl=slDist>0?(direction>0?entry-slDist:entry+slDist):0.0;
   double tp=tpDist>0?(direction>0?entry+tpDist:entry-tpDist):0.0;
   if(sl>0) sl=NormalizePrice(sl,direction<0);
   if(tp>0) tp=NormalizePrice(tp,direction>0);
   slDist=sl>0?MathAbs(entry-sl):0.0;
   double lots=CalculateLots(direction,entry,sl);
   if(lots<=0) return false;
   double margin=0; ENUM_ORDER_TYPE orderType=direction>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcMargin(orderType,_Symbol,lots,entry,margin) || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     { Print("Entry skipped: insufficient free margin."); return false; }
   bool ok=direction>0?trade.Buy(lots,_Symbol,0,sl,tp,InpComment):trade.Sell(lots,_Symbol,0,sl,tp,InpComment);
   if(!ok) PrintFormat("Entry failed: %d %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
   else PrintFormat("Opened %s %.2f lots SL %s TP %s",direction>0?"BUY":"SELL",lots,PriceText(sl),PriceText(tp));
   return ok;
  }

double CalculateLots(const int direction,const double entry,const double sl)
  {
   double lots=InpFixedLots;
   if(InpMoneyMode==MONEY_RISK_PERCENT && sl>0.0)
     {
      double lossOneLot=0.0;
      ENUM_ORDER_TYPE orderType=direction>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      if(OrderCalcProfit(orderType,_Symbol,1.0,entry,sl,lossOneLot) && lossOneLot<0.0)
         lots=AccountInfoDouble(ACCOUNT_BALANCE)*InpRiskPercent/100.0/MathAbs(lossOneLot);
      else
         Print("Risk sizing calculation failed; fixed lots will be used. Error ",GetLastError());
     }
   return NormalizeVolume(lots);
  }

double NormalizeVolume(double volume)
  {
   double minV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN), maxV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX), step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0) step=minV>0?minV:0.01;
   volume=MathFloor(volume/step+1e-8)*step;
   if(volume<minV) volume=minV; if(volume>maxV) volume=maxV;
   int digits=0; double s=step; while(digits<8 && MathAbs(s-MathRound(s))>1e-8) { s*=10; digits++; }
   return NormalizeDouble(volume,digits);
  }

void ManagePositions()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i); if(ticket==0 || !position.SelectByTicket(ticket)) continue;
      if(position.Symbol()!=_Symbol || position.Magic()!=InpMagic) continue;
      bool isBuy=position.PositionType()==POSITION_TYPE_BUY;
      double entry=position.PriceOpen(), current=isBuy?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double profit=isBuy?current-entry:entry-current, unit=DistanceUnit();
      ManagePartial(ticket,isBuy,entry,position.Volume(),profit/unit);
      if(!position.SelectByTicket(ticket)) continue;
      double oldSL=position.StopLoss(), desired=oldSL;
      if(InpUseBreakEven && profit/unit>=InpBETriggerPips)
         desired=BetterStop(isBuy,desired,isBuy?entry+InpBEOffsetPips*unit:entry-InpBEOffsetPips*unit);
      if(InpUseTrailing && profit/unit>=InpTrailStartPips)
        {
         double dist=InpTrailDistancePips*unit;
         double atr=0; if(InpTrailMode==TRAIL_ATR && ReadBuffer(hATR,0,1,atr)) dist=atr*InpTrailATRMultiplier;
         if(dist>0) desired=BetterStop(isBuy,desired,isBuy?current-dist:current+dist);
        }
      if(desired<=0 || (oldSL>0 && MathAbs(desired-oldSL)<InpTrailStepPips*unit)) continue;
      double minDist=MinimumStopDistance();
      if(isBuy) desired=MathMin(desired,SymbolInfoDouble(_Symbol,SYMBOL_BID)-minDist);
      else desired=MathMax(desired,SymbolInfoDouble(_Symbol,SYMBOL_ASK)+minDist);
      desired=NormalizePrice(desired,!isBuy);
      if((isBuy && oldSL>0 && desired<=oldSL) || (!isBuy && oldSL>0 && desired>=oldSL)) continue;
      if(!trade.PositionModify(ticket,desired,position.TakeProfit()))
         PrintFormat("SL modify failed #%I64u: %d %s",ticket,trade.ResultRetcode(),trade.ResultRetcodeDescription());
     }
  }

void ManagePartial(ulong ticket,bool isBuy,double entry,double volume,double profitPips)
  {
   if(!InpUsePartialClose || PartialAlreadyDone(ticket) || profitPips<InpPartialTriggerPips) return;
   double pct=MathMax(1.0,MathMin(99.0,InpPartialClosePercent));
   double closeVolume=NormalizeVolume(volume*pct/100.0), minV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(closeVolume<minV || volume-closeVolume<minV) return;
   if(ClosePartial(ticket,isBuy,closeVolume))
     {
      GlobalVariableSet(PartialKey(ticket),(double)TimeCurrent());
      if(InpPartialThenBreakEven && position.SelectByTicket(ticket))
        {
         double sl=isBuy?entry+InpBEOffsetPips*DistanceUnit():entry-InpBEOffsetPips*DistanceUnit();
         trade.PositionModify(ticket,NormalizePrice(sl,!isBuy),position.TakeProfit());
        }
     }
  }

bool ClosePartial(const ulong ticket,const bool isBuy,const double volume)
  {
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return false;
   MqlTradeRequest request={}; MqlTradeResult result={};
   request.action=TRADE_ACTION_DEAL;
   request.position=ticket;
   request.symbol=_Symbol;
   request.magic=InpMagic;
   request.volume=volume;
   request.deviation=InpDeviationPoints;
   request.type=isBuy?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
   request.price=isBuy?tick.bid:tick.ask;
   request.type_filling=SymbolFillingMode();
   request.comment=InpComment+" partial";
   if(!OrderSend(request,result) || (result.retcode!=TRADE_RETCODE_DONE && result.retcode!=TRADE_RETCODE_DONE_PARTIAL))
     {
      PrintFormat("Partial close failed #%I64u: %u %s",ticket,result.retcode,result.comment);
      return false;
     }
   PrintFormat("Partially closed %.2f lots on #%I64u",volume,ticket);
   return true;
  }

ENUM_ORDER_TYPE_FILLING SymbolFillingMode()
  {
   long filling=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   if((filling&SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   if((filling&SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
  }

string PartialKey(const ulong ticket)
  { return StringFormat("RSS.P.%I64d.%I64u",InpMagic,ticket); }
bool PartialAlreadyDone(const ulong ticket)
  { return GlobalVariableCheck(PartialKey(ticket)); }

double BetterStop(bool isBuy,double current,double candidate)
  { if(candidate<=0) return current; if(current<=0) return candidate; return isBuy?MathMax(current,candidate):MathMin(current,candidate); }

void CloseDirection(ENUM_POSITION_TYPE type,const string reason)
  { for(int i=PositionsTotal()-1;i>=0;i--) { ulong ticket=PositionGetTicket(i); if(ticket==0 || !position.SelectByTicket(ticket)) continue; if(position.Symbol()==_Symbol && position.Magic()==InpMagic && position.PositionType()==type && !trade.PositionClose(ticket)) Print("Close failed (",reason,") ",trade.ResultRetcodeDescription()); } }
void CloseOurPositions(const string reason) { CloseDirection(POSITION_TYPE_BUY,reason); CloseDirection(POSITION_TYPE_SELL,reason); }
int CountOurPositions() { int n=0; for(int i=PositionsTotal()-1;i>=0;i--) { ulong t=PositionGetTicket(i); if(t>0 && PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==InpMagic) n++; } return n; }

bool EntryAllowed()
  {
   if(InpMaxTradesPerDay>0 && tradesToday>=InpMaxTradesPerDay) return false;
   if(InpUseSpreadFilter && (int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)>InpMaxSpreadPoints) return false;
   if(!InSession()) return false;
   return true;
  }
bool InSession()
  {
   if(!InpUseSessionFilter) return true;
   MqlDateTime t; TimeToStruct(TimeCurrent(),t); int now=t.hour*60+t.min, start=InpSessionStartHour*60+InpSessionStartMinute, end=InpSessionEndHour*60+InpSessionEndMinute;
   if(start==end) return true; return start<end?(now>=start && now<end):(now>=start || now<end);
  }
void UpdateDayAnchor(bool force)
  {
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   datetime d=StringToTime(StringFormat("%04d.%02d.%02d",t.year,t.mon,t.day));
   if(force || d!=dayStamp)
     {
      dayStamp=d;
      dayStartBalance=DayStartBalance(d);
      tradesToday=CountTodayEntries(d);
     }
  }
double DayStartBalance(const datetime from)
  {
   double realized=0.0;
   if(!HistorySelect(from,TimeCurrent())) return AccountInfoDouble(ACCOUNT_BALANCE);
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      ulong deal=HistoryDealGetTicket(i); if(deal==0) continue;
      long type=HistoryDealGetInteger(deal,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
      realized+=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_SWAP)+HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE);
     }
   return AccountInfoDouble(ACCOUNT_BALANCE)-realized;
  }
int CountTodayEntries(const datetime from)
  {
   if(!HistorySelect(from,TimeCurrent())) return 0;
   int count=0;
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      ulong deal=HistoryDealGetTicket(i); if(deal==0) continue;
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol || HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagic) continue;
      long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
      long type=HistoryDealGetInteger(deal,DEAL_TYPE);
      if((entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_INOUT) && (type==DEAL_TYPE_BUY || type==DEAL_TYPE_SELL)) count++;
     }
   return count;
  }
bool DailyLossHit()
  { return InpUseDailyLossGuard && dayStartBalance>0 && AccountInfoDouble(ACCOUNT_EQUITY)<=dayStartBalance*(1.0-InpDailyLossPercent/100.0); }
int SymbolDigits() { return (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS); }
double SymbolPoint() { return SymbolInfoDouble(_Symbol,SYMBOL_POINT); }
double SymbolTickSize()
  { double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE); return tick>0.0?tick:SymbolPoint(); }
double ForexPipSize()
  {
   int digits=SymbolDigits(); double point=SymbolPoint();
   return (digits==3 || digits==5)?10.0*point:point;
  }
double DistanceUnit()
  {
   if(InpDistanceUnit==DISTANCE_POINT) return SymbolPoint();
   if(InpDistanceUnit==DISTANCE_TICK) return SymbolTickSize();
   if(InpDistanceUnit==DISTANCE_FOREX_PIP) return ForexPipSize();
   // Standard 3/5-digit quotes use ten points per pip. The tick-size floor
   // also supports metals and CFDs whose valid price increment exceeds it.
   return MathMax(ForexPipSize(),SymbolTickSize());
  }
double NormalizePrice(const double price,const bool roundUp)
  {
   if(price<=0.0) return 0.0;
   double tick=SymbolTickSize();
   double steps=price/tick;
   double aligned=roundUp?MathCeil(steps-1e-10)*tick:MathFloor(steps+1e-10)*tick;
   return NormalizeDouble(aligned,SymbolDigits());
  }
string PriceText(const double price) { return DoubleToString(price,SymbolDigits()); }
double MinimumStopDistance()
  {
   long stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double raw=(double)MathMax(stops,freeze)*SymbolPoint();
   double tick=SymbolTickSize();
   return MathMax(MathCeil(raw/tick-1e-10)*tick,tick);
  }
//+------------------------------------------------------------------+
