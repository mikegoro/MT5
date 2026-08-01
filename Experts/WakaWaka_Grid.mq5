//+------------------------------------------------------------------+
//|                                                WakaWaka_Grid.mq5 |
//|  Educational rebuild of the "Waka Waka" style multi-currency     |
//|  RSI grid/martingale EA (Part 1 spec + Part 2 structure, with    |
//|  the stubbed functions implemented ahead of the video series).   |
//|                                                                  |
//|  Core logic:                                                     |
//|   - Entry: RSI(20) beyond 50 +/- RSIValue on a new M15 bar       |
//|            (+ optional close beyond recent extreme filter)       |
//|   - Grid:  add level every GridDistance pips, optionally scaled  |
//|            by ATR(96)/ATR(672) clamped to [1.0, 1.5]             |
//|   - Lots:  ladder x1 (L1), x2 (L2-L4), x1.6 (L5+), with          |
//|            bookmark levels below GridLevelToStart                |
//|   - TP:    (weighted) average price of the grid +/- TP pips      |
//|   - Magic: direction*10^7 + (84570+UID)*100 + level              |
//+------------------------------------------------------------------+
#property copyright   "Educational rebuild - not for sale"
#property version     "1.00"
#property strict
#property description "Multi-currency RSI grid/martingale rebuild (Waka Waka style)"

#include <Trade\Trade.mqh>

CTrade         trade;
CPositionInfo  positionInfo;
COrderInfo     orderInfo;

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum LOT_SIZING_ENUM
  {
   LOTS_LOW_RISK         = 0, // Low risk (0.25% deposit load)
   LOTS_MID_RISK         = 1, // Medium risk (0.5% deposit load)
   LOTS_SIGNIFICANT_RISK = 2, // Significant risk (1% deposit load)
   LOTS_HIGH_RISK        = 3, // High risk (1.5% deposit load)
   LOTS_DYNAMIC_EQUITY   = 4, // Dynamic lots based on equity
   LOTS_DYNAMIC_BALANCE  = 5, // Dynamic lots based on balance
   LOTS_DEPOSIT_LOAD     = 6, // Lots based on custom deposit load %
   LOTS_FIXED            = 7  // Fixed lots
  };

enum ALLOW_BUY_SELL_ENUM
  {
   ALLOW_BOTH      = 0, // Allow buy and sell
   ALLOW_BUY_ONLY  = 1, // Buy only
   ALLOW_SELL_ONLY = 2  // Sell only
  };

enum DD_ACTION_ENUM
  {
   DD_PROHIBIT_GRIDS_RESTART = 0, // Prohibit new grids until restart
   DD_PROHIBIT_GRIDS_24H     = 1, // Prohibit new grids for 24 hours
   DD_CLOSE_STOP_RESTART     = 2, // Close all trades and stop until restart
   DD_CLOSE_STOP_24H         = 3  // Close all trades and stop for 24 hours
  };

enum DD_CALC_ENUM
  {
   DD_STRATEGY_ONLY = 0, // Drawdown of this strategy only
   DD_WHOLE_ACCOUNT = 1  // Drawdown of the whole account
  };

enum PROP_MODEL_ENUM
  {
   PROP_CUSTOM = 0, // Custom (use the inputs below)
   GOAT_1STEP  = 1, // Goat Funded 1-Step (4% daily, 6% static)
   GOAT_2STEP  = 2, // Goat Funded 2-Step GOAT (4% daily, 10% static)
   GOAT_3STEP  = 3, // Goat Funded 3-Step (4% daily, 8% static)
   GOAT_BLITZ  = 4  // Goat Blitz (3% daily, 5% trailing, 2% floating)
  };

enum PROP_PHASE_ENUM
  {
   PHASE_EVALUATION = 0, // Evaluation
   PHASE_FUNDED     = 1  // Funded ($3k daily profit cap, lower leverage)
  };

//+------------------------------------------------------------------+
//| Per-symbol state                                                 |
//+------------------------------------------------------------------+
struct SymbolState
  {
   string            symbolName;
   datetime          lastMainTFUpdate;
   int               updateCounter;
   bool              canBuy;
   bool              canSell;
   double            smartDistMultiplier;
   double            bbUpper;
   double            bbLower;
   double            bbWidth;
   double            closePrice;
   datetime          currentBarTime;
   datetime          previousBarTime;
   datetime          lastBuyGridTime;
   datetime          lastSellGridTime;
   int               lastBuyLevels;    // grid size when buy TP was last set
   int               lastSellLevels;   // grid size when sell TP was last set
   double            buyTPPrice;       // internal TP when HideTP=true
   double            sellTPPrice;
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Risk / lot sizing ==="
input bool                InpAllowNewGrids       = true;      // Allow opening new grids
input LOT_SIZING_ENUM     InpLotSizingMethod     = LOTS_LOW_RISK;
input double              InpFixedLots           = 0.01;      // Fixed lots
input double              InpDynamicLotPer       = 10000.0;   // Dynamic: 0.01 lot per this balance/equity
input double              InpCustomDepositLoad   = 0.25;      // Custom deposit load %
input double              InpFixedInitialDeposit = 0.0;       // Tester only: fixed initial deposit (0=off)
input double              InpMaxLotPerOrder      = 100.0;     // Max lot per order
input bool                InpAutoSplit           = true;      // Auto-split oversized lots
input double              InpMaxSpreadPips       = 3.0;       // Max spread in pips (0=off)
input int                 InpMaxSlippagePips     = 3;         // Max slippage in pips
input int                 InpMaxSymbolsWithGrids = 2;         // Max symbols with grids at a time
input int                 InpOnlyOneSymbolLevel  = 4;         // Only one symbol if a grid reaches this level (0=off)
input bool                InpAllowHedging        = false;     // Allow buy and sell grid on same symbol
input bool                InpTradeOnHolidays     = false;     // Trade Dec 25 - Jan 3
input ALLOW_BUY_SELL_ENUM InpAllowBuySell        = ALLOW_BOTH;
input double              InpMinFreeMarginPct    = 0.0;       // Min margin level % (0=off)
input double              InpMaxDrawdownPct      = 0.0;       // Max floating drawdown % (0=off)
input double              InpMaxDrawdownMoney    = 0.0;       // Max floating drawdown in money (0=off)
input DD_ACTION_ENUM      InpDrawdownAction      = DD_CLOSE_STOP_RESTART;
input DD_CALC_ENUM        InpDrawdownCalc        = DD_STRATEGY_ONLY;

input group "=== Strategy ==="
input string              InpSymbols             = "AUDCAD,NZDCAD,AUDNZD"; // Symbols (comma separated)
input int                 InpStartHour           = 0;         // Hour to start trading
input int                 InpStopHour            = 23;        // Hour to stop trading
input int                 InpBBPeriod            = 35;        // Bollinger Band period
input int                 InpRSIPeriod           = 20;        // RSI period
input double              InpRSIValue            = 15;        // RSI distance from 50 to trigger
input bool                InpBreakoutFilter      = true;      // Require close beyond recent extreme

input group "=== Take profit ==="
input double              InpInitialTPPips       = 10;        // Initial TP in pips
input bool                InpWeightedTP          = true;      // Weight average price by lots
input double              InpGridTPPips          = 0;         // Grid TP in pips (0 = use initial TP)
input int                 InpBreakEvenAfterLevel = 0;         // Break even after this level (0=off)
input bool                InpHideTP              = false;     // Manage TP internally (don't send to broker)
input bool                InpTPOnlyOnNewLevel    = true;      // Adjust TP only when a new level opens
input bool                InpSmartTP             = false;     // Smart TP: % of Bollinger width
input bool                InpUseOPO              = false;     // OPO: close hidden TP only on bar close beyond it
input ENUM_TIMEFRAMES     InpOPOTimeframe        = PERIOD_M15; // OPO timeframe

input group "=== Stop loss ==="
input double              InpStopLossPips        = 0;         // SL in pips (0 = 1000)
input bool                InpHideSL              = true;      // Don't send SL to broker

input group "=== Grid ==="
input double              InpGridDistancePips    = 35;        // Distance between grid levels in pips
input bool                InpSmartDistance       = true;      // Scale distance by ATR96/ATR672
input double              InpMult2               = 1.0;       // Second trade multiplier
input double              InpMult3to5            = 2.0;       // 3rd to 5th trade multiplier
input double              InpMult6plus           = 1.6;       // 6th+ trade multiplier
input int                 InpMaxTrades           = 10;        // Max trades per grid
input int                 InpGridLevelToStart    = 1;         // Grid level to start (1=normal, N>1 = bookmarks below)
input bool                InpKeepOriginalSizing  = true;      // Keep original lot sizing for bookmark levels

input group "=== Identification ==="
input string              InpTradeComment        = "WakaWaka";
input int                 InpUID                 = 0;         // Unique instance ID (0-9)

input group "=== Prop firm / risk guard ==="
input PROP_MODEL_ENUM     InpPropModel           = PROP_CUSTOM; // Prop model preset (overrides limits & risk sizing)
input PROP_PHASE_ENUM     InpPropPhase           = PHASE_EVALUATION; // Account phase
input string              InpPropFirmName        = "Goat Funded"; // Firm name (panel header, Custom model)
input string              InpAccountPhase        = "Custom";   // Phase label (panel header, Custom model)
input double              InpDailyLossLimitPct   = 5.0;       // Daily loss limit % (0=off)
input double              InpDailyLossBufferPct  = 0.5;       // Stop this % BEFORE the daily limit
input double              InpMaxTotalDDPct       = 10.0;      // Max overall drawdown % from initial (0=off)
input double              InpProfitTargetPct     = 10.0;      // Profit target % (panel display)
input int                 InpDailyResetHour      = 0;         // Server hour of daily reset (0 = broker midnight, ~5PM EST on GMT+2/+3 servers)
input bool                InpMaxDDTrailing       = false;     // Max loss trails highest equity (else static from initial)
input double              InpMaxFloatingLossPct  = 0.0;       // Close all if floating loss hits this % of balance (0=off)

input group "=== News filter (live) ==="
input bool                InpNewsFilter          = false;     // Block initial entries around news
input int                 InpNewsMinutesBefore   = 30;        // Minutes before news
input int                 InpNewsMinutesAfter    = 30;        // Minutes after news
input bool                InpNewsHighOnly        = true;      // Block on high impact only (else medium too)

input group "=== Panel ==="
input bool                InpShowPanel           = true;      // Show the panel
input int                 InpPanelFontSize       = 9;         // Panel font size

input group "=== Tester ==="
input bool                InpTestAllCurrencies   = false;     // Tester: trade all input symbols (slower)

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
#define MAGIC_BASE      84570
#define ATR_FAST_PERIOD 96
#define ATR_SLOW_PERIOD 672
#define DIR_BUY         1
#define DIR_SELL        2

ENUM_TIMEFRAMES mainTimeframe = PERIOD_M15;

SymbolState symbolsArray[];
int maHandle[];
int stdHandle[];
int rsiHandle[];
int atrFastHandle[];
int atrSlowHandle[];

double   EPSILON              = 0.0000001;
int      tickCounter          = 0;
int      lastProcessHour      = -1;
bool     symbolErrorList      = false;
bool     ddTriggered          = false;
bool     stopUntilRestart     = false;
bool     prohibitGridsRestart = false;
int      ddCooldownHours      = 0;
double   initialBalance       = 0;
datetime lastTimerCheck       = 0;
bool     uidErrorPrinted      = false;

// Prop-firm daily guard state
double   dayStartAnchor       = 0;
int      dayStartKey          = -1;
bool     dailyLocked          = false;
bool     dailyProfitLocked    = false;
double   equityHighWatermark  = 0;

// Effective settings - inputs possibly overridden by the prop model preset
LOT_SIZING_ENUM g_lotMethod   = LOTS_FIXED;
double   g_dynamicLotPer      = 10000;
int      g_maxTrades          = 10;
double   g_dailyLossPct       = 0;
double   g_maxDDPct           = 0;
bool     g_ddTrailing         = false;
double   g_floatLossPct       = 0;
double   g_dailyProfitCap     = 0;
string   g_firmLabel          = "";

// Panel / news
#define PANEL_PREFIX "WWP_"
bool     panelEnabled         = false;
datetime lastNewsFetch        = 0;

struct NewsEvent
  {
   datetime          time;
   string            currency;
   string            title;
   int               importance;
  };
NewsEvent newsCache[];

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Apply the prop-model preset: firm limits + risk sizing tuned to  |
//| that model's drawdown budget. Custom = the raw inputs.           |
//+------------------------------------------------------------------+
void ApplyPropPreset()
  {
   g_lotMethod     = InpLotSizingMethod;
   g_dynamicLotPer = InpDynamicLotPer;
   g_maxTrades     = InpMaxTrades;
   g_dailyLossPct  = InpDailyLossLimitPct;
   g_maxDDPct      = InpMaxTotalDDPct;
   g_ddTrailing    = InpMaxDDTrailing;
   g_floatLossPct  = InpMaxFloatingLossPct;
   g_dailyProfitCap = 0;
   g_firmLabel     = InpPropFirmName + " | " + InpAccountPhase;

   switch(InpPropModel)
     {
      case GOAT_1STEP:   // 6% static budget: smallest ladder
         g_dailyLossPct = 4.0;  g_maxDDPct = 6.0;   g_ddTrailing = false;
         g_floatLossPct = 0;    g_lotMethod = LOTS_DYNAMIC_BALANCE;
         g_dynamicLotPer = 15000;  g_maxTrades = 8;
         g_firmLabel = "GOAT FUNDED | 1-STEP";
         break;
      case GOAT_2STEP:   // 10% static budget: roomiest profile
         g_dailyLossPct = 4.0;  g_maxDDPct = 10.0;  g_ddTrailing = false;
         g_floatLossPct = 0;    g_lotMethod = LOTS_DYNAMIC_BALANCE;
         g_dynamicLotPer = 10000;  g_maxTrades = 10;
         g_firmLabel = "GOAT FUNDED | 2-STEP GOAT";
         break;
      case GOAT_3STEP:   // 8% static budget
         g_dailyLossPct = 4.0;  g_maxDDPct = 8.0;   g_ddTrailing = false;
         g_floatLossPct = 0;    g_lotMethod = LOTS_DYNAMIC_BALANCE;
         g_dynamicLotPer = 12000;  g_maxTrades = 9;
         g_firmLabel = "GOAT FUNDED | 3-STEP";
         break;
      case GOAT_BLITZ:   // 2% floating rule: grid must stay tiny and shallow
         g_dailyLossPct = 3.0;  g_maxDDPct = 5.0;   g_ddTrailing = true;
         g_floatLossPct = 2.0;  g_lotMethod = LOTS_DYNAMIC_BALANCE;
         g_dynamicLotPer = 20000;  g_maxTrades = 4;
         g_firmLabel = "GOAT FUNDED | BLITZ";
         break;
      default:
         break;
     }

   if(InpPropModel != PROP_CUSTOM)
     {
      g_firmLabel += (InpPropPhase == PHASE_FUNDED) ? " FUNDED" : " EVAL";
      if(InpPropPhase == PHASE_FUNDED)
         g_dailyProfitCap = 3000; // Goat Funded: excess profit is deducted anyway
     }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   Print(InpTradeComment, ": initializing...");
   ApplyPropPreset();
   Print(InpTradeComment, ": prop profile: ", g_firmLabel,
         "  daily ", DoubleToString(g_dailyLossPct, 1),
         "%  maxDD ", DoubleToString(g_maxDDPct, 1),
         (g_ddTrailing ? "% trailing" : "% static"),
         "  maxTrades ", g_maxTrades);

   ChartSetInteger(0, CHART_SHOW_GRID, false);

   ddCooldownHours      = 0;
   stopUntilRestart     = false;
   prohibitGridsRestart = false;
   ddTriggered          = false;
   initialBalance       = AccountInfoDouble(ACCOUNT_BALANCE);

   if(!MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
     {
      EventSetTimer(5);
      lastTimerCheck = TimeCurrent();
     }

   if(!ParseAndInitializeSymbols())
     {
      Print(InpTradeComment, ": failed to initialize symbols");
      return(INIT_FAILED);
     }

   int arraySize = ArraySize(symbolsArray);
   ArrayResize(maHandle, arraySize);
   ArrayResize(stdHandle, arraySize);
   ArrayResize(rsiHandle, arraySize);
   ArrayResize(atrFastHandle, arraySize);
   ArrayResize(atrSlowHandle, arraySize);

   for(int i = 0; i < arraySize; i++)
     {
      string sym = symbolsArray[i].symbolName;
      maHandle[i]      = iMA(sym, mainTimeframe, InpBBPeriod, 0, MODE_SMA, PRICE_CLOSE);
      stdHandle[i]     = iStdDev(sym, mainTimeframe, InpBBPeriod, 0, MODE_SMA, PRICE_CLOSE);
      rsiHandle[i]     = iRSI(sym, mainTimeframe, InpRSIPeriod, PRICE_CLOSE);
      atrFastHandle[i] = iATR(sym, mainTimeframe, ATR_FAST_PERIOD);
      atrSlowHandle[i] = iATR(sym, mainTimeframe, ATR_SLOW_PERIOD);

      if(maHandle[i] == INVALID_HANDLE || stdHandle[i] == INVALID_HANDLE ||
         rsiHandle[i] == INVALID_HANDLE || atrFastHandle[i] == INVALID_HANDLE ||
         atrSlowHandle[i] == INVALID_HANDLE)
        {
         Print(InpTradeComment, ": failed to create indicators for ", sym,
               ". Check that all input currencies are visible in the Market Watch window.");
         return(INIT_FAILED);
        }
     }

   trade.SetExpertMagicNumber(MakeMagic(DIR_BUY, 0));

   panelEnabled = InpShowPanel && !MQLInfoInteger(MQL_OPTIMIZATION) &&
                  (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE));
   if(panelEnabled)
      UpdatePanel();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i = 0; i < ArraySize(maHandle); i++)
     {
      if(maHandle[i] != INVALID_HANDLE)      IndicatorRelease(maHandle[i]);
      if(stdHandle[i] != INVALID_HANDLE)     IndicatorRelease(stdHandle[i]);
      if(rsiHandle[i] != INVALID_HANDLE)     IndicatorRelease(rsiHandle[i]);
      if(atrFastHandle[i] != INVALID_HANDLE) IndicatorRelease(atrFastHandle[i]);
      if(atrSlowHandle[i] != INVALID_HANDLE) IndicatorRelease(atrSlowHandle[i]);
     }
   ObjectsDeleteAll(0, PANEL_PREFIX);
   ChartRedraw();
   Print(InpTradeComment, ": deinitialized (reason ", reason, ")");
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   // Live-mode 5s refresh for the panel and the news cache
   lastTimerCheck = TimeCurrent();
   RefreshNews();
   if(panelEnabled)
      UpdatePanel();
  }

//+------------------------------------------------------------------+
//| Main tick handler - all logic runs on new bars only              |
//+------------------------------------------------------------------+
void OnTick()
  {
   CheckPropRules();
   CheckMaxDrawdown();

   for(int i = 0; i < ArraySize(symbolsArray); i++)
     {
      // Close conditions run on every tick: hidden TP/SL hits and OPO
      // closes shouldn't wait for the next M15 bar
      CheckAndCloseGrid(i, DIR_BUY);
      CheckAndCloseGrid(i, DIR_SELL);

      bool newBarMainTF;
      datetime barTime = iTime(symbolsArray[i].symbolName, mainTimeframe, 0);
      if(barTime <= symbolsArray[i].lastMainTFUpdate)
         newBarMainTF = false;
      else
        {
         symbolsArray[i].lastMainTFUpdate = barTime;
         newBarMainTF = true;
        }

      if(newBarMainTF)
        {
         UpdateSymbolInfo(i);
         ManageTakeProfit(i, DIR_BUY);
         ManageTakeProfit(i, DIR_SELL);
         ManageGrid(i);
         SendInitialOrder(i);
        }
     }

   if(panelEnabled)
     {
      static datetime lastPanelUpdate = 0;
      if(TimeCurrent() != lastPanelUpdate)
        {
         UpdatePanel();
         lastPanelUpdate = TimeCurrent();
        }
     }
  }

//+------------------------------------------------------------------+
//| Symbol related functions                                         |
//+------------------------------------------------------------------+
bool ParseAndInitializeSymbols()
  {
   bool live = !MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION);
   bool multiSymbolTester = MQLInfoInteger(MQL_TESTER) && InpTestAllCurrencies &&
                            !MQLInfoInteger(MQL_OPTIMIZATION);
   if(live || multiSymbolTester)
     {
      string parts[];
      int symbolCount = StringSplit(InpSymbols, ',', parts);
      if(symbolCount <= 0)
        {
         Print(InpTradeComment, ": symbols input is empty");
         symbolErrorList = true;
         return(false);
        }
      ArrayResize(symbolsArray, symbolCount);
      for(int i = 0; i < symbolCount; i++)
        {
         string name = parts[i];
         StringTrimLeft(name);
         StringTrimRight(name);
         if(name == "")
           {
            Print(InpTradeComment, ": symbols input is incorrect, check for extra commas: ", InpSymbols);
            symbolErrorList = true;
            return(false);
           }
         if(!SymbolSelect(name, true))
           {
            Print(InpTradeComment, ": cannot select symbol ", name, " in Market Watch");
            symbolErrorList = true;
            return(false);
           }
         InitializeSymbolData(i, name);
        }
     }
   else
     {
      // Tester: single-currency mode on the chart symbol
      ArrayResize(symbolsArray, 1);
      InitializeSymbolData(0, _Symbol);
     }
   return(true);
  }

//+------------------------------------------------------------------+
void InitializeSymbolData(int index, string symbolName)
  {
   symbolsArray[index].symbolName          = symbolName;
   symbolsArray[index].lastMainTFUpdate    = 0;
   symbolsArray[index].updateCounter       = 0;
   symbolsArray[index].canBuy              = false;
   symbolsArray[index].canSell             = false;
   symbolsArray[index].smartDistMultiplier = 1.0;
   symbolsArray[index].bbUpper             = 0;
   symbolsArray[index].bbLower             = 0;
   symbolsArray[index].bbWidth             = 0;
   symbolsArray[index].closePrice          = 0;
   symbolsArray[index].currentBarTime      = 0;
   symbolsArray[index].previousBarTime     = 0;
   symbolsArray[index].lastBuyGridTime     = 0;
   symbolsArray[index].lastSellGridTime    = 0;
   symbolsArray[index].lastBuyLevels       = 0;
   symbolsArray[index].lastSellLevels      = 0;
   symbolsArray[index].buyTPPrice          = 0;
   symbolsArray[index].sellTPPrice         = 0;
  }

//+------------------------------------------------------------------+
//| Update per-symbol state and the canBuy/canSell gauntlet          |
//+------------------------------------------------------------------+
void UpdateSymbolInfo(int symbolIndex)
  {
   string symbol = symbolsArray[symbolIndex].symbolName;
   symbolsArray[symbolIndex].updateCounter++;

   MqlDateTime tmCurrent;
   TimeToStruct(TimeCurrent(), tmCurrent);
   int currentHour = tmCurrent.hour;

   symbolsArray[symbolIndex].previousBarTime = symbolsArray[symbolIndex].currentBarTime;
   symbolsArray[symbolIndex].currentBarTime  = iTime(symbol, mainTimeframe, 0);

   bool canTrade = IsTradingAllowed() && InpAllowNewGrids;
   bool canBuy   = canTrade;
   bool canSell  = canTrade;

   // Check historical data
   if(Bars(symbol, mainTimeframe) < 1000)
     {
      canBuy  = false;
      canSell = false;
     }

   // Check free margin
   if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < 10)
     {
      static datetime lastMarginMsg = 0;
      if(TimeCurrent() - lastMarginMsg > 3600)
        {
         Print(InpTradeComment, ": free margin too low: ",
               DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2));
         lastMarginMsg = TimeCurrent();
        }
      canBuy  = false;
      canSell = false;
     }

   // Check UID
   if(InpUID < 0 || InpUID > 9)
     {
      if(!uidErrorPrinted)
        {
         Print(InpTradeComment, ": UID must be between 0 and 9");
         uidErrorPrinted = true;
        }
      canBuy  = false;
      canSell = false;
     }

   // Don't trade on the first bars after initialization
   if(symbolsArray[symbolIndex].updateCounter < 2)
     {
      canBuy  = false;
      canSell = false;
     }

   // Broker-side trade mode for this symbol
   long tradeMode = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
     {
      canBuy  = false;
      canSell = false;
     }
   else if(tradeMode == SYMBOL_TRADE_MODE_LONGONLY)
      canSell = false;
   else if(tradeMode == SYMBOL_TRADE_MODE_SHORTONLY)
      canBuy = false;

   // User-level buy/sell restriction
   if(InpAllowBuySell == ALLOW_BUY_ONLY)
      canSell = false;
   else if(InpAllowBuySell == ALLOW_SELL_ONLY)
      canBuy = false;

   // Bar time structure for hour/day/holiday checks
   datetime barTime = symbolsArray[symbolIndex].currentBarTime;
   MqlDateTime tmBar;
   TimeToStruct(barTime, tmBar);

   // Trading hours (supports overnight windows, e.g. 17 -> 6)
   int barHM   = tmBar.hour * 100 + tmBar.min;
   int startHM = InpStartHour * 100;
   int stopHM  = InpStopHour * 100 + 59;
   bool timeOK;
   if(stopHM > startHM)
      timeOK = (barHM >= startHM && barHM <= stopHM);
   else
      timeOK = (barHM >= startHM || barHM <= stopHM);

   // Holiday check: Dec 25 - Jan 3
   if(!InpTradeOnHolidays)
     {
      if((tmBar.mon == 12 && tmBar.day >= 25) || (tmBar.mon == 1 && tmBar.day <= 3))
         timeOK = false;
     }

   canBuy  = canBuy && timeOK;
   canSell = canSell && timeOK;

   // Last closed candle
   double close = iClose(symbol, mainTimeframe, 1);
   symbolsArray[symbolIndex].closePrice = close;

   // Bollinger Bands calculated manually from MA + StdDev
   // (multi-currency EAs handle this more reliably than iBands)
   double maBuf[1], stdBuf[1];
   if(CopyBuffer(maHandle[symbolIndex], 0, 1, 1, maBuf) == 1 &&
      CopyBuffer(stdHandle[symbolIndex], 0, 1, 1, stdBuf) == 1)
     {
      double bbMA  = maBuf[0];
      double bbStd = stdBuf[0];
      int digits   = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      symbolsArray[symbolIndex].bbUpper = bbMA + 2.0 * bbStd;
      symbolsArray[symbolIndex].bbLower = bbMA - 2.0 * bbStd;
      symbolsArray[symbolIndex].bbWidth =
         NormalizeDouble(symbolsArray[symbolIndex].bbUpper - symbolsArray[symbolIndex].bbLower, digits);
     }

   // RSI filter: buy below 50-X, sell above 50+X
   if(InpRSIPeriod > 0 && InpRSIValue > 0)
     {
      double rsiBuf[1];
      if(CopyBuffer(rsiHandle[symbolIndex], 0, 1, 1, rsiBuf) == 1)
        {
         double rsi = rsiBuf[0];
         canBuy  = canBuy && (rsi < 50.0 - InpRSIValue);
         canSell = canSell && (rsi > 50.0 + InpRSIValue);
        }
      else
        {
         canBuy  = false;
         canSell = false;
        }
     }

   // Breakout confirmation: close beyond the recent extreme
   // (extremes exclude the signal candle itself, hence start shift 2)
   if(InpBreakoutFilter)
     {
      int hiBar = iHighest(symbol, mainTimeframe, MODE_HIGH, InpBBPeriod, 2);
      int loBar = iLowest(symbol, mainTimeframe, MODE_LOW, InpBBPeriod, 2);
      double recentHigh = (hiBar >= 0) ? iHigh(symbol, mainTimeframe, hiBar) : 0;
      double recentLow  = (loBar >= 0) ? iLow(symbol, mainTimeframe, loBar) : 0;
      canBuy  = canBuy && (recentLow > EPSILON) && (close < recentLow);
      canSell = canSell && (recentHigh > EPSILON) && (close > recentHigh);
     }

   // Maximum symbols with active grids
   int activeSymbols = 0;
   for(int i = 0; i < ArraySize(symbolsArray); i++)
     {
      if(GridExists(symbolsArray[i].symbolName, -1, 0))
         activeSymbols++;
     }
   if(activeSymbols >= InpMaxSymbolsWithGrids &&
      !GridExists(symbol, -1, 0))
     {
      canBuy  = false;
      canSell = false;
     }

   // "Only one symbol" rule: a deep grid elsewhere blocks new grids here
   if(InpOnlyOneSymbolLevel > 0 && !GridExists(symbol, -1, 0))
     {
      for(int i = 0; i < ArraySize(symbolsArray); i++)
        {
         if(symbolsArray[i].symbolName == symbol)
            continue;
         if(MaxGridLevel(symbolsArray[i].symbolName, 0) + 1 >= InpOnlyOneSymbolLevel)
           {
            canBuy  = false;
            canSell = false;
            break;
           }
        }
     }

   // Smart distance multiplier: ATR fast / ATR slow, clamped to [1.0, 1.5]
   double atrFastBuf[1], atrSlowBuf[1];
   if(CopyBuffer(atrFastHandle[symbolIndex], 0, 1, 1, atrFastBuf) == 1 &&
      CopyBuffer(atrSlowHandle[symbolIndex], 0, 1, 1, atrSlowBuf) == 1)
     {
      if(atrSlowBuf[0] > EPSILON)
        {
         double mult = atrFastBuf[0] / atrSlowBuf[0];
         mult = MathMax(1.0, mult);
         mult = MathMin(1.5, mult);
         symbolsArray[symbolIndex].smartDistMultiplier = mult;
        }
     }

   // Margin level check
   if(InpMinFreeMarginPct > EPSILON &&
      AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) > EPSILON &&
      AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) < InpMinFreeMarginPct)
     {
      static datetime lastLevelMsg = 0;
      if(TimeCurrent() - lastLevelMsg > 1800)
        {
         Print(InpTradeComment, ": margin level below minimum: ",
               DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 1), "%");
         lastLevelMsg = TimeCurrent();
        }
      canBuy  = false;
      canSell = false;
     }

   // Drawdown control (CheckMaxDrawdown itself runs every tick in OnTick)
   if(ddTriggered || stopUntilRestart || prohibitGridsRestart || ddCooldownHours > 0)
     {
      static datetime lastDDMsg = 0;
      if(TimeCurrent() - lastDDMsg > 3600)
        {
         string reason = "drawdown triggered";
         if(stopUntilRestart)          reason = "drawdown: restart required";
         else if(prohibitGridsRestart) reason = "drawdown: new grids prohibited until restart";
         else if(ddCooldownHours > 0)  reason = "drawdown cooldown: " + (string)ddCooldownHours + " hour(s) left";
         Print(InpTradeComment, ": trading blocked - ", reason);
         lastDDMsg = TimeCurrent();
        }
      canBuy  = false;
      canSell = false;
     }

   // Hourly cooldown countdown; reset drawdown flag once flat
   if(lastProcessHour != currentHour)
     {
      if(ddCooldownHours > 0)
         ddCooldownHours--;
      if(ddCooldownHours < 0)
         ddCooldownHours = 0;
      if(ddTriggered)
        {
         double totalLots = 0;
         for(int i = 0; i < ArraySize(symbolsArray); i++)
            totalLots += GetTotalLotsInGrid(symbolsArray[i].symbolName, 0, 0);
         if(totalLots < EPSILON && ddCooldownHours == 0 && !stopUntilRestart && !prohibitGridsRestart)
            ddTriggered = false;
        }
      lastProcessHour = currentHour;
     }

   // Prop-firm daily lock / profit cap and news filter block new entries
   if(dailyLocked || dailyProfitLocked)
     {
      canBuy  = false;
      canSell = false;
     }
   if(InpNewsFilter && IsNewsTime(symbol))
     {
      canBuy  = false;
      canSell = false;
     }

   symbolsArray[symbolIndex].canBuy  = canBuy;
   symbolsArray[symbolIndex].canSell = canSell;
   tickCounter++;
  }

//+------------------------------------------------------------------+
//| Lot size functions                                               |
//+------------------------------------------------------------------+
double GetBaseLot(string symbol, ENUM_ORDER_TYPE orderType)
  {
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   bool tester = MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION);
   if(tester && InpFixedInitialDeposit > EPSILON)
     {
      // Simulate constant profit withdrawal: always size off the initial deposit
      balance    = InpFixedInitialDeposit;
      equity     = InpFixedInitialDeposit;
      freeMargin = InpFixedInitialDeposit;
     }

   double lots = InpFixedLots;
   switch(g_lotMethod)
     {
      case LOTS_FIXED:
         lots = InpFixedLots;
         break;
      case LOTS_DYNAMIC_BALANCE:
         lots = 0.01 * MathFloor(balance / MathMax(g_dynamicLotPer, 1.0));
         break;
      case LOTS_DYNAMIC_EQUITY:
         lots = 0.01 * MathFloor(equity / MathMax(g_dynamicLotPer, 1.0));
         break;
      default:
        {
         double loadPct = InpCustomDepositLoad;
         if(g_lotMethod == LOTS_LOW_RISK)              loadPct = 0.25;
         else if(g_lotMethod == LOTS_MID_RISK)         loadPct = 0.5;
         else if(g_lotMethod == LOTS_SIGNIFICANT_RISK) loadPct = 1.0;
         else if(g_lotMethod == LOTS_HIGH_RISK)        loadPct = 1.5;

         double marginPerLot = GetMarginRequired(symbol);
         double leverage     = (double)AccountInfoInteger(ACCOUNT_LEVERAGE);
         if(marginPerLot < EPSILON || leverage < EPSILON)
            return(0);
         // Leverage-neutral deposit load: margin per lot shrinks with higher
         // leverage but the 100/leverage normalizer shrinks with it, so the
         // same load% yields the same lots at 1:100 and at 1:500
         lots = freeMargin / marginPerLot * (100.0 / leverage) * (loadPct / 100.0);
         break;
        }
     }

   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   if(lots < minLot)
      lots = minLot;
   return(lots);
  }

//+------------------------------------------------------------------+
//| Cumulative martingale multiplier for a level:                    |
//| L0 = 1, L1 = Mult2, L2-L4 = x Mult3to5 each, L5+ = x Mult6+      |
//+------------------------------------------------------------------+
double CumMultiplier(int level)
  {
   double mult = 1.0;
   for(int l = 1; l <= level; l++)
     {
      if(l == 1)
         mult *= InpMult2;
      else if(l <= 4)
         mult *= InpMult3to5;
      else
         mult *= InpMult6plus;
     }
   return(mult);
  }

//+------------------------------------------------------------------+
//| Sum of our position volumes at one exact grid level              |
//+------------------------------------------------------------------+
double SumLotsAtLevel(string symbol, int direction, int level)
  {
   double total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      int dir, lvl;
      if(!ParseMagic(PositionGetInteger(POSITION_MAGIC), dir, lvl))
         continue;
      if(dir != direction || lvl != level)
         continue;
      total += PositionGetDouble(POSITION_VOLUME);
     }
   return(total);
  }

//+------------------------------------------------------------------+
//| Final lot for a level, honoring GridLevelToStart bookmarks.      |
//| Levels above the anchor derive from the anchor position's actual |
//| lots so the ladder stays consistent if balance changes mid-grid. |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, ENUM_ORDER_TYPE orderType, int level)
  {
   int anchor = MathMax(1, InpGridLevelToStart) - 1; // first fully sized level
   double lots;
   if(level < anchor)
     {
      // Bookmark trade: minimum lot placeholder below the start level
      lots = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
     }
   else if(level == anchor)
     {
      double base = GetBaseLot(symbol, orderType);
      // KeepOriginal: size as if the bookmarks had been full ladder trades
      lots = InpKeepOriginalSizing ? base * CumMultiplier(anchor) : base;
     }
   else
     {
      int direction = (orderType == ORDER_TYPE_BUY) ? DIR_BUY : DIR_SELL;
      double anchorLots = SumLotsAtLevel(symbol, direction, anchor);
      if(anchorLots < EPSILON)
        {
         double base = GetBaseLot(symbol, orderType);
         anchorLots = InpKeepOriginalSizing ? base * CumMultiplier(anchor) : base;
        }
      lots = anchorLots * CumMultiplier(level) / CumMultiplier(anchor);
     }
   return(NormalizeLots(symbol, lots));
  }

//+------------------------------------------------------------------+
double NormalizeLots(string symbol, double lots)
  {
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(lotStep > EPSILON)
      lots = MathFloor(lots / lotStep + 0.5) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return(NormalizeDouble(lots, 8));
  }

//+------------------------------------------------------------------+
//| Grid related functions                                           |
//+------------------------------------------------------------------+
// direction: 0 = any, DIR_BUY, DIR_SELL. level: -1 = any.
bool GridExists(string symbol, int level, int direction)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      int dir, lvl;
      if(!ParseMagic(PositionGetInteger(POSITION_MAGIC), dir, lvl))
         continue;
      if(direction != 0 && dir != direction)
         continue;
      if(level >= 0 && lvl != level)
         continue;
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Highest open grid level, -1 if no grid. direction: 0 = any       |
//+------------------------------------------------------------------+
int MaxGridLevel(string symbol, int direction)
  {
   int maxLevel = -1;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      int dir, lvl;
      if(!ParseMagic(PositionGetInteger(POSITION_MAGIC), dir, lvl))
         continue;
      if(direction != 0 && dir != direction)
         continue;
      if(lvl > maxLevel)
         maxLevel = lvl;
     }
   return(maxLevel);
  }

//+------------------------------------------------------------------+
//| Total lots in a grid. direction 0 = both; minLevel 0 = all       |
//+------------------------------------------------------------------+
double GetTotalLotsInGrid(string symbol, int direction, int minLevel)
  {
   double total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(symbol != "" && PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      int dir, lvl;
      if(!ParseMagic(PositionGetInteger(POSITION_MAGIC), dir, lvl))
         continue;
      if(direction != 0 && dir != direction)
         continue;
      if(lvl < minLevel)
         continue;
      total += PositionGetDouble(POSITION_VOLUME);
     }
   return(total);
  }

//+------------------------------------------------------------------+
//| Snapshot of one direction's grid on a symbol                     |
//+------------------------------------------------------------------+
void CollectGrid(string symbol, int direction, int &count, double &totalLots,
                 double &avgPrice, double &weightedAvgPrice, double &weightedAvgAdjPrice,
                 int &maxLevel, double &lowestOpen, double &highestOpen)
  {
   count = 0; totalLots = 0; avgPrice = 0; weightedAvgPrice = 0; weightedAvgAdjPrice = 0;
   maxLevel = -1; lowestOpen = 0; highestOpen = 0;
   double sumPrice = 0, sumLotPrice = 0, sumLotAdjPrice = 0;
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      int dir, lvl;
      if(!ParseMagic(PositionGetInteger(POSITION_MAGIC), dir, lvl))
         continue;
      if(dir != direction)
         continue;

      double lots = PositionGetDouble(POSITION_VOLUME);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);

      // Cost-adjusted open: fold the accrued swap into the price so a TP
      // off this average also covers the carrying costs of the grid
      // (position-level commission is deprecated in MT5; it lives on deals)
      double adjOpen = open;
      double cost = PositionGetDouble(POSITION_SWAP);
      if(tickValue * lots > EPSILON && MathAbs(cost) > EPSILON)
        {
         double priceAdj = cost / (tickValue * lots) * point;
         adjOpen = (dir == DIR_BUY) ? open - priceAdj : open + priceAdj;
        }

      count++;
      totalLots      += lots;
      sumPrice       += open;
      sumLotPrice    += lots * open;
      sumLotAdjPrice += lots * adjOpen;
      if(lvl > maxLevel)
         maxLevel = lvl;
      if(lowestOpen == 0 || open < lowestOpen)
         lowestOpen = open;
      if(open > highestOpen)
         highestOpen = open;
     }
   if(count > 0)
     {
      avgPrice = sumPrice / count;
      if(totalLots > EPSILON)
        {
         weightedAvgPrice    = sumLotPrice / totalLots;
         weightedAvgAdjPrice = sumLotAdjPrice / totalLots;
        }
     }
  }

//+------------------------------------------------------------------+
//| Add grid levels. Level N opens when the bar close has moved      |
//| N x GridDistance (x smart mult) beyond the grid's weighted       |
//| average price - the original EA's geometry.                      |
//+------------------------------------------------------------------+
void ManageGrid(int symbolIndex)
  {
   if(!IsTradingAllowed())
      return;
   if(dailyLocked || dailyProfitLocked)
      return; // daily guard / profit cap: no new exposure
   if(stopUntilRestart || (ddTriggered &&
      (InpDrawdownAction == DD_CLOSE_STOP_RESTART || InpDrawdownAction == DD_CLOSE_STOP_24H)))
      return;
   if(g_maxTrades < 1 || InpMult3to5 <= 0 || InpGridDistancePips < EPSILON)
      return;

   CheckGridDirection(symbolIndex, ORDER_TYPE_BUY);
   CheckGridDirection(symbolIndex, ORDER_TYPE_SELL);
  }

//+------------------------------------------------------------------+
void CheckGridDirection(int symbolIndex, ENUM_ORDER_TYPE orderType)
  {
   string symbol = symbolsArray[symbolIndex].symbolName;
   int direction = (orderType == ORDER_TYPE_BUY) ? DIR_BUY : DIR_SELL;

   if(!GridExists(symbol, -1, direction))
      return;

   int count, maxLevel;
   double totalLots, avg, wavg, wavgAdj, lowest, highest;
   CollectGrid(symbol, direction, count, totalLots, avg, wavg, wavgAdj, maxLevel, lowest, highest);
   if(count == 0 || wavg < EPSILON)
      return;

   double pip = SymbolInfoDouble(symbol, SYMBOL_POINT) * GetPipMultiplier(symbol);
   double close = symbolsArray[symbolIndex].closePrice;
   double priceDiff = close - wavg;

   // Walk the levels and open the first missing one whose distance is reached
   for(int level = 1; level < g_maxTrades && level < 100; level++)
     {
      if(GridExists(symbol, level, direction))
         continue;
      double priceDistance = InpGridDistancePips * level * pip;
      if(InpSmartDistance)
         priceDistance *= symbolsArray[symbolIndex].smartDistMultiplier;
      bool reached = (orderType == ORDER_TYPE_BUY) ? (priceDiff < -priceDistance)
                                                   : (priceDiff > priceDistance);
      if(!reached)
         continue;
      OpenMarketOrder(symbolIndex, orderType, level);
      break; // at most one new level per bar
     }
  }

//+------------------------------------------------------------------+
//| Open the initial (level 0) order when the RSI signal fires       |
//+------------------------------------------------------------------+
void SendInitialOrder(int symbolIndex)
  {
   string symbol = symbolsArray[symbolIndex].symbolName;

   if(!symbolsArray[symbolIndex].canBuy && !symbolsArray[symbolIndex].canSell)
      return;
   if(!IsTradingAllowed())
      return;

   // Try to open the buy order
   if(symbolsArray[symbolIndex].canBuy)
     {
      bool noPosition;
      if(InpAllowHedging)
         noPosition = !GridExists(symbol, -1, DIR_BUY);
      else
         noPosition = !GridExists(symbol, -1, 0);
      if(noPosition)
         OpenMarketOrder(symbolIndex, ORDER_TYPE_BUY, 0);
     }

   // Try to open the sell order
   if(symbolsArray[symbolIndex].canSell)
     {
      bool noPosition;
      if(InpAllowHedging)
         noPosition = !GridExists(symbol, -1, DIR_SELL);
      else
         noPosition = !GridExists(symbol, -1, 0);
      if(noPosition)
         OpenMarketOrder(symbolIndex, ORDER_TYPE_SELL, 0);
     }
  }

//+------------------------------------------------------------------+
//| Send a market order with retries, margin check and auto-split    |
//+------------------------------------------------------------------+
void OpenMarketOrder(int symbolIndex, ENUM_ORDER_TYPE orderType, int level)
  {
   string symbol = symbolsArray[symbolIndex].symbolName;

   // Spread check (user input in pips, broker spread in points)
   double spreadPoints = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   if(InpMaxSpreadPips > EPSILON && spreadPoints > InpMaxSpreadPips * GetPipMultiplier(symbol))
     {
      Print(InpTradeComment, ": spread too high on ", symbol, " (", spreadPoints, " points)");
      return;
     }

   double lotSize = CalculateLotSize(symbol, orderType, level);
   if(lotSize < EPSILON)
     {
      Print(InpTradeComment, ": calculated lot size too small for ", symbol);
      return;
     }

   // Split into broker/user-compliant chunks
   double chunkMax  = GetMaxLotForSymbol(symbol);
   double remaining = lotSize;
   if(!InpAutoSplit && remaining > chunkMax)
      remaining = chunkMax;

   while(remaining > EPSILON)
     {
      double chunk = NormalizeLots(symbol, MathMin(remaining, chunkMax));
      if(chunk < EPSILON)
         break;
      if(!SendSingleOrder(symbolIndex, orderType, level, chunk))
         return;
      remaining -= chunk;
      if(remaining < SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN) - EPSILON)
         break;
     }
  }

//+------------------------------------------------------------------+
bool SendSingleOrder(int symbolIndex, ENUM_ORDER_TYPE orderType, int level, double lotSize)
  {
   string symbol = symbolsArray[symbolIndex].symbolName;
   int maxAttempts = 10;

   for(int attempt = 0; attempt < maxAttempts; attempt++)
     {
      // Margin pre-check
      double price = (orderType == ORDER_TYPE_BUY)
                     ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                     : SymbolInfoDouble(symbol, SYMBOL_BID);
      double margin = 0;
      if(!OrderCalcMargin(orderType, symbol, lotSize, price, margin) ||
         margin <= 0 || margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
        {
         Print(InpTradeComment, ": not enough money for ", DoubleToString(lotSize, 2),
               " lots on ", symbol);
         if(orderType == ORDER_TYPE_BUY)
            symbolsArray[symbolIndex].canBuy = false;
         else
            symbolsArray[symbolIndex].canSell = false;
         return(false);
        }

      long magic = MakeMagic(orderType == ORDER_TYPE_BUY ? DIR_BUY : DIR_SELL, level);
      string comment = InpTradeComment + "-L" + (string)level;
      Print(InpTradeComment, ": sending ", (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
            " L", level, " ", DoubleToString(lotSize, 2), " ", symbol,
            " attempt ", attempt + 1);

      trade.SetExpertMagicNumber(magic);
      trade.SetDeviationInPoints((ulong)(InpMaxSlippagePips * GetPipMultiplier(symbol)));

      // SL sent with the order (unless hidden); TP is managed afterwards
      double sl = 0;
      if(!InpHideSL)
        {
         double pip = SymbolInfoDouble(symbol, SYMBOL_POINT) * GetPipMultiplier(symbol);
         double slPips = (InpStopLossPips > EPSILON) ? InpStopLossPips : 1000;
         int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         if(orderType == ORDER_TYPE_BUY)
            sl = NormalizeDouble(price - slPips * pip, digits);
         else
            sl = NormalizeDouble(price + slPips * pip, digits);
        }

      bool success;
      if(orderType == ORDER_TYPE_BUY)
         success = trade.Buy(lotSize, symbol, 0, sl, 0, comment);
      else
         success = trade.Sell(lotSize, symbol, 0, sl, 0, comment);

      if(success)
        {
         Print(InpTradeComment, ": order opened on ", symbol, " L", level);
         if(orderType == ORDER_TYPE_BUY)
           {
            symbolsArray[symbolIndex].canBuy = false;
            symbolsArray[symbolIndex].lastBuyGridTime = TimeCurrent();
           }
         else
           {
            symbolsArray[symbolIndex].canSell = false;
            symbolsArray[symbolIndex].lastSellGridTime = TimeCurrent();
           }
         return(true);
        }

      uint retcode = trade.ResultRetcode();
      Print(InpTradeComment, ": failed to open order on ", symbol,
            " - ", trade.ResultRetcodeDescription(), " (", retcode, ")");
      if(retcode == TRADE_RETCODE_INVALID || retcode == TRADE_RETCODE_INVALID_VOLUME ||
         retcode == TRADE_RETCODE_NO_MONEY || retcode == TRADE_RETCODE_MARKET_CLOSED ||
         retcode == TRADE_RETCODE_TRADE_DISABLED)
        {
         // Fatal - retrying won't help
         symbolsArray[symbolIndex].canBuy  = false;
         symbolsArray[symbolIndex].canSell = false;
         return(false);
        }
      Sleep(5000); // no-op in tester
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| TP and SL related functions                                      |
//+------------------------------------------------------------------+
void ManageTakeProfit(int symbolIndex, int direction)
  {
   string symbol = symbolsArray[symbolIndex].symbolName;

   int count, maxLevel;
   double totalLots, avg, wavg, wavgAdj, lowest, highest;
   CollectGrid(symbol, direction, count, totalLots, avg, wavg, wavgAdj, maxLevel, lowest, highest);

   int lastLevels = (direction == DIR_BUY) ? symbolsArray[symbolIndex].lastBuyLevels
                                           : symbolsArray[symbolIndex].lastSellLevels;
   if(count == 0)
     {
      if(direction == DIR_BUY)
        {
         symbolsArray[symbolIndex].lastBuyLevels = 0;
         symbolsArray[symbolIndex].buyTPPrice = 0;
        }
      else
        {
         symbolsArray[symbolIndex].lastSellLevels = 0;
         symbolsArray[symbolIndex].sellTPPrice = 0;
        }
      return;
     }

   // Only re-place the TP when the grid grew (if the user asked for that)
   if(InpTPOnlyOnNewLevel && count == lastLevels)
      return;

   // Cost-adjusted weighted average so the TP also covers swaps/commission
   double basePrice = InpWeightedTP ? wavgAdj : avg;
   double pip = SymbolInfoDouble(symbol, SYMBOL_POINT) * GetPipMultiplier(symbol);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double tpPrice;

   if(InpSmartTP && symbolsArray[symbolIndex].bbWidth > EPSILON &&
      MathMax(1, InpGridLevelToStart) == 1)
     {
      // Smart TP: a fraction of the Bollinger width (InitialTP pips read as %).
      // Deep grids (past level 5) halve the fraction to pull the TP closer.
      double factor = InpInitialTPPips / 100.0;
      if(maxLevel + 1 > 5)
         factor /= 2.0;
      double tpDist = factor * symbolsArray[symbolIndex].bbWidth;
      tpPrice = (direction == DIR_BUY) ? basePrice + tpDist : basePrice - tpDist;
     }
   else
     {
      double tpPips = (count > 1 && InpGridTPPips > EPSILON) ? InpGridTPPips : InpInitialTPPips;
      if(InpBreakEvenAfterLevel > 0 && maxLevel + 1 > InpBreakEvenAfterLevel)
         tpPips = 0; // break even: TP sits on the (cost-adjusted) average price
      tpPrice = (direction == DIR_BUY) ? basePrice + tpPips * pip
                                       : basePrice - tpPips * pip;
     }
   tpPrice = NormalizeDouble(tpPrice, digits);

   if(direction == DIR_BUY)
     {
      symbolsArray[symbolIndex].buyTPPrice = tpPrice;
      symbolsArray[symbolIndex].lastBuyLevels = count;
     }
   else
     {
      symbolsArray[symbolIndex].sellTPPrice = tpPrice;
      symbolsArray[symbolIndex].lastSellLevels = count;
     }

   if(InpHideTP)
      return; // managed internally, nothing sent to the broker

   // Respect the broker's minimum stop distance when sending the TP
   double stopsDist = (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) *
                      SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(stopsDist > EPSILON)
     {
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(direction == DIR_BUY)
         tpPrice = NormalizeDouble(MathMax(tpPrice, bid + stopsDist), digits);
      else
         tpPrice = NormalizeDouble(MathMin(tpPrice, ask - stopsDist), digits);
     }

   // Push the shared TP to every position in this grid
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      int dir, lvl;
      if(!ParseMagic(PositionGetInteger(POSITION_MAGIC), dir, lvl))
         continue;
      if(dir != direction)
         continue;
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      if(MathAbs(curTP - tpPrice) > SymbolInfoDouble(symbol, SYMBOL_POINT) / 2.0)
        {
         if(!trade.PositionModify(ticket, curSL, tpPrice))
            Print(InpTradeComment, ": failed to modify TP on ", symbol,
                  " ticket ", ticket, " - ", trade.ResultRetcodeDescription());
        }
     }
  }

//+------------------------------------------------------------------+
//| Closing grids / drawdowns                                        |
//+------------------------------------------------------------------+
//| Internal close conditions, checked every tick: hidden SL at the  |
//| grid SL distance from the average, and hidden TP (optionally OPO |
//| - only when a closed bar on the OPO timeframe is beyond the TP). |
//+------------------------------------------------------------------+
void CheckAndCloseGrid(int symbolIndex, int direction)
  {
   if(!InpHideTP && !InpHideSL)
      return; // broker-side TP/SL handle the closing

   string symbol = symbolsArray[symbolIndex].symbolName;

   int count, maxLevel;
   double totalLots, avg, wavg, wavgAdj, lowest, highest;
   CollectGrid(symbol, direction, count, totalLots, avg, wavg, wavgAdj, maxLevel, lowest, highest);
   if(count == 0)
      return;

   double pip = SymbolInfoDouble(symbol, SYMBOL_POINT) * GetPipMultiplier(symbol);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   bool shouldClose = false;
   string reason = "";

   if(InpHideSL && wavgAdj > EPSILON)
     {
      double slPips  = (InpStopLossPips > EPSILON) ? InpStopLossPips : 1000;
      double slPrice = (direction == DIR_BUY) ? wavgAdj - slPips * pip
                                              : wavgAdj + slPips * pip;
      if((direction == DIR_BUY && bid <= slPrice) ||
         (direction == DIR_SELL && ask >= slPrice))
        {
         shouldClose = true;
         reason = "internal SL hit";
        }
     }

   if(!shouldClose && InpHideTP)
     {
      double tp = (direction == DIR_BUY) ? symbolsArray[symbolIndex].buyTPPrice
                                         : symbolsArray[symbolIndex].sellTPPrice;
      if(tp > EPSILON)
        {
         if(InpUseOPO)
           {
            double opoClose = iClose(symbol, InpOPOTimeframe, 1);
            if((direction == DIR_BUY && opoClose >= tp) ||
               (direction == DIR_SELL && opoClose <= tp))
              {
               shouldClose = true;
               reason = "OPO close beyond internal TP";
              }
           }
         else if((direction == DIR_BUY && bid >= tp) ||
                 (direction == DIR_SELL && ask <= tp))
           {
            shouldClose = true;
            reason = "internal TP hit";
           }
        }
     }

   if(!shouldClose)
      return;

   // Don't close into a spread spike; try again on the next tick
   double spreadPoints = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   if(InpMaxSpreadPips > EPSILON && spreadPoints > InpMaxSpreadPips * GetPipMultiplier(symbol))
      return;

   Print(InpTradeComment, ": closing ", (direction == DIR_BUY ? "BUY" : "SELL"),
         " grid on ", symbol, " - ", reason);
   CloseGrid(symbol, direction);
  }

//+------------------------------------------------------------------+
void CloseGrid(string symbol, int direction)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(symbol != "" && PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      int dir, lvl;
      if(!ParseMagic(PositionGetInteger(POSITION_MAGIC), dir, lvl))
         continue;
      if(direction != 0 && dir != direction)
         continue;
      if(!trade.PositionClose(ticket))
         Print(InpTradeComment, ": failed to close ticket ", ticket,
               " - ", trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
void CheckMaxDrawdown()
  {
   if(ddTriggered || stopUntilRestart)
      return;
   if(InpMaxDrawdownPct < EPSILON && InpMaxDrawdownMoney < EPSILON)
      return;

   double floating = 0;
   if(InpDrawdownCalc == DD_WHOLE_ACCOUNT)
      floating = AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE);
   else
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         int dir, lvl;
         if(!ParseMagic(PositionGetInteger(POSITION_MAGIC), dir, lvl))
            continue;
         floating += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        }
     }

   double drawdown = -floating;
   if(drawdown < EPSILON)
      return;

   double balanceBase = AccountInfoDouble(ACCOUNT_BALANCE);
   bool tester = MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION);
   if(tester && InpFixedInitialDeposit > EPSILON)
      balanceBase = InpFixedInitialDeposit;

   bool hit = false;
   if(InpMaxDrawdownPct > EPSILON && balanceBase > EPSILON &&
      drawdown / balanceBase * 100.0 >= InpMaxDrawdownPct)
      hit = true;
   if(InpMaxDrawdownMoney > EPSILON && drawdown >= InpMaxDrawdownMoney)
      hit = true;
   if(!hit)
      return;

   ddTriggered = true;
   Print(InpTradeComment, ": MAX DRAWDOWN HIT - floating ", DoubleToString(floating, 2),
         " (", DoubleToString(drawdown / MathMax(balanceBase, 1) * 100.0, 2), "% of ",
         DoubleToString(balanceBase, 2), ")");

   switch(InpDrawdownAction)
     {
      case DD_CLOSE_STOP_RESTART:
         CloseGrid("", 0);
         stopUntilRestart = true;
         break;
      case DD_CLOSE_STOP_24H:
         CloseGrid("", 0);
         ddCooldownHours = 24;
         break;
      case DD_PROHIBIT_GRIDS_RESTART:
         prohibitGridsRestart = true;
         break;
      case DD_PROHIBIT_GRIDS_24H:
         ddCooldownHours = 24;
         break;
     }
  }

//+------------------------------------------------------------------+
//| General helping functions                                        |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
  {
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
      return(true);
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return(false);
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      return(false);
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      return(false);
   return(true);
  }

//+------------------------------------------------------------------+
//| Margin required for 1.0 lot, with retries                        |
//+------------------------------------------------------------------+
double GetMarginRequired(string symbol)
  {
   double margin = 0;
   for(int attempt = 0; attempt < 3 && margin < EPSILON; attempt++)
     {
      if(attempt > 0)
         Sleep(100 * attempt);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(!OrderCalcMargin(ORDER_TYPE_BUY, symbol, 1.0, ask, margin))
         margin = 0;
     }
   if(margin < EPSILON)
      Print(InpTradeComment, ": failed to get margin requirement for ", symbol);
   return(margin);
  }

//+------------------------------------------------------------------+
//| Max lot per order: broker per-order max, per-symbol limit, and   |
//| the user's own cap - whichever is smallest                       |
//+------------------------------------------------------------------+
double GetMaxLotForSymbol(string symbol)
  {
   double maxLot   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double limitLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_LIMIT);
   if(limitLot > EPSILON && limitLot < maxLot)
      maxLot = limitLot;
   if(InpMaxLotPerOrder > EPSILON && InpMaxLotPerOrder < maxLot)
      maxLot = InpMaxLotPerOrder;
   return(maxLot);
  }

//+------------------------------------------------------------------+
//| Pips vs points: 10 for 5/3-digit symbols, 1 otherwise            |
//+------------------------------------------------------------------+
double GetPipMultiplier(string symbol)
  {
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(digits == 5 || digits == 3)
      return(10.0);
   return(1.0);
  }

//+------------------------------------------------------------------+
//| Magic number scheme:                                             |
//|   direction * 10^7 + (84570 + UID) * 100 + level                 |
//|   buy L0 = 1_84570_00, sell L3 = 2_84570_03                      |
//+------------------------------------------------------------------+
long MakeMagic(int direction, int level)
  {
   long base = MAGIC_BASE + InpUID;
   return((long)direction * 10000000 + base * 100 + level);
  }

//+------------------------------------------------------------------+
bool ParseMagic(long magic, int &direction, int &level)
  {
   long dir = magic / 10000000;
   if(dir != DIR_BUY && dir != DIR_SELL)
      return(false);
   long rem = magic - dir * 10000000;
   if(rem / 100 != MAGIC_BASE + InpUID)
      return(false);
   direction = (int)dir;
   level     = (int)(rem % 100);
   return(true);
  }

//+------------------------------------------------------------------+
//| Prop-firm risk guard: daily loss limit (with early buffer) and   |
//| max overall drawdown from the initial balance. Checked per tick. |
//+------------------------------------------------------------------+
void CheckPropRules()
  {
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double worst   = MathMin(balance, equity); // firms breach on balance OR equity

   if(equity > equityHighWatermark)
      equityHighWatermark = equity;

   // Day rollover at the firm's reset hour (Goat Funded: 5PM EST = broker
   // midnight on GMT+2/+3 servers). Anchor = HIGHER of balance/equity.
   MqlDateTime tm;
   TimeToStruct(TimeCurrent() - InpDailyResetHour * 3600, tm);
   int dayKey = tm.year * 1000 + tm.day_of_year;
   if(dayKey != dayStartKey)
     {
      dayStartKey       = dayKey;
      dayStartAnchor    = MathMax(balance, equity);
      dailyLocked       = false;
      dailyProfitLocked = false;
     }

   // Daily loss: a FIXED amount (% of the initial account size) below the
   // day's anchor - not a percentage of the anchor itself
   if(!dailyLocked && g_dailyLossPct > EPSILON &&
      initialBalance > EPSILON && dayStartAnchor > EPSILON)
     {
      double guardAmt = initialBalance *
                        MathMax(0.1, g_dailyLossPct - InpDailyLossBufferPct) / 100.0;
      if(worst <= dayStartAnchor - guardAmt)
        {
         dailyLocked = true;
         Print(InpTradeComment, ": DAILY LOSS GUARD hit (", DoubleToString(guardAmt, 2),
               " below day anchor ", DoubleToString(dayStartAnchor, 2),
               ") - closing everything, locked until the next trading day");
         CloseGrid("", 0);
        }
     }

   // Funded daily profit cap: stop adding exposure near the cap - profits
   // above it are deducted by the firm, so there is nothing to gain
   if(!dailyProfitLocked && g_dailyProfitCap > EPSILON &&
      equity - dayStartAnchor >= g_dailyProfitCap * 0.95)
     {
      dailyProfitLocked = true;
      Print(InpTradeComment, ": daily profit cap reached (",
            DoubleToString(equity - dayStartAnchor, 2), " / ",
            DoubleToString(g_dailyProfitCap, 2), ") - no new exposure today");
     }

   // Floating loss rule (e.g. Goat Blitz: -2% open PnL = instant closure).
   // Guard fires at the buffer distance before the firm's line.
   if(g_floatLossPct > EPSILON && balance > EPSILON)
     {
      double guardPct = MathMax(0.1, g_floatLossPct - InpDailyLossBufferPct);
      if(equity - balance <= -balance * guardPct / 100.0)
        {
         Print(InpTradeComment, ": FLOATING LOSS GUARD hit at -", DoubleToString(guardPct, 2),
               "% (firm limit -", DoubleToString(g_floatLossPct, 2),
               "%) - closing everything");
         CloseGrid("", 0);
        }
     }

   // Max overall loss: static floor from initial size, or trailing below
   // the highest recorded equity. Guard fires a buffer early.
   if(!stopUntilRestart && g_maxDDPct > EPSILON && initialBalance > EPSILON)
     {
      double base  = g_ddTrailing ? equityHighWatermark : initialBalance;
      double floor = base * (1.0 - g_maxDDPct / 100.0) +
                     initialBalance * InpDailyLossBufferPct / 100.0;
      if(worst <= floor)
        {
         stopUntilRestart = true;
         ddTriggered      = true;
         Print(InpTradeComment, ": MAX ", (g_ddTrailing ? "TRAILING" : "STATIC"),
               " DRAWDOWN guard hit (floor ", DoubleToString(floor, 2),
               ") - closing everything, stopped until restart");
         CloseGrid("", 0);
        }
     }
  }

//+------------------------------------------------------------------+
//| News: cache upcoming events from the MT5 economic calendar       |
//| (live only - the calendar is not available in the tester)        |
//+------------------------------------------------------------------+
void RefreshNews()
  {
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
      return;
   if(lastNewsFetch > 0 && TimeCurrent() - lastNewsFetch < 900)
      return;
   lastNewsFetch = TimeCurrent();
   ArrayResize(newsCache, 0);

   MqlCalendarValue values[];
   datetime from = TimeCurrent() - 2 * 3600;
   datetime to   = TimeCurrent() + 48 * 3600;
   if(!CalendarValueHistory(values, from, to))
      return;

   for(int i = 0; i < ArraySize(values) && ArraySize(newsCache) < 40; i++)
     {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event))
         continue;
      if(event.importance == CALENDAR_IMPORTANCE_NONE)
         continue;
      MqlCalendarCountry country;
      if(!CalendarCountryById(event.country_id, country))
         continue;

      int n = ArraySize(newsCache);
      ArrayResize(newsCache, n + 1);
      newsCache[n].time       = values[i].time;
      newsCache[n].currency   = country.currency;
      newsCache[n].title      = event.name;
      newsCache[n].importance = (int)event.importance;
     }
  }

//+------------------------------------------------------------------+
//| True while inside the blocking window of a relevant news event   |
//+------------------------------------------------------------------+
bool IsNewsTime(string symbol)
  {
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
      return(false);
   string baseCur   = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   string profitCur = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
   datetime now = TimeCurrent();

   for(int i = 0; i < ArraySize(newsCache); i++)
     {
      if(InpNewsHighOnly && newsCache[i].importance != CALENDAR_IMPORTANCE_HIGH)
         continue;
      if(!InpNewsHighOnly && newsCache[i].importance < CALENDAR_IMPORTANCE_MODERATE)
         continue;
      if(newsCache[i].currency != baseCur && newsCache[i].currency != profitCur)
         continue;
      if(now >= newsCache[i].time - InpNewsMinutesBefore * 60 &&
         now <= newsCache[i].time + InpNewsMinutesAfter * 60)
         return(true);
     }
   return(false);
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

//+------------------------------------------------------------------+
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
//| Floating PnL / open lots of our positions (one symbol or all)    |
//+------------------------------------------------------------------+
double StrategyFloatingPnL(string symbol)
  {
   double total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(symbol != "" && PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      int dir, lvl;
      if(!ParseMagic(PositionGetInteger(POSITION_MAGIC), dir, lvl))
         continue;
      total += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return(total);
  }

//+------------------------------------------------------------------+
//| Next grid level trigger price and lot for the panel row          |
//+------------------------------------------------------------------+
bool GetNextLevelInfo(int symbolIndex, int direction, double &price, double &lots)
  {
   string symbol = symbolsArray[symbolIndex].symbolName;
   int count, maxLevel;
   double totalLots, avg, wavg, wavgAdj, lowest, highest;
   CollectGrid(symbol, direction, count, totalLots, avg, wavg, wavgAdj, maxLevel, lowest, highest);
   if(count == 0 || wavg < EPSILON)
      return(false);

   double pip = SymbolInfoDouble(symbol, SYMBOL_POINT) * GetPipMultiplier(symbol);
   for(int level = 1; level < g_maxTrades && level < 100; level++)
     {
      if(GridExists(symbol, level, direction))
         continue;
      double dist = InpGridDistancePips * level * pip;
      if(InpSmartDistance)
         dist *= symbolsArray[symbolIndex].smartDistMultiplier;
      price = (direction == DIR_BUY) ? wavg - dist : wavg + dist;
      lots  = CalculateLotSize(symbol, direction == DIR_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, level);
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| The panel: prop-firm risk header, account stats, news, symbols   |
//+------------------------------------------------------------------+
void UpdatePanel()
  {
   int f  = MathMax(7, InpPanelFontSize);
   int rh = (int)(f * 2.0);          // row height
   int x0 = 12, pad = 10;
   int w  = f * 46;                  // panel width scales with font
   int x  = x0 + pad;

   color colBg     = (color)0x1C140C;   // dark navy (BGR)
   color colBorder = (color)0x604828;
   color colHead   = (color)0x37B4DC;   // gold
   color colText   = (color)0xC8C8C8;   // silver
   color colDim    = (color)0x808080;
   color colOK     = (color)0x53C878;   // green
   color colWarn   = (color)0x2090F0;   // orange
   color colBad    = (color)0x4040E8;   // red

   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   // --- risk numbers -------------------------------------------------
   double dailyPnL = (dayStartAnchor > EPSILON) ? equity - dayStartAnchor : 0;
   double dailyPct = (dayStartAnchor > EPSILON) ? dailyPnL / dayStartAnchor * 100.0 : 0;
   double ddPct    = (initialBalance > EPSILON) ?
                     MathMax(0, (initialBalance - equity) / initialBalance * 100.0) : 0;
   double gainPct  = (initialBalance > EPSILON) ?
                     (equity - initialBalance) / initialBalance * 100.0 : 0;

   color dailyCol = colOK;
   if(g_dailyLossPct > EPSILON && dailyPct < 0)
     {
      double usage = -dailyPct / g_dailyLossPct;
      dailyCol = (usage >= 0.6) ? colBad : ((usage >= 0.3) ? colWarn : colText);
     }
   color ddCol = colOK;
   if(g_maxDDPct > EPSILON && ddPct > 0)
     {
      double usage = ddPct / g_maxDDPct;
      ddCol = (usage >= 0.6) ? colBad : ((usage >= 0.3) ? colWarn : colText);
     }

   // --- layout -------------------------------------------------------
   int newsRows = MathMin(6, ArraySize(newsCache));
   int symRows  = ArraySize(symbolsArray);
   int height   = pad + rh * (6 + 1 + MathMax(newsRows, 1) + 1 + symRows + 1) + pad;
   PanelRect("bg", x0, 20, w, height, colBg, colBorder);

   int y = 20 + pad;
   PanelText("firm", x, y, StringFormat("%s  $%.0fk", g_firmLabel, initialBalance / 1000.0),
             colHead, f + 3, true);
   string status;
   color  statusCol;
   if(stopUntilRestart)          { status = "STOPPED - MAX DD";    statusCol = colBad;  }
   else if(dailyLocked)          { status = "LOCKED - DAILY GUARD"; statusCol = colWarn; }
   else if(dailyProfitLocked)    { status = "PROFIT CAP REACHED";   statusCol = colWarn; }
   else if(ddTriggered || ddCooldownHours > 0)
                                 { status = "DD COOLDOWN";          statusCol = colWarn; }
   else                          { status = "LIVE TRADING";         statusCol = colOK;   }
   PanelText("status", x + w - pad - (int)(StringLen(status) * f * 0.62) - 10, y + 2,
             status, statusCol, f, true);
   y += rh + 4;

   PanelText("daily", x, y, StringFormat("Daily PnL : %+.2f (%+.2f%%)   limit %.1f%% (guard %.1f%%)",
             dailyPnL, dailyPct, g_dailyLossPct,
             MathMax(0.1, g_dailyLossPct - InpDailyLossBufferPct)), dailyCol, f);
   y += rh;
   PanelText("dd", x, y, StringFormat("Overall DD: %.2f%% / %.1f%%%s    target %+.2f%% / %.1f%%",
             ddPct, g_maxDDPct, (g_ddTrailing ? " TRL" : ""), gainPct, InpProfitTargetPct), ddCol, f);
   y += rh;
   PanelText("acct", x, y, StringFormat("Equity %.2f   Balance %.2f   Lev 1:%d",
             equity, balance, (int)AccountInfoInteger(ACCOUNT_LEVERAGE)), colText, f);
   y += rh;
   double totalLotsOpen = GetTotalLotsInGrid("", 0, 0);
   int gmtOff = (int)((TimeCurrent() - TimeGMT()) / 3600);
   PanelText("info", x, y, StringFormat("Float PnL %+.2f   Lots open %.2f   GMT %+d   %s",
             StrategyFloatingPnL(""), totalLotsOpen, gmtOff, InpTradeComment), colText, f);
   y += rh;
   PanelText("hours", x, y, StringFormat("Hours %02d:00-%02d:59   Spread cap %.1fp   News filter %s",
             InpStartHour, InpStopHour, InpMaxSpreadPips,
             InpNewsFilter ? (InpNewsHighOnly ? "HIGH" : "MED+") : "off"), colDim, f);
   y += rh;

   // --- news ----------------------------------------------------------
   PanelText("newshdr", x, y, "Time             Cur  Impact  Event", colHead, f, true);
   y += rh;
   if(newsRows == 0)
     {
      PanelText("news0", x, y, MQLInfoInteger(MQL_TESTER) ?
                "(calendar unavailable in tester)" : "(no upcoming events)", colDim, f);
      for(int i = 1; i < 6; i++)
         ObjectDelete(0, PANEL_PREFIX + "news" + (string)i);
      y += rh;
     }
   else
     {
      for(int i = 0; i < newsRows; i++)
        {
         string impact = (newsCache[i].importance == CALENDAR_IMPORTANCE_HIGH) ? "High" :
                         (newsCache[i].importance == CALENDAR_IMPORTANCE_MODERATE) ? "Med " : "Low ";
         color impCol  = (newsCache[i].importance == CALENDAR_IMPORTANCE_HIGH) ? colBad :
                         (newsCache[i].importance == CALENDAR_IMPORTANCE_MODERATE) ? colWarn : colDim;
         string title = newsCache[i].title;
         if(StringLen(title) > 28)
            title = StringSubstr(title, 0, 28);
         PanelText("news" + (string)i, x, y,
                   StringFormat("%s  %-4s %-6s %s",
                   TimeToString(newsCache[i].time, TIME_DATE | TIME_MINUTES),
                   newsCache[i].currency, impact, title), impCol, f);
         y += rh;
        }
      for(int i = newsRows; i < 6; i++)
         ObjectDelete(0, PANEL_PREFIX + "news" + (string)i);
     }

   // --- per-symbol table ----------------------------------------------
   PanelText("symhdr", x, y, "Pair      Grid   Next @ / Lot          PnL", colHead, f, true);
   y += rh;
   for(int i = 0; i < symRows; i++)
     {
      string sym = symbolsArray[i].symbolName;
      int buyLevels  = MaxGridLevel(sym, DIR_BUY) + 1;
      int sellLevels = MaxGridLevel(sym, DIR_SELL) + 1;
      string gridTxt = StringFormat("B%d/S%d", buyLevels, sellLevels);

      string nextTxt = "....../....";
      double np, nl;
      int dir = (buyLevels > 0) ? DIR_BUY : ((sellLevels > 0) ? DIR_SELL : 0);
      if(dir != 0 && GetNextLevelInfo(i, dir, np, nl))
         nextTxt = StringFormat("%s/%.2f", DoubleToString(np,
                   (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)), nl);
      else if(dir == 0)
         nextTxt = StringFormat("....../%.2f",
                   CalculateLotSize(sym, ORDER_TYPE_BUY, 0));

      double pnl = StrategyFloatingPnL(sym);
      color rowCol = (pnl > EPSILON) ? colOK : ((pnl < -EPSILON) ? colBad : colText);
      PanelText("sym" + (string)i, x, y,
                StringFormat("%-9s %-6s %-20s %+9.2f", sym, gridTxt, nextTxt, pnl), rowCol, f);
      y += rh;
     }

   ChartRedraw();
  }
//+------------------------------------------------------------------+
