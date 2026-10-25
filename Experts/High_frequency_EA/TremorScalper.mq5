


#property copyright "Copyright 2025,Mikey"
#property link      "https:// www.tremorBeast.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
CTrade           trade;      // This is to do buying and selling 
CPositionInfo    posinfo;    // This is to get open positions 
COrderInfo       ordinfo;    // This is to get infomation of order placed
CHistoryOrderInfo  hisinfo;  // This is used to get the histolical orders
CDealInfo          dealinfo;  //Tjis is to get all the deals inforamtion wer can get
// give the user option to select whether to choose what lot type he/she wnats to use we use enum
enum enumLotType{Fixed_lots=0,Pct_of_balance=1,Pct_of_Equity=2,Pct_of_free_margin=3};

// General Settings'
input group "GENERAL SETTINGS";

   input int InpMagic   = 123445;      ///Magic Number
   input int Slippage   = 30;         


input group "TIME SETTINGS";
   input int StartHour  = 16;    //START TRADING HOUR
   input int EndHour    = 22;    //END TRADING HOUR
   input int Secs       = 60;    // Order MoDiFICATION(should be same as TF)

input group "MONEY MANAGEMENT ";
   input enumLotType LotType    = 0;  // type of lotsize calculation
   input double  FixedLot       = 0.01; //Fixed lot 0.0 =MM
   input double  RiskPercentage = 0.5; // Risk MM%EAModeFlag

input group "TRADE SETTING IN POINTS"; ///TRADE SETTINGS
      input double Delta        = 10; //ORDER DISTANCE 
      input double MaxDistance  = 15; //THETA (MAX order Distance)
      input double Stop         = 30; // Stop Loss Size WILL BE MULTIPLIED WITH THE SPREAD OF THE BROKER
      input double MaxTrailing  = 4;  //COS(Start of Trailing Stop)
      input int    MaxSpread    = 40; //Max  Spread Limit

// Add new trailing Method
input group "====Trailing Stop Management or Take Profit======";

    enum TSLType { Default_trail = 0,ScalpTrail = 1,Previous_Candle = 2,Fast_MA = 3,TenkanSen = 4,TakeProfit = 5};//This Is to add New Trailing methods Trailing PreviousCandle=2 this will helpto trail According to Previous Candle
    input TSLType   TrailType     = 1 ;   // type of Trailing StopLoss;

input group "=== If Trailing as Scalping Trailing==="
    input int TslTriggerPoints  = 15 ; /// Points in Profit before Trailing Starts ( 10 points = 1 pip);    
    input int TslPoints         = 10 ; // Trailing Distance in Points  (10 points = 1 pip) ;

input group "== If Trailing by Previous Candle ===";
    input int PrvCandleN        = 1  ;  // No of candles to trail SL (if selected)

input group "=== If Trailing by Fast Moving Average ==";
    input int              FMAperiod        = 5   ;      //Fast-moving avg period to trail on (if selected)
    input ENUM_MA_METHOD   MA_Mode          = MODE_EMA ; // moving Average Mode/Method
    input ENUM_APPLIED_PRICE Ma_AppPrice    = PRICE_MEDIAN; // Moving Avg Applied Price

    int handleTrailMA, handleIchimoku;

input group "=== If Take Profit is Selected ==== " 
    input int TakeProfite  = 0;    /// Here the user will set the take Profit in Points

/// CREATING VARIABLES THIS ARE NOT USER DEFINED

double DeltaX = Delta;

double MinOrderDistance        = 5;
double MaxTrailingLimit        = 7.5;
double OrderModificationFactor = 3;
int    TickCounter             = 0;
double PriceToPipRatio         = 0;

///Trailing stop 
double BaseTrailingStop        =0;
double TrailingStopBuffer      =0;
double TrailingStopIncrement   =0;
double TrailingStopThreshold   =0;
long   AccountLeverageValue    =0;

///Lotsize calculations
double LotStepSize             =0;
double MaxLotSize              =0;
double MinLotSize              =0;
double MarginPerMinLot         =0;
double MinStopDistance         =0;

int     BrokerStopLevel        =0;
double  MinFreezeDistance      =0;
int     BrokerFreezeLevel      =0;
double  CurrentSpread          =0;
double  AverageSpread          =0;

int     EAModeFlag             =0;
int     SpreadArraySize        =0;
int     DefaultSpreadPeriod    =30;
double  MaxAllowedSpread       =0;
double  CalculatedLotSize      =0;

double CommissionPerPip        =0; //Get commision from historical deals
int    SpreadMultiplier        =0;
double AdjustedOrderDistance   =0;
double MinOrderModification    =0;
double TrailingStopActive      =0;


double TrailingStopMax           =0;
double MaxOrderPlacementDistance =0;
double OrderPlacementStep        =0;
double CalculatedStoploss        =0;
bool   AllowBuyOrders            =false;


bool AllowSellOrders             =false;
bool SpreadAcceptable            =false;
int  LastOrderTimeDiff           =0;
int  LastOrderTime               =0;
int  MinOrderIntervel            =0;

double CurrentBuySL              =0;
string OrderCommentText          ="Tremor Beast Scalper";
int    LastBuyOrderTime          =0;
bool   TradeAllowed              =false;
double CurrentSellSl             =0;


int    LastSellOrderTime       =0;
int    OrderCheckFrequency     =2;
int    SpreadCalculationMethod =1;
bool   EnableTrading           =false;
double SpreadHistoryArray[];

int OnInit(){
   trade.SetExpertMagicNumber(InpMagic);
   ChartSetInteger(0,CHART_SHOW_GRID,false);

/// V2 changes = adding handles for Trailing on Ma and Ichimoku
//=============================================================
    if(TrailType== 3) handleTrailMA  = iMA(_Symbol,PERIOD_CURRENT,FMAperiod,0,MA_Mode,Ma_AppPrice);
    if(TrailType== 4) handleIchimoku = iIchimoku(_Symbol,PERIOD_CURRENT,9,26,52);
//=============================================================


   if((MinOrderDistance>Delta)){///This is to ensure That User does not Put a very very Small Number and if he does Than it is over_ridden by
      DeltaX=(MinOrderDistance+0.1);///the values we set in the Global "MinOrderDistance=5" variable 
   }                                   
   if((MaxTrailing>MaxTrailingLimit)){
      MaxTrailingLimit=(MaxTrailing+0.1);
   }
   if((OrderModificationFactor<1)){
      OrderModificationFactor=1;
   }
   TickCounter      = 0;
   PriceToPipRatio  = 0;
   BaseTrailingStop = TrailingStopBuffer;
   TrailingStopIncrement =TrailingStopThreshold;
   AccountLeverageValue  = AccountInfoInteger(ACCOUNT_LEVERAGE);

   LotStepSize            = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);  // lotsize allowed by broker in that Pair
   MaxLotSize             = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);  //Maximum Lot size allowed by Broker in that Pair
   MinLotSize             = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);    // This code is to check the minimum lotsize broker allows in that pair
   MarginPerMinLot        = SymbolInfoDouble(_Symbol,SYMBOL_MARGIN_INITIAL)*MinLotSize;
   MinStopDistance        = 0 ;

   //Get the Value of Broker Stop Level
   BrokerStopLevel = (int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   if(BrokerStopLevel>0) MinStopDistance =(BrokerStopLevel + 1)*_Point; 

   // This will help determine whether a broker has freeze level if so we add 1 to add a buffer
   MinFreezeDistance=0;
   BrokerFreezeLevel = (int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   if(BrokerFreezeLevel>0)MinFreezeDistance = (BrokerFreezeLevel + 1)* _Point;

   if(BrokerStopLevel>0 || BrokerFreezeLevel>0){
      Print("WARNING! Broker is not Sutable, The stoplevel is greater than Zero");
   }

   //spread calculation
   double Ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double Bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);

   CurrentSpread = NormalizeDouble(Ask - Bid, _Digits);
   AverageSpread = CurrentSpread;

   SpreadArraySize = (EAModeFlag == 0) ? DefaultSpreadPeriod : 3; //if EMAModeFlag==0, then DefaultSpreadPeriod else 3;

   ArrayResize(SpreadHistoryArray,SpreadArraySize,0); //This is to Store the Spread History Data 


   MaxAllowedSpread = NormalizeDouble((MaxSpread * _Point),_Digits);
   // This is to Hide the Indictors
   TesterHideIndicators(true);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){

}
// price data will be run on every tick in mql
void OnTick(){

   //local Variables
   int CurrentTime            = (int) TimeCurrent();
   int PendingBuyCount        =  0;
   int PendingSellCount       =  0;
   int OpenBuyCount           =  0;
   int OpenSellCount          =  0;
   int TotalBuyCount          =  0;
   int TotalSellCount         =  0;
   double OrderLotsValue      =  0;
   double OrderStopLossValue  =  0;
   double OrderTakeProfitValue=  0;
   double OrderOpenPriceValue =  0;
   double NewOrderTakeProfit  =  0; // Take Profit
   double BuyOrdersPriceSum   =  0;
   double BuyOrdersLotSum     =  0;
   double SellOrdersPriceSum  =  0;
   double SellOrdersLotSum    =  0;
   double AverageBuyPrice     =  0;
   double AverageSellPrice    =  0;
   double LowestBuyPrice      =  99999;
   double HighestSellPrice    =  0;

TickCounter++;

if(PriceToPipRatio==0){
   HistorySelect(0,TimeCurrent());
   for(int i =HistoryDealsTotal()-1; i>=0; i--){
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      if(HistoryDealGetString(ticket,DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetDouble(ticket,DEAL_PROFIT) == 0) continue;
      if(HistoryDealGetInteger(ticket,DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      ulong posID  = HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
      if (posID == 0) continue;

      //Find the Corresponding entry deal
      if(HistoryDealSelect(posID)){
         double entryPrice = HistoryDealGetDouble(posID,DEAL_PRICE);
         double exitPrice  = HistoryDealGetDouble(ticket, DEAL_PRICE);
         double profit     = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         double commission = HistoryDealGetDouble(ticket,DEAL_COMMISSION);

         if (exitPrice != entryPrice){
            PriceToPipRatio = fabs(profit/(exitPrice - entryPrice));// this will return the negative value to positve
            CommissionPerPip = -commission / PriceToPipRatio;
            break;
         }
      }
   }

double Ask  = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
double Bid  = SymbolInfoDouble(_Symbol,SYMBOL_BID);


/// Update Spread history Array
double newSpread = NormalizeDouble(Ask-Bid,_Digits);
ArrayCopy(SpreadHistoryArray,SpreadHistoryArray,0,1,SpreadArraySize - 1); /// This will delete the oldest value 
SpreadHistoryArray[SpreadArraySize -1]   = newSpread;

//calculate  MA of Spreads
double sum =0;
for(int i=0; i < SpreadArraySize; i++){
   sum += SpreadHistoryArray[i];
}
CurrentSpread = sum / SpreadArraySize; // getting the average spread

//  calcurate average Spread including commission
AverageSpread = MathMax(SpreadMultiplier * _Point, CurrentSpread + CommissionPerPip);

// calculate order distance
AdjustedOrderDistance  = MathMax(AverageSpread * Delta, MinStopDistance);
MinOrderDistance       = MathMax(AverageSpread * MinOrderDistance,MinFreezeDistance);

//calculate Trailing stop values
TrailingStopActive         = AverageSpread *  MaxTrailing;  // Trailing will become Active on this conditions
TrailingStopMax            = AverageSpread  * MaxTrailingLimit; 
MaxOrderPlacementDistance  = AverageSpread * MaxDistance;
OrderPlacementStep         = MinOrderModification / OrderModificationFactor; 
CalculatedStoploss         = MathMax(AverageSpread * Stop, MinStopDistance);   

//function to see how many Trades are currently open

for(int i = PositionsTotal()-1; i>= 0; i--){
   if(posinfo.SelectByIndex(i) && posinfo.Symbol() == _Symbol && posinfo.Magic() == InpMagic){
     
      double price = posinfo.PriceOpen();
      double lots  = posinfo.Volume();
      double sl    = posinfo.StopLoss();


      // here we increase the amount of buy as the market moves up  to 1 
      if(posinfo.PositionType() == POSITION_TYPE_BUY){
         OpenBuyCount++;
         if(sl==0 || (sl >0 && sl < price)) TotalBuyCount++;
         CurrentBuySL = sl;
         BuyOrdersPriceSum += price * lots;
         BuyOrdersLotSum   += lots;
         if(price < LowestBuyPrice) LowestBuyPrice=price;
      }
      // increase the sell posistions by one 
      else if(posinfo.PositionType()== POSITION_TYPE_SELL){
         OpenSellCount++;
         if(sl==0 || (sl > 0 && sl > price)) TotalSellCount++;
         CurrentSellSl = sl;
         SellOrdersPriceSum += price * lots;
         SellOrdersLotSum += lots;
         if(price > HighestSellPrice) HighestSellPrice = price;
      }

   }
}
for(int i= OrdersTotal()-1; i>=0; i--){
   if(ordinfo.SelectByIndex(i) && ordinfo.Symbol() == _Symbol && ordinfo.Magic() == InpMagic){
      if(ordinfo.OrderType() == ORDER_TYPE_BUY_STOP){
         PendingBuyCount++;
         TotalBuyCount++;
      }
      else if(ordinfo.OrderType() == ORDER_TYPE_SELL_STOP){
         PendingSellCount++;
         TotalSellCount++;
      }

   }
}

if ((BuyOrdersLotSum>0)){
   AverageBuyPrice=NormalizeDouble((BuyOrdersPriceSum / BuyOrdersLotSum),_Digits);
   
}
if((SellOrdersLotSum>0)){
   AverageSellPrice = NormalizeDouble((SellOrdersPriceSum / SellOrdersLotSum),_Digits);
}

//create a variable
MqlDateTime BrokerTime;
TimeCurrent(BrokerTime);
// processing the pedding Orders

for(int i = OrdersTotal()-1; i>=0; i--){
   if(!ordinfo.SelectByIndex(i)) continue;
   if(ordinfo.Symbol() != _Symbol || ordinfo.Magic() != InpMagic)continue;
   ulong ticket = ordinfo.Ticket();
   ENUM_ORDER_TYPE type =ordinfo.OrderType();
   double openPrice = ordinfo.PriceOpen();
   double sl = ordinfo.StopLoss();
   double tp = ordinfo.TakeProfit();
   double lots = ordinfo.VolumeCurrent();

   //Process buy limit Orders
   if(type == ORDER_TYPE_BUY_STOP){
      bool allowTrade = (BrokerTime.hour>= StartHour && BrokerTime.hour <= EndHour);
      if(AverageSellPrice> MaxAllowedSpread || ! allowTrade){
         trade.OrderDelete(ticket);
         continue;
      }
      // Check the time Different between the last Buy order
      int timeDiff =(int)(CurrentTime-LastBuyOrderTime);
      // this is for order modification and tick counts 
      bool needsModification = (timeDiff > Secs) ||(TickCounter % OrderCheckFrequency 
      == 0 && ((OpenBuyCount < 1 && (openPrice - SymbolInfoDouble(_Symbol,SYMBOL_ASK)) < MinOrderModification) 
      || (openPrice - SymbolInfoDouble(_Symbol,SYMBOL_ASK)) < OrderPlacementStep 
      || (openPrice - SymbolInfoDouble(_Symbol,SYMBOL_ASK)) > MaxOrderPlacementDistance));

      if(needsModification == true){
         double distance = AdjustedOrderDistance;
         if(OpenBuyCount>0) distance/= OrderModificationFactor;
         distance      = MathMax(distance,MinStopDistance);
         double modifiedPrice = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK) + distance,_Digits);
         double modifiedSl    = (OpenBuyCount > 0) ? CurrentBuySL : NormalizeDouble(modifiedPrice - CalculatedStoploss,_Digits);

         if((OpenBuyCount == 0 || modifiedPrice> AverageBuyPrice) &&
          modifiedPrice != openPrice && (openPrice - SymbolInfoDouble(_Symbol,SYMBOL_ASK)) > MinFreezeDistance){
            trade.OrderModify(ticket,modifiedPrice,modifiedSl,tp,0,0);
            LastBuyOrderTime = CurrentTime;
          }
      }
   }
   /// Process   sell stop orders
   else if (type == ORDER_TYPE_SELL_STOP){
      bool allowTrade = (BrokerTime.hour >= StartHour && BrokerTime.hour <= EndHour);
      if(AverageSpread > MaxAllowedSpread || !allowTrade){
         trade.OrderDelete(ticket);
         continue;
      }
   }

   int timeDiff =(int)(CurrentTime - LastSellOrderTime);
   bool needsModification =(timeDiff > Secs) ||
    (TickCounter % OrderCheckFrequency == 0 && ((OpenSellCount < 
      1 && (SymbolInfoDouble(_Symbol,SYMBOL_BID)-openPrice)<MinOrderModification) || (SymbolInfoDouble(_Symbol,SYMBOL_BID) - openPrice) < OrderPlacementStep 
      || (SymbolInfoDouble(_Symbol,SYMBOL_BID) - openPrice) > MaxOrderPlacementDistance));

   if(needsModification == true){
      double distance = AdjustedOrderDistance;
      if(OpenSellCount > 0) distance /= OrderModificationFactor;
      distance         = MathMax(distance,MinStopDistance);

      double modifiedPrice = NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_BID)- distance, _Digits);
      double moodifiedSl =  (OpenSellCount>0) ? CurrentSellSl : NormalizeDouble(modifiedPrice + CalculatedStoploss,_Digits);

      if((OpenSellCount == 0 || modifiedPrice < AverageSellPrice) && modifiedPrice != openPrice && 
         (SymbolInfoDouble(_Symbol,SYMBOL_BID) - openPrice) > MinFreezeDistance){  
            trade.OrderModify(ticket,modifiedPrice,moodifiedSl,tp,0,0);
            LastSellOrderTime = CurrentTime;    
         }

   }

}

// Chage in V2 - All Trailing moved to TrailStop() function
//======================================================
TrailStop();
///====================================================
if((OrderModificationFactor > 1 && TotalBuyCount < 1) || OpenBuyCount < 1){
   if(PendingBuyCount < 1){
      bool SpreadOK  = (AverageSpread <= MaxAllowedSpread);
      bool timeOk    = (BrokerTime.hour >= StartHour && BrokerTime.hour <= EndHour);
      if(SpreadOK && timeOk && (CurrentTime - LastOrderTime) > MinOrderIntervel && EAModeFlag == 0){
         //Lot Size calculation
         if(LotType == 0){
            CalculatedLotSize = MathCeil(FixedLot/LotStepSize) * LotStepSize;
            CalculatedLotSize = MathMax(CalculatedLotSize,MinLotSize); // Enforce minimum 
         } else if(LotType > 0){
            CalculatedLotSize = calcLots(CalculatedStoploss);      
         }
         double marginRequired = 0.0;
         double ask            = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         if(OrderCalcMargin(ORDER_TYPE_BUY_STOP, _Symbol, CalculatedLotSize,ask,marginRequired) && 
         AccountInfoDouble(ACCOUNT_MARGIN_FREE)>marginRequired){
            // calculate order price and SL
            double orderDist = MathMax(MathMax(AdjustedOrderDistance,MinFreezeDistance),MinStopDistance);
            double orderPrice = NormalizeDouble(ask + orderDist, _Digits);
            // Create Pending Buy:
            //Anchor the initial SL to this order own entry price
            //Buy Sl = this Pending Buy entry - calculated Stop distance
            // Here was to remove the newly created SL from placing to the current executed order price 

            double orderSl =NormalizeDouble(orderPrice - CalculatedStoploss,_Digits);
            // send the order
            if(trade.OrderOpen(_Symbol, ORDER_TYPE_BUY_STOP, CalculatedLotSize,orderPrice, ask,
                orderSl, NewOrderTakeProfit,0,0, OrderCommentText)){
               LastBuyOrderTime = (int) TimeCurrent();
               LastOrderTime    = (int) TimeCurrent();
            }
         }

      }

   }

}
// same logic for sell trades

if((OrderModificationFactor> 1 && TotalSellCount < 1) || OpenSellCount < 1){
 if(PendingSellCount < 1){
   bool spreadOk = (AverageSpread <= MaxAllowedSpread);
   bool timeOk   = (BrokerTime.hour >= StartHour && BrokerTime.hour <= EndHour);

   if(spreadOk && timeOk && (CurrentTime - LastOrderTime)> MinOrderIntervel && EAModeFlag == 0){
      // lot Size calculation
      if(LotType == 0){
         CalculatedLotSize = MathCeil(FixedLot / LotStepSize) * LotStepSize;
         CalculatedLotSize = MathMax(CalculatedLotSize, MinLotSize); // enforce Minimum

      }
      else if (LotType > 0 ){
         CalculatedLotSize = calcLots(CalculatedStoploss);
      }

      double marginRequired = 0.0;
      double bid =SymbolInfoDouble(_Symbol,SYMBOL_BID);
      if(OrderCalcMargin(ORDER_TYPE_SELL_STOP,_Symbol,CalculatedLotSize,bid,marginRequired)
       && AccountInfoDouble(ACCOUNT_MARGIN_FREE) > marginRequired){
         double orderDist = MathMax(MathMax(AdjustedOrderDistance,MinFreezeDistance), MinStopDistance);
         double orderPrice = NormalizeDouble(bid - orderDist,_Digits);  // placing the orders below the price

         /// Current Pending Buy
         // Anchor the initial SL to this orders own entry Price
         // SELL Sl = this pending Sell entry + calculated Stop distance
         //(OpenSellCount > 0) ? CurrentSellSl : this was the fix 

         double orderSl =  NormalizeDouble(orderPrice + CalculatedStoploss,_Digits); // placement of stop loss of order
         if(trade.OrderOpen(_Symbol,ORDER_TYPE_SELL_STOP, CalculatedLotSize,orderPrice,bid,orderSl, NewOrderTakeProfit, 0,0, OrderCommentText))
         {
            LastSellOrderTime =(int) TimeCurrent();
            LastOrderTime     = (int) TimeCurrent();
         }
       }
   }
 }
}
}
}


//// any special function will be run on here 
/// function for Trail Distance
double  CalculateTrailingStop(double priceMove, double minDist,double activeDist,double baseDist,double maxDist)
{

if (maxDist == 0) return MathMax(activeDist,minDist);
double ratio  = priceMove / maxDist;
double dynamicDist = (activeDist - baseDist) * ratio + baseDist;
return MathMax(MathMin(dynamicDist,activeDist),minDist);

}


// calculating the Lot

double calcLots(double slPoints){
   double lots = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double AccountBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double EquityBalance   = AccountInfoDouble(ACCOUNT_EQUITY);
   double FreeMargin      = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   double risk =0;
   switch (LotType){
      case 0: lots = Fixed_lots; return lots;
      case 1: risk = AccountBalance * RiskPercentage / 100 ; break;
      case 2: risk = EquityBalance  * RiskPercentage / 100 ; break;
      case 3: risk = FreeMargin    *  RiskPercentage   / 100; break;

   }

   double ticksize  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickvalue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double lotstep   = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   double moneyPerLotstep = slPoints / ticksize * tickvalue * lotstep;
   lots                   = MathFloor(risk / moneyPerLotstep)* lotstep;

   double minvolume = SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
   double maxvolume = SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX);
   double volumelimit = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_LIMIT);

   if(volumelimit != 0) lots = MathMin(lots,volumelimit);
   if(maxvolume   != 0) lots = MathMin(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX));
   if(minvolume   != 0) lots = MathMax(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN));
   lots = NormalizeDouble(lots,2);
   return lots;
}
// we gonna call this function on every tick
void TrailStop(){
// Here if the trail is default
   if(TrailType==0){
// Process Open Positions
for(int i = PositionsTotal() - 1; i>=0; i--){
   if(!posinfo.SelectByIndex(i)) continue;
   if(posinfo.Symbol() != _Symbol || posinfo.Magic() != InpMagic) continue;

   ulong ticket = posinfo.Ticket();
   ENUM_POSITION_TYPE type = posinfo.PositionType();
   double openPrice = posinfo.PriceOpen();
   double sl        = posinfo.StopLoss();
   double tp       = posinfo.TakeProfit();


   // process buy positions

   if(type == POSITION_TYPE_BUY){
      double priceMove  = MathMax(SymbolInfoDouble(_Symbol,SYMBOL_BID) - openPrice + CommissionPerPip,0);
      double trailDist  = CalculateTrailingStop(priceMove,MinStopDistance,TrailingStopActive,BaseTrailingStop,TrailingStopMax);
      double modifiedSl = NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_BID)- trailDist, _Digits); // modify the stoploss
      double triggerLevel = openPrice + CommissionPerPip + TrailingStopIncrement;

      if((SymbolInfoDouble(_Symbol,SYMBOL_BID) - triggerLevel ) > trailDist && 
      (sl == 0 || (SymbolInfoDouble(_Symbol,SYMBOL_BID) - sl) > trailDist) && modifiedSl != sl){
         trade.PositionModify(ticket, modifiedSl,tp);
      }

   }
   //process Sell positions
   else if(type == POSITION_TYPE_SELL){
      double priceMove =  MathMax(openPrice - SymbolInfoDouble(_Symbol,SYMBOL_ASK) - CommissionPerPip, 0);
      double trailDist = CalculateTrailingStop(priceMove,MinStopDistance,TrailingStopActive,BaseTrailingStop,TrailingStopMax);
      double modifiedSL = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK) + trailDist, _Digits);
      double triggerLevel = openPrice - CommissionPerPip - TrailingStopIncrement;
      if((triggerLevel - SymbolInfoDouble(_Symbol, SYMBOL_ASK))> trailDist && (sl==0 || (sl-SymbolInfoDouble(_Symbol,SYMBOL_ASK)) > trailDist) && modifiedSL != sl){
         trade.PositionModify(ticket, modifiedSL ,tp);
      }
   }

 } return; // This is to make sure it does not get past the default Trail;
}

//=============================================
// Version 2 Changes = Adding all the other Trailing Stop methods
double sl        = 0;
double tp        = 0;
double ask       = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
double bid       = SymbolInfoDouble(_Symbol,SYMBOL_BID);
double stopLevel = (int) SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
double indbuffer [];

for(int i=PositionsTotal()-1; i>=0;i--){
   if(posinfo.SelectByIndex(i)){
      ulong ticket = posinfo.Ticket();
      if(posinfo.Magic()==InpMagic && posinfo.Symbol() == _Symbol){
         if(posinfo.PositionType()==POSITION_TYPE_BUY){
            if(bid-posinfo.PriceOpen()>TslTriggerPoints*_Point){
               tp = posinfo.TakeProfit();

               switch(TrailType){
                  case 1: sl = bid- (TslPoints * _Point);
                           break;
                  case 2 : sl =iLow(_Symbol,PERIOD_CURRENT,PrvCandleN);
                           break;
                  case 3 : CopyBuffer(handleTrailMA,MAIN_LINE,1,1,indbuffer); ///trailing using FastMA if selected
                           ArraySetAsSeries(indbuffer,true);
                           sl = NormalizeDouble(indbuffer[0],_Digits);
                           break;
                  case 4 : CopyBuffer(handleIchimoku,TENKANSEN_LINE,1,1,indbuffer); // Traling using ICHimoku if selected
                           ArraySetAsSeries(indbuffer,true);
                           sl = NormalizeDouble(indbuffer[0],_Digits);
                           break;    

                            
               }
               if(sl > posinfo.StopLoss() && sl !=0 && sl > posinfo.PriceOpen() && sl < bid){
                  trade.PositionModify(ticket,sl,tp);
               }

            }
            else if (posinfo.PositionType() == POSITION_TYPE_SELL){
               if(ask + (TslTriggerPoints * _Point)< posinfo.PriceOpen()){
                  tp = posinfo.TakeProfit();
                  switch(TrailType){
                     case 1:  sl=ask + (TslPoints * _Point);
                              break;

                     case 2:  sl =iHigh(_Symbol,PERIOD_CURRENT,PrvCandleN);
                              break;//this will get the high of the previous candle as trail
                     case 3:  CopyBuffer(handleTrailMA,MAIN_LINE,1,1,indbuffer);
                              ArraySetAsSeries(indbuffer,true);
                              sl = NormalizeDouble(indbuffer[0],_Digits);
                              break;
                     case 4:  CopyBuffer(handleIchimoku,TENKANSEN_LINE,1,1,indbuffer);
                              ArraySetAsSeries(indbuffer,true);
                              sl = NormalizeDouble(indbuffer[0],_Digits);
                              break;

                  }  if( sl < posinfo.StopLoss() && sl!=0 && sl < posinfo.PriceOpen() && sl > ask){
                     trade.PositionModify( ticket,sl,tp);
                  } 

               }
            }
         }
      }

   }
}
}
