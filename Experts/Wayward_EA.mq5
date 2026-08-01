//+------------------------------------------------------------------+
//|                                                   Wayward_EA.mq5 |
//|  Mean-reversion scalper built from the "Wayward EA" video        |
//|  transcript (parts 1 + 2).                                       |
//|                                                                  |
//|  Core mechanics (part 1):                                        |
//|   - Price pokes outside a Bollinger band while RSI is at an      |
//|     extreme -> the market is "stretched".                        |
//|   - Instead of entering immediately (catching the falling        |
//|     knife), a stop order is placed on the snap-back side so      |
//|     the trade only triggers once the reversal has started.       |
//|   - While the stretch continues, the pending order is dragged    |
//|     along with price at a fixed ATR distance.                    |
//|   - TP sits on the Bollinger mid line; an aggressive ATR         |
//|     trailing stop locks in profit once the position is in the    |
//|     money.                                                       |
//|                                                                  |
//|  Filters and cockpit (part 2):                                   |
//|   - Higher-timeframe confluence: the price must also be outside  |
//|     the HTF Bollinger band, or the EA sits on its hands.         |
//|   - Spike filter: a tick-to-tick jump larger than a fraction of  |
//|     ATR pauses new entries for a configurable time.              |
//|   - Prop-firm rules: daily / 7-day / 30-day / all-time drawdown  |
//|     limits and a profit target; breaching one disables trading   |
//|     and deletes pending orders (open positions keep trailing).   |
//|   - Visuals (visual tests / live chart only): gradient           |
//|     background, LTF + HTF reversal lines, the last three HTF     |
//|     candles painted beside price, spread indicator, optional     |
//|     Fibonacci from the last swing high/low, and a status panel.  |
//+------------------------------------------------------------------+
#property copyright "built from transcript for backtesting"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

CTrade        trade;
CPositionInfo positionInfo;
COrderInfo    orderInfo;

#define OBJ_PREFIX   "WW_"
#define PANEL_PREFIX "WW_PANEL_"

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_HOUR
  {
   INACTIVE = 0,   // Inactive (disabled / midnight)
   H0100    = 1,   // 01:00
   H0200    = 2,   // 02:00
   H0300    = 3,   // 03:00
   H0400    = 4,   // 04:00
   H0500    = 5,   // 05:00
   H0600    = 6,   // 06:00
   H0700    = 7,   // 07:00
   H0800    = 8,   // 08:00
   H0900    = 9,   // 09:00
   H1000    = 10,  // 10:00
   H1100    = 11,  // 11:00
   H1200    = 12,  // 12:00
   H1300    = 13,  // 13:00
   H1400    = 14,  // 14:00
   H1500    = 15,  // 15:00
   H1600    = 16,  // 16:00
   H1700    = 17,  // 17:00
   H1800    = 18,  // 18:00
   H1900    = 19,  // 19:00
   H2000    = 20,  // 20:00
   H2100    = 21,  // 21:00
   H2200    = 22,  // 22:00
   H2300    = 23   // 23:00
  };

enum ENUM_LOT_TYPE
  {
   LOT_FIXED       = 0,  // Fixed lots
   LOT_PCT_BALANCE = 1,  // % of balance
   LOT_PCT_EQUITY  = 2,  // % of equity
   LOT_PCT_MARGIN  = 3   // % of free margin
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== General Settings ==="
input long            InpMagicNumber   = 20260710;        // Magic number
input ENUM_TIMEFRAMES InpTimeframe     = PERIOD_CURRENT;  // Working timeframe
input ENUM_TIMEFRAMES InpHigherTF      = PERIOD_H1;       // Higher timeframe
input ENUM_HOUR       InpStartHour     = INACTIVE;        // Trading start hour (broker time)
input ENUM_HOUR       InpEndHour       = INACTIVE;        // Trading end hour (broker time)
input color           InpGradientColor = clrMidnightBlue; // Chart gradient color

input group "=== Indicator Settings ==="
input int                InpBBPeriod     = 20;          // Bollinger period
input double             InpBBDeviation  = 2.0;         // Bollinger deviation
input int                InpRSIPeriod    = 14;          // RSI period
input int                InpRSIFilter    = 30;          // RSI filter (extremes at 50 +/- filter)
input int                InpATRPeriod    = 1000;        // ATR period (large = smoothed)
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_CLOSE; // Applied price (Bollinger & RSI)

input group "=== Higher Timeframe Confluence ==="
input bool   InpUseHTFConfluence = true;  // Use higher timeframe confluence
input int    InpHTFBBPeriod      = 20;    // HTF Bollinger period
input double InpHTFBBDeviation   = 2.0;   // HTF Bollinger deviation

input group "=== Spike Filter ==="
input bool   InpUseSpikeFilter = true;    // Use spike filter
input double InpSpikeATRMult   = 0.5;     // Spike threshold (x ATR, tick-to-tick)
input int    InpSpikePauseSec  = 300;     // Pause after a spike (seconds)

input group "=== Trade Management (ATR multiples) ==="
input double InpATRMultiplier = 1.0;   // Min candle size (x ATR)
input double InpStopLossATR   = 1.0;   // Initial stop-loss (x ATR)
input double InpTrailATR      = 0.2;   // Trailing distance (x ATR)
input double InpOrderDistATR  = 0.2;   // Stop-order distance (x ATR)
input int    InpMaxSpreadPts  = 10;    // Max spread (points)
input int    InpSlippage      = 10;    // Max slippage (points)

input group "=== Money Management ==="
input ENUM_LOT_TYPE InpLotType     = LOT_PCT_BALANCE; // Lot size calculation type
input double        InpFixedLots   = 0.01;            // Fixed lot size
input double        InpRiskPercent = 1.0;             // Risk % (balance/equity/margin modes)

input group "=== Higher Timeframe Visual Settings ==="
input bool InpShowFibonacci    = false;  // Show Fibonacci levels on chart
input int  InpFibBars          = 50;     // Bars each side for swing highs/lows
input int  InpHTFGapMultiplier = 8;      // HTF candles gap (bars to the right)

input group "=== Panel ==="
input bool InpShowPanel     = true;      // Show the panel
input int  InpPanelFontSize = 9;         // Panel font size

input group "=== Prop Firm Rule Settings (0 = disabled) ==="
input double   InpInitialBalance  = 0;   // Initial balance (0 = use account balance)
input double   InpProfitTargetPct = 0;   // Profit target % (all-time)
input double   InpMaxDDDayPct     = 0;   // Max drawdown % (daily)
input double   InpMaxDDWeekPct    = 0;   // Max drawdown % (7-day)
input double   InpMaxDDMonthPct   = 0;   // Max drawdown % (30-day)
input double   InpMaxDDTotalPct   = 0;   // Max drawdown % (all-time)
input datetime InpChallengeStart  = D'2026.01.01 00:00'; // Challenge start (7/30-day anchor)

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
int    handleBollinger    = INVALID_HANDLE;
int    handleBollingerHTF = INVALID_HANDLE;
int    handleRSI          = INVALID_HANDLE;
int    handleATR          = INVALID_HANDLE;

double indicatorBuffer[];

double bollLower    = 0;
double bollMain     = 0;
double bollUpper    = 0;
double htfBollUpper = 0;
double htfBollLower = 0;
double rsiValue     = 0;
double atrValue     = 0;

//--- spike filter
double   previousTickBid = 0;
datetime spikePauseUntil = 0;

//--- visual variables
color gradientStartColor = clrBlack;   // gradient runs from this to InpGradientColor
int   gradientLines      = 40;         // strips: more = smoother but slower

//--- Fibonacci
datetime prevHighTime = 0;
datetime prevLowTime  = 0;
double   prevHigh     = 0;
double   prevLow      = 0;
color    fiboColor    = clrGoldenrod;

//--- panel / prop firm rules (working copies: DBL_MAX = disabled)
double initialBalance = 0;
double profitTarget   = 0;
double maxDDDay       = 0;
double maxDDWeek      = 0;
double maxDDMonth     = 0;
double maxDDTotal     = 0;

double beginDayBalance   = 0;
double beginWeekBalance  = 0;
double beginMonthBalance = 0;

double ddPct1Day  = 0, ddPct7Day  = 0, ddPct30Day  = 0, ddPctAll  = 0;
double profitPct1Day = 0, profitPct7Day = 0, profitPct30Day = 0, profitPctAll = 0;
double equityHigh1Day = 0, equityHigh7Day = 0, equityHigh30Day = 0, equityHighAll = 0;

bool   tradingEnabled    = true;
string tradingEnabledCom = "";

string      startDayOfChallenge = "";
MqlDateTime challengeStart;

bool panelEnabled = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);

   TesterHideIndicators(true);

   if(!IsSilentBacktest())
      ChartSetInteger(0, CHART_SHOW_GRID, false);

   handleBollinger    = iBands(_Symbol, InpTimeframe, InpBBPeriod, 0, InpBBDeviation, InpAppliedPrice);
   handleBollingerHTF = iBands(_Symbol, InpHigherTF, InpHTFBBPeriod, 0, InpHTFBBDeviation, InpAppliedPrice);
   handleRSI          = iRSI(_Symbol, InpTimeframe, InpRSIPeriod, InpAppliedPrice);
   handleATR          = iATR(_Symbol, InpTimeframe, InpATRPeriod);

   if(handleBollinger == INVALID_HANDLE || handleBollingerHTF == INVALID_HANDLE
      || handleRSI == INVALID_HANDLE || handleATR == INVALID_HANDLE)
     {
      Print("Failed to create indicator handles");
      return(INIT_FAILED);
     }

   //--- prop firm rule validation: 0 means disabled
   if(InpInitialBalance == 0)
     {
      initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      Print("No initial balance defined in settings - using the account balance");
     }
   else
      initialBalance = InpInitialBalance;

   if(InpProfitTargetPct == 0)
     {
      profitTarget = DBL_MAX;
      Print("No profit target defined - unlimited target");
     }
   else
      profitTarget = InpProfitTargetPct;

   if(InpMaxDDDayPct == 0)
     {
      maxDDDay = DBL_MAX;
      Print("No daily max drawdown defined - unlimited daily drawdown allowed");
     }
   else
      maxDDDay = InpMaxDDDayPct;

   if(InpMaxDDWeekPct == 0)
     {
      maxDDWeek = DBL_MAX;
      Print("No 7-day max drawdown defined - unlimited 7-day drawdown allowed");
     }
   else
      maxDDWeek = InpMaxDDWeekPct;

   if(InpMaxDDMonthPct == 0)
     {
      maxDDMonth = DBL_MAX;
      Print("No 30-day max drawdown defined - unlimited 30-day drawdown allowed");
     }
   else
      maxDDMonth = InpMaxDDMonthPct;

   if(InpMaxDDTotalPct == 0)
     {
      maxDDTotal = DBL_MAX;
      Print("No all-time max drawdown defined - unlimited drawdown allowed");
     }
   else
      maxDDTotal = InpMaxDDTotalPct;

   TimeToStruct(InpChallengeStart, challengeStart);
   startDayOfChallenge = EnumToString((ENUM_DAY_OF_WEEK)challengeStart.day_of_week);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   beginDayBalance   = balance;
   beginWeekBalance  = balance;
   beginMonthBalance = balance;
   equityHigh1Day  = balance;
   equityHigh7Day  = balance;
   equityHigh30Day = balance;
   equityHighAll   = initialBalance;

   panelEnabled = InpShowPanel && !IsSilentBacktest();

   CheckHigherTimeframeWarning();

   if(!IsSilentBacktest())
     {
      ChartSetInteger(0, CHART_SHIFT, true);   // leave room for the HTF candles
      UpdateVisuals();
      DrawPaddingRectangles();
      if(panelEnabled)
         UpdatePanel();
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(handleBollinger);
   IndicatorRelease(handleBollingerHTF);
   IndicatorRelease(handleRSI);
   IndicatorRelease(handleATR);
   ObjectsDeleteAll(0, OBJ_PREFIX);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   int tradeSignal = 0;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- pull the latest indicator values (current candle)
   if(CopyBuffer(handleBollinger, 0, 0, 1, indicatorBuffer) < 1)
      return;
   bollMain = indicatorBuffer[0];

   if(CopyBuffer(handleBollinger, 1, 0, 1, indicatorBuffer) < 1)
      return;
   bollUpper = indicatorBuffer[0];

   if(CopyBuffer(handleBollinger, 2, 0, 1, indicatorBuffer) < 1)
      return;
   bollLower = indicatorBuffer[0];

   if(CopyBuffer(handleBollingerHTF, 1, 0, 1, indicatorBuffer) < 1)
      return;
   htfBollUpper = indicatorBuffer[0];

   if(CopyBuffer(handleBollingerHTF, 2, 0, 1, indicatorBuffer) < 1)
      return;
   htfBollLower = indicatorBuffer[0];

   if(CopyBuffer(handleRSI, 0, 0, 1, indicatorBuffer) < 1)
      return;
   rsiValue = indicatorBuffer[0];

   if(CopyBuffer(handleATR, 0, 0, 1, indicatorBuffer) < 1)
      return;
   atrValue = indicatorBuffer[0];

   double candleHigh = iHigh(_Symbol, InpTimeframe, 0);
   double candleLow  = iLow(_Symbol, InpTimeframe, 0);
   double candleSize = candleHigh - candleLow;

   //--- signal: big candle + outside the band + RSI extreme + HTF agrees
   if(candleSize > atrValue * InpATRMultiplier)
     {
      if(bid < bollLower && rsiValue < 50.0 - InpRSIFilter
         && (!InpUseHTFConfluence || bid < htfBollLower))
         tradeSignal = -1;   // stretched down -> buy the bounce
      if(ask > bollUpper && rsiValue > 50.0 + InpRSIFilter
         && (!InpUseHTFConfluence || ask > htfBollUpper))
         tradeSignal = 1;    // stretched up -> sell the snap-back
     }

   //--- trail positions/orders and count how many of ours are live
   int orderPositionsTotal = OrderPositionModify(ask, bid);

   //--- spike filter: a violent tick-to-tick move pauses new entries
   if(InpUseSpikeFilter)
     {
      if(previousTickBid != 0 && MathAbs(bid - previousTickBid) > atrValue * InpSpikeATRMult)
         spikePauseUntil = TimeCurrent() + InpSpikePauseSec;
      previousTickBid = bid;
      if(TimeCurrent() < spikePauseUntil)
         return;
     }

   //--- prop firm drawdown / profit-target gate
   UpdatePropFirmValues();
   tradingEnabled = IsTradingAllowedPropFirmValues();
   if(tradingEnabled && tradingEnabledCom != "")
     {
      Print("Trading is enabled again");
      tradingEnabledCom = "";
     }
   if(!tradingEnabled)
      CloseAllOrders();   // pending orders go, open positions keep trailing

   if(orderPositionsTotal == 0 && tradeSignal != 0 && IsTradingTime() && tradingEnabled)
      SendOrder(tradeSignal, ask, bid, bollMain);

   //--- per-tick visuals (visual test / live chart only)
   if(!IsSilentBacktest())
     {
      datetime ltfStart = iTime(_Symbol, PERIOD_CURRENT, 0) - PeriodSeconds(PERIOD_CURRENT) * 5;
      datetime ltfEnd   = iTime(_Symbol, PERIOD_CURRENT, 0) + PeriodSeconds(PERIOD_CURRENT) * 5;
      DrawReversalLines("LTF", bollUpper, bollLower, ltfStart, ltfEnd);

      datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);
      int      candleWidth = PeriodSeconds(PERIOD_CURRENT) * 2;
      int      spacing     = PeriodSeconds(PERIOD_CURRENT);
      int      initialGap  = PeriodSeconds(PERIOD_CURRENT) * InpHTFGapMultiplier;
      datetime htfStart    = currentTime + initialGap;
      datetime htfEnd      = currentTime + initialGap + (candleWidth + spacing) * 3;
      DrawReversalLines("HTF", htfBollUpper, htfBollLower, htfStart, htfEnd, true);

      UpdateSpreadIndicator(ask, bid);
     }

   //--- everything below runs once per new bar only
   if(!IsNewBar())
      return;

   UpdateInitialBalances();

   if(!IsSilentBacktest())
     {
      UpdateVisuals();
      if(panelEnabled)
         UpdatePanel();
     }
  }

//+------------------------------------------------------------------+
//| Chart event: keep the gradient glued to the chart                |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   static uint lastRedraw = 0;
   if(id == CHARTEVENT_CHART_CHANGE && GetTickCount() - lastRedraw > 300)
     {
      lastRedraw = GetTickCount();
      ChartSetInteger(0, CHART_SHIFT, true);
      DrawPaddingRectangles();
     }
  }

//+------------------------------------------------------------------+
//| Trade related functions                                          |
//+------------------------------------------------------------------+
void SendOrder(int tradeSignal, double ask, double bid, double bollingerMain)
  {
   double entry    = 0;
   double stopLoss = 0;

   double slDistance = atrValue * InpStopLossATR;
   double lots       = CalcLots(slDistance);

   double stopsLevel    = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double orderDistance = MathMax(atrValue * InpOrderDistATR, stopsLevel);
   double takeProfit    = NormalizeDouble(bollingerMain, _Digits);

   if(tradeSignal < 0)  // buy stop above price, TP on the mid band
     {
      entry    = NormalizeDouble(ask + orderDistance, _Digits);
      stopLoss = NormalizeDouble(entry - slDistance, _Digits);
      if(ask - bid < InpMaxSpreadPts * _Point && takeProfit > entry + stopsLevel)
         trade.BuyStop(lots, entry, _Symbol, stopLoss, takeProfit, ORDER_TIME_GTC, 0, "Wayward buy");
     }

   if(tradeSignal > 0)  // sell stop below price, TP on the mid band
     {
      entry    = NormalizeDouble(bid - orderDistance, _Digits);
      stopLoss = NormalizeDouble(entry + slDistance, _Digits);
      if(ask - bid < InpMaxSpreadPts * _Point && takeProfit < entry - stopsLevel)
         trade.SellStop(lots, entry, _Symbol, stopLoss, takeProfit, ORDER_TIME_GTC, 0, "Wayward sell");
     }
  }

//+------------------------------------------------------------------+
//| Trail open positions and pending stop orders.                    |
//| Returns the total number of our orders + positions.              |
//+------------------------------------------------------------------+
int OrderPositionModify(double ask, double bid)
  {
   double currentStopLoss   = 0;
   double newStopLoss       = 0;
   double currentOrderPrice = 0;
   double entry             = 0;
   int    orderPositionsTotal = 0;

   double trailingDistance = atrValue * InpTrailATR;
   double minStopDistance  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(trailingDistance < minStopDistance)
      trailingDistance = minStopDistance;

   double orderDistance = MathMax(atrValue * InpOrderDistATR, minStopDistance);
   double slDistance    = atrValue * InpStopLossATR;

   //--- open positions: trail the stop-loss once in profit
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!positionInfo.SelectByIndex(i))
         continue;
      if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
        {
         ulong  ticket    = positionInfo.Ticket();
         double openPrice = positionInfo.PriceOpen();
         orderPositionsTotal++;

         if(positionInfo.PositionType() == POSITION_TYPE_BUY)
           {
            currentStopLoss = positionInfo.StopLoss();
            newStopLoss     = NormalizeDouble(bid - trailingDistance, _Digits);
            if(newStopLoss > currentStopLoss && newStopLoss > openPrice)
               trade.PositionModify(ticket, newStopLoss, positionInfo.TakeProfit());
           }
         if(positionInfo.PositionType() == POSITION_TYPE_SELL)
           {
            currentStopLoss = positionInfo.StopLoss();
            newStopLoss     = NormalizeDouble(ask + trailingDistance, _Digits);
            if((newStopLoss < currentStopLoss || currentStopLoss == 0.0) && newStopLoss < openPrice)
               trade.PositionModify(ticket, newStopLoss, positionInfo.TakeProfit());
           }
        }
     }

   //--- pending stop orders: drag them along while price keeps stretching
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!orderInfo.SelectByIndex(i))
         continue;
      if(orderInfo.Symbol() == _Symbol && orderInfo.Magic() == InpMagicNumber)
        {
         ulong ticket = orderInfo.Ticket();
         orderPositionsTotal++;

         if(orderInfo.OrderType() == ORDER_TYPE_BUY_STOP)
           {
            currentOrderPrice = orderInfo.PriceOpen();
            entry             = NormalizeDouble(ask + orderDistance, _Digits);
            if(entry < currentOrderPrice)  // price fell further: pull the order down with it
              {
               newStopLoss = NormalizeDouble(entry - slDistance, _Digits);
               trade.OrderModify(ticket, entry, newStopLoss, orderInfo.TakeProfit(), ORDER_TIME_GTC, 0);
              }
           }
         if(orderInfo.OrderType() == ORDER_TYPE_SELL_STOP)
           {
            currentOrderPrice = orderInfo.PriceOpen();
            entry             = NormalizeDouble(bid - orderDistance, _Digits);
            if(entry > currentOrderPrice)  // price rose further: pull the order up with it
              {
               newStopLoss = NormalizeDouble(entry + slDistance, _Digits);
               trade.OrderModify(ticket, entry, newStopLoss, orderInfo.TakeProfit(), ORDER_TIME_GTC, 0);
              }
           }
        }
     }

   return orderPositionsTotal;
  }

//+------------------------------------------------------------------+
//| Delete all of our pending orders (used outside trading hours     |
//| and when the prop-firm rules disable trading)                    |
//+------------------------------------------------------------------+
void CloseAllOrders()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!orderInfo.SelectByIndex(i))
         continue;
      if(orderInfo.Symbol() == _Symbol && orderInfo.Magic() == InpMagicNumber)
         trade.OrderDelete(orderInfo.Ticket());
     }
  }

//+------------------------------------------------------------------+
//| Prop firm related functions                                      |
//+------------------------------------------------------------------+
//| Roll the day / 7-day / 30-day reference balances forward         |
//+------------------------------------------------------------------+
void UpdateInitialBalances()
  {
   static MqlDateTime previousCheck;
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   if(now.day != previousCheck.day)
     {
      beginDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      equityHigh1Day  = beginDayBalance;
      ddPct1Day       = 0;
      profitPct1Day   = 0;
      previousCheck   = now;
     }

   static datetime sevenDayPeriod = 0;
   if(sevenDayPeriod == 0)
      sevenDayPeriod = InpChallengeStart;
   if(TimeCurrent() > sevenDayPeriod)
     {
      beginWeekBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      equityHigh7Day   = beginWeekBalance;
      ddPct7Day        = 0;
      profitPct7Day    = 0;
      while(sevenDayPeriod <= TimeCurrent())
         sevenDayPeriod += 7 * 86400;
     }

   static datetime thirtyDayPeriod = 0;
   if(thirtyDayPeriod == 0)
      thirtyDayPeriod = InpChallengeStart;
   if(TimeCurrent() > thirtyDayPeriod)
     {
      beginMonthBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      equityHigh30Day   = beginMonthBalance;
      ddPct30Day        = 0;
      profitPct30Day    = 0;
      while(thirtyDayPeriod <= TimeCurrent())
         thirtyDayPeriod += 30 * 86400;
     }
  }

//+------------------------------------------------------------------+
//| Track equity highs, profit % and drawdown % per window           |
//+------------------------------------------------------------------+
void UpdatePropFirmValues()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd     = 0;

   if(beginDayBalance != 0)
     {
      profitPct1Day = (equity - beginDayBalance) / beginDayBalance * 100.0;
      if(equity > equityHigh1Day)
         equityHigh1Day = equity;
      dd = (equity - equityHigh1Day) / equityHigh1Day * 100.0;
      if(dd < ddPct1Day)
         ddPct1Day = dd;
     }

   if(beginWeekBalance != 0)
     {
      profitPct7Day = (equity - beginWeekBalance) / beginWeekBalance * 100.0;
      if(equity > equityHigh7Day)
         equityHigh7Day = equity;
      dd = (equity - equityHigh7Day) / equityHigh7Day * 100.0;
      if(dd < ddPct7Day)
         ddPct7Day = dd;
     }

   if(beginMonthBalance != 0)
     {
      profitPct30Day = (equity - beginMonthBalance) / beginMonthBalance * 100.0;
      if(equity > equityHigh30Day)
         equityHigh30Day = equity;
      dd = (equity - equityHigh30Day) / equityHigh30Day * 100.0;
      if(dd < ddPct30Day)
         ddPct30Day = dd;
     }

   if(initialBalance != 0)
     {
      profitPctAll = (equity - initialBalance) / initialBalance * 100.0;
      if(equity > equityHighAll)
         equityHighAll = equity;
      dd = (equity - equityHighAll) / equityHighAll * 100.0;
      if(dd < ddPctAll)
         ddPctAll = dd;
     }
  }

//+------------------------------------------------------------------+
//| False once any drawdown limit or the profit target is breached   |
//+------------------------------------------------------------------+
bool IsTradingAllowedPropFirmValues()
  {
   if(ddPct1Day < -maxDDDay)
     {
      if(tradingEnabledCom != "printed")
        {
         tradingEnabledCom = "Trading disabled: max drawdown for the day has been exceeded";
         Print(tradingEnabledCom);
         tradingEnabledCom = "printed";
        }
      return false;
     }
   if(ddPct7Day < -maxDDWeek)
     {
      if(tradingEnabledCom != "printed")
        {
         tradingEnabledCom = "Trading disabled: max drawdown for the week has been exceeded";
         Print(tradingEnabledCom);
         tradingEnabledCom = "printed";
        }
      return false;
     }
   if(ddPct30Day < -maxDDMonth)
     {
      if(tradingEnabledCom != "printed")
        {
         tradingEnabledCom = "Trading disabled: max drawdown for the month has been exceeded";
         Print(tradingEnabledCom);
         tradingEnabledCom = "printed";
        }
      return false;
     }
   if(ddPctAll < -maxDDTotal)
     {
      if(tradingEnabledCom != "printed")
        {
         tradingEnabledCom = "Trading disabled: all-time max drawdown has been exceeded";
         Print(tradingEnabledCom);
         tradingEnabledCom = "printed";
        }
      return false;
     }
   if(profitPctAll > profitTarget)
     {
      if(tradingEnabledCom != "printed")
        {
         tradingEnabledCom = "Hooray, profit target achieved - trading disabled";
         Print(tradingEnabledCom);
         tradingEnabledCom = "printed";
        }
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Helper functions                                                 |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   static datetime previousTime = 0;
   datetime currentTime = iTime(_Symbol, InpTimeframe, 0);
   if(previousTime != currentTime)
     {
      previousTime = currentTime;
      return true;
     }
   return false;
  }

// True when running headless (non-visual backtest or optimization):
// skip chart objects / panels so the test runs faster.
bool IsSilentBacktest()
  {
   return((MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
          || MQLInfoInteger(MQL_OPTIMIZATION));
  }

// Effective working timeframe (resolves PERIOD_CURRENT)
ENUM_TIMEFRAMES WorkingTimeframe()
  {
   return(InpTimeframe == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : InpTimeframe);
  }

//+------------------------------------------------------------------+
//| Trading-hours filter. Outside the window all pending orders      |
//| are removed. InpEndHour = INACTIVE disables the end check.       |
//+------------------------------------------------------------------+
bool IsTradingTime()
  {
   MqlDateTime time;
   TimeCurrent(time);
   int hourNow = time.hour;

   if(hourNow < InpStartHour)
     {
      CloseAllOrders();
      return false;
     }
   if(hourNow > InpEndHour && InpEndHour != INACTIVE)
     {
      CloseAllOrders();
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Big red warning if the "higher" timeframe isn't higher           |
//+------------------------------------------------------------------+
void CheckHigherTimeframeWarning()
  {
   string obj = OBJ_PREFIX + "HTFWarning";
   if(InpHigherTF <= WorkingTimeframe())
     {
      long width  = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      long height = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      if(ObjectFind(0, obj) < 0)
         ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, width / 2);
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, height / 2);
      ObjectSetString(0, obj, OBJPROP_TEXT, "Higher timeframe is not higher than the current chart");
      ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 15);
      ObjectSetString(0, obj, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, obj, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
     }
   else
      ObjectDelete(0, obj);
  }

//+------------------------------------------------------------------+
//| Lot size from the stop-loss distance and the selected MM mode    |
//+------------------------------------------------------------------+
double CalcLots(double slDistance)
  {
   double lots = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   double risk = 0;
   switch(InpLotType)
     {
      case LOT_FIXED:
         lots = InpFixedLots;
         return lots;
      case LOT_PCT_BALANCE:
         risk = balance * InpRiskPercent / 100.0;
         break;
      case LOT_PCT_EQUITY:
         risk = equity * InpRiskPercent / 100.0;
         break;
      case LOT_PCT_MARGIN:
         risk = freeMargin * InpRiskPercent / 100.0;
         break;
     }

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double moneyPerLotStep = slDistance / tickSize * tickValue * lotStep;
   if(moneyPerLotStep > 0)
      lots = MathFloor(risk / moneyPerLotStep) * lotStep;

   double minVolume   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVolume   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volumeLimit = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);

   if(volumeLimit != 0)
      lots = MathMin(lots, volumeLimit);
   if(maxVolume != 0)
      lots = MathMin(lots, maxVolume);
   if(minVolume != 0)
      lots = MathMax(lots, minVolume);

   lots = NormalizeDouble(lots, 2);
   return lots;
  }

//+------------------------------------------------------------------+
//| Fibonacci: swing high/low detection (fractal style)              |
//+------------------------------------------------------------------+
double FindHigh()
  {
   double highestHigh = 0;
   for(int i = 0; i < 200; i++)
     {
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      if(i > InpFibBars
         && iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, InpFibBars * 2 + 1, i - InpFibBars) == i)
        {
         if(high > highestHigh)
           {
            prevHighTime = iTime(_Symbol, PERIOD_CURRENT, i);
            return high;
           }
        }
      highestHigh = MathMax(high, highestHigh);
     }
   return -1;
  }

double FindLow()
  {
   double lowestLow = DBL_MAX;
   for(int i = 0; i < 200; i++)
     {
      double low = iLow(_Symbol, PERIOD_CURRENT, i);
      if(i > InpFibBars
         && iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, InpFibBars * 2 + 1, i - InpFibBars) == i)
        {
         if(low < lowestLow)
           {
            prevLowTime = iTime(_Symbol, PERIOD_CURRENT, i);
            return low;
           }
        }
      lowestLow = MathMin(low, lowestLow);
     }
   return -1;
  }

//+------------------------------------------------------------------+
//| Visual elements                                                  |
//+------------------------------------------------------------------+
void UpdateVisuals()
  {
   if(IsSilentBacktest())
      return;
   DrawHigherTimeframeData();
   prevHigh = FindHigh();
   prevLow  = FindLow();
   if(prevHigh > 0 && prevLow > 0 && InpShowFibonacci)
      DrawFibonacciLevels();
  }

//+------------------------------------------------------------------+
//| Reversal lines: the band levels drawn as short trend lines       |
//+------------------------------------------------------------------+
void DrawReversalLines(string name, double upperLevel, double lowerLevel,
                       datetime start, datetime end, bool levelOnRight = false)
  {
   string upperObj = OBJ_PREFIX + name + "_upper";
   string lowerObj = OBJ_PREFIX + name + "_lower";

   if(ObjectFind(0, upperObj) < 0)
     {
      ObjectCreate(0, upperObj, OBJ_TREND, 0, start, upperLevel, end, upperLevel);
      ObjectSetInteger(0, upperObj, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, upperObj, OBJPROP_WIDTH, 5);
      ObjectSetInteger(0, upperObj, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, upperObj, OBJPROP_SELECTABLE, false);
     }
   else
     {
      ObjectMove(0, upperObj, 0, start, upperLevel);
      ObjectMove(0, upperObj, 1, end, upperLevel);
     }

   if(ObjectFind(0, lowerObj) < 0)
     {
      ObjectCreate(0, lowerObj, OBJ_TREND, 0, start, lowerLevel, end, lowerLevel);
      ObjectSetInteger(0, lowerObj, OBJPROP_COLOR, clrGreen);
      ObjectSetInteger(0, lowerObj, OBJPROP_WIDTH, 5);
      ObjectSetInteger(0, lowerObj, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, lowerObj, OBJPROP_SELECTABLE, false);
     }
   else
     {
      ObjectMove(0, lowerObj, 0, start, lowerLevel);
      ObjectMove(0, lowerObj, 1, end, lowerLevel);
     }

   //--- labels next to the lines
   datetime lblTime  = levelOnRight ? end : start;
   string   upperLbl = OBJ_PREFIX + name + "_upper_lbl";
   string   lowerLbl = OBJ_PREFIX + name + "_lower_lbl";

   if(ObjectFind(0, upperLbl) < 0)
     {
      ObjectCreate(0, upperLbl, OBJ_TEXT, 0, lblTime, upperLevel);
      ObjectSetString(0, upperLbl, OBJPROP_TEXT, name + " upper");
      ObjectSetInteger(0, upperLbl, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, upperLbl, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetString(0, upperLbl, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, upperLbl, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, upperLbl, OBJPROP_SELECTABLE, false);
     }
   else
      ObjectMove(0, upperLbl, 0, lblTime, upperLevel);

   if(ObjectFind(0, lowerLbl) < 0)
     {
      ObjectCreate(0, lowerLbl, OBJ_TEXT, 0, lblTime, lowerLevel);
      ObjectSetString(0, lowerLbl, OBJPROP_TEXT, name + " lower");
      ObjectSetInteger(0, lowerLbl, OBJPROP_COLOR, clrGreen);
      ObjectSetInteger(0, lowerLbl, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetString(0, lowerLbl, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, lowerLbl, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, lowerLbl, OBJPROP_SELECTABLE, false);
     }
   else
      ObjectMove(0, lowerLbl, 0, lblTime, lowerLevel);
  }

//+------------------------------------------------------------------+
//| One HTF candle: a filled box body plus a trend-line wick         |
//+------------------------------------------------------------------+
void DrawHTFBar(string name, datetime start, datetime end,
                double closePrice, double openPrice, double low, double high, color clr)
  {
   string bodyObj = OBJ_PREFIX + "body_" + name;
   if(ObjectFind(0, bodyObj) < 0)
     {
      ObjectCreate(0, bodyObj, OBJ_RECTANGLE, 0, start, closePrice, end, openPrice);
      ObjectSetInteger(0, bodyObj, OBJPROP_FILL, true);
      ObjectSetInteger(0, bodyObj, OBJPROP_SELECTABLE, false);
     }
   else
     {
      ObjectMove(0, bodyObj, 0, start, closePrice);
      ObjectMove(0, bodyObj, 1, end, openPrice);
     }
   ObjectSetInteger(0, bodyObj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, bodyObj, OBJPROP_BACK, true);

   datetime midTime = start + (end - start) / 2;
   string   wickObj = OBJ_PREFIX + "wick_" + name;
   if(ObjectFind(0, wickObj) < 0)
     {
      ObjectCreate(0, wickObj, OBJ_TREND, 0, midTime, high, midTime, low);
      ObjectSetInteger(0, wickObj, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, wickObj, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, wickObj, OBJPROP_SELECTABLE, false);
     }
   else
     {
      ObjectMove(0, wickObj, 0, midTime, high);
      ObjectMove(0, wickObj, 1, midTime, low);
     }
   ObjectSetInteger(0, wickObj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, wickObj, OBJPROP_BACK, true);
  }

//+------------------------------------------------------------------+
//| Paint the last three HTF candles to the right of the price       |
//+------------------------------------------------------------------+
void DrawHigherTimeframeData()
  {
   if(WorkingTimeframe() >= InpHigherTF)
      return;

   double high[3], low[3], close[3], open[3];
   if(CopyHigh(_Symbol, InpHigherTF, 0, 3, high) < 3)
      return;
   if(CopyLow(_Symbol, InpHigherTF, 0, 3, low) < 3)
      return;
   if(CopyClose(_Symbol, InpHigherTF, 0, 3, close) < 3)
      return;
   if(CopyOpen(_Symbol, InpHigherTF, 0, 3, open) < 3)
      return;

   datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   int      candleWidth = PeriodSeconds(PERIOD_CURRENT) * 2;
   int      spacing     = PeriodSeconds(PERIOD_CURRENT);
   int      initialGap  = PeriodSeconds(PERIOD_CURRENT) * InpHTFGapMultiplier;

   for(int i = 0; i < 3; i++)
     {
      datetime boxStart = currentTime + initialGap + (candleWidth + spacing) * i;
      datetime boxEnd   = boxStart + candleWidth;
      color    boxColor = close[i] > open[i] ? clrGreen : clrRed;
      DrawHTFBar("HTF_" + IntegerToString(i), boxStart, boxEnd,
                 close[i], open[i], low[i], high[i], boxColor);
     }
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Blend two colors: MQL packs colors as 0x00BBGGRR                 |
//+------------------------------------------------------------------+
color CalculateGradientColor(color startColor, color endColor, int steps, int step)
  {
   uint sc = (uint)startColor;
   uint ec = (uint)endColor;

   int startB = (int)((sc >> 16) & 0xFF);
   int startG = (int)((sc >> 8) & 0xFF);
   int startR = (int)(sc & 0xFF);
   int endB   = (int)((ec >> 16) & 0xFF);
   int endG   = (int)((ec >> 8) & 0xFF);
   int endR   = (int)(ec & 0xFF);

   int r, g, b;
   if(startR > endR)
      r = startR - (startR - endR) * step / steps;
   else
      r = startR + (endR - startR) * step / steps;
   if(startG > endG)
      g = startG - (startG - endG) * step / steps;
   else
      g = startG + (endG - startG) * step / steps;
   if(startB > endB)
      b = startB - (startB - endB) * step / steps;
   else
      b = startB + (endB - startB) * step / steps;

   return (color)((b << 16) | (g << 8) | r);
  }

//+------------------------------------------------------------------+
//| The gradient: horizontal strips blending start -> user color     |
//+------------------------------------------------------------------+
void DrawPaddingRectangles()
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION))
      return;

   int width  = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int height = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int lineHeight = height / gradientLines + 1;

   for(int i = 0; i < gradientLines; i++)
     {
      string obj = OBJ_PREFIX + "PadRect" + IntegerToString(i);
      if(ObjectFind(0, obj) < 0)
         ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);

      color band = CalculateGradientColor(gradientStartColor, InpGradientColor, gradientLines, i);
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, 0);
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, i * lineHeight);
      ObjectSetInteger(0, obj, OBJPROP_XSIZE, width);
      ObjectSetInteger(0, obj, OBJPROP_YSIZE, lineHeight + 1);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_BACK, true);
      ObjectSetInteger(0, obj, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, band);
      ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, band);
      ObjectSetInteger(0, obj, OBJPROP_FILL, true);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
     }
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Spread readout just below the price                              |
//+------------------------------------------------------------------+
void UpdateSpreadIndicator(double ask, double bid)
  {
   string obj  = OBJ_PREFIX + "Spread";
   string text = "Spread: " + DoubleToString((ask - bid) / _Point, 1) + " pts";
   double textPrice = bid - 10 * _Point;
   datetime textTime = iTime(_Symbol, PERIOD_CURRENT, 0) + PeriodSeconds(PERIOD_CURRENT);

   if(ObjectFind(0, obj) < 0)
     {
      ObjectCreate(0, obj, OBJ_TEXT, 0, textTime, textPrice);
      ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
     }
   else
      ObjectMove(0, obj, 0, textTime, textPrice);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
  }

//+------------------------------------------------------------------+
//| Fibonacci between the last swing high and swing low              |
//+------------------------------------------------------------------+
void DrawFibonacciLevels()
  {
   datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   string   name        = OBJ_PREFIX + "Fibo";

   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_FIBO, 0, prevHighTime, prevHigh, prevLowTime, prevLow);
      ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, fiboColor);
      ObjectSetInteger(0, name, OBJPROP_COLOR, fiboColor);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
     }

   // the fibo always runs from the older point to the newer one
   if(prevHighTime < prevLowTime)
     {
      ObjectMove(0, name, 0, prevHighTime, prevHigh);
      ObjectMove(0, name, 1, currentTime, prevLow);
     }
   else
     {
      ObjectMove(0, name, 0, prevLowTime, prevLow);
      ObjectMove(0, name, 1, currentTime, prevHigh);
     }
  }

//+------------------------------------------------------------------+
//| Panel primitives                                                 |
//+------------------------------------------------------------------+
void PanelRect(string name, int x, int y, int w, int h, color bg, color border)
  {
   string obj = PANEL_PREFIX + name;
   if(ObjectFind(0, obj) < 0)
     {
      ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, obj, OBJPROP_BACK, false);
      ObjectSetInteger(0, obj, OBJPROP_BORDER_TYPE, BORDER_FLAT);
     }
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, border);
  }

void PanelText(string name, int x, int y, string text, color clr, int size, bool bold = false)
  {
   string obj = PANEL_PREFIX + name;
   if(ObjectFind(0, obj) < 0)
     {
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
     }
   ObjectSetString(0, obj, OBJPROP_FONT, bold ? "Consolas Bold" : "Consolas");
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
  }

//+------------------------------------------------------------------+
//| The command center: status, account, prop-firm windows           |
//+------------------------------------------------------------------+
void UpdatePanel()
  {
   int f    = MathMax(7, InpPanelFontSize);
   int pad  = 10;
   int rowH = f + 7;
   int w    = f * 44;
   int x0   = 10;
   int y0   = 20;
   int x    = x0 + pad;
   int y    = y0 + pad;

   color colBg     = C'18,18,26';
   color colBorder = C'70,70,90';
   color colHead   = clrSilver;
   color colText   = clrWhiteSmoke;
   color colGood   = clrLime;
   color colBad    = clrTomato;
   color colWarn   = clrOrange;

   int rows   = 12;
   int height = pad * 2 + rows * rowH;
   PanelRect("bg", x0, y0, w, height, colBg, colBorder);

   //--- header + status
   PanelText("hdr", x, y, StringFormat("Wayward EA  %s %s", _Symbol,
             StringSubstr(EnumToString(WorkingTimeframe()), 7)), clrWhite, f + 1, true);
   string status;
   color  statusColor;
   if(!tradingEnabled)
     {
      status      = "STOPPED";
      statusColor = colBad;
     }
   else if(TimeCurrent() < spikePauseUntil)
     {
      status      = "SPIKE PAUSE";
      statusColor = colWarn;
     }
   else
     {
      status      = "TRADING";
      statusColor = colGood;
     }
   PanelText("status", x + w - pad * 2 - (int)(StringLen(status) * f * 0.62), y, status, statusColor, f, true);
   y += rowH;

   //--- account line
   PanelText("acct", x, y, StringFormat("Equity %.2f   Balance %.2f",
             AccountInfoDouble(ACCOUNT_EQUITY), AccountInfoDouble(ACCOUNT_BALANCE)), colText, f);
   y += rowH;

   //--- signal context
   PanelText("sig", x, y, StringFormat("RSI %.1f   Bid %s   ATR %s", rsiValue,
             DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits),
             DoubleToString(atrValue, _Digits)), colText, f);
   y += rowH;

   PanelText("bands", x, y, StringFormat("LTF band %s / %s   HTF conf %s",
             DoubleToString(bollLower, _Digits), DoubleToString(bollUpper, _Digits),
             InpUseHTFConfluence ? "ON" : "OFF"), colText, f);
   y += rowH;

   string session = (InpStartHour == INACTIVE && InpEndHour == INACTIVE) ? "24h"
                    : StringFormat("%02d:00-%02d:59", (int)InpStartHour, (int)InpEndHour);
   PanelText("sess", x, y, StringFormat("Session %s   Spread cap %d pts   Risk %.1f%%",
             session, InpMaxSpreadPts, InpRiskPercent), colText, f);
   y += rowH;

   //--- prop firm windows
   PanelText("pfhdr", x, y, "Window   Profit%     DD%      Limit", colHead, f, true);
   y += rowH;

   string limitDay   = (maxDDDay   == DBL_MAX) ? "-" : StringFormat("%.1f", maxDDDay);
   string limitWeek  = (maxDDWeek  == DBL_MAX) ? "-" : StringFormat("%.1f", maxDDWeek);
   string limitMonth = (maxDDMonth == DBL_MAX) ? "-" : StringFormat("%.1f", maxDDMonth);
   string limitAll   = (maxDDTotal == DBL_MAX) ? "-" : StringFormat("%.1f", maxDDTotal);

   PanelText("pfday", x, y, StringFormat("Day      %+7.2f  %7.2f   %s",
             profitPct1Day, ddPct1Day, limitDay),
             ddPct1Day < 0 ? colText : colText, f);
   y += rowH;
   PanelText("pfweek", x, y, StringFormat("7-day    %+7.2f  %7.2f   %s",
             profitPct7Day, ddPct7Day, limitWeek), colText, f);
   y += rowH;
   PanelText("pfmonth", x, y, StringFormat("30-day   %+7.2f  %7.2f   %s",
             profitPct30Day, ddPct30Day, limitMonth), colText, f);
   y += rowH;
   PanelText("pfall", x, y, StringFormat("All      %+7.2f  %7.2f   %s",
             profitPctAll, ddPctAll, limitAll),
             profitPctAll >= 0 ? colGood : colBad, f);
   y += rowH;

   string target = (profitTarget == DBL_MAX) ? "-" : StringFormat("%.1f%%", profitTarget);
   PanelText("target", x, y, StringFormat("Target %s   Initial %.2f", target, initialBalance), colText, f);
   y += rowH;

   PanelText("chal", x, y, StringFormat("Challenge start: %s %04d.%02d.%02d",
             startDayOfChallenge, challengeStart.year, challengeStart.mon, challengeStart.day),
             colHead, f);

   ChartRedraw();
  }
//+------------------------------------------------------------------+
