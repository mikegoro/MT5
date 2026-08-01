//+------------------------------------------------------------------+
//|                                     WakaWaka by MrCapFree.mq5    |
//|                                  https://www.MrCapFree.com |
//+------------------------------------------------------------------+
#property copyright "Mr CapFree"
#property link      "https://www.MrCapFree.com"
#property version   "1.00"
#property strict
#property description "Waka Waka EA"

#include <Trade\Trade.mqh>
      CTrade         Trade;
      CPositionInfo  posInfo;
      COrderInfo     ordInfo;

enum LotSizingEnum    {
      LowRiskPreset = 5,              //Low Risk Set 20% annual (0.25% load)
      MidRiskPreset = 4,              //Mid Risk Set 40% annual (0.5% load)
      HighRiskPreset = 3,             //Significant Risk Set 80% annual (1.0% load)
      ExtremeRiskPreset = 7,          //High Risk Set 120% annual (1.5% load)
      LotsEquity = 2,                 //Dynamic Lot based on Equity
      LotsBalance = 1,                //Dynamic Lot based on Balance
      LotsDepositLoad = 6,            //Lots based on Deposit load
      FixedLots = 0                   //Fixed Lot
      };

enum AllowBuySellEnum {
      AllowSell2 = 2,                 //Sell only
      AllowBuy1 = 1,                  //Buy only
      AllowBuySell = 0                //Buy and Sell
      };

enum eMaxDrawdownAction {
      IgnoreNewUntilRestart = 3,      //Prohibit opening new grids until restart
      IgnoreNewSignals = 2,           //Prohibit opening new grids
      CloseStopTradingUntilRestart = 1,//Close trades & stop trading until restart
      CloseStopTradingFor24h = 0      //Close trades & stop trading for 24h
      };

enum eDrawdownCalculation {
      ThisStrategy = 1,               //This strategy
      TheAccount = 0                  //The account
      };

struct SymbolInformation {
      string      SymbolName;                 // Name of the currency pair (e.g., "AUDCAD")
      datetime    LastMainTFUpdate;           // Timestamp of the last processed M15 main timeframe candle
      datetime    LastOPOTFUpdate;            // Timestamp of the last processed Open Price Only (OPO) timeframe candle
      int         UpdateCounter;              // Counter tracking processed 15m bars to enforce the 2-bar delay after initialization
      bool        CanBuy;                     // Flag indicating if buy conditions are met (RSI, margins, hours, etc.)
      bool        CanSell;                    // Flag indicating if sell conditions are met (RSI, margins, hours, etc.)
      datetime    CurrentBarTime;             // Open time of the current processing bar
      datetime    PreviousBarTime;            // Open time of the previously processed bar
      double      ClosePrice;                 // Closing price of the last completed bar, used for entry checks
      bool        GridOpened;                 // Flag indicating if an active grid series exists on this symbol
      bool        OPOTriggered;               // Flag indicating if the virtual Open Price Only trigger is activated
      double      SmartDistanceMultiplier;    // ATR-based dynamic grid distance multiplier (ATR 96 / ATR 672, clamped 1.0 to 1.5)
      double      BBWidth;                    // Width (bandwidth) of the manually calculated Bollinger Bands (Upper minus Lower)
      int         LastBarIndex;               // Index tracker of the last processed bar
      int         CurrentBarIndex;            // Index tracker of the current active bar
      long        PatternValue;               // Value representing identified candlestick or trend patterns
      double      PatternPrice;               // Price level where the identified pattern was triggered
      bool        PatternSearchActive;        // Flag stating if the EA is actively searching for entry patterns
      bool        TradingAllowedToday;        // Flag indicating if trading is permitted for the current day
      bool        PreviousDayTradingAllowed;  // Stores trading state of the previous day to assist daily rollover checks
      int         LastDayOfWeek;              // Tracks the last processed day of the week to handle daily shifts and holiday restrictions
      double      MaxGridLotMultiplier;       // The highest lot size multiplier achieved in the current active grid
      double      LastBuyAvgPrice;            // Weighted average price of all open buy orders in the current grid
      double      LastSellAvgPrice;           // Weighted average price of all open sell orders in the current grid
      double      LastBuyTP;                  // Target Take Profit price for the active buy grid
      double      LastSellTP;                 // Target Take Profit price for the active sell grid
      datetime    LastBuyGridTime;            // Time when the most recent buy order in the grid was executed
      datetime    LastSellGridTime;           // Time when the most recent sell order in the grid was executed
};

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "<<<========= Select the risk settings ========>"

input bool                    AllowOpeningNewGrid        = true ;        //Allow Opening a new Grid?
input LotSizingEnum           LotSizingMethod            = 5 ;           //Lot-sizing Method
input double                  LotSizingValueFixed        = 0.01 ;        //Fixed Lot
input double                  LotSizingValueDynamic      = 10000 ;       //Dynamic Lot (Balance/Equity based)
input double                  LotSizingDepositLoadPercent= 0.25 ;        //Deposit Load %
input bool                    FixedInitialDeposit        = false ;       //Fixed Initial Deposit? (Tester only)
input double                  MaximumLot                 = 100 ;         //Maximum Lot
input bool                    AutoSplit                  = false ;       //Auto Split?
input double                  MaximumSpread              = 10 ;          //Maximum Spread, in pips
input int                     MaximumSlippage            = 10 ;          //Maximum Slippage for a non-ECN acc, in pips
input int                     MaximumSymbols             = 2 ;           //Maximum Symbols at a time
input bool                    AllowHedging               = true ;        //Allow Hedging?
input bool                    AllowTradingOnHolidays     = false ;       //Allow Trading on Holidays?
input AllowBuySellEnum        AllowToBuySell             = 0 ;           //Allow to Buy/Sell
input double                  MinimumFreeMargin          = 0 ;           //Minimum Free Margin % [0-disabled]
input double                  MaximumDrawdown            = 100 ;         //Max Floating Drawdown %
input double                  MaximumDrawdownMoney       = 0 ;           //Max Floating Drawdown in Money [0-disabled]
input eMaxDrawdownAction      MaximumDrawdownAction      = 0 ;           //Max Drawdown Action
input eDrawdownCalculation    DrawdownCalculation        = 1 ;           //Max Drawdown Calculation

input group "<<<===== Select the strategy settings and symbols used =====>>>"

input string                  Symbols                    = "AUDNZD,AUDCAD,NZDCAD" ; //Symbols separated by comma (custom if
input int                     HourToStartTrading         = 0 ;           //Hour to Start Trading (broker's time)
input int                     HourToStopTrading          = 23 ;          //Hour to Stop Trading (broker's time)
input int                     BollingerBandsPeriod       = 35 ;          //Bollinger Bands Period
input int                     RSI_Period                 = 20 ;          //RSI Period
input int                     RSI_Value                  = 15 ;          //Maximum RSI Value

input group "<<<===== Select TP settings =====>>>"

input double                  InitialTP                  = 10 ;          //TakeProfit for Initial Trade, in pips
input bool                    WeightedTP                 = true ;        //Weighted TakeProfit?
input double                  GridTP                     = 0 ;           //TakeProfit for Grid, in pips (can also be zero
input int                     BreakEvenAfterThisLevel    = 0 ;           //Break Even after this Level [0-disabled]
input bool                    HideTP                     = false ;       //Hide TakeProfit?
input bool                    Use_OPO_Method             = false ;       //Use OPO method to handle TP
input ENUM_TIMEFRAMES         OPO_TimeFrame              = 15 ;          //TF for OPO method
input bool                    SmartTP                    = false ;       //Smart TakeProfit?
input bool                    DoNotAdjustTPUnlessNewGrid = false ;       //Do not adjust TP unless new grid level opene

input group "<<<===== Select SL settings =====>>>"

input double                  GridSL                     = 0 ;           // Stop-loss distance in pips. If set to 0, the EA defaults to a 1000 pips stop-loss to prevent premature stopouts.
input bool                    HideSL                     = false ;       // If true, the SL is hidden from the broker. This is used alongside the OPO (Open Price Only) method so that brief spread spikes do not trigger the SL; the trade only closes if a candle closes past the SL.

input group "<<<===== Adjust the grid distance and multipliers =====>>>"

input int                     TradeDistance              = 35 ;          // The base distance (minimum pips) between consecutive grid levels. The EA checks this on new candles, so the actual distance may be slightly larger than 35 pips.
input bool                    SmartDistance              = true ;        // If true, adjusts grid distance dynamically. It multiplies the TradeDistance by a volatility multiplier (ATR_96 / ATR_672). This multiplier is mathematically clamped strictly between 1.0 (minimum) and 1.5 (maximum).
input double                  TradeMultiplier_2nd        = 1 ;           // Lot size multiplier for the 2nd trade (first grid trade). Set to 1.0 by default to keep the first recovery position at the same volume as the base trade.
input double                  TradeMultiplier_3rd        = 2 ;           // Lot size multiplier applied from the 3rd to 5th positions. Set to 2.0 to double the volume for classic recovery/martingale behavior.
input double                  TradeMultiplier_6th        = 1.5 ;         // Lot size multiplier applied from the 6th position onward. Dropped to 1.5 to reduce drawdown expansion on deep grid levels.
input int                     MaximumTrades              = 9 ;           // Maximum number of open trades permitted in the grid series. Acts as a strict equity protector.
input int                     GridLevelToStart           = 1 ;           // The grid level where full lot sizing actually starts. If greater than 1 (e.g., 3), the EA places low-risk 0.01 "bookmark" trades for levels 1 and 2, delaying the heavy lot sizes until the market has moved against us.
input bool                    KeepOriginalProfitLotSize  = false ;       // Used when GridLevelToStart > 1. If true, the EA calculates the lot size for the starting level as if the previous "bookmark" trades were opened at full lot sizes, instantly skipping to the corresponding multiplier.

input group "Misc"
input string               TradeComment             = "Waka Waka";                  // Trade comment
input int                  UID                      = 0;                            // Unique ID 0 to 9

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
int                  tickCounter             = 0;
ENUM_TIMEFRAMES      mainTimeframe           = PERIOD_M15;
SymbolInformation    symbolsArray[];
ulong                magicNumberBase         = 84570;
double               epsilon                 = 0.00001;
int                  currentHour;
bool                 drawdownTriggered       = false;
bool                 stopTradingUntilRestart = false;
int                  cooldownHours           = 0;
double               initialBalance          = 0;
bool                 initialized             = true;
datetime             lastCheckTimer;
datetime             lastPrintMessage        = 0;
bool                 UIDPrinted              = false;
int                  lastProcessHour;

//+------------------------------------------------------------------+
//| Dynamic Indicator Handles                                        |
//+------------------------------------------------------------------+
int                  maHandles[];
int                  stdDevHandles[];
int                  rsiHandles[];
int                  atr96Handles[];
int                  atr672Handles[];

//+------------------------------------------------------------------+
//| Initialize per-symbol runtime data                               |
//+------------------------------------------------------------------+
void initializeSymbolData(int index, string name)
{
   symbolsArray[index].SymbolName                = name;
   symbolsArray[index].LastMainTFUpdate          = 0;
   symbolsArray[index].LastOPOTFUpdate           = 0;
   symbolsArray[index].UpdateCounter             = 0;
   symbolsArray[index].CanBuy                    = (AllowToBuySell != AllowSell2);
   symbolsArray[index].CanSell                   = (AllowToBuySell != AllowBuy1);
   symbolsArray[index].CurrentBarTime            = 0;
   symbolsArray[index].PreviousBarTime           = 0;
   symbolsArray[index].ClosePrice                = 0.0;
   symbolsArray[index].GridOpened                = false;
   symbolsArray[index].OPOTriggered              = false;
   symbolsArray[index].SmartDistanceMultiplier   = 1.0;
   symbolsArray[index].BBWidth                   = 0.0;
   symbolsArray[index].LastBarIndex              = -1;
   symbolsArray[index].CurrentBarIndex           = 0;
   symbolsArray[index].PatternValue              = 0;
   symbolsArray[index].PatternPrice              = 0.0;
   symbolsArray[index].PatternSearchActive       = false;
   symbolsArray[index].TradingAllowedToday       = true;
   symbolsArray[index].PreviousDayTradingAllowed = true;
   symbolsArray[index].LastDayOfWeek             = -1;
   symbolsArray[index].MaxGridLotMultiplier      = 1.0;
   symbolsArray[index].LastBuyAvgPrice           = 0.0;
   symbolsArray[index].LastSellAvgPrice          = 0.0;
   symbolsArray[index].LastBuyTP                 = 0.0;
   symbolsArray[index].LastSellTP                = 0.0;
   symbolsArray[index].LastBuyGridTime           = 0;
   symbolsArray[index].LastSellGridTime          = 0;
}

//+------------------------------------------------------------------+
//| Parse input symbols and build the symbol tracking array          |
//+------------------------------------------------------------------+
bool parseAndInitializeSymbols()
{
   string parsedSymbols[];
   int symbolCount = 0;

   if(MQLInfoInteger(MQL_TESTER))
   {
      ArrayResize(parsedSymbols, 1);
      parsedSymbols[0] = Symbol();
      symbolCount = 1;
   }
   else
   {
      string rawSymbols[];
      int rawCount = StringSplit(Symbols, StringGetCharacter(",", 0), rawSymbols);

      if(rawCount <= 0)
      {
         Print("No valid symbols were provided in Symbols.");
         return false;
      }

      for(int i = 0; i < rawCount; i++)
      {
         string name = rawSymbols[i];
         StringTrimLeft(name);
         StringTrimRight(name);

         if(name == "")
            continue;

         ArrayResize(parsedSymbols, symbolCount + 1);
         parsedSymbols[symbolCount] = name;
         symbolCount++;
      }
   }

   if(symbolCount <= 0)
   {
      Print("Symbol initialization failed: parsed symbol list is empty.");
      return false;
   }

   ArrayResize(symbolsArray, symbolCount);

   for(int i = 0; i < symbolCount; i++)
   {
      if(!SymbolSelect(parsedSymbols[i], true))
      {
         PrintFormat("Symbol registration failed for %s. Please make sure it is available in Market Watch.", parsedSymbols[i]);
         return false;
      }

      initializeSymbolData(i, parsedSymbols[i]);
   }

   return true;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Waka Waka by Mr. Caffrey initialization started.");

   ChartSetInteger(0, CHART_SHOW_GRID, false);

   drawdownTriggered       = false;
   stopTradingUntilRestart = false;
   cooldownHours           = 0;
   initialized             = true;
   lastCheckTimer          = 0;
   lastPrintMessage        = 0;
   UIDPrinted              = false;
   lastProcessHour         = -1;
   tickCounter             = 0;
   initialBalance          = AccountInfoDouble(ACCOUNT_BALANCE);

   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   currentHour = timeStruct.hour;

   if(!MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
      EventSetTimer(5);

   if(!parseAndInitializeSymbols())
      return INIT_FAILED;

   int symbolCount = ArraySize(symbolsArray);
   ArrayResize(maHandles, symbolCount);
   ArrayResize(stdDevHandles, symbolCount);
   ArrayResize(rsiHandles, symbolCount);
   ArrayResize(atr96Handles, symbolCount);
   ArrayResize(atr672Handles, symbolCount);

   for(int i = 0; i < symbolCount; i++)
   {
      string symbolName = symbolsArray[i].SymbolName;

      maHandles[i]     = iMA(symbolName, mainTimeframe, BollingerBandsPeriod, 0, MODE_SMA, PRICE_CLOSE);
      stdDevHandles[i] = iStdDev(symbolName, mainTimeframe, BollingerBandsPeriod, 0, MODE_SMA, PRICE_CLOSE);
      rsiHandles[i]    = iRSI(symbolName, mainTimeframe, RSI_Period, PRICE_CLOSE);
      atr96Handles[i]  = iATR(symbolName, mainTimeframe, 96);
      atr672Handles[i] = iATR(symbolName, mainTimeframe, 672);

      if(maHandles[i] == INVALID_HANDLE ||
         stdDevHandles[i] == INVALID_HANDLE ||
         rsiHandles[i] == INVALID_HANDLE ||
         atr96Handles[i] == INVALID_HANDLE ||
         atr672Handles[i] == INVALID_HANDLE)
      {
         PrintFormat("Indicator handle creation failed for %s. Make sure all configured symbols are visible in the Market Watch window.", symbolName);
         return INIT_FAILED;
      }
   }

   PrintFormat("Waka Waka initialized successfully with %d symbol(s).", symbolCount);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   tickCounter++;

   int symbolCount = ArraySize(symbolsArray);
   bool orderCandidates[];
   ArrayResize(orderCandidates, symbolCount);

   for(int i = 0; i < symbolCount; i++)
   {
      bool newBar = false;
      string symbolName = symbolsArray[i].SymbolName;
      datetime currentBarTime = iTime(symbolName, mainTimeframe, 0);

      orderCandidates[i] = false;

      if(currentBarTime > symbolsArray[i].LastMainTFUpdate)
      {
         symbolsArray[i].PreviousBarTime = symbolsArray[i].CurrentBarTime;
         symbolsArray[i].CurrentBarTime = currentBarTime;
         symbolsArray[i].LastMainTFUpdate = currentBarTime;
         symbolsArray[i].LastBarIndex = symbolsArray[i].CurrentBarIndex;
         symbolsArray[i].CurrentBarIndex = 0;
         newBar = true;
         updateSymbolInformation(i);
      }

      if(newBar && !symbolsArray[i].GridOpened && (symbolsArray[i].CanBuy || symbolsArray[i].CanSell))
         orderCandidates[i] = true;
   }

   for(int i = 0; i < symbolCount; i++)
   {
      if(orderCandidates[i])
         sendInitialOrder(i);
   }
}

//+------------------------------------------------------------------+
//| Refresh symbol-specific indicator and permission state           |
//+------------------------------------------------------------------+
void updateSymbolInformation(int index)
{
   SymbolInformation symbolData = symbolsArray[index];
   string symbolName = symbolData.SymbolName;

   symbolsArray[index].UpdateCounter++;

   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   currentHour = timeStruct.hour;
   int currentMinute = timeStruct.min;
   int currentDayOfWeek = timeStruct.day_of_week;
   symbolsArray[index].PreviousDayTradingAllowed = symbolsArray[index].TradingAllowedToday;
   symbolsArray[index].LastDayOfWeek = currentDayOfWeek;

   bool tradingAllowed = isTradingAllowed();
   bool canBuyNow = tradingAllowed;
   bool canSellNow = tradingAllowed;

   if(Bars(symbolName, mainTimeframe) < 1000)
   {
      canBuyNow = false;
      canSellNow = false;
   }

   if(symbolsArray[index].UpdateCounter < 2)
   {
      canBuyNow = false;
      canSellNow = false;
   }

   if(!AllowTradingOnHolidays &&
      ((timeStruct.mon == 12 && timeStruct.day >= 25) ||
       (timeStruct.mon == 1 && timeStruct.day <= 3)))
   {
      canBuyNow = false;
      canSellNow = false;
   }

   long tradeMode = SymbolInfoInteger(symbolName, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED || tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY)
   {
      canBuyNow = false;
      canSellNow = false;
   }
   else if(tradeMode == SYMBOL_TRADE_MODE_LONGONLY)
   {
      canSellNow = false;
   }
   else if(tradeMode == SYMBOL_TRADE_MODE_SHORTONLY)
   {
      canBuyNow = false;
   }

   if(AllowToBuySell == AllowBuy1)
      canSellNow = false;
   else if(AllowToBuySell == AllowSell2)
      canBuyNow = false;

   if(HourToStartTrading <= HourToStopTrading)
   {
      if(currentHour < HourToStartTrading || currentHour > HourToStopTrading)
      {
         canBuyNow = false;
         canSellNow = false;
      }
   }
   else
   {
      if(currentHour < HourToStartTrading && currentHour > HourToStopTrading)
      {
         canBuyNow = false;
         canSellNow = false;
      }
   }

   double maBuffer[];
   double stdDevBuffer[];
   ArraySetAsSeries(maBuffer, true);
   ArraySetAsSeries(stdDevBuffer, true);

   if(CopyBuffer(maHandles[index], 0, 1, 1, maBuffer) != 1 ||
      CopyBuffer(stdDevHandles[index], 0, 1, 1, stdDevBuffer) != 1)
   {
      symbolsArray[index].CanBuy = false;
      symbolsArray[index].CanSell = false;
      return;
   }

   double upperBand = maBuffer[0] + (2.0 * stdDevBuffer[0]);
   double lowerBand = maBuffer[0] - (2.0 * stdDevBuffer[0]);
   symbolsArray[index].BBWidth = upperBand - lowerBand;

   double rsiBuffer[];
   ArraySetAsSeries(rsiBuffer, true);

   if(CopyBuffer(rsiHandles[index], 0, 1, 1, rsiBuffer) != 1)
   {
      symbolsArray[index].CanBuy = false;
      symbolsArray[index].CanSell = false;
      return;
   }

   double buyThreshold = 50.0 - RSI_Value;
   double sellThreshold = 50.0 + RSI_Value;

   canBuyNow = canBuyNow && (rsiBuffer[0] < buyThreshold);
   canSellNow = canSellNow && (rsiBuffer[0] > sellThreshold);

   int highestIndex = iHighest(symbolName, mainTimeframe, MODE_HIGH, BollingerBandsPeriod, 1);
   int lowestIndex = iLowest(symbolName, mainTimeframe, MODE_LOW, BollingerBandsPeriod, 1);
   double previousClose = iClose(symbolName, mainTimeframe, 1);
   symbolsArray[index].ClosePrice = previousClose;

   if(highestIndex < 0 || lowestIndex < 0)
   {
      canBuyNow = false;
      canSellNow = false;
   }
   else
   {
      double highestHigh = iHigh(symbolName, mainTimeframe, highestIndex);
      double lowestLow = iLow(symbolName, mainTimeframe, lowestIndex);

      canBuyNow = canBuyNow && (previousClose < lowestLow);
      canSellNow = canSellNow && (previousClose > highestHigh);
   }

   double atr96Buffer[];
   double atr672Buffer[];
   ArraySetAsSeries(atr96Buffer, true);
   ArraySetAsSeries(atr672Buffer, true);

   if(CopyBuffer(atr96Handles[index], 0, 1, 1, atr96Buffer) == 1 &&
      CopyBuffer(atr672Handles[index], 0, 1, 1, atr672Buffer) == 1 &&
      atr672Buffer[0] > epsilon)
   {
      double atrMultiplier = atr96Buffer[0] / atr672Buffer[0];
      symbolsArray[index].SmartDistanceMultiplier = MathMax(1.0, MathMin(1.5, atrMultiplier));
   }
   else
   {
      symbolsArray[index].SmartDistanceMultiplier = 1.0;
   }

   if(MinimumFreeMargin > 0.0)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

      if(equity <= epsilon || ((freeMargin / equity) * 100.0) < MinimumFreeMargin)
      {
         canBuyNow = false;
         canSellNow = false;
      }
   }

   if(drawdownTriggered || stopTradingUntilRestart)
   {
      canBuyNow = false;
      canSellNow = false;
   }

   if(MaximumDrawdown > 0.0 || MaximumDrawdownMoney > 0.0)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double drawdownMoney = MathMax(0.0, balance - equity);
      double drawdownPercent = (balance > epsilon) ? (drawdownMoney / balance) * 100.0 : 0.0;

      if((MaximumDrawdownMoney > 0.0 && drawdownMoney >= MaximumDrawdownMoney) ||
         (MaximumDrawdown > 0.0 && drawdownPercent >= MaximumDrawdown))
      {
         drawdownTriggered = true;
         canBuyNow = false;
         canSellNow = false;
      }
   }

   symbolsArray[index].TradingAllowedToday = tradingAllowed;
   symbolsArray[index].CanBuy = canBuyNow;
   symbolsArray[index].CanSell = canSellNow;
}

//+------------------------------------------------------------------+
//| Verify terminal, EA, account, and connection trading permissions |
//+------------------------------------------------------------------+
bool isTradingAllowed()
{
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
      return false;

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return false;

   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return false;

   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Convert point-based symbols into pip multipliers                 |
//+------------------------------------------------------------------+
int getPipMultiplier(string symbol)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   if(digits == 3 || digits == 5)
      return 10;

   return 1;
}

//+------------------------------------------------------------------+
//| Initial order placeholder                                        |
//+------------------------------------------------------------------+
bool sendInitialOrder(int index)
{
   string symbolName = symbolsArray[index].SymbolName;
   long currentSpread = SymbolInfoInteger(symbolName, SYMBOL_SPREAD);
   double maxAllowedSpread = MaximumSpread * getPipMultiplier(symbolName);

   if(currentSpread > maxAllowedSpread)
      return false;

   if(symbolsArray[index].GridOpened || gridExist(symbolName, 0, 0))
      return false;

   int activeSymbols = 0;
   for(int i = 0; i < ArraySize(symbolsArray); i++)
   {
      if(symbolsArray[i].GridOpened)
         activeSymbols++;
   }

   if(activeSymbols >= MaximumSymbols)
      return false;

   if(symbolsArray[index].CanBuy)
   {
      bool buyGridClear = AllowHedging || !gridExist(symbolName, 0, 2);

      if(buyGridClear && openMarketOrder(index, ORDER_TYPE_BUY))
         return true;
   }

   if(symbolsArray[index].CanSell)
   {
      bool sellGridClear = AllowHedging || !gridExist(symbolName, 0, 1);

      if(sellGridClear && openMarketOrder(index, ORDER_TYPE_SELL))
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Open a base market order                                         |
//+------------------------------------------------------------------+
bool openMarketOrder(int index, ENUM_ORDER_TYPE orderType)
{
   string symbolName = symbolsArray[index].SymbolName;
   bool isBuy = (orderType == ORDER_TYPE_BUY);
   int level = 0;

   for(int attempt = 1; attempt <= 10; attempt++)
   {
      double lotSize = calculateLotSize();
      double price = isBuy ? SymbolInfoDouble(symbolName, SYMBOL_ASK) : SymbolInfoDouble(symbolName, SYMBOL_BID);
      double requiredMargin = 0.0;

      if(lotSize <= 0.0 || price <= 0.0)
      {
         symbolsArray[index].CanBuy = false;
         symbolsArray[index].CanSell = false;
         PrintFormat("Order blocked for %s: invalid lot size or price.", symbolName);
         return false;
      }

      if(!OrderCalcMargin(orderType, symbolName, lotSize, price, requiredMargin))
      {
         symbolsArray[index].CanBuy = false;
         symbolsArray[index].CanSell = false;
         PrintFormat("Order blocked for %s: margin calculation failed. Error %d", symbolName, GetLastError());
         return false;
      }

      if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < requiredMargin)
      {
         symbolsArray[index].CanBuy = false;
         symbolsArray[index].CanSell = false;
         PrintFormat("Order blocked for %s: insufficient free margin for %.2f lots.", symbolName, lotSize);
         return false;
      }

      int direction = isBuy ? 1 : 2;
      int digits = (int)SymbolInfoInteger(symbolName, SYMBOL_DIGITS);
      ulong magic = (direction * (ulong)MathPow(10, digits + 2)) + (magicNumberBase * 100) + level;

      Trade.SetExpertMagicNumber(magic);
      Trade.SetDeviationInPoints((ulong)(MaximumSlippage * getPipMultiplier(symbolName)));

      bool result = false;
      if(isBuy)
         result = Trade.Buy(lotSize, symbolName, 0.0, 0.0, 0.0, TradeComment);
      else
         result = Trade.Sell(lotSize, symbolName, 0.0, 0.0, 0.0, TradeComment);

      if(result)
      {
         datetime now = TimeCurrent();

         symbolsArray[index].GridOpened = true;

         if(isBuy)
            symbolsArray[index].LastBuyGridTime = now;
         else
            symbolsArray[index].LastSellGridTime = now;

         symbolsArray[index].CanBuy = false;
         symbolsArray[index].CanSell = false;

         PrintFormat("%s base order opened on %s. Lots: %.2f, Magic: %I64u",
                     isBuy ? "BUY" : "SELL",
                     symbolName,
                     lotSize,
                     magic);
         return true;
      }

      uint retcode = Trade.ResultRetcode();
      PrintFormat("Order attempt %d failed for %s. Retcode: %u, %s",
                  attempt,
                  symbolName,
                  retcode,
                  Trade.ResultRetcodeDescription());

      if(retcode == TRADE_RETCODE_INVALID_VOLUME ||
         retcode == TRADE_RETCODE_INVALID_PRICE ||
         retcode == TRADE_RETCODE_INVALID_STOPS ||
         retcode == TRADE_RETCODE_MARKET_CLOSED ||
         retcode == TRADE_RETCODE_TRADE_DISABLED ||
         retcode == TRADE_RETCODE_NO_MONEY ||
         retcode == TRADE_RETCODE_ONLY_REAL)
      {
         symbolsArray[index].CanBuy = false;
         symbolsArray[index].CanSell = false;
         break;
      }

      if(attempt < 10)
         Sleep(5000);
   }

   return false;
}

//+------------------------------------------------------------------+
//| Temporary grid lookup stub                                       |
//+------------------------------------------------------------------+
bool gridExist(string symbol, int level, int direction)
{
   return false;
}

//+------------------------------------------------------------------+
//| Temporary lot calculation stub                                   |
//+------------------------------------------------------------------+
double calculateLotSize()
{
   return 0.01;
}

//+------------------------------------------------------------------+
//| Temporary grid lot aggregation stub                              |
//+------------------------------------------------------------------+
double totalLotsInGrid()
{
   return 0.0;
}

//+------------------------------------------------------------------+
//| Temporary drawdown check stub                                    |
//+------------------------------------------------------------------+
void maxDrawdownCheck()
{
}
