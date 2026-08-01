//+------------------------------------------------------------------+
//|                                            PropFirm_Sentinel.mq5 |
//|  Session breakout EA purpose-built for prop-firm challenges.     |
//|                                                                  |
//|  Combines the strongest ideas from the Mr Capfree video library: |
//|   - Swing high/low stop-order breakout core (scalping robot)     |
//|   - ATR-based distances so one profile works on FX/gold/BTC/     |
//|     indices (revert-to-mean / Wayward EAs)                       |
//|   - Partial close at TP1 + break-even move (3-EMA strategy)      |
//|   - Prop-safe trailing modes: step / previous candle / fast MA / |
//|     Ichimoku tenkan, with broker min-stop + freeze-level checks  |
//|     and a minimum-modify step (prop-firm scalper version)        |
//|   - Equity-high based drawdown guardian: daily / weekly / total  |
//|     with auto-pause + optional close-all, profit-target lock     |
//|     (prop-firm scalper version)                                  |
//|   - News / RSI-extreme / MA-distance / day-of-week filters       |
//|     (scalping robot part 3)                                      |
//|   - Pending-order expiry, day-start safety sweep and orphan-TP   |
//|     repair (ICT Silver Bullet lessons 9.1/9.2)                   |
//|   - Challenge stats panel drawn with lightweight chart objects   |
//|                                                                  |
//|  One chart = one symbol. Attach to each symbol you want traded.  |
//+------------------------------------------------------------------+
#property copyright "Built with Claude for wairemichael"
#property version   "1.00"
#property description "Prop-firm session breakout EA with drawdown guardian, partial TP,"
#property description "prop-safe trailing and news/RSI/MA filters."

#include <Trade\Trade.mqh>

//--- trade objects
CTrade         trade;
CPositionInfo  posInfo;
COrderInfo     ordInfo;

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_LOT_MODE
  {
   LOT_FIXED          = 0,  // Fixed lots
   LOT_PCT_BALANCE    = 1,  // % of balance
   LOT_PCT_EQUITY     = 2,  // % of equity
   LOT_PCT_FREEMARGIN = 3   // % of free margin
  };

enum ENUM_TRAIL_MODE
  {
   TRAIL_NONE         = 0,  // No trailing (fixed TP only)
   TRAIL_STEP         = 1,  // Step trail (ATR distance)
   TRAIL_PREV_CANDLE  = 2,  // Previous candle low/high
   TRAIL_FAST_MA      = 3,  // Fast moving average
   TRAIL_TENKAN       = 4   // Ichimoku tenkan-sen
  };

enum ENUM_DD_ACTION
  {
   DD_PAUSE_ONLY      = 0,  // Pause new trading only
   DD_CLOSE_AND_PAUSE = 1   // Close everything and pause
  };

enum ENUM_TOTALDD_MODE
  {
   TOTALDD_STATIC     = 0,  // Static (vs initial balance)
   TOTALDD_TRAILING   = 1   // Trailing (vs equity high)
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== General ==="
input long              InpMagic             = 20260707;      // Magic number
input int               InpSlippagePoints    = 10;            // Max slippage (points)
input string            InpTradeComment      = "PropSentinel";// Trade comment

input group "=== Session (broker/server time) ==="
input int               InpStartHour         = 10;            // Entry window start hour
input int               InpStartMinute       = 0;             // Entry window start minute
input int               InpEndHour           = 20;            // Entry window end hour
input int               InpEndMinute         = 0;             // Entry window end minute
input bool              InpCloseAtSessionEnd = true;          // Close positions at session end
input int               InpFridayCloseHour   = 21;            // Friday flat hour (0 = off)

input group "=== Strategy: swing breakout ==="
input int               InpBarsN             = 24;            // Swing strength (candles each side)
input int               InpLookbackBars      = 500;           // Max bars to search for swing
input int               InpATRPeriod         = 96;            // ATR period (smoothed distances)
input double            InpEntryBufferATR    = 0.10;          // Entry buffer beyond swing (x ATR)
input double            InpSL_ATR            = 1.00;          // Stop-loss distance (x ATR)
input double            InpTP_RR             = 2.00;          // Final take-profit (R multiple)
input int               InpOrderExpiryBars   = 12;            // Pending order expiry (bars)
input bool              InpCancelOpposite    = true;          // Cancel opposite order on fill
input double            InpMaxSpreadATRPct   = 10.0;          // Max spread as % of ATR (0 = off)
input int               InpMaxSpreadPoints   = 0;             // Max spread absolute points (0 = off)

input group "=== Partial TP + break-even ==="
input bool              InpUsePartial        = true;          // Close partial at TP1 + move to BE
input double            InpTP1_RR            = 1.00;          // TP1 level (R multiple)
input double            InpPartialPct        = 50.0;          // % of volume closed at TP1
input int               InpBEBufferPoints    = 5;             // BE buffer (covers commission)

input group "=== Trailing (prop-safe) ==="
input ENUM_TRAIL_MODE   InpTrailMode         = TRAIL_PREV_CANDLE; // Trailing mode
input double            InpTrailStartRR      = 1.00;          // Start trailing after (R multiple)
input double            InpTrailATR          = 0.50;          // Step-trail distance (x ATR)
input int               InpTrailPrevCandles  = 2;             // Previous candle shift for trail
input int               InpTrailMAPeriod     = 20;            // Fast MA period for trail
input int               InpMinModifyPoints   = 10;            // Min SL improvement to modify (points)

input group "=== Money management ==="
input ENUM_LOT_MODE     InpLotMode           = LOT_PCT_BALANCE; // Lot sizing mode
input double            InpRiskPercent       = 0.75;          // Risk per trade (%)
input double            InpFixedLots         = 0.10;          // Fixed lots (if fixed mode)

input group "=== Prop-firm rules ==="
input double            InpChallengeBalance  = 0.0;           // Challenge start balance (0 = auto)
input datetime          InpChallengeStart    = D'2026.07.01'; // Challenge start date (panel info)
input double            InpProfitTargetPct   = 8.0;           // Profit target % (0 = off)
input bool              InpCloseAllAtTarget  = true;          // Close everything at target
input double            InpMaxDailyDDPct     = 3.5;           // Max daily drawdown % (safety < firm limit)
input double            InpMaxWeeklyDDPct    = 0.0;           // Max weekly drawdown % (0 = off)
input double            InpMaxTotalDDPct     = 7.0;           // Max total drawdown % (safety < firm limit)
input ENUM_TOTALDD_MODE InpTotalDDMode       = TOTALDD_STATIC;// Total DD measured
input ENUM_DD_ACTION    InpDDAction          = DD_CLOSE_AND_PAUSE; // Action on drawdown breach
input int               InpMaxTradesPerDay   = 4;             // Max entries per day this symbol (0 = off)

input group "=== Filter: days allowed ==="
input bool              InpTradeMonday       = true;          // Trade Monday
input bool              InpTradeTuesday      = true;          // Trade Tuesday
input bool              InpTradeWednesday    = true;          // Trade Wednesday
input bool              InpTradeThursday     = true;          // Trade Thursday
input bool              InpTradeFriday       = true;          // Trade Friday
input bool              InpTradeSaturday     = false;         // Trade Saturday
input bool              InpTradeSunday       = false;         // Trade Sunday

input group "=== Filter: RSI extreme (higher TF) ==="
input bool              InpUseRSIFilter      = true;          // Use RSI extreme filter
input ENUM_TIMEFRAMES   InpRSITimeframe      = PERIOD_H4;     // RSI timeframe
input int               InpRSIPeriod         = 14;            // RSI period
input double            InpRSIUpper          = 80.0;          // Block above
input double            InpRSILower          = 20.0;          // Block below

input group "=== Filter: MA distance (higher TF) ==="
input bool              InpUseMAFilter       = false;         // Use MA distance filter
input ENUM_TIMEFRAMES   InpMATimeframe       = PERIOD_H4;     // MA timeframe
input int               InpMAPeriod          = 200;           // MA period (EMA)
input double            InpMaxDistPct        = 3.0;           // Block if price further than % from MA

input group "=== Filter: news (live only, not tester) ==="
input bool              InpUseNewsFilter     = true;          // Use news filter
input string            InpNewsKeywords      = "Nonfarm,NFP,Interest Rate,FOMC,CPI,GDP,Powell"; // Keywords (comma separated)
input string            InpNewsCurrencies    = "USD,EUR";     // Currencies (comma separated)
input int               InpStopBeforeMin     = 30;            // Stop minutes before news
input int               InpResumeAfterMin    = 30;            // Resume minutes after news
input int               InpNewsLookupDays    = 7;             // Calendar lookup days

input group "=== Panel / chart ==="
input bool              InpShowPanel         = true;          // Show challenge panel
input int               InpPanelFontSize     = 9;             // Panel font size
input bool              InpColorChart        = true;          // Color chart by status
input color             InpColorActive       = clrBlack;      // Chart color: trading
input color             InpColorPaused       = C'45,10,10';   // Chart color: paused/breach
input color             InpColorTarget       = C'10,45,10';   // Chart color: target reached

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
int      g_hATR      = INVALID_HANDLE;
int      g_hRSI      = INVALID_HANDLE;
int      g_hMA       = INVALID_HANDLE;
int      g_hTrailMA  = INVALID_HANDLE;
int      g_hIchimoku = INVALID_HANDLE;

//--- prop state
double   g_baseBalance    = 0.0;
double   g_overallHigh    = 0.0;
datetime g_dayDate        = 0;
double   g_dayStartEquity = 0.0;
double   g_dayStartBal    = 0.0;
double   g_dayHigh        = 0.0;
datetime g_weekMonday     = 0;
double   g_weekStartEq    = 0.0;
double   g_weekHigh       = 0.0;
datetime g_pausedUntil    = 0;
bool     g_hardStop       = false;
string   g_stopReason     = "";
string   g_status         = "starting";
string   g_lastPrinted    = "";
bool     g_ui             = false;

#define PANEL_PREFIX "PFS_"
#define SECONDS_DAY  86400

//+------------------------------------------------------------------+
//| Persistence helpers (terminal global variables)                  |
//+------------------------------------------------------------------+
string GVKey(const string name) { return StringFormat("PFS_%I64d_%s", InpMagic, name); }

void SaveState()
  {
   GlobalVariableSet(GVKey("base"),        g_baseBalance);
   GlobalVariableSet(GVKey("overallHigh"), g_overallHigh);
   GlobalVariableSet(GVKey("dayDate"),     (double)g_dayDate);
   GlobalVariableSet(GVKey("dayStartEq"),  g_dayStartEquity);
   GlobalVariableSet(GVKey("dayStartBal"), g_dayStartBal);
   GlobalVariableSet(GVKey("dayHigh"),     g_dayHigh);
   GlobalVariableSet(GVKey("weekMonday"),  (double)g_weekMonday);
   GlobalVariableSet(GVKey("weekStartEq"), g_weekStartEq);
   GlobalVariableSet(GVKey("weekHigh"),    g_weekHigh);
   GlobalVariableSet(GVKey("pausedUntil"), (double)g_pausedUntil);
   GlobalVariableSet(GVKey("hardStop"),    g_hardStop ? 1.0 : 0.0);
  }

void LoadState()
  {
   if(GlobalVariableCheck(GVKey("base")))
     {
      g_baseBalance    = GlobalVariableGet(GVKey("base"));
      g_overallHigh    = GlobalVariableGet(GVKey("overallHigh"));
      g_dayDate        = (datetime)GlobalVariableGet(GVKey("dayDate"));
      g_dayStartEquity = GlobalVariableGet(GVKey("dayStartEq"));
      g_dayStartBal    = GlobalVariableGet(GVKey("dayStartBal"));
      g_dayHigh        = GlobalVariableGet(GVKey("dayHigh"));
      g_weekMonday     = (datetime)GlobalVariableGet(GVKey("weekMonday"));
      g_weekStartEq    = GlobalVariableGet(GVKey("weekStartEq"));
      g_weekHigh       = GlobalVariableGet(GVKey("weekHigh"));
      g_pausedUntil    = (datetime)GlobalVariableGet(GVKey("pausedUntil"));
      g_hardStop       = (GlobalVariableGet(GVKey("hardStop")) > 0.5);
      if(g_hardStop) g_stopReason = "restored hard-stop (restart EA with new magic to reset)";
     }
  }

//+------------------------------------------------------------------+
//| Small helpers                                                    |
//+------------------------------------------------------------------+
double Pt()  { return SymbolInfoDouble(_Symbol, SYMBOL_POINT); }

double MinStopDistance()
  {
   long stops  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return MathMax((double)MathMax(stops, freeze) * Pt(), spread) + Pt();
  }

double GetATR()
  {
   double b[1];
   if(CopyBuffer(g_hATR, 0, 1, 1, b) < 1) return 0.0;
   return b[0];
  }

bool IsNewBar()
  {
   static datetime prevTime = 0;
   datetime cur = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(cur != prevTime) { prevTime = cur; return true; }
   return false;
  }

void StatusPrint(const string msg)
  {
   if(msg != g_lastPrinted) { Print(msg); g_lastPrinted = msg; }
  }

//+------------------------------------------------------------------+
//| Position / order census                                          |
//+------------------------------------------------------------------+
int CountOurPositions()
  {
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic) cnt++;
   return cnt;
  }

int CountOurOrders()
  {
   int cnt = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(ordInfo.SelectByIndex(i))
         if(ordInfo.Symbol() == _Symbol && ordInfo.Magic() == InpMagic) cnt++;
   return cnt;
  }

void DeleteAllPendings()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(ordInfo.SelectByIndex(i))
         if(ordInfo.Symbol() == _Symbol && ordInfo.Magic() == InpMagic)
            trade.OrderDelete(ordInfo.Ticket());
  }

void CloseAllPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic)
            trade.PositionClose(posInfo.Ticket());
  }

int TradesOpenedToday()
  {
   if(g_dayDate == 0) return 0;
   if(!HistorySelect(g_dayDate, TimeCurrent() + 60)) return 0;
   int cnt = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      if(HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetString(t, DEAL_SYMBOL) != _Symbol)  continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_IN) cnt++;
     }
   return cnt;
  }

//+------------------------------------------------------------------+
//| Prop-firm state tracking                                         |
//+------------------------------------------------------------------+
void UpdatePropState()
  {
   datetime now   = TimeCurrent();
   datetime today = now - (now % SECONDS_DAY);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);

   if(g_dayDate != today)
     {
      g_dayDate        = today;
      g_dayStartEquity = eq;
      g_dayStartBal    = bal;
      g_dayHigh        = eq;
      MqlDateTime st;
      TimeToStruct(now, st);
      datetime monday = today - ((st.day_of_week + 6) % 7) * SECONDS_DAY;
      if(monday != g_weekMonday)
        {
         g_weekMonday  = monday;
         g_weekStartEq = eq;
         g_weekHigh    = eq;
        }
      // day-start safety sweep: kill any pending left over from yesterday
      DeleteAllPendings();
      SaveState();
     }
   if(eq > g_dayHigh)     g_dayHigh     = eq;
   if(eq > g_weekHigh)    g_weekHigh    = eq;
   if(eq > g_overallHigh) { g_overallHigh = eq; SaveState(); }
  }

double DailyDDPct()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double anchor = MathMax(g_dayStartBal, MathMax(g_dayStartEquity, g_dayHigh));
   return (anchor - eq) / g_baseBalance * 100.0;
  }

double WeeklyDDPct()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double anchor = MathMax(g_weekStartEq, g_weekHigh);
   return (anchor - eq) / g_baseBalance * 100.0;
  }

double TotalDDPct()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double anchor = (InpTotalDDMode == TOTALDD_TRAILING) ? g_overallHigh
                                                        : MathMax(g_baseBalance, 0.0);
   return (anchor - eq) / g_baseBalance * 100.0;
  }

double ProfitPct()
  {
   return (AccountInfoDouble(ACCOUNT_EQUITY) - g_baseBalance) / g_baseBalance * 100.0;
  }

void CheckPropLimits()
  {
   if(g_hardStop) return;
   datetime now = TimeCurrent();

   // profit target: lock the challenge in
   if(InpProfitTargetPct > 0 && ProfitPct() >= InpProfitTargetPct)
     {
      g_hardStop  = true;
      g_stopReason = StringFormat("PROFIT TARGET %.1f%% REACHED - trading locked", InpProfitTargetPct);
      if(InpCloseAllAtTarget) { CloseAllPositions(); DeleteAllPendings(); }
      StatusPrint(g_stopReason);
      SaveState();
      return;
     }
   // total drawdown
   if(InpMaxTotalDDPct > 0 && TotalDDPct() >= InpMaxTotalDDPct)
     {
      g_hardStop  = true;
      g_stopReason = StringFormat("TOTAL DRAWDOWN BREACH %.2f%% >= %.2f%%", TotalDDPct(), InpMaxTotalDDPct);
      if(InpDDAction == DD_CLOSE_AND_PAUSE) { CloseAllPositions(); DeleteAllPendings(); }
      StatusPrint(g_stopReason);
      SaveState();
      return;
     }
   // daily drawdown -> pause until next server day
   if(now >= g_pausedUntil && InpMaxDailyDDPct > 0 && DailyDDPct() >= InpMaxDailyDDPct)
     {
      g_pausedUntil = g_dayDate + SECONDS_DAY;
      if(InpDDAction == DD_CLOSE_AND_PAUSE) { CloseAllPositions(); DeleteAllPendings(); }
      StatusPrint(StringFormat("DAILY DRAWDOWN BREACH %.2f%% >= %.2f%% - paused until next day",
                               DailyDDPct(), InpMaxDailyDDPct));
      SaveState();
      return;
     }
   // weekly drawdown -> pause until next Monday
   if(now >= g_pausedUntil && InpMaxWeeklyDDPct > 0 && WeeklyDDPct() >= InpMaxWeeklyDDPct)
     {
      g_pausedUntil = g_weekMonday + 7 * SECONDS_DAY;
      if(InpDDAction == DD_CLOSE_AND_PAUSE) { CloseAllPositions(); DeleteAllPendings(); }
      StatusPrint(StringFormat("WEEKLY DRAWDOWN BREACH %.2f%% >= %.2f%% - paused until Monday",
                               WeeklyDDPct(), InpMaxWeeklyDDPct));
      SaveState();
     }
  }

bool TradingAllowed()
  {
   return (!g_hardStop && TimeCurrent() >= g_pausedUntil);
  }

//+------------------------------------------------------------------+
//| Session / calendar filters                                       |
//+------------------------------------------------------------------+
bool InEntryWindow()
  {
   MqlDateTime st;
   TimeToStruct(TimeCurrent(), st);
   int nowMin   = st.hour * 60 + st.min;
   int startMin = InpStartHour * 60 + InpStartMinute;
   int endMin   = InpEndHour * 60 + InpEndMinute;
   if(startMin == endMin) return true;
   if(startMin < endMin)  return (nowMin >= startMin && nowMin < endMin);
   return (nowMin >= startMin || nowMin < endMin); // overnight window
  }

bool FridayFlatTime()
  {
   if(InpFridayCloseHour <= 0) return false;
   MqlDateTime st;
   TimeToStruct(TimeCurrent(), st);
   return (st.day_of_week == 5 && st.hour >= InpFridayCloseHour);
  }

bool DayAllowed()
  {
   MqlDateTime st;
   TimeToStruct(TimeCurrent(), st);
   switch(st.day_of_week)
     {
      case 0: return InpTradeSunday;
      case 1: return InpTradeMonday;
      case 2: return InpTradeTuesday;
      case 3: return InpTradeWednesday;
      case 4: return InpTradeThursday;
      case 5: return InpTradeFriday;
      case 6: return InpTradeSaturday;
     }
   return false;
  }

bool IsRSIExtreme()
  {
   if(!InpUseRSIFilter || g_hRSI == INVALID_HANDLE) return false;
   double b[1];
   if(CopyBuffer(g_hRSI, 0, 0, 1, b) < 1) return false;
   return (b[0] >= InpRSIUpper || b[0] <= InpRSILower);
  }

bool IsMATooFar()
  {
   if(!InpUseMAFilter || g_hMA == INVALID_HANDLE) return false;
   double b[1];
   if(CopyBuffer(g_hMA, 0, 0, 1, b) < 1) return false;
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   return (price > b[0] * (1.0 + InpMaxDistPct / 100.0) ||
           price < b[0] * (1.0 - InpMaxDistPct / 100.0));
  }

bool SpreadTooWide()
  {
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(InpMaxSpreadPoints > 0 && spread > InpMaxSpreadPoints * Pt()) return true;
   if(InpMaxSpreadATRPct > 0)
     {
      double atr = GetATR();
      if(atr > 0 && spread > atr * InpMaxSpreadATRPct / 100.0) return true;
     }
   return false;
  }

string Upper(string s) { StringToUpper(s); return s; }

bool IsNewsBlocked()
  {
   if(!InpUseNewsFilter) return false;
   if((bool)MQLInfoInteger(MQL_TESTER)) return false;   // calendar unavailable in tester

   static datetime blockUntil = 0;
   static datetime lastCheck  = 0;
   datetime now = TimeCurrent();
   if(now < blockUntil) return true;
   if(now - lastCheck < 60) return false;               // throttle calendar queries
   lastCheck = now;

   string kw[];
   int nk = StringSplit(InpNewsKeywords, ',', kw);
   if(nk <= 0) return false;
   string curList = Upper(InpNewsCurrencies);

   MqlCalendarValue vals[];
   if(!CalendarValueHistory(vals, now, now + (datetime)InpNewsLookupDays * SECONDS_DAY, NULL, NULL))
      return false;

   for(int i = 0; i < ArraySize(vals); i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id, ev)) continue;
      MqlCalendarCountry cn;
      if(!CalendarCountryById(ev.country_id, cn)) continue;
      if(StringFind(curList, Upper(cn.currency)) < 0) continue;

      string evName = Upper(ev.name);
      bool match = false;
      for(int j = 0; j < nk && !match; j++)
        {
         string k = kw[j];
         StringTrimLeft(k);
         StringTrimRight(k);
         if(StringLen(k) > 0 && StringFind(evName, Upper(k)) >= 0) match = true;
        }
      if(!match) continue;

      datetime evTime = vals[i].time;
      if(evTime - now <= (datetime)InpStopBeforeMin * 60 && evTime + (datetime)InpResumeAfterMin * 60 > now)
        {
         blockUntil = evTime + (datetime)InpResumeAfterMin * 60;
         StatusPrint("News block: " + cn.currency + " " + ev.name + " @ " + TimeToString(evTime));
         return true;
        }
      break; // values are time-ordered: first relevant event decides
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Lot sizing (with broker limits + margin check)                   |
//+------------------------------------------------------------------+
double NormalizeVolume(double vol)
  {
   double vMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(vStep <= 0) vStep = 0.01;
   vol = MathFloor(vol / vStep + 1e-9) * vStep;
   vol = MathMax(vMin, MathMin(vMax, vol));
   return NormalizeDouble(vol, 8);
  }

double CalcLots(double slDistPrice, ENUM_ORDER_TYPE dir, double refPrice)
  {
   double vMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lots = vMin;

   if(InpLotMode == LOT_FIXED)
      lots = InpFixedLots;
   else
     {
      double baseAmt = 0.0;
      switch(InpLotMode)
        {
         case LOT_PCT_BALANCE:    baseAmt = AccountInfoDouble(ACCOUNT_BALANCE);      break;
         case LOT_PCT_EQUITY:     baseAmt = AccountInfoDouble(ACCOUNT_EQUITY);       break;
         case LOT_PCT_FREEMARGIN: baseAmt = AccountInfoDouble(ACCOUNT_MARGIN_FREE);  break;
         default:                 baseAmt = AccountInfoDouble(ACCOUNT_BALANCE);      break;
        }
      double riskMoney = baseAmt * InpRiskPercent / 100.0;
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double vStep     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(tickSize <= 0 || tickValue <= 0 || vStep <= 0 || slDistPrice <= 0) return vMin;
      double moneyPerStep = slDistPrice / tickSize * tickValue * vStep;
      if(moneyPerStep <= 0) return vMin;
      lots = MathFloor(riskMoney / moneyPerStep) * vStep;
     }

   // broker volume-limit cap (open + pending)
   double vLimit = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);
   if(vLimit > 0) lots = MathMin(lots, vLimit);
   lots = NormalizeVolume(lots);

   // margin check: shrink until it fits with a 10% cushion
   double vStep2 = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double margin = 0.0;
   while(lots >= vMin)
     {
      if(!OrderCalcMargin(dir, _Symbol, lots, refPrice, margin)) break;
      if(margin <= AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9) break;
      lots = NormalizeVolume(lots - vStep2);
      if(lots < vMin) break;
     }
   return MathMax(lots, vMin);
  }

//+------------------------------------------------------------------+
//| Swing detection (fractal with N candles each side)               |
//+------------------------------------------------------------------+
double FindSwingHigh()
  {
   for(int shift = InpBarsN + 1; shift <= InpLookbackBars; shift++)
     {
      int idx = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, InpBarsN * 2 + 1, shift - InpBarsN);
      if(idx == shift) return iHigh(_Symbol, PERIOD_CURRENT, shift);
     }
   return -1.0;
  }

double FindSwingLow()
  {
   for(int shift = InpBarsN + 1; shift <= InpLookbackBars; shift++)
     {
      int idx = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, InpBarsN * 2 + 1, shift - InpBarsN);
      if(idx == shift) return iLow(_Symbol, PERIOD_CURRENT, shift);
     }
   return -1.0;
  }

//+------------------------------------------------------------------+
//| Entry: straddle stop orders on structure                         |
//+------------------------------------------------------------------+
void PlaceEntries()
  {
   double atr = GetATR();
   if(atr <= 0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minStop = MinStopDistance();

   double buffer = MathMax(atr * InpEntryBufferATR, minStop);
   double slDist = MathMax(atr * InpSL_ATR, minStop * 2.0);
   datetime expiry = TimeCurrent() + (datetime)InpOrderExpiryBars * PeriodSeconds(PERIOD_CURRENT);

   double swingHigh = FindSwingHigh();
   double swingLow  = FindSwingLow();

   // BUY STOP above swing high
   if(swingHigh > 0)
     {
      double entry = NormalizeDouble(swingHigh + buffer, _Digits);
      if(entry - ask >= minStop)
        {
         double sl = NormalizeDouble(entry - slDist, _Digits);
         double tp = NormalizeDouble(entry + slDist * InpTP_RR, _Digits);
         double lots = CalcLots(slDist, ORDER_TYPE_BUY, entry);
         if(lots > 0)
            if(!trade.BuyStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiry, InpTradeComment))
               trade.BuyStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, InpTradeComment);
        }
     }
   // SELL STOP below swing low
   if(swingLow > 0)
     {
      double entry = NormalizeDouble(swingLow - buffer, _Digits);
      if(bid - entry >= minStop)
        {
         double sl = NormalizeDouble(entry + slDist, _Digits);
         double tp = NormalizeDouble(entry - slDist * InpTP_RR, _Digits);
         double lots = CalcLots(slDist, ORDER_TYPE_SELL, entry);
         if(lots > 0)
            if(!trade.SellStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiry, InpTradeComment))
               trade.SellStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, InpTradeComment);
        }
     }
  }

//+------------------------------------------------------------------+
//| Trailing stop value per mode (returns 0 if not available)        |
//+------------------------------------------------------------------+
double TrailLevel(bool isBuy)
  {
   double b[1];
   switch(InpTrailMode)
     {
      case TRAIL_STEP:
        {
         double atr = GetATR();
         if(atr <= 0) return 0.0;
         return isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) - atr * InpTrailATR
                      : SymbolInfoDouble(_Symbol, SYMBOL_ASK) + atr * InpTrailATR;
        }
      case TRAIL_PREV_CANDLE:
         return isBuy ? iLow(_Symbol, PERIOD_CURRENT, InpTrailPrevCandles)
                      : iHigh(_Symbol, PERIOD_CURRENT, InpTrailPrevCandles);
      case TRAIL_FAST_MA:
         if(g_hTrailMA == INVALID_HANDLE) return 0.0;
         if(CopyBuffer(g_hTrailMA, 0, 1, 1, b) < 1) return 0.0;
         return b[0];
      case TRAIL_TENKAN:
         if(g_hIchimoku == INVALID_HANDLE) return 0.0;
         if(CopyBuffer(g_hIchimoku, 0, 1, 1, b) < 1) return 0.0;   // buffer 0 = tenkan-sen
         return b[0];
      default:
         return 0.0;
     }
  }

//+------------------------------------------------------------------+
//| Position management: orphan repair, partial+BE, trailing         |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   double atr = GetATR();
   double minStop = MinStopDistance();
   double vMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagic) continue;

      ulong  ticket = posInfo.Ticket();
      bool   isBuy  = (posInfo.PositionType() == POSITION_TYPE_BUY);
      double open   = posInfo.PriceOpen();
      double sl     = posInfo.StopLoss();
      double tp     = posInfo.TakeProfit();
      double vol    = posInfo.Volume();
      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // --- orphan repair (Silver Bullet lesson: never let a trade run naked)
      if(sl == 0.0 && atr > 0)
        {
         sl = isBuy ? NormalizeDouble(open - atr * InpSL_ATR, _Digits)
                    : NormalizeDouble(open + atr * InpSL_ATR, _Digits);
         trade.PositionModify(ticket, sl, tp);
         continue;
        }
      if(tp == 0.0 && sl != 0.0)
        {
         double dist = MathAbs(open - sl);
         tp = isBuy ? NormalizeDouble(open + dist * InpTP_RR, _Digits)
                    : NormalizeDouble(open - dist * InpTP_RR, _Digits);
         trade.PositionModify(ticket, sl, tp);
         continue;
        }

      bool beDone = isBuy ? (sl >= open) : (sl <= open && sl != 0.0);

      // --- partial close at TP1 + move to break-even
      if(InpUsePartial && !beDone && sl != 0.0)
        {
         double risk = MathAbs(open - sl);
         bool tp1Hit = isBuy ? (bid >= open + risk * InpTP1_RR)
                             : (ask <= open - risk * InpTP1_RR);
         if(tp1Hit)
           {
            double closeVol = NormalizeVolume(vol * InpPartialPct / 100.0);
            if(closeVol >= vMin && vol - closeVol >= vMin)
               trade.PositionClosePartial(ticket, closeVol);
            double be = isBuy ? NormalizeDouble(open + InpBEBufferPoints * Pt(), _Digits)
                              : NormalizeDouble(open - InpBEBufferPoints * Pt(), _Digits);
            // respect broker min distance
            if(isBuy  && be <= bid - minStop) trade.PositionModify(ticket, be, tp);
            if(!isBuy && be >= ask + minStop) trade.PositionModify(ticket, be, tp);
            continue;
           }
        }

      // --- trailing (only after trigger; only meaningful improvements)
      if(InpTrailMode == TRAIL_NONE || atr <= 0) continue;
      double trigger = atr * InpSL_ATR * InpTrailStartRR;
      bool triggered = isBuy ? (bid - open >= trigger) : (open - ask >= trigger);
      if(InpUsePartial && !beDone) continue;   // partial/BE first, then trail the runner
      if(!triggered && !beDone)    continue;

      double lvl = TrailLevel(isBuy);
      if(lvl <= 0) continue;
      double newSL = NormalizeDouble(lvl, _Digits);

      if(isBuy)
        {
         if(newSL <= sl + InpMinModifyPoints * Pt()) continue;   // min improvement (prop-friendly)
         if(newSL > bid - minStop) newSL = NormalizeDouble(bid - minStop, _Digits);
         if(newSL <= sl) continue;
         trade.PositionModify(ticket, newSL, tp);
        }
      else
        {
         if(sl != 0.0 && newSL >= sl - InpMinModifyPoints * Pt()) continue;
         if(newSL < ask + minStop) newSL = NormalizeDouble(ask + minStop, _Digits);
         if(sl != 0.0 && newSL >= sl) continue;
         trade.PositionModify(ticket, newSL, tp);
        }
     }
  }

//+------------------------------------------------------------------+
//| Panel                                                            |
//+------------------------------------------------------------------+
void PanelLabel(const string name, int x, int y, const string text, color clr)
  {
   string obj = PANEL_PREFIX + name;
   if(ObjectFind(0, obj) < 0)
     {
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, InpPanelFontSize);
      ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
     }
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
  }

void PanelCreate()
  {
   string obj = PANEL_PREFIX + "bg";
   if(ObjectFind(0, obj) < 0)
     {
      ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, 8);
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, 18);
      ObjectSetInteger(0, obj, OBJPROP_XSIZE, 300);
      ObjectSetInteger(0, obj, OBJPROP_YSIZE, 14 * (InpPanelFontSize + 7));
      ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, C'20,20,25');
      ObjectSetInteger(0, obj, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, clrDimGray);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, obj, OBJPROP_BACK, false);
     }
  }

void PanelUpdate()
  {
   if(!g_ui || !InpShowPanel) return;
   static datetime lastDraw = 0;
   datetime now = TimeCurrent();
   if(now == lastDraw) return;
   lastDraw = now;

   PanelCreate();
   int lh = InpPanelFontSize + 7;
   int x = 16, y = 24;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   color stClr = clrLime;
   if(!TradingAllowed()) stClr = clrOrangeRed;
   else if(!InEntryWindow()) stClr = clrGold;

   PanelLabel("t0", x, y, "PROPFIRM SENTINEL  [" + _Symbol + "]", clrGoldenrod);            y += lh;
   PanelLabel("t1", x, y, "Status : " + g_status, stClr);                                    y += lh;
   PanelLabel("t2", x, y, StringFormat("Base balance : %.2f", g_baseBalance), clrSilver);    y += lh;
   PanelLabel("t3", x, y, StringFormat("Equity       : %.2f", eq), clrSilver);               y += lh;
   PanelLabel("t4", x, y, StringFormat("Profit       : %+.2f%%  (target %.1f%%)",
                                       ProfitPct(), InpProfitTargetPct), clrSilver);         y += lh;
   PanelLabel("t5", x, y, StringFormat("Daily DD     : %.2f%% / %.2f%%",
                                       MathMax(DailyDDPct(), 0), InpMaxDailyDDPct),
              (DailyDDPct() > InpMaxDailyDDPct * 0.7 ? clrOrangeRed : clrSilver));           y += lh;
   PanelLabel("t6", x, y, StringFormat("Weekly DD    : %.2f%% / %s",
                                       MathMax(WeeklyDDPct(), 0),
                                       InpMaxWeeklyDDPct > 0 ? StringFormat("%.2f%%", InpMaxWeeklyDDPct) : "off"),
              clrSilver);                                                                    y += lh;
   PanelLabel("t7", x, y, StringFormat("Total DD     : %.2f%% / %.2f%%  (%s)",
                                       MathMax(TotalDDPct(), 0), InpMaxTotalDDPct,
                                       InpTotalDDMode == TOTALDD_TRAILING ? "trailing" : "static"),
              (TotalDDPct() > InpMaxTotalDDPct * 0.7 ? clrOrangeRed : clrSilver));           y += lh;
   PanelLabel("t8", x, y, StringFormat("Day equity high  : %.2f", g_dayHigh), clrGray);      y += lh;
   PanelLabel("t9", x, y, StringFormat("Peak equity      : %.2f", g_overallHigh), clrGray);  y += lh;
   PanelLabel("tA", x, y, StringFormat("Trades today : %d / %s", TradesOpenedToday(),
                                       InpMaxTradesPerDay > 0 ? IntegerToString(InpMaxTradesPerDay) : "off"),
              clrSilver);                                                                    y += lh;
   PanelLabel("tB", x, y, StringFormat("Open pos/ord : %d / %d", CountOurPositions(), CountOurOrders()),
              clrSilver);                                                                    y += lh;
   PanelLabel("tC", x, y, StringFormat("Session %02d:%02d-%02d:%02d  Risk %.2f%%",
                                       InpStartHour, InpStartMinute, InpEndHour, InpEndMinute,
                                       InpRiskPercent), clrGray);                            y += lh;
   PanelLabel("tD", x, y, "Challenge day " +
              IntegerToString((int)((TimeCurrent() - InpChallengeStart) / SECONDS_DAY) + 1), clrGray);
  }

void ApplyChartColor()
  {
   if(!g_ui || !InpColorChart) return;
   color want = InpColorActive;
   if(g_hardStop && StringFind(g_stopReason, "TARGET") >= 0) want = InpColorTarget;
   else if(!TradingAllowed()) want = InpColorPaused;
   static color current = clrNONE;
   if(current != want)
     {
      ChartSetInteger(0, CHART_COLOR_BACKGROUND, want);
      current = want;
     }
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_ui = !(bool)MQLInfoInteger(MQL_OPTIMIZATION) &&
          (!(bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_VISUAL_MODE));

   if(g_ui) ChartSetInteger(0, CHART_SHOW_GRID, false);

   //--- indicator handles
   g_hATR = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   if(g_hATR == INVALID_HANDLE) { Print("Failed to create ATR handle"); return INIT_FAILED; }

   if(InpUseRSIFilter)
     {
      g_hRSI = iRSI(_Symbol, InpRSITimeframe, InpRSIPeriod, PRICE_CLOSE);
      if(g_hRSI == INVALID_HANDLE) { Print("Failed to create RSI handle"); return INIT_FAILED; }
     }
   if(InpUseMAFilter)
     {
      g_hMA = iMA(_Symbol, InpMATimeframe, InpMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_hMA == INVALID_HANDLE) { Print("Failed to create MA handle"); return INIT_FAILED; }
     }
   if(InpTrailMode == TRAIL_FAST_MA)
     {
      g_hTrailMA = iMA(_Symbol, PERIOD_CURRENT, InpTrailMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_hTrailMA == INVALID_HANDLE) { Print("Failed to create trail MA handle"); return INIT_FAILED; }
     }
   if(InpTrailMode == TRAIL_TENKAN)
     {
      g_hIchimoku = iIchimoku(_Symbol, PERIOD_CURRENT, 9, 26, 52);
      if(g_hIchimoku == INVALID_HANDLE) { Print("Failed to create Ichimoku handle"); return INIT_FAILED; }
     }

   //--- validate session inputs
   if(InpStartHour < 0 || InpStartHour > 23 || InpEndHour < 0 || InpEndHour > 23)
     {
      Print("Invalid session hours");
      return INIT_PARAMETERS_INCORRECT;
     }

   //--- prop state: restore or initialise
   LoadState();
   if(g_baseBalance <= 0)
     {
      g_baseBalance = (InpChallengeBalance > 0) ? InpChallengeBalance
                                                : AccountInfoDouble(ACCOUNT_BALANCE);
      g_overallHigh = AccountInfoDouble(ACCOUNT_EQUITY);
      SaveState();
     }
   if(InpChallengeBalance > 0 && MathAbs(g_baseBalance - InpChallengeBalance) > 0.005)
     {
      g_baseBalance = InpChallengeBalance;   // explicit input wins over stored value
      SaveState();
     }

   //--- sanity warning: worst-case day vs daily limit
   if(InpMaxTradesPerDay > 0 && InpMaxDailyDDPct > 0 &&
      InpRiskPercent * InpMaxTradesPerDay > InpMaxDailyDDPct)
      Print(StringFormat("WARNING: risk %.2f%% x %d trades/day = %.2f%% exceeds daily DD stop %.2f%%",
                         InpRiskPercent, InpMaxTradesPerDay,
                         InpRiskPercent * InpMaxTradesPerDay, InpMaxDailyDDPct));

   Print(StringFormat("PropFirm Sentinel started. Base=%.2f DailyDD=%.1f%% TotalDD=%.1f%% Target=%.1f%%",
                      g_baseBalance, InpMaxDailyDDPct, InpMaxTotalDDPct, InpProfitTargetPct));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   SaveState();
   if(g_ui)
     {
      ObjectsDeleteAll(0, PANEL_PREFIX);
      Comment("");
     }
   if(g_hATR      != INVALID_HANDLE) IndicatorRelease(g_hATR);
   if(g_hRSI      != INVALID_HANDLE) IndicatorRelease(g_hRSI);
   if(g_hMA       != INVALID_HANDLE) IndicatorRelease(g_hMA);
   if(g_hTrailMA  != INVALID_HANDLE) IndicatorRelease(g_hTrailMA);
   if(g_hIchimoku != INVALID_HANDLE) IndicatorRelease(g_hIchimoku);
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- 1. prop-firm guardian (every tick)
   UpdatePropState();
   CheckPropLimits();

   //--- 2. position management runs even when paused (protects open risk)
   ManagePositions();

   //--- 3. one-cancels-other: a fill kills the opposite pending
   if(InpCancelOpposite && CountOurPositions() > 0 && CountOurOrders() > 0)
      DeleteAllPendings();

   //--- 4. status + visuals
   if(g_hardStop)                      g_status = "HARD STOP: " + g_stopReason;
   else if(TimeCurrent() < g_pausedUntil)
                                       g_status = "paused (drawdown) until " + TimeToString(g_pausedUntil, TIME_DATE|TIME_MINUTES);
   else if(FridayFlatTime())           g_status = "Friday flat";
   else if(!InEntryWindow())           g_status = "outside session";
   else                                g_status = "hunting breakouts";
   ApplyChartColor();
   PanelUpdate();

   //--- 5. Friday flat: close everything and stand down
   if(FridayFlatTime())
     {
      DeleteAllPendings();
      if(InpCloseAtSessionEnd) CloseAllPositions();
      return;
     }

   //--- 6. everything below runs once per bar
   if(!IsNewBar()) return;

   //--- 7. hard blocks
   if(!TradingAllowed()) { DeleteAllPendings(); return; }

   //--- 8. session boundary housekeeping
   if(!InEntryWindow())
     {
      DeleteAllPendings();
      if(InpCloseAtSessionEnd) CloseAllPositions();
      return;
     }

   //--- 9. soft filters
   if(!DayAllowed())      return;
   if(IsNewsBlocked())    { DeleteAllPendings(); return; }
   if(IsRSIExtreme())     { StatusPrint("RSI extreme filter active - no new setups"); return; }
   if(IsMATooFar())       { StatusPrint("MA distance filter active - no new setups"); return; }
   if(SpreadTooWide())    return;

   //--- 10. exposure gates: one setup at a time, daily trade cap
   if(CountOurPositions() + CountOurOrders() > 0) return;
   if(InpMaxTradesPerDay > 0 && TradesOpenedToday() >= InpMaxTradesPerDay)
     {
      StatusPrint("Daily trade cap reached - done for today");
      return;
     }

   //--- 11. place the straddle
   PlaceEntries();
  }
//+------------------------------------------------------------------+
