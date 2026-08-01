//+------------------------------------------------------------------+
//|                                                MikeyScalping.mq5 |
//|                                              TREMOR_Grid_Recovery |
//|                                                                  |
//|  Grid entry with fixed base lots inside a sequence, plus a       |
//|  post-loss martingale that scales the base lot of the NEXT       |
//|  cycle only. Basket exits on a synchronized take profit.         |
//+------------------------------------------------------------------+
#property copyright "Mikey"
#property version   "1.00"
#property description "TREMOR_Grid_Recovery - grid layering with post-loss martingale recovery"

#include <Trade\Trade.mqh>

CTrade        trade;
CPositionInfo posinfo;

//--- Trade Settings
input string   _s1_                      = "=== Trade Settings ===";
input double   InitialLotSize            = 0.01;  // Initial lot size (MINIMUM)
input double   DistanceForPending        = 0.5;   // Distance for pending orders ($)
input double   ProfitTargetInDollars     = 0.5;   // Profit target in dollars ($)
input double   LossToTriggerRecovery     = 0.5;   // Loss to trigger recovery ($)

//--- Martingale Settings
input string   _s2_                      = "=== Martingale Settings ===";
input double   MartingaleMultiplier      = 2.0;   // Martingale multiplier
input int      MaxRecoveryAttempts       = 3;     // Maximum recovery attempts
input bool     UseTrailingStop           = true;  // Use trailing stop

//--- Risk Management
input string   _s3_                      = "=== Risk Management ===";
input int      MaxSimultaneousPositions  = 5;     // Maximum simultaneous positions
input double   StopLossPerTrade          = 2.0;   // Stop loss per trade ($)
input double   TakeProfitPerTrade        = 1.0;   // Take profit per trade ($)
input double   DailyProfitTarget         = 100.0; // Daily profit target ($)
input double   MaxLossPercentOfBalance   = 50.0;  // Max loss (% of balance)
input int      MagicNumber               = 888123;// EA Magic Number

//--- Session Filter
//--- values are minutes since midnight, so they compare directly
enum enumTime
  {
   Inactive = -1,   // Inactive (no time filter)
   _0000 = 0,       // 00:00
   _0015 = 15,      // 00:15
   _0030 = 30,      // 00:30
   _0045 = 45,      // 00:45
   _0100 = 60,      // 01:00
   _0115 = 75,      // 01:15
   _0130 = 90,      // 01:30
   _0145 = 105,     // 01:45
   _0200 = 120,     // 02:00
   _0215 = 135,     // 02:15
   _0230 = 150,     // 02:30
   _0245 = 165,     // 02:45
   _0300 = 180,     // 03:00
   _0315 = 195,     // 03:15
   _0330 = 210,     // 03:30
   _0345 = 225,     // 03:45
   _0400 = 240,     // 04:00
   _0415 = 255,     // 04:15
   _0430 = 270,     // 04:30
   _0445 = 285,     // 04:45
   _0500 = 300,     // 05:00
   _0515 = 315,     // 05:15
   _0530 = 330,     // 05:30
   _0545 = 345,     // 05:45
   _0600 = 360,     // 06:00
   _0615 = 375,     // 06:15
   _0630 = 390,     // 06:30
   _0645 = 405,     // 06:45
   _0700 = 420,     // 07:00
   _0715 = 435,     // 07:15
   _0730 = 450,     // 07:30
   _0745 = 465,     // 07:45
   _0800 = 480,     // 08:00
   _0815 = 495,     // 08:15
   _0830 = 510,     // 08:30
   _0845 = 525,     // 08:45
   _0900 = 540,     // 09:00
   _0915 = 555,     // 09:15
   _0930 = 570,     // 09:30
   _0945 = 585,     // 09:45
   _1000 = 600,     // 10:00
   _1015 = 615,     // 10:15
   _1030 = 630,     // 10:30
   _1045 = 645,     // 10:45
   _1100 = 660,     // 11:00
   _1115 = 675,     // 11:15
   _1130 = 690,     // 11:30
   _1145 = 705,     // 11:45
   _1200 = 720,     // 12:00
   _1215 = 735,     // 12:15
   _1230 = 750,     // 12:30
   _1245 = 765,     // 12:45
   _1300 = 780,     // 13:00
   _1315 = 795,     // 13:15
   _1330 = 810,     // 13:30
   _1345 = 825,     // 13:45
   _1400 = 840,     // 14:00
   _1415 = 855,     // 14:15
   _1430 = 870,     // 14:30
   _1445 = 885,     // 14:45
   _1500 = 900,     // 15:00
   _1515 = 915,     // 15:15
   _1530 = 930,     // 15:30
   _1545 = 945,     // 15:45
   _1600 = 960,     // 16:00
   _1615 = 975,     // 16:15
   _1630 = 990,     // 16:30
   _1645 = 1005,    // 16:45
   _1700 = 1020,    // 17:00
   _1715 = 1035,    // 17:15
   _1730 = 1050,    // 17:30
   _1745 = 1065,    // 17:45
   _1800 = 1080,    // 18:00
   _1815 = 1095,    // 18:15
   _1830 = 1110,    // 18:30
   _1845 = 1125,    // 18:45
   _1900 = 1140,    // 19:00
   _1915 = 1155,    // 19:15
   _1930 = 1170,    // 19:30
   _1945 = 1185,    // 19:45
   _2000 = 1200,    // 20:00
   _2015 = 1215,    // 20:15
   _2030 = 1230,    // 20:30
   _2045 = 1245,    // 20:45
   _2100 = 1260,    // 21:00
   _2115 = 1275,    // 21:15
   _2130 = 1290,    // 21:30
   _2145 = 1305,    // 21:45
   _2200 = 1320,    // 22:00
   _2215 = 1335,    // 22:15
   _2230 = 1350,    // 22:30
   _2245 = 1365,    // 22:45
   _2300 = 1380,    // 23:00
   _2315 = 1395,    // 23:15
   _2330 = 1410,    // 23:30
   _2345 = 1425     // 23:45
  };

input string   _s4_                      = "=== Session Filter ===";
input enumTime SessionStart              = Inactive; // Start time (broker server time)
input enumTime SessionEnd                = Inactive; // End time (broker server time)

//--- symbol geometry
int      g_digits          = 0;
double   g_point           = 0;
double   g_pip             = 0;      // 1 pip in price terms
double   g_stopsLevel      = 0;      // broker minimum stop distance (price)
double   g_freezeLevel     = 0;
int      g_slippage        = 0;      // deviation in points

//--- cycle / recovery state
int      g_recoveryLevel   = 0;      // 0 = normal, 1..MaxRecoveryAttempts = recovering
double   g_cycleBaseLot    = 0;      // fixed lot for every layer of the active cycle
datetime g_cycleStart      = 0;
bool     g_cycleActive     = false;

//--- daily / circuit breaker state
datetime g_dayStart        = 0;
double   g_dailyClosed     = 0;
bool     g_haltedForDay    = false;
bool     g_haltedByDrawdown= false;

//--- dashboard
string   g_dashPrefix      = "Tremor";

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(g_point <= 0)
   {
      Print("TREMOR: symbol properties unavailable for ", _Symbol);
      return(INIT_FAILED);
   }

   //--- pip sizing: gold quotes $0.10 as a pip on both 2 and 3 digit feeds,
   //--- FX uses the usual 10-point pip on 3/5 digit feeds.
   if(StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0)
      g_pip = 0.1;
   else if(g_digits == 3 || g_digits == 5)
      g_pip = g_point * 10.0;
   else
      g_pip = g_point;

   g_stopsLevel  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)  * g_point;
   g_freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * g_point;

   //--- allow ~3 pips of slippage, expressed in points
   g_slippage = (int)MathMax(10, MathRound(3.0 * g_pip / g_point));

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(g_slippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   //--- validate inputs that would otherwise produce nonsense silently
   if(InitialLotSize <= 0 || MartingaleMultiplier < 1.0 || MaxRecoveryAttempts < 0 ||
      MaxSimultaneousPositions < 1 || DistanceForPending <= 0)
   {
      Print("TREMOR: invalid input combination - check lots, multiplier, distance and position cap");
      return(INIT_PARAMETERS_INCORRECT);
   }

   g_dayStart = ServerDayStart();
   g_recoveryLevel = 0;
   g_cycleBaseLot = NormalizeVolume(InitialLotSize);

   //--- adopt any basket that already exists (EA restart / recompile)
   int cnt; double vol, wavg, profit, lastEntry; int dir;
   BasketStats(cnt, vol, wavg, profit, dir, lastEntry);
   if(cnt > 0)
   {
      g_cycleActive = true;
      g_cycleStart  = EarliestPositionTime();
   }

   CreateDashboard();
   EventSetTimer(1);
   UpdateDashboard();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteDashboard();
   Comment("");
}

//+------------------------------------------------------------------+
//| Timer - dashboard refresh only                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Main tick handler                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   RollServerDay();

   //--- circuit breaker 1: floating drawdown against balance
   if(CheckDrawdownBreaker())
      return;

   //--- basket housekeeping first, so exits always get priority over entries
   DetectCycleClose();
   SyncBasketTakeProfit();

   if(UseTrailingStop)
      TrailPositions();

   //--- circuit breaker 2: daily profit target
   if(CheckDailyTarget())
      return;

   ManageEntries();
}

//+------------------------------------------------------------------+
//| Entries: open a new cycle, or add a grid layer to the active one |
//+------------------------------------------------------------------+
void ManageEntries()
{
   if(g_haltedByDrawdown || g_haltedForDay)
      return;

   int cnt; double vol, wavg, profit, lastEntry; int dir;
   BasketStats(cnt, vol, wavg, profit, dir, lastEntry);

   //--- no basket: start a new cycle at the recovery-scaled base lot
   if(cnt == 0)
   {
      //--- new cycles only inside the session window; an already-open basket
      //--- is still allowed to layer so it can work its way out
      if(!InTradingWindow())
         return;

      g_cycleBaseLot = NormalizeVolume(InitialLotSize * MathPow(MartingaleMultiplier, g_recoveryLevel));

      ENUM_ORDER_TYPE type = EntryDirection();
      double sl = 0, tp = 0;
      ComputeInitialStops(type, g_cycleBaseLot, sl, tp);

      if(SendMarketOrder(type, g_cycleBaseLot, sl, tp, "TREMOR cycle R" + IntegerToString(g_recoveryLevel)))
      {
         g_cycleActive = true;
         g_cycleStart  = TimeCurrent();
      }
      return;
   }

   //--- existing basket: add a layer only on an adverse move of DistanceForPending
   if(cnt >= MaxSimultaneousPositions)
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   bool adverseMoveReached = false;
   if(dir > 0)
      adverseMoveReached = (lastEntry - ask) >= DistanceForPending;
   else
      adverseMoveReached = (bid - lastEntry) >= DistanceForPending;

   if(!adverseMoveReached)
      return;

   //--- every layer inside a sequence keeps the same fixed base lot
   ENUM_ORDER_TYPE type = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double sl = 0, tp = 0;
   ComputeInitialStops(type, g_cycleBaseLot, sl, tp);

   SendMarketOrder(type, g_cycleBaseLot, sl, tp, "TREMOR grid " + IntegerToString(cnt + 1));
}

//+------------------------------------------------------------------+
//| Entry direction - last completed bar's body                      |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE EntryDirection()
{
   double o = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double c = iClose(_Symbol, PERIOD_CURRENT, 1);
   return (c >= o) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
}

//+------------------------------------------------------------------+
//| Per-trade stops, sized in account currency                       |
//+------------------------------------------------------------------+
void ComputeInitialStops(const ENUM_ORDER_TYPE type, const double lots, double &sl, double &tp)
{
   double entry = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double slDist = MoneyToPriceDistance(StopLossPerTrade,   lots);
   double tpDist = MoneyToPriceDistance(TakeProfitPerTrade, lots);

   double minDist = MathMax(g_stopsLevel, g_point);
   if(slDist > 0) slDist = MathMax(slDist, minDist);
   if(tpDist > 0) tpDist = MathMax(tpDist, minDist);

   if(type == ORDER_TYPE_BUY)
   {
      sl = (slDist > 0) ? NormalizeDouble(entry - slDist, g_digits) : 0;
      tp = (tpDist > 0) ? NormalizeDouble(entry + tpDist, g_digits) : 0;
   }
   else
   {
      sl = (slDist > 0) ? NormalizeDouble(entry + slDist, g_digits) : 0;
      tp = (tpDist > 0) ? NormalizeDouble(entry - tpDist, g_digits) : 0;
   }
}

//+------------------------------------------------------------------+
//| Unified basket take profit                                       |
//|                                                                  |
//| Solves for the price at which the whole basket is worth the      |
//| target, then writes that price to every position's TP.           |
//+------------------------------------------------------------------+
void SyncBasketTakeProfit()
{
   int cnt; double vol, wavg, profit, lastEntry; int dir;
   BasketStats(cnt, vol, wavg, profit, dir, lastEntry);

   if(cnt == 0 || vol <= 0)
      return;

   //--- a lone position uses the per-trade target; a real basket uses the basket target
   double targetMoney = (cnt == 1) ? TakeProfitPerTrade : ProfitTargetInDollars;

   //--- swap and commission already accrued must be earned back on top
   double costs = BasketCosts();
   double needed = targetMoney - costs;

   double dist = MoneyToPriceDistance(needed, vol);
   double targetPrice = (dir > 0) ? wavg + dist : wavg - dist;
   targetPrice = NormalizeDouble(targetPrice, g_digits);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- respect the broker's minimum distance from the live price
   double minDist = MathMax(g_stopsLevel, g_point);
   if(dir > 0 && targetPrice < bid + minDist) targetPrice = NormalizeDouble(bid + minDist, g_digits);
   if(dir < 0 && targetPrice > ask - minDist) targetPrice = NormalizeDouble(ask - minDist, g_digits);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posinfo.SelectByIndex(i))                continue;
      if(posinfo.Symbol() != _Symbol)              continue;
      if(posinfo.Magic()  != MagicNumber)          continue;

      double curTp = posinfo.TakeProfit();
      double curSl = posinfo.StopLoss();

      if(MathAbs(curTp - targetPrice) < g_point * 0.5)
         continue;

      //--- do not fight the freeze level
      double ref = (posinfo.PositionType() == POSITION_TYPE_BUY) ? bid : ask;
      if(g_freezeLevel > 0 && MathAbs(targetPrice - ref) < g_freezeLevel)
         continue;

      if(!trade.PositionModify(posinfo.Ticket(), curSl, targetPrice))
         LogTradeFailure("PositionModify(TP)", posinfo.Ticket());
   }
}

//+------------------------------------------------------------------+
//| Trailing stop, per position, once it has earned TakeProfitPerTrade|
//+------------------------------------------------------------------+
void TrailPositions()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minDist = MathMax(g_stopsLevel, g_point);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posinfo.SelectByIndex(i))       continue;
      if(posinfo.Symbol() != _Symbol)     continue;
      if(posinfo.Magic()  != MagicNumber) continue;

      double lots  = posinfo.Volume();
      double open  = posinfo.PriceOpen();
      double curSl = posinfo.StopLoss();
      double curTp = posinfo.TakeProfit();

      double armDist   = MoneyToPriceDistance(TakeProfitPerTrade, lots);
      double trailDist = MathMax(MoneyToPriceDistance(DistanceForPending, lots), minDist);

      if(posinfo.PositionType() == POSITION_TYPE_BUY)
      {
         if((bid - open) < armDist) continue;

         double newSl = NormalizeDouble(bid - trailDist, g_digits);
         if(newSl <= open) continue;                       // never trail below entry
         if(curSl > 0 && newSl <= curSl) continue;         // never loosen
         if((bid - newSl) < minDist) continue;

         if(!trade.PositionModify(posinfo.Ticket(), newSl, curTp))
            LogTradeFailure("PositionModify(trail buy)", posinfo.Ticket());
      }
      else
      {
         if((open - ask) < armDist) continue;

         double newSl = NormalizeDouble(ask + trailDist, g_digits);
         if(newSl >= open) continue;
         if(curSl > 0 && newSl >= curSl) continue;
         if((newSl - ask) < minDist) continue;

         if(!trade.PositionModify(posinfo.Ticket(), newSl, curTp))
            LogTradeFailure("PositionModify(trail sell)", posinfo.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
//| Recovery bookkeeping - runs when a cycle finishes                |
//+------------------------------------------------------------------+
void DetectCycleClose()
{
   if(!g_cycleActive)
      return;

   if(CountPositions() > 0)
      return;

   //--- the basket just went flat: settle the cycle's realised result
   double netPL = RealizedProfit(g_cycleStart - 1, TimeCurrent() + 1);

   if(netPL <= -LossToTriggerRecovery)
   {
      if(g_recoveryLevel < MaxRecoveryAttempts)
         g_recoveryLevel++;
      PrintFormat("TREMOR: cycle closed at %.2f - recovery level now %d", netPL, g_recoveryLevel);
   }
   else if(netPL > 0)
   {
      if(g_recoveryLevel != 0)
         PrintFormat("TREMOR: recovery cycle closed at +%.2f - resetting to base lot", netPL);
      g_recoveryLevel = 0;
   }
   else
   {
      PrintFormat("TREMOR: cycle closed at %.2f - below recovery trigger, level unchanged (%d)",
                  netPL, g_recoveryLevel);
   }

   g_cycleBaseLot = NormalizeVolume(InitialLotSize * MathPow(MartingaleMultiplier, g_recoveryLevel));
   g_cycleActive  = false;
   g_cycleStart   = 0;
}

//+------------------------------------------------------------------+
//| Circuit breaker 1 - floating drawdown vs balance                 |
//+------------------------------------------------------------------+
bool CheckDrawdownBreaker()
{
   if(g_haltedByDrawdown)
      return(true);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(balance <= 0)
      return(false);

   double drawdown = balance - equity;
   double limit    = balance * MaxLossPercentOfBalance / 100.0;

   if(drawdown >= limit)
   {
      PrintFormat("TREMOR: drawdown breaker tripped - DD %.2f >= limit %.2f. Closing all and halting.",
                  drawdown, limit);
      CloseAllPositions();
      g_haltedByDrawdown = true;
      UpdateDashboard();
      return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Circuit breaker 2 - daily closed profit target                   |
//+------------------------------------------------------------------+
bool CheckDailyTarget()
{
   g_dailyClosed = RealizedProfit(g_dayStart, TimeCurrent() + 1);

   if(g_dailyClosed >= DailyProfitTarget)
   {
      if(!g_haltedForDay)
         PrintFormat("TREMOR: daily target reached (%.2f) - no new entries until next server day",
                     g_dailyClosed);
      g_haltedForDay = true;
      return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Server day rollover                                              |
//+------------------------------------------------------------------+
void RollServerDay()
{
   datetime today = ServerDayStart();
   if(today != g_dayStart)
   {
      g_dayStart     = today;
      g_haltedForDay = false;
      g_dailyClosed  = 0;
      Print("TREMOR: new server day - daily counters reset");
   }
}

//+------------------------------------------------------------------+
//| Session window - broker server time, 15 minute resolution        |
//+------------------------------------------------------------------+
bool InTradingWindow()
{
   //--- either end set to Inactive disables the filter entirely
   if(SessionStart == Inactive || SessionEnd == Inactive)
      return(true);

   int s = (int)SessionStart;
   int e = (int)SessionEnd;

   if(s == e)
      return(true);

   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   int now = t.hour * 60 + t.min;

   if(s < e)
      return(now >= s && now < e);      // same day

   return(now >= s || now < e);         // wraps midnight
}

string TimeLabel(const int minutes)
{
   if(minutes < 0) return("--:--");
   return(StringFormat("%02d:%02d", minutes / 60, minutes % 60));
}

datetime ServerDayStart()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   t.hour = 0; t.min = 0; t.sec = 0;
   return(StructToTime(t));
}

//+------------------------------------------------------------------+
//| Realised P/L for this EA between two times (profit+swap+comm)    |
//+------------------------------------------------------------------+
double RealizedProfit(const datetime from, const datetime to)
{
   if(!HistorySelect(from, to))
      return(0);

   double total = 0;
   int deals = HistoryDealsTotal();

   for(int i = 0; i < deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)     continue;

      total += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      total += HistoryDealGetDouble(ticket, DEAL_SWAP);
      total += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   }
   return(total);
}

//+------------------------------------------------------------------+
//| Basket aggregation                                               |
//+------------------------------------------------------------------+
void BasketStats(int &cnt, double &vol, double &wavgEntry, double &profit,
                 int &dir, double &lastEntry)
{
   cnt = 0; vol = 0; wavgEntry = 0; profit = 0; dir = 0; lastEntry = 0;

   double priceVolSum = 0;
   datetime newest = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posinfo.SelectByIndex(i))       continue;
      if(posinfo.Symbol() != _Symbol)     continue;
      if(posinfo.Magic()  != MagicNumber) continue;

      double v = posinfo.Volume();
      double p = posinfo.PriceOpen();

      cnt++;
      vol          += v;
      priceVolSum  += p * v;
      profit       += posinfo.Profit() + posinfo.Swap() + posinfo.Commission();

      if(dir == 0)
         dir = (posinfo.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;

      datetime t = (datetime)posinfo.Time();
      if(t >= newest) { newest = t; lastEntry = p; }
   }

   if(vol > 0)
      wavgEntry = priceVolSum / vol;
}

double BasketCosts()
{
   double costs = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posinfo.SelectByIndex(i))       continue;
      if(posinfo.Symbol() != _Symbol)     continue;
      if(posinfo.Magic()  != MagicNumber) continue;
      costs += posinfo.Swap() + posinfo.Commission();
   }
   return(costs);
}

int CountPositions()
{
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posinfo.SelectByIndex(i))       continue;
      if(posinfo.Symbol() != _Symbol)     continue;
      if(posinfo.Magic()  != MagicNumber) continue;
      cnt++;
   }
   return(cnt);
}

datetime EarliestPositionTime()
{
   datetime earliest = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posinfo.SelectByIndex(i))       continue;
      if(posinfo.Symbol() != _Symbol)     continue;
      if(posinfo.Magic()  != MagicNumber) continue;

      datetime t = (datetime)posinfo.Time();
      if(earliest == 0 || t < earliest) earliest = t;
   }
   return(earliest == 0 ? TimeCurrent() : earliest);
}

//+------------------------------------------------------------------+
//| Money <-> price conversion for a given volume                    |
//+------------------------------------------------------------------+
double MoneyToPriceDistance(const double money, const double lots)
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue <= 0 || tickSize <= 0 || lots <= 0)
      return(0);

   double valuePerPriceUnit = lots * tickValue / tickSize;   // account currency per 1.0 of price
   if(valuePerPriceUnit <= 0)
      return(0);

   return(money / valuePerPriceUnit);
}

double PriceDistanceToMoney(const double dist, const double lots)
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue <= 0 || tickSize <= 0 || lots <= 0)
      return(0);

   return(dist * lots * tickValue / tickSize);
}

//+------------------------------------------------------------------+
//| Volume normalisation                                             |
//+------------------------------------------------------------------+
double NormalizeVolume(const double v)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mn   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(step <= 0) step = 0.01;

   double out = MathRound(v / step) * step;
   out = MathMax(mn, MathMin(mx, out));

   int decimals = (int)MathMax(0, MathCeil(-MathLog10(step)));
   return(NormalizeDouble(out, decimals));
}

//+------------------------------------------------------------------+
//| Market order with retry on transient failures                    |
//+------------------------------------------------------------------+
bool SendMarketOrder(const ENUM_ORDER_TYPE type, const double lots,
                     double sl, double tp, const string comment)
{
   double vol = NormalizeVolume(lots);
   if(vol <= 0)
   {
      Print("TREMOR: volume normalised to zero, order skipped");
      return(false);
   }

   //--- margin check before we bother the server
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double marginRequired = 0;
   if(OrderCalcMargin(type, _Symbol, vol, price, marginRequired))
   {
      if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) <= marginRequired)
      {
         PrintFormat("TREMOR: insufficient free margin (need %.2f, have %.2f) - order skipped",
                     marginRequired, AccountInfoDouble(ACCOUNT_MARGIN_FREE));
         return(false);
      }
   }

   for(int attempt = 1; attempt <= 3; attempt++)
   {
      bool ok = (type == ORDER_TYPE_BUY)
                ? trade.Buy(vol, _Symbol, 0.0, sl, tp, comment)
                : trade.Sell(vol, _Symbol, 0.0, sl, tp, comment);

      uint rc = trade.ResultRetcode();

      if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED ||
                rc == TRADE_RETCODE_DONE_PARTIAL))
         return(true);

      switch(rc)
      {
         case TRADE_RETCODE_REQUOTE:
         case TRADE_RETCODE_PRICE_CHANGED:
         case TRADE_RETCODE_PRICE_OFF:
         case TRADE_RETCODE_CONNECTION:
            PrintFormat("TREMOR: transient send failure (%u %s), attempt %d/3",
                        rc, trade.ResultRetcodeDescription(), attempt);
            Sleep(150);
            continue;

         case TRADE_RETCODE_INVALID_STOPS:
            //--- retry bare, then attach stops once we know the fill price
            PrintFormat("TREMOR: broker rejected stops (sl=%.*f tp=%.*f), retrying without them",
                        g_digits, sl, g_digits, tp);
            sl = 0; tp = 0;
            continue;

         case TRADE_RETCODE_INVALID_VOLUME:
         case TRADE_RETCODE_NO_MONEY:
         case TRADE_RETCODE_TRADE_DISABLED:
         case TRADE_RETCODE_MARKET_CLOSED:
            PrintFormat("TREMOR: order rejected, not retryable (%u %s)",
                        rc, trade.ResultRetcodeDescription());
            return(false);

         default:
            PrintFormat("TREMOR: order failed (%u %s), attempt %d/3",
                        rc, trade.ResultRetcodeDescription(), attempt);
            Sleep(150);
            continue;
      }
   }

   Print("TREMOR: order abandoned after 3 attempts");
   return(false);
}

//+------------------------------------------------------------------+
//| Close every position belonging to this EA                        |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int pass = 0; pass < 3; pass++)
   {
      bool anyLeft = false;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!posinfo.SelectByIndex(i))       continue;
         if(posinfo.Symbol() != _Symbol)     continue;
         if(posinfo.Magic()  != MagicNumber) continue;

         anyLeft = true;
         if(!trade.PositionClose(posinfo.Ticket(), g_slippage))
            LogTradeFailure("PositionClose", posinfo.Ticket());
      }

      if(!anyLeft) return;
      Sleep(150);
   }
}

void LogTradeFailure(const string what, const ulong ticket)
{
   PrintFormat("TREMOR: %s failed on #%I64u - %u %s",
               what, ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void MakeLabel(const string name, const int x, const int y, const int size,
               const color clr, const string font = "Consolas")
{
   string obj = g_dashPrefix + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, obj, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE,   size);
   ObjectSetInteger(0, obj, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, obj, OBJPROP_BACK,       false);
   ObjectSetString (0, obj, OBJPROP_FONT,       font);
   ObjectSetString (0, obj, OBJPROP_TEXT,       "");
}

void CreateDashboard()
{
   string bg = g_dashPrefix + "BG";
   if(ObjectFind(0, bg) < 0)
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);

   ObjectSetInteger(0, bg, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE,  10);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE,  20);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE,      290);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE,      232);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR,    C'22,26,32');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR,      C'70,78,90');
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, bg, OBJPROP_BACK,       false);

   MakeLabel("Title",   22,  30, 11, C'235,240,245', "Arial Bold");
   MakeLabel("Bal",     22,  56,  9, C'175,185,195');
   MakeLabel("Eq",      22,  74,  9, C'175,185,195');
   MakeLabel("DD",      22,  92,  9, C'175,185,195');
   MakeLabel("Float",   22, 110,  9, C'175,185,195');
   MakeLabel("Pos",     22, 128,  9, C'175,185,195');
   MakeLabel("Rec",     22, 146,  9, C'175,185,195');
   MakeLabel("Lot",     22, 164,  9, C'175,185,195');
   MakeLabel("Daily",   22, 182,  9, C'175,185,195');
   MakeLabel("Sess",    22, 200,  9, C'175,185,195');
   MakeLabel("Status",  22, 222,  9, C'235,240,245');
}

void SetLabel(const string name, const string text, const color clr)
{
   string obj = g_dashPrefix + name;
   ObjectSetString (0, obj, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
}

void UpdateDashboard()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd      = balance - equity;
   double ddLimit = balance * MaxLossPercentOfBalance / 100.0;

   int cnt; double vol, wavg, profit, lastEntry; int dir;
   BasketStats(cnt, vol, wavg, profit, dir, lastEntry);

   color neutral = C'175,185,195';
   color good    = C'110,200,130';
   color bad     = C'230,110,110';
   color warn    = C'235,190,90';

   SetLabel("Title", "TREMOR  GRID  RECOVERY", C'235,240,245');
   SetLabel("Bal",   StringFormat("Balance      %10.2f", balance), neutral);
   SetLabel("Eq",    StringFormat("Equity       %10.2f", equity),  neutral);
   SetLabel("DD",    StringFormat("Drawdown     %10.2f  / %.2f", (dd > 0 ? dd : 0), ddLimit),
            (dd >= ddLimit * 0.5 ? bad : neutral));
   SetLabel("Float", StringFormat("Floating P/L %10.2f", profit),
            (profit >= 0 ? good : bad));
   SetLabel("Pos",   StringFormat("Positions    %10d  / %d", cnt, MaxSimultaneousPositions),
            neutral);
   SetLabel("Rec",   StringFormat("Recovery lvl %10d  / %d", g_recoveryLevel, MaxRecoveryAttempts),
            (g_recoveryLevel > 0 ? warn : good));
   SetLabel("Lot",   StringFormat("Base lot     %10.2f", g_cycleBaseLot),
            (g_recoveryLevel > 0 ? warn : neutral));
   SetLabel("Daily", StringFormat("Closed today %10.2f  / %.2f", g_dailyClosed, DailyProfitTarget),
            (g_dailyClosed >= 0 ? good : bad));

   bool filterOn = (SessionStart != Inactive && SessionEnd != Inactive);
   bool inWindow = InTradingWindow();

   if(filterOn)
      SetLabel("Sess", StringFormat("Session      %s - %s  [%s]",
               TimeLabel((int)SessionStart), TimeLabel((int)SessionEnd),
               inWindow ? "OPEN" : "SHUT"),
               inWindow ? good : warn);
   else
      SetLabel("Sess", "Session           inactive (24h)", neutral);

   string status = "TRADING";
   color  sclr   = good;

   if(g_haltedByDrawdown)      { status = "HALTED - DRAWDOWN BREAKER"; sclr = bad;  }
   else if(g_haltedForDay)     { status = "HALTED - DAILY TARGET MET"; sclr = warn; }
   else if(cnt > 0)            { status = StringFormat("IN BASKET (%s)", dir > 0 ? "BUY" : "SELL"); sclr = neutral; }
   else if(filterOn && !inWindow) { status = "WAITING - OUTSIDE SESSION"; sclr = warn; }

   SetLabel("Status", status, sclr);
   ChartRedraw(0);
}

void DeleteDashboard()
{
   ObjectsDeleteAll(0, g_dashPrefix);
}
//+------------------------------------------------------------------+
