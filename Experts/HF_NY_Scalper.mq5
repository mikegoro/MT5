//+------------------------------------------------------------------+
//|                                                HF_NY_Scalper.mq5 |
//|  High-frequency stop-order scalper (port of the "Mr. Caffrey"    |
//|  MT4 HFT EA), adapted for XAUUSD during the New York session.    |
//|                                                                  |
//|  Core mechanics:                                                 |
//|   - Places a buy stop above ask and a sell stop below bid at a   |
//|     distance measured in multiples of the (average) spread.      |
//|   - Continuously drags the pending orders toward price so a      |
//|     breakout in either direction triggers immediately.           |
//|   - Once a position opens, trails the stop-loss aggressively     |
//|     with a dynamic (profit-scaled) trail distance.               |
//|   - All distances are spread-multiples so the settings carry     |
//|     across symbols with different spreads.                       |
//+------------------------------------------------------------------+
#property copyright "ported for backtesting"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

CTrade            trade;
CPositionInfo     positionInfo;
COrderInfo        orderInfo;
CHistoryOrderInfo histInfo;
CDealInfo         dealInfo;

enum ENUM_LOT_TYPE
  {
   LOT_FIXED = 0,        // Fixed lots
   LOT_PCT_BALANCE = 1,  // % of balance
   LOT_PCT_EQUITY = 2,   // % of equity
   LOT_PCT_MARGIN = 3    // % of free margin
  };

input group "=== General Settings ==="
input long   InpMagicNumber   = 20260705;   // Magic number
input int    InpSlippage      = 30;         // Slippage (points)

input group "=== Time Settings (broker time) ==="
// NY open 09:30 ET = 16:30 on a GMT+2 broker (17:30 summer GMT+3).
// Default window covers the first NY hours; verify your broker offset.
input int    InpStartHour     = 16;         // Start hour
input int    InpEndHour       = 19;         // End hour

input group "=== Order Modification ==="
input int    InpSeconds       = 60;         // Min seconds between order updates

input group "=== Money Management ==="
input ENUM_LOT_TYPE InpLotType = LOT_FIXED; // Lot size calculation type
input double InpFixedLots     = 0.01;       // Fixed lot size
input double InpRiskPercent   = 0.5;        // Risk % (balance/equity/margin modes)

input group "=== Trade Settings (spread multiples) ==="
input double InpDelta         = 0.5;        // Order distance (x spread)
input double InpMaxDistance   = 7.0;        // Max order distance (x spread)
input double InpStop          = 10.0;       // Initial stop-loss (x spread)
input double InpMaxTrailing   = 3.0;        // Trailing start (x spread)
input double InpMaxSpreadPts  = 100000;     // Max allowed spread (points)

//--- internal tuning constants (from the original code)
int    orderCheckFrequency      = 2;      // act on every Nth tick
int    defaultSpreadPeriod      = 30;     // spread history length
double orderModificationFactor  = 3.0;    // order step divisor
double minOrderDistance         = 0.5;    // floor for delta (x spread)
double maxTrailingLimit         = 7.5;    // cap for trailing (x spread)
double spreadMultiplier         = 1.0;    // safeguard multiplier
int    eaModeFlag               = 0;      // 0 = trading enabled, 1 = debug only

//--- working copies of user inputs (may be clamped in OnInit)
double deltaX = 0, maxTrailingX = 0, orderModFactorX = 0;

//--- state
int      tickCounter          = 0;
double   priceToPipRatio      = 0;
double   commissionPerPip     = 0;
double   trailingStopBuffer   = 0;
double   trailingStopThreshold= 0;
long     accountLeverage      = 0;
double   lotStepSize = 0, maxLotSize = 0, minLotSize = 0, marginPerMinLot = 0;
double   minStopDistance = 0, minFreezeDistance = 0;
double   currentSpread = 0, averageSpread = 0;
double   maxAllowedSpread = 0;
datetime lastBuyOrderTime  = 0;
datetime lastSellOrderTime = 0;
datetime lastOrderTime     = 0;
double   spreadHistory[];

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   ChartSetInteger(0, CHART_SHOW_GRID, false);

   // clamp user inputs the way the original code does
   deltaX = InpDelta;
   if(minOrderDistance > deltaX)
      deltaX = minOrderDistance + 0.1;
   maxTrailingX = InpMaxTrailing;
   if(maxTrailingX > maxTrailingLimit)
      maxTrailingX = maxTrailingLimit;
   orderModFactorX = orderModificationFactor;
   if(orderModFactorX < 1)
      orderModFactorX = 1;

   tickCounter = 0;
   priceToPipRatio = 0;
   trailingStopBuffer = maxTrailingX;
   trailingStopThreshold = maxTrailingX;

   accountLeverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
   lotStepSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   maxLotSize  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   minLotSize  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   marginPerMinLot = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);

   minStopDistance = 0;
   long brokerStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(brokerStopLevel > 0)
      minStopDistance = (brokerStopLevel + 1) * _Point;

   minFreezeDistance = 0;
   long brokerFreezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   if(brokerFreezeLevel > 0)
      minFreezeDistance = (brokerFreezeLevel + 1) * _Point;

   if(brokerStopLevel > 0 || brokerFreezeLevel > 0)
      Comment("WARNING: broker stop/freeze level > 0 - not ideal for HFT scalping");

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   currentSpread = NormalizeDouble(ask - bid, _Digits);
   averageSpread = currentSpread;

   int period = (eaModeFlag == 0) ? defaultSpreadPeriod : 3;
   ArrayResize(spreadHistory, period);
   ArrayInitialize(spreadHistory, currentSpread);

   maxAllowedSpread = NormalizeDouble(InpMaxSpreadPts * _Point, _Digits);

   ChartSetInteger(0, CHART_SHOW_OBJECT_DESCR, false);
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
  }
//+------------------------------------------------------------------+
void OnTick()
  {
   tickCounter++;

   // one-time: derive price-to-pip ratio and commission per pip from history
   if(priceToPipRatio == 0)
     {
      if(HistorySelect(0, TimeCurrent()))
        {
         for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
           {
            ulong ticket = HistoryDealGetTicket(i);
            if(ticket == 0)
               break;
            if(HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol &&
               HistoryDealGetDouble(ticket, DEAL_PROFIT) != 0 &&
               HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN)
              {
               long positionID = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
               if(positionID == 0)
                  continue;
               double entryPrice = 0;
               // find the entry deal of this position
               for(int j = 0; j < HistoryDealsTotal(); j++)
                 {
                  ulong t2 = HistoryDealGetTicket(j);
                  if(t2 != 0 &&
                     HistoryDealGetInteger(t2, DEAL_POSITION_ID) == positionID &&
                     HistoryDealGetInteger(t2, DEAL_ENTRY) == DEAL_ENTRY_IN)
                    {
                     entryPrice = HistoryDealGetDouble(t2, DEAL_PRICE);
                     break;
                    }
                 }
               double exitPrice  = HistoryDealGetDouble(ticket, DEAL_PRICE);
               double profit     = HistoryDealGetDouble(ticket, DEAL_PROFIT);
               double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
               if(exitPrice != entryPrice && entryPrice > 0)
                 {
                  priceToPipRatio = MathAbs(profit / (exitPrice - entryPrice));
                  if(priceToPipRatio > 0)
                     commissionPerPip = -commission / priceToPipRatio;
                  break;
                 }
              }
           }
        }
     }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // update spread history (rolling window) and average spread
   double newSpread = NormalizeDouble(ask - bid, _Digits);
   int histSize = ArraySize(spreadHistory);
   for(int i = 0; i < histSize - 1; i++)
      spreadHistory[i] = spreadHistory[i + 1];
   spreadHistory[histSize - 1] = newSpread;

   double sum = 0;
   for(int i = 0; i < histSize; i++)
      sum += spreadHistory[i];
   currentSpread = sum / histSize;
   averageSpread = MathMax(0, currentSpread + commissionPerPip);

   // derived distances (all in price units)
   double adjustedOrderDistance = MathMax(averageSpread * deltaX, minStopDistance + _Point);
   double minOrderModification  = MathMax(averageSpread * minOrderDistance, minFreezeDistance + _Point);
   double trailingStopActive    = averageSpread * maxTrailingX;      // trail start
   double trailingStopMaxDist   = averageSpread * maxTrailingLimit;  // trail cap
   double maxOrderPlacementDist = averageSpread * InpMaxDistance;
   double orderPlacementStep    = minOrderModification / orderModFactorX;
   double calculatedStop        = MathMax(InpStop * averageSpread, minStopDistance);

   // ---- scan positions ----
   int    openBuyCount = 0, openSellCount = 0;
   int    totalBuyCount = 0, totalSellCount = 0;
   double currentBuySL = 0, currentSellSL = 0;
   double buyPriceSum = 0, buyLotSum = 0, sellPriceSum = 0, sellLotSum = 0;
   double lowestBuyPrice = 0, highestSellPrice = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!positionInfo.SelectByIndex(i))
         continue;
      if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != InpMagicNumber)
         continue;
      double pPrice = positionInfo.PriceOpen();
      double pLots  = positionInfo.Volume();
      double pSL    = positionInfo.StopLoss();
      if(positionInfo.PositionType() == POSITION_TYPE_BUY)
        {
         openBuyCount++;
         if(pSL == 0 || (pSL > 0 && pSL < pPrice))
            totalBuyCount++;                 // still at original SL (not trailing yet)
         currentBuySL = pSL;
         buyPriceSum += pPrice * pLots;
         buyLotSum   += pLots;
         if(lowestBuyPrice == 0 || pPrice < lowestBuyPrice)
            lowestBuyPrice = pPrice;
        }
      else if(positionInfo.PositionType() == POSITION_TYPE_SELL)
        {
         openSellCount++;
         if(pSL == 0 || (pSL > 0 && pSL > pPrice))
            totalSellCount++;
         currentSellSL = pSL;
         sellPriceSum += pPrice * pLots;
         sellLotSum   += pLots;
         if(pPrice > highestSellPrice)
            highestSellPrice = pPrice;
        }
     }

   // ---- scan pending orders ----
   int pendingBuyCount = 0, pendingSellCount = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!orderInfo.SelectByIndex(i))
         continue;
      if(orderInfo.Symbol() != _Symbol || orderInfo.Magic() != InpMagicNumber)
         continue;
      if(orderInfo.OrderType() == ORDER_TYPE_BUY_STOP)
        {
         pendingBuyCount++;
         totalBuyCount++;
        }
      else if(orderInfo.OrderType() == ORDER_TYPE_SELL_STOP)
        {
         pendingSellCount++;
         totalSellCount++;
        }
     }

   double avgBuyPrice  = (buyLotSum  > 0) ? buyPriceSum  / buyLotSum  : 0;
   double avgSellPrice = (sellLotSum > 0) ? sellPriceSum / sellLotSum : 0;

   MqlDateTime brokerTime;
   TimeToStruct(TimeCurrent(), brokerTime);
   bool timeOK   = (brokerTime.hour >= InpStartHour && brokerTime.hour < InpEndHour);
   bool spreadOK = (averageSpread <= maxAllowedSpread);

   // ==== modify / delete pending orders ====
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!orderInfo.SelectByIndex(i))
         continue;
      if(orderInfo.Symbol() != _Symbol || orderInfo.Magic() != InpMagicNumber)
         continue;

      ulong  ticket    = orderInfo.Ticket();
      double openPrice = orderInfo.PriceOpen();
      double orderSL   = orderInfo.StopLoss();
      double orderTP   = orderInfo.TakeProfit();

      if(orderInfo.OrderType() == ORDER_TYPE_BUY_STOP)
        {
         if(!timeOK || !spreadOK)
           {
            trade.OrderDelete(ticket);
            continue;
           }
         long timeDiff = (long)(TimeCurrent() - lastBuyOrderTime);
         bool needsModification =
            (timeDiff > InpSeconds) &&
            (tickCounter % orderCheckFrequency == 0) &&
            ((openBuyCount < 1 && openPrice - ask < minOrderModification) ||
             (openPrice - ask < orderPlacementStep) ||
             (openPrice - ask > maxOrderPlacementDist));
         if(needsModification)
           {
            double distance = adjustedOrderDistance;
            if(openBuyCount > 0)
               distance = distance / orderModFactorX;
            distance = MathMax(distance, minStopDistance);
            double modifiedPrice = NormalizeDouble(ask + distance, _Digits);
            double modifiedSL = (openBuyCount > 0) ? currentBuySL
                              : NormalizeDouble(modifiedPrice - calculatedStop, _Digits);
            if((openBuyCount == 0 || modifiedPrice > avgBuyPrice) &&
               modifiedPrice != openPrice &&
               MathAbs(openPrice - ask) > minFreezeDistance)
              {
               if(trade.OrderModify(ticket, modifiedPrice, modifiedSL, orderTP,
                                    ORDER_TIME_GTC, 0))
                  lastBuyOrderTime = TimeCurrent();
              }
           }
        }
      else if(orderInfo.OrderType() == ORDER_TYPE_SELL_STOP)
        {
         if(!timeOK || !spreadOK)
           {
            trade.OrderDelete(ticket);
            continue;
           }
         long timeDiff = (long)(TimeCurrent() - lastSellOrderTime);
         bool needsModification =
            (timeDiff > InpSeconds) &&
            (tickCounter % orderCheckFrequency == 0) &&
            ((openSellCount < 1 && bid - openPrice < minOrderModification) ||
             (bid - openPrice < orderPlacementStep) ||
             (bid - openPrice > maxOrderPlacementDist));
         if(needsModification)
           {
            double distance = adjustedOrderDistance;
            if(openSellCount > 0)
               distance = distance / orderModFactorX;
            distance = MathMax(distance, minStopDistance);
            double modifiedPrice = NormalizeDouble(bid - distance, _Digits);
            double modifiedSL = (openSellCount > 0) ? currentSellSL
                              : NormalizeDouble(modifiedPrice + calculatedStop, _Digits);
            if((openSellCount == 0 || modifiedPrice < avgSellPrice) &&
               modifiedPrice != openPrice &&
               MathAbs(bid - openPrice) > minFreezeDistance)
              {
               if(trade.OrderModify(ticket, modifiedPrice, modifiedSL, orderTP,
                                    ORDER_TIME_GTC, 0))
                  lastSellOrderTime = TimeCurrent();
              }
           }
        }
     }

   // ==== trail open positions ====
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!positionInfo.SelectByIndex(i))
         continue;
      if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != InpMagicNumber)
         continue;

      ulong  ticket    = positionInfo.Ticket();
      double openPrice = positionInfo.PriceOpen();
      double posSL     = positionInfo.StopLoss();
      double posTP     = positionInfo.TakeProfit();

      if(positionInfo.PositionType() == POSITION_TYPE_BUY)
        {
         double priceMove = bid - openPrice - commissionPerPip;
         double trailDistance = CalcTrailDistance(priceMove, minStopDistance,
                                 trailingStopActive, trailingStopActive * trailingStopBuffer / MathMax(maxTrailingX,0.1),
                                 trailingStopMaxDist);
         double modifiedSL = NormalizeDouble(bid - trailDistance, _Digits);
         double triggerLevel = openPrice + commissionPerPip + trailingStopActive;
         if(bid - triggerLevel > 0 &&
            (posSL == 0 || bid - posSL > trailDistance) &&
            modifiedSL > posSL)
           {
            trade.PositionModify(ticket, modifiedSL, posTP);
           }
        }
      else if(positionInfo.PositionType() == POSITION_TYPE_SELL)
        {
         double priceMove = openPrice - ask - commissionPerPip;
         double trailDistance = CalcTrailDistance(priceMove, minStopDistance,
                                 trailingStopActive, trailingStopActive * trailingStopBuffer / MathMax(maxTrailingX,0.1),
                                 trailingStopMaxDist);
         double modifiedSL = NormalizeDouble(ask + trailDistance, _Digits);
         double triggerLevel = openPrice - commissionPerPip - trailingStopActive;
         if(triggerLevel - ask > 0 &&
            (posSL == 0 || posSL - ask > trailDistance) &&
            (posSL == 0 || modifiedSL < posSL))
           {
            trade.PositionModify(ticket, modifiedSL, posTP);
           }
        }
     }

   // ==== place new stop orders ====
   if(eaModeFlag != 0)
      return;

   long sinceLastOrder = (long)(TimeCurrent() - lastOrderTime);

   // --- buy stop ---
   if(((orderModFactorX > 1 && totalBuyCount < 1) || openBuyCount == 0) &&
      pendingBuyCount < 1 && spreadOK && timeOK && sinceLastOrder > InpSeconds)
     {
      double lots = CalcOrderLots(calculatedStop / _Point);
      double marginRequired = 0;
      if(OrderCalcMargin(ORDER_TYPE_BUY_STOP, _Symbol, lots, ask, marginRequired) &&
         AccountInfoDouble(ACCOUNT_MARGIN_FREE) > marginRequired)
        {
         double orderDistance = MathMax(MathMax(adjustedOrderDistance,
                                                minFreezeDistance + _Point),
                                        minStopDistance);
         double orderPrice = NormalizeDouble(ask + orderDistance, _Digits);
         double orderSL = (openBuyCount > 0) ? currentBuySL
                        : NormalizeDouble(orderPrice - calculatedStop, _Digits);
         if(trade.OrderOpen(_Symbol, ORDER_TYPE_BUY_STOP, lots, 0, orderPrice,
                            orderSL, 0, ORDER_TIME_GTC, 0, "HF_NY_Scalper"))
           {
            lastBuyOrderTime = TimeCurrent();
            lastOrderTime = TimeCurrent();
           }
        }
     }

   // --- sell stop ---
   if(((orderModFactorX > 1 && totalSellCount < 1) || openSellCount == 0) &&
      pendingSellCount < 1 && spreadOK && timeOK && sinceLastOrder > InpSeconds)
     {
      double lots = CalcOrderLots(calculatedStop / _Point);
      double marginRequired = 0;
      if(OrderCalcMargin(ORDER_TYPE_SELL_STOP, _Symbol, lots, bid, marginRequired) &&
         AccountInfoDouble(ACCOUNT_MARGIN_FREE) > marginRequired)
        {
         double orderDistance = MathMax(MathMax(adjustedOrderDistance,
                                                minFreezeDistance + _Point),
                                        minStopDistance);
         double orderPrice = NormalizeDouble(bid - orderDistance, _Digits);
         double orderSL = (openSellCount > 0) ? currentSellSL
                        : NormalizeDouble(orderPrice + calculatedStop, _Digits);
         if(trade.OrderOpen(_Symbol, ORDER_TYPE_SELL_STOP, lots, 0, orderPrice,
                            orderSL, 0, ORDER_TIME_GTC, 0, "HF_NY_Scalper"))
           {
            lastSellOrderTime = TimeCurrent();
            lastOrderTime = TimeCurrent();
           }
        }
     }

   Comment(StringFormat("HF NY Scalper | avg spread: %.1f pts | window %02d-%02d | time %s spread %s\nbuys open/pend: %d/%d  sells open/pend: %d/%d",
           averageSpread / _Point, InpStartHour, InpEndHour,
           timeOK ? "OK" : "OFF", spreadOK ? "OK" : "WIDE",
           openBuyCount, pendingBuyCount, openSellCount, pendingSellCount));
  }
//+------------------------------------------------------------------+
//| Dynamic trailing distance: scales from base toward active as     |
//| profit approaches maxDist, never below minDist.                  |
//+------------------------------------------------------------------+
double CalcTrailDistance(double priceMove, double minDist,
                         double activeDist, double baseDist, double maxDist)
  {
   if(maxDist == 0)
      return MathMax(activeDist, minDist);
   double ratio = priceMove / maxDist;
   if(ratio < 0) ratio = 0;
   if(ratio > 1) ratio = 1;
   double dynamicDist = (activeDist - baseDist) * (1.0 - ratio) + baseDist;
   return MathMax(MathMin(dynamicDist, activeDist), minDist);
  }
//+------------------------------------------------------------------+
//| Lot size: fixed, or risk % of balance/equity/free margin         |
//+------------------------------------------------------------------+
double CalcOrderLots(double slPoints)
  {
   if(InpLotType == LOT_FIXED)
     {
      double lots = MathCeil(InpFixedLots / lotStepSize) * lotStepSize;
      return MathMax(minLotSize, lots);
     }
   return CalcLots(slPoints);
  }

double CalcLots(double slPoints)
  {
   double lots = minLotSize;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double freeMgn = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double risk = 0;

   switch(InpLotType)
     {
      case LOT_FIXED:       return InpFixedLots;
      case LOT_PCT_BALANCE: risk = balance * InpRiskPercent / 100.0; break;
      case LOT_PCT_EQUITY:  risk = equity  * InpRiskPercent / 100.0; break;
      case LOT_PCT_MARGIN:  risk = freeMgn * InpRiskPercent / 100.0; break;
     }

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(tickSize <= 0 || tickValue <= 0 || lotStep <= 0 || slPoints <= 0)
      return minLotSize;

   double moneyPerLotStep = slPoints * _Point / tickSize * tickValue * lotStep;
   if(moneyPerLotStep <= 0)
      return minLotSize;
   lots = MathFloor(risk / moneyPerLotStep) * lotStep;

   double volMin   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volMax   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volLimit = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);
   if(volLimit > 0) lots = MathMin(lots, volLimit);
   if(volMax   > 0) lots = MathMin(lots, volMax);
   if(volMin   > 0) lots = MathMax(lots, volMin);
   return NormalizeDouble(lots, 2);
  }
//+------------------------------------------------------------------+
