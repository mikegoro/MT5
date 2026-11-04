//+------------------------------------------------------------------+
//|                        High Frequency EA cleaned up by Mr CapFree |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Mr. CapFree"
#property link      "https://www.mrCapFree.com"
#property version   "1.00"

#include        <Trade\Trade.mqh>
   CTrade            trade;
   CPositionInfo     posinfo;
   COrderInfo        ordinfo;
   CHistoryOrderInfo hisinfo;
   CDealInfo         dealinfo;

   enum enumLotType{Fixed_Lots=0, Pct_of_Balance=1, Pct_of_Equity=2, Pct_of_Free_Margin=3};
   // this to select Hours to trade it will appear like a drop down 
enum trading_hours{Inactive=0,_0100=1,_0200=2,_0300=3,_0400=4,_0500=5,_0600=6,_0700=7,_0800=8,
   _0900=9,_1000=10,_1100=11,_1200=12,_1300=13,_1400=14,_1500=15,_1600=16,_1700=17,_1800=18,
   _1900=19,_2000=20,_2100=21,_2200=22,_2300=23};

input group "GENERAL SETTINGS"; // General Settings

   input int InpMagic = 12345; // Magic Number
   input int Slippage = 1;

input group "TIME SETTINGS";
    input trading_hours StartHour  = _1000;    //START TRADING HOUR
   input trading_hours EndHour    = _2200;    //END TRADING HOUR
   input int Secs = 60; // ORDER MODIFICATIONS (Should be same as TF)

input group "MONEY MANAGEMENT"; // MONEY MANAGEMENT
   input enumLotType LotType = 0; // Type of Lotsize calculation
   input double FixedLot = 0.01; // Fixed Lots 0.0 = MM
   input double RiskPercent = 0.5; // Risk MM%

input group "TRADE SETTING IN POINTS"; // TRADE SETTINGS
   input double Delta = 15; // ORDER DISTANCE
   input double MaxDistance = 20; // THETA (Max order distance)
   input double Stop = 30; // Stop Loss size
   input double MaxTrailing = 6; // COS (Start of Trailing Stop)
   input int MaxSpread = 5555; // Max Spread Limit

input group "== Trailing Stop Management=="
   enum TSlType{Default_trail=0,Scalp_trail=1,Previous_candle=2,Fast_MA=3,Tenkensen=4};
   input TSlType  TrailType = 1;                    // type of trailing stopLoss

input group "==If Trailing as Scalping Trailing ===="
   input int   TslTriggerPoints   =  60;  //points in profit before Traili9ng Starts(10 points =1pip)
   input int TslPoints            =  30;  // Traildistance in points (10 points = 1 pip)

input group "== If Trailing by previous Candle =="
   input  int  PrvCandleN         = 1 ;   // no of candles to trail Sl (if selected)

input group "== If trailing by Fast moving Average ==="
   input int   FMAperiod         =5;                // Fast-moving Avg to trail (if selected)
   input ENUM_MA_METHOD MA_mode  = MODE_EMA;        // Moving Average Mode/Method
   input ENUM_APPLIED_PRICE  MA_AppPrice   = PRICE_MEDIAN;   /// Moving Avg Applied Price
   
   int   handleTrailMA, handleIChimoku;


double DeltaX = Delta;

double MinOrderDistance = 0.5;
double MaxTrailingLimit = 7.5;
double OrderModificationFactor = 3;
int TickCounter = 0;
double PriceToPipRatio = 0;

double BaseTrailingStop = 0;
double TrailingStopBuffer = 0;
double TrailingStopIncrement = 0;
double TrailingStopThreshold = 0;
long AccountLeverageValue = 0;

double LotStepSize = 0;
double MaxLotSize = 0;
double MinLotSize = 0;
double MarginPerMinLot = 0;
double MinStopDistance = 0;

int BrokerStopLevel = 0;
double MinFreezeDistance = 0;
int BrokerFreezeLevel = 0;
double CurrentSpread = 0;
double AverageSpread = 0;

int EAModeFlag = 0;
int SpreadArraySize = 0;
int DefaultSpreadPeriod = 30;
double MaxAllowedSpread = 0;
double CalculatedLotSize = 0;

double CommissionPerPip = 0;
int SpreadMultiplier = 0;
double AdjustedOrderDistance = 0;
double MinOrderModification = 0;
double TrailingStopActive = 0;

double TrailingStopMax = 0;
double MaxOrderPlacementDistance = 0;
double OrderPlacementStep = 0;
double CalculatedStopLoss = 0;
bool AllowBuyOrders = false;

bool AllowSellOrders = false;
bool SpreadAcceptable = false;
int LastOrderTimeDiff = 0;
int LastOrderTime = 0;
int MinOrderInterval = 0;

double CurrentBuySL = 0;
string OrderCommentText = "TREMOR BEAST";
int LastBuyOrderTime = 0;
bool TradeAllowed = false;
double CurrentSellSL = 0;

int LastSellOrderTime = 0;
int OrderCheckFrequency = 2;
int SpreadCalculationMethod = 1;
bool EnableTrading = false;
double SpreadHistoryArray[];


int OnInit(){

   trade.SetExpertMagicNumber(InpMagic);
   ChartSetInteger(0, CHART_SHOW_GRID, false);

   //advanced changes = Adding handles for Trailing on MA and Ichimoku
   //================================================================
   if(TrailType==3) handleTrailMA =iMA(_Symbol,PERIOD_CURRENT,FMAperiod,0,MA_mode,MA_AppPrice);
   if(TrailType==4) handleIChimoku = iIchimoku(_Symbol,PERIOD_CURRENT,9,26,52);

   //=======================================================================


   if ((MinOrderDistance > Delta)) {
      DeltaX = (MinOrderDistance + 0.1);
   }
   if ((MaxTrailing > MaxTrailingLimit)) {
      MaxTrailingLimit = (MaxTrailing + 0.1);
   }
   if ((OrderModificationFactor < 1)) {
      OrderModificationFactor = 1;
   }

   TickCounter = 0;
   PriceToPipRatio = 0;
   BaseTrailingStop = TrailingStopBuffer;
   TrailingStopIncrement = TrailingStopThreshold;
   AccountLeverageValue = AccountInfoInteger(ACCOUNT_LEVERAGE);

   LotStepSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   MaxLotSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   MinLotSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   MarginPerMinLot = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL) * MinLotSize;
   MinStopDistance = 0;

   BrokerStopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if (BrokerStopLevel > 0) MinStopDistance = (BrokerStopLevel + 1) * _Point;

   MinFreezeDistance = 0;
   BrokerFreezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   if (BrokerFreezeLevel > 0) MinFreezeDistance = (BrokerFreezeLevel + 1) * _Point;

   if (BrokerStopLevel > 0 || BrokerFreezeLevel > 0) {
      Comment("WARNING! Broker is not suitable, the stoplevel is greater than zero.");
   }

   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   CurrentSpread = NormalizeDouble(Ask - Bid, _Digits);
   AverageSpread = CurrentSpread;

   SpreadArraySize = (EAModeFlag == 0) ? DefaultSpreadPeriod : 3; // if EMAModeFlag == 0, then DefaultSpreadPeriod else 3
   ArrayResize(SpreadHistoryArray, SpreadArraySize, 0);

   MaxAllowedSpread = NormalizeDouble((MaxSpread * _Point), _Digits);

   TesterHideIndicators(true);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){

}

void OnTick(){

   int CurrentTime = (int)TimeCurrent();
   int PendingBuyCount = 0;
   int PendingSellCount = 0;
   int OpenBuyCount = 0;
   int OpenSellCount = 0;
   int TotalBuyCount = 0;
   int TotalSellCount = 0;
   double OrderLotsValue = 0;
   double OrderStopLossValue = 0;
   double OrderTakeProfitValue = 0;
   double OrderOpenPriceValue = 0;
   double NewOrderTakeProfit = 0;
   double BuyOrdersPriceSum = 0;
   double BuyOrdersLotSum = 0;
   double SellOrdersPriceSum = 0;
   double SellOrdersLotSum = 0;
   double AverageBuyPrice = 0;
   double AverageSellPrice = 0;
   double LowestBuyPrice = 99999;
   double HighestSellPrice = 0;

   TickCounter++;

   if (PriceToPipRatio == 0) {
      HistorySelect(0, TimeCurrent());
      for(int i = HistoryDealsTotal()-1; i >= 0; i--) {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;

         if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
         if(HistoryDealGetDouble(ticket, DEAL_PROFIT) == 0) continue;
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

         ulong posID = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
         if(posID == 0) continue;

         // Find the corresponding entry deal
         if(HistoryDealSelect(posID)) {
            double entryPrice = HistoryDealGetDouble(posID, DEAL_PRICE);
            double exitPrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);

            if(exitPrice != entryPrice) {
               PriceToPipRatio = fabs(profit / (exitPrice - entryPrice));
               CommissionPerPip = -commission / PriceToPipRatio;
               break;
            }
         }
      }
   }

   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Update spread history array
   double newSpread = NormalizeDouble(Ask - Bid, _Digits);
   ArrayCopy(SpreadHistoryArray, SpreadHistoryArray, 0, 1, SpreadArraySize-1);
   SpreadHistoryArray[SpreadArraySize-1] = newSpread;

   // Calculate MA of spreads
   double sum = 0;
   for(int i = 0; i < SpreadArraySize; i++) {
      sum += SpreadHistoryArray[i];
   }
   CurrentSpread = sum / SpreadArraySize;

   // Calculate average spread including commission
   AverageSpread = MathMax(SpreadMultiplier * _Point, CurrentSpread + CommissionPerPip);

   // Calculate order distances
   AdjustedOrderDistance = MathMax(AverageSpread * Delta, MinStopDistance);
   MinOrderModification = MathMax(AverageSpread * MinOrderDistance, MinFreezeDistance);

   // Calculate trailing stop values
   TrailingStopActive = AverageSpread * MaxTrailing;
   TrailingStopMax = AverageSpread * MaxTrailingLimit;
   MaxOrderPlacementDistance = AverageSpread * MaxDistance;
   OrderPlacementStep = MinOrderModification / OrderModificationFactor;
   CalculatedStopLoss = MathMax(AverageSpread * Stop, MinStopDistance);

   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(posinfo.SelectByIndex(i) &&
         posinfo.Symbol() == _Symbol &&
         posinfo.Magic() == InpMagic) {
         double price = posinfo.PriceOpen();
         double lots = posinfo.Volume();
         double sl = posinfo.StopLoss();

         if(posinfo.PositionType() == POSITION_TYPE_BUY) {
            OpenBuyCount++;
            if(sl == 0 || (sl > 0 && sl < price)) TotalBuyCount++;
            CurrentBuySL = sl;
            BuyOrdersPriceSum += price * lots;
            BuyOrdersLotSum += lots;
            if(price < LowestBuyPrice) LowestBuyPrice = price;
         }
         else if(posinfo.PositionType() == POSITION_TYPE_SELL) {
            OpenSellCount++;
            if(sl == 0 || (sl > 0 && sl > price)) TotalSellCount++;
            CurrentSellSL = sl;
            SellOrdersPriceSum += price * lots;
            SellOrdersLotSum += lots;
            if(price > HighestSellPrice) HighestSellPrice = price;
         }
      }
   }

   for(int i = OrdersTotal()-1; i >= 0; i--) {
      if(ordinfo.SelectByIndex(i) &&
         ordinfo.Symbol() == _Symbol &&
         ordinfo.Magic() == InpMagic) {

         if(ordinfo.OrderType() == ORDER_TYPE_BUY_STOP) {
            PendingBuyCount++;
            TotalBuyCount++;
         }
         else if(ordinfo.OrderType() == ORDER_TYPE_SELL_STOP) {
            PendingSellCount++;
            TotalSellCount++;
         }
      }
   }

   if ((BuyOrdersLotSum > 0)) {
      AverageBuyPrice = NormalizeDouble((BuyOrdersPriceSum / BuyOrdersLotSum), _Digits);
   }
   if ((SellOrdersLotSum > 0)) {
      AverageSellPrice = NormalizeDouble((SellOrdersPriceSum / SellOrdersLotSum), _Digits);
   }

   MqlDateTime BrokerTime;
   TimeCurrent(BrokerTime);

   // Process pending orders

   for(int i = OrdersTotal()-1; i >= 0; i--) {
      if(!ordinfo.SelectByIndex(i)) continue;
      if(ordinfo.Symbol() != _Symbol || ordinfo.Magic() != InpMagic) continue;
      ulong ticket = ordinfo.Ticket();
      ENUM_ORDER_TYPE type = ordinfo.OrderType();
      double openPrice = ordinfo.PriceOpen();
      double sl = ordinfo.StopLoss();
      double tp = ordinfo.TakeProfit();
      double lots = ordinfo.VolumeCurrent();

      // Process buy limit orders
      if(type == ORDER_TYPE_BUY_STOP) {
         bool allowTrade = (BrokerTime.hour >= StartHour && BrokerTime.hour <= EndHour);
         if(AverageSpread > MaxAllowedSpread || !allowTrade) {
            trade.OrderDelete(ticket);
            continue;
         }

         int timeDiff = (int)(CurrentTime - LastBuyOrderTime);

         bool needsModification = (timeDiff > Secs) ||
            (TickCounter % OrderCheckFrequency == 0 &&
            ((OpenBuyCount < 1 && (openPrice - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) < MinOrderModification) ||
            (openPrice - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) < OrderPlacementStep ||
            (openPrice - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) > MaxOrderPlacementDistance));

         if(needsModification == true) {
            double distance = AdjustedOrderDistance;
            if(OpenBuyCount > 0) distance /= OrderModificationFactor;
            distance = MathMax(distance, MinStopDistance);

            double modifiedPrice = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK) + distance, _Digits);
            // Give this pending buy order its own SL, measured from its own entry price.
            double modifiedSl = NormalizeDouble(modifiedPrice - CalculatedStopLoss, _Digits);

            if((OpenBuyCount == 0 || modifiedPrice > AverageBuyPrice) &&
               modifiedPrice != openPrice &&
               (openPrice - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) > MinFreezeDistance) {
               trade.OrderModify(ticket, modifiedPrice, modifiedSl, tp, 0, 0);
               LastBuyOrderTime = CurrentTime;
            }
         }
      }
      // Process sell stop orders
      else if(type == ORDER_TYPE_SELL_STOP) {
         bool allowTrade = (BrokerTime.hour >= StartHour && BrokerTime.hour <= EndHour);
         if(AverageSpread > MaxAllowedSpread || !allowTrade) {
            trade.OrderDelete(ticket);
            continue;
         }

         int timeDiff = (int)(CurrentTime - LastSellOrderTime);

         bool needsModification = (timeDiff > Secs) ||
            (TickCounter % OrderCheckFrequency == 0 &&
            ((OpenSellCount < 1 && (SymbolInfoDouble(_Symbol, SYMBOL_BID) - openPrice) < MinOrderModification) ||
            (SymbolInfoDouble(_Symbol, SYMBOL_BID) - openPrice) < OrderPlacementStep ||
            (SymbolInfoDouble(_Symbol, SYMBOL_BID) - openPrice) > MaxOrderPlacementDistance));

         if(needsModification == true) {
            double distance = AdjustedOrderDistance;
            if(OpenSellCount > 0) distance /= OrderModificationFactor;
            distance = MathMax(distance, MinStopDistance);

            double modifiedPrice = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID) - distance, _Digits);
            // Give this pending sell order its own SL, measured from its own entry price.
            double modifiedSl = NormalizeDouble(modifiedPrice + CalculatedStopLoss, _Digits);

            if((OpenSellCount == 0 || modifiedPrice < AverageSellPrice) &&
               modifiedPrice != openPrice &&
               (SymbolInfoDouble(_Symbol, SYMBOL_BID) - openPrice) > MinFreezeDistance) {
               trade.OrderModify(ticket, modifiedPrice, modifiedSl, tp, 0, 0);
               LastSellOrderTime = CurrentTime;
            }
         }
      }
   }
/// CONTINUE
   

   if ((OrderModificationFactor > 1 && TotalBuyCount < 1) || OpenBuyCount < 1) {

      if (PendingBuyCount < 1) {

         bool spreadOK = (AverageSpread <= MaxAllowedSpread);
         bool timeOK = (BrokerTime.hour >= StartHour && BrokerTime.hour <= EndHour);

         if (spreadOK && timeOK && (CurrentTime - LastOrderTime) > MinOrderInterval && EAModeFlag == 0) {

            // Lot size calculation
            if (LotType == 0) {
               CalculatedLotSize = MathCeil(FixedLot / LotStepSize) * LotStepSize;
               CalculatedLotSize = MathMax(CalculatedLotSize, MinLotSize); // Enforce minimum
            }
            else if (LotType > 0) {
               CalculatedLotSize = calcLots(CalculatedStopLoss);
            }
            double marginRequired = 0.0;
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            if(OrderCalcMargin(ORDER_TYPE_BUY_STOP, _Symbol, CalculatedLotSize, ask, marginRequired) &&
               AccountInfoDouble(ACCOUNT_MARGIN_FREE) > marginRequired) {

               // Calculate order price and SL
               double orderDist = MathMax(MathMax(AdjustedOrderDistance, MinFreezeDistance), MinStopDistance);
               double orderPrice = NormalizeDouble(ask + orderDist, _Digits);
               // Calculate this pending buy order's SL from this order's own entry price.
               double orderSL = NormalizeDouble(orderPrice - CalculatedStopLoss, _Digits);

               if(trade.OrderOpen(_Symbol, ORDER_TYPE_BUY_STOP, CalculatedLotSize, orderPrice,
                  ask, orderSL, NewOrderTakeProfit, 0, 0, OrderCommentText)) {

                  LastBuyOrderTime = (int)TimeCurrent();
                  LastOrderTime = (int)TimeCurrent();
               }
            }
         }
      }
   }

   if ((OrderModificationFactor > 1 && TotalSellCount < 1) || OpenSellCount < 1)
   {

      if (PendingSellCount < 1)
      {

         bool spreadOK = (AverageSpread <= MaxAllowedSpread);
         bool timeOK = (BrokerTime.hour >= StartHour && BrokerTime.hour <= EndHour);

         if (spreadOK && timeOK && (CurrentTime - LastOrderTime) > MinOrderInterval && EAModeFlag == 0) {

            // Lot size calculation
            if (LotType == 0) {
               CalculatedLotSize = MathCeil(FixedLot / LotStepSize) * LotStepSize;
               CalculatedLotSize = MathMax(CalculatedLotSize, MinLotSize); // Enforce minimum
            }
            else if (LotType > 0) {
               CalculatedLotSize = calcLots(CalculatedStopLoss);
            }

            double marginRequired = 0.0;
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(OrderCalcMargin(ORDER_TYPE_SELL_STOP, _Symbol, CalculatedLotSize, bid, marginRequired) &&
               AccountInfoDouble(ACCOUNT_MARGIN_FREE) > marginRequired) {

               double orderDist = MathMax(MathMax(AdjustedOrderDistance, MinFreezeDistance), MinStopDistance);
               double orderPrice = NormalizeDouble(bid - orderDist, _Digits);
               // Calculate this pending sell order's SL from this order's own entry price.
               double orderSL = NormalizeDouble(orderPrice + CalculatedStopLoss, _Digits);

               if(trade.OrderOpen(_Symbol, ORDER_TYPE_SELL_STOP, CalculatedLotSize, orderPrice,
                  bid, orderSL, NewOrderTakeProfit, 0, 0, OrderCommentText)) {

                  LastSellOrderTime = (int)TimeCurrent();
                  LastOrderTime = (int)TimeCurrent();
               }
            }
         }
      }
   }

}


double CalculateTrailingStop(double priceMove, double minDist, double activeDist, double baseDist, double maxDist)
{
   if(maxDist == 0) return MathMax(activeDist, minDist);

   double ratio = priceMove / maxDist;
   double dynamicDist = (activeDist - baseDist) * ratio + baseDist;
   return MathMax(MathMin(dynamicDist, activeDist), minDist);
}


double calcLots(double slPoints){

   double lots = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double AccountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double EquityBalance  = AccountInfoDouble(ACCOUNT_EQUITY);
   double FreeMargin     = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   double risk=0;
   switch(LotType){
      case 0: lots= Fixed_Lots; return lots;
      case 1: risk = AccountBalance * RiskPercent / 100; break;
      case 2: risk = EquityBalance * RiskPercent / 100; break;
      case 3: risk = FreeMargin * RiskPercent / 100;
   }

   double ticksize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickvalue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotstep = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   double moneyPerLotstep = slPoints / ticksize * tickvalue * lotstep;
   lots = MathFloor(risk / moneyPerLotstep) * lotstep;

   double minvolume=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
   double maxvolume=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX);
   double volumelimit = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);

   if(volumelimit != 0) lots = MathMin(lots,volumelimit);
   if(maxvolume != 0) lots = MathMin(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX));
   if(minvolume != 0) lots = MathMax(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
   lots = NormalizeDouble(lots,2);

   return lots;
}
void TrailStop(){
   if(TrailType==0){
      // Process open positions
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(!posinfo.SelectByIndex(i)) continue;
      if(posinfo.Symbol() != _Symbol || posinfo.Magic() != InpMagic) continue;

      ulong ticket = posinfo.Ticket();
      ENUM_POSITION_TYPE type = posinfo.PositionType();
      double openPrice = posinfo.PriceOpen();
      double sl = posinfo.StopLoss();
      double tp = posinfo.TakeProfit();

      // Process buy positions
      if(type == POSITION_TYPE_BUY) {
         double priceMove = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_BID) - openPrice + CommissionPerPip, 0);
         double trailDist = CalculateTrailingStop(priceMove, MinStopDistance, TrailingStopActive, BaseTrailingStop, TrailingStopMax);

         double modifiedSl = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID) - trailDist, _Digits);
         double triggerLevel = openPrice + CommissionPerPip + TrailingStopIncrement;

         if((SymbolInfoDouble(_Symbol, SYMBOL_BID) - triggerLevel) > trailDist &&
            (sl == 0 || (SymbolInfoDouble(_Symbol, SYMBOL_BID) - sl) > trailDist) &&
            modifiedSl != sl) {
            trade.PositionModify(ticket, modifiedSl, tp);
         }
      }
      else if(type == POSITION_TYPE_SELL) {
         double priceMove = MathMax(openPrice - SymbolInfoDouble(_Symbol, SYMBOL_ASK) - CommissionPerPip, 0);
         double trailDist = CalculateTrailingStop(priceMove, MinStopDistance, TrailingStopActive, BaseTrailingStop, TrailingStopMax);

         double modifiedSl = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK) + trailDist, _Digits);
         double triggerLevel = openPrice - CommissionPerPip - TrailingStopIncrement;

         if((triggerLevel - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) > trailDist &&
            (sl == 0 || (sl - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) > trailDist) &&
            modifiedSl != sl) {
            trade.PositionModify(ticket, modifiedSl, tp);
         }
      }
   } return;
   }

// new Changes  
// v2 == Adding All the other Trailing Stop methods 
  double  sl                 =0;
  double  tp                 =0;
  double  ask                = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
  double  bid                 = SymbolInfoDouble(_Symbol,SYMBOL_BID);
  int    stopLevel           = (int) SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
  double indbuffer[];

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
                  case 4 : CopyBuffer(handleIChimoku,TENKANSEN_LINE,1,1,indbuffer); // Traling using ICHimoku if selected
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
                     case 4:  CopyBuffer(handleIChimoku,TENKANSEN_LINE,1,1,indbuffer);
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