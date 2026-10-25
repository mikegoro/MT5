//+------------------------------------------------------------------+
//|                                                      Scaling Robot |
//|                                    Copyright 2024, MetaQuotes Ltd. |
//|                                       https://www.mql5.com         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>
#include <PropFirmPanel.mqh>

CTrade         trade;
CPositionInfo  posinfo;
COrderInfo     ord;
CPropFirmPanel panel;
//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum SystemType{Forex=0, BitCoin=1, _Gold=2, US_Indices=3};
enum enumSystemType{Fixed_pips_profile=0, Pct_of_Price_Profile=1};
enum Hours{Inactive=0, _0100=1, _0200=2, _0300=3, _0400=4, _0500=5, _0600=6, _0700=7, _0800=8, _0900=9, _1000=10, _1100=11, _1200=12, _1300=13, _1400=14, _1500=15, _1600=16, _1700=17, _1800=18, _1900=19, _2000=20, _2100=21, _2200=22, _2300=23};
enum LotSizeType{Fixed_Lots=0, Pct_of_Balance=1, Pct_of_Equity=2, Pct_of_Free_Margin=3};
enum TSLType{Default_Trail=0, Previous_Candle=1, Fast_MA=2, Tenkansen=3};
//+------------------------------------------------------------------+
//| Prop Firm Variables                                              |
//+------------------------------------------------------------------+
double   BegofDayBalance, BegofWeekBalance, BegofMonthBalance;
double   DD_1D_Pct=0, DD_7D_Pct=0, DD_30D_Pct=0, DD_AT_Pct=0;
double   Prf_1D_Pct=0, Prf_7D_Pct=0, Prf_30D_Pct=0, Prf_AT_Pct=0;
double   EqHigh_1D=0, EqHigh_7D=0, EqHigh_30D=0, EqHigh_AT;
string   StartDayofChallenge;
MqlDateTime ChallengeStart;

int      handleRSI, handleMovAvg, handleTrailMA, handleIchimoku;
//+------------------------------------------------------------------+
//| Input variables                                                  |
//+------------------------------------------------------------------+
input group "=== Trading Profiles ==="

input enumSystemType SType=0; //Trading System applied (Forex, Indices or Crypto)
int SysChoice;

input group "=== Common Trading Inputs ==="

input LotSizeType LotType   = Pct_of_Balance; // Type of Lotsize (Fixed or % Risk)
input double   FixedLots    = 0.01;           // Fixed Lots (if selected)
input double   RiskPercent  = 2;              //Risk in % on each trade
input ENUM_TIMEFRAMES Timeframe = PERIOD_M5;  //Time frame to run
input int      InpMagic     = 298347;         //EA identification no
input string   TradeComment = "No Shenanigans"; //Trade Comments

input Hours SHInput = _0700;   // Start Hour
input Hours EHInput = _2100;   // End Hour

int SHChoice;
int EHChoice;

input int    BarsN           = 100;  //No of Bars to identify high/low
input int    ExpirationBars  = 100;  //No of Bars before order is expired

input color  ChartColorTradingOff = clrPurple; // Chart color when EA is Inactive
input color  ChartColorTradingOn  = clrBlack;  // Chart color when EA is active
bool         TradingEnabled       = true;
input bool   HideIndicators       = true;      // Hide Indicators on Chart?
string       TradingEnabledComm   = "";

input group "=== Forex Trading Inputs ==="

input int    TPointsInput    = 200; // Take Profit (10 points = 1 pip)
input int    SLPointsInput    = 200; // Stoploss Points (10 points = 1 pip)
input int    TSLTriggerPointsInput = 15; // Points in profit before Trailing SL is activated (10 points = 1 pip)
input int    TSLPointsInput    = 10; // Trailing Stop Loss (10 points = 1 pip)
input double OrderDistPointsInput = 100; // Minimum order distance (10 points = 1 pip)

double       TPoints, SLPoints, TSLTriggerPoints, TSLPoints, OrderDistPoints;

input group "=== % as % of Price Profile Inputs ==="

input double TPasPct          = 0.4;  // TP as % of Price
input double SLasPct          = 0.4;  // SL as % of Price
input double TSLasPctofSL     = 5;    // Trail SL as % of SL
input double TSLTgrasPctofSL  = 7;    // Trigger of Trail SL as % of SL
input double OrdDisPtasPctofSL= 50;   // Minimum order distance as % of SL

input group "=== Trailing Stop Management ==="

input TSLType TrailType   = 0;   // Type of Trailing Stoploss
input int     PrvCandleN  = 1;   // No of candles to trail SL (if selected)
input int     FMAperiod   = 5;   // Fast-moving avg period to trail on (if selected)

input group "=== News Filter ==="

input bool      NewsFilterOn   = true;   //Filter for News?
enum sep_dropdown{comma=0,semicolon=1};
input sep_dropdown separator   = 0;      //Separator to separate news keywords
input string    KeyNews        = "BCB,NFP,JOLTS,Nonfarm,PMI,Retail,GDP,Confidence,Interest Rate"; //Keywords to avoid
input string    NewsCurrencies = "USD,GBP,EUR,JPY"; //Currencies for News LookUp
input int       DaysNewsLookup = 100;    // No of Days to look up news
input int       StopBeforeMin  = 15;     // Stop Trading before (in minutes)
input int       StartTradingMin= 15;     // Start Trading after (in minutes)
bool            TrDisabledNews = false;  // variable to store if trading disabled due to news

ushort          sep_code;
string          Newstoavoid[];
datetime        LastNewsAvoided;

input group "=== RSI Filter ==="

input bool              RSIFilterOn   = false;           // Filter for RSI extremes?
input ENUM_TIMEFRAMES   RSITimeframe  = PERIOD_H1;       // Timeframe for RSI filter
input int               RSIlowerlvl   = 20;              // RSI Lower level to filter
input int               RSIUpperlvl   = 80;              // RSI Upper level to filter
input int               RSI_MA        = 14;              // RSI Period
input ENUM_APPLIED_PRICE RSI_AppPrice = PRICE_MEDIAN;    // RSI Applied Price

input group "=== Moving Average Filter ==="

input bool              MAFilterOn    = false;           // Filter for Moving Average extremes?
input ENUM_TIMEFRAMES   MATimeframe   = PERIOD_H4;       // Timeframe for Moving Average Filter
input double            PctPricefromMA= 3;               // % Price is away from Mov Avg to be extreme
input int               MA_Period     = 200;             // Moving Average Period
input ENUM_MA_METHOD    MA_Mode       = MODE_EMA;        // Moving Average Mode/Method
input ENUM_APPLIED_PRICE MA_AppPrice  = PRICE_MEDIAN;    // Moving Avg Applied Price

input group "=== Trading Allowed by Days ==="

input bool   AllowedMonday    = true;   // Trading Allowed on Monday?
input bool   AllowedTuesday   = true;   // Trading Allowed on Tuesday?
input bool   AllowedWednesday = true;   // Trading Allowed on Wednesday?
input bool   AllowedThursday  = true;   // Trading Allowed on Thursday?
input bool   AllowedFriday    = true;   // Trading Allowed on Friday?
input bool   AllowedSaturday  = true;   // Trading Allowed on Saturday?
input bool   AllowedSunday    = true;   // Trading Allowed on Sunday?
bool         DayFilterOn      = true;

input group "=== Propfirm Rules Settings ==="

input int      InitialBalance   = 1000;               // Initial Balance
input double   ProfitTarget     = 10;                 // Profit Target for Prop Challenge
input datetime StartofChallenge = D'2024.10.01 00:00'; // Start day of the month (for challenge)
input int      ChallengeLength  = 30;                 // No of days for Challenge
input double   MaxDDPDay        = 3;                  // Max Drawdown for day allowed
input double   MaxDDWeek        = 6;                  // Max Drawdown for week allowed
input double   MaxDDMonth       = 6;                  // Max Drawdown for 30-days allowed
input double   MaxDDTotal       = 8;                  // Max Drawdown for entire challenge allowed
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit(){
    trade.SetExpertMagicNumber(InpMagic);
    panel.OnInit();

    TimeToStruct(StartofChallenge, ChallengeStart);
    StartDayofChallenge = EnumToString((ENUM_DAY_OF_WEEK)ChallengeStart.day_of_week);

    BegofDayBalance   = AccountInfoDouble(ACCOUNT_BALANCE);
    BegofWeekBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
    BegofMonthBalance = AccountInfoDouble(ACCOUNT_BALANCE);

    ChartSetInteger(0,CHART_SHOW_GRID,false);

    SHChoice = SHInput;
    EHChoice = EHInput;

    double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
    
    switch(SType){
       case 0:
          TPoints = TPointsInput;
          SLPoints = SLPointsInput;
          TSLTriggerPoints = TSLTriggerPointsInput;
          TSLPoints = TSLPointsInput;
          OrderDistPoints = OrderDistPointsInput;
          break;
       case 1:
          TPoints = ask * TPasPct/100/_Point;
          SLPoints = ask * SLasPct/100/_Point;
          OrderDistPoints = SLPoints * OrdDisPtasPctofSL/100;
          TSLPoints = SLPoints * TSLasPctofSL/100;
          TSLTriggerPoints = SLPoints * TSLTgrasPctofSL/100;
          break;
    }

    int stoplevel = (int) SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    Print("Minimum Stoploss Distance Required by Broker on ", _Symbol, ": ", stoplevel, " points.");
    
    if(TSLPoints < stoplevel){
       Print("Trailing Stoploss value of ", (int)TSLPoints, " is smaller than allowed by broker.");
       Print("Overriding to Broker Minimum of ", stoplevel, " points.");
       TSLPoints = stoplevel;
    } else {
       Print("Current Trailing Stop value of ", (int)TSLPoints, " is OK.");
    }
    
    TesterHideIndicators(false);
    if(HideIndicators==true) TesterHideIndicators(true);

    handleRSI = iRSI(_Symbol,RSITimeframe,RSI_MA,RSI_AppPrice);
    handleMovAvg = iMA(_Symbol,MATimeframe,MA_Period,0,MA_Mode,MA_AppPrice);
    if(TrailType==2) handleTrailMA = iMA(_Symbol,Timeframe,FMAperiod,0,MA_Mode,MA_AppPrice);
    if(TrailType==3) handleIchimoku = iIchimoku(_Symbol,Timeframe,9,26,52);

    return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
    panel.Destroy(reason);
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick(){
    TrailStop();

    if(!IsNewBar()) return;

    UpdateInitialBalances();
    UpdatePropfirmValues();
    panel.Update();
    IsTradingAllowedPropValues();

    if( IsRSIFilter() || IsUpcomingNews() || IsMAFilter() || !IsTradingAllowedbyDay() || !IsTradingAllowedPropValues() ){
        CloseAllOrders();
        TradingEnabled=false;
        ChartSetInteger(0,CHART_COLOR_BACKGROUND,ChartColorTradingOff);
        if(TradingEnabledComm!="Printed")
            Print(_Symbol, ": ", TradingEnabledComm);
        TradingEnabledComm="Printed";
        return;
    }

    TradingEnabled=true;
    if(TradingEnabledComm!=""){
        Print("Trading is enabled again");
        TradingEnabledComm = "";
    }

    ChartSetInteger(0,CHART_COLOR_BACKGROUND,ChartColorTradingOn);

    MqlDateTime time;
    TimeToStruct(TimeCurrent(),time);
    int Hournow = time.hour;

    if(Hournow < SHChoice){CloseAllOrders(); return;}
    if(Hournow >= EHChoice && EHChoice != 0){CloseAllOrders(); return;}

    int BuyTotal = 0;
    int SellTotal = 0;

    for (int i = OrdersTotal()-1; i >= 0; i--) {
        ord.SelectByIndex(i);
        if(ord.OrderType() == ORDER_TYPE_BUY_STOP && ord.Symbol() == _Symbol && ord.Magic() == InpMagic) BuyTotal++;
        if(ord.OrderType() == ORDER_TYPE_SELL_STOP && ord.Symbol() == _Symbol && ord.Magic() == InpMagic) SellTotal++;
    }

    for (int i = PositionsTotal()-1; i >= 0; i--) {
        posinfo.SelectByIndex(i);
        if(posinfo.PositionType() == POSITION_TYPE_BUY && posinfo.Symbol() == _Symbol && posinfo.Magic() == InpMagic) BuyTotal++;
        if(posinfo.PositionType() == POSITION_TYPE_SELL && posinfo.Symbol() == _Symbol && posinfo.Magic() == InpMagic) SellTotal++;
    }

    if(BuyTotal <= 0){
        double high = findHigh();
        if(high > 0){
            executeBuy(high);
        }
    }

    if(SellTotal <= 0){
        double low = findLow();
        if(low > 0){
            executeSell(low);
        }
    }
}
//+------------------------------------------------------------------+
//| IsNewBar function                                                |
//+------------------------------------------------------------------+
bool IsNewBar(){
    static datetime previousTime = 0;
    datetime currentTime = iTime(_Symbol, Timeframe, 0);
    if(previousTime!=currentTime){
    previousTime=currentTime;
    return true;
    }
    return false;
}
//+------------------------------------------------------------------+
//| findHigh function                                                |
//+------------------------------------------------------------------+
double findHigh() {
    double highestHigh = 0;

    for(int i = 0; i < 200; i++) {
    double high = iHigh(_Symbol,Timeframe,i);
    if(i > BarsN && iHighest(_Symbol,Timeframe,MODE_HIGH,BarsN*2+1,i-BarsN) == i){
    if(high > highestHigh){
    return high;
    }
    }

    highestHigh = MathMax(high,highestHigh);
    }

    return -1;
}
//+------------------------------------------------------------------+
//| findLow function                                                 |
//+------------------------------------------------------------------+
double findLow() {
    double lowestLow = DBL_MAX;
    for(int i = 0; i < 200; i++) {
    double low = iLow(_Symbol,Timeframe,i);
    if(i > BarsN && iLowest(_Symbol,Timeframe,MODE_LOW,BarsN*2+1,i-BarsN) == i){
    if(low < lowestLow){
    return low;
    }
    }

    lowestLow = MathMin(low,lowestLow);
    }

    return -1;
}
//+------------------------------------------------------------------+
//| calcLots function                                                |
//+------------------------------------------------------------------+
double calcLots(double slPoints){
    double lots = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
    
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
    
    double ticksize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickvalue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    double moneyPerLotstep = slPoints / ticksize * tickvalue * lotstep;
    lots = MathFloor(risk / moneyPerLotstep) * lotstep;
    
    double minvolume=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
    double maxvolume=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX);
    double volumelimit = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_LIMIT);

    if(volumelimit!=0) lots = MathMin(lots,volumelimit);
    if(maxvolume!=0) lots = MathMin(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX));
    if(minvolume!=0) lots = MathMax(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN));
    lots = NormalizeDouble(lots,2);

    return lots;
}
//+------------------------------------------------------------------+
//| executeBuy function                                              |
//+------------------------------------------------------------------+
void executeBuy(double entry){
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    if(ask > entry - OrderDistPoints * _Point) return;

    double tp = entry + TPoints * _Point;
    double sl = entry - SLPoints * _Point;

    double lots = 0.01;
    if(RiskPercent > 0) lots = calcLots(entry - sl);

    datetime expiration = iTime(_Symbol, Timeframe, 0) + ExpirationBars * PeriodSeconds(Timeframe);

    trade.BuyStop(lots,entry,_Symbol,sl,tp,ORDER_TIME_SPECIFIED,expiration);
}
//+------------------------------------------------------------------+
//| executeSell function                                             |
//+------------------------------------------------------------------+
void executeSell(double entry){
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(bid < entry + OrderDistPoints * _Point) return;

    double tp = entry - TPoints * _Point;
    double sl = entry + SLPoints * _Point;

    double lots = 0.01;
    if(RiskPercent > 0) lots = calcLots(sl - entry);

    datetime expiration = iTime(_Symbol, Timeframe, 0) + ExpirationBars * PeriodSeconds(Timeframe);

    trade.SellStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration);
}
//+------------------------------------------------------------------+
//| CloseAllOrders function                                          |
//+------------------------------------------------------------------+
void CloseAllOrders(){
    for(int i=OrdersTotal()-1;i>=0;i--){
    ord.SelectByIndex(i);
    ulong ticket = ord.Ticket();
    if(ord.Symbol()==_Symbol && ord.Magic()==InpMagic){
    trade.OrderDelete(ticket);
    }
    }
}
//+------------------------------------------------------------------+
//| TrailStop function                                               |
//+------------------------------------------------------------------+
void TrailStop(){
    double sl = 0;
    double tp = 0;
    double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
    int stoplevel = (int) SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
    double indbuffer[];
    
    for (int i=PositionsTotal()-1; i>=0; i--){
        if(posinfo.SelectByIndex(i)){
            ulong ticket = posinfo.Ticket();
            if(posinfo.Magic()==InpMagic && posinfo.Symbol()==_Symbol){
                //--- BUY POSITIONS ---
                if(posinfo.PositionType()==POSITION_TYPE_BUY){
                    if(bid-posinfo.PriceOpen()>TSLTriggerPoints*_Point){
                        tp = posinfo.TakeProfit();
                        // First move: SL is still below open price (move to break-even)
                        if(posinfo.StopLoss()<posinfo.PriceOpen()){
                            sl = bid - (TSLPoints * _Point);
                            if(sl > posinfo.StopLoss() && sl!=0){
                                trade.PositionModify(ticket,sl,tp);
                            }
                        }
                        // Subsequent moves: switch on the selected trailing type
                        switch(TrailType){
                            case 0:
                                sl = bid - (TSLPoints * _Point);
                                break;
                            case 1:
                                sl = iLow(_Symbol,Timeframe,PrvCandleN);
                                break;
                            case 2:
                                CopyBuffer(handleTrailMA,MAIN_LINE,1,1,indbuffer);
                                ArraySetAsSeries(indbuffer,true);
                                sl = NormalizeDouble(indbuffer[0],_Digits);
                                break;
                            case 3:
                                CopyBuffer(handleIchimoku,TENKANSEN_LINE,1,1,indbuffer);
                                ArraySetAsSeries(indbuffer,true);
                                sl = NormalizeDouble(indbuffer[0],_Digits);
                                break;
                        }
                        if(sl > posinfo.StopLoss() && sl!=0 && sl > posinfo.PriceOpen() && sl < bid){
                            trade.PositionModify(ticket,sl,tp);
                        }
                    }
                }
                //--- SELL POSITIONS ---
                else if(posinfo.PositionType()==POSITION_TYPE_SELL){
                    if(ask+(TSLTriggerPoints*_Point)<posinfo.PriceOpen()){
                        tp = posinfo.TakeProfit();
                        // First move: SL is still above open price (move to break-even)
                        if(posinfo.StopLoss()>posinfo.PriceOpen()){
                            sl = ask + (TSLPoints * _Point);
                            trade.PositionModify(ticket,sl,tp);
                        }
                        // Subsequent moves: switch on the selected trailing type
                        switch(TrailType){
                            case 0:
                                sl = ask + (TSLPoints * _Point);
                                break;
                            case 1:
                                sl = iHigh(_Symbol,Timeframe,PrvCandleN);
                                break;
                            case 2:
                                CopyBuffer(handleTrailMA,MAIN_LINE,1,1,indbuffer);
                                ArraySetAsSeries(indbuffer,true);
                                sl = NormalizeDouble(indbuffer[0],_Digits);
                                break;
                            case 3:
                                CopyBuffer(handleIchimoku,TENKANSEN_LINE,1,1,indbuffer);
                                ArraySetAsSeries(indbuffer,true);
                                sl = NormalizeDouble(indbuffer[0],_Digits);
                                break;
                        }
                        if(sl < posinfo.StopLoss() && sl!=0 && sl < posinfo.PriceOpen() && sl > ask){
                            trade.PositionModify(ticket,sl,tp);
                        }
                    }
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
//| IsUpcomingNews function                                          |
//+------------------------------------------------------------------+
bool IsUpcomingNews(){
   if(NewsFilterOn==false) return(false);

   if(TrDisabledNews && TimeCurrent()-LastNewsAvoided < StartTradingMin*PeriodSeconds(PERIOD_M1)) return true;

   TrDisabledNews=false;

   string sep;
   switch(separator){
      case 0: sep = ","; break;
      case 1: sep = ";";
   }

   sep_code = StringGetCharacter(sep,0);

   int k = StringSplit(KeyNews,sep_code,Newstoavoid);

   MqlCalendarValue values[];
   datetime starttime = TimeCurrent(); //iTime(_Symbol,PERIOD_D1,0);
   datetime endtime   = starttime + PeriodSeconds(PERIOD_D1)*DaysNewsLookup;

   CalendarValueHistory(values,starttime,endtime,NULL,NULL);

   for(int i = 0; i < ArraySize(values); i++){
      MqlCalendarEvent event;
      CalendarEventById(values[i].event_id, event);
      MqlCalendarCountry country;
      CalendarCountryById(event.country_id,country);

      if(StringFind(NewsCurrencies,country.currency) < 0) continue;

      for(int j=0; j<k; j++){
         string currentevent = Newstoavoid[j];
         string currentnews = event.name;
         if(StringFind(currentnews,currentevent) < 0) continue;

         Comment("Next News: ", country.currency, ": ", event.name, " -> ", values[i].time);
         if(values[i].time - TimeCurrent() < StopBeforeMin*PeriodSeconds(PERIOD_M1)){
            LastNewsAvoided = values[i].time;
            TrDisabledNews = true;
            if(TradingEnabledComm=="" || TradingEnabledComm!="Printed"){
               TradingEnabledComm = "Trading is disabled due to upcoming news: " + event.name;
            }
            return true;
         }
         return false;
      }
   }

   return false;
}
//+------------------------------------------------------------------+
//| IsRSIFilter function                                             |
//+------------------------------------------------------------------+
bool IsRSIFilter(){
   if(RSIFilterOn==false) return(false);

   double RSI[];
   CopyBuffer(handleRSI,MAIN_LINE,0,1,RSI);
   ArraySetAsSeries(RSI,true);

   double RSInow = RSI[0];

   Comment("RSI = ",RSInow);

   if(RSInow>RSIUpperlvl || RSInow<RSIlowerlvl){
      if(TradingEnabledComm=="" || TradingEnabledComm!="Printed"){
         TradingEnabledComm = "Trading is disabled due to RSI filter";
      }
      return(true);
   }

   return false;
}
//+------------------------------------------------------------------+
//| IsMAFilter function                                              |
//+------------------------------------------------------------------+
bool IsMAFilter(){
   if(MAFilterOn==false) return(false);

   double MovAvg[];
   CopyBuffer(handleMovAvg,MAIN_LINE,0,1,MovAvg);
   ArraySetAsSeries(MovAvg,true);

   double MAnow = MovAvg[0];
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   if( ask > MAnow * (1 + PctPricefromMA/100) ||
       ask < MAnow * (1 - PctPricefromMA/100)
     ){
      if(TradingEnabledComm=="" || TradingEnabledComm!="Printed"){
         TradingEnabledComm = "Trading is disabled due to Mov Avg Filter";
      }
      return true;
   }

   return false;
}
//+------------------------------------------------------------------+
//| IsTradingAllowedbyDay function                                   |
//+------------------------------------------------------------------+
bool IsTradingAllowedbyDay(){
   MqlDateTime today;
   TimeCurrent(today);
   string Daytoday = EnumToString((ENUM_DAY_OF_WEEK)today.day_of_week);
   
   if(AllowedMonday==true && Daytoday=="MONDAY") return true;
   if(AllowedTuesday==true && Daytoday=="TUESDAY") return true;
   if(AllowedWednesday==true && Daytoday=="WEDNESDAY") return true;
   if(AllowedThursday==true && Daytoday=="THURSDAY") return true;
   if(AllowedFriday==true && Daytoday=="FRIDAY") return true;
   if(AllowedSaturday==true && Daytoday=="SATURDAY") return true;
   if(AllowedSunday==true && Daytoday=="SUNDAY") return true;
   
   if(TradingEnabledComm=="" || TradingEnabledComm!="Printed"){
      TradingEnabledComm = "Trading is not allowed on " + Daytoday;
   }
   
   return false;
}
//+------------------------------------------------------------------+
//| UpdateInitialBalances function                                   |
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
//+------------------------------------------------------------------+
//| UpdatePropfirmValues function                                    |
//+------------------------------------------------------------------+
void UpdatePropfirmValues(){
   double Equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   if(BegofDayBalance != 0){
      Prf_1D_Pct = (Equity - BegofDayBalance) * 100 / BegofDayBalance;
      if(Equity > EqHigh_1D) EqHigh_1D = Equity;
      double currDD_1D = (Equity - EqHigh_1D) * 100 / EqHigh_1D;
      if(currDD_1D < DD_1D_Pct) DD_1D_Pct = currDD_1D;
   }
   
   if(BegofWeekBalance != 0){
      Prf_7D_Pct = (Equity - BegofWeekBalance) * 100 / BegofWeekBalance;
      if(Equity > EqHigh_7D) EqHigh_7D = Equity;
      double currDD_7D = (Equity - EqHigh_7D) * 100 / EqHigh_7D;
      if(currDD_7D < DD_7D_Pct) DD_7D_Pct = currDD_7D;
   }
   
   if(BegofMonthBalance != 0){
      Prf_30D_Pct = (Equity - BegofMonthBalance) * 100 / BegofMonthBalance;
      if(Equity > EqHigh_30D) EqHigh_30D = Equity;
      double currDD_30D = (Equity - EqHigh_30D) * 100 / EqHigh_30D;
      if(currDD_30D < DD_30D_Pct) DD_30D_Pct = currDD_30D;
   }
   
   if(InitialBalance != 0){
      Prf_AT_Pct = (Equity - InitialBalance) * 100 / InitialBalance;
      if(Equity > EqHigh_AT) EqHigh_AT = Equity;
      double currAT_DD = (Equity - EqHigh_AT) * 100 / EqHigh_AT;
      if(currAT_DD < DD_AT_Pct) DD_AT_Pct = currAT_DD;
   }
}
//+------------------------------------------------------------------+
//| IsTradingAllowedPropValues function                              |
//+------------------------------------------------------------------+
bool IsTradingAllowedPropValues(){
   if(DD_1D_Pct < -MaxDDPDay){
      if(TradingEnabledComm != "Printed") TradingEnabledComm = "Trading Disabled: Max Drawdown for Day Exceeded";
      return false;
   }
   
   if(DD_7D_Pct < -MaxDDWeek){
      if(TradingEnabledComm != "Printed") TradingEnabledComm = "Trading Disabled: Max Drawdown for Week Exceeded";
      return false;
   }
   
   if(DD_30D_Pct < -MaxDDMonth){
      if(TradingEnabledComm != "Printed") TradingEnabledComm = "Trading Disabled: Max Drawdown for Month Exceeded";
      return false;
   }
   
   if(DD_AT_Pct < -MaxDDTotal){
      if(TradingEnabledComm != "Printed") TradingEnabledComm = "Trading Disabled: Max Drawdown for All Time Exceeded";
      return false;
   }
   
   if(Prf_AT_Pct > ProfitTarget){
      if(TradingEnabledComm != "Printed") TradingEnabledComm = "Hoorayyyyy!!!!! Target Achieved";
      return false;
   }
   
   return true;
}
//+------------------------------------------------------------------+
//| OnChartEvent                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam){
   panel.ChartEvent(id,lparam,dparam,sparam);
}
//+------------------------------------------------------------------+