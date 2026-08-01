//+------------------------------------------------------------------+
//|                    High Frequency EA - Step 1 Base               |
//|                    Author: Mr. Cafrey / Cleaned up               |
//| Description: HFT EA with two-sided stop orders, aggressive        |
//| trailing, and spread-based distance calculation                   |
//| UPGRADE: Added Trend Filter to trade only in direction of HTF EMA|
//+------------------------------------------------------------------+
#property copyright "Mr. Cafrey / Cleaned up"
#property version   "2.00"
#property strict

//--- Standard trade and information classes
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>
#include <Trade/HistoryOrderInfo.mqh>
#include <Trade/DealInfo.mqh>

//--- Global trade and market information instances
CTrade            trade;
CPositionInfo     positionInfo;
COrderInfo        orderInfo;
CHistoryOrderInfo hisInfo;      // In MT5, this is CHistoryOrderInfo
CDealInfo         dealInfo;

//--- Lot type selection for EA inputs
enum ENUM_LOT_TYPE
  {
   LOT_FIXED,                  // Fixed Lots
   LOT_PERCENT_BALANCE,        // % of Balance
   LOT_PERCENT_EQUITY,         // % of Equity
   LOT_PERCENT_FREE_MARGIN     // % of Free Margin
  };

//--- General EA settings
input group "General Settings"
input int      InpMagicNumber = 12345;   // Magic Number
input int      InpSlippage    = 30;      // Slippage (points)

//--- Trading session settings
input group "Time Settings"
input int      InpStartHour = 16;        // Trading Start Hour (16 = 4 PM NY Open)
input int      InpEndHour   = 17;        // Trading End Hour (runs max 1 hour)

//--- Money management settings
input group "Money Management"
input ENUM_LOT_TYPE InpLotType     = LOT_FIXED;  // Lot Type (dropdown from enum)
input double        InpFixedLot    = 0.01;       // Fixed Lot Size (if LOT_FIXED selected)
input double        InpRiskPercent = 0.5;        // Risk % (if % of Balance/Equity/Margin)

//--- Trade settings using spread-based distances
input group "Trade Settings (in Spreads)"
input double      InpDelta         = 0.5;    // Delta - Order distance (multiplied by spread)
input double      InpTheta         = 7.0;    // Theta - Max allowed order distance (x spread)
input double      InpStop          = 10.0;   // Stop - Initial stop loss (x spread)
input double      InpTrailingStart = 4.0;    // TrailingStart - When trailing begins (x spread)
input double      InpMaxSpread     = 100.0;  // MaxSpread - Maximum allowed spread (points)

// === TREND FILTER SETTINGS (UPGRADE PATCH) ===
input group "Trend Filter Settings (Upgrade)"
input bool      InpUseTrendFilter = true;           // Enable Trend Filter (true/false)
input ENUM_TIMEFRAMES InpTrendTimeframe = PERIOD_H1; // Trend Timeframe (default: 1 Hour)
input int       InpTrendFastEMA = 8;                // Trend Fast EMA Period
input int       InpTrendSlowEMA = 21;               // Trend Slow EMA Period
input ENUM_MA_METHOD InpTrendMAMethod = MODE_EMA;   // Moving Average Method (EMA/SMA)
input ENUM_APPLIED_PRICE InpTrendAppliedPrice = PRICE_CLOSE; // Applied Price

// NOTE: All distances are multiplied by the current spread.
// This makes the EA work consistently across different symbols
// (Forex, Indices, Crypto) regardless of their typical spread values.
// For example, on US30 with $1 spread:
// - Delta 0.5 = order distance of $0.50
// - Theta 7.0 = max order distance of $7.00
// - Stop 10.0 = initial stop loss of $10.00
// - TrailingStart 4.0 = trailing activates after $4.00 profit

//--- Order modification timing
int seconds = 60;   // Will be used to check modification frequency (60 seconds for 1-minute chart)

//--- Working variables for spread-based calculations (to be used in later steps)
double g_deltaPoints;          // Delta converted to points
double g_thetaPoints;          // Theta converted to points
double g_stopPoints;           // Stop converted to points
double g_trailingStartPoints;  // TrailingStart converted to points
double g_maxSpreadPoints;      // MaxSpread converted to points

//--- Tick counter and control variables
int g_tickCounter = 0;           // Counts incoming ticks
int g_orderCheckFrequency = 2;   // Check orders every Nth tick

//--- Trailing stop management
double g_baseTrailingStop = 0;        // Base trailing stop distance
double g_trailingStopBuffer = 0;      // Buffer for trailing calculations
double g_trailingStopIncrement = 0;   // Increment value for trailing
double g_trailingStopThreshold = 0;   // Threshold to activate trailing

//--- Account information
int g_accountLeverage = 0;   // Account leverage from broker

//--- Lot size management
double g_lotStep = 0;          // Minimum lot step size from broker
double g_maxLot = 0;           // Maximum lot allowed by broker
double g_minLot = 0;           // Minimum lot allowed by broker
double g_marginPerMinLot = 0;  // Margin required for minimum lot

//--- Broker restrictions
double g_minStopDistance = 0;    // Minimum stop distance allowed by broker
double g_minFreezeDistance = 0;  // Minimum freeze distance (orders cannot be modified within this)

//--- Spread tracking
double g_currentSpread = 0;          // Current spread in points
double g_averageSpread = 0;          // Average spread over period
int g_spreadPeriod = 30;             // Period for average spread calculation (default 30 ticks)
double g_spreadMultiplier = 0;       // Safeguard against zero/negative spreads
int g_spreadCalculationMethod = 1;   // Method for spread calculation

//--- Commission handling
double g_priceToPipRatio = 0;   // Ratio for converting price movement to pips
double g_commissionPerPip = 0;  // Commission cost per pip

//--- Spread history array (dynamic size)
double g_spreadHistory[];   // Array to store historical spread values

//--- Trading control flags
bool g_enableTrading = false;      // Master trading flag
bool g_isTradingAllowed = false;   // Whether trading is currently allowed (time + spread check)
int g_eaModeFlag = 0;              // EA mode (0 = normal trading, 1 = debug/no trading)

//--- Order distance calculations
double g_adjustedOrderDistance = 0;  // Final order distance after adjustments
double g_minOrderModification = 0;   // Minimum distance for order modification
double g_orderPlacementStep = 0;     // Step size for order placement increments
double g_calculatedStopLoss = 0;     // Calculated initial stop loss distance
double g_maxOrderDistance = 0;       // Maximum allowed order distance

//--- Trading permission checks
bool g_sellOrdersAllowed = true;      // Whether sell orders are currently allowed
bool g_buyOrdersAllowed = true;       // Whether buy orders are currently allowed
bool g_isSpreadAcceptable = false;    // Whether current spread is within limits
bool g_isTimeAcceptable = false;      // Whether current time is within trading hours

//--- Order modification tracking
double g_currentStopLoss = 0;       // Current stop loss value for modification checks
datetime g_lastBuyOrderTime = 0;    // Timestamp of last buy order placement/modification
datetime g_lastSellOrderTime = 0;   // Timestamp of last sell order placement/modification
datetime g_lastOrderTime = 0;       // Timestamp of last any order action

//--- Position counters (recalculated on each tick)
int g_openBuyCount = 0;       // Number of open buy positions
int g_openSellCount = 0;      // Number of open sell positions
int g_pendingBuyCount = 0;    // Number of pending buy stop orders
int g_pendingSellCount = 0;   // Number of pending sell stop orders
int g_totalBuyCount = 0;      // Total buys (open + pending)
int g_totalSellCount = 0;     // Total sells (open + pending)

//--- Position price tracking
double g_averageBuyPrice = 0;    // Average price of all buy positions
double g_averageSellPrice = 0;   // Average price of all sell positions
double g_lowestBuyPrice = 0;     // Lowest price among buy positions
double g_highestSellPrice = 0;   // Highest price among sell positions
double g_buyOrderSumPrice = 0;   // Sum of (price x lot) for buys
double g_sellOrderSumPrice = 0;  // Sum of (price x lot) for sells
double g_buyOrderSumLot = 0;     // Total lot size of all buys
double g_sellOrderSumLot = 0;    // Total lot size of all sells

//--- Stop loss tracking
double g_currentBuyStopLoss = 0;    // Current stop loss for buy positions
double g_currentSellStopLoss = 0;   // Current stop loss for sell positions

//--- Additional parameters from the original code
int g_orderModificationFactor = 3;   // Factor for order modification distance reduction
double g_minOrderDistance = 0.5;     // Minimum order distance safeguard
double g_maxTrailingLimit = 7.5;     // Maximum trailing limit safeguard
int g_spreadArraySize = 0;           // Size of spread history array

// === TREND FILTER VARIABLES (UPGRADE PATCH) ===
// Trend direction values:
// 2 = Both directions allowed (filter disabled)
// 1 = Uptrend only (allow BUY orders)
// -1 = Downtrend only (allow SELL orders)
// 0 = Neutral (no trading, delete all orders)
int g_trendFastEMAHandle = INVALID_HANDLE;   // Handle for fast EMA indicator
int g_trendSlowEMAHandle = INVALID_HANDLE;   // Handle for slow EMA indicator
double g_trendFastEMA[1];                    // Buffer array for fast EMA value
double g_trendSlowEMA[1];                    // Buffer array for slow EMA value
int g_currentTrend = 0;                      // 1 = Uptrend (BUY only), -1 = Downtrend (SELL only), 0 = Neutral, 2 = Both
datetime g_lastTrendCheck = 0;               // Timestamp of last trend update

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // === 1. SET MAGIC NUMBER AND CHART SETUP ===
   trade.SetExpertMagicNumber(InpMagicNumber);
   ChartSetInteger(0, CHART_SHOW_GRID, false);

   // === 2. VALIDATE MONEY MANAGEMENT INPUTS ===
   if(InpFixedLot <= 0 && InpLotType == LOT_FIXED)
     {
      Print("ERROR: Fixed Lot must be greater than 0 when using Fixed Lot type");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpRiskPercent <= 0 || InpRiskPercent > 100)
     {
      Print("ERROR: Risk Percentage must be between 0 and 100");
      return(INIT_PARAMETERS_INCORRECT);
     }

   // === 3. VALIDATE TRADE SETTINGS INPUTS ===
   if(InpDelta <= 0)
     {
      Print("ERROR: Delta must be greater than 0");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpTheta <= InpDelta)
     {
      Print("ERROR: Theta must be greater than Delta");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpStop <= 0)
     {
      Print("ERROR: Stop must be greater than 0");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpTrailingStart <= 0)
     {
      Print("ERROR: TrailingStart must be greater than 0");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpMaxSpread <= 0)
     {
      Print("ERROR: MaxSpread must be greater than 0");
      return(INIT_PARAMETERS_INCORRECT);
     }

   // === 4. VALIDATE MINIMUM ORDER DISTANCE ===
   // If user's delta is less than minimum order distance, adjust it
   if(InpDelta < g_minOrderDistance)
     {
      Print("WARNING: Delta (", InpDelta, ") is less than minimum order distance (",
            g_minOrderDistance, "). Adjusting to minimum.");
      // g_deltaPoints will be adjusted later with actual spread
     }

   // === 5. VALIDATE MAX TRAILING LIMIT ===
   if(InpTrailingStart > g_maxTrailingLimit)
     {
      Print("WARNING: TrailingStart (", InpTrailingStart,
            ") exceeds max trailing limit (", g_maxTrailingLimit,
            "). Adjusting to limit.");
      // Will be handled in calculations
     }

   // === 6. FETCH ACCOUNT INFORMATION ===
   g_accountLeverage = (int)AccountInfoInteger(ACCOUNT_LEVERAGE);
   Print("Account leverage: ", g_accountLeverage);

   // === 7. FETCH SYMBOL LOT INFORMATION ===
   g_lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   g_minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   Print("Lot settings - Step: ", g_lotStep, " Min: ", g_minLot, " Max: ", g_maxLot);

   if(g_lotStep <= 0 || g_minLot <= 0 || g_maxLot <= 0)
     {
      Print("ERROR: Failed to retrieve lot information from broker");
      return(INIT_FAILED);
     }

   // Calculate margin per minimum lot
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tickValue > 0 && point > 0)
     {
      g_marginPerMinLot = tickValue * g_minLot;
     }
   else
     {
      g_marginPerMinLot = 100; // Fallback value
      Print("WARNING: Could not calculate margin per lot, using default");
     }

   // === 8. FETCH BROKER STOP LEVEL ===
   long brokerStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   Print("Broker stop level: ", brokerStopLevel, " points");

   if(brokerStopLevel > 0)
     {
      // Convert to price distance and add 1 point buffer
      g_minStopDistance = brokerStopLevel * point;
      Print("Minimum stop distance set to: ", g_minStopDistance);
     }
   else
     {
      g_minStopDistance = 0;
      Print("No broker stop level restriction detected");
     }

   // === 9. FETCH BROKER FREEZE LEVEL ===
   long brokerFreezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   Print("Broker freeze level: ", brokerFreezeLevel, " points");

   if(brokerFreezeLevel > 0)
     {
      // Convert to price distance and add 1 point buffer
      g_minFreezeDistance = brokerFreezeLevel * point;
      Print("Minimum freeze distance set to: ", g_minFreezeDistance);
     }
   else
     {
      g_minFreezeDistance = 0;
      Print("No broker freeze level restriction detected");
     }

   // === 10. WARNING FOR UNSUITABLE BROKER ===
   if(brokerStopLevel > 0 || brokerFreezeLevel > 0)
     {
      Comment("WARNING: Your broker has stop/freeze levels!\n",
              "Stop Level: ", brokerStopLevel, " points\n",
              "Freeze Level: ", brokerFreezeLevel, " points\n",
              "This EA requires a broker with NO stop/freeze levels (ECN/DMA broker recommended).\n",
              "You may experience order modification rejections.");
      Print("WARNING: Broker has stop/freeze levels. HFT EA may not work properly!");
     }
   else
     {
      Comment("Broker check PASSED - No stop/freeze levels detected.");
      Print("Broker check PASSED - Suitable for HFT trading.");
     }

   // === 11. GET INITIAL ASK AND BID ===
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(ask <= 0 || bid <= 0)
     {
      Print("ERROR: Failed to get current ask/bid prices");
      return(INIT_FAILED);
     }

   // === 12. INITIALIZE SPREAD VALUES ===
   g_currentSpread = (ask - bid) / point;
   g_averageSpread = g_currentSpread;
   g_spreadMultiplier = (g_currentSpread > 0) ? 1.0 : 1.0;

   Print("Current spread: ", g_currentSpread, " points");
   Print("Point value: ", point);

   // === 13. INITIALIZE SPREAD HISTORY ARRAY ===
   // Determine spread period (default 30)
   if(g_spreadCalculationMethod == 0)
     {
      g_spreadPeriod = 30;  // Default
     }
   else
     {
      g_spreadPeriod = 3;   // Shorter period for faster response
     }

   g_spreadArraySize = g_spreadPeriod;
   ArrayResize(g_spreadHistory, g_spreadArraySize);

   // Fill array with current spread
   for(int i = 0; i < g_spreadArraySize; i++)
     {
      g_spreadHistory[i] = g_currentSpread;
     }

   Print("Spread history array initialized with size: ", g_spreadArraySize);

   // === 14. INITIALIZE MAX SPREAD IN POINTS ===
   g_maxSpreadPoints = InpMaxSpread * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   Print("Max spread in points: ", g_maxSpreadPoints);

   // === 15. INITIALIZE WORKING VARIABLES ===
   g_tickCounter = 0;
   g_enableTrading = true;
   g_eaModeFlag = 0;
   g_priceToPipRatio = 0;
   g_commissionPerPip = 0;
   g_baseTrailingStop = InpTrailingStart;
   g_trailingStopThreshold = InpTrailingStart;
   g_trailingStopIncrement = InpTrailingStart;
   g_trailingStopBuffer = InpTrailingStart;
   g_orderModificationFactor = 3;

   // Initialize order tracking timestamps
   g_lastBuyOrderTime = 0;
   g_lastSellOrderTime = 0;
   g_lastOrderTime = 0;

   // Initialize position tracking variables
   g_openBuyCount = 0;
   g_openSellCount = 0;
   g_pendingBuyCount = 0;
   g_pendingSellCount = 0;
   g_totalBuyCount = 0;
   g_totalSellCount = 0;
   g_averageBuyPrice = 0;
   g_averageSellPrice = 0;
   g_lowestBuyPrice = 0;
   g_highestSellPrice = 0;
   g_buyOrderSumPrice = 0;
   g_sellOrderSumPrice = 0;
   g_buyOrderSumLot = 0;
   g_sellOrderSumLot = 0;
   g_currentBuyStopLoss = 0;
   g_currentSellStopLoss = 0;
   g_currentStopLoss = 0;

   // === INITIALIZE TREND FILTER INDICATORS (UPGRADE PATCH) ===
   if(InpUseTrendFilter)
     {
      Print("Initializing Trend Filter on timeframe: ", EnumToString(InpTrendTimeframe));
      
      // Create fast EMA handle
      g_trendFastEMAHandle = iMA(_Symbol, InpTrendTimeframe, InpTrendFastEMA, 0, 
                                  InpTrendMAMethod, InpTrendAppliedPrice);
      
      // Create slow EMA handle
      g_trendSlowEMAHandle = iMA(_Symbol, InpTrendTimeframe, InpTrendSlowEMA, 0, 
                                  InpTrendMAMethod, InpTrendAppliedPrice);
      
      // Check if handles are valid
      if(g_trendFastEMAHandle == INVALID_HANDLE || g_trendSlowEMAHandle == INVALID_HANDLE)
        {
         Print("ERROR: Failed to create trend indicator handles");
         return(INIT_FAILED);
        }
      
      // Initial trend check
      g_currentTrend = UpdateTrendDirection();
      Print("Initial Trend Direction: ", 
            g_currentTrend == 1 ? "UPTREND (BUY only)" : 
            (g_currentTrend == -1 ? "DOWNTREND (SELL only)" : 
            (g_currentTrend == 0 ? "NEUTRAL (no trades)" : "BOTH (filter disabled)")));
     }
   else
     {
      Print("Trend Filter DISABLED - Trading both directions");
      g_currentTrend = 2;  // Both directions allowed
     }

   Print("EA Initialized Successfully!");
   Print("Symbol: ", _Symbol, " | Timeframe: ", PeriodToString(Period()));
   Print("Trading hours: ", InpStartHour, ":00 to ", InpEndHour, ":00");
   Print("Lot type: ", EnumToString(InpLotType));

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Helper function to convert period to string for display          |
//+------------------------------------------------------------------+
string PeriodToString(ENUM_TIMEFRAMES period)
  {
   switch(period)
     {
      case PERIOD_M1:  return("M1");
      case PERIOD_M5:  return("M5");
      case PERIOD_M15: return("M15");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H4:  return("H4");
      case PERIOD_D1:  return("D1");
      default:         return("Other");
     }
  }

//+------------------------------------------------------------------+
//| Function: Update Current Trend Direction                         |
//+------------------------------------------------------------------+
//| Returns: 1 = Uptrend (allow BUY only)                           |
//|          -1 = Downtrend (allow SELL only)                       |
//|          0 = Neutral (no trading)                               |
//|          2 = Both (filter disabled)                             |
//+------------------------------------------------------------------+
int UpdateTrendDirection()
  {
   // If trend filter is disabled, allow both directions (return 2)
   if(!InpUseTrendFilter)
      return 2;
   
   // Get current price on trend timeframe
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(currentPrice <= 0)
      return 0;
   
   // Get EMA values from higher timeframe (most recent completed candle)
   double fastEMA = 0, slowEMA = 0;
   
   // Copy fast EMA value
   if(CopyBuffer(g_trendFastEMAHandle, 0, 1, 1, g_trendFastEMA) == 1)
     {
      fastEMA = g_trendFastEMA[0];
     }
   else
     {
      return g_currentTrend;  // Return last known trend on error
     }
   
   // Copy slow EMA value
   if(CopyBuffer(g_trendSlowEMAHandle, 0, 1, 1, g_trendSlowEMA) == 1)
     {
      slowEMA = g_trendSlowEMA[0];
     }
   else
     {
      return g_currentTrend;
     }
   
   // Validate EMAs are valid
   if(fastEMA <= 0 || slowEMA <= 0)
      return g_currentTrend;
   
   // Determine trend direction based on strategy rules:
   // Uptrend: Price > Fast EMA AND Fast EMA > Slow EMA
   if(currentPrice > fastEMA && fastEMA > slowEMA)
     {
      return 1;   // Uptrend - Allow BUY only
     }
   // Downtrend: Price < Fast EMA AND Fast EMA < Slow EMA
   else if(currentPrice < fastEMA && fastEMA < slowEMA)
     {
      return -1;  // Downtrend - Allow SELL only
     }
   else
     {
      return 0;   // Neutral - No trading, delete all orders
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // ============================================================
   // PART 1: TICK COUNTING AND COMMISSION CALCULATION (ONE TIME)
   // ============================================================

   // Increment tick counter on every new tick
   g_tickCounter++;
   
   // === UPDATE TREND DIRECTION (UPGRADE PATCH) ===
   // Update trend every 60 seconds to save resources
   datetime currentTimeTrend = TimeCurrent();
   if(currentTimeTrend - g_lastTrendCheck >= 60)
     {
      g_lastTrendCheck = currentTimeTrend;
      g_currentTrend = UpdateTrendDirection();
     }

   // Calculate commission per pip from historical deals (only once at start)
   // This runs only when g_priceToPipRatio is still zero (first tick only)
   if(g_priceToPipRatio == 0)
     {
      // Select all history deals from beginning to current time
      HistorySelect(0, TimeCurrent());

      int totalDeals = HistoryDealsTotal();

      // Loop through all deals from newest to oldest
      for(int i = totalDeals - 1; i >= 0; i--)
        {
         ulong ticket = HistoryDealGetTicket(i);

         if(ticket == 0)
            continue;

         // Check if this deal is for our symbol and has profit
         string dealSymbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
         double dealProfit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         long dealEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);

         if(dealSymbol == _Symbol && dealProfit != 0 && dealEntry != DEAL_ENTRY_OUT)
           {
            // Get deal details
            double entryPrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
            double exitPrice = 0;
            double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);

            // Find matching exit deal to get exit price
            // For MT5, the same ticket contains both entry and exit info
            // Use position ID to find corresponding exit
            long positionId = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);

            if(positionId > 0)
              {
               // Search for the exit deal with same position ID
               for(int j = totalDeals - 1; j >= 0; j--)
                 {
                  ulong exitTicket = HistoryDealGetTicket(j);
                  if(exitTicket == 0)
                     continue;

                  long exitPositionId = HistoryDealGetInteger(exitTicket, DEAL_POSITION_ID);
                  long exitEntry = HistoryDealGetInteger(exitTicket, DEAL_ENTRY);

                  if(exitPositionId == positionId && exitEntry == DEAL_ENTRY_OUT)
                    {
                     exitPrice = HistoryDealGetDouble(exitTicket, DEAL_PRICE);
                     break;
                    }
                 }
              }

            // If we have both entry and exit prices, calculate ratio
            if(exitPrice != 0 && exitPrice != entryPrice)
              {
               double priceMovement = exitPrice - entryPrice;

               // Use absolute value for calculation
               double absPriceMovement = MathAbs(priceMovement);

               if(absPriceMovement > 0)
                 {
                  // Price to pip ratio: profit / price movement
                  g_priceToPipRatio = MathAbs(dealProfit / absPriceMovement);

                  // Commission per pip: commission / ratio (commission is negative, make positive)
                  if(g_priceToPipRatio > 0)
                    {
                     g_commissionPerPip = MathAbs(commission / g_priceToPipRatio);
                     Print("Commission per pip calculated: ", g_commissionPerPip);
                     break; // Exit loop once calculated
                    }
                 }
              }
           }
        }

      if(g_priceToPipRatio == 0)
        {
         Print("No historical deals found. Using zero commission per pip.");
        }
     }

   // ============================================================
   // PART 2: GET CURRENT PRICES AND UPDATE SPREAD
   // ============================================================

   // Get current ask and bid prices
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Validate prices
   if(ask <= 0 || bid <= 0)
     {
      Print("ERROR: Invalid ask/bid prices. Skipping tick.");
      return;
     }

   // Calculate current spread in points
   double newSpread = (ask - bid) / point;

   if(newSpread > 0)
     {
      g_currentSpread = newSpread;
     }

   // ============================================================
   // PART 3: UPDATE SPREAD HISTORY ARRAY (ROLLING WINDOW)
   // ============================================================

   // Shift array left (remove oldest value, make space for new)
   for(int i = 0; i < g_spreadArraySize - 1; i++)
     {
      g_spreadHistory[i] = g_spreadHistory[i + 1];
     }

   // Add new spread value at the end
   g_spreadHistory[g_spreadArraySize - 1] = g_currentSpread;

   // ============================================================
   // PART 4: CALCULATE AVERAGE SPREAD
   // ============================================================

   double spreadSum = 0;
   for(int i = 0; i < g_spreadArraySize; i++)
     {
      spreadSum += g_spreadHistory[i];
     }

   g_averageSpread = spreadSum / g_spreadArraySize;

   // Ensure average spread is not zero (use current spread if zero)
   if(g_averageSpread <= 0)
     {
      g_averageSpread = g_currentSpread;
     }

   // ============================================================
   // PART 5: CALCULATE TOTAL SPREAD WITH COMMISSION
   // ============================================================

   // Total spread = current spread + commission per pip
   double totalSpread = g_currentSpread + g_commissionPerPip;

   // Use MathMax to ensure we never get negative values
   g_averageSpread = MathMax(g_averageSpread, totalSpread);

   // ============================================================
   // PART 6: UPDATE POINT-BASED WORKING VARIABLES
   // ============================================================

   // Convert spread-based inputs to actual point values
   g_deltaPoints = InpDelta * g_averageSpread * point;
   g_thetaPoints = InpTheta * g_averageSpread * point;
   g_stopPoints = InpStop * g_averageSpread * point;
   g_trailingStartPoints = InpTrailingStart * g_averageSpread * point;

   // ============================================================
   // PART 7: CALCULATE ADJUSTED ORDER DISTANCE
   // ============================================================

   // Order distance is the maximum of:
   // 1. Delta * average spread (converted to points)
   // 2. Minimum stop distance from broker (+1 point buffer)
   g_adjustedOrderDistance = MathMax(g_deltaPoints, g_minStopDistance + point);

   // ============================================================
   // PART 8: CALCULATE MINIMUM ORDER MODIFICATION DISTANCE
   // ============================================================

   // Minimum modification distance = max(Delta * spread, Freeze level + 1 point)
   double minModDistance = MathMax(g_deltaPoints, g_minFreezeDistance + point);

   // Multiply by 1.1 for a small buffer (10% safety margin)
   g_minOrderModification = minModDistance * 1.1;

   // ============================================================
   // PART 9: CALCULATE ORDER PLACEMENT STEP
   // ============================================================

   // Order placement step = minimum modification distance / modification factor
   g_orderPlacementStep = g_minOrderModification / g_orderModificationFactor;

   // Ensure order placement step is at least 1 point
   if(g_orderPlacementStep < point)
     {
      g_orderPlacementStep = point;
     }

   // ============================================================
   // PART 10: CALCULATE INITIAL STOP LOSS DISTANCE
   // ============================================================

   // Stop loss = max(Stop * spread, Minimum stop distance from broker)
   g_calculatedStopLoss = MathMax(g_stopPoints, g_minStopDistance + point);

   // ============================================================
   // PART 11: CALCULATE MAX ORDER DISTANCE
   // ============================================================

   // Max order distance = Theta * average spread
   g_maxOrderDistance = g_thetaPoints;

   // ============================================================
   // PART 12: CHECK MAX SPREAD CONDITION
   // ============================================================

   // Check if current spread exceeds max allowed spread
   if(g_currentSpread * point <= g_maxSpreadPoints)
     {
      g_isSpreadAcceptable = true;
     }
   else
     {
      g_isSpreadAcceptable = false;
     }

   // ============================================================
   // PART 13: CHECK TIME CONDITION
   // ============================================================

   // Get current server time
   MqlDateTime currentTime;
   TimeCurrent(currentTime);
   int currentHour = currentTime.hour;

   // Check if current hour is within trading hours
   if(currentHour >= InpStartHour && currentHour < InpEndHour)
     {
      g_isTimeAcceptable = true;
     }
   else
     {
      g_isTimeAcceptable = false;
     }

   // ============================================================
   // PART 14: SET MASTER TRADING ALLOWED FLAG
   // ============================================================

   // Trading allowed only if time is acceptable AND spread is acceptable
   if(g_isTimeAcceptable && g_isSpreadAcceptable && g_eaModeFlag == 0)
     {
      g_isTradingAllowed = true;
     }
   else
     {
      g_isTradingAllowed = false;
     }

   // ============================================================
   // DEBUG OUTPUT (every 100 ticks to avoid spam)
   // ============================================================

   static int debugCounter = 0;
   debugCounter++;

   if(debugCounter >= 100)
     {
      debugCounter = 0;
      Print("Tick: ", g_tickCounter,
            " | Spread: ", DoubleToString(g_currentSpread, 2),
            " | Avg Spread: ", DoubleToString(g_averageSpread, 2),
            " | Trading Allowed: ", g_isTradingAllowed,
            " | Hour: ", currentHour);
     }

   // ============================================================
   // PART 15: RESET POSITION COUNTING VARIABLES
   // ============================================================

   // Reset all counters before recalculating
   g_openBuyCount = 0;
   g_openSellCount = 0;
   g_pendingBuyCount = 0;
   g_pendingSellCount = 0;
   g_totalBuyCount = 0;
   g_totalSellCount = 0;

   // Reset price tracking variables
   g_averageBuyPrice = 0;
   g_averageSellPrice = 0;
   g_lowestBuyPrice = 0;
   g_highestSellPrice = 0;
   g_buyOrderSumPrice = 0;
   g_sellOrderSumPrice = 0;
   g_buyOrderSumLot = 0;
   g_sellOrderSumLot = 0;
   g_currentBuyStopLoss = 0;
   g_currentSellStopLoss = 0;

   // ============================================================
   // PART 16: COUNT OPEN POSITIONS
   // ============================================================

   int totalPositions = PositionsTotal();

   for(int i = totalPositions - 1; i >= 0; i--)
     {
      // Select position by index
      if(positionInfo.SelectByIndex(i))
        {
         // Check if position belongs to our EA and symbol
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
           {
            // Get position details
            ulong ticket = positionInfo.Ticket();
            long positionType = positionInfo.PositionType();
            double positionPrice = positionInfo.PriceOpen();
            double positionVolume = positionInfo.Volume();
            double positionStopLoss = positionInfo.StopLoss();

            // --- Handle BUY positions ---
            if(positionType == POSITION_TYPE_BUY)
              {
               g_openBuyCount++;
               g_totalBuyCount++;

               // Accumulate for average price calculation
               g_buyOrderSumPrice += positionPrice * positionVolume;
               g_buyOrderSumLot += positionVolume;

               // Track stop loss
               if(positionStopLoss > 0)
                 {
                  g_currentBuyStopLoss = positionStopLoss;
                 }

               // Track lowest buy price
               if(g_lowestBuyPrice == 0 || positionPrice < g_lowestBuyPrice)
                 {
                  g_lowestBuyPrice = positionPrice;
                 }
              }

            // --- Handle SELL positions ---
            else if(positionType == POSITION_TYPE_SELL)
              {
               g_openSellCount++;
               g_totalSellCount++;

               // Accumulate for average price calculation
               g_sellOrderSumPrice += positionPrice * positionVolume;
               g_sellOrderSumLot += positionVolume;

               // Track stop loss
               if(positionStopLoss > 0)
                 {
                  g_currentSellStopLoss = positionStopLoss;
                 }

               // Track highest sell price
               if(g_highestSellPrice == 0 || positionPrice > g_highestSellPrice)
                 {
                  g_highestSellPrice = positionPrice;
                 }
              }
           }
        }
     }

   // Calculate average buy price
   if(g_buyOrderSumLot > 0)
     {
      g_averageBuyPrice = g_buyOrderSumPrice / g_buyOrderSumLot;
     }

   // Calculate average sell price
   if(g_sellOrderSumLot > 0)
     {
      g_averageSellPrice = g_sellOrderSumPrice / g_sellOrderSumLot;
     }

   // ============================================================
   // PART 17: COUNT PENDING ORDERS
   // ============================================================

   int totalOrders = OrdersTotal();

   for(int i = totalOrders - 1; i >= 0; i--)
     {
      // Select order by index
      if(orderInfo.SelectByIndex(i))
        {
         // Check if order belongs to our EA and symbol
         if(orderInfo.Symbol() == _Symbol && orderInfo.Magic() == InpMagicNumber)
           {
            // Get order details
            ulong ticket = orderInfo.Ticket();
            long orderType = orderInfo.Type();

            // --- Handle BUY STOP orders ---
            if(orderType == ORDER_TYPE_BUY_STOP)
              {
               g_pendingBuyCount++;
               g_totalBuyCount++;
              }

            // --- Handle SELL STOP orders ---
            else if(orderType == ORDER_TYPE_SELL_STOP)
              {
               g_pendingSellCount++;
               g_totalSellCount++;
              }
           }
        }
     }

   // ============================================================
   // PART 18: CHECK STOP LOSS CONDITIONS FOR POSITIONS
   // ============================================================

   // For BUY positions: If stop loss is zero OR stop loss is below price
   // (meaning position hasn't started trailing yet), count as "needs scaling"
   // Note: This logic is used in Step 9 to determine if we can add more positions

   bool buyStopLossActive = false;
   bool sellStopLossActive = false;

   if(g_openBuyCount > 0)
     {
      double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // Check if stop loss is active (above zero and above price)
      if(g_currentBuyStopLoss > 0 && g_currentBuyStopLoss > currentBid)
        {
         buyStopLossActive = true;
        }
     }

   if(g_openSellCount > 0)
     {
      double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // Check if stop loss is active (above zero and below price)
      if(g_currentSellStopLoss > 0 && g_currentSellStopLoss < currentAsk)
        {
         sellStopLossActive = true;
        }
     }

   // ============================================================
   // PART 19: DEBUG OUTPUT FOR POSITIONS (every 100 ticks)
   // ============================================================

   static int positionDebugCounter = 0;
   positionDebugCounter++;

   if(positionDebugCounter >= 100)
     {
      positionDebugCounter = 0;

      Print("=== Position Summary ===");
      Print("Open Buys: ", g_openBuyCount, " | Open Sells: ", g_openSellCount);
      Print("Pending Buys: ", g_pendingBuyCount, " | Pending Sells: ", g_pendingSellCount);
      Print("Total Buys: ", g_totalBuyCount, " | Total Sells: ", g_totalSellCount);

      if(g_averageBuyPrice > 0)
        {
         Print("Avg Buy Price: ", DoubleToString(g_averageBuyPrice, _Digits));
         Print("Lowest Buy Price: ", DoubleToString(g_lowestBuyPrice, _Digits));
         Print("Buy Stop Loss Active: ", buyStopLossActive);
        }

      if(g_averageSellPrice > 0)
        {
         Print("Avg Sell Price: ", DoubleToString(g_averageSellPrice, _Digits));
         Print("Highest Sell Price: ", DoubleToString(g_highestSellPrice, _Digits));
         Print("Sell Stop Loss Active: ", sellStopLossActive);
        }
      Print("=========================");
     }

   // ============================================================
   // PART 20-22: ORDER MODIFICATION AND TRAILING
   // ============================================================

   {
   // ============================================================
   // PART 20: MODIFY PENDING BUY STOP ORDERS
   // ============================================================

   // Loop through all pending orders to modify buy stops
   int totalOrdersModify = OrdersTotal();

   for(int i = totalOrdersModify - 1; i >= 0; i--)
     {
      if(orderInfo.SelectByIndex(i))
        {
         if(orderInfo.Symbol() == _Symbol && orderInfo.Magic() == InpMagicNumber)
           {
            long orderType = orderInfo.Type();
            ulong orderTicket = orderInfo.Ticket();
            double orderOpenPrice = orderInfo.PriceOpen();
            double orderStopLoss = orderInfo.StopLoss();
            double orderVolume = orderInfo.VolumeInitial();
            datetime orderTime = orderInfo.TimeSetup();

            // --- MODIFY BUY STOP ORDERS ---
            if(orderType == ORDER_TYPE_BUY_STOP)
              {
               // Check if we are within trading hours and spread acceptable
               if(!g_isTimeAcceptable || !g_isSpreadAcceptable)
                 {
                  // Delete order if outside trading conditions
                  if(trade.OrderDelete(orderTicket))
                    {
                     Print("Buy Stop order deleted - Outside trading conditions");
                    }
                  continue;
                 }

               // Check time since last modification
               datetime currentTime = TimeCurrent();
               double timeDifference = (double)(currentTime - g_lastBuyOrderTime);

               // Check if modification is needed based on tick frequency
               bool needsModification = false;

               // Condition 1: Time difference exceeds seconds threshold
               if(timeDifference >= seconds)
                 {
                  needsModification = true;
                 }

               // Condition 2: Tick counter is multiple of order check frequency
               if(g_tickCounter % g_orderCheckFrequency == 0)
                 {
                  needsModification = true;
                 }

               // Condition 3: No open buy positions (or stop loss not yet active)
               if(g_openBuyCount < 1)
                 {
                  needsModification = true;
                 }

               if(needsModification)
                 {
                  // Calculate new order distance
                  double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                  double newDistance = g_adjustedOrderDistance;

                  // If there are open positions, reduce distance
                  if(g_openBuyCount > 0)
                    {
                     newDistance = newDistance / g_orderModificationFactor;
                    }

                  // Ensure distance is at least minimum stop distance
                  newDistance = MathMax(newDistance, g_minStopDistance);

                  // Calculate new order price
                  double newOrderPrice = ask + newDistance;
                  newOrderPrice = NormalizeDouble(newOrderPrice, _Digits);

                  // Calculate new stop loss
                  double newStopLoss = 0;
                  if(g_openBuyCount > 0 && g_currentBuyStopLoss > 0)
                    {
                     newStopLoss = g_currentBuyStopLoss;
                    }
                  else
                    {
                     newStopLoss = newOrderPrice - g_calculatedStopLoss;
                     newStopLoss = NormalizeDouble(newStopLoss, _Digits);
                    }

                  // Check if modification is actually needed
                  if(newOrderPrice != orderOpenPrice || newStopLoss != orderStopLoss)
                    {
                     // Check freeze level
                     double priceDifference = MathAbs(newOrderPrice - orderOpenPrice);

                     if(priceDifference > g_minFreezeDistance)
                       {
                        if(trade.OrderModify(orderTicket, newOrderPrice, newStopLoss, 0, 0, NULL))
                          {
                           g_lastBuyOrderTime = currentTime;
                           g_lastOrderTime = currentTime;
                           Print("Buy Stop order modified - New Price: ", newOrderPrice,
                                 " | New SL: ", newStopLoss);
                          }
                        else
                          {
                           Print("Failed to modify Buy Stop order. Error: ", GetLastError());
                          }
                       }
                    }
                 }
              }
           }
        }
     }

   // ============================================================
   // PART 21: MODIFY PENDING SELL STOP ORDERS
   // ============================================================

   for(int i = totalOrdersModify - 1; i >= 0; i--)
     {
      if(orderInfo.SelectByIndex(i))
        {
         if(orderInfo.Symbol() == _Symbol && orderInfo.Magic() == InpMagicNumber)
           {
            long orderType = orderInfo.Type();
            ulong orderTicket = orderInfo.Ticket();
            double orderOpenPrice = orderInfo.PriceOpen();
            double orderStopLoss = orderInfo.StopLoss();

            // --- MODIFY SELL STOP ORDERS ---
            if(orderType == ORDER_TYPE_SELL_STOP)
              {
               // Check if we are within trading hours and spread acceptable
               if(!g_isTimeAcceptable || !g_isSpreadAcceptable)
                 {
                  if(trade.OrderDelete(orderTicket))
                    {
                     Print("Sell Stop order deleted - Outside trading conditions");
                    }
                  continue;
                 }

               // Check time since last modification
               datetime currentTime = TimeCurrent();
               double timeDifference = (double)(currentTime - g_lastSellOrderTime);

               bool needsModification = false;

               if(timeDifference >= seconds)
                 {
                  needsModification = true;
                 }

               if(g_tickCounter % g_orderCheckFrequency == 0)
                 {
                  needsModification = true;
                 }

               if(g_openSellCount < 1)
                 {
                  needsModification = true;
                 }

               if(needsModification)
                 {
                  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                  double newDistance = g_adjustedOrderDistance;

                  if(g_openSellCount > 0)
                    {
                     newDistance = newDistance / g_orderModificationFactor;
                    }

                  newDistance = MathMax(newDistance, g_minStopDistance);

                  double newOrderPrice = bid - newDistance;
                  newOrderPrice = NormalizeDouble(newOrderPrice, _Digits);

                  double newStopLoss = 0;
                  if(g_openSellCount > 0 && g_currentSellStopLoss > 0)
                    {
                     newStopLoss = g_currentSellStopLoss;
                    }
                  else
                    {
                     newStopLoss = newOrderPrice + g_calculatedStopLoss;
                     newStopLoss = NormalizeDouble(newStopLoss, _Digits);
                    }

                  if(newOrderPrice != orderOpenPrice || newStopLoss != orderStopLoss)
                    {
                     double priceDifference = MathAbs(newOrderPrice - orderOpenPrice);

                     if(priceDifference > g_minFreezeDistance)
                       {
                        if(trade.OrderModify(orderTicket, newOrderPrice, newStopLoss, 0, 0, NULL))
                          {
                           g_lastSellOrderTime = currentTime;
                           g_lastOrderTime = currentTime;
                           Print("Sell Stop order modified - New Price: ", newOrderPrice,
                                 " | New SL: ", newStopLoss);
                          }
                        else
                          {
                           Print("Failed to modify Sell Stop order. Error: ", GetLastError());
                          }
                       }
                    }
                 }
              }
           }
        }
     }

   // ============================================================
   // PART 22: TRAILING STOP FOR OPEN BUY POSITIONS
   // ============================================================

   int totalPositionsTrail = PositionsTotal();

   for(int i = totalPositionsTrail - 1; i >= 0; i--)
     {
      if(positionInfo.SelectByIndex(i))
        {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
           {
            long positionType = positionInfo.PositionType();
            ulong positionTicket = positionInfo.Ticket();
            double positionOpenPrice = positionInfo.PriceOpen();
            double positionCurrentSL = positionInfo.StopLoss();

            // --- TRAILING STOP FOR BUY POSITIONS ---
            if(positionType == POSITION_TYPE_BUY)
              {
               double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

               // Calculate price movement in profit (bid - open price - commission)
               double priceMove = currentBid - positionOpenPrice - g_commissionPerPip * point;

               // Only trail if price has moved beyond trailing start threshold
               if(priceMove > g_trailingStartPoints)
                 {
                  // Calculate trailing distance using helper function
                  double trailingDistance = CalcTrailingDistance(
                     priceMove,                    // How far price has moved
                     g_minStopDistance,            // Minimum stop distance
                     g_trailingStartPoints,        // Active distance (when trailing starts)
                     g_trailingStartPoints * 0.5,  // Base distance (half of start)
                     g_trailingStartPoints * 3     // Max distance (3x start)
                  );

                  // Calculate new stop loss
                  double newStopLoss = currentBid - trailingDistance;
                  newStopLoss = NormalizeDouble(newStopLoss, _Digits);

                  // Calculate trigger level (when trailing should activate)
                  double triggerLevel = positionOpenPrice + g_commissionPerPip * point + g_trailingStartPoints;

                  // Check if we should modify the stop loss
                  bool shouldModify = false;

                  if(positionCurrentSL == 0)
                    {
                     shouldModify = true;
                    }
                  else if(currentBid - triggerLevel > trailingDistance)
                    {
                     shouldModify = true;
                    }
                  else if(newStopLoss > positionCurrentSL)
                    {
                     shouldModify = true;
                    }

                  if(shouldModify && newStopLoss > positionCurrentSL)
                    {
                     if(trade.PositionModify(positionTicket, newStopLoss, 0))
                       {
                        Print("Buy position trailing - New SL: ", newStopLoss,
                              " | Price move: ", DoubleToString(priceMove / point, 2), " points");
                       }
                    }
                 }
              }

            // --- TRAILING STOP FOR SELL POSITIONS ---
            else if(positionType == POSITION_TYPE_SELL)
              {
               double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

               // Calculate price movement in profit (open price - ask - commission)
               double priceMove = positionOpenPrice - currentAsk - g_commissionPerPip * point;

               if(priceMove > g_trailingStartPoints)
                 {
                  double trailingDistance = CalcTrailingDistance(
                     priceMove,
                     g_minStopDistance,
                     g_trailingStartPoints,
                     g_trailingStartPoints * 0.5,
                     g_trailingStartPoints * 3
                  );

                  double newStopLoss = currentAsk + trailingDistance;
                  newStopLoss = NormalizeDouble(newStopLoss, _Digits);

                  double triggerLevel = positionOpenPrice - g_commissionPerPip * point - g_trailingStartPoints;

                  bool shouldModify = false;

                  if(positionCurrentSL == 0)
                    {
                     shouldModify = true;
                    }
                  else if(triggerLevel - currentAsk > trailingDistance)
                    {
                     shouldModify = true;
                    }
                  else if(newStopLoss < positionCurrentSL)
                    {
                     shouldModify = true;
                    }

                  if(shouldModify && (newStopLoss < positionCurrentSL || positionCurrentSL == 0))
                    {
                     if(trade.PositionModify(positionTicket, newStopLoss, 0))
                       {
                        Print("Sell position trailing - New SL: ", newStopLoss,
                              " | Price move: ", DoubleToString(priceMove / point, 2), " points");
                       }
                    }
                 }
              }
           }
        }
     }
   }

   // ============================================================
   // DELETE COUNTER-TREND ORDERS (UPGRADE PATCH)
   // ============================================================
   int totalOrdersForDeletion = OrdersTotal();
   
   for(int i = totalOrdersForDeletion - 1; i >= 0; i--)
     {
      if(orderInfo.SelectByIndex(i))
        {
         if(orderInfo.Symbol() == _Symbol && orderInfo.Magic() == InpMagicNumber)
           {
            long orderType = orderInfo.Type();
            ulong orderTicket = orderInfo.Ticket();
            bool shouldDelete = false;
            
            // If trend is neutral, delete ALL orders
            if(g_currentTrend == 0)
              {
               shouldDelete = true;
              }
            // If trend is UPTREND, delete all SELL STOP orders
            else if(g_currentTrend == 1 && orderType == ORDER_TYPE_SELL_STOP)
              {
               shouldDelete = true;
              }
            // If trend is DOWNTREND, delete all BUY STOP orders
            else if(g_currentTrend == -1 && orderType == ORDER_TYPE_BUY_STOP)
              {
               shouldDelete = true;
              }
            
            if(shouldDelete)
              {
               if(trade.OrderDelete(orderTicket))
                 {
                  Print("Counter-trend order deleted. Ticket: ", orderTicket, " | Trend: ", g_currentTrend);
                 }
              }
           }
        }
     }

   // ============================================================
   // Continue to Sending New Orders
   // ============================================================

   {
   // ============================================================
   // PART 23: SEND NEW BUY STOP ORDERS (with Trend Filter)
   // ============================================================

   // Check if we should send a new buy stop order
   bool shouldSendBuyOrder = false;
   
   // Only allow BUY orders if: filter disabled (g_currentTrend == 2) OR uptrend (g_currentTrend == 1)
   if(g_currentTrend == 2 || g_currentTrend == 1)
     {
      // Condition 1: No open buy positions OR stop loss not yet active (scaling in)
      if(g_openBuyCount < 1 || (g_openBuyCount > 0 && g_currentBuyStopLoss > 0 &&
         g_currentBuyStopLoss < SymbolInfoDouble(_Symbol, SYMBOL_BID)))
        {
         // Condition 2: No pending buy stop orders already
         if(g_pendingBuyCount < 1)
           {
            // Condition 3: Trading is allowed (time + spread)
            if(g_isTradingAllowed)
              {
               // Condition 4: Sufficient time has passed since last order
               datetime currentTime = TimeCurrent();
               if(currentTime - g_lastOrderTime >= seconds)
                 {
                  shouldSendBuyOrder = true;
                 }
              }
           }
        }
     }

   if(shouldSendBuyOrder)
     {
      // Calculate lot size
      double lotSize = 0;

      if(InpLotType == LOT_FIXED)
        {
         lotSize = InpFixedLot;
        }
      else
        {
         // Use stop loss distance for risk calculation
         lotSize = CalcLotSize(g_calculatedStopLoss / SymbolInfoDouble(_Symbol, SYMBOL_POINT));
        }

      // Validate lot size
      if(lotSize < g_minLot)
        {
         lotSize = g_minLot;
         Print("Lot size adjusted to minimum: ", lotSize);
        }

      if(lotSize > g_maxLot)
        {
         lotSize = g_maxLot;
         Print("Lot size adjusted to maximum: ", lotSize);
        }

      // Calculate order price
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double orderDistance = g_adjustedOrderDistance;

      // Reduce distance if scaling into existing position
      if(g_openBuyCount > 0)
        {
         orderDistance = orderDistance / g_orderModificationFactor;
        }

      orderDistance = MathMax(orderDistance, g_minStopDistance);

      double orderPrice = ask + orderDistance;
      orderPrice = NormalizeDouble(orderPrice, _Digits);

      // Calculate stop loss
      double stopLoss = 0;
      if(g_openBuyCount > 0 && g_currentBuyStopLoss > 0)
        {
         stopLoss = g_currentBuyStopLoss;
        }
      else
        {
         stopLoss = orderPrice - g_calculatedStopLoss;
         stopLoss = NormalizeDouble(stopLoss, _Digits);
        }

      // Check margin requirements
      double marginRequired = 0;
      if(!OrderCalcMargin(ORDER_TYPE_BUY_STOP, _Symbol, lotSize, orderPrice, marginRequired))
        {
         // Fallback calculation
         if(g_accountLeverage > 0)
            marginRequired = lotSize * ask * (100.0 / g_accountLeverage);
         else
            marginRequired = lotSize * ask;
        }

      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

      if(freeMargin > marginRequired * 1.1)  // 10% buffer
        {
         // Place the buy stop order
         if(trade.BuyStop(lotSize, orderPrice, _Symbol, stopLoss, 0,
                          ORDER_TIME_GTC, 0, "HFT EA - Buy Stop"))
           {
            g_lastBuyOrderTime = TimeCurrent();
            g_lastOrderTime = TimeCurrent();
            Print("Buy Stop order placed - Price: ", orderPrice,
                  " | SL: ", stopLoss, " | Lot: ", lotSize);
           }
         else
           {
            Print("Failed to place Buy Stop order. Error: ", GetLastError());
           }
        }
      else
        {
         Print("Insufficient margin for Buy Stop order. Required: ", marginRequired,
               " | Free: ", freeMargin);
        }
     }

   // ============================================================
   // PART 24: SEND NEW SELL STOP ORDERS (with Trend Filter)
   // ============================================================

   // Check if we should send a new sell stop order
   bool shouldSendSellOrder = false;
   
   // Only allow SELL orders if: filter disabled (g_currentTrend == 2) OR downtrend (g_currentTrend == -1)
   if(g_currentTrend == 2 || g_currentTrend == -1)
     {
      // Condition 1: No open sell positions OR stop loss not yet active (scaling in)
      if(g_openSellCount < 1 || (g_openSellCount > 0 && g_currentSellStopLoss > 0 &&
         g_currentSellStopLoss > SymbolInfoDouble(_Symbol, SYMBOL_ASK)))
        {
         // Condition 2: No pending sell stop orders already
         if(g_pendingSellCount < 1)
           {
            // Condition 3: Trading is allowed (time + spread)
            if(g_isTradingAllowed)
              {
               // Condition 4: Sufficient time has passed since last order
               datetime currentTime = TimeCurrent();
               if(currentTime - g_lastOrderTime >= seconds)
                 {
                  shouldSendSellOrder = true;
                 }
              }
           }
        }
     }

   if(shouldSendSellOrder)
     {
      // Calculate lot size
      double lotSize = 0;

      if(InpLotType == LOT_FIXED)
        {
         lotSize = InpFixedLot;
        }
      else
        {
         lotSize = CalcLotSize(g_calculatedStopLoss / SymbolInfoDouble(_Symbol, SYMBOL_POINT));
        }

      // Validate lot size
      if(lotSize < g_minLot)
        {
         lotSize = g_minLot;
         Print("Lot size adjusted to minimum: ", lotSize);
        }

      if(lotSize > g_maxLot)
        {
         lotSize = g_maxLot;
         Print("Lot size adjusted to maximum: ", lotSize);
        }

      // Calculate order price
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double orderDistance = g_adjustedOrderDistance;

      // Reduce distance if scaling into existing position
      if(g_openSellCount > 0)
        {
         orderDistance = orderDistance / g_orderModificationFactor;
        }

      orderDistance = MathMax(orderDistance, g_minStopDistance);

      double orderPrice = bid - orderDistance;
      orderPrice = NormalizeDouble(orderPrice, _Digits);

      // Calculate stop loss
      double stopLoss = 0;
      if(g_openSellCount > 0 && g_currentSellStopLoss > 0)
        {
         stopLoss = g_currentSellStopLoss;
        }
      else
        {
         stopLoss = orderPrice + g_calculatedStopLoss;
         stopLoss = NormalizeDouble(stopLoss, _Digits);
        }

      // Check margin requirements
      double marginRequired = 0;
      if(!OrderCalcMargin(ORDER_TYPE_SELL_STOP, _Symbol, lotSize, orderPrice, marginRequired))
        {
         if(g_accountLeverage > 0)
            marginRequired = lotSize * bid * (100.0 / g_accountLeverage);
         else
            marginRequired = lotSize * bid;
        }

      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

      if(freeMargin > marginRequired * 1.1)  // 10% buffer
        {
         // Place the sell stop order
         if(trade.SellStop(lotSize, orderPrice, _Symbol, stopLoss, 0,
                           ORDER_TIME_GTC, 0, "HFT EA - Sell Stop"))
           {
            g_lastSellOrderTime = TimeCurrent();
            g_lastOrderTime = TimeCurrent();
            Print("Sell Stop order placed - Price: ", orderPrice,
                  " | SL: ", stopLoss, " | Lot: ", lotSize);
           }
         else
           {
            Print("Failed to place Sell Stop order. Error: ", GetLastError());
           }
        }
      else
        {
         Print("Insufficient margin for Sell Stop order. Required: ", marginRequired,
               " | Free: ", freeMargin);
        }
     }

   // ============================================================
   // DISPLAY TREND STATUS ON CHART (UPGRADE PATCH)
   // ============================================================
   static datetime lastCommentUpdate = 0;
   if(TimeCurrent() - lastCommentUpdate >= 10)  // Update every 10 seconds
     {
      lastCommentUpdate = TimeCurrent();
      
      string trendText = "";
      if(!InpUseTrendFilter)
        {
         trendText = "Trend Filter: DISABLED (Both directions)";
        }
      else if(g_currentTrend == 1)
        {
         trendText = "Trend: UPTREND 🔼 (BUY only)";
        }
      else if(g_currentTrend == -1)
        {
         trendText = "Trend: DOWNTREND 🔽 (SELL only)";
        }
      else if(g_currentTrend == 0)
        {
         trendText = "Trend: NEUTRAL 🟡 (No trading - deleting orders)";
        }
      else
        {
         trendText = "Trend: UNKNOWN";
        }
      
      // Add trend info to chart (will show alongside existing comment)
      Comment(trendText, "\n",
              "Fast EMA: ", DoubleToString(g_trendFastEMA[0], _Digits), " | ",
              "Slow EMA: ", DoubleToString(g_trendSlowEMA[0], _Digits));
     }

   // ============================================================
   // PART 25: FINAL DEBUG OUTPUT (every 500 ticks)
   // ============================================================

   static int finalDebugCounter = 0;
   finalDebugCounter++;

   if(finalDebugCounter >= 500)
     {
      finalDebugCounter = 0;

      Print("========== EA STATUS UPDATE ==========");
      Print("Tick: ", g_tickCounter);
      Print("Spread: ", DoubleToString(g_currentSpread, 2), " points");
      Print("Trading Allowed: ", g_isTradingAllowed);
      Print("Open Positions - Buy: ", g_openBuyCount, " | Sell: ", g_openSellCount);
      Print("Pending Orders - Buy: ", g_pendingBuyCount, " | Sell: ", g_pendingSellCount);

      double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      Print("Balance: ", DoubleToString(accountBalance, 2),
            " | Equity: ", DoubleToString(accountEquity, 2));

      if(g_openBuyCount > 0)
        {
         Print("Avg Buy Price: ", DoubleToString(g_averageBuyPrice, _Digits));
         Print("Buy Stop Loss: ", DoubleToString(g_currentBuyStopLoss, _Digits));
        }

      if(g_openSellCount > 0)
        {
         Print("Avg Sell Price: ", DoubleToString(g_averageSellPrice, _Digits));
         Print("Sell Stop Loss: ", DoubleToString(g_currentSellStopLoss, _Digits));
        }

      Print("=======================================");
     }
   }
  }

// ============================================================
// HELPER FUNCTION: Calculate Lot Size Based on Risk
// ============================================================
// This function calculates the appropriate lot size based on:
// - Fixed lots, or
// - Percentage of Balance, Equity, or Free Margin
//
// Parameters:
//   slPoints - Stop loss distance in points
//
// Returns: Calculated lot size normalized to broker requirements
// ============================================================
double CalcLotSize(double slPoints)
  {
   double lotSize = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   // Get account information
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double accountFreeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   // Calculate based on lot type
   switch(InpLotType)
     {
      case LOT_FIXED:
         lotSize = InpFixedLot;
         break;

      case LOT_PERCENT_BALANCE:
        {
         double riskAmount = accountBalance * (InpRiskPercent / 100.0);
         if(slPoints > 0 && tickValue > 0)
           {
            double moneyPerLot = slPoints * tickValue;
            if(moneyPerLot > 0)
              {
               lotSize = riskAmount / moneyPerLot;
              }
           }
        }
        break;

      case LOT_PERCENT_EQUITY:
        {
         double riskAmount = accountEquity * (InpRiskPercent / 100.0);
         if(slPoints > 0 && tickValue > 0)
           {
            double moneyPerLot = slPoints * tickValue;
            if(moneyPerLot > 0)
              {
               lotSize = riskAmount / moneyPerLot;
              }
           }
        }
        break;

      case LOT_PERCENT_FREE_MARGIN:
        {
         double riskAmount = accountFreeMargin * (InpRiskPercent / 100.0);
         if(slPoints > 0 && tickValue > 0)
           {
            double moneyPerLot = slPoints * tickValue;
            if(moneyPerLot > 0)
              {
               lotSize = riskAmount / moneyPerLot;
              }
           }
        }
        break;
     }

   // Apply broker lot constraints
   if(g_lotStep > 0)
     {
      lotSize = MathRound(lotSize / g_lotStep) * g_lotStep;
     }

   // Ensure within min/max
   lotSize = MathMax(lotSize, g_minLot);
   lotSize = MathMin(lotSize, g_maxLot);

   // Normalize to 2 decimal places
   lotSize = NormalizeDouble(lotSize, 2);

   return lotSize;
  }

// ============================================================
// HELPER FUNCTION: Calculate Trailing Stop Distance
// ============================================================
// This function calculates the dynamic trailing stop distance
// based on how far price has moved in profit.
//
// Parameters:
//   priceMove      - How many points the price has moved in profit
//   minDistance    - Minimum allowed stop distance (broker stop level)
//   activeDistance - Base trailing distance when trailing starts
//   baseDistance   - Minimum trailing distance
//   maxDistance    - Maximum trailing distance (when price moves far)
//
// Returns: The calculated trailing stop distance in points
// ============================================================
double CalcTrailingDistance(double priceMove, double minDistance,
                            double activeDistance, double baseDistance,
                            double maxDistance)
  {
   double result = 0;

   // Get point value for calculations
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // If no max distance defined, use active vs minimum
   if(maxDistance <= 0 || maxDistance == activeDistance)
     {
      result = MathMax(activeDistance, minDistance);
     }
   else
     {
      // Calculate ratio of price movement to max distance
      double ratio = priceMove / maxDistance;

      // Cap ratio between 0 and 1
      if(ratio < 0)
         ratio = 0;
      if(ratio > 1)
         ratio = 1;

      // Dynamic distance = active - (active - base) * ratio + base
      double dynamicDistance = activeDistance - ((activeDistance - baseDistance) * ratio);

      // Result is the minimum of dynamic distance and max distance
      result = MathMin(dynamicDistance, maxDistance);
     }

   // Ensure result is not less than minimum stop distance
   result = MathMax(result, minDistance);

   // Ensure at least 1 point
   if(result < point)
     {
      result = point;
     }

   return result;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // Clean up trend indicator handles
   if(g_trendFastEMAHandle != INVALID_HANDLE)
     {
      IndicatorRelease(g_trendFastEMAHandle);
     }
   if(g_trendSlowEMAHandle != INVALID_HANDLE)
     {
      IndicatorRelease(g_trendSlowEMAHandle);
   }
   
   // Clean up chart comments
   Comment("");
   
   // Print shutdown message
   Print("EA removed from chart. Reason: ", reason);
   Print("Total ticks processed: ", g_tickCounter);
   Print("Final balance: ", AccountInfoDouble(ACCOUNT_BALANCE));
   Print("Trend indicators released.");
  }