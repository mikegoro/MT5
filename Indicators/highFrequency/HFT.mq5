//+------------------------------------------------------------------+
//|                                            MyExpertAdvisor.mq5   |
//|                                  Initial Expert Advisor Setup    |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      ""
#property version   "1.00"
#property strict

//--- Include the MQL5 standard trade library
#include <Trade\Trade.mqh>

//--- Global instances of standard trade classes
CTrade          trade;
CPositionInfo   positionInfo;
COrderInfo      orderInfo;
CHistoryOrderInfo hisInfo;
CDealInfo       dealInfo;

//--- Forward declarations
void trailStop(double trailingStopActive, double maxOrderPlacementDistance);
void closeAtProfit();
void checkPositionLossLimit();
void executeMartingale();
void executeAntiMartingale();

//--- Lot sizing type enum
enum ENUM_LOT_TYPE
  {
   LOT_FIXED,                // Fixed lot size
   LOT_PERCENT_BALANCE,      // % of account balance
   LOT_PERCENT_EQUITY,       // % of account equity
   LOT_PERCENT_FREE_MARGIN   // % of free margin
  };

//--- Trailing Stop-Loss Type enum
enum ENUM_TSL_TYPE
  {
   TSL_DEFAULT,             // Default trailing (V1 aggressive math)
   TSL_SCALPING,            // Scalping Trail (based on fixed points)
   TSL_PREVIOUS_CANDLE,     // Previous Candle's High/Low
   TSL_FAST_MA,             // Fast Moving Average
   TSL_ICHIMOKU_TENKAN      // Ichimoku Tenkan-sen
  };

//--- Maximum Positions Type enum
enum ENUM_MAX_POS_TYPE
  {
   MAX_POS_DISABLED,        // Disabled (No position limits)
   MAX_POS_GLOBAL,          // Global limit (Buys + Sells combined)
   MAX_POS_DIRECTIONAL      // Directional limit (Per direction independently)
  };

//--- Trading Mode Type enum
enum ENUM_TRADING_MODE
  {
   MODE_CURRENT_SYSTEM,     // Current system (Trailing Stops + Scalping)
   MODE_MARTINGALE,         // Martingale (Scale up on losses) - HIGH RISK
   MODE_ANTIMARTINGALE      // Anti-Martingale (Scale down on losses) - SAFER
  };

//+------------------------------------------------------------------+
//| Input parameters                                                  |
//+------------------------------------------------------------------+
input group "General Settings"
input ulong  InputMagicNumber = 123456;     // Magic number
input int    InputSlippage    = 3;          // Slippage (points)
input int    StartHour        = 16;         // Start hour for trading
input int    EndHour          = 17;         // End hour for trading
input int    Seconds          = 60;         // Seconds for order modification

input group "Money Management"
input ENUM_LOT_TYPE    LotType            = LOT_FIXED;      // Lot type
input double           FixedLots          = 0.01;           // Fixed lot size
input double           RiskPercent        = 0.5;            // Risk percentage (used if LotType is percentage-based)
input bool             EnableProfitTarget = true;           // Enable profit target close
input double           ProfitTargetAmount = 1.0;            // Close position if profit > $ (0 = disabled)
input ENUM_MAX_POS_TYPE MaxPositionsType  = MAX_POS_GLOBAL; // Maximum positions limit type
input int              MaxPositions       = 5;              // Maximum position value (if enabled)
input bool             EnableMaxLossLimit = true;           // Enable per-position loss limit (RISK CONTROL)
input double           MaxLossPerPosition = 5.0;            // Close position if loss exceeds $ amount (Risk Control)

input group "Trade Settings in Points"
input double InputDelta        = 0.5;   // Delta (multiplied by spread to calculate order distance)
input double InputMaxDistance  = 7.0;   // Max distance for stop orders (multiplied by spread)
input double InputStop         = 10.0;  // Initial stop (multiplied by spread)
input double InputMaxTrailing  = 7.5;   // Trailing start threshold (multiplied by spread)
input double InputMaxSpread    = 100.0; // Maximum spread threshold

input group "Trailing Stop-Loss Management"
input ENUM_TSL_TYPE    TrailType          = TSL_SCALPING;      // Trailing stop-loss type
input double           TSL_TriggerPoint   = 15.0;              // TSL Trigger Point (Points)
input double           TSL_Point          = 10.0;              // TSL Trail Distance (Points)
input int              TSL_Candles        = 3;                 // Previous candle count
input int              MA_Period          = 5;                 // Fast MA Period
input ENUM_MA_METHOD   MA_Method          = MODE_EMA;          // Fast MA Method
input ENUM_APPLIED_PRICE MA_AppliedPrice  = PRICE_MEDIAN;      // Fast MA Applied Price

input group "Advanced - Trading Mode (Separate System)"
input ENUM_TRADING_MODE TradingMode       = MODE_CURRENT_SYSTEM; // Select trading mode

input group "Martingale Settings (HIGH RISK - Use with Caution!)"
input bool              EnableMartingale    = false;           // Enable Martingale mode
input double            MartingaleLotSize   = 0.01;           // Starting lot size (0.01 = 1,000 units - micro lot)
input double            MartingaleMultiplier = 2.2;            // Lot multiplier on loss
input int               MartingaleMaxLosses = 4;               // Max consecutive losses (SAFETY LIMIT)
input double            MartingaleMaxLot     = 0.1;            // Max lot size cap (SAFETY LIMIT)
input int               MartingaleTakeProfit = 77;             // Take profit (points)
input int               MartingaleStopLoss   = 20;             // Stop loss (points)

input group "Anti-Martingale Settings (SAFER)"
input bool              EnableAntiMartingale = false;          // Enable Anti-Martingale mode
input double            AntiMartingaleLotSize = 0.01;         // Starting lot size (0.01 = 1,000 units - micro lot)
input double            AntiMartingaleMultiplier = 1.5;        // Lot multiplier on WIN (scale up)
input double            AntiMartingaleLotReduction = 0.5;      // Lot divisor on LOSS (scale down)
input double            AntiMartingaleMaxLot = 0.05;           // Max lot size cap
input int               AntiMartingaleTakeProfit = 50;         // Take profit (points)
input int               AntiMartingaleStopLoss = 15;           // Stop loss (points)

//+------------------------------------------------------------------+
//| Global variables - default configuration values                 |
//+------------------------------------------------------------------+
int    orderCheckFrequency    = 2;
int    defaultSpreadPeriod    = 30;
double orderModificationFactor = 3.0;
double minOrderDistance       = 0.5;
double maxTrailingLimit       = 7.5;
int    spreadCalculationMethod = 1;

//+------------------------------------------------------------------+
//| Global variables - working/state variables                      |
//+------------------------------------------------------------------+
int    tickCounter = 0;

double deltaX           = 0;
double baseTrailingStop  = 0;
double incrementStop     = 0;

long   accountLeverage = 0;

double lotStep       = 0;
double maxLot         = 0;
double minLot         = 0;
double marginMinLot   = 0;

double minStopDistance    = 0;
double brokerStopLevel    = 0;
double minFreezeDistance  = 0;
double brokerFreezeLevel  = 0;

double currentSpread = 0;
double averageSpread = 0;

int    eaModeFlag = 0;

int    spreadArraySize = 0;

double commissionPerPip  = 0;
double priceToPipRatio   = 0;

double spreadMultiplier = 0;

bool   enableTrading    = false;
bool   sellOrderAllowed = false;
bool   spreadAcceptable = false;

double currentStopLoss   = 0;
double lastBuyOrderTime  = 0;
double lastSellOrderTime = 0;
double lastOrderTime     = 0;

double spreadHistory[];

double maxAllowedSpread = 0;

//--- Indicator handles
int handle_MA        = INVALID_HANDLE;
int handle_Ichimoku  = INVALID_HANDLE;

//--- Martingale tracking variables
int    martingaleConsecutiveLosses = 0;
double martingaleCurrentLotSize    = 0.01;

//--- Anti-Martingale tracking variables
int    antiMartingaleConsecutiveWins = 0;
double antiMartingaleCurrentLotSize  = 0.01;

//--- Martingale/Anti-Martingale deal tracking (prevent reprocessing)
ulong  lastProcessedMartingaleDeal = 0;
int    lastMartingaleOpenTick = 0;

string EAComment = "Mr. Caffrey";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- 1. Set the EA's magic number for trade identification
   trade.SetExpertMagicNumber(InputMagicNumber);

//--- 2. Remove the chart grid
   ChartSetInteger(0, CHART_SHOW_GRID, false);

//--- 3. Input parameter checks and adjustments
   if(minOrderDistance > InputDelta)
      deltaX = minOrderDistance + 0.1;
   else
      deltaX = InputDelta;

   // NOTE: InputMaxTrailing is an 'input' variable and is read-only at runtime,
   // so the clamped result is stored in maxTrailingLimit instead.
   if(InputMaxTrailing > maxTrailingLimit)
      maxTrailingLimit = maxTrailingLimit + 0.1;
   else
      maxTrailingLimit = InputMaxTrailing;

   if(orderModificationFactor < 1)
      orderModificationFactor = 1;

//--- 4. Reset counters and fetch account leverage
   tickCounter     = 0;
   priceToPipRatio = 0;
   accountLeverage = AccountInfoInteger(ACCOUNT_LEVERAGE);

//--- 5. Query broker/symbol volume properties
   lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double minLotMargin = 0;
   if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, minLot, SymbolInfoDouble(_Symbol, SYMBOL_ASK), minLotMargin))
      marginMinLot = minLotMargin;

//--- 6. Check broker stop level and freeze level
   brokerStopLevel   = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   brokerFreezeLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);

   if(brokerStopLevel > 0)
      minStopDistance = brokerStopLevel + SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(brokerFreezeLevel > 0)
      minFreezeDistance = brokerFreezeLevel + SymbolInfoDouble(_Symbol, SYMBOL_POINT);

//--- 7. Warn on chart if broker enforces stop/freeze levels
   if(brokerStopLevel > 0 || brokerFreezeLevel > 0)
      Comment("Warning: broker enforces a Stop/Freeze level on ", _Symbol,
              ".  Stop level: ", brokerStopLevel, " pts   Freeze level: ", brokerFreezeLevel, " pts");

//--- 8. Initialize spread tracking using current Ask/Bid
   currentSpread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   averageSpread = currentSpread;

//--- 9. Size the spread history array based on EA mode
   if(eaModeFlag == 0)
      ArrayResize(spreadHistory, defaultSpreadPeriod);
   else
      ArrayResize(spreadHistory, 3);
   spreadArraySize = ArraySize(spreadHistory);

//--- 10. Store max allowed spread (in points) and hide chart indicators
   maxAllowedSpread = InputMaxSpread;

   int totalWindows = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
   for(int win = 0; win < totalWindows; win++)
     {
      int totalInd = ChartIndicatorsTotal(0, win);
      for(int i = totalInd - 1; i >= 0; i--)
        {
         string indName = ChartIndicatorName(0, win, i);
         ChartIndicatorDelete(0, win, indName);
        }
     }

//--- 11. Initialize indicator handles if their respective trail types are active
   if(TrailType == TSL_FAST_MA)
     {
      handle_MA = iMA(_Symbol, _Period, MA_Period, 0, MA_Method, MA_AppliedPrice);
      if(handle_MA == INVALID_HANDLE)
        {
         Print("Failed to initialize Fast MA handle.");
         return(INIT_FAILED);
        }
     }
   else if(TrailType == TSL_ICHIMOKU_TENKAN)
     {
      handle_Ichimoku = iIchimoku(_Symbol, _Period, 9, 26, 52);
      if(handle_Ichimoku == INVALID_HANDLE)
        {
         Print("Failed to initialize Ichimoku handle.");
         return(INIT_FAILED);
        }
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- TODO: deinitialization logic

  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Mode routing: Direct to appropriate trading system
   if(TradingMode == MODE_MARTINGALE && EnableMartingale)
     {
      executeMartingale();
      return;
     }
   else if(TradingMode == MODE_ANTIMARTINGALE && EnableAntiMartingale)
     {
      executeAntiMartingale();
      return;
     }
   
   // Continue with current system (MODE_CURRENT_SYSTEM is default)

//--- 1. Temporary working variables for this tick
   double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double calcPrice = 0;   // generic scratch variable, reused later for order price calculations

   tickCounter++;

//--- 2. Derive commissionPerPip / priceToPipRatio once, from trade history
   if(priceToPipRatio == 0)
     {
      if(HistorySelect(0, TimeCurrent()))
        {
         int totalDeals = HistoryDealsTotal();

         for(int i = totalDeals - 1; i >= 0; i--)
           {
            ulong dealTicket = HistoryDealGetTicket(i);
            if(dealTicket == 0)
               continue;

            dealInfo.Ticket(dealTicket);

            if(dealInfo.Symbol() != _Symbol)
               continue;
            if(dealInfo.Entry() != DEAL_ENTRY_OUT)
               continue;

            double profit = dealInfo.Profit();
            if(profit == 0)
               continue;

            double exitPrice  = dealInfo.Price();
            double entryPrice = 0;
            long   posId      = dealInfo.PositionId();

            //--- find the matching entry (opening) deal for this position
            for(int j = 0; j < totalDeals; j++)
              {
               ulong entryTicket = HistoryDealGetTicket(j);
               if(entryTicket == 0)
                  continue;

               dealInfo.Ticket(entryTicket);
               if(dealInfo.PositionId() == posId && dealInfo.Entry() == DEAL_ENTRY_IN)
                 {
                  entryPrice = dealInfo.Price();
                  break;
                 }
              }

            double priceDiff = MathAbs(exitPrice - entryPrice);
            if(priceDiff > 0)
              {
               priceToPipRatio = profit / priceDiff;

               dealInfo.Ticket(dealTicket);
               double commission = dealInfo.Commission();
               commissionPerPip  = -commission / priceToPipRatio;

               break;
              }
           }
        }
     }

//--- 3. Update the rolling spread history array
   if(spreadArraySize > 0)
     {
      double newSpread = ask - bid;

      for(int i = 0; i < spreadArraySize - 1; i++)
         spreadHistory[i] = spreadHistory[i + 1];

      spreadHistory[spreadArraySize - 1] = newSpread;
      currentSpread = newSpread;

//--- 4. Recalculate average spread, adjusted for commission
      double spreadSum = 0;
      for(int i = 0; i < spreadArraySize; i++)
         spreadSum += spreadHistory[i];

      averageSpread  = spreadSum / spreadArraySize;
      averageSpread += commissionPerPip;
     }

//--- 5. Derived trade-calculation variables
   double adjustedOrderDistance     = MathMax(averageSpread * InputDelta, minStopDistance + _Point);
   double minimumOrderModification  = MathMax(minOrderDistance * averageSpread, minStopDistance + _Point);
   double trailingStopActive        = averageSpread * InputMaxTrailing;
   double maxOrderPlacementDistance = InputMaxDistance * averageSpread;
   double orderPlacementStep        = minimumOrderModification / orderModificationFactor;
   double calculatedLotStop         = MathMax(InputStop * averageSpread, minStopDistance);

//--- 6. Scan open positions for this symbol/magic number
   int    openBuyCount  = 0;
   int    openSellCount = 0;
   int    totalBuyCount  = 0;
   int    totalSellCount = 0;

   double buyStopLoss  = 0;
   double sellStopLoss = 0;

   double buyOrderPriceSum  = 0;
   double sellOrderPriceSum = 0;
   double buyOrderSumLot    = 0;
   double sellOrderSumLot   = 0;

   double lowestBuyPrice   = DBL_MAX;
   double highestSellPrice = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!positionInfo.SelectByIndex(i))
         continue;
      if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != InputMagicNumber)
         continue;

      double posVolume = positionInfo.Volume();
      double posPrice  = positionInfo.PriceOpen();
      double posSL     = positionInfo.StopLoss();

      if(positionInfo.PositionType() == POSITION_TYPE_BUY)
        {
         openBuyCount++;
         totalBuyCount++;
         buyStopLoss = posSL;

         buyOrderPriceSum += posPrice * posVolume;
         buyOrderSumLot   += posVolume;

         if(posPrice < lowestBuyPrice)
            lowestBuyPrice = posPrice;
        }
      else
         if(positionInfo.PositionType() == POSITION_TYPE_SELL)
           {
            openSellCount++;
            totalSellCount++;
            sellStopLoss = posSL;

            sellOrderPriceSum += posPrice * posVolume;
            sellOrderSumLot   += posVolume;

            if(posPrice > highestSellPrice)
               highestSellPrice = posPrice;
           }
     }

//--- 7. Scan pending orders for this symbol/magic number
   int pendingBuyCount  = 0;
   int pendingSellCount = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!orderInfo.SelectByIndex(i))
         continue;
      if(orderInfo.Symbol() != _Symbol || orderInfo.Magic() != InputMagicNumber)
         continue;

      ENUM_ORDER_TYPE pendingType = orderInfo.OrderType();

      if(pendingType == ORDER_TYPE_BUY_STOP)
        {
         pendingBuyCount++;
         totalBuyCount++;
        }
      else
         if(pendingType == ORDER_TYPE_SELL_STOP)
           {
            pendingSellCount++;
            totalSellCount++;
           }
     }

//--- 8. Average entry prices, weighted by volume
   double averageBuyPrice  = 0;
   double averageSellPrice = 0;

   if(buyOrderSumLot > 0)
      averageBuyPrice = buyOrderPriceSum / buyOrderSumLot;

   if(sellOrderSumLot > 0)
      averageSellPrice = sellOrderPriceSum / sellOrderSumLot;

//--- 9. Evaluate position limits
   bool buyLimitReached  = false;
   bool sellLimitReached = false;
   
   if(MaxPositionsType == MAX_POS_GLOBAL)
     {
      if((openBuyCount + openSellCount) >= MaxPositions)
        {
         buyLimitReached  = true;
         sellLimitReached = true;
        }
     }
   else if(MaxPositionsType == MAX_POS_DIRECTIONAL)
     {
      if(openBuyCount >= MaxPositions)
         buyLimitReached  = true;
      if(openSellCount >= MaxPositions)
         sellLimitReached = true;
     }

//--- 10. Current broker time, parsed into a structure
   MqlDateTime brokerTime;
   TimeToStruct(TimeCurrent(), brokerTime);

//--- 11. Manage pending Buy Stop / Sell Stop orders
   bool withinTradingHours = (brokerTime.hour >= StartHour && brokerTime.hour < EndHour);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!orderInfo.SelectByIndex(i))
         continue;
      if(orderInfo.Symbol() != _Symbol || orderInfo.Magic() != InputMagicNumber)
         continue;

      ulong           ticket         = orderInfo.Ticket();
      ENUM_ORDER_TYPE pendOrderType  = orderInfo.OrderType();
      double          orderOpenPrice = orderInfo.PriceOpen();
      double          orderVolume    = orderInfo.VolumeInitial();
      double          orderStopLoss  = orderInfo.StopLoss();

      //--- Buy Stop management
      if(pendOrderType == ORDER_TYPE_BUY_STOP)
        {
         if(!withinTradingHours || averageSpread > maxAllowedSpread)
           {
            trade.OrderDelete(ticket);
            continue;
           }

         bool needsModification = false;

         if(((double)TimeCurrent() - lastBuyOrderTime) > Seconds)
            needsModification = true;

         if(tickCounter % orderCheckFrequency == 0)
            needsModification = true;

         bool buyDistanceCriteria = (MathAbs(orderOpenPrice - ask) < adjustedOrderDistance) ||
                                     (MathAbs(orderOpenPrice - ask) > maxOrderPlacementDistance);

         if(openBuyCount == 0 && buyDistanceCriteria)
            needsModification = true;

         if(needsModification)
           {
            double newPrice = ask + adjustedOrderDistance;
            double newSL    = newPrice - calculatedLotStop;

            bool freezeOk = (minFreezeDistance == 0) || (MathAbs(orderOpenPrice - ask) > minFreezeDistance);

            if(freezeOk)
              {
               if(trade.OrderModify(ticket, newPrice, newSL, 0, ORDER_TIME_GTC, 0, 0))
                  lastBuyOrderTime = (double)TimeCurrent();
              }
           }
        }

      //--- Sell Stop management (mirrored logic)
      else
         if(pendOrderType == ORDER_TYPE_SELL_STOP)
           {
            if(!withinTradingHours || averageSpread > maxAllowedSpread)
              {
               trade.OrderDelete(ticket);
               continue;
              }

            bool needsModification = false;

            if(((double)TimeCurrent() - lastSellOrderTime) > Seconds)
               needsModification = true;

            if(tickCounter % orderCheckFrequency == 0)
               needsModification = true;

            bool sellDistanceCriteria = (MathAbs(orderOpenPrice - bid) < adjustedOrderDistance) ||
                                         (MathAbs(orderOpenPrice - bid) > maxOrderPlacementDistance);

            if(openSellCount == 0 && sellDistanceCriteria)
               needsModification = true;

            if(needsModification)
              {
               double newPrice = bid - adjustedOrderDistance;
               double newSL    = newPrice + calculatedLotStop;

               bool freezeOk = (minFreezeDistance == 0) || (MathAbs(orderOpenPrice - bid) > minFreezeDistance);

               if(freezeOk)
                 {
                  if(trade.OrderModify(ticket, newPrice, newSL, 0, ORDER_TIME_GTC, 0, 0))
                     lastSellOrderTime = (double)TimeCurrent();
                 }
              }
           }
     }

//--- 12. Manage trailing stops for open positions
   trailStop(trailingStopActive, maxOrderPlacementDistance);

//--- 13. Close positions at profit target
   closeAtProfit();

//--- 14. Check per-position loss limit (Risk Control)
   checkPositionLossLimit();

//--- 15. Buy Stop order placement
   bool buyScalingAllowed = (openBuyCount == 0) ||
                             (MathAbs((lowestBuyPrice - buyStopLoss) - calculatedLotStop) < _Point);

   if(buyScalingAllowed && pendingBuyCount == 0 && !buyLimitReached &&
      averageSpread <= maxAllowedSpread && withinTradingHours)
     {
      double slPointsValue = calculatedLotStop / _Point;
      double buyLots       = calcLots(slPointsValue);

      double buyPrice = ask + adjustedOrderDistance;
      double buySL    = buyPrice - calculatedLotStop;

      double requiredMargin = 0;

      if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, buyLots, buyPrice, requiredMargin))
        {
         if(requiredMargin <= AccountInfoDouble(ACCOUNT_MARGIN_FREE))
           {
            if(trade.OrderOpen(_Symbol, ORDER_TYPE_BUY_STOP, buyLots, 0, buyPrice, buySL, 0,
                                ORDER_TIME_GTC, 0, EAComment))
              {
               lastBuyOrderTime = (double)TimeCurrent();
               lastOrderTime    = (double)TimeCurrent();
              }
           }
        }
     }

//--- 16. Sell Stop order placement (mirrored logic)
   bool sellScalingAllowed = (openSellCount == 0) ||
                              (MathAbs((sellStopLoss - highestSellPrice) - calculatedLotStop) < _Point);

   if(sellScalingAllowed && pendingSellCount == 0 && !sellLimitReached &&
      averageSpread <= maxAllowedSpread && withinTradingHours)
     {
      double slPointsValue = calculatedLotStop / _Point;
      double sellLots      = calcLots(slPointsValue);

      double sellPrice = bid - adjustedOrderDistance;
      double sellSL    = sellPrice + calculatedLotStop;

      double requiredMargin = 0;

      if(OrderCalcMargin(ORDER_TYPE_SELL, _Symbol, sellLots, sellPrice, requiredMargin))
        {
         if(requiredMargin <= AccountInfoDouble(ACCOUNT_MARGIN_FREE))
           {
            if(trade.OrderOpen(_Symbol, ORDER_TYPE_SELL_STOP, sellLots, 0, sellPrice, sellSL, 0,
                                ORDER_TIME_GTC, 0, EAComment))
              {
               lastSellOrderTime = (double)TimeCurrent();
               lastOrderTime     = (double)TimeCurrent();
              }
           }
        }
     }

  }
//+------------------------------------------------------------------+
//| Calculate a dynamic trailing-stop distance based on profit move  |
//+------------------------------------------------------------------+
double trailDistance(double priceMove, double minDistance, double activeDistance,
                      double baseDistance, double maxDistance)
  {
   if(maxDistance == 0)
      return(MathMax(activeDistance, minDistance));

   double ratio           = priceMove / maxDistance;
   double dynamicDistance = activeDistance - (baseDistance * ratio) + baseDistance;

   return(MathMax(dynamicDistance, minDistance));
  }
//+------------------------------------------------------------------+
//| Calculate trade volume based on the selected ENUM_LOT_TYPE       |
//+------------------------------------------------------------------+
double calcLots(double slPoints)
  {
   double lots = 0;

   if(LotType == LOT_FIXED)
     {
      lots = FixedLots;
     }
   else
     {
      double accountValue = 0;

      switch(LotType)
        {
         case LOT_PERCENT_BALANCE:
            accountValue = AccountInfoDouble(ACCOUNT_BALANCE);
            break;
         case LOT_PERCENT_EQUITY:
            accountValue = AccountInfoDouble(ACCOUNT_EQUITY);
            break;
         case LOT_PERCENT_FREE_MARGIN:
            accountValue = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
            break;
         default:
            accountValue = AccountInfoDouble(ACCOUNT_BALANCE);
            break;
        }

      double riskCash = accountValue * (RiskPercent / 100.0);

      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

      if(slPoints > 0 && tickSize > 0)
        {
         double valuePerPoint = (tickValue / tickSize) * _Point;
         double slCost        = slPoints * valuePerPoint;

         if(slCost > 0)
            lots = riskCash / slCost;
        }
     }

//--- enforce broker volume step, then clamp to broker min/max limits
   if(lotStep > 0)
      lots = MathRound(lots / lotStep) * lotStep;

   if(lots < minLot)
      lots = minLot;
   if(lots > maxLot)
      lots = maxLot;

//--- determine decimal precision implied by the lot step, then normalize
   int    lotDigits  = 0;
   double stepCheck  = lotStep;

   if(stepCheck > 0)
     {
      while(MathAbs(stepCheck - MathRound(stepCheck)) > 0.0000001 && lotDigits < 8)
        {
         stepCheck *= 10;
         lotDigits++;
        }
     }

   lots = NormalizeDouble(lots, lotDigits);

   return(lots);
  }
//+------------------------------------------------------------------+
//| Manage trailing stops for open positions with multiple strategies |
//+------------------------------------------------------------------+
void trailStop(double trailingStopActive, double maxOrderPlacementDistance)
  {
//--- If Default Trailing is selected, run the original V1 trailing logic and exit
   if(TrailType == TSL_DEFAULT)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!positionInfo.SelectByIndex(i))
            continue;
         if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != InputMagicNumber)
            continue;

         ulong  posTicket = positionInfo.Ticket();
         double openPrice = positionInfo.PriceOpen();
         double posSL     = positionInfo.StopLoss();
         double posTP     = positionInfo.TakeProfit();

         if(positionInfo.PositionType() == POSITION_TYPE_BUY)
           {
            double priceMove = SymbolInfoDouble(_Symbol, SYMBOL_BID) - openPrice + commissionPerPip;
            double trailDist = trailDistance(priceMove, minStopDistance, trailingStopActive,
                                              baseTrailingStop, maxOrderPlacementDistance);

            double modifiedStopLoss = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID) - trailDist, _Digits);
            double triggerLevel     = openPrice + commissionPerPip + incrementStop;

            if((SymbolInfoDouble(_Symbol, SYMBOL_BID) - triggerLevel) > trailDist)
              {
               if(posSL == 0 || (modifiedStopLoss - posSL) >= _Point)
                  trade.PositionModify(posTicket, modifiedStopLoss, posTP);
              }
           }
         else if(positionInfo.PositionType() == POSITION_TYPE_SELL)
           {
            double priceMove = openPrice - SymbolInfoDouble(_Symbol, SYMBOL_ASK) + commissionPerPip;
            double trailDist = trailDistance(priceMove, minStopDistance, trailingStopActive,
                                              baseTrailingStop, maxOrderPlacementDistance);

            double modifiedStopLoss = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK) + trailDist, _Digits);
            double triggerLevel     = openPrice - commissionPerPip - incrementStop;

            if((triggerLevel - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) > trailDist)
              {
               if(posSL == 0 || (posSL - modifiedStopLoss) >= _Point)
                  trade.PositionModify(posTicket, modifiedStopLoss, posTP);
              }
           }
        }
      return; // Exit early
     }

//--- V2 Dynamic Trailing Stop-Loss Logic (TrailType 1 to 4)
   double stopLoss        = 0;
   double takeProfit      = 0;
   double ask             = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid             = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double indicatorBuffer[];
   
   ArraySetAsSeries(indicatorBuffer, true);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!positionInfo.SelectByIndex(i))
         continue;
      if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != InputMagicNumber)
         continue;

      ulong  ticket    = positionInfo.Ticket();
      double openPrice = positionInfo.PriceOpen();
      double posSL     = positionInfo.StopLoss();
      takeProfit       = positionInfo.TakeProfit();

      //--- 1. BUY POSITION TRAILING
      if(positionInfo.PositionType() == POSITION_TYPE_BUY)
        {
         // Check if position profit has exceeded the trigger threshold
         if((bid - openPrice) > (TSL_TriggerPoint * _Point))
           {
            switch(TrailType)
              {
               case TSL_SCALPING:
                  stopLoss = bid - (TSL_Point * _Point);
                  break;

               case TSL_PREVIOUS_CANDLE:
                 {
                  double lowValues[];
                  if(CopyLow(_Symbol, _Period, 1, TSL_Candles, lowValues) > 0)
                    {
                     int minIndex = ArrayMinimum(lowValues);
                     stopLoss = lowValues[minIndex];
                    }
                  break;
                 }

               case TSL_FAST_MA:
                  if(CopyBuffer(handle_MA, 0, 1, 1, indicatorBuffer) > 0)
                     stopLoss = indicatorBuffer[0];
                  break;

               case TSL_ICHIMOKU_TENKAN:
                  if(CopyBuffer(handle_Ichimoku, 0, 1, 1, indicatorBuffer) > 0)
                     stopLoss = indicatorBuffer[0];
                  break;
                  
               default:
                  break;
              }

            stopLoss = NormalizeDouble(stopLoss, _Digits);

            // Safety rules: Ensure stopLoss is trailed upwards, non-zero, above entry, and respects broker stop limits
            if(stopLoss > posSL && stopLoss != 0 && stopLoss > openPrice && stopLoss < (bid - minStopDistance))
              {
               if(posSL == 0 || (stopLoss - posSL) >= _Point)
                  trade.PositionModify(ticket, stopLoss, takeProfit);
              }
           }
        }

      //--- 2. SELL POSITION TRAILING
      else if(positionInfo.PositionType() == POSITION_TYPE_SELL)
        {
         // Check if position profit has exceeded the trigger threshold
         if((openPrice - ask) > (TSL_TriggerPoint * _Point))
           {
            switch(TrailType)
              {
               case TSL_SCALPING:
                  stopLoss = ask + (TSL_Point * _Point);
                  break;

               case TSL_PREVIOUS_CANDLE:
                 {
                  double highValues[];
                  if(CopyHigh(_Symbol, _Period, 1, TSL_Candles, highValues) > 0)
                    {
                     int maxIndex = ArrayMaximum(highValues);
                     stopLoss = highValues[maxIndex];
                    }
                  break;
                 }

               case TSL_FAST_MA:
                  if(CopyBuffer(handle_MA, 0, 1, 1, indicatorBuffer) > 0)
                     stopLoss = indicatorBuffer[0];
                  break;

               case TSL_ICHIMOKU_TENKAN:
                  if(CopyBuffer(handle_Ichimoku, 0, 1, 1, indicatorBuffer) > 0)
                     stopLoss = indicatorBuffer[0];
                  break;
                  
               default:
                  break;
              }

            stopLoss = NormalizeDouble(stopLoss, _Digits);

            // Safety rules: Ensure stopLoss is trailed downwards, non-zero, below entry, and respects broker stop limits
            if((stopLoss < posSL || posSL == 0) && stopLoss != 0 && stopLoss < openPrice && stopLoss > (ask + minStopDistance))
              {
               if(posSL == 0 || (posSL - stopLoss) >= _Point)
                  trade.PositionModify(ticket, stopLoss, takeProfit);
              }
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Close positions when profit target is reached                     |
//+------------------------------------------------------------------+
void closeAtProfit()
  {
//--- Skip if feature is disabled or target amount is zero
   if(!EnableProfitTarget || ProfitTargetAmount <= 0)
      return;

//--- Loop through all open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!positionInfo.SelectByIndex(i))
         continue;
      if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != InputMagicNumber)
         continue;

      double profit = positionInfo.Profit();

      //--- Close position if profit meets or exceeds the target
      if(profit >= ProfitTargetAmount)
        {
         trade.PositionClose(positionInfo.Ticket());
        }
     }
  }
//+------------------------------------------------------------------+
//| Check per-position loss limit and close if exceeded               |
//| Prevents individual losses from snowballing                       |
//+------------------------------------------------------------------+
void checkPositionLossLimit()
  {
//--- Skip if feature is disabled or limit is 0
   if(!EnableMaxLossLimit || MaxLossPerPosition <= 0)
      return;

//--- Loop through all open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!positionInfo.SelectByIndex(i))
         continue;
      if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != InputMagicNumber)
         continue;

      double loss = positionInfo.Profit();

      //--- Close position if loss exceeds maximum allowed loss
      // Note: Profit is negative for losses, so we check if loss < -MaxLossPerPosition
      if(loss < -MaxLossPerPosition && loss < 0)
        {
         trade.PositionClose(positionInfo.Ticket());
         
         Print("⚠️ LOSS LIMIT TRIGGERED: Position closed - Loss: $", 
               MathAbs(loss), " | Max Allowed: $", MaxLossPerPosition);
        }
     }
  }
//+------------------------------------------------------------------+//+------------------------------------------------------------------+
//| MARTINGALE MODE: Scale up lot size on consecutive losses         |
//| WARNING: HIGH RISK - Can blow account quickly!                   |
//+------------------------------------------------------------------+
void executeMartingale()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

//--- Process closed deals only once per deal
   if(HistorySelect(TimeCurrent() - 86400, TimeCurrent()))  // Last 24 hours
     {
      int totalDeals = HistoryDealsTotal();
      
      if(totalDeals > 0)
        {
         ulong lastDeal = HistoryDealGetTicket(totalDeals - 1);
         
         // Only process if this is a NEW deal (not processed before)
         if(lastDeal != lastProcessedMartingaleDeal)
           {
            dealInfo.Ticket(lastDeal);
            
            if(dealInfo.Symbol() == _Symbol && dealInfo.Magic() == InputMagicNumber)
              {
               double profit = dealInfo.Profit();
               
               // Loss detected: Increase lot size
               if(profit < 0)
                 {
                  martingaleConsecutiveLosses++;
                  
                  if(martingaleConsecutiveLosses > MartingaleMaxLosses)
                    {
                     Print("⚠️ MARTINGALE: Max consecutive losses (", MartingaleMaxLosses, ") reached. Stopping.");
                     return;
                    }
                  
                  martingaleCurrentLotSize = MartingaleLotSize * MathPow(MartingaleMultiplier, martingaleConsecutiveLosses);
                  
                  if(martingaleCurrentLotSize > MartingaleMaxLot)
                     martingaleCurrentLotSize = MartingaleMaxLot;
                  
                  Print("MARTINGALE: Loss #", martingaleConsecutiveLosses, " | Next lot: ", martingaleCurrentLotSize);
                 }
               // Win detected: Reset
               else if(profit > 0)
                 {
                  Print("✓ MARTINGALE: Win! $", profit, " | Reset lot to ", MartingaleLotSize);
                  martingaleConsecutiveLosses = 0;
                  martingaleCurrentLotSize = MartingaleLotSize;
                 }
               
               lastProcessedMartingaleDeal = lastDeal;  // Mark as processed
              }
           }
        }
     }

//--- Count open positions
   int openPositions = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(positionInfo.SelectByIndex(i))
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InputMagicNumber)
            openPositions++;
     }

//--- Cooldown: Only open one position per 10 ticks (prevent spam)
   if(openPositions == 0 && (tickCounter - lastMartingaleOpenTick) >= 10)
     {
      ENUM_ORDER_TYPE direction = (rand() % 2 == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      
      double entryPrice = (direction == ORDER_TYPE_BUY) ? ask : bid;
      double slPrice = (direction == ORDER_TYPE_BUY) ? 
                       (entryPrice - MartingaleStopLoss * _Point) : 
                       (entryPrice + MartingaleStopLoss * _Point);
      double tpPrice = (direction == ORDER_TYPE_BUY) ? 
                       (entryPrice + MartingaleTakeProfit * _Point) : 
                       (entryPrice - MartingaleTakeProfit * _Point);
      
      if(trade.OrderOpen(_Symbol, direction, martingaleCurrentLotSize, entryPrice, 
                         3, slPrice, tpPrice, ORDER_TIME_GTC, 0, "Martingale"))
        {
         lastMartingaleOpenTick = tickCounter;
         Print("MARTINGALE: Opening position - Lot: ", martingaleCurrentLotSize, 
               " | Consecutive Losses: ", martingaleConsecutiveLosses);
        }
     }
  }
//+------------------------------------------------------------------+
//| ANTI-MARTINGALE MODE: Scale up on wins, down on losses (SAFER)   |
//+------------------------------------------------------------------+
void executeAntiMartingale()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

//--- Process closed deals only once per deal
   if(HistorySelect(TimeCurrent() - 86400, TimeCurrent()))  // Last 24 hours
     {
      int totalDeals = HistoryDealsTotal();
      
      if(totalDeals > 0)
        {
         ulong lastDeal = HistoryDealGetTicket(totalDeals - 1);
         
         // Only process if this is a NEW deal (not processed before)
         if(lastDeal != lastProcessedMartingaleDeal)
           {
            dealInfo.Ticket(lastDeal);
            
            if(dealInfo.Symbol() == _Symbol && dealInfo.Magic() == InputMagicNumber)
              {
               double profit = dealInfo.Profit();
               
               // Win detected: Increase lot size
               if(profit > 0)
                 {
                  antiMartingaleConsecutiveWins++;
                  antiMartingaleCurrentLotSize = AntiMartingaleLotSize * MathPow(AntiMartingaleMultiplier, antiMartingaleConsecutiveWins);
                  
                  if(antiMartingaleCurrentLotSize > AntiMartingaleMaxLot)
                     antiMartingaleCurrentLotSize = AntiMartingaleMaxLot;
                  
                  Print("ANTI-MARTINGALE: Win #", antiMartingaleConsecutiveWins, " | Next lot: ", antiMartingaleCurrentLotSize);
                 }
               // Loss detected: Reset
               else if(profit < 0)
                 {
                  Print("⚠️ ANTI-MARTINGALE: Loss! -$", MathAbs(profit), " | Reset lot to ", AntiMartingaleLotSize);
                  antiMartingaleConsecutiveWins = 0;
                  antiMartingaleCurrentLotSize = AntiMartingaleLotSize;
                 }
               
               lastProcessedMartingaleDeal = lastDeal;  // Mark as processed
              }
           }
        }
     }

//--- Count open positions
   int openPositions = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(positionInfo.SelectByIndex(i))
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InputMagicNumber)
            openPositions++;
     }

//--- Cooldown: Only open one position per 10 ticks (prevent spam)
   if(openPositions == 0 && (tickCounter - lastMartingaleOpenTick) >= 10)
     {
      ENUM_ORDER_TYPE direction = (rand() % 2 == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      
      double entryPrice = (direction == ORDER_TYPE_BUY) ? ask : bid;
      double slPrice = (direction == ORDER_TYPE_BUY) ? 
                       (entryPrice - AntiMartingaleStopLoss * _Point) : 
                       (entryPrice + AntiMartingaleStopLoss * _Point);
      double tpPrice = (direction == ORDER_TYPE_BUY) ? 
                       (entryPrice + AntiMartingaleTakeProfit * _Point) : 
                       (entryPrice - AntiMartingaleTakeProfit * _Point);
      
      if(trade.OrderOpen(_Symbol, direction, antiMartingaleCurrentLotSize, entryPrice, 
                         3, slPrice, tpPrice, ORDER_TIME_GTC, 0, "Anti-Martingale"))
        {
         lastMartingaleOpenTick = tickCounter;
         Print("ANTI-MARTINGALE: Opening position - Lot: ", antiMartingaleCurrentLotSize, 
               " | Consecutive Wins: ", antiMartingaleConsecutiveWins);
        }
     }
  }
//+------------------------------------------------------------------+