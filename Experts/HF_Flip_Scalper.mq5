//+------------------------------------------------------------------+
//|                                              HF_Flip_Scalper.mq5 |
//|  "Account flip" variant of the HF stop-order straddle scalper.   |
//|                                                                  |
//|  Same entry engine as HF_NY_Scalper (buy stop above / sell stop  |
//|  below price, dragged toward price until one triggers), but:     |
//|   - Lots compound with balance (lots per $100), like the video   |
//|     flips: bigger balance -> bigger lots, immediately.           |
//|   - Positions are closed the instant floating profit reaches a   |
//|     quick target (% of balance), instead of long trailing.       |
//|                                                                  |
//|  WARNING: by design this risks the whole account repeatedly.     |
//|  A single adverse move at size ends the flip. Backtest/demo only.|
//+------------------------------------------------------------------+
#property copyright "ported for backtesting"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

CTrade            trade;
CPositionInfo     positionInfo;
COrderInfo        orderInfo;

enum ENUM_FLIP_LOT_MODE
  {
   FLIP_COMPOUND = 0,   // Lots per $100 of balance (flip mode)
   FLIP_FIXED    = 1    // Fixed lots
  };

input group "=== General Settings ==="
input long   InpMagicNumber   = 20260706;   // Magic number
input int    InpSlippage      = 30;         // Slippage (points)

input group "=== Time Settings (broker time) ==="
input int    InpStartHour     = 16;         // Start hour
input int    InpEndHour       = 19;         // End hour

input group "=== Flip Money Management ==="
input ENUM_FLIP_LOT_MODE InpLotMode = FLIP_COMPOUND; // Lot mode
input double InpLotsPer100    = 0.20;       // Lots per $100 balance (compound mode)
input double InpFixedLots     = 0.01;       // Fixed lots (fixed mode)
input double InpQuickTPPct    = 10.0;       // Quick close at profit >= % of balance
input double InpMinQuickTPUSD = 0.20;       // Quick close floor in USD

input group "=== Trade Settings (spread multiples) ==="
input double InpDelta         = 0.5;        // Order distance (x spread)
input double InpMaxDistance   = 7.0;        // Max order distance (x spread)
input double InpStop          = 10.0;       // Initial stop-loss (x spread)
input double InpMaxSpreadPts  = 100000;     // Max allowed spread (points)

input group "=== Order Modification ==="
input int    InpSeconds       = 30;         // Min seconds between order updates

//--- internal tuning constants (from the original engine)
int    orderCheckFrequency      = 2;
int    defaultSpreadPeriod      = 30;
double orderModificationFactor  = 3.0;
double minOrderDistance         = 0.5;

double deltaX = 0, orderModFactorX = 0;

int      tickCounter       = 0;
double   lotStepSize = 0, maxLotSize = 0, minLotSize = 0;
double   minStopDistance = 0, minFreezeDistance = 0;
double   averageSpread = 0, maxAllowedSpread = 0;
datetime lastBuyOrderTime = 0, lastSellOrderTime = 0, lastOrderTime = 0;
double   spreadHistory[];

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   ChartSetInteger(0, CHART_SHOW_GRID, false);

   deltaX = InpDelta;
   if(minOrderDistance > deltaX)
      deltaX = minOrderDistance + 0.1;
   orderModFactorX = orderModificationFactor;
   if(orderModFactorX < 1)
      orderModFactorX = 1;

   tickCounter = 0;
   lotStepSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   maxLotSize  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   minLotSize  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   minStopDistance = 0;
   long brokerStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(brokerStopLevel > 0)
      minStopDistance = (brokerStopLevel + 1) * _Point;

   minFreezeDistance = 0;
   long brokerFreezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   if(brokerFreezeLevel > 0)
      minFreezeDistance = (brokerFreezeLevel + 1) * _Point;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = NormalizeDouble(ask - bid, _Digits);
   averageSpread = spread;
   ArrayResize(spreadHistory, defaultSpreadPeriod);
   ArrayInitialize(spreadHistory, spread);

   maxAllowedSpread = NormalizeDouble(InpMaxSpreadPts * _Point, _Digits);
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

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // rolling average spread
   double newSpread = NormalizeDouble(ask - bid, _Digits);
   int histSize = ArraySize(spreadHistory);
   for(int i = 0; i < histSize - 1; i++)
      spreadHistory[i] = spreadHistory[i + 1];
   spreadHistory[histSize - 1] = newSpread;
   double sum = 0;
   for(int i = 0; i < histSize; i++)
      sum += spreadHistory[i];
   averageSpread = sum / histSize;

   double adjustedOrderDistance = MathMax(averageSpread * deltaX, minStopDistance + _Point);
   double minOrderModification  = MathMax(averageSpread * minOrderDistance, minFreezeDistance + _Point);
   double maxOrderPlacementDist = averageSpread * InpMaxDistance;
   double orderPlacementStep    = minOrderModification / orderModFactorX;
   double calculatedStop        = MathMax(InpStop * averageSpread, minStopDistance);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double quickTarget = MathMax(balance * InpQuickTPPct / 100.0, InpMinQuickTPUSD);

   // ==== quick profit close: the "video" behaviour ====
   // close every position of ours the moment its floating P/L
   // (incl. swap+commission) reaches the quick target
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!positionInfo.SelectByIndex(i))
         continue;
      if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != InpMagicNumber)
         continue;
      double netProfit = positionInfo.Profit() + positionInfo.Swap()
                       + positionInfo.Commission();
      if(netProfit >= quickTarget)
         trade.PositionClose(positionInfo.Ticket());
     }

   // ==== count what's left ====
   int openBuyCount = 0, openSellCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!positionInfo.SelectByIndex(i))
         continue;
      if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != InpMagicNumber)
         continue;
      if(positionInfo.PositionType() == POSITION_TYPE_BUY)  openBuyCount++;
      if(positionInfo.PositionType() == POSITION_TYPE_SELL) openSellCount++;
     }

   int pendingBuyCount = 0, pendingSellCount = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!orderInfo.SelectByIndex(i))
         continue;
      if(orderInfo.Symbol() != _Symbol || orderInfo.Magic() != InpMagicNumber)
         continue;
      if(orderInfo.OrderType() == ORDER_TYPE_BUY_STOP)  pendingBuyCount++;
      if(orderInfo.OrderType() == ORDER_TYPE_SELL_STOP) pendingSellCount++;
     }

   MqlDateTime brokerTime;
   TimeToStruct(TimeCurrent(), brokerTime);
   bool timeOK   = (brokerTime.hour >= InpStartHour && brokerTime.hour < InpEndHour);
   bool spreadOK = (averageSpread <= maxAllowedSpread);

   // ==== drag pending orders toward price / clean up ====
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!orderInfo.SelectByIndex(i))
         continue;
      if(orderInfo.Symbol() != _Symbol || orderInfo.Magic() != InpMagicNumber)
         continue;

      ulong  ticket    = orderInfo.Ticket();
      double openPrice = orderInfo.PriceOpen();
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
            ((openPrice - ask < orderPlacementStep) ||
             (openPrice - ask > maxOrderPlacementDist));
         if(needsModification)
           {
            double distance = MathMax(adjustedOrderDistance, minStopDistance);
            double modifiedPrice = NormalizeDouble(ask + distance, _Digits);
            double modifiedSL = NormalizeDouble(modifiedPrice - calculatedStop, _Digits);
            if(modifiedPrice != openPrice &&
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
            ((bid - openPrice < orderPlacementStep) ||
             (bid - openPrice > maxOrderPlacementDist));
         if(needsModification)
           {
            double distance = MathMax(adjustedOrderDistance, minStopDistance);
            double modifiedPrice = NormalizeDouble(bid - distance, _Digits);
            double modifiedSL = NormalizeDouble(modifiedPrice + calculatedStop, _Digits);
            if(modifiedPrice != openPrice &&
               MathAbs(bid - openPrice) > minFreezeDistance)
              {
               if(trade.OrderModify(ticket, modifiedPrice, modifiedSL, orderTP,
                                    ORDER_TIME_GTC, 0))
                  lastSellOrderTime = TimeCurrent();
              }
           }
        }
     }

   // ==== place new stop orders (one straddle at a time) ====
   long sinceLastOrder = (long)(TimeCurrent() - lastOrderTime);

   // hourly diagnostic while flat inside the window: shows exactly which
   // gate is blocking order placement
   static datetime lastDbg = 0;
   if(timeOK && TimeCurrent() - lastDbg >= 3600 &&
      openBuyCount + openSellCount + pendingBuyCount + pendingSellCount == 0)
     {
      lastDbg = TimeCurrent();
      double dbgLots = CalcFlipLots(ORDER_TYPE_BUY_STOP, ask);
      double dbgMargin = 0;
      bool dbgCalcOK = OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, minLotSize, ask, dbgMargin);
      PrintFormat("DBG flat: bal=%.2f eq=%.2f freeM=%.2f lev=1:%d lots=%.2f minLotMargin=%.2f calcOK=%d spreadOK=%d timeOK=%d sinceLast=%d",
                  balance, AccountInfoDouble(ACCOUNT_EQUITY),
                  AccountInfoDouble(ACCOUNT_MARGIN_FREE),
                  (int)AccountInfoInteger(ACCOUNT_LEVERAGE),
                  dbgLots, dbgMargin, (int)dbgCalcOK, (int)spreadOK, (int)timeOK,
                  (int)sinceLastOrder);
     }

   if(openBuyCount == 0 && pendingBuyCount < 1 &&
      spreadOK && timeOK && sinceLastOrder > InpSeconds)
     {
      double lots = CalcFlipLots(ORDER_TYPE_BUY_STOP, ask);
      if(lots >= minLotSize)
        {
         double orderDistance = MathMax(MathMax(adjustedOrderDistance,
                                                minFreezeDistance + _Point),
                                        minStopDistance);
         double orderPrice = NormalizeDouble(ask + orderDistance, _Digits);
         double orderSL    = NormalizeDouble(orderPrice - calculatedStop, _Digits);
         if(trade.OrderOpen(_Symbol, ORDER_TYPE_BUY_STOP, lots, 0, orderPrice,
                            orderSL, 0, ORDER_TIME_GTC, 0, "HF_Flip"))
           {
            lastBuyOrderTime = TimeCurrent();
            lastOrderTime = TimeCurrent();
           }
        }
     }

   if(openSellCount == 0 && pendingSellCount < 1 &&
      spreadOK && timeOK && sinceLastOrder > InpSeconds)
     {
      double lots = CalcFlipLots(ORDER_TYPE_SELL_STOP, bid);
      if(lots >= minLotSize)
        {
         double orderDistance = MathMax(MathMax(adjustedOrderDistance,
                                                minFreezeDistance + _Point),
                                        minStopDistance);
         double orderPrice = NormalizeDouble(bid - orderDistance, _Digits);
         double orderSL    = NormalizeDouble(orderPrice + calculatedStop, _Digits);
         if(trade.OrderOpen(_Symbol, ORDER_TYPE_SELL_STOP, lots, 0, orderPrice,
                            orderSL, 0, ORDER_TIME_GTC, 0, "HF_Flip"))
           {
            lastSellOrderTime = TimeCurrent();
            lastOrderTime = TimeCurrent();
           }
        }
     }

   Comment(StringFormat("HF Flip | balance %.2f | next lots %.2f | quick TP $%.2f | window %02d-%02d %s",
           balance, CalcFlipLots(ORDER_TYPE_BUY_STOP, ask), quickTarget,
           InpStartHour, InpEndHour, timeOK ? "ON" : "OFF"));
  }
//+------------------------------------------------------------------+
//| Compounding lot size: lots per $100 balance, capped by margin.   |
//+------------------------------------------------------------------+
double CalcFlipLots(ENUM_ORDER_TYPE type, double price)
  {
   double lots;
   if(InpLotMode == FLIP_FIXED)
      lots = InpFixedLots;
   else
     {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      lots = MathFloor(balance * InpLotsPer100 / 100.0 / lotStepSize) * lotStepSize;
     }
   lots = MathMax(lots, minLotSize);
   lots = MathMin(lots, maxLotSize);

   // margin must be checked against the market position the stop order
   // becomes at trigger: pending orders reserve no margin in the tester,
   // so checking the stop type always passes and fills get rejected later
   ENUM_ORDER_TYPE marketType =
      (type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY)
      ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   // shrink until the margin fits (keeps the flip alive instead of erroring);
   // step by integer counts of lotStepSize: repeated double subtraction
   // drifts (0.03-0.01-0.01 < 0.01) and skips the last viable size
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginRequired = 0;
   int kMin = (int)MathCeil(minLotSize / lotStepSize - 0.0000001);
   for(int k = (int)MathRound(lots / lotStepSize); k >= kMin; k--)
     {
      double tryLots = NormalizeDouble(k * lotStepSize, 2);
      if(OrderCalcMargin(marketType, _Symbol, tryLots, price, marginRequired) &&
         marginRequired < freeMargin * 0.9)
         return tryLots;
     }
   return 0;
  }
//+------------------------------------------------------------------+
