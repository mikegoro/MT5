//+------------------------------------------------------------------+
//|                                              MikeyScalping_Fixed.mq5 |
//|                                      Fixed Version - Production Ready |
//+------------------------------------------------------------------+
#property copyright "Educational Use Only"
#property link      ""
#property version   "2.00"

#include <Trade\Trade.mqh>

//--- Session Time Enumeration for Dropdown ---
enum ENUM_SESSION_TIMES
{
   SESSION_INACTIVE = -1,    // Inactive
   SESSION_0000 = 0,         // 00:00
   SESSION_0015 = 15,        // 00:15
   SESSION_0030 = 30,        // 00:30
   SESSION_0045 = 45,        // 00:45
   SESSION_0100 = 60,        // 01:00
   SESSION_0115 = 75,        // 01:15
   SESSION_0130 = 90,        // 01:30
   SESSION_0145 = 105,       // 01:45
   SESSION_0200 = 120,       // 02:00
   SESSION_0215 = 135,       // 02:15
   SESSION_0230 = 150,       // 02:30
   SESSION_0245 = 165,       // 02:45
   SESSION_0300 = 180,       // 03:00
   SESSION_0315 = 195,       // 03:15
   SESSION_0330 = 210,       // 03:30
   SESSION_0345 = 225,       // 03:45
   SESSION_0400 = 240,       // 04:00
   SESSION_0415 = 255,       // 04:15
   SESSION_0430 = 270,       // 04:30
   SESSION_0445 = 285,       // 04:45
   SESSION_0500 = 300,       // 05:00
   SESSION_0515 = 315,       // 05:15
   SESSION_0530 = 330,       // 05:30
   SESSION_0545 = 345,       // 05:45
   SESSION_0600 = 360,       // 06:00
   SESSION_0615 = 375,       // 06:15
   SESSION_0630 = 390,       // 06:30
   SESSION_0645 = 405,       // 06:45
   SESSION_0700 = 420,       // 07:00
   SESSION_0715 = 435,       // 07:15
   SESSION_0730 = 450,       // 07:30
   SESSION_0745 = 465,       // 07:45
   SESSION_0800 = 480,       // 08:00
   SESSION_0815 = 495,       // 08:15
   SESSION_0830 = 510,       // 08:30
   SESSION_0845 = 525,       // 08:45
   SESSION_0900 = 540,       // 09:00
   SESSION_0915 = 555,       // 09:15
   SESSION_0930 = 570,       // 09:30
   SESSION_0945 = 585,       // 09:45
   SESSION_1000 = 600,       // 10:00
   SESSION_1015 = 615,       // 10:15
   SESSION_1030 = 630,       // 10:30
   SESSION_1045 = 645,       // 10:45
   SESSION_1100 = 660,       // 11:00
   SESSION_1115 = 675,       // 11:15
   SESSION_1130 = 690,       // 11:30
   SESSION_1145 = 705,       // 11:45
   SESSION_1200 = 720,       // 12:00
   SESSION_1215 = 735,       // 12:15
   SESSION_1230 = 750,       // 12:30
   SESSION_1245 = 765,       // 12:45
   SESSION_1300 = 780,       // 13:00
   SESSION_1315 = 795,       // 13:15
   SESSION_1330 = 810,       // 13:30
   SESSION_1345 = 825,       // 13:45
   SESSION_1400 = 840,       // 14:00
   SESSION_1415 = 855,       // 14:15
   SESSION_1430 = 870,       // 14:30
   SESSION_1445 = 885,       // 14:45
   SESSION_1500 = 900,       // 15:00
   SESSION_1515 = 915,       // 15:15
   SESSION_1530 = 930,       // 15:30
   SESSION_1545 = 945,       // 15:45
   SESSION_1600 = 960,       // 16:00
   SESSION_1615 = 975,       // 16:15
   SESSION_1630 = 990,       // 16:30
   SESSION_1645 = 1005,      // 16:45
   SESSION_1700 = 1020,      // 17:00
   SESSION_1715 = 1035,      // 17:15
   SESSION_1730 = 1050,      // 17:30
   SESSION_1745 = 1065,      // 17:45
   SESSION_1800 = 1080,      // 18:00
   SESSION_1815 = 1095,      // 18:15
   SESSION_1830 = 1110,      // 18:30
   SESSION_1845 = 1125,      // 18:45
   SESSION_1900 = 1140,      // 19:00
   SESSION_1915 = 1155,      // 19:15
   SESSION_1930 = 1170,      // 19:30
   SESSION_1945 = 1185,      // 19:45
   SESSION_2000 = 1200,      // 20:00
   SESSION_2015 = 1215,      // 20:15
   SESSION_2030 = 1230,      // 20:30
   SESSION_2045 = 1245,      // 20:45
   SESSION_2100 = 1260,      // 21:00
   SESSION_2115 = 1275,      // 21:15
   SESSION_2130 = 1290,      // 21:30
   SESSION_2145 = 1305,      // 21:45
   SESSION_2200 = 1320,      // 22:00
   SESSION_2215 = 1335,      // 22:15
   SESSION_2230 = 1350,      // 22:30
   SESSION_2245 = 1365,      // 22:45
   SESSION_2300 = 1380,      // 23:00
   SESSION_2315 = 1395,      // 23:15
   SESSION_2330 = 1410,      // 23:30
   SESSION_2345 = 1425       // 23:45
};

//--- Input Parameters ---
input double   InpInitialLot        = 0.01;       // Initial lot size (MINIMUM)
input double   InpDistancePips      = 50.0;       // Distance for pending orders (in Points)
input double   InpProfitTarget      = 1.00;       // Profit target in dollars
input double   InpLossTrigger       = 0.50;       // Loss to trigger recovery ($)
input double   InpMartingaleMulti   = 2.0;        // Martingale multiplier
input int      InpMaxRecovery       = 3;          // Maximum recovery attempts
input int      InpMaxSimPositions   = 5;          // Maximum simultaneous positions
input double   InpStopLossPerTrade  = 2.00;       // Stop loss per trade ($) - Hard safety
input bool     InpUseTrailing       = true;       // Use trailing stop
input int      InpMagicNumber       = 20260115;   // Magic number for EA trades
input int      InpCooldownSeconds   = 60;         // Cooldown between trades (seconds)

//--- Session Filter Inputs (Now using ENUM for dropdown) ---
input string   _s4_                   = "=== Session Filter ===";
input ENUM_SESSION_TIMES SessionStart  = SESSION_INACTIVE;  // Start time (broker server time)
input ENUM_SESSION_TIMES SessionEnd    = SESSION_INACTIVE;  // End time (broker server time)

//--- Global Variables ---
double currentLot = 0.01;
bool isRecoveryMode = false;
CTrade trade;
datetime lastTradeTime = 0;
int eaPositions = 0;
double totalDailyLoss = 0;
bool isDailyLossReset = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate inputs
   if(InpInitialLot <= 0 || InpDistancePips <= 0 || InpMartingaleMulti <= 1)
   {
      Print("Error: Invalid input parameters!");
      return(INIT_FAILED);
   }
   
   // Validate symbol
   if(_Symbol != "XAUUSD")
   {
      Print("ERROR: This EA is designed for XAUUSD only. Current symbol: ", _Symbol);
      return(INIT_FAILED);
   }
   
   // Initialize trade object with magic number
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   // Set initial lot
   currentLot = InpInitialLot;
   
   Print("EA initialized successfully on ", _Symbol);
   Print("Magic Number: ", InpMagicNumber);
   Print("Initial Lot: ", currentLot);
   Print("Session Start: ", SessionStart, " Session End: ", SessionEnd);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Get current account profit and count positions
   double currentProfit = AccountInfoDouble(ACCOUNT_PROFIT);
   int posCount = CountCurrentSymbolPositions();
   
   // 2. Check hard stop loss
   if(currentProfit <= -InpStopLossPerTrade)
   {
      CloseAllPositions();
      currentLot = InpInitialLot;
      isRecoveryMode = false;
      isDailyLossReset = true;
      Print("Hard Stop Loss hit. All positions closed. Profit: $", currentProfit);
      return;
   }
   
   // 3. Check if total loss exceeds trigger
   double totalLoss = CalculateTotalLoss();
   
   // 4. Take profit management
   if(currentProfit >= InpProfitTarget && posCount > 0)
   {
      CloseAllPositions();
      currentLot = InpInitialLot;
      isRecoveryMode = false;
      isDailyLossReset = false;
      lastTradeTime = TimeCurrent();
      Print("Daily Profit Target Reached. Positions Closed. Profit: $", currentProfit);
      return;
   }
   
   // 5. Session time filter (only for new entries)
   if(posCount == 0 && !isRecoveryMode)
   {
      if(!IsWithinSession())
      {
         // Print("Outside session hours. Waiting..."); // Uncomment for debugging
         return;
      }
   }
   
   // 6. ENTRY LOGIC - Initial Trade
   if(posCount == 0 && !isRecoveryMode && !isDailyLossReset)
   {
      if(CanPlaceTrade())
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = CalculateStopLoss(ask, InpInitialLot);
         double tp = CalculateTakeProfit(ask, InpInitialLot);
         
         if(trade.Buy(InpInitialLot, _Symbol, ask, sl, tp, "Initial Trade"))
         {
            currentLot = InpInitialLot;
            lastTradeTime = TimeCurrent();
            Print("Initial Trade placed. Lot: ", currentLot, " SL: ", sl, " TP: ", tp);
         }
         else
         {
            Print("OrderSend Failed: ", trade.ResultRetcode());
         }
      }
   }
   // 7. RECOVERY LOGIC (Martingale)
   else if(posCount > 0 && !isRecoveryMode && !isDailyLossReset)
   {
      if(totalLoss >= InpLossTrigger && posCount < InpMaxRecovery && posCount < InpMaxSimPositions)
      {
         if(CanPlaceTrade())
         {
            double newLot = CalculateMartingaleLot();
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double sl = CalculateStopLoss(ask, newLot);
            
            if(trade.Buy(newLot, _Symbol, ask, sl, 0, "Recovery Trade"))
            {
               currentLot = newLot;
               isRecoveryMode = true;
               lastTradeTime = TimeCurrent();
               Print("Recovery Trade placed. Lot: ", newLot, " Loss: $", totalLoss, " SL: ", sl);
            }
            else
            {
               Print("Recovery Trade Failed: ", trade.ResultRetcode());
            }
         }
      }
   }
   // 8. Check if recovery trade is profitable and reset mode
   else if(isRecoveryMode && posCount > 0)
   {
      double positionProfit = GetTotalPositionProfit();
      if(positionProfit >= 0)
      {
         isRecoveryMode = false;
         Print("Recovery mode exited. Position profitable.");
      }
   }
   
   // 9. Trailing Stop Logic
   if(InpUseTrailing && posCount > 0)
   {
      TrailingStopLogic();
   }
}

//+------------------------------------------------------------------+
//| Helper Functions                                                 |
//+------------------------------------------------------------------+

//--- Count positions for current symbol only ---
int CountCurrentSymbolPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
               count++;
         }
      }
   }
   return count;
}

//--- Calculate total loss from all positions ---
double CalculateTotalLoss()
{
   double totalLoss = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            {
               double profit = PositionGetDouble(POSITION_PROFIT);
               if(profit < 0)
                  totalLoss += MathAbs(profit);
            }
         }
      }
   }
   return totalLoss;
}

//--- Get total profit from all positions ---
double GetTotalPositionProfit()
{
   double totalProfit = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            {
               totalProfit += PositionGetDouble(POSITION_PROFIT);
            }
         }
      }
   }
   return totalProfit;
}

//--- Calculate proper stop loss based on lot size ---
double CalculateStopLoss(double price, double lot)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double slPoints = (InpStopLossPerTrade / (lot * tickValue)) * tickSize;
   return price - slPoints;
}

//--- Calculate proper take profit based on lot size ---
double CalculateTakeProfit(double price, double lot)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tpPoints = (InpProfitTarget / (lot * tickValue)) * tickSize;
   return price + tpPoints;
}

//--- Calculate martingale lot size with safety checks ---
double CalculateMartingaleLot()
{
   double newLot = NormalizeDouble(currentLot * InpMartingaleMulti, 2);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   
   if(newLot > maxLot) newLot = maxLot;
   if(newLot < minLot) newLot = minLot;
   
   return newLot;
}

//--- Check if we can place a trade (cooldown) ---
bool CanPlaceTrade()
{
   datetime currentTime = TimeCurrent();
   if((currentTime - lastTradeTime) < InpCooldownSeconds)
   {
      return false;
   }
   return true;
}

//--- Check if current time is within session ---
bool IsWithinSession()
{
   // If session not set, always allow trading
   if(SessionStart == SESSION_INACTIVE || SessionEnd == SESSION_INACTIVE)
      return true;
   
   MqlDateTime timeStruct;
   TimeCurrent(timeStruct);
   int currentMinutes = (timeStruct.hour * 60) + timeStruct.min;
   
   // Convert enum values to integers
   int startTime = (int)SessionStart;
   int endTime = (int)SessionEnd;
   
   // Handle overnight sessions (e.g., 22:00 to 02:00)
   if(startTime > endTime)
   {
      if(currentMinutes >= startTime || currentMinutes <= endTime)
         return true;
   }
   else  // Normal intra-day session
   {
      if(currentMinutes >= startTime && currentMinutes <= endTime)
         return true;
   }
   
   return false;
}

//--- Close all positions for this EA ---
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            {
               trade.PositionClose(ticket);
               Print("Position closed. Ticket: ", ticket);
            }
         }
      }
   }
}

//--- Improved trailing stop logic ---
void TrailingStopLogic()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      
      if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY)
         continue;
      
      double currentProfit = PositionGetDouble(POSITION_PROFIT);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double positionLot = PositionGetDouble(POSITION_VOLUME);
      
      // Calculate profit percentage
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double profitInPips = currentProfit / (positionLot * tickValue);
      
      // Dynamic trailing stop
      if(profitInPips >= 0.5 && currentSL < openPrice)  // 0.5 pips profit
      {
         double trailPips = 0.3;  // 0.3 pips trail
         double trailPoints = trailPips * 10;  // Convert to points
         double newSL = currentBid - (trailPoints * _Point);
         
         if(newSL > currentSL)  // Only move SL up
         {
            if(trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP)))
            {
               Print("Trailing stop updated. New SL: ", newSL, " Profit: $", currentProfit);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+