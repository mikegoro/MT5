
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
                     
class    MagicHelper{
    private:
        int m_base;           //MagicNumberBase (84570)
        int m_uid;           //UID(0-9)
        int m_magicBase;     // base + uid 
        int m_digits;       // how many digits in M_magicBase

    public:
        //Constructor - stores all the values we need
        MagicHelper(int base,int uid)
        {
            m_base = base;
            m_uid  = uid;
            m_magicBase=base +uid;
            m_digits= StringLen(IntegerToString(m_magicBase));


        }
    //Helper functions
    int GetBase(){return m_magicBase;}

    //Get magic number for a direction (1=buy 2=sell ) Without lvel
    //This is for the "base" orders (level 0)

    int GetDirectionMagic(int direction){
        return (int) MathPow(10,m_digits+2) * direction + m_magicBase * 100; // => buy =>10000000 * 1 + *84570 * 100 = 18457000


    }

    //Get magic number for a specific level and direction
    //This is for grid orders (Level 1,2,3.......)

    int GetLevelMagic(int direction,int level)
    {
        return (int) MathPow(10,m_digits + 2 ) * direction + m_magicBase * 100 + level;  // => buy =>10000000 * 1 + *84570 * 100 + 2(level) = 18457000
    }

    //Check if a magic number belongs to our EA
     bool IsOurOrder(int magic)
     {
        if(magic<=0) return false;

        int prefix = magic /100; /// Get everything except the 2 digits (level)

        //Our prefix are: m_MagicBase + 10^m_digits (for buys)
        // or m_magicBase + 2*10^m_digits (for sells)
        int buyPrefix = m_magicBase + (int)MathPow(10,m_digits);
        int sellPrefix = m_magicBase + (int)MathPow(10,m_digits) * 2;

        return (prefix == buyPrefix || prefix==sellPrefix);
     }

     //Get direction from magic number (1=buy,2=sell,0=not ours)

     int GetDirectionFromMagic(int magic)
     {
        if(!IsOurOrder(magic)) return 0;
        int prefix = magic /100;
        int buyPrefix = m_magicBase + (int)MathPow(10,m_digits);
        int sellPrefix = m_magicBase +(int)MathPow(10,m_digits) *2;


        if(prefix == buyPrefix) return 1; //buy
        if(prefix == sellPrefix) return 2; //sell
        return 0;

     }


     // Get level from magic number (-1 if base/level 0 order)
     int GetLevelFromMagic(int magic)
     {
        if(!IsOurOrder(magic)) return -2;
        return magic % 100; // Last 2 digits are Level 

     }


    
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

MagicHelper g_magic(MagicNumberBase,UID);

int OnInit(){
    Print(TradeComment+ "-> Initializing..");
    ChartSetInteger(0,CHART_SHOW_GRID,false);
    // TesterHideIndicators(true);

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
    InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);


return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){

    for(int i =0; i<ArraySize(handle_MA);i++){
        IndicatorRelease(handle_MA[i]);
        IndicatorRelease(handle_Std[i]);
        IndicatorRelease(handle_RSI[i]);
        IndicatorRelease(handle_ATR96[i]);
        IndicatorRelease(handle_ATR672[i]);

        
    }
    EventKillTimer();  //we gonna update on timer function 
    if(!MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
    {
        ObjectsDeleteAll(0,-1);
    }

}


void OnTick()
{
    bool isNewBarMainTF;
    for(int i=0;i<ArraySize(SymbolsArray);i++){
        if(iTime(SymbolsArray[i].SymbolName,MainTimeframe,0)<= SymbolsArray[i].LastMainTFUpdate)
        {
            isNewBarMainTF=false;
        }
        else
        {
            SymbolsArray[i].LastMainTFUpdate=iTime(SymbolsArray[i].SymbolName,MainTimeframe,0);
            isNewBarMainTF=true;
        }
        if(isNewBarMainTF){
            UpdateSymbolInfo(i);
            if(IsTradingAllowed())
            {
                CheckAndOpenGridOrders(i);
                ModifyGridTPsl(i);

            }
        }
    }
 



}


//+------------------------------------------------------+


/*===================================================================================================================
                                            Symbol Related Fuctions
=====================================================================================================================*/
void CheckAndOpenGridOrders(int symbolIndex)
{
    string symbol = SymbolsArray[symbolIndex].SymbolName;

    //Quick validation
    if(MaximumTrades <= 1 || TradeMultiplier_3rd <=0 || TradeDistance<=Epsilon)
        return;
    
    double spread =(double)SymbolInfoInteger(symbol,SYMBOL_SPREAD);
    double point  = SymbolInfoDouble(symbol,SYMBOL_POINT);
    int   digits  = (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);

    CheckGridDirection(symbolIndex,ORDER_TYPE_BUY,spread,point,digits);
    CheckGridDirection(symbolIndex,ORDER_TYPE_SELL,spread,point,digits);


}

void CheckGridDirection(int symbolIndex,ENUM_ORDER_TYPE orderType,double spread,double point,int digits)
{
    string symbol =SymbolsArray[symbolIndex].SymbolName;
    int direction =(orderType == ORDER_TYPE_BUY) ? 1 :-1;

    //check if we have initial position
    if(!GridExists(symbol,0,direction))
        return;
    
    //if there is an existing grid 
    double totLots      =GetTotalLotsInGrid(symbol,0,direction,false);
    double currentPrice =SymbolsArray[symbolIndex].ClosePrice;
    double avgPrice     = GetWeightedAvgPrice(symbol,0,direction);

    //check each grid level
    for(int level=1; level<=MaximumTrades-1;level++)
    {
        //skip if this level already exists
        if(GridExists(symbol,level,direction) || SymbolsArray[symbolIndex].GridOpened)
        continue;

        //calculate required distance- Match original Exactly
        double requiredDistance = TradeDistance * level;

        //Convert to price distance
        double priceDistance = requiredDistance * point * GetPipMultiplier(symbol) *
                               SymbolsArray[symbolIndex].SmartDistanceMultiplier;


        double    priceDiff = currentPrice -avgPrice;

        bool priceReached;

        if(orderType==ORDER_TYPE_BUY)
            priceReached =(priceDiff<-priceDistance);
        else
            priceReached=(priceDiff>priceDistance);

        if(!priceReached)
            continue;

        //calculate initial lot for GridLevelToStart feature
        double initialLot=0;
        if(GridLevelToStart>1)
            initialLot=GetTotalLotsInGrid(symbol,GridLevelToStart-1,direction,false);
        
        //Calculate lot size

        double lotSize=CalculateGridLotSize(symbol,totLots,level,initialLot);

        if(lotSize<=0)
            continue;

        //open the order
        if(OpenGridOrder(symbolIndex,orderType,level,lotSize))
        {
            SymbolsArray[symbolIndex].GridOpened=true;
            SymbolsArray[symbolIndex].OPOTriggered=true;
            Sleep(5000);


        }
    }  
}

bool OpenGridOrder(int symbolIndex,ENUM_ORDER_TYPE orderType,int level,double lotSize)
{
    string symbol = SymbolsArray[symbolIndex].SymbolName;

    //Check spread
    double spread =(double)SymbolInfoInteger(symbol,SYMBOL_SPREAD);
    if(spread > MaximumSpread * GetPipMultiplier(symbol) && MaximumSpread > Epsilon)
    {
        Print(TradeComment + " "+symbol,":Spread too high for grid order :",spread);
        return false;

    }

    //Check margin
    double margin =0;

    if(!OrderCalcMargin(orderType,symbol,lotSize,
        (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol,SYMBOL_ASK):SymbolInfoDouble(symbol,SYMBOL_BID),
        margin) || margin <=0 || 
        margin >AccountInfoDouble(ACCOUNT_MARGIN_FREE))
    {
        Print(TradeComment + " " + symbol,": Not enough margin for grid order");
        return false;

    }

    // Handle auto-splitting if needed
    if(AutoSplit && lotSize > GetMaxLot(symbol))
        return  SplitAndOpenOrders(symbolIndex,orderType,level,lotSize);

        //open single order
        return SendGridOrder(symbolIndex,orderType,level,lotSize);




}

bool SendGridOrder(int symbolIndex,ENUM_ORDER_TYPE orderType,int level,double lotSize)
{
    string symbol =SymbolsArray[symbolIndex].SymbolName;

    //Calculate magic number
    int magic =CalculateGridMagicNumber(orderType,level);
    //Prepare comment

    string comment = TradeComment;
    if(level>0)
        comment += " # " + IntegerToString(level);

        Trade.SetExpertMagicNumber(magic);
        Trade.SetDeviationInPoints(MaximumSlippage * GetPipMultiplier(symbol));
        bool success =(orderType == ORDER_TYPE_BUY) ? Trade.Buy(lotSize,symbol,0,0,0, comment):
                                                      Trade.Sell(lotSize,symbol,0,0,0,comment);

    if(success)
    {
        Print(TradeComment+" "+symbol,":Grid order opened,id",Trade.ResultOrder(),"level :",level);
        if(orderType == ORDER_TYPE_BUY)
            SymbolsArray[symbolIndex].LastBuyGridTime=TimeCurrent();
            else
            SymbolsArray[symbolIndex].LastSellGridTime=TimeCurrent();
            return true;
    }
    else
    {
        Print(TradeComment+ " " + symbol,":Failed to Open grid order.Retcode",Trade.ResultRetcode()," "
        ,Trade.ResultRetcodeDescription());
        Sleep(1000);
        return false;

    }



}

int  CalculateGridMagicNumber(ENUM_ORDER_TYPE orderType, int level)
{
  int magicBase = MagicNumberBase + UID;
  int digits    = StringLen(IntegerToString(magicBase));
  int direction = (orderType== ORDER_TYPE_BUY) ? 1:2;

  return (int)MathPow(10,digits+2) * direction + magicBase * 100 + level;
}

double GetWeightedAvgPrice(string symbol,int level, int direction)
{
    double totLots     =0;
    double totalPrice  =0;

    //Convert direction : 1=buy -1=sell to our helper format (1=buy,2=sell)
    int targetDir=(direction==1) ? 1:2;

    //Loop through all orders
    for(int i =0;i<PositionsTotal();i++)
    {
        //Select the order
        if(!posInfo.SelectByIndex(i))
        {
            Print("OrderSelect failed",GetLastError());
            continue;
        }
        //Skip if wrong symbol
        if(posInfo.Symbol() !=symbol) continue;

        //Get magic number
        int magic = (int)posInfo.Magic();

        //Is this our order? Use our helper
        if(!g_magic.IsOurOrder(magic)) continue;

        //Is it the right direction?
        if(g_magic.GetDirectionFromMagic(magic) != targetDir) continue;

        //If level >=0, only include that Specific level
        if(level >=0 && g_magic.GetLevelFromMagic(magic)!=level) continue;

        // Add to totals
        double lots = posInfo.Volume();
        totLots+=lots;
        totalPrice+=posInfo.PriceOpen() * lots;

        //Original behavior if not AutoSplit, only take first order
        if(!AutoSplit) break;
    }
    //Calculate average
    if(totLots > Epsilon)
        return totalPrice/totLots;
    
    return 0;
}


double CalculateGridLotSize(string symbol,double currentTotalLots,int level, double initialLot){
  double step =SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
  double minLot =SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
  double maxLot  =SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
  double limitLot =SymbolInfoDouble(symbol,SYMBOL_VOLUME_LIMIT);

  if(step <0.0001) step=0.001;

  double result =minLot;
  double baseLot = currentTotalLots;

  //handle GrindLevelToStart feature
    if(GridLevelToStart>1)
    {
        if(initialLot<0.0099)
            initialLot=CalculateLotSize(symbol,false);
            if(level <GridLevelToStart-1)
            {
                double multiplier = GetMultiplierForLevel(level);
                result =baseLot * multiplier;
            }
            else
            {
                if(KeepOriginalProfitLotSize && !AutoSplit)
                {
                    if(level == GridLevelToStart-1)
                    {
                        result =initialLot;
                    }
                    else
                    {
                        double startMultiplier =GetMultiplierForLevel(GridLevelToStart-1);
                        double levelMultiplier =GetMultiplierForLevel(level);
                        result =(initialLot/startMultiplier) * levelMultiplier;



                    }
                }
                else
                {
                    int levelsFromStart = level-(GridLevelToStart -1);
                    double multiplier   = GetMultiplierForLevel(levelsFromStart);
                    result = initialLot * multiplier;
                }
            }

    }
    else
    {
        double multiplier = GetMultiplierForLevel(level);
        result            = baseLot * multiplier;

    }
    //Round to Step size
    int steps = (int)(result/step);
    result   =steps *step;

    //Apply  limits
    if(result < minLot)
        result =minLot;
    
    if(result>maxLot && !AutoSplit)
        result =maxLot;
    
    if(limitLot>Epsilon && result >limitLot)
        result = limitLot;
    
    //Normalize based on digits
    if(step<0.001001 && step >0.000999)         //If step is very close to 0.001 -> normalize to 3 decimal places
        result = NormalizeDouble(result,3);

    else if(step < 0.01001 && step > 0.009999)  //If step is very close to 0.01 -> normalize to 2 decimal places 
        result = NormalizeDouble(result,2);   

    else if(step<0.100001 && step >0.099999)   //If step is very close to 0.1  -> normalize to 1 decimal place
        result= NormalizeDouble(result,1);

    else if(step<1.0000001 && step > 0.999999) //if step is very close to 1 -> normalize to 0 decimal place 
        result =NormalizeDouble(result,0);
    
  return result;

}

double GetMultiplierForLevel(int level)
{
if(level <=0) return 1.0;

double mult =1.0;

for(int i=1; i<=level;i++){
    if(i == 1)

        mult *=TradeMultiplier_2nd;

    else if(i>=2 && i<=4)

        mult *= TradeMultiplier_3rd;
    else
        mult *=TradeMultiplier_6th;
}
return mult;
}


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

            SymbolsArray[i].MaxGridLotMultiplier = CalculateMaxGridLotMultiplier(symbolName);


        }
    }
    else
    {
        ArrayResize(SymbolsArray,1);
        string symbolName =Symbol();
        InitializeSymbolData(0,symbolName);
        SymbolsArray[0].MaxGridLotMultiplier=CalculateMaxGridLotMultiplier(symbolName);
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
void UpdateSymbolInfo(int symbolIndex){
    string symbol=SymbolsArray[symbolIndex].SymbolName;
    SymbolsArray[symbolIndex].UpdateCounter++;

    MqlDateTime tmCurrent;
    TimeToStruct(TimeCurrent(),tmCurrent);
    int currentHour=tmCurrent.hour;
    int currentMinute=tmCurrent.min;
    SymbolsArray[symbolIndex].CurrentBarTime=iTime(symbol,MainTimeframe,0);
    SymbolsArray[symbolIndex].PreviousBarTime=SymbolsArray[symbolIndex].CurrentBarTime;

    bool canTrade=IsTradingAllowed() && AllowOpeningNewGrid; // Here we will check if trading is allowed 
    bool canBuy  =canTrade;
    bool canSell =canTrade;

//Check historical data
    if(iBars(symbol,MainTimeframe)<100)
    {
        Print(TradeComment +" "+ symbol, ":Not enough historical data");
        canBuy=canSell =false;
    }
//Check account balance
    if(AccountInfoDouble(ACCOUNT_MARGIN_FREE)<10.0)
    {
        static datetime lastMarginMsg=0;
        if(TimeCurrent()-lastMarginMsg>3600)
        {
            Print(TradeComment +" " + symbol,":Low Margin:",AccountInfoDouble(ACCOUNT_MARGIN_FREE));
            lastMarginMsg = TimeCurrent();
        }
        canBuy=canSell=false;
    }

//Check UID
    if(UID <0|| UID>9)
    {
        static bool uidMsgPrinted =false;
        if(!uidMsgPrinted)
        {
            Print(TradeComment+" "+symbol,":UID must be 0-9");
            uidMsgPrinted=true;

        }
        canBuy =canSell=false;

    }
//Need at least 2 Bars updates before trading
    if(SymbolsArray[symbolIndex].UpdateCounter<2)
        canBuy = canSell =false;
    
//Check    symbol trading mode
    int tradeMode=(int)SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);
    switch(tradeMode){
        case SYMBOL_TRADE_MODE_DISABLED:canBuy=canSell=false; break;
        case SYMBOL_TRADE_MODE_LONGONLY:canSell=false;break;
        case SYMBOL_TRADE_MODE_SHORTONLY:canBuy=false;break;
    }
//Apply user buy/sell restrictions
    if(AllowToBuySell ==1) canSell =false;
    if(AllowToBuySell==2) canBuy=false;

    //Get bar times

    datetime barTime =SymbolsArray[symbolIndex].CurrentBarTime;
    MqlDateTime tmBar;
    TimeToStruct(barTime,tmBar);
    int barHour  = tmBar.hour;
    int barMinute= tmBar.min;
    int barDay   = tmBar.day;
    int barMonth = tmBar.mon;
    int barYear  = tmBar.year;

    //Trading hours check

    int currentTimeCode =barMinute + barHour * 100;                         
    int startTimeCode   =HourToStartTrading * 100;
    int stopTimeCode    =HourToStopTrading * 100;

    bool timeOk;

    if(stopTimeCode>=startTimeCode)
        timeOk =(currentTimeCode >= startTimeCode && currentTimeCode <= stopTimeCode);
    else
        timeOk=(currentTimeCode>=startTimeCode || currentTimeCode <= stopTimeCode);
    
    //Holiday check - more realistic holiday dates
    if(!AllowTradingOnHolidays)
    {
        //Christmas to New Year week  (Dec 25 -Jan 3)
        if((barMonth==12 && barDay>= 25)|| (barMonth==1 && barDay <=3))
          timeOk=false;

    }
    // Only trade at 15 min boundaries
    timeOk = timeOk  && (barMinute==0 || barMinute==15 || barMinute==30 || barMinute ==45);

    canBuy=canBuy && timeOk;
    canSell=canSell && timeOk;

    //Get close Price
    SymbolsArray[symbolIndex].ClosePrice= iClose(symbol,MainTimeframe,1);

    //Calculate indicators for trading signals
    double maBuffer[1],stdBuffer[1];
    CopyBuffer(handle_MA[symbolIndex],0,1,1,maBuffer);
    CopyBuffer(handle_Std[symbolIndex],0,1,1,stdBuffer);


    double bbMA   = maBuffer[0];
    double bbStd  = stdBuffer[0];
    double bbUpper= bbMA + 2* bbStd;
    double bbLower= bbMA -2 * bbStd;
    
    int highestBar =iHighest(symbol,MainTimeframe,MODE_HIGH,BollingerBandsPeriod+1,2);
    int lowestBar  =iLowest(symbol,MainTimeframe,MODE_LOW,BollingerBandsPeriod+1,2);
    double recentHigh =iHigh(symbol,MainTimeframe,highestBar);
    double recentLow  =iLow(symbol,MainTimeframe,lowestBar);

    //we create digits variable

    int digits= (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
    SymbolsArray[symbolIndex].BBWidth =NormalizeDouble(bbUpper - bbLower,digits);

    //Rsi filter
    if(RSI_period > 0 && RSI_Value>0){
        double rsiBuffer[1];
        CopyBuffer(handle_RSI[symbolIndex],0,1,1,rsiBuffer);
        double rsi=rsiBuffer[0];
        canBuy =canBuy && (rsi<50-RSI_Value);
        canSell=canSell && (rsi>50 + RSI_Value);

    }
    //Price breakout signal
    double close = SymbolsArray[symbolIndex].ClosePrice;
    canBuy       = canBuy && (close<recentLow && recentLow>0);
    canSell      = canSell && (close>recentHigh && recentHigh>0);


    //Max symbol check
    int activeSymbols =0;
    for(int i=0;i<ArraySize(SymbolsArray);i++)
    if(GridExists(SymbolsArray[i].SymbolName,0,0))
        activeSymbols++;
    
    if(activeSymbols>=MaximumSymbols)
        canBuy=canSell=false;

    //Smart distancw multiplier
    if(SmartDistance)
    {
        double atr96Buffer[1],atr672Buffer[1];
        CopyBuffer(handle_ATR96[symbolIndex],0,1,1,atr96Buffer);
        CopyBuffer(handle_ATR672[symbolIndex],0,1,1,atr672Buffer);
        double atr96  =atr96Buffer[0];
        double atr672 =atr672Buffer[0];

        if(atr672 > Epsilon)
        SymbolsArray[symbolIndex].SmartDistanceMultiplier =atr96/atr672;

        //Clamp multiplier
        SymbolsArray[symbolIndex].SmartDistanceMultiplier = MathMin(1.5,MathMax(1.0,SymbolsArray[symbolIndex].SmartDistanceMultiplier));


    }
    //Day Tracking 
    int dayOfWeek = tmBar.day_of_week;
    if(dayOfWeek != SymbolsArray[symbolIndex].LastDayOfWeek && SymbolsArray[symbolIndex].LastDayOfWeek!=0)
    {
        SymbolsArray[symbolIndex].TradingAllowedToday = SymbolsArray[symbolIndex].PreviousDayTradingAllowed;
        SymbolsArray[symbolIndex].PreviousDayTradingAllowed =true;

    }
    SymbolsArray[symbolIndex].LastDayOfWeek = dayOfWeek;

    canBuy =canBuy && SymbolsArray[symbolIndex].TradingAllowedToday;
    canSell=canSell && SymbolsArray[symbolIndex].TradingAllowedToday;

//Margin Level Check
    if(MinimumFreeMargin>Epsilon && AccountInfoDouble(ACCOUNT_MARGIN_LEVEL)<MinimumFreeMargin)
    {
        static  datetime lastMarginLevelMsg =0;
        if(TimeCurrent()-lastMarginLevelMsg>1800)
        {
            Print(TradeComment+": Low margin Level:",AccountInfoDouble(ACCOUNT_MARGIN_LEVEL));
            lastMarginLevelMsg = TimeCurrent();
        }
        canBuy=canSell =false;

    }
    // Drawdown checks
    CheckMaxDrawdown();

    //Apply drawdown restrictions
    if(DrawdownTriggered || StopTradingUntilRestart || DrawdownCooldownHours>0)
    {
        static datetime lastDDMsg=0;
        if(TimeCurrent()-lastDDMsg>3600)
        {
            string reason;
            if(DrawdownTriggered)
                reason="drawdown triggered";
            else if(StopTradingUntilRestart)
                reason ="drawdown - resart required";
            else 
                reason ="drawdown cooldown "+ IntegerToString(DrawdownCooldownHours) + "h";
            Print(TradeComment + " " +symbol,": Trading blocked -",reason);
            lastDDMsg = TimeCurrent();
     
        }
        canBuy=canSell =false;
    }
    
    //Update cooldown counter
    if(LastProcessedHour != currentHour)
        DrawdownCooldownHours--;
    if (DrawdownCooldownHours<0) DrawdownCooldownHours =0;

    //Clear drawdown flag if no positions
    if(DrawdownTriggered)
    {
        double totLots=0;
        for(int i =0; i<ArraySize(SymbolsArray);i++)
            totLots +=GetTotalLotsInGrid(SymbolsArray[i].SymbolName,-1,0,false);
        if(totLots < Epsilon)
            DrawdownTriggered =false;
    }

    //Update symbol State
    SymbolsArray[symbolIndex].CanBuy = canBuy;
    SymbolsArray[symbolIndex].CanSell= canSell;
    SymbolsArray[symbolIndex].GridOpened=false;
    // we update the tick counter 
    TickCounter++;
    LastProcessedHour=currentHour;
    //Try to Open initial Order
    SendInitialOrder(symbolIndex);


}


void SendInitialOrder(int symbolIndex)
{
      string symbol = SymbolsArray[symbolIndex].SymbolName;

      //Quick Permission check
      if(!IsTradingAllowed() || (!SymbolsArray[symbolIndex].CanBuy && !SymbolsArray[symbolIndex].CanSell))
      return;

      //Check Max Symbols limit
      int activeSymbols =0;
      for(int i=0; i<ArraySize(SymbolsArray);i++)
        if(GridExists(SymbolsArray[i].SymbolName,0,0))
            activeSymbols++;
      if(activeSymbols>=MaximumSymbols) return;

      //Check Spread
      double spread = (double)SymbolInfoInteger(symbol,SYMBOL_SPREAD);
      if(spread > MaximumSpread * GetPipMultiplier(symbol) && MaximumSpread > Epsilon)
      {
        Print(TradeComment + " " + symbol,": Spread too high: ",spread);
        return;
      }
      // Try to Open buy order
      if(SymbolsArray[symbolIndex].CanBuy)
      {
        bool hasPosition = AllowHedging ? ! GridExists(symbol,-1,1): ! GridExists(symbol,-1,0);
        if(hasPosition)
            OpenMarketOrder(symbolIndex,ORDER_TYPE_BUY);
      }
      
      //Try to open sell order
      if(SymbolsArray[symbolIndex].CanSell)
      {
        bool hasPosition =AllowHedging ? !GridExists(symbol,-1,-1) : !GridExists(symbol,-1,0);
        if(hasPosition)
            OpenMarketOrder(symbolIndex,ORDER_TYPE_SELL);
      }
}

void OpenMarketOrder(int symbolIndex,ENUM_ORDER_TYPE orderType){
    string symbol = SymbolsArray [symbolIndex].SymbolName;
    int maxAttempts = 10;
    
    for(int attempt = 0; attempt <maxAttempts; attempt++){
        double lotSize =CalculateLotSize(symbol,true);
        if(lotSize < Epsilon)
        {
            Print(TradeComment+""+symbol,": Lot size too small");
            return;

        }

        double margin = 0;
        if(!OrderCalcMargin(orderType,symbol,lotSize,(orderType == ORDER_TYPE_BUY)? SymbolInfoDouble(symbol,SYMBOL_ASK): 
        SymbolInfoDouble(symbol,SYMBOL_BID),margin)
         || margin <=0 || margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
         {
            Print(TradeComment+ " "+ symbol,":Not enough money");
            if(orderType == ORDER_TYPE_BUY)
                SymbolsArray[symbolIndex].CanBuy=false;
            else
                SymbolsArray[symbolIndex].CanSell=false;
                return;

         }

         // Calculate magic number 
         int magicBase = MagicNumberBase + UID;                                       //84570 +0 = 84570
         int digits    = StringLen(IntegerToString(magicBase));                      //5
         int direction =(orderType == ORDER_TYPE_BUY) ? 1 : 2;                      //Buy=> 1 , Sell => 2
         int magic     = (int)MathPow(10,digits+2) * direction + magicBase *100;   //10r7 =10000000 * 1+84570 * 100 
                                                                                    //18457000=> Buy
                                                                                    //28457000=  Sell
          string comment = TradeComment;
          Print(TradeComment + " "+ symbol," : sending "+(orderType==ORDER_TYPE_BUY ? "buy": "sell") +
          "order,attempt" + IntegerToString(attempt + 1));

          Trade.SetExpertMagicNumber(magic);
          Trade.SetDeviationInPoints(MaximumSlippage * GetPipMultiplier(symbol));

          bool success = (orderType==ORDER_TYPE_BUY ? Trade.Buy(lotSize,symbol,0,0,0,comment):
                                                      Trade.Sell(lotSize,symbol,0,0,0,comment));
        // if the order went through
        if(success){
            Print(TradeComment + " "+ symbol,"Order opened,id: ", Trade.ResultOrder());
            //update state
            if(orderType == ORDER_TYPE_BUY)
            {
                SymbolsArray [symbolIndex].CanBuy =false;
                SymbolsArray[symbolIndex].LastBuyGridTime=TimeCurrent();
            }
            else
            {
                SymbolsArray[symbolIndex].CanSell =false;
                SymbolsArray[symbolIndex].LastSellGridTime=TimeCurrent();
            }
            SymbolsArray[symbolIndex].GridOpened   =true;
            SymbolsArray[symbolIndex].OPOTriggered =true;

            return;
            
        }
        else
        {
            uint retcode =Trade.ResultRetcode();
            Print(TradeComment + " "+symbol," Failed to Send order . Retcode",Trade.ResultRetcode()," ", 
                      Trade.ResultRetcodeDescription());

            //Fatal errors -stop trying
            if(retcode  == TRADE_RETCODE_INVALID          ||
               retcode  == TRADE_RETCODE_INVALID_VOLUME   ||
               retcode  == TRADE_RETCODE_NO_MONEY         ||
               retcode  == TRADE_RETCODE_MARKET_CLOSED    ||
               retcode  == TRADE_RETCODE_TRADE_DISABLED
            )
            {
                if(orderType == ORDER_TYPE_BUY)
                    SymbolsArray[symbolIndex].CanBuy =false;
                else
                    SymbolsArray[symbolIndex].CanSell =false;
                return;

            }
            Sleep(5000); // sleep after 5000 seconds

        }
        


    }
     
}

/*===================================================================================================================
                                            Grid Related  Functions
=====================================================================================================================*/
// this is grid exist function to check whether there are grids exixting
bool GridExists(string symbol,int level,int direction){

  for(int i = 0;i<PositionsTotal();i++) // Here we gonna loop through all the positions
  {
    if(!posInfo.SelectByIndex(i))
    {
        Print("OrderSelect failed :",GetLastError());
        continue;
    }
    if(posInfo.Symbol() !=symbol) continue;

    int magic =(int)posInfo.Magic();
    if(!g_magic.IsOurOrder(magic)) continue; //if its not our magic number

    int orderDirection = g_magic.GetDirectionFromMagic(magic);  // Here we are going to store our order either is a buy or sell order 1 for buy -1 for sell

    if(direction == 1 && orderDirection!=1) continue;
    if(direction == -1 && orderDirection != 2) continue;

    int orderLevel = g_magic.GetLevelFromMagic(magic); // Here we are going to check order level
    if(level >=0 && orderLevel != level) continue;  

    //if all matches
    return true;

  }

  //If no position was not found 
  return false;
}


double GetTotalLotsInGrid(string symbol,int level, int direction,bool useOriginalLotSize= false){
    double total    =0;
    double baseLot  =0;

    // Convert direction : 1=buy,-1=sell, 0=both
    int targetDir1  = (direction == 1 || direction ==0) ? 1 : -1;
    int targetDir2  = (direction == -1 || direction ==0) ? 2: -1;

    //If using original profit lot size , find the base lot first
    if(useOriginalLotSize && GridLevelToStart > 1 && !AutoSplit)
    {
        baseLot=FindBaseLotForGrid(symbol,direction);
    }
    //Loop through all orders
    for(int i=0;i<PositionsTotal();i++)
    {
        if(!posInfo.SelectByIndex(i)) continue;

        //wrong symbol? Skip
        if(posInfo.Symbol() !=symbol) continue;

        int magic =(int)posInfo.Magic();

        //Is this our order?
        if(!g_magic.IsOurOrder(magic)) continue;

        //check direction
        int orderDir  =g_magic.GetDirectionFromMagic(magic);
        bool dirMatch =(targetDir1>0 && orderDir==1)|| (targetDir2>0 && orderDir==2);
        if(!dirMatch) continue;

        //Check level
        int orderLevel = g_magic.GetDirectionFromMagic(magic);
        if(level >=0 && orderLevel !=level) continue;
        //if all the above matches

        // Get lot Size
        double lots =posInfo.Volume();

        //Adjust lot size if using original profit size
        if(useOriginalLotSize && baseLot > 0)
        {
            lots = CalculateLotFromBase(baseLot,orderLevel);
        }

        total += lots;
        //Original behavior:if not AutoSplit and level specified, only take first
        if(!AutoSplit && level >=0) break;

    }
    return total;   
}



double FindBaseLotForGrid(string symbol,int direction){

    //Convert direction: 1=buy,-1=sell
    int targetDir = (direction==1) ? 1:2;

    for(int i=0; i<PositionsTotal();i++)
    {
        if(!posInfo.SelectByIndex(i)) continue;

        if(posInfo.Symbol() !=symbol) continue;

        int magic =(int)posInfo.Magic();

        if(!g_magic.IsOurOrder(magic)) continue;

        if(g_magic.GetDirectionFromMagic(magic) != targetDir) continue;

        int level = g_magic.GetDirectionFromMagic(magic);
        if(level == GridLevelToStart-1)
        {
            double lot        =posInfo.Volume();
            double multiplier =GetMultiplierForLevel(level);
            return (multiplier>0) ? lot /multiplier :0;
        }

    }
    //If we could not find any positions
    return 0;
}

double CalculateLotFromBase(double baseLot,int level)
{
    if(baseLot <= 0) return 0;

    return baseLot * GetMultiplierForLevel(level);
}




/*===================================================================================================================
                                            Lot Size Functions
=====================================================================================================================*/




double CalculateLotSize(string symbol,bool isInitialOrder){
    //Here we are going to get alot of information from the broker  like volume 
    double step =SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);   //Get the minimum volume increment (lot step  ) allowed for the symbol
    double minLot =SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);  //Get the minimum lot size allowed by the broker
    double maxLot  =SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);  // Get the Maximum lot size allowed by the broker
    double limitLot =SymbolInfoDouble(symbol,SYMBOL_VOLUME_LIMIT);  // Get the maximum total volume that can be open for the symbol

    if(step < 0.0001) step=0.001;       ///Some brokers may return an invalid volume step. Use 0.01 as a safe default lot increment

    //Get account values
    double freeMargin =AccountInfoDouble(ACCOUNT_MARGIN_FREE);//Get the currently available free margin for opening new positions
    double balance   =AccountInfoDouble(ACCOUNT_BALANCE); //Get the current account balance excluding floating profit or loss
    double equity   =AccountInfoDouble(ACCOUNT_EQUITY);  //We will get the account equity including current profit or loss

    //Use fixed initial deposite for backtesting if enabled instead of live account values 
    
if(FixedInitialDeposit && MQLInfoInteger(MQL_TESTER) && InitialBalance > Epsilon)
    
        freeMargin =InitialBalance; //Set free margin to the configured starting balance
        balance   = InitialBalance; //Override account balance with the configured starting balance
        equity    =InitialBalance; //Override equity with the configured starting balance

        //Get margin requirements with retry (preserving original behaviour)
        double marginRequired = GetMarginRequired(symbol);
        double leverage      =GetLeverage(symbol);
        
        double  lotSize=0;

        // Calculate based on sizing method
        switch(LotSizingMethod)
        {
            case FixedLots :
                 lotSize = LotSizingValueFixed; ///Use a fixed lot size if the User Selects 
                 break;
            case  LotsBalance :
                 lotSize = CalculateLotFromValue(
                    balance,
                    LotSizingValueDynamic,
                    marginRequired,
                    leverage,
                    step
                 ); 
                 break;
            case LotsEquity:
                 lotSize = CalculateLotFromValue(
                    equity,
                    -LotSizingValueDynamic,
                    marginRequired,
                    leverage,
                    step
                 );
                 break;
            case LotsDepositLoad:
                 lotSize = CalculateLotFromDepositLoad(
                    freeMargin,
                    marginRequired,
                    leverage,
                    step
                 );
                 break;
            case ExtremeRiskPreset: // 1.5% load
                 lotSize =CalculateLotFromRisk(
                    freeMargin,
                    marginRequired,
                    leverage,
                    1.5, 
                    step
                    );
                    break;
            case HighRiskPreset : //1.0% load
                    lotSize = CalculateLotFromRisk(
                        freeMargin,
                        marginRequired,
                        leverage,
                        1.0,
                        step
                    );
                    break;
            case MidRiskPreset : //0.5 % load
                    lotSize = CalculateLotFromRisk(
                        freeMargin,
                        marginRequired,
                        leverage,
                        0.5,
                        step);
                    break;
            case  LowRiskPresent://0.25% load
                    lotSize = CalculateLotFromRisk(
                        freeMargin,
                        marginRequired,
                        leverage,
                        0.25,
                        step);
                        break;
                    

        }
        //Apply grid multiplier limit (preserving original logic)
        if(Initialized && !AutoSplit)
        {
            double maxGridMultiplier = GetMaxGridMultiplier();
            if((maxGridMultiplier+1.0)* lotSize > maxLot * 2.0 && maxGridMultiplier + 1.0 >1.0)
                    lotSize =maxLot * 2.0 /(maxGridMultiplier + 1.0);
        }

        //For initial orders  with GridLevelToStart >1, use min lot (preserving original)
        if(GridLevelToStart >1 && isInitialOrder)
            lotSize = minLot;

        //Normalize Lot size using the existing function
        lotSize = NormalizeLotSize(symbol,lotSize);

        return lotSize;
  
}


double CalculateLotFromValue(double accountValue,double divisor,double marginRequired,double leverage,double step){
    if(divisor == 0 || marginRequired < Epsilon || leverage < Epsilon)
     return 0;
    
     double absDivisor = MathAbs(divisor);     //make it absolute incase equity becomes negative value
     double  lots      = accountValue /absDivisor;
     lots              =MathRound(lots * 0.01/step) * step;

     return lots;

}

double CalculateLotFromDepositLoad(double freeMargin,double marginRequired, double leverage,double step)
{
  if(marginRequired < Epsilon || leverage <Epsilon || LotSizingDepositLoadPercent <Epsilon)
  {
    Print(TradeComment + ": Cant't calculate lot size - missing margin/leverage data");
    return 0;
  }
  double lots =MathFloor(100.0 / leverage * freeMargin / marginRequired * LotSizingDepositLoadPercent /100.0 / step)*step;

  return lots;
}  


double CalculateLotFromRisk(double freeMargin,double marginRequired,double leverage,double riskPercent,double step)
{
    if(marginRequired < Epsilon || leverage <Epsilon)
    {
        Print(TradeComment+ ": Cant't calculate lot size- missing margin/leverage data");
        return 0;

    }

    double lots = MathFloor( 100/ leverage * freeMargin / marginRequired * 
        riskPercent /100 / step) *step;
    return lots;

}
double NormalizeLotSize(string symbol,double lotSize)
{
    double step    = SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
    double minLot  = SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);

    lotSize = MathRound(lotSize/step) * step;

    if(lotSize < minLot)
        lotSize=minLot;
    
    int digits =(int)(-MathLog10(step)+0.5);
    
    return  NormalizeDouble(lotSize,digits);
    

}

double GetMaxGridMultiplier()
{
    double maxMultiplier =0;
    for(int i =0; i< ArraySize(SymbolsArray);i++)
    {
        if(SymbolsArray[i].MaxGridLotMultiplier>maxMultiplier)
            maxMultiplier=SymbolsArray[i].MaxGridLotMultiplier;
    }
    return maxMultiplier;
}              

double CalculateMaxGridLotMultiplier(string symbolName)
{
    double startLot =0.1;
    double totLots  =0.1;

    for(int level =1; level<=MaximumTrades - 1; level ++)
    {
        totLots =totLots + CalculateGridLotSize(symbolName,startLot,level,0.0);
    }

    if(startLot>Epsilon)
        return totLots /startLot;
    
    else
    return 0.0;

    
}





/*===================================================================================================================
                                            Tp and Sl Related Functions
=====================================================================================================================*/
void ModifyGridTPsl(int symbolIndex)
{

}








/*===================================================================================================================
                                            Closing the Grids/Trades /DrawDowns
=====================================================================================================================*/

void CheckMaxDrawdown(){
    
}







/*===================================================================================================================
                                            General  Helping Functios
=====================================================================================================================*/
bool IsTradingAllowed(){
    if(MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION)) // Here we are checking whether it is MQL_tester or MQl optimization 
    return true;

    int allowed =(int) TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);//If it is a live enviroment we create a varible allowed
    if(allowed==0)
     return false;

     allowed =(int)AccountInfoInteger(ACCOUNT_TRADE_EXPERT);  // checking account expert if it is allowed
     if(allowed==0)
     return false;

     allowed =MQLInfoInteger(MQL_TRADE_ALLOWED);
     if(allowed==0)
     return false;

    return true;

}

int GetPipMultiplier(string symbol)
{
    int digits =(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
    if(digits==5 || digits ==3)
        return 10;
    return 1;
}

//Calculate the margin required to open a position
double GetMarginRequired( string symbol)
{
    double margin =0;   //Here we store the calculated margin required
    int   attempts=0;   //Here we track the number of retrival attempts

    //Retry until margin is obtained ,maximum attempts reached or symbol is invalid

    while(margin<Epsilon && attempts < 3 && symbol !="??????")
    {
        attempts++;// Here we will increment retry counter 

        if(attempts ==1) Sleep(100); //Here we will wait breifly before the first retry
        if(attempts  ==2) Sleep(1000);  // Here we will increase delay before the send retry
        if(attempts  ==3)  Sleep(2000); //Here  we Will allow additional time  before the final retry

        if(!OrderCalcMargin(
            ORDER_TYPE_BUY,
            symbol,
            1.0,
            SymbolInfoDouble(symbol,SYMBOL_ASK),margin)) 
            margin=0;//Calculate margin required for a 1 lot Buy order 
        if(attempts ==3 && margin <Epsilon)
           Print(
            TradeComment +" "+symbol, ":Failed to get MODE_MARGINREQUIRED after 3 attempts"
           );

    }
    //Return the calculated margin requirement
    return margin;
}

//Retrieve the account leverage for position sizing calculation
double GetLeverage (string symbol){

    double lev = (double)AccountInfoInteger(ACCOUNT_LEVERAGE);//Here we will store the account leverage level
    
    int attempts =0; //Here we will track the number of retrival attempts

    while(lev<Epsilon && attempts < 3 && symbol !="????") //Here we will Retry if leverage information is unavailable
    {
        attempts++;   //This is the increment retry counter

        if(attempts == 1)  Sleep(100); //Here we will have a short delay before first retry
        
        if(attempts == 2)  Sleep(1000); //Here we will have a longer delay before second retry

        if(attempts == 3)  Sleep(2000); //Final delay before last retry

        lev =(double)AccountInfoInteger(ACCOUNT_LEVERAGE);  // Here we request leverage information again

        if(attempts == 3 && lev < Epsilon)
             Print(TradeComment +" "+ symbol,":Failed to get ACCOUNT_LEVERAGE after 3 attempts"); //log an error if leverage could not be retrived 
        


    }
    return lev; // return the account leverage value

}

bool SplitAndOpenOrders(int symbolIndex,ENUM_ORDER_TYPE orderType,int level,double totalLotSize)
{
   string symbol       = SymbolsArray[symbolIndex].SymbolName;
   double maxLot       = GetMaxLot(symbol);
   int    numOrders    =(int)MathCeil(totalLotSize/maxLot);
   double remainingLots=totalLotSize;
   bool   allSuccess   =true;

// we Loopt through the orders we are starting to send
    for(int i=0;i<numOrders;i++){
        double lotSize  = MathMin(maxLot,remainingLots);
        lotSize         = NormalizeLotSize(symbol,lotSize);

        if(!SendGridOrder(symbolIndex,orderType,level,lotSize))
            allSuccess =false;
        
        remainingLots -= lotSize;
        Sleep(500);
    }

    return allSuccess;

}

double GetMaxLot(string symbol)
{
     double maxLot   = SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);     // Max value per ORDER
     double limitMax = SymbolInfoDouble(symbol,SYMBOL_VOLUME_LIMIT);   // Max value per symbol broker allows 

     if(limitMax >0 && limitMax < maxLot)
        maxLot = limitMax;
    
    return MathMin(maxLot,MaximumLot);

      
}

