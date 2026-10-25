//+------------------------------------------------------------------+
//|                                      HighFrequencyEA_Caffrey.mq5 |
//|  Faithful MT5 build of the "High Frequency EA cleaned up by      |
//|  Mr. Caffrey" video transcript (base version, no modifications). |
//|                                                                  |
//|  Mechanics:                                                      |
//|   - Straddles price with a buy stop and a sell stop at Delta x   |
//|     spread; drags them toward price so any impulse triggers.     |
//|   - Once a position's profit reaches InpTrailStart, the SL       |
//|     trails at InpTrailStep behind price.                         |
//|   - Outside the time window: pending orders are deleted.         |
//|   - MODIFIED: When a position is open (from any direction), no   |
//|     new pending orders are placed until that position closes.    |
//|   - MODIFIED: Orders wait for InpPendingExpiry seconds before    |
//|     they start chasing price (Delay-Then-Chase logic).           |
//|   - MODIFIED: Tracks original placement time to prevent reset    |
//|     when orders are modified.                                    |
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

enum enumHour
  {
   Inactive=0, _0100=1, _0200=2, _0300=3, _0400=4, _0500=5, _0600=6, _0700=7,
   _0800=8, _0900=9, _1000=10, _1100=11, _1200=12, _1300=13, _1400=14, _1500=15,
   _1600=16, _1700=17, _1800=18, _1900=19, _2000=20, _2100=21, _2200=22, _2300=23
  };

//═══════════════════════════════════════════════════════════════════
//                    ═══ USER INPUTS ═══
//═══════════════════════════════════════════════════════════════════

input group "=== General Settings ==="
input long   InpMagicNumber   = 999877;      // Magic Number

input group "=== Time Settings (broker time) ==="
input enumHour InpStartHour   = _0300;       // Start Hour
input enumHour InpEndHour     = _2300;       // End Hour

input group "=== Trade Settings ==="
input double InpDistance      = 80.0;        // Distance for Pending Order (Points)
input double InpStopLoss      = 500.0;       // Stop Loss (Points)
input double InpTakeProfit    = 2000.0;      // Take Profit (Points)

input group "=== Trailing Stop ==="
input double InpTrailStart    = 50.0;        // Trailing Start (Points)
input double InpTrailStep     = 60.0;        // Trailing Step (Points)

input group "=== Money Management ==="
input double InpLotSize       = 0.01;        // Lot Size

input group "=== Pending Order Management ==="
input int    InpPendingExpiry = 4;           // Delay Before Chasing (Seconds)
input int    InpMaxOrderAge   = 30;          // Max Order Age Before Deletion (Seconds)

input group "=== Dashboard Settings ==="
input string InpComment       = "ULTRAEAST AI"; // Order Comment
input long   InpUserNumber    = 256760589936;   // User Number
input string InpTitle         = "ULTRAEAST AI"; // Dashboard Title

//═══════════════════════════════════════════════════════════════════
//                   ═══ INTERNAL VARIABLES ═══
//═══════════════════════════════════════════════════════════════════

int    InpSlippage            = 30;          // Slippage (points)
int    orderCheckFrequency    = 2;
double priceToPipRatio        = 0;
int    tickCounter            = 0;
double currentSpread          = 0;
double averageSpread          = 0;
double spreadHistory[];
double minStopDistance        = 0;
double minFreezeDistance      = 0;
double lotStepSize            = 0;
double minLotSize             = 0;
double maxLotSize             = 0;
string orderComment           = "";
datetime lastBuyOrderTime     = 0;
datetime lastSellOrderTime    = 0;
datetime lastOrderTime        = 0;
datetime pendingBuyCreateTime = 0;
datetime pendingSellCreateTime = 0;
bool     hasActivePosition    = false;
ENUM_POSITION_TYPE activePositionType = POSITION_TYPE_BUY;

// ⭐ NEW: Track original placement time of each order
struct OrderTrackInfo {
   ulong ticket;
   datetime placementTime;
   double originalPrice;
};

OrderTrackInfo trackedOrders[];

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   ChartSetInteger(0, CHART_SHOW_GRID, false);

   tickCounter = 0;
   priceToPipRatio = 0;

   lotStepSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   minLotSize  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   maxLotSize  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   minStopDistance = 0;
   long brokerStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(brokerStopLevel > 0)
      minStopDistance = brokerStopLevel * _Point + _Point;

   minFreezeDistance = 0;
   long brokerFreezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   if(brokerFreezeLevel > 0)
      minFreezeDistance = brokerFreezeLevel * _Point + _Point;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   currentSpread = NormalizeDouble(ask - bid, _Digits);
   averageSpread = currentSpread;

   ArrayResize(spreadHistory, 30);
   ArrayInitialize(spreadHistory, currentSpread);

   hasActivePosition = false;
   pendingBuyCreateTime = 0;
   pendingSellCreateTime = 0;

   orderComment = InpComment + " ";

   // Initialize tracking array
   ArrayResize(trackedOrders, 0);

   TesterHideIndicators(true);
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
  }
//+------------------------------------------------------------------+

// ⭐ Helper function to find tracked order by ticket
int FindTrackedOrder(ulong ticket)
  {
   int size = ArraySize(trackedOrders);
   for(int i = 0; i < size; i++)
     {
      if(trackedOrders[i].ticket == ticket)
         return i;
     }
   return -1;
  }

// ⭐ Helper function to add or update tracked order
void UpdateTrackedOrder(ulong ticket, datetime placementTime, double price)
  {
   int index = FindTrackedOrder(ticket);
   if(index >= 0)
     {
      // Update existing entry (but keep original placement time!)
      trackedOrders[index].ticket = ticket;
      // Only update placement time if it's 0 (new order)
      if(trackedOrders[index].placementTime == 0)
         trackedOrders[index].placementTime = placementTime;
      trackedOrders[index].originalPrice = price;
     }
   else
     {
      // Add new entry
      int size = ArraySize(trackedOrders);
      ArrayResize(trackedOrders, size + 1);
      trackedOrders[size].ticket = ticket;
      trackedOrders[size].placementTime = placementTime;
      trackedOrders[size].originalPrice = price;
     }
  }

// ⭐ Helper function to remove tracked order
void RemoveTrackedOrder(ulong ticket)
  {
   int index = FindTrackedOrder(ticket);
   if(index >= 0)
     {
      int size = ArraySize(trackedOrders);
      if(index < size - 1)
        {
         for(int i = index; i < size - 1; i++)
            trackedOrders[i] = trackedOrders[i + 1];
        }
      ArrayResize(trackedOrders, size - 1);
     }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   tickCounter++;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Track spread for display only
   double newSpread = NormalizeDouble(ask - bid, _Digits);
   int histSize = ArraySize(spreadHistory);
   for(int i = 0; i < histSize - 1; i++)
      spreadHistory[i] = spreadHistory[i + 1];
   spreadHistory[histSize - 1] = newSpread;

   double sum = 0;
   for(int i = 0; i < histSize; i++)
      sum += spreadHistory[i];
   currentSpread = sum / histSize;
   averageSpread = currentSpread;

   // ========== POINT-BASED CALCULATIONS (No Spread Multiplier) ==========
   double point = _Point;
   
   double adjustedOrderDistance = MathMax(InpDistance * point, minStopDistance + point);
   double trailTriggerPrice     = InpTrailStart * point;
   double trailDistancePrice    = InpTrailStep * point;
   double takeProfitPrice       = InpTakeProfit * point;
   double calculatedStop        = MathMax(InpStopLoss * point, minStopDistance);
   // =========================================================================

   int    openBuyCount = 0, openSellCount = 0;
   double currentBuySL = 0, currentSellSL = 0;

   hasActivePosition = false;

   // Count open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!positionInfo.SelectByIndex(i))
         continue;
      if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != InpMagicNumber)
         continue;
      
      hasActivePosition = true;
      activePositionType = positionInfo.PositionType();
      
      if(positionInfo.PositionType() == POSITION_TYPE_BUY)
        {
         openBuyCount++;
         currentBuySL = positionInfo.StopLoss();
        }
      else if(positionInfo.PositionType() == POSITION_TYPE_SELL)
        {
         openSellCount++;
         currentSellSL = positionInfo.StopLoss();
        }
     }

   // Count pending orders
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
         if(pendingBuyCreateTime == 0)
            pendingBuyCreateTime = TimeCurrent();
        }
      else if(orderInfo.OrderType() == ORDER_TYPE_SELL_STOP)
        {
         pendingSellCount++;
         if(pendingSellCreateTime == 0)
            pendingSellCreateTime = TimeCurrent();
        }
     }

   MqlDateTime brokerTime;
   TimeToStruct(TimeCurrent(), brokerTime);
   bool timeOK = IsTradingHour(brokerTime.hour);

   // ⭐⭐⭐ FIXED: MANAGE PENDING ORDERS WITH PROPER TIME TRACKING ⭐⭐⭐
   // First, check for new orders that need tracking
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!orderInfo.SelectByIndex(i))
         continue;
      if(orderInfo.Symbol() != _Symbol || orderInfo.Magic() != InpMagicNumber)
         continue;
      
      ulong ticket = orderInfo.Ticket();
      int index = FindTrackedOrder(ticket);
      if(index < 0)
        {
         // New order found - add to tracking with current time
         UpdateTrackedOrder(ticket, TimeCurrent(), orderInfo.PriceOpen());
         Print("Order tracked: #", ticket, " placed at ", orderInfo.PriceOpen());
        }
     }

   // Now process orders with proper tracking
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
      
      // ⭐⭐ KEY FIX: Get ORIGINAL placement time from tracking ⭐⭐
      int trackIndex = FindTrackedOrder(ticket);
      if(trackIndex < 0)
        {
         // Shouldn't happen, but just in case
         UpdateTrackedOrder(ticket, TimeCurrent(), openPrice);
         trackIndex = FindTrackedOrder(ticket);
        }
      
      datetime originalPlacementTime = trackedOrders[trackIndex].placementTime;
      double originalPrice = trackedOrders[trackIndex].originalPrice;
      
      // Calculate TRUE age from original placement
      long orderAge = (long)(TimeCurrent() - originalPlacementTime);

      // ===== PHASE 1: Delete if outside trading hours =====
      if(!timeOK)
        {
         if(trade.OrderDelete(ticket))
           {
            Print("Order deleted: outside trading hours (age: ", orderAge, "s)");
            RemoveTrackedOrder(ticket);
            if(orderInfo.OrderType() == ORDER_TYPE_BUY_STOP)
              {
               pendingBuyCreateTime = 0;
               pendingBuyCount = 0;
              }
            else if(orderInfo.OrderType() == ORDER_TYPE_SELL_STOP)
              {
               pendingSellCreateTime = 0;
               pendingSellCount = 0;
              }
           }
         continue;
        }

      // ===== PHASE 2: Delete if too old (Max Order Age) =====
      if(orderAge >= InpMaxOrderAge)
        {
         if(trade.OrderDelete(ticket))
           {
            Print("Order deleted: max age reached (", orderAge, " seconds)");
            RemoveTrackedOrder(ticket);
            if(orderInfo.OrderType() == ORDER_TYPE_BUY_STOP)
              {
               pendingBuyCreateTime = 0;
               pendingBuyCount = 0;
              }
            else if(orderInfo.OrderType() == ORDER_TYPE_SELL_STOP)
              {
               pendingSellCreateTime = 0;
               pendingSellCount = 0;
              }
           }
         continue;
        }

      // ===== PHASE 3: ⏰ DELAY PERIOD - NO MODIFICATIONS! =====
      if(orderAge < InpPendingExpiry)
        {
         // ⭐⭐⭐ KEY: Order stays at original price - DO NOTHING ⭐⭐⭐
         // Even if it was modified before (shouldn't happen with this logic)
         // But just to be safe, if price changed during delay, revert it
         if(openPrice != originalPrice && orderAge < InpPendingExpiry)
           {
            // ⚠️ This shouldn't happen with our logic, but if it does, revert
            Print("WARNING: Order modified during delay period - reverting");
            // We could revert here, but better to let it be and log it
           }
         continue;  // Skip to next order without modifying
        }

      // ===== PHASE 4: 🏃 CHASING PERIOD - Start modifying =====
      // Order has waited InpPendingExpiry seconds, now start chasing!
      
      if(orderInfo.OrderType() == ORDER_TYPE_BUY_STOP)
        {
         double modifiedPrice = NormalizeDouble(ask + adjustedOrderDistance, _Digits);
         double modifiedSL = NormalizeDouble(modifiedPrice - calculatedStop, _Digits);
         double modifiedTP = (takeProfitPrice > 0) ? NormalizeDouble(modifiedPrice + takeProfitPrice, _Digits) : 0;
         
         if(modifiedPrice != openPrice && openPrice - ask > minFreezeDistance)
           {
            if(trade.OrderModify(ticket, modifiedPrice, modifiedSL, modifiedTP, ORDER_TIME_GTC, 0))
              {
               Print("BUY STOP chasing: modified from ", openPrice, " to ", modifiedPrice, 
                     " (TRUE age: ", orderAge, "s, placed at: ", TimeToString(originalPlacementTime), ")");
               lastBuyOrderTime = TimeCurrent();
               pendingBuyCreateTime = TimeCurrent();
               // DON'T update placement time in tracking!
              }
           }
        }
      else if(orderInfo.OrderType() == ORDER_TYPE_SELL_STOP)
        {
         double modifiedPrice = NormalizeDouble(bid - adjustedOrderDistance, _Digits);
         double modifiedSL = NormalizeDouble(modifiedPrice + calculatedStop, _Digits);
         double modifiedTP = (takeProfitPrice > 0) ? NormalizeDouble(modifiedPrice - takeProfitPrice, _Digits) : 0;
         
         if(modifiedPrice != openPrice && bid - openPrice > minFreezeDistance)
           {
            if(trade.OrderModify(ticket, modifiedPrice, modifiedSL, modifiedTP, ORDER_TIME_GTC, 0))
              {
               Print("SELL STOP chasing: modified from ", openPrice, " to ", modifiedPrice,
                     " (TRUE age: ", orderAge, "s, placed at: ", TimeToString(originalPlacementTime), ")");
               lastSellOrderTime = TimeCurrent();
               pendingSellCreateTime = TimeCurrent();
               // DON'T update placement time in tracking!
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
         double profitMove = bid - openPrice;
         if(profitMove >= trailTriggerPrice)
           {
            double trailDist = MathMax(trailDistancePrice, minStopDistance);
            double modifiedSL = NormalizeDouble(bid - trailDist, _Digits);
            if((posSL == 0 || modifiedSL > posSL) &&
               modifiedSL != posSL &&
               bid - modifiedSL > minFreezeDistance)
              {
               if(trade.PositionModify(ticket, modifiedSL, posTP))
                 {
                  Print("BUY position trailing: SL moved to ", modifiedSL);
                 }
              }
           }
        }
      else if(positionInfo.PositionType() == POSITION_TYPE_SELL)
        {
         double profitMove = openPrice - ask;
         if(profitMove >= trailTriggerPrice)
           {
            double trailDist = MathMax(trailDistancePrice, minStopDistance);
            double modifiedSL = NormalizeDouble(ask + trailDist, _Digits);
            if((posSL == 0 || modifiedSL < posSL) &&
               modifiedSL != posSL &&
               modifiedSL - ask > minFreezeDistance)
              {
               if(trade.PositionModify(ticket, modifiedSL, posTP))
                 {
                  Print("SELL position trailing: SL moved to ", modifiedSL);
                 }
              }
           }
        }
     }

   // ==== place new stop orders ====
   bool canPlaceNewOrders = !hasActivePosition;
   
   if(hasActivePosition)
     {
      // Delete all pending orders when a position is open
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         if(!orderInfo.SelectByIndex(i))
            continue;
         if(orderInfo.Symbol() != _Symbol || orderInfo.Magic() != InpMagicNumber)
            continue;
         ulong ticket = orderInfo.Ticket();
         if(trade.OrderDelete(ticket))
           {
            Print("Deleted pending order due to active position");
            RemoveTrackedOrder(ticket);
           }
        }
      lastBuyOrderTime = 0;
      lastSellOrderTime = 0;
      lastOrderTime = 0;
      pendingBuyCreateTime = 0;
      pendingSellCreateTime = 0;
      // Continue to dashboard display
     }
   else
     {
      // Only place new orders if no position exists
      long sinceLastOrder = (long)(TimeCurrent() - lastOrderTime);

      // --- buy stop ---
      if(canPlaceNewOrders && openBuyCount < 1 && pendingBuyCount < 1 && 
         timeOK && sinceLastOrder > 10)
        {
         double lots = InpLotSize;
         double marginRequired = 0;
         if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lots, ask, marginRequired) &&
            AccountInfoDouble(ACCOUNT_MARGIN_FREE) > marginRequired)
           {
            double orderDistance = MathMax(MathMax(adjustedOrderDistance,
                                                   minFreezeDistance + point),
                                           minStopDistance);
            
            double orderPrice = NormalizeDouble(ask + orderDistance, _Digits);
            double orderSL = NormalizeDouble(orderPrice - calculatedStop, _Digits);
            double orderTP = (takeProfitPrice > 0) ? NormalizeDouble(orderPrice + takeProfitPrice, _Digits) : 0;
            
            if(trade.OrderOpen(_Symbol, ORDER_TYPE_BUY_STOP, lots, 0, orderPrice,
                               orderSL, orderTP, ORDER_TIME_GTC, 0, orderComment))
              {
               lastBuyOrderTime = TimeCurrent();
               lastOrderTime = TimeCurrent();
               pendingBuyCreateTime = TimeCurrent();
               // The order will be automatically tracked in the next loop iteration
               Print("BUY STOP placed at ", orderPrice, " SL ", orderSL, " TP ", orderTP, 
                     " (will chase after ", InpPendingExpiry, "s)");
              }
           }
        }

      // --- sell stop ---
      if(canPlaceNewOrders && openSellCount < 1 && pendingSellCount < 1 && 
         timeOK && sinceLastOrder > 10)
        {
         double lots = InpLotSize;
         double marginRequired = 0;
         if(OrderCalcMargin(ORDER_TYPE_SELL, _Symbol, lots, bid, marginRequired) &&
            AccountInfoDouble(ACCOUNT_MARGIN_FREE) > marginRequired)
           {
            double orderDistance = MathMax(MathMax(adjustedOrderDistance,
                                                   minFreezeDistance + point),
                                           minStopDistance);
            
            double orderPrice = NormalizeDouble(bid - orderDistance, _Digits);
            double orderSL = NormalizeDouble(orderPrice + calculatedStop, _Digits);
            double orderTP = (takeProfitPrice > 0) ? NormalizeDouble(orderPrice - takeProfitPrice, _Digits) : 0;
            
            if(trade.OrderOpen(_Symbol, ORDER_TYPE_SELL_STOP, lots, 0, orderPrice,
                               orderSL, orderTP, ORDER_TIME_GTC, 0, orderComment))
              {
               lastSellOrderTime = TimeCurrent();
               lastOrderTime = TimeCurrent();
               pendingSellCreateTime = TimeCurrent();
               Print("SELL STOP placed at ", orderPrice, " SL ", orderSL, " TP ", orderTP,
                     " (will chase after ", InpPendingExpiry, "s)");
              }
           }
        }
     }
     
   // ==== Display info on chart ====
   string commentStr = "";
   commentStr += "=== " + InpTitle + " ===\n";
   commentStr += "User: " + IntegerToString(InpUserNumber) + "\n";
   commentStr += "Symbol: " + _Symbol + "\n";
   commentStr += "Spread: " + DoubleToString(averageSpread * 10000, 1) + " pips\n";
   commentStr += "Distance: " + DoubleToString(adjustedOrderDistance * 10000, 1) + " pips\n";
   commentStr += "Stop Loss: " + DoubleToString(calculatedStop * 10000, 1) + " pips\n";
   commentStr += "Take Profit: " + DoubleToString(takeProfitPrice * 10000, 1) + " pips\n";
   commentStr += "Trail Start: " + DoubleToString(trailTriggerPrice * 10000, 1) + " pips\n";
   commentStr += "Trail Step: " + DoubleToString(trailDistancePrice * 10000, 1) + " pips\n";
   commentStr += "Delay: " + IntegerToString(InpPendingExpiry) + "s | Max Age: " + IntegerToString(InpMaxOrderAge) + "s\n";
   commentStr += "Position: " + (hasActivePosition ? "OPEN (No new orders)" : "CLOSED (Ready)") + "\n";
   
   // Show order ages if pending orders exist
   bool hasPending = false;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!orderInfo.SelectByIndex(i))
         continue;
      if(orderInfo.Symbol() != _Symbol || orderInfo.Magic() != InpMagicNumber)
         continue;
      hasPending = true;
      break;
     }
   
   if(hasPending)
     {
      commentStr += "\n--- Pending Orders ---\n";
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         if(!orderInfo.SelectByIndex(i))
            continue;
         if(orderInfo.Symbol() != _Symbol || orderInfo.Magic() != InpMagicNumber)
            continue;
         
         ulong ticket = orderInfo.Ticket();
         int trackIndex = FindTrackedOrder(ticket);
         if(trackIndex < 0)
            continue;
         
         long trueAge = (long)(TimeCurrent() - trackedOrders[trackIndex].placementTime);
         string type = (orderInfo.OrderType() == ORDER_TYPE_BUY_STOP) ? "BUY" : "SELL";
         string status = (trueAge < InpPendingExpiry) ? "⏰ WAITING" : "🏃 CHASING";
         string priceStatus = (orderInfo.PriceOpen() == trackedOrders[trackIndex].originalPrice) ? "Fixed" : "Moving";
         commentStr += type + " STOP: Age=" + IntegerToString(trueAge) + "s [" + status + "] " + priceStatus + "\n";
        }
     }
   
   Comment(commentStr);
  }
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