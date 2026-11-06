
#property  copyright "Mikey"
#property  link "https://Mikey.com"
#property  version "1.00"
#property  strict
#property  description "Waka Waka EA"

#include<Trade\Trade.mqh>
      CTrade          Trade;
      CPositionInfo  posInfo;
      COrderInfo     ordInfo;

enum  LotSizingEnum{
                  LowRiskPresent =5,                      //Low Risk Set 20% annual (0.25% load)
                  MidRiskPreset=4,                        //Mid Risk set 40% annual (0.5% load)
                  HighRiskPreset=3,                       //Significant Risk Set 80% annual (1.0%)
                  ExtremeRiskPreset=7,                    //High Risk set 120% annual  (1.5% load)
                  LotsEquity=2,                           //Dynamic Lot based on Equity  
                  LotsBalance=1,                          //Dynamic Lot based on Balance
                  LotsDepositLoad=6,                      //Lots based on Deposit load
                  FixedLots=0                             //Fixed Lot
                   };

enum  AllowBuySellEnum{
            AllowSell2  =2,                                //Sell only
            AllowBuy1   =1,                                 //Buy only
            AllowBuySell=0                               //Buy and sell
                     };
enum eMaxDrawdownAction{ 
            IgnoreNewUntilRestart       =3,                      //Prohibit opening new grids until restart
            IgnoreNewSignals            =2,                         //Prohibit opening new grids
            CloseStopTradingUntilRestart=1,            //Close Trades & Stop trading until restart
            CloseStopTradingFor24H      =0                   //close trades & stop trading for 24H

                       };

//How are we going to calculate the drawdown to be choosen by the user either by thisStrategy or by The Account
enum  eDrawdownCalculation{
                ThisStrategy =1,                       //This Strategy
                TheAccount   =0                        //The account
                          };


enum tTradeHours{
         _0000=0,_0100=1,_0200=2,_0300=3,_0400=4,_0500=5,
         _0600=6,_0700=7,_0800=8,_0900=9,_1000=10,_1100=11,
         _1200=12,_1300=13,_1400=14,_1500=15,_1600=16,_1700=17,
         _1800=18,_1900=19,_2000=20,_2100=21,_2200=22,_2300=23
               };
                          
//create a structure this are symbol variables
struct SymbolInformation{
            string   SymbolName;
            datetime LastMainTFUpdate;
            datetime LastOPOTUpdate;
            int      UpdateCounter;
            bool     CanBuy;
            bool     CanSell;
            datetime CurrentBarTime;
            datetime PreviousBarTime;
            double   ClosePrice;
            bool     GridOpened;
            bool     OPOTriggered;
            double   SmartDistanceMultiplier;
            double   BBWidth;
            int      LastBarIndex;
            int      CurrentBarIndex;
            long     PatternValue;
            double   PatternPrice;
            bool     PatternSearchActive;
            bool     TradingAllowedToday;
            bool     PreviousDayTradingAllowed;
            int      LastDayOfWeek;
            double   MaxGridLotMultiplier;
            double   LastBuyAvgPrice;
            double   LastSellAvgPrice;
            double   LastBuyTP;
            double   LastSellTP;
            datetime LastBuyGridTime;
            datetime LastSellGridTime;
                     };           


//Variables to be set by the user
input group "<<=========================== Select the risk settings=========>>>"
   input  bool                   AllowOpeningNewGrid            =true;         // Allow Opening a new Grid?
   input  LotSizingEnum          LotSizingMethod                =5;           //Lot-Sizing Method
   input  double                 LotSizingValueFixed            =0.01;        //Fixed Lot
   input  double                 LotSizingValueDynamic          =10000;       //Dynamic Lot (Balance / Equity Based)
   input  double                 LotSizingDepositLoadPercent    =0.25;       //Deposite Load %
   input  bool                   FixedInitialDeposit            =false ;     //Fixed Initial Deposit ?(Tester only)     
   input  double                 MaximumLot                     =100;        //Maximum Lot
   input  bool                   AutoSplit                      =false;      //Auto Split?
   input  double                 MaximumSpread                  =10;         //Maximum Spread in pips
   input  int                    MaximumSlippage                =10;         //Maximum Slippage for a non-ECN acc in Pips
   input  int                    MaximumSymbols                 =2;          //Maximum Symbols at a time
   input  bool                   AllowHedging                   =true;      //Allow Hedging
   input  bool                   AllowTradingOnHolidays         =false;     //Allow Trading on Holidays?
   input  AllowBuySellEnum       AllowToBuySell                 =0;         //Allow to Buy/Sell
   input  double                 MinimumFreeMargin              =0;         //Minimum Free Margin % [0-disabled]
   input  double                 maximumDrawdown                =100;       //Max Floating Drawdown %
   input  double                 MaximumDrawdownMoney           =0;        //Max floating Drawdown in Money[0-disabled]
   input  eMaxDrawdownAction     MaximumDrawdownAction          =0;        //Max Drawdown  Action
   input  eDrawdownCalculation   DrawdownCalculation            =1;        //Max Drawdown caculation

 input   group "<<<===== Select the Strategy Settings and Symbols used==>>"
   input string                  Symbols                        ="AUDNZD,AUDCAD,NZDCAD"; //Symbols sepparated by comma
   input tTradeHours             HourToStartTrading             =_0700;                     //Hour to Start trading (Broker\`s time)
   input tTradeHours             HourToStopTrading              =_2300;                   //Hour to Stop Trading (broker\`s time)
   input int                     BollingerBandsPeriod           =35;                      //Bollinger Bands    Period
   input int                     RSI_period                     =20;                      //RSI Period
   input int                     RSI_Value                      =15;                      //Maximmum RSI value
 
input  group "<<<=== Select TP settings ====>>>"
    input  double                InitialTp                      =10;                      // TakeProfit for Initial Trade in pips
    input  bool                  WeightedTp                     =true;                    // Weighted   TakeProfit
    input  double                GridTP                         =0;                       // TakeProfit for Grid in pips (can also be Zero)
    input  int                   BreakEvenAfterThisLevel        =0;                       //Break Even after this Level [0-disabled]
    input  bool                  HideTP                         =false;                  //Hide TakeProfit
    input  bool                  Use_OPO_Method                 =false;                  //Use OPO method to handle TP
    input ENUM_TIMEFRAMES        OPO_TimeFrame                  =15;                    //TF for OPO method
    input bool                   SmartTP                        =false ;                 // Smart TakeProfit
    input bool                   DoNotAdjustTPUnlessNewGrid     =false;                 //Do not adjust TP unless new grid level opened  
    
    
input group "<<<=== Select SL Settings==>>"
    input  double                GridSL                         =0;                     //StopLoss for Grid in pips (1000)
    input  bool                  HideSl                         =false;                 //Hide Stoploss?

input group "<<=====Adjust the grid distance and multipliers====>>"

input int                        TradeDistance                 =35;                    // Trade Distance
input bool                       SmartDistance                 =true;                  //Smart Distance?
input double                     TradeMultiplier_2nd           =1;                    //2nd Trade Multiplier
input double                     TradeMultiplier_3rd           =2;                    //3rd-5th Trade Multiplier
input double                     TradeMultiplier_6th           =1.5;                  //6th -Trade Multiplier
input int                        MaximumTrades                 =9;                  //Maximum  Trades
input int                        GridLevelToStart              =1;                  // Grid Level   to Start (1-initial trade)
input bool                       KeepOriginalProfitLotSize     =false;              //Keep Original  Profit Level & Lotsize

input  group "<<===Change The comment and UID if Needed=====>"

input string                      TradeComment                 ="Waka Waka " ;           // Trade comment 
input int                         UID                          =0;                       //Uid(0---9)
input bool                        ShowPanel                    =true;                    //  show Panel

//Global variables                               
int                                TickCounter                  =0;
ENUM_TIMEFRAMES                    MainTimeframe                =PERIOD_M15;
SymbolInformation                  SymbolsArray[];              
int                                MagicNumberBase              =84570;
double                             Epsilon                      =0.0000001;
int                                LastUpdateMinute             =-1;
long                               LastTimerCheck               =0;
int                                CurrentHour                  =0;
bool                               DrawdownTriggered            =false;
int                                DrawdownCooldownHours        =0;
bool                               StopTradingUntilRestart      =false;
int                                LastProcessedHour            =-1;
bool                               SymbolsListError             =false;
double                             InitialBalance               =0.0;
bool                               Initialized                  =true;


int  handle_MA[];
int  handle_Std[];
int  handle_RSI[];
int  handle_ATR96[];
int  handle_ATR672[];                ///This will be used to know the volatility in the market

int OnInit(){
    Print(TradeComment+ "-> Initializing..");
    ChartSetInteger(0,CHART_SHOW_GRID,false);
    TesterHideIndicators(true);

    Comment("Waka Waka EA");

    DrawdownCooldownHours=0;
    StopTradingUntilRestart=false;
    DrawdownTriggered=false;

    if(!MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
        EventSetTimer(5);
        LastTimerCheck =TimeCurrent();
        if(!ParseAndInitializeSymbols()){
            Print(TradeComment +"Error:Failed to initialize symbols");
            return INIT_FAILED;
        }
    ArrayResize(handle_MA,ArraySize(SymbolsArray));
    ArrayResize(handle_Std,ArraySize(SymbolsArray));
    ArrayResize(handle_RSI,ArraySize(SymbolsArray));
    ArrayResize(handle_ATR96,ArraySize(SymbolsArray));
    ArrayResize(handle_ATR672,ArraySize(SymbolsArray));
    // Here we initialize the handles
    for(int i =0;i<ArraySize(SymbolsArray);i++){
        handle_MA[i] =iMA(SymbolsArray[i].SymbolName,MainTimeframe,BollingerBandsPeriod+1,0,MODE_SMA,PRICE_CLOSE);
        handle_Std[i]=iStdDev(SymbolsArray[i].SymbolName,MainTimeframe,BollingerBandsPeriod+1,0,MODE_SMA,PRICE_CLOSE);
        handle_RSI[i]=iRSI(SymbolsArray[i].SymbolName,MainTimeframe,RSI_period,PRICE_CLOSE);
        handle_ATR96[i]=iATR(SymbolsArray[i].SymbolName,MainTimeframe,96);
        handle_ATR672[i]=iATR(SymbolsArray[i].SymbolName,MainTimeframe,672);

        if(handle_MA[i]==INVALID_HANDLE || handle_Std[i] == INVALID_HANDLE || 
           handle_RSI[i]==INVALID_HANDLE || handle_ATR96[i]== INVALID_HANDLE || 
           handle_ATR672[i]==INVALID_HANDLE){
            Print(TradeComment + ": Failed to create indicator handle for",SymbolsArray[i].SymbolName);
            Print(TradeComment +"Failed to create indicator handles for",SymbolsArray[i].SymbolName,
                "Check that all input currencies are visibe in the MarketWatch Window");
            return INIT_FAILED;
           }


    }


return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){

}


void OnTick()
{
bool isNewBarMainTF;



}


//+------------------------------------------------------+


/*===================================================================================================================
                                            Symbol Related Fuctions
=====================================================================================================================*/
bool ParseAndInitializeSymbols(){
    string symbols[];
    int symbolCount = StringSplit(Symbols,StringGetCharacter(",",0),symbols);
    if(symbolCount>0 && !MQLInfoInteger(MQL_TESTER)){
        ArrayResize(SymbolsArray,symbolCount);
        //loop through the symbols count
        for(int i=0;i<symbolCount;i++){
            string symbolName=symbols[i];
            StringTrimLeft(symbolName);
            StringTrimRight(symbolName);
            if(symbolName==" "){
                Print(TradeComment + ":List of Symbols is incorrect! Check it for extra commas!");
                SymbolsListError=true;
                return false;
            }
            InitializeSymbolData(i,symbolName);

        }
    }
    else
    {
        ArrayResize(SymbolsArray,1);
        string symbolName =Symbol();
        InitializeSymbolData(0,symbolName);
        // SymbolsArray[0].MaxGridLotMultiplier=CalculateMaxGridLotMultiplier(symbolName);
    }
    return true;

}

void InitializeSymbolData(int index, string symbolName){
    SymbolsArray[index].SymbolName=symbolName;
    SymbolsArray[index].LastMainTFUpdate=0;
    SymbolsArray[index].LastOPOTUpdate=0;
    SymbolsArray[index].UpdateCounter=0;
    SymbolsArray[index].CanBuy=false;
    SymbolsArray[index].CanSell=false;
    SymbolsArray[index].CurrentBarTime=0;
    SymbolsArray[index].PreviousBarTime=0;
    SymbolsArray[index].ClosePrice=0.0;
    SymbolsArray[index].GridOpened=false;
    SymbolsArray[index].OPOTriggered=false;
    SymbolsArray[index].SmartDistanceMultiplier=1.0;
    SymbolsArray[index].BBWidth=0.0;
    SymbolsArray[index].LastBarIndex=0;
    SymbolsArray[index].CurrentBarIndex=0;
    SymbolsArray[index].PatternValue=0;
    SymbolsArray[index].PatternPrice=0.0;
    SymbolsArray[index].PatternSearchActive=true;
    SymbolsArray[index].TradingAllowedToday=true;
    SymbolsArray[index].PreviousDayTradingAllowed=true;
    SymbolsArray[index].LastDayOfWeek=0;
    SymbolsArray[index].LastBuyAvgPrice=0.0;
    SymbolsArray[index].LastSellAvgPrice=0.0;
    SymbolsArray[index].LastBuyTP=0.0;
    SymbolsArray[index].LastSellTP=0.0;





}































/*===================================================================================================================
                                            Grid Related  Functions
=====================================================================================================================*/















/*===================================================================================================================
                                            Tp and Sl Related Functios
=====================================================================================================================*/









/*===================================================================================================================
                                            Closing the Grids/Trades /DrawDowns
=====================================================================================================================*/









/*===================================================================================================================
                                            General  Helping Functios
=====================================================================================================================*/