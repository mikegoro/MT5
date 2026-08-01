//+------------------------------------------------------------------+
//|                                      HighFrequencyEA_Caffrey.mq5 |
//|  Faithful MT5 build of the "High Frequency EA cleaned up by      |
//|  Mr. Caffrey" video transcript (base version, no modifications). |
//|                                                                  |
//|  Mechanics:                                                      |
//|   - Straddles price with a buy stop and a sell stop at Delta x   |
//|     spread; drags them toward price so any impulse triggers.     |
//|   - All distances are spread-multiples (incl. commission cost    |
//|     converted to price distance) for cross-symbol consistency.   |
//|   - Once triggered, trails the SL: tight at first (locks         |
//|     breakeven+commission fast), widening toward the trail cap    |
//|     as profit grows.                                             |
//|   - While a position still sits at its ORIGINAL stop-loss (not   |
//|     trailing yet), one additional stop order may be placed in    |
//|     the same direction (scale-in). Once trailing starts, no      |
//|     further scale-ins.                                           |
//|   - Outside the time window / above max spread: pending orders   |
//|     are deleted.                                                 |
//+------------------------------------------------------------------+
#property copyright "transcript port for testing"
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

enum enumHour
  {
   Inactive=0, _0100=1, _0200=2, _0300=3, _0400=4, _0500=5, _0600=6, _0700=7,
   _0800=8, _0900=9, _1000=10, _1100=11, _1200=12, _1300=13, _1400=14, _1500=15,
   _1600=16, _1700=17, _1800=18, _1900=19, _2000=20, _2100=21, _2200=22, _2300=23
  };

input group "=== General Settings ==="
input long   InpMagicNumber   = 20260711;   // Magic number
input int    InpSlippage      = 30;         // Slippage (points)

input group "=== Time Settings (broker time) ==="
input enumHour InpStartHour   = _1600;      // Start hour (Inactive = midnight)
input enumHour InpEndHour     = _1700;      // End hour (Inactive = midnight)

input group "=== Order Modification ==="
input int    InpMinSeconds    = 60;         // Min seconds between modifications
input int    InpMaxSeconds    = 180;        // Max seconds before forced refresh (0 = off)
input double InpMinOrderMod   = 0.5;        // Min order modification (x spread)
input double InpMaxOrderMod   = 7.0;        // Max order modification (x spread)

input group "=== Money Management ==="
input ENUM_LOT_TYPE InpLotType = LOT_FIXED; // Lot size calculation type
input double InpFixedLots     = 0.01;       // Fixed lot size
input double InpRiskPercent   = 0.5;        // Risk % (balance/equity/margin modes)

input group "=== Trade Settings (spread multiples) ==="
input double InpDelta         = 0.5;        // Order distance (x spread)
input double InpStop          = 10.0;       // Initial stop-loss (x spread)
input double InpMaxTrailing   = 3.0;        // Trailing start (x spread)
input double InpMaxSpreadPts  = 100000;     // Max allowed spread (points)

//--- internal tuning constants (hard-coded in the original)
int    orderCheckFrequency     = 2;      // act on every Nth tick
int    defaultSpreadPeriod     = 30;     // spread history length
double orderModificationFactor = 3.0;    // order step divisor
double maxTrailingLimit        = 7.5;    // cap for trailing (x spread)
int    spreadCalculationMethod = 1;      // reserved (unused in base version)
double spreadMultiplier        = 0.0;    // zero-floor safeguard on avg spread
int    eaModeFlag              = 0;      // 0 = trade, non-zero = calc only (debug)

//--- working copies of inputs (clamped in OnInit)
double deltaX = 0, maxTrailingX = 0, orderModFactorX = 0;
double minOrderModX = 0, maxOrderModX = 0;
int    minSecondsX = 0, maxSecondsX = 0;
int    minOrderInterval = 0;

//--- state
int      tickCounter           = 0;
double   priceToPipRatio       = 0;
double   commissionPerPip      = 0;   // commission expressed as price distance
double   trailingStopBuffer    = 0;
double   trailingStopThreshold = 0;
double   baseTrailingStop      = 0;
double   trailingStopIncrement = 0;
long     accountLeverage       = 0;
double   lotStepSize = 0, maxLotSize = 0, minLotSize = 0, marginPerMinLot = 0;
double   minStopDistance = 0, minFreezeDistance = 0;
double   currentSpread = 0, averageSpread = 0;
double   maxAllowedSpread = 0;
string   orderComment = "Mr Caffrey";
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

   // clamp user inputs the way the original does
   minOrderModX = InpMinOrderMod;
   if(minOrderModX < 0.1)
      minOrderModX = 0.1;
   deltaX = InpDelta;
   if(minOrderModX > deltaX)
      deltaX = minOrderModX + 0.1;
   // max band must clear the placement distance or the freshly placed
   // order instantly violates it and the EA thrashes modify requests
   maxOrderModX = InpMaxOrderMod;
   if(maxOrderModX <= deltaX)
      maxOrderModX = deltaX + 1.0;
   maxTrailingX = InpMaxTrailing;
   if(maxTrailingX > maxTrailingLimit)
      maxTrailingX = maxTrailingLimit;
   orderModFactorX = orderModificationFactor;
   if(orderModFactorX < 1)
      orderModFactorX = 1;

   tickCounter = 0;
   priceToPipRatio = 0;
   baseTrailingStop = trailingStopBuffer;           // 0 in base version
   trailingStopIncrement = trailingStopThreshold;   // 0 in base version
   minSecondsX = (InpMinSeconds < 1) ? 1 : InpMinSeconds;
   maxSecondsX = InpMaxSeconds;
   if(maxSecondsX > 0 && maxSecondsX <= minSecondsX)
      maxSecondsX = minSecondsX * 2;
   minOrderInterval = minSecondsX;

   accountLeverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
   lotStepSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   maxLotSize  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   minLotSize  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   marginPerMinLot = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);

   minStopDistance = 0;
   long brokerStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(brokerStopLevel > 0)
      minStopDistance = brokerStopLevel * _Point + _Point;

   minFreezeDistance = 0;
   long brokerFreezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   if(brokerFreezeLevel > 0)
      minFreezeDistance = brokerFreezeLevel * _Point + _Point;

   if(brokerStopLevel > 0 || brokerFreezeLevel > 0)
      Comment("WARNING: broker stop/freeze level > 0 - broker not suitable for HFT scalping");

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   currentSpread = NormalizeDouble(ask - bid, _Digits);
   averageSpread = currentSpread;

   int period = (eaModeFlag == 0) ? defaultSpreadPeriod : 3;
   ArrayResize(spreadHistory, period);
   ArrayInitialize(spreadHistory, currentSpread);

   maxAllowedSpread = NormalizeDouble(InpMaxSpreadPts * _Point, _Digits);

   TesterHideIndicators(true);
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

   // one-time: derive price-to-profit ratio and commission-per-pip
   // (as price distance) from the most recent closed deal in history
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

   // rolling spread window: shift left, append newest, average
   double newSpread = NormalizeDouble(ask - bid, _Digits);
   int histSize = ArraySize(spreadHistory);
   for(int i = 0; i < histSize - 1; i++)
      spreadHistory[i] = spreadHistory[i + 1];
   spreadHistory[histSize - 1] = newSpread;

   double sum = 0;
   for(int i = 0; i < histSize; i++)
      sum += spreadHistory[i];
   currentSpread = sum / histSize;
   // effective spread = avg spread + commission cost as price distance
   averageSpread = MathMax(spreadMultiplier * _Point, currentSpread + commissionPerPip);

   // derived distances (all in price units)
   double adjustedOrderDistance = MathMax(averageSpread * deltaX, minStopDistance + _Point);
   double minOrderModification  = MathMax(averageSpread * minOrderModX, minFreezeDistance + _Point);
   double trailingStopActive    = averageSpread * maxTrailingX;      // trail start / active distance
   double trailingStopMaxDist   = averageSpread * maxTrailingLimit;  // profit scale for widening
   double maxOrderPlacementDist = averageSpread * maxOrderModX;
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
         // counts toward the total only once the SL has trailed to/past
         // entry; a position still at its original SL leaves the total
         // at 0 so one scale-in stop order can be placed
         if(pSL > 0 && pSL >= pPrice)
            totalBuyCount++;
         currentBuySL = pSL;
         buyPriceSum += pPrice * pLots;
         buyLotSum   += pLots;
         if(lowestBuyPrice == 0 || pPrice < lowestBuyPrice)
            lowestBuyPrice = pPrice;
        }
      else if(positionInfo.PositionType() == POSITION_TYPE_SELL)
        {
         openSellCount++;
         if(pSL > 0 && pSL <= pPrice)
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
   bool timeOK   = IsTradingHour(brokerTime.hour);
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
         bool forcedRefresh = (maxSecondsX > 0 && timeDiff > maxSecondsX);
         bool needsModification =
            (tickCounter % orderCheckFrequency == 0) &&
            (forcedRefresh ||
             ((timeDiff > minSecondsX) &&
              ((openBuyCount < 1 && openPrice - ask < minOrderModification) ||
               (openPrice - ask < orderPlacementStep) ||
               (openPrice - ask > maxOrderPlacementDist))));
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
               openPrice - ask > minFreezeDistance)
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
         bool forcedRefresh = (maxSecondsX > 0 && timeDiff > maxSecondsX);
         bool needsModification =
            (tickCounter % orderCheckFrequency == 0) &&
            (forcedRefresh ||
             ((timeDiff > minSecondsX) &&
              ((openSellCount < 1 && bid - openPrice < minOrderModification) ||
               (bid - openPrice < orderPlacementStep) ||
               (bid - openPrice > maxOrderPlacementDist))));
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
               bid - openPrice > minFreezeDistance)
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
                                 trailingStopActive, baseTrailingStop,
                                 trailingStopMaxDist);
         double modifiedSL = NormalizeDouble(bid - trailDistance, _Digits);
         double triggerLevel = openPrice + commissionPerPip + trailingStopIncrement;
         if(bid - triggerLevel > trailDistance &&
            (posSL == 0 || bid - posSL > trailDistance) &&
            modifiedSL != posSL)
           {
            trade.PositionModify(ticket, modifiedSL, posTP);
           }
        }
      else if(positionInfo.PositionType() == POSITION_TYPE_SELL)
        {
         double priceMove = openPrice - ask - commissionPerPip;
         double trailDistance = CalcTrailDistance(priceMove, minStopDistance,
                                 trailingStopActive, baseTrailingStop,
                                 trailingStopMaxDist);
         double modifiedSL = NormalizeDouble(ask + trailDistance, _Digits);
         double triggerLevel = openPrice - commissionPerPip - trailingStopIncrement;
         if(triggerLevel - ask > trailDistance &&
            (posSL == 0 || posSL - ask > trailDistance) &&
            modifiedSL != posSL)
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
   if((openBuyCount < 1 || (orderModFactorX > 1 && totalBuyCount < 1)) &&
      pendingBuyCount < 1 && spreadOK && timeOK && sinceLastOrder > minOrderInterval)
     {
      double lots = CalcOrderLots(calculatedStop);
      double marginRequired = 0;
      // margin-check with the market type the pending becomes: pending
      // orders reserve no margin in the tester, BUY_STOP would pass vacuously
      if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lots, ask, marginRequired) &&
         AccountInfoDouble(ACCOUNT_MARGIN_FREE) > marginRequired)
        {
         double orderDistance = MathMax(MathMax(adjustedOrderDistance,
                                                minFreezeDistance + _Point),
                                        minStopDistance);
         double orderPrice = NormalizeDouble(ask + orderDistance, _Digits);
         double orderSL = (openBuyCount > 0) ? currentBuySL
                        : NormalizeDouble(orderPrice - calculatedStop, _Digits);
         if(trade.OrderOpen(_Symbol, ORDER_TYPE_BUY_STOP, lots, 0, orderPrice,
                            orderSL, 0, ORDER_TIME_GTC, 0, orderComment))
           {
            lastBuyOrderTime = TimeCurrent();
            lastOrderTime = TimeCurrent();
           }
        }
     }

   // --- sell stop ---
   if((openSellCount < 1 || (orderModFactorX > 1 && totalSellCount < 1)) &&
      pendingSellCount < 1 && spreadOK && timeOK && sinceLastOrder > minOrderInterval)
     {
      double lots = CalcOrderLots(calculatedStop);
      double marginRequired = 0;
      if(OrderCalcMargin(ORDER_TYPE_SELL, _Symbol, lots, bid, marginRequired) &&
         AccountInfoDouble(ACCOUNT_MARGIN_FREE) > marginRequired)
        {
         double orderDistance = MathMax(MathMax(adjustedOrderDistance,
                                                minFreezeDistance + _Point),
                                        minStopDistance);
         double orderPrice = NormalizeDouble(bid - orderDistance, _Digits);
         double orderSL = (openSellCount > 0) ? currentSellSL
                        : NormalizeDouble(orderPrice + calculatedStop, _Digits);
         if(trade.OrderOpen(_Symbol, ORDER_TYPE_SELL_STOP, lots, 0, orderPrice,
                            orderSL, 0, ORDER_TIME_GTC, 0, orderComment))
           {
            lastSellOrderTime = TimeCurrent();
            lastOrderTime = TimeCurrent();
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Trading-hour window. Start == End (e.g. both Inactive) means no  |
//| time filter; Start > End wraps past midnight (e.g. 22:00-03:00). |
//+------------------------------------------------------------------+
bool IsTradingHour(int hour)
  {
   int startH = (int)InpStartHour;
   int endH   = (int)InpEndHour;
   if(startH == endH)
      return true;
   if(startH < endH)
      return (hour >= startH && hour < endH);
   return (hour >= startH || hour < endH);
  }
//+------------------------------------------------------------------+
//| Dynamic trailing distance. Starts at baseDist (0 = broker min)   |
//| and widens with profit: ratio = priceMove / maxDist, capped at   |
//| activeDist, floored at minDist.                                  |
//+------------------------------------------------------------------+
double CalcTrailDistance(double priceMove, double minDist,
                         double activeDist, double baseDist, double maxDist)
  {
   if(maxDist == 0)
      return MathMax(activeDist, minDist);
   double ratio = priceMove / maxDist;
   double dynamicDist = (activeDist - baseDist) * ratio + baseDist;
   return MathMax(MathMin(dynamicDist, activeDist), minDist);
  }
//+------------------------------------------------------------------+
//| Lot size: fixed (rounded up to lot step, floored at broker min)  |
//| or risk % of balance/equity/free margin over the SL distance.    |
//+------------------------------------------------------------------+
double CalcOrderLots(double slDistance)
  {
   if(InpLotType == LOT_FIXED)
     {
      double lots = MathCeil(InpFixedLots / lotStepSize) * lotStepSize;
      return MathMax(minLotSize, lots);
     }
   return CalcLots(slDistance);
  }

double CalcLots(double slDistance)
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
   if(tickSize <= 0 || tickValue <= 0 || lotStep <= 0 || slDistance <= 0)
      return minLotSize;

   double moneyPerLotStep = slDistance / tickSize * tickValue * lotStep;
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
