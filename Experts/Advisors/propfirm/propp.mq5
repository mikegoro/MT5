//+------------------------------------------------------------------+
//|                                                      Scaling Robot |
//|                                    Copyright 2023, MetaQuotes Ltd. |
//|                                       https://www.mql5.com         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

CTrade    trade;
CPositionInfo pos;
COrderInfo    ord;
//+------------------------------------------------------------------+
//| Input variables                                                  |
//+------------------------------------------------------------------+
input group "=== Trading Profiles ==="

enum SystemType{Forex=0, BitCoin=1, _Gold=2, US_Indices=3};
input SystemType SType=0; //Trading System applied (Forex, Crypto, Gold, Indices)
int SysChoice;

input group "=== Common Trading Inputs ==="

input double    RiskPercent    = 3; // Risk as % of Trading Capital
input ENUM_TIMEFRAMES   Timeframe = PERIOD_CURRENT; //Time frame to run
input int    InpMagic = 298347;    //EA identification no
input string    TradeComment = "Scalping Robot";

enum Hours{Inactive=0, _0100=1, _0200=2, _0300=3, _0400=4, _0500=5, _0600=6, _0700=7, _0800=8, _0900=9, _1000=10, _1100=11, _1200=12, _1300=13, _1400=14, _1500=15, _1600=16, _1700=17, _1800=18, _1900=19, _2000=20, _2100=21, _2200=22, _2300=23};
input Hours SHInput=0;    // Start Hour
input Hours EHInput=0;    // End Hour

int SHChoice;
int EHChoice;

input int    BarsN           = 5;    //No of Bars to identify high/low
double       OrderDistPoints = 100;
input int    ExpirationBars  = 100;  //No of Bars before order is expired
double       TPoints, SLPoints, TSLTriggerPoints, TSLPoints;

int          handleRSI, handleMovAvg;
input color  ChartColorTradingOff = clrPink;   // Chart color when EA is Inactive
input color  ChartColorTradingOn  = clrBlack;  // Chart color when EA is active
bool         TradingEnabled       = true;
input bool   HideIndicators       = true;      // Hide Indicators on Chart?
string       TradingEnabledComm   = "";

input group "=== Forex Trading Inputs ==="

input int    TPointsInput    = 200; // Take Profit (10 points = 1 pip)
input int    SLPointsInput    = 200; // Stoploss Points (10 points = 1 pip)
input int    TSLTriggerPointsInput = 15; // Points in profit before Trailing SL is activated (10 points = 1 pip)
input int    TSLPointsInput    = 10; // Trailing Stop Loss (10 points = 1 pip)

input group "=== Crypto Related Input === (effective only under Bitcoin profile)"

input double TPasPct =0.4;   // TP as % of Price
input double SLasPct = 0.4;  // SL as % of Price
input double TSLasPctTP=5; // Trail SL as % of TP
input double TSLTgrasPctTP=7; // Trigger of Trail SL % of TP

input group "=== Gold Related Input === (effective only under Gold profile)"

input double TPasPctGold =0.2; // TP as % of Price
input double SLasPctGold = 0.2; // SL as % of Price
input double TSLasPctTPGold=5; // Trail SL as % of TP
input double TSLTgrasPctTPGold=7; // Trigger of Trail SL % of TP

input group "=== Indices Inputs === (effective only under Bitcoin Profile)"

input double TPasPctIndices =0.2; // TP as % of Price
input double SLasPctIndices = 0.2; // SL as % of Price
input double TSLasPctTPIndices=5; // Trail SL as % of TP
input double TSLTgrasPctTPIndices=7; // Trigger of Trail SL as % of Price

input group "=== News Filter ==="

input bool      NewsFilterOn   = true;   //Filter for Level 3 News?
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
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit(){
    trade.SetExpertMagicNumber(InpMagic);

    ChartSetInteger(0,CHART_SHOW_GRID,false);

    SHChoice = SHInput;
    EHChoice = EHInput;

    if(SType==0) SysChoice=0;
    if(SType==1) SysChoice=1;
    if(SType==2) SysChoice=2;
    if(SType==3) SysChoice=3;

    TPoints = TPointsInput;
    SLPoints = SLPointsInput;
    TSLTriggerPoints = TSLTriggerPointsInput;
    TSLPoints = TSLPointsInput;

    if(HideIndicators==true) TesterHideIndicators(true);

    handleRSI = iRSI(_Symbol,RSITimeframe,RSI_MA,RSI_AppPrice);
    handleMovAvg = iMA(_Symbol,MATimeframe,MA_Period,0,MA_Mode,MA_AppPrice);

    return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick(){
    TrailStop();

    if( IsRSIFilter() || IsUpcomingNews() || IsMAFilter() ){
        CloseAllOrders();
        TradingEnabled=false;
        ChartSetInteger(0,CHART_COLOR_BACKGROUND,ChartColorTradingOff);
        if(TradingEnabledComm!="Printed")
            Print(TradingEnabledComm);
        TradingEnabledComm="Printed";
        return;
    }

    TradingEnabled=true;
    if(TradingEnabledComm!=""){
        Print("Trading is enabled again");
        TradingEnabledComm = "";
    }

    ChartSetInteger(0,CHART_COLOR_BACKGROUND,ChartColorTradingOn);

    if(!IsNewBar()) return;

    MqlDateTime time;
    TimeToStruct(TimeCurrent(),time);
    int Hournow = time.hour;

    if(Hournow < SHChoice){CloseAllOrders(); return;}
    if(Hournow >= EHChoice && EHChoice != 0){CloseAllOrders(); return;}

    if(SysChoice==1){
        double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
        TPoints = ask * TPasPct;
        SLPoints = ask * SLasPct;
        OrderDistPoints = TPoints/2;
        TSLPoints = TPoints * TSLasPctTP/100;
        TSLTriggerPoints = TPoints * TSLTgrasPctTP/100;
    }

    if(SysChoice==2){
        double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
        TPoints = ask * TPasPctGold;
        SLPoints = ask * SLasPctGold;
        OrderDistPoints = TPoints/2;
        TSLPoints = TPoints * TSLasPctTPGold/100;
        TSLTriggerPoints = TPoints * TSLTgrasPctTPGold/100;
    }

    if(SysChoice==3){
        double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
        TPoints = ask * TPasPctIndices;
        SLPoints = ask * SLasPctIndices;
        OrderDistPoints = TPoints/2;
        TSLPoints = TPoints * TSLasPctTPIndices/100;
        TSLTriggerPoints = TPoints * TSLTgrasPctTPIndices/100;
    }

    int BuyTotal = 0;
    int SellTotal = 0;

    for (int i = OrdersTotal()-1; i >= 0; i--) {
        ord.SelectByIndex(i);
        if(ord.OrderType() == ORDER_TYPE_BUY_STOP && ord.Symbol() == _Symbol && ord.Magic() == InpMagic) BuyTotal++;
        if(ord.OrderType() == ORDER_TYPE_SELL_STOP && ord.Symbol() == _Symbol && ord.Magic() == InpMagic) SellTotal++;
    }

    for (int i = PositionsTotal()-1; i >= 0; i--) {
        pos.SelectByIndex(i);
        if(pos.PositionType() == POSITION_TYPE_BUY && pos.Symbol() == _Symbol && pos.Magic() == InpMagic) BuyTotal++;
        if(pos.PositionType() == POSITION_TYPE_SELL && pos.Symbol() == _Symbol && pos.Magic() == InpMagic) SellTotal++;
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
    double risk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100;
    double ticksize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickvalue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    double moneyPerLotstep = slPoints / ticksize * tickvalue * lotstep;
    double lots = MathFloor(risk / moneyPerLotstep) * lotstep;

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

    for (int i=PositionsTotal()-1; i>=0; i--){
        if(pos.SelectByIndex(i)){
            ulong ticket = pos.Ticket();
            if(pos.Magic()==InpMagic && pos.Symbol()==_Symbol){
                if(pos.PositionType()==POSITION_TYPE_BUY){
                    if(bid-pos.PriceOpen()>TSLTriggerPoints*_Point){
                        tp = pos.TakeProfit();
                        sl = bid - (TSLPoints * _Point);
                        if(sl > pos.StopLoss() && sl!=0){
                            trade.PositionModify(ticket,sl,tp);
                        }
                    }
                }
                else{
                    if(pos.PositionType()==POSITION_TYPE_SELL){
                        if(ask+(TSLTriggerPoints*_Point)<pos.PriceOpen()){
                            tp = pos.TakeProfit();
                            sl = ask + (TSLPoints * _Point);
                            if(sl < pos.StopLoss() && sl!=0){
                                trade.PositionModify(ticket,sl,tp);
                            }
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






//+------------------------------------------------------------------+
//|                                                      Scaling Robot |
//|                                    Copyright 2023, MetaQuotes Ltd. |
//|                                       https://www.mql5.com         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>
#include <PropfirmPanel.mqh>

CTrade         trade;
CPositionInfo  posinfo;
COrderInfo     ord;
//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum SystemType{Forex=0, BitCoin=1, _Gold=2, US_Indices=3};
enum Hours{Inactive=0, _0100=1, _0200=2, _0300=3, _0400=4, _0500=5, _0600=6, _0700=7, _0800=8, _0900=9, _1000=10, _1100=11, _1200=12, _1300=13, _1400=14, _1500=15, _1600=16, _1700=17, _1800=18, _1900=19, _2000=20, _2100=21, _2200=22, _2300=23};
enum LotSizeType{Fixed_Lots=0, Pct_of_Balance=1, Pct_of_Equity=2, Pct_of_Free_Margin=3};