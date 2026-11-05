//+------------------------------------------------------------------+
//|                   Time Range EA         Trades Range Breakes     |
//|                                                                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024 MetaQuots LTD"
#property   link " https://www.mql5.com"
#property   version "1.00"



#include<Trade/Trade.mqh>
      CTrade        trade;     // this will be used to do the trading operation like buying selling chinging stoplosses
      CPositionInfo posinfo;   // this will be used to get the tade positions whether its a buy or sell
      COrderInfo    ordinfo;   // this will be used to get the pending positions on the brokers server
//we get the indicators information Trend based Indicators
#include<Indicators/Trend.mqh>
      CiIchimoku       Ichimoku;              // This is to call Ichimoku indicator
      CiMA             MovAvgFast,MovAVgSlow; // This is to call Moving Average Indicator

// drop down menu

enum   LST     {Fixed=0,RiskPct=1};
enum   Hours   {Inactive=0,_0100=1,_0200=2,_0300=3,_0400=4,_0500=5,_0600=6,_0700=7,_0800=8,_0900=9,_1000=10,_1100=11,_1200=12,_1300=13,_1400=14,_1500=15,_1600=16,_1700=17,_1800=18,_1900=19,_2000=20,_2100=21,_2200=22,_2300=23};
enum   Minutes {_0=0,_5=5,_10=10,_15=15,_20=20,_25=25,_30=30,_35=35,_40=40,_45=45,_50=50,_55=55};
enum   TrSides {Onesided=0,Bothside=1};
enum   SLType  {Yes=0,No=1};
enum   TrType  {RangePct=0,HighLow=1,Fixedpips=2};
enum   TrStyle  {with_Break=0,Opposite_to_Break=1};
enum   IcTypes {Price_above_Cloud=0,Price_above_Ten=1,Price_above_Kij=2,Price_above_SenA=3,Price_above_SenB=4,Ten_above_Kij=5,Ten_above_Kij_above_above_Cloud=6,Ten_above_Cloud=7,Kij_above_Cloud=8};
enum   sep_dropdown { comma=0,semicolon=1}; // This is for the News filter
//Creating the variables

input group "==== EA Specific Variables=="
      input ulong     InpMagic                  = 34567;        //EA's identification Number
      input string    TradeComment              ="Time Range";  //Trade Comment
      input TrStyle    TradingStyle             =1 ;            //Trading with Break or Opposite?
      input TrSides    TradingSides             =0;             //Trade one_side or Both-sides?

input group "=== Range Parameters===="
      input Hours      RangeStartHour           =8;      //Start-Hour for Range
      input Minutes    RangeStartMin            =0;      //Start-Minute for Range
      input Hours      RangeEndHour             =12;     //End hour for Range
      input Minutes    RangeEndMin              =0;      //End Minutes for Range
      input Hours      TradeCloseHour           =22;    //Close hour for Open Trades
      input Minutes    TradeCloseMin            =0;     //close minutes for open Trades
      input color      rangecolor               =clrBeige; //color of range on screen when within min/max Size
      input int        MinRangeSize             =15;       // min Range size in Pips (1 pip = 10 points)
      input int        MaxRangeSize             =30;       //Max Range   size in Pips (1 pip = 10 points)
      input color      rangecolordisabled       =clrRed;  // Color of range when outside Min/Max size

input group "=== Trade Management =="
      input LST            LotSizeType           =1;       //Fixed Lotsize or as % of Capital
      input double         FixedLotSize          =0.01;    //Fixed Lotsize in case
      input double         RiskPercent           =2;       // Risk % of capital on one trade
      input ENUM_TIMEFRAMES InpTimeFrame         =PERIOD_M5; //Timeframe for the EA
      input int             ordDistPct           =10;       //Order Distance in % of Range
      input int             SLPercent            =100;      //Sl% of Range (100% = opposite end of range)
      input int             TPPercent            =180;      //Tp % of Range (100% = TP equal range size)

input group "== StopLoss Management==="

      input  SLType         SlT                  =1;     //Trail Stoploss ?  (no = fixed Stoploss)
      input  TrType         TrailType            =1;     //If yes What type
      input  int            TrailFixedpips       =30;    //Fixed Pips to Trail (if selected)
      input  int            TrailRangePct        =80;    // What % of Range Size (if selected)
      input  int            BarsN                =5;     //No of Bars   to find high/low (if selected)
      input  int            HighLowBuffer        =2;     //Buffer in pips above /below high/low (if high/low)

//variables not needed to be placed by the user
MqlDateTime  starttime,endtime,closetime;
datetime timestart,timeend,timeclose;
int      BarsRangeStart,BarstoCount,BuyTotal,SellTotal;
double   RangeHigh,RangeLow,RangeSize,Tsl;

input group "==News Filter=="
      input bool            NewsFilterOn         =true;             //Filter for News?
      input sep_dropdown    separator            =0;                //Separator to separate news Keywords
      input string          KeyNews              ="NFP,JOLTS,Nonfarm,PMI,Retail,GDP,confidence,Interest Rate";  //Keynews to avoid 
      input string          NewsCurrencies       ="USD";            //Currencies for news Lookup
      input int             DaysNewsLookup       =100;              //No of Days to look up news
      input color           InpDisabledColor     =clrRed;          //Chart color When   disabled  by upcoming news
      
      ushort    sep_code;
      string    Newstoavoid[];
      bool      newsprinted=false;

input group "=== Moving Average Filter=="
      input  bool             MAFilterOn          =true;             //Buy When Fast MA >Slow MA (vice versa for sells)
      input  ENUM_TIMEFRAMES  MATimeframe         =PERIOD_D1;        //Timeframe for mov Average Filter
      input   int             Slow_MA_Period      =200;              //Slow Moving Average Period
      input   int             Fast_MA_Period      =50;               //Fast Moving Average Period
      input   ENUM_MA_METHOD  MA_Mode             =MODE_EMA;         //Moving Average Mode/Method
      input   ENUM_APPLIED_PRICE MA_AppPrice      =PRICE_MEDIAN;     //Moving Avg Applied Price

              bool            MA_BuyOn             =true;
              bool            MA_sellOn            =true;

input group "=== Ichimoku Filter ==="
      input  bool              IchimokuFilter       =true;            // Buy only above cloud and sell only below cloud
      input  IcTypes           IchiFilterType       =0;                // Buy above Which Ichimoku Parameter ?
      input ENUM_TIMEFRAMES    IchiTimeframe        =PERIOD_D1;       //ICHIMOKU CLOUD Timeframe
      input int                tenkan               =9;               //Period of TenkanSen
      input int                kijun                =26;              //period  of kijunsen
      input int                senkou_b             =52;              //Period of senKouSpanB
            
           bool                 Ichi_BuyOn          =true;
           bool                 Ichi_SellOn         =true;
   


//+--------------------------------------------------+
//|EXPERT initialization function
//+--------------------------------------------------

int OnInit(){
   //--
   trade.SetExpertMagicNumber(InpMagic); // Here we correct the magic number placed by the user
   ChartSetInteger(0,CHART_SHOW_GRID,false); // Remove the Chart grid when the EA is loaded
   if(IchiFilterType==true){
      Ichimoku = new CiIchimoku;
      Ichimoku.Create(_Symbol,IchiTimeframe,tenkan,kijun,senkou_b);
   }
   if(MAFilterOn== true){
      MovAVgSlow = new CiMA;
      MovAVgSlow.Create(_Symbol,MATimeframe,Slow_MA_Period,0,MA_Mode,MA_AppPrice);
      MovAvgFast = new CiMA;
      MovAvgFast.Create(_Symbol,MATimeframe,Fast_MA_Period,0,MA_Mode,MA_AppPrice);

   }


   //--
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){

}

void OnTick(){

}


//EA specific functions
void ConvertTimes(){
   TimeToStruct(TimeCurrent(),starttime); //This will check the current time into the starttime(hours) and minutes for the Range defined by the user
   starttime.hour =RangeStartHour; starttime.min =RangeStartMin;
   timestart=StructToTime(starttime);

   TimeToStruct(TimeCurrent(),endtime); //This will check the current time into the Endtime(hour) and minutes  for the Range defined by the user
   endtime.hour =RangeEndHour; endtime.min=RangeEndMin;
   timeend      =StructToTime(endtime);

   TimeToStruct(TimeCurrent(),closetime); //This will check the current time into the close time for the range defined by the user 
   closetime.hour =TradeCloseHour; closetime.min=TradeCloseMin;
   timeclose= StructToTime(closetime);

   if(BarsRangeStart ==0 && TimeCurrent()>=timestart){
      BarsRangeStart =iBars(_Symbol,InpTimeFrame);
   }

}

// here we get the value of the Range
double GetHigh(){
   double high=0;
   int highestbar=0;
   int BarsNow=iBars(_Symbol,InpTimeFrame);
   if(TimeCurrent()>timestart && TimeCurrent()<timeend){
      BarstoCount = iBars(_Symbol,InpTimeFrame) - BarsRangeStart +1;
      highestbar =  iHighest(_Symbol,InpTimeFrame,MODE_HIGH,BarstoCount,0);
      high = iHigh(_Symbol,InpTimeFrame,highestbar);
      if(high!=RangeHigh) return high;
   }
   return RangeHigh;
}

//creating the Range visualy on the Chart
void ShowRange(double high, double low){
   ObjectCreate(0,"range",OBJ_RECTANGLE,0,timestart,high,timeend,low);
   if(RangeSize<MaxRangeSize*10*_Point && RangeSize > MinRangeSize*10*_Point){
      ObjectSetInteger(0,"range",OBJPROP_COLOR,rangecolor);
      ObjectSetInteger(0,"range",OBJPROP_FILL,rangecolor);
   }else{
      ObjectSetInteger(0,"range",OBJPROP_COLOR,rangecolordisabled);
      ObjectSetInteger(0,"range",OBJPROP_FILL,rangecolordisabled);

   }
   ObjectCreate(0,"Tradingtime",OBJ_RECTANGLE,0,timeend,high,timeclose,low);
   ObjectSetInteger(0,"Tradingtime",OBJPROP_COLOR,rangecolor);

   ObjectCreate(0,"endtime",OBJ_VLINE,0,timeclose,0);
   ObjectSetInteger(0,"endtime",OBJPROP_COLOR,rangecolor);


}
// this function is to check whether we are inside the time
bool IsInsideTime(){
   MqlDateTime start,now;
   int startmin,nowmin;
   TimeToStruct(TimeCurrent(),now);
      nowmin = now.hour*60+now.min;

      TimeToStruct(timestart,start);
      startmin=start.hour * 60 +start.min;

      if(nowmin >=startmin) return true;

 return false;
}
// getting the low of the Range
double GetLow(){
   double low   =0;
   int lowestbar=0;
   if(TimeCurrent()>timestart && TimeCurrent()<timeend){
      BarstoCount =iBars(_Symbol,InpTimeFrame)-BarsRangeStart+1;
      lowestbar=iLowest(_Symbol,InpTimeFrame,MODE_LOW,BarstoCount,0);
      low      =iLow(_Symbol,InpTimeFrame,lowestbar);
      if(low!=RangeLow) return low;

   }
   return RangeLow;

}
// Fuction for preparing the orders

void PrepareOrder(){
   if(TimeCurrent()>timeend && TimeCurrent()<timeclose){
      double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      if(RangeSize>MinRangeSize *10*_Point && RangeSize < MaxRangeSize * 10 *_Point){
         if(ask<RangeHigh-(RangeSize * ordDistPct/100)&& ask>RangeLow +(RangeSize * ordDistPct/100)){
            //HERE we are placing orders with the break
            if(TradingStyle==0){
               // here we check if the order is supported by moving Average and ichimoku cloud
               if(BuyTotal<=0 && MA_BuyOn == true && Ichi_BuyOn==true){
                  OpenTrade(ORDER_TYPE_BUY_STOP,RangeHigh,RangeHigh-(RangeSize*SLPercent/100));                 
               }
               if(SellTotal<0 && MA_sellOn==true && Ichi_SellOn==true){
                  OpenTrade(ORDER_TYPE_SELL_STOP,RangeLow,RangeLow+(RangeSize*SLPercent/100));
               }
            }

            if(TradingStyle==1){
               if(BuyTotal <0 && MA_BuyOn==true && Ichi_BuyOn==true){
                  OpenTrade(ORDER_TYPE_BUY_LIMIT,RangeLow,RangeLow-(RangeSize*SLPercent/100));
               }
               if(SellTotal <=0 && MA_sellOn==true && Ichi_SellOn==true){
                  OpenTrade(ORDER_TYPE_SELL_LIMIT,RangeHigh,RangeHigh+(RangeSize*SLPercent));
               }
            }
         }
      }
   }
}

void OpenTrade(ENUM_ORDER_TYPE type,double price,double sl){
   double tp =price +(price-sl)*TPPercent/SLPercent;
// (price -sl>0) ? sl price-sl:sl=sl-price
    double lots=0.01;
    switch(LotSizeType){
      case 0: lots =FixedLotSize; break;
      case 1: lots =calcLots(price-sl);
    }
    if(!trade.OrderOpen(_Symbol,type,lots,0,price,sl,tp,0,0,TradeComment)){
      printf("Open Failed for %s,%s,price=%f,sl=%f,tp=%f",_Symbol,EnumToString(type),price,sl,tp);
    }


}
















///Stardard Functions
// here we check whether there is a new candle on the chart
bool ISNewBar(){
   static datetime previousTime=0;
   datetime currentTime =iTime(_Symbol,PERIOD_CURRENT,0); // Checking the time of open of the current candle
   if(previousTime != currentTime){
      previousTime = currentTime;
      return true;  

   }
   return false; 
}

double calcLots (double slPoints){
   double risk        = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent/100;
   double ticksize    = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickvalue   = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double lotstep     = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double minvolume   =SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
   double maxvolume   =SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX);
   double volumelimit =SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_LIMIT);

   if(slPoints<0) slPoints=slPoints *-1;
   double moneyPerLotstep = slPoints / ticksize * tickvalue * lotstep;
   double lots = MathFloor(risk/moneyPerLotstep) * lotstep;

   if(volumelimit !=0)  lots = MathMin(lots,volumelimit);
   if(maxvolume !=0)    lots = MathMin(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX));
   if(minvolume!=0)     lots = MathMax(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN));
   lots = NormalizeDouble(lots,2);

   return lots;


}

void CheckforOpenOrdersandPositions(){
   for(int i=OrdersTotal()-1; i>=0;i--){
      ordinfo.SelectByIndex(i);
      if(ordinfo.OrderType()==ORDER_TYPE_BUY_STOP && ordinfo.Symbol()==_Symbol   && ordinfo.Magic()==InpMagic) BuyTotal++;
      if(ordinfo.OrderType()==ORDER_TYPE_SELL_STOP && ordinfo.Symbol()== _Symbol && ordinfo.Magic() ==InpMagic)SellTotal++;
      if(ordinfo.OrderType()==ORDER_TYPE_BUY_LIMIT && ordinfo.Symbol()==_Symbol  && ordinfo.Magic()  ==InpMagic) BuyTotal++;
      if(ordinfo.OrderType()==ORDER_TYPE_SELL_LIMIT && ordinfo.Symbol()==_Symbol && ordinfo.Magic()   ==InpMagic) SellTotal++;

   }
   for(int i = PositionsTotal()-1; i>=0;i--){
      posinfo.SelectByIndex(i);
      if(posinfo.PositionType()==POSITION_TYPE_BUY && posinfo.Symbol()==_Symbol && posinfo.Magic()==InpMagic) BuyTotal++;
      if(posinfo.PositionType()==POSITION_TYPE_SELL && posinfo.Symbol()==_Symbol && posinfo.Magic()==InpMagic) SellTotal++;

   }
}


double findHigh(){
   double highestHigh =0;
   for(int i =0; i<200;i++){
      double high=iHigh(_Symbol,InpTimeFrame,i);
      if(i>BarsN && iHighest(_Symbol,InpTimeFrame,MODE_HIGH,BarsN*2+1, i-BarsN) ==1){
         if(high > highestHigh){
            return  high;
         }

      }
      highestHigh = MathMax(high,highestHigh);

   }
   return -1;
}


double findLow(){
   double lowestLow=DBL_MAX;
   for(int i= 0; i<200;i++){
      double low=iLow(_Symbol,InpTimeFrame,i);
      if(i>BarsN && iLowest(_Symbol,InpTimeFrame,MODE_LOW,BarsN*2+1,i-BarsN)==i){
         if(low < lowestLow){
            return low;
         }
      }
      lowestLow =MathMin(low,lowestLow);     
   }
   return -1;
}