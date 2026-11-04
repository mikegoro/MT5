//+------------------------------------------------------------------+
//|                                                      Tremor3.mq5 |
//|                                                Copyright 2024, Tremor |
//|                                              https://www.Tremor.com |
//+------------------------------------------------------------------+
#property copyright "Tremor"
#property link      "https://www.Tremor.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

CTrade         trade;
CPositionInfo  posinfo;
COrderInfo     ordinfo;

#include <Tremor3Panel.mqh>

CPropFirmPanel panel;
//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum enumHour{Inactive=0, _0100=1, _0200=2, _0300=3, _0400=4, _0500=5, _0600=6, _0700=7, _0800=8, _0900=9, _1000=10, _1100=11, _1200=12, _1300=13, _1400=14, _1500=15, _1600=16, _1700=17, _1800=18, _1900=19, _2000=20, _2100=21, _2200=22, _2300=23};

enum ENUM_LOT_TYPE {LOT_FIXED = 0, Pct_of_Balance = 1, Pct_of_Equity = 2, Pct_of_Free_Margin = 3};

enum ENUM_STRATEGY_MODE {Reversal = 0, Continuation = 1};
//+------------------------------------------------------------------+
//| EA Settings Inputs                                               |
//+------------------------------------------------------------------+
input group "======== EA Settings ========"

input ENUM_STRATEGY_MODE StrategyMode  = Reversal;       // Direction of Trade
input bool               Rearm         = true;           // 1 Trade per setup?
input ulong              InpMagic      = 298347;         // EA Identification number (Magic No)
input ENUM_TIMEFRAMES    Timeframe     = PERIOD_CURRENT; // Timeframe for Trading
input ENUM_TIMEFRAMES    HigherTimeframe = PERIOD_H1;    // Higher Timeframe
input enumHour           SHInput       = 7;              // Start Hour
input enumHour           EHInput       = 21;             // End Hour
input color              GradientEnd   = clrBlue;        // Color of the gradient

//+------------------------------------------------------------------+
//| Indicator Parameters                                             |
//+------------------------------------------------------------------+
input group "======== Indicator Parameters ========"

input int               BolPeriod     = 20;           // Bollinger Band Period
input double            BolStDev      = 2.0;          // Bollinger St. Deviation
input int               RSIPeriod     = 10;           // RSI Period
input int               RSIFilter     = 30;           // RSI Filter from Mean 50 (30 = 80/20)
input int               ATR_Period    = 1000;         // Period for ATR (higher = smoother)
input ENUM_APPLIED_PRICE AppliedPrice = PRICE_CLOSE;  // Applied Price for RSI and Bollinger

//+------------------------------------------------------------------+
//| HTF Confluence                                                   |
//+------------------------------------------------------------------+
input group "======== HTF Confluence ========"

input bool    UseHTFConfluence = true;  // Require price outside HTF Bollinger Band too
input int     HTF_BolPeriod    = 20;     // HTF Bollinger Band Period
input double  HTF_BolStDev     = 2.0;    // HTF Bollinger St. Deviation

//+------------------------------------------------------------------+
//| Spike Filter                                                     |
//+------------------------------------------------------------------+
input group "======== Spike Filter ========"

input bool    UseSpikeFilter      = false; // Enable spike filter
input double  SpikeATRMultiplier  = 0.5;   // Tick move threshold, x ATR100
input int     SpikePauseSeconds   = 10;    // Seconds to pause trading after spike

//+------------------------------------------------------------------+
//| Money Management                                                 |
//+------------------------------------------------------------------+
input group "======== Money Management ========"

input ENUM_LOT_TYPE LotType       = Pct_of_Balance; // Lotsize defined by
input double        FixedLots     = 0.01;           // Fixed lots (if LotType = 0)
input double        RiskPercent   = 2.0;            // Risk percentage (if LotType = 1, 2, 3)

//+------------------------------------------------------------------+
//| Trade Management                                                 |
//+------------------------------------------------------------------+
input group "======== Trade Management ========"

input double  ATR_Multiplier      = 1.0;  // Minimum Candlesize in ATR (x1000)
input double  SLATR               = 1.0;  // Initial Stoploss (x ATR1000)
input double  TrailSLATR          = 0.2;  // Trail Stop Distance (x ATR1000)
input double  OrderDistanceATR    = 0.2;  // Stop order distance from price (x ATR1000)
input int     MaxSpread           = 10;   // Max Spread allowed (10 points = 1 pip)
input int     InpSlippage         = 10;   // Slippage in points

//+------------------------------------------------------------------+
//| HTF Visual Settings                                              |
//+------------------------------------------------------------------+
input group "======== HTF Visual Settings ========"

input bool    ShowFibonacci     = false; // Show Fibonacci Levels on chart
input int     BarsN             = 50;    // Number of bars on each side (5=11-candle fractal)
input int     HTF_GapMultiplier = 40;    // Gap between current candle and HTF boxes/bands (x current TF)

//+------------------------------------------------------------------+
//| Propfirm Rules Settings                                          |
//+------------------------------------------------------------------+
input group "======== Propfirm Rules Settings ========"

input double    InitialBal        = 0;                  // Initial Balance (0 = Use Account Balance)
input double    PrfTarget         = 0;                  // Profit Target for Prop Challenge (0=disabled)
input datetime  StartofChallenge  = D'2024.10.01 00:00'; // Start day of the month (for challenge)
input int       ChallengeLength   = 30;                 // No of days for Challenge
input double    MaxDDDayInp       = 0;                  // Max Drawdown for day allowed (0=disabled)
input double    MaxDDWeekInp      = 0;                  // Max Drawdown for week allowed (0=disabled)
input double    MaxDDMonthInp     = 0;                  // Max Drawdown for 30-days allowed (0=disabled)
input double    MaxDDTotalInp     = 0;                  // Max Drawdown allowed (0=disabled)

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
int     handleBol, handleRSI, handleATR, handleBolHTF;
double  atrValue=0, HTF_BolUpper=0, HTF_BollLower=0;
double  InitialBalance=0, ProfitTarget=0, MaxDDDay=0, MaxDDWeek=0, MaxDDMonth=0, MaxDDTotal=0;

//--- Panel Related Variables ---
double BegofDayBalance, BegofWeekBalance, BegofMonthBalance;
double DD_1D_Pct=0, DD_7D_Pct=0, DD_30D_Pct=0, DD_AT_Pct=0, Prf_1D_Pct=0, Prf_7D_Pct=0, Prf_30D_Pct=0, Prf_AT_Pct=0;
double EqHigh_1D=0, EqHigh_7D=0, EqHigh_30D=0, EqHigh_AT=0;
string StartDayofChallenge;
MqlDateTime ChallengeStart;

bool    TradingEnabled = true;
string  TradingEnabledComm = "";

bool    signalBuyArmed  = true;
bool    signalSellArmed = true;

double  IndBuffer[];
double  BollLower = 0;
double  BolMain   = 0;
double  BollUpper = 0;
double  rsi       = 0;

double   PrevTickBid = 0;
datetime SpikePauseUntil = 0;

datetime PrvHighTime, PrvLowTime;
double   PrvHigh, PrvLow;
color    FiboColor = DarkGray;

//--- Visual Variables ---
color   GradientStart = clrBlack;
int     No_of_Gradient_Lines = 40;
string  SpreadIndName = "spread";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   TesterHideIndicators(true);
   trade.SetExpertMagicNumber(InpMagic);
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   trade.SetDeviationInPoints(InpSlippage);
   
   if(InitialBal==0){
      InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      Print("User has not defined an Initial Balance in Settings, using Account Balance Information");
   } else InitialBalance = InitialBal;
   
   if(PrfTarget==0){
      ProfitTarget = DBL_MAX;
      Print("User has not defined a Profit Target in Settings. Unlimited Target.");
   } else ProfitTarget = PrfTarget;
   
   if(MaxDDDayInp==0){
      MaxDDDay = DBL_MAX;
      Print("User has not defined a Daily Max Drawdown in Settings. Unlimited Drawdown allowed.");
   } else MaxDDDay = MaxDDDayInp;
   
   if(MaxDDWeekInp==0){
      MaxDDWeek = DBL_MAX;
      Print("User has not defined a Weekly Max Drawdown in Settings. Unlimited Drawdown allowed.");
   } else MaxDDWeek = MaxDDWeekInp;
   
   if(MaxDDMonthInp==0){
      MaxDDMonth = DBL_MAX;
      Print("User has not defined a Monthly Max Drawdown in Settings. Unlimited Drawdown allowed.");
   } else MaxDDMonth = MaxDDMonthInp;
   
   if(MaxDDTotalInp==0){
      MaxDDTotal = DBL_MAX;
      Print("User has not defined a Max Total Drawdown in Settings. Unlimited Drawdown allowed.");
   } else MaxDDTotal = MaxDDTotalInp;
   
   panel.OnInit();
   
   TimeToStruct(StartofChallenge, ChallengeStart);
   StartDayofChallenge = EnumToString((ENUM_DAY_OF_WEEK)ChallengeStart.day_of_week);
   
   BegofDayBalance   = AccountInfoDouble(ACCOUNT_BALANCE);
   BegofWeekBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
   BegofMonthBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   handleBol    = iBands(_Symbol, Timeframe, BolPeriod, 0, BolStDev, AppliedPrice);
   handleBolHTF = iBands(_Symbol, HigherTimeframe, HTF_BolPeriod, 0, HTF_BolStDev, AppliedPrice);
   handleRSI    = iRSI(_Symbol, Timeframe, RSIPeriod, AppliedPrice);
   handleATR    = iATR(_Symbol, Timeframe, ATR_Period);
   
   if(IsVisualTesterLiveChart()){
      UpdateVisuals();
      DrawPaddingRectangles();
   }
   
   CheckHigherTimeframeWarning();

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   panel.Destroy(reason);
   ObjectsDeleteAll(0);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   int TradeSignal = 0;
   
   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   CopyBuffer(handleBol, 0, 0, 1, IndBuffer);
   BolMain = IndBuffer[0];
   
   CopyBuffer(handleBol, 1, 0, 1, IndBuffer);
   BollUpper = IndBuffer[0];
   
   CopyBuffer(handleBol, 2, 0, 1, IndBuffer);
   BollLower = IndBuffer[0];
   
   CopyBuffer(handleRSI, 0, 0, 1, IndBuffer);
   rsi = IndBuffer[0];
   
   CopyBuffer(handleATR, 0, 0, 1, IndBuffer);
   atrValue = IndBuffer[0];
   
   CopyBuffer(handleBolHTF, 1, 0, 1, IndBuffer);
   HTF_BolUpper = IndBuffer[0];
   
   CopyBuffer(handleBolHTF, 2, 0, 1, IndBuffer);
   HTF_BollLower = IndBuffer[0];
   
   double CandleHigh  = iHigh(_Symbol, Timeframe, 0);
   double CandleLow   = iLow(_Symbol, Timeframe, 0);
   double CandleSize  = CandleHigh - CandleLow;
   
   if(CandleSize > atrValue * ATR_Multiplier){
      if(Bid < BollLower && rsi < 50 - RSIFilter && (!UseHTFConfluence || Bid < HTF_BollLower)) TradeSignal = -1;
      if(Ask > BollUpper && rsi > 50 + RSIFilter && (!UseHTFConfluence || Ask > HTF_BolUpper)) TradeSignal = 1;
   }
   
   int ordposTotal = OrdPosModify(Ask, Bid);
   
   if(UseSpikeFilter){
      if(PrevTickBid != 0 && MathAbs(Bid - PrevTickBid) > atrValue * SpikeATRMultiplier){
         SpikePauseUntil = TimeCurrent() + SpikePauseSeconds;
      }
      PrevTickBid = Bid;
      if(TimeCurrent() < SpikePauseUntil) return;
   }
   
   TradingEnabled = IsTradingAllowedPropValues();
   
   if(TradingEnabled && TradingEnabledComm != ""){
      Print("Trading is enabled again");
      TradingEnabledComm = "";
   }
   
   if(ordposTotal == 0 && TradeSignal != 0 && IsTradingTime() && TradingEnabled){
      SendOrder(TradeSignal, Ask, Bid, BolMain);
   }
   
   if(!TradingEnabled) CloseAllOrders();
   
   //--- Reversal lines (LTF + HTF) ---
   if(IsVisualTesterLiveChart()){
      datetime ltf_start = iTime(_Symbol, Period(), 5);
      datetime ltf_end   = iTime(_Symbol, Period(), 0) + PeriodSeconds() * 5;
      DrawReversallines("LTF", BollUpper, BollLower, ltf_start, ltf_end);
      
      datetime current_time = iTime(_Symbol, PERIOD_CURRENT, 0);
      int candle_width = PeriodSeconds(PERIOD_CURRENT) * 2;
      int spacing      = PeriodSeconds(PERIOD_CURRENT) * 1;
      int initial_gap  = PeriodSeconds(PERIOD_CURRENT) * HTF_GapMultiplier;
      datetime htf_start = current_time + initial_gap;
      datetime htf_end   = current_time + initial_gap + (candle_width + spacing) * 3;
      DrawReversallines("HTF", HTF_BolUpper, HTF_BollLower, htf_start, htf_end, true);
      
      UpdateSpreadIndicator();
   }
   
   if(!IsNewBar()) return;
   
   UpdateInitialBalances();
   UpdatePropfirmValues();
   
   //--- Rearm Logic ---
   bool buySignalStillTrue  = (Ask > BollUpper && rsi > 50 + RSIFilter && (!UseHTFConfluence || Ask > HTF_BolUpper));
   bool sellSignalStillTrue = (Bid < BollLower && rsi < 50 - RSIFilter && (!UseHTFConfluence || Bid < HTF_BollLower));
   
   if(Rearm){
      if(signalBuyArmed  && !buySignalStillTrue)  signalBuyArmed  = true;
      if(signalSellArmed && !sellSignalStillTrue) signalSellArmed = true;
   }
   
   if(IsVisualTesterLiveChart()){
      panel.Update();
      UpdateVisuals();
   }
  }
//+------------------------------------------------------------------+
//| Helper Functions                                                 |
//+------------------------------------------------------------------+
bool IsNewBar(){
   static datetime previousTime = 0;
   datetime currentTime = iTime(_Symbol, Timeframe, 0);
   if(previousTime != currentTime){
      previousTime = currentTime;
      return true;
   }
   return false;
}

bool IsBacktestOrVisual(){
   return ( (MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) || MQLInfoInteger(MQL_OPTIMIZATION) );
}

bool IsVisualTesterLiveChart(){
   return ( (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE)) && !MQLInfoInteger(MQL_OPTIMIZATION) );
}

//+------------------------------------------------------------------+
//| CheckHigherTimeframeWarning - Display warning if HTF <= LTF      |
//+------------------------------------------------------------------+
void CheckHigherTimeframeWarning(){
   if(HigherTimeframe <= Timeframe){
      long w = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      long h = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      
      ObjectCreate(0, "HTF_Warning", OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, "HTF_Warning", OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, "HTF_Warning", OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, "HTF_Warning", OBJPROP_XDISTANCE, (int)(w/2));
      ObjectSetInteger(0, "HTF_Warning", OBJPROP_YDISTANCE, (int)(h/2));
      ObjectSetString(0, "HTF_Warning", OBJPROP_TEXT, "HIGHER TIMEFRAME IS NOT HIGHER THAN CURRENT CHART");
      ObjectSetInteger(0, "HTF_Warning", OBJPROP_FONTSIZE, 15);
      ObjectSetString(0, "HTF_Warning", OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, "HTF_Warning", OBJPROP_COLOR, clrRed);
   } else {
      ObjectDelete(0, "HTF_Warning");
   }
}

//+------------------------------------------------------------------+
//| UpdateVisuals - Master function to refresh all visuals          |
//+------------------------------------------------------------------+
void UpdateVisuals(){
   if(IsVisualTesterLiveChart()){
      DrawHigherTimeframeData();
      PrvHigh = findHigh();
      PrvLow  = findLow();
      if(PrvHigh > 0 && PrvLow > 0 && ShowFibonacci) DrawFibonacciLevels();
   }
}

//+------------------------------------------------------------------+
//| findHigh / findLow / DrawFibonacciLevels (unchanged)             |
//+------------------------------------------------------------------+
double findHigh(){
   double highestHigh = 0;
   for(int i = 0; i < 200; i++){
      double high = iHigh(_Symbol, Timeframe, i);
      if(i > BarsN && iHighest(_Symbol, Timeframe, MODE_HIGH, BarsN*2+1, i-BarsN) == i){
         if(high > highestHigh){
            PrvHighTime = iTime(_Symbol, Timeframe, i);
            return high;
         }
      }
      highestHigh = MathMax(high, highestHigh);
   }
   return -1;
}

double findLow(){
   double lowestLow = DBL_MAX;
   for(int i = 0; i < 200; i++){
      double low = iLow(_Symbol, Timeframe, i);
      if(i > BarsN && iLowest(_Symbol, Timeframe, MODE_LOW, BarsN*2+1, i-BarsN) == i){
         if(low < lowestLow){
            PrvLowTime = iTime(_Symbol, Timeframe, i);
            return low;
         }
      }
      lowestLow = MathMin(low, lowestLow);
   }
   return -1;
}

void DrawFibonacciLevels(){
   datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   string fiboName = "FiboIn";
   if(ObjectFind(0, fiboName) < 0){
      ObjectCreate(0, fiboName, OBJ_FIBO, 0, PrvHighTime, PrvHigh, PrvLowTime, PrvLow);
      ObjectSetInteger(0, fiboName, OBJPROP_LEVELCOLOR, FiboColor);
      ObjectSetInteger(0, fiboName, OBJPROP_RAY_RIGHT, false);
   }
   if(PrvHighTime < PrvLowTime){
      ObjectMove(0, fiboName, 0, PrvHighTime, PrvHigh);
      ObjectMove(0, fiboName, 1, currentTime, PrvLow);
   } else {
      ObjectMove(0, fiboName, 0, PrvLowTime, PrvLow);
      ObjectMove(0, fiboName, 1, currentTime, PrvHigh);
   }
}

//+------------------------------------------------------------------+
//| CalculateGradientColor / DrawPaddingRectangles                   |
//+------------------------------------------------------------------+
int CalculateGradientColor(color ColorStart, color ColorEnd, int steps, int Step){
   int Start_B = (ColorStart>>16)&0xFF, Start_G = (ColorStart>>8)&0xFF, Start_R = ColorStart&0xFF;
   int End_B   = (ColorEnd>>16)&0xFF,   End_G   = (ColorEnd>>8)&0xFF,   End_R   = ColorEnd&0xFF;
   int R, G, B;
   if(Start_R > End_R) R = Start_R + (End_R - Start_R)/steps*Step;
   else R = Start_R + (End_R - Start_R)/steps*Step;
   if(Start_G > End_G) G = Start_G + (End_G - Start_G)/steps*Step;
   else G = Start_G + (End_G - Start_G)/steps*Step;
   if(Start_B > End_B) B = Start_B + (End_B - Start_B)/steps*Step;
   else B = Start_B + (End_B - Start_B)/steps*Step;
   return (B<<16)|(G<<8)|R;
}

void DrawPaddingRectangles(){
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;
   
   int totalWidth  = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int chartHeight = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int shiftSize   = (int)(totalWidth * ChartGetDouble(0, CHART_SHIFT_SIZE) / 100.0);
   
   int chartWidth = totalWidth - shiftSize;
   int lineHeight = chartHeight / No_of_Gradient_Lines + 1;
   
   for(int i = 1; i <= No_of_Gradient_Lines; i++){
      string objName = StringFormat("Padding_rect%d", i);
      if(ObjectFind(0, objName) == -1)
         ObjectCreate(0, objName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      color bandColor = (color)CalculateGradientColor(GradientStart, GradientEnd, No_of_Gradient_Lines, i);
      
      ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, 0);
      ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, (i - 1) * lineHeight);
      ObjectSetInteger(0, objName, OBJPROP_XSIZE, chartWidth);
      ObjectSetInteger(0, objName, OBJPROP_YSIZE, lineHeight + 1);
      ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, objName, OBJPROP_BACK, true);
      ObjectSetInteger(0, objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, bandColor);
      ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, bandColor);
      ObjectSetInteger(0, objName, OBJPROP_FILL, true);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| UpdateSpreadIndicator - Spread + RSI displayed on chart         |
//+------------------------------------------------------------------+
void UpdateSpreadIndicator(){
   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double SpreadPips = (Ask - Bid) / _Point;
   
   string text = "Spread " + IntegerToString(MaxSpread) + " => " + DoubleToString(SpreadPips, 0)
               + " | RSI " + IntegerToString((int)MathRound(rsi));
   
   double textPrice = Bid - (10 * _Point);
   
   if(ObjectFind(0, SpreadIndName) < 0){
      ObjectCreate(0, SpreadIndName, OBJ_TEXT, 0, 0, 0);
      ObjectSetInteger(0, SpreadIndName, OBJPROP_FONTSIZE, 10);
      ObjectSetString (0, SpreadIndName, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, SpreadIndName, OBJPROP_COLOR, clrWhite);
   }
   ObjectMove(0, SpreadIndName, 0, iTime(_Symbol, PERIOD_CURRENT, 0) + PeriodSeconds(PERIOD_CURRENT), textPrice);
   ObjectSetString(0, SpreadIndName, OBJPROP_TEXT, text);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| DrawReversallines / DrawHFTBar / DrawHigherTimeframeData (same)  |
//+------------------------------------------------------------------+
void DrawReversallines(string name, double upperLevel, double lowerLevel, datetime start, datetime end, bool labelOnRight = false){
   if(ObjectFind(0, name+"_Upper") < 0){
      ObjectCreate(0, name+"_Upper", OBJ_TREND, 0, start, upperLevel, end, upperLevel);
      ObjectSetInteger(0, name+"_Upper", OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, name+"_Upper", OBJPROP_WIDTH, 5);
      ObjectSetInteger(0, name+"_Upper", OBJPROP_RAY, false);
      ObjectSetInteger(0, name+"_Upper", OBJPROP_SELECTABLE, false);
   }
   ObjectMove(0, name+"_Upper", 0, start, upperLevel);
   ObjectMove(0, name+"_Upper", 1, end, upperLevel);
   
   if(ObjectFind(0, name+"_Lower") < 0){
      ObjectCreate(0, name+"_Lower", OBJ_TREND, 0, start, lowerLevel, end, lowerLevel);
      ObjectSetInteger(0, name+"_Lower", OBJPROP_COLOR, clrLawnGreen);
      ObjectSetInteger(0, name+"_Lower", OBJPROP_WIDTH, 5);
      ObjectSetInteger(0, name+"_Lower", OBJPROP_RAY, false);
      ObjectSetInteger(0, name+"_Lower", OBJPROP_SELECTABLE, false);
   }
   ObjectMove(0, name+"_Lower", 0, start, lowerLevel);
   ObjectMove(0, name+"_Lower", 1, end, lowerLevel);
   
   if(ObjectFind(0, name+"_UpperLabel") < 0){
      ObjectCreate(0, name+"_UpperLabel", OBJ_TEXT, 0, start, upperLevel);
      ObjectSetString(0, name+"_UpperLabel", OBJPROP_TEXT, name+" Upper");
      ObjectSetInteger(0, name+"_UpperLabel", OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, name+"_UpperLabel", OBJPROP_ANCHOR, labelOnRight ? ANCHOR_LEFT_LOWER : ANCHOR_RIGHT_LOWER);
      ObjectSetString(0, name+"_UpperLabel", OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, name+"_UpperLabel", OBJPROP_FONTSIZE, 10);
   }
   ObjectSetInteger(0, name+"_UpperLabel", OBJPROP_ANCHOR, labelOnRight ? ANCHOR_LEFT_LOWER : ANCHOR_RIGHT_LOWER);
   ObjectMove(0, name+"_UpperLabel", 0, labelOnRight ? end : start, upperLevel);
   
   if(ObjectFind(0, name+"_LowerLabel") < 0){
      ObjectCreate(0, name+"_LowerLabel", OBJ_TEXT, 0, start, lowerLevel);
      ObjectSetString(0, name+"_LowerLabel", OBJPROP_TEXT, name+" Lower");
      ObjectSetInteger(0, name+"_LowerLabel", OBJPROP_COLOR, clrLawnGreen);
      ObjectSetInteger(0, name+"_LowerLabel", OBJPROP_ANCHOR, labelOnRight ? ANCHOR_LEFT_UPPER : ANCHOR_RIGHT_UPPER);
      ObjectSetString(0, name+"_LowerLabel", OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, name+"_LowerLabel", OBJPROP_FONTSIZE, 10);
   }
   ObjectSetInteger(0, name+"_LowerLabel", OBJPROP_ANCHOR, labelOnRight ? ANCHOR_LEFT_UPPER : ANCHOR_RIGHT_UPPER);
   ObjectMove(0, name+"_LowerLabel", 0, labelOnRight ? end : start, lowerLevel);
}

void DrawHFTBar(string name, datetime start, datetime end, double close, double open, double low, double high, color clr){
   if(ObjectFind(0, "Body_"+name) < 0){
      ObjectCreate(0, "Body_"+name, OBJ_RECTANGLE, 0, start, close, end, open);
      ObjectSetInteger(0, "Body_"+name, OBJPROP_FILL, true);
   } else {
      ObjectSetInteger(0, "Body_"+name, OBJPROP_TIME, 0, start);
      ObjectSetDouble (0, "Body_"+name, OBJPROP_PRICE, 0, close);
      ObjectSetInteger(0, "Body_"+name, OBJPROP_TIME, 1, end);
      ObjectSetDouble (0, "Body_"+name, OBJPROP_PRICE, 1, open);
   }
   ObjectSetInteger(0, "Body_"+name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, "Body_"+name, OBJPROP_BACK, true);
   
   datetime mid_time = start + (end - start)/2;
   if(ObjectFind(0, "Wick_"+name) < 0){
      ObjectCreate(0, "Wick_"+name, OBJ_TREND, 0, mid_time, high, mid_time, low);
      ObjectSetInteger(0, "Wick_"+name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, "Wick_"+name, OBJPROP_RAY, false);
   } else {
      ObjectSetInteger(0, "Wick_"+name, OBJPROP_TIME, 0, mid_time);
      ObjectSetDouble (0, "Wick_"+name, OBJPROP_PRICE, 0, high);
      ObjectSetInteger(0, "Wick_"+name, OBJPROP_TIME, 1, mid_time);
      ObjectSetDouble (0, "Wick_"+name, OBJPROP_PRICE, 1, low);
   }
   ObjectSetInteger(0, "Wick_"+name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, "Wick_"+name, OBJPROP_BACK, true);
}

void DrawHigherTimeframeData(){
   if(Period() >= HigherTimeframe) return;
   
   double highs[3], lows[3], closes[3], opens[3];
   CopyHigh (_Symbol, HigherTimeframe, 0, 3, highs);
   CopyLow  (_Symbol, HigherTimeframe, 0, 3, lows);
   CopyClose(_Symbol, HigherTimeframe, 0, 3, closes);
   CopyOpen (_Symbol, HigherTimeframe, 0, 3, opens);
   
   datetime current_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   int candle_width = PeriodSeconds(PERIOD_CURRENT) * 2;
   int spacing      = PeriodSeconds(PERIOD_CURRENT) * 1;
   int initial_gap  = PeriodSeconds(PERIOD_CURRENT) * HTF_GapMultiplier;
   
   for(int i=0; i<3; i++){
      datetime box_start = current_time + initial_gap + (candle_width + spacing) * i;
      datetime box_end   = box_start + candle_width;
      color box_color    = (closes[i] > opens[i]) ? clrGreen : clrRed;
      DrawHFTBar("HTF_"+IntegerToString(i), box_start, box_end, closes[i], opens[i], lows[i], highs[i], box_color);
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| calcLots / IsTradingTime / CloseAllOrders (unchanged)            |
//+------------------------------------------------------------------+
double calcLots(double slDistance){
   double lots = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double AccountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double EquityBalance  = AccountInfoDouble(ACCOUNT_EQUITY);
   double FreeMargin     = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double risk = 0;
   
   switch(LotType){
      case 0: lots = FixedLots; return lots;
      case 1: risk = AccountBalance * RiskPercent / 100; break;
      case 2: risk = EquityBalance * RiskPercent / 100; break;
      case 3: risk = FreeMargin * RiskPercent / 100; break;
   }
   
   double ticksize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickvalue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotstep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   double moneyPerLotstep = (slDistance / ticksize) * tickvalue * lotstep;
   lots = MathFloor(risk / moneyPerLotstep) * lotstep;
   
   double minvolume    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxvolume    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volumelimit  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);
   
   if(volumelimit!=0) lots = MathMin(lots, volumelimit);
   if(maxvolume!=0)   lots = MathMin(lots, maxvolume);
   if(minvolume!=0)   lots = MathMax(lots, minvolume);
   
   return NormalizeDouble(lots, 2);
}

bool IsTradingTime(){
   MqlDateTime time;
   TimeToStruct(TimeCurrent(), time);
   int Hournow = time.hour;
   
   if(Hournow < SHInput){ CloseAllOrders(); return(false); }
   if(Hournow >= EHInput && EHInput != 0){ CloseAllOrders(); return(false); }
   
   return(true);
}

void CloseAllOrders(){
   for(int i = OrdersTotal()-1; i >= 0; i--){
      ordinfo.SelectByIndex(i);
      ulong ticket = ordinfo.Ticket();
      if(ordinfo.Symbol() == _Symbol && ordinfo.Magic() == InpMagic){
         trade.OrderDelete(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| SendOrder - Handles both Reversal and Continuation strategies    |
//+------------------------------------------------------------------+
void SendOrder(double TradeSignal, double Ask, double Bid, double BolMainParam){
   double entry = 0;
   double sl    = 0;
   
   double SLDistance = atrValue * SLATR;
   double LotSize    = calcLots(SLDistance);
   
   bool spreadOK = (Ask - Bid < MaxSpread * _Point);
   if(!spreadOK) return;
   
   if(StrategyMode == Reversal){
      if(TradeSignal < 0 && (signalSellArmed || !Rearm)){
         entry = Ask + (atrValue * OrderDistanceATR);
         sl    = entry - SLDistance;
         trade.BuyStop(LotSize, entry, _Symbol, sl, BolMainParam, ORDER_TIME_GTC, 0, "Tremor");
         signalSellArmed = false;
      }
      if(TradeSignal > 0 && (signalBuyArmed || !Rearm)){
         entry = Bid - (atrValue * OrderDistanceATR);
         sl    = entry + SLDistance;
         trade.SellStop(LotSize, entry, _Symbol, sl, BolMainParam, ORDER_TIME_GTC, 0, "Tremor");
         signalBuyArmed = false;
      }
   }
   else if(StrategyMode == Continuation){
      if(TradeSignal < 0 && (signalSellArmed || !Rearm)){
         sl = Bid + SLDistance;
         trade.Sell(LotSize, _Symbol, Bid, sl, 0, "Tremor");
         signalSellArmed = false;
      }
      if(TradeSignal > 0 && (signalBuyArmed || !Rearm)){
         sl = Ask - SLDistance;
         trade.Buy(LotSize, _Symbol, Ask, sl, 0, "Tremor");
         signalBuyArmed = false;
      }
   }
}

//+------------------------------------------------------------------+
//| OrdPosModify (unchanged)                                         |
//+------------------------------------------------------------------+
int OrdPosModify(double Ask, double Bid){
   double currSL=0, newSL=0, currOrdPrice=0, entry=0;
   int ordposTotal = 0;
   
   double TrailDist    = atrValue * TrailSLATR;
   double minStopDist  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(TrailDist < minStopDist) TrailDist = minStopDist;
   
   double OrderDist  = atrValue * OrderDistanceATR;
   double SLDist     = atrValue * SLATR;
   
   for(int i=PositionsTotal()-1; i>=0; i--){
      posinfo.SelectByIndex(i);
      if(posinfo.Symbol()==_Symbol && posinfo.Magic()==InpMagic){
         ulong ticket     = posinfo.Ticket();
         double openprice = posinfo.PriceOpen();
         ordposTotal++;
         
         if(posinfo.PositionType()==POSITION_TYPE_BUY){
            currSL = posinfo.StopLoss();
            newSL  = Bid - TrailDist;
            if(newSL > currSL && newSL > openprice)
               trade.PositionModify(ticket,newSL,posinfo.TakeProfit());
         }
         if(posinfo.PositionType()==POSITION_TYPE_SELL){
            currSL = posinfo.StopLoss();
            newSL  = Ask + TrailDist;
            if(newSL < currSL && newSL < openprice)
               trade.PositionModify(ticket,newSL,posinfo.TakeProfit());
         }
      }
   }
   
   for(int j=OrdersTotal()-1; j>=0; j--){
      ordinfo.SelectByIndex(j);
      if(ordinfo.Symbol()==_Symbol && ordinfo.Magic()==InpMagic){
         ulong ticket = ordinfo.Ticket();
         ordposTotal++;
         
         if(ordinfo.OrderType()==ORDER_TYPE_BUY_STOP){
            currOrdPrice = ordinfo.PriceOpen();
            entry = Ask + OrderDist;
            if(entry < currOrdPrice){
               newSL = entry - SLDist;
               trade.OrderModify(ticket,entry,newSL,ordinfo.TakeProfit(),ORDER_TIME_GTC,0,0);
            }
         }
         if(ordinfo.OrderType()==ORDER_TYPE_SELL_STOP){
            currOrdPrice = ordinfo.PriceOpen();
            entry = Bid - OrderDist;
            if(entry > currOrdPrice){
               newSL = entry + SLDist;
               trade.OrderModify(ticket,entry,newSL,ordinfo.TakeProfit(),ORDER_TIME_GTC,0,0);
            }
         }
      }
   }
   
   return(ordposTotal);
}

//+------------------------------------------------------------------+
//| Panel Related Functions                                          |
//+------------------------------------------------------------------+
void UpdateInitialBalances(){
   static MqlDateTime prevcheck;
   MqlDateTime now;
   TimeCurrent(now);
   
   if(now.day != prevcheck.day){
      BegofDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      EqHigh_1D = BegofDayBalance;
      DD_1D_Pct = 0;
      Prf_1D_Pct = 0;
      prevcheck = now;
   }
   
   static datetime _7dayperiod = StartofChallenge;
   if(TimeCurrent() > _7dayperiod){
      BegofWeekBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      EqHigh_7D = BegofWeekBalance;
      DD_7D_Pct = 0;
      Prf_7D_Pct = 0;
      _7dayperiod += PeriodSeconds(PERIOD_D1) * 7;
   }
   
   static datetime _30dayperiod = StartofChallenge;
   if(TimeCurrent() > _30dayperiod){
      BegofMonthBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      EqHigh_30D = BegofMonthBalance;
      DD_30D_Pct = 0;
      Prf_30D_Pct = 0;
      _30dayperiod += PeriodSeconds(PERIOD_D1) * 30;
   }
}

void UpdatePropfirmValues(){
   double Equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   if(BegofDayBalance != 0){
      Prf_1D_Pct = (Equity - BegofDayBalance) * 100 / BegofDayBalance;
      if(Equity > EqHigh_1D) EqHigh_1D = Equity;
      double dd = (Equity - EqHigh_1D) * 100 / EqHigh_1D;
      if(dd < DD_1D_Pct) DD_1D_Pct = dd;
   }
   if(BegofWeekBalance != 0){
      Prf_7D_Pct = (Equity - BegofWeekBalance) * 100 / BegofWeekBalance;
      if(Equity > EqHigh_7D) EqHigh_7D = Equity;
      double dd = (Equity - EqHigh_7D) * 100 / EqHigh_7D;
      if(dd < DD_7D_Pct) DD_7D_Pct = dd;
   }
   if(BegofMonthBalance != 0){
      Prf_30D_Pct = (Equity - BegofMonthBalance) * 100 / BegofMonthBalance;
      if(Equity > EqHigh_30D) EqHigh_30D = Equity;
      double dd = (Equity - EqHigh_30D) * 100 / EqHigh_30D;
      if(dd < DD_30D_Pct) DD_30D_Pct = dd;
   }
   if(InitialBalance != 0){
      Prf_AT_Pct = (Equity - InitialBalance) * 100 / InitialBalance;
      if(Equity > EqHigh_AT) EqHigh_AT = Equity;
      double dd = (Equity - EqHigh_AT) * 100 / EqHigh_AT;
      if(dd < DD_AT_Pct) DD_AT_Pct = dd;
   }
}

bool IsTradingAllowedPropValues(){
   if(DD_1D_Pct < -MaxDDDay){
      if(TradingEnabledComm != "Printed"){
         TradingEnabledComm = "Trading Disabled: Max Drawdown for Day Exceeded";
         Print(TradingEnabledComm);
         TradingEnabledComm = "Printed";
      }
      return false;
   }
   if(DD_7D_Pct < -MaxDDWeek){
      if(TradingEnabledComm != "Printed"){
         TradingEnabledComm = "Trading Disabled: Max Drawdown for Week Exceeded";
         Print(TradingEnabledComm);
         TradingEnabledComm = "Printed";
      }
      return false;
   }
   if(DD_30D_Pct < -MaxDDMonth){
      if(TradingEnabledComm != "Printed"){
         TradingEnabledComm = "Trading Disabled: Max Drawdown for Month Exceeded";
         Print(TradingEnabledComm);
         TradingEnabledComm = "Printed";
      }
      return false;
   }
   if(DD_AT_Pct < -MaxDDTotal){
      if(TradingEnabledComm != "Printed"){
         TradingEnabledComm = "Trading Disabled: Max Drawdown for All Time Exceeded";
         Print(TradingEnabledComm);
         TradingEnabledComm = "Printed";
      }
      return false;
   }
   if(Prf_AT_Pct > ProfitTarget){
      if(TradingEnabledComm != "Printed"){
         TradingEnabledComm = "Hoorayyyyy!!!!! Target Achieved";
         Print(TradingEnabledComm);
         TradingEnabledComm = "Printed";
      }
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| OnChartEvent                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam){
   panel.ChartEvent(id, lparam, dparam, sparam);
   
   static datetime lastRedrawTime = 0;
   if (id == CHARTEVENT_CHART_CHANGE && TimeCurrent() > lastRedrawTime + 0.3){
      lastRedrawTime = TimeCurrent();
      ChartSetInteger(0, CHART_SHIFT, true);
      DrawPaddingRectangles();
   }
}
//+------------------------------------------------------------------+