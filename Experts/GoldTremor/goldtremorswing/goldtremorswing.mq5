//+------------------------------------------------------------------+
//|                                        Gold X9 v6.3 - Youtube shared Part 1 |
//|                                                          Mr CapFree |
//|                                              https://www.MrCapFree.com |
//+------------------------------------------------------------------+
#property copyright "Mr CapFree"
#property link      "https://www.MrCapFree.com"
#property strict
#property description "Gold X9 - v 6.3 - by Mr CapFree"

#include <Trade/Trade.mqh>

CTrade        trade;
COrderInfo    ordinfo;
CPositionInfo posinfo;

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum enum_lotsizing{
   Manual_lotsize = 0,
   Tiered_lotsizing = 1,
   RiskScaleFactor = 2
};

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== TRADE SETUP ===";
input int    InpMagic      = 647873;
input string TradeComment  = "Gold X9 by MrCapFree";

input group "=== MONEY MANAGEMENT / Lotsize Calculations ===";
input enum_lotsizing Lotsizing_Method = 1;
input double  TieredLot          = 30;
double        TieredLotEff       = 0;
input double  FixedLots          = 0.01;
input double  RiskScaling        = 1;

input group "=== PROP AND ENTRY ADJUSTMENTS ===";
input double  AdjustEntry       = 0;
input double  AdjustSL          = 0;
input double  AdjustTP          = 0;
input double  AdjustTrailSL     = 0;
input double  AdjustSalvageExit = 0;
input double  AdjustBreakEven   = 0;

input group "=== Strategy Parameters ===";
input ENUM_TIMEFRAMES  fractalTf        = PERIOD_H1;
input ENUM_TIMEFRAMES  rescanTf         = PERIOD_M15;
input int    fractalRight      = 5;
input int    fractalLeft       = 5;
input int    fractalMaxSearch  = 200;
input int    maxPending        = 3;
input int    pendExpiryHrs     = 15;
input ENUM_TIMEFRAMES  exitScanTf      = PERIOD_M1;
input int    maxPositions      = 10;
input double fractalMinDistPct = 0.02;
input double pendDedupDist     = 5.0;
input double buyEntryPct       = -0.08;
input double sellEntryPct      = -0.08;
input double slPct             = 2;
input double tpPct             = 0.7;
input double trailPct          = 0.2;
input double trailMinProfitPct = 0.2;
input double trailMaxSLPct     = 1;
input double salvageTriggerPct = 1;
input double salvageExitPct    = 0.15;
input double beTriggerPct      = 0.1;
input double beLockPct         = 0.025;
input double riskWeight        = 0.055;

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
double         CurrSpread;
ENUM_TIMEFRAMES FractalTf;
ENUM_TIMEFRAMES RescanTf;
int            FractalRight;
int            FractalLeft;
int            FractalMaxSearch;
int            MaxPendingOrders;
int            MaxPositions;
double         PendingDedupDist;
int            PendingExpiryHrs;
int            ActiveMagic;
ENUM_TIMEFRAMES ExitScanTf;
int            SymDigits;
double         StopLevelDist;
double         PipFactor;
double         FreezeLevelDist;
string         ActiveComment;
string         TradeSym;
double         SymPoint;

int            DayswitchBufferMin = 30;
double         FractalMinDist;
double         BuyEntryOffset;
double         SellEntryOffset;
bool           Virtual_expiration = true;

double SLDist;
double TPDist;
double TrailDist;
double TrailMinProfit;
double TrailMaxSL;
double TrailStep = 0.1;
double SalvageExitDist;
double SalvageTrigger;
double BeTrigger;
double BeLockDist;
double MaxLotCap = 100.0;
double WeightedRiskDivisor = 1.0;

double LastSwingHigh = 0.0;
double LastSwingLow  = 0.0;
double VirtualSL     = 0.0;
double VirtualSLStore[20][2];
double OrderPriceMap[100][2];
int    VirtualSLStoreSize = 20;
double StrategyLots = 0.01;
int    LastTradeTicket = 0;
int    PendingExpirySeconds;
double SwingLow  = 0.0;
double SwingHigh = 0.0;
int    LastHour = 0;
datetime PendingExpiry = 0;
int PerStrategyRescanBars = 0;
int PerStrategyPendingRescanBars = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   int vslResetOuterIdx;
   int vslResetInnerIdx;
   MqlDateTime nowDt;

   TieredLotEff = TieredLot;
   if ( TieredLotEff > 100.0 ) TieredLotEff = 100.0;
   if ( TieredLotEff <= 0.0 )  TieredLotEff = 1.0;

   ActiveComment = TradeComment;
   ActiveMagic   = InpMagic;
   TradeSym      = Symbol();
   SymPoint      = SymbolInfoDouble(TradeSym, SYMBOL_POINT);

   PipFactor = SymPoint;
   if ( ( (double)SymbolInfoInteger(TradeSym, SYMBOL_DIGITS) == 3.0 )
        || ( (double)SymbolInfoInteger(TradeSym, SYMBOL_DIGITS) == 5.0 ) ) {
      PipFactor = SymPoint * 10.0;
   }
   if ( SymbolInfoInteger(TradeSym, SYMBOL_DIGITS) == 1 ) {
      PipFactor = SymPoint / 10.0;
   }

   SymDigits       = (int)SymbolInfoInteger(TradeSym, SYMBOL_DIGITS);
   CurrSpread      = SymbolInfoDouble(TradeSym, SYMBOL_ASK) - SymbolInfoDouble(TradeSym, SYMBOL_BID);
   StopLevelDist   = (double)SymbolInfoInteger(TradeSym, SYMBOL_TRADE_STOPS_LEVEL) * SymPoint;
   FreezeLevelDist = (double)SymbolInfoInteger(TradeSym, SYMBOL_TRADE_FREEZE_LEVEL) * SymPoint;

   FractalTf        = fractalTf;
   RescanTf         = rescanTf;
   FractalRight     = fractalRight;
   FractalLeft      = fractalLeft;
   FractalMaxSearch = fractalMaxSearch;
   MaxPendingOrders = maxPending;
   PendingDedupDist = pendDedupDist;
   PendingExpiryHrs = pendExpiryHrs;
   ExitScanTf       = exitScanTf;
   MaxPositions     = maxPositions;

   ActivateStrategyContext();

   if ( SLDist <= 0.0 ) SLDist = 1.0;
   if ( TPDist <= 0.0 ) TPDist = 1.0;
   if ( BeLockDist > BeTrigger ) BeLockDist = BeTrigger / 2;
   if ( TrailDist != 0.0 && TrailDist < FreezeLevelDist / PipFactor ) TrailDist = FreezeLevelDist / PipFactor;
   if ( TrailDist != 0.0 && TrailDist < StopLevelDist / PipFactor ) TrailDist = StopLevelDist / PipFactor;
   if ( SLDist < StopLevelDist * 2.0 / PipFactor ) SLDist = StopLevelDist * 2.0 / PipFactor;
   if ( TPDist < StopLevelDist * 2.0 / PipFactor ) TPDist = StopLevelDist * 2.0 / PipFactor;
   if ( FractalMinDist < StopLevelDist * 2.0 / PipFactor ) FractalMinDist = StopLevelDist * 2.0 / PipFactor;
   if ( FractalRight < 1 ) FractalRight = 1;
   if ( FractalLeft < 1 ) FractalLeft = 1;
   if ( FractalMinDist < 0.1 ) FractalMinDist = 0.1;

   PendingExpirySeconds = PendingExpiryHrs * 60 * 60;
   if ( PendingExpiryHrs > 0 ) PendingExpiry = TimeCurrent() + PendingExpirySeconds;
   else PendingExpiry = 0;
   if ( Virtual_expiration ) PendingExpiry = 0;

   FindSwingPoint(FractalTf, true);
   FindSwingPoint(FractalTf, false);
   LastSwingHigh = NormalizeDouble(SwingHigh, SymDigits);
   LastSwingLow  = NormalizeDouble(SwingLow, SymDigits);

   FreezeLevelDist = (double)SymbolInfoInteger(TradeSym, SYMBOL_TRADE_FREEZE_LEVEL) * SymPoint;
   VirtualSL = 0.0;
   if ( MaxLotCap > SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MAX) ) {
      MaxLotCap = SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MAX);
   }

   for ( vslResetOuterIdx = 0; vslResetOuterIdx < VirtualSLStoreSize; vslResetOuterIdx++ ) {
      for ( vslResetInnerIdx = 0; vslResetInnerIdx < 2; vslResetInnerIdx++ ) {
         VirtualSLStore[vslResetOuterIdx][vslResetInnerIdx] = 0.0;
      }
   }

   TimeToStruct(TimeCurrent(), nowDt);
   LastHour = nowDt.hour;
   PerStrategyPendingRescanBars = 0;
   PerStrategyRescanBars = 0;

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {

  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   ActivateStrategyContext();
   RunStrategyTick();
  }
//+------------------------------------------------------------------+
//| Strategy Functions                                               |
//+------------------------------------------------------------------+
void ActivateStrategyContext(){
   
   CurrSpread      = SymbolInfoDouble(TradeSym,SYMBOL_ASK) - SymbolInfoDouble(TradeSym,SYMBOL_BID);
   StopLevelDist   = (double)SymbolInfoInteger(TradeSym,SYMBOL_TRADE_STOPS_LEVEL) * SymPoint;
   FreezeLevelDist = (double)SymbolInfoInteger(TradeSym,SYMBOL_TRADE_FREEZE_LEVEL) * SymPoint;
   
   double currentRefPrice = SymbolInfoDouble(TradeSym,SYMBOL_BID);
   
   FractalMinDist   = fractalMinDistPct / 100.0 * currentRefPrice / PipFactor;
   BuyEntryOffset   = AdjustEntry + NormalizeDouble(buyEntryPct / 100.0 * currentRefPrice / PipFactor, 0);
   SellEntryOffset  = AdjustEntry + NormalizeDouble(sellEntryPct / 100.0 * currentRefPrice / PipFactor, 0);
   SLDist           = AdjustSL + slPct / 100.0 * currentRefPrice / PipFactor;
   TPDist           = AdjustTP + tpPct / 100.0 * currentRefPrice / PipFactor;
   TrailDist        = AdjustTrailSL + trailPct / 100.0 * currentRefPrice / PipFactor;
   TrailMinProfit   = trailMinProfitPct / 100.0 * currentRefPrice / PipFactor;
   TrailMaxSL       = trailMaxSLPct / 100.0 * currentRefPrice / PipFactor;
   SalvageExitDist  = AdjustSalvageExit + salvageExitPct / 100.0 * currentRefPrice / PipFactor;
   SalvageTrigger   = salvageTriggerPct / 100.0 * currentRefPrice / PipFactor;
   BeTrigger        = beTriggerPct / 100.0 * currentRefPrice / PipFactor;
   BeLockDist       = AdjustBreakEven + beLockPct / 100.0 * currentRefPrice / PipFactor;
}

//+------------------------------------------------------------------+
//| RunStrategyTick - Calls both buy and sell entry functions        |
//+------------------------------------------------------------------+
int RunStrategyTick(){
   bool anyOrderModified;
   MqlDateTime nowDt;

   int         pendingLoopCounter;
   int         buyPendingCount;
   int         buyPendingCountScanIdx;
   double      highestBuyPendingPrice;
   long        highestBuyPendingTicket;
   int         buyPendingWorstScanIdx;
   long        deleteBuyTicket;
   int         buyMapClearIdx;
   int         sellPendingCount;
   int         sellPendingCountScanIdx;
   double      lowestSellPendingPrice;
   long        lowestSellPendingTicket;
   int         sellPendingWorstScanIdx;
   long        deletedSellTicket;
   int         sellMapClearIdx;
   bool        orderMapEntryStillOpen;
   int         orderMapScanIdx;
   long        mapStoredTicket;
   int         orderMapTicketScanIdx;
   long        currentScanTicket;


   // we put the variable 
   TimeToStruct(TimeCurrent(),nowDt);
   anyOrderModified=false;
   //
   if(ExitScanTf==PERIOD_CURRENT){
      if(ManageOrders(true)){
         anyOrderModified =true;
      }
      if(ManageOrders(false)){
         anyOrderModified=true;
      }
      if(anyOrderModified){
         return(0);
      }
   }
   // if the User has selected any other value
   else{
      if(PerStrategyPendingRescanBars != iBars(TradeSym,ExitScanTf)){
         PerStrategyPendingRescanBars = iBars(TradeSym,ExitScanTf);
         if(ManageOrders(true)){
            anyOrderModified=true;
         }
         if(ManageOrders(false)){
            anyOrderModified = true;
         }
         if(anyOrderModified){
            return(0);
         }
      }
   }

   if(!((bool)MQLInfoInteger(MQL_TESTER)) && 
              SymbolInfoInteger(TradeSym,SYMBOL_TRADE_MODE)==SYMBOL_TRADE_MODE_DISABLED)            
   {
   return (0);
   }
   if(DayswitchBufferMin>0 && ((nowDt.hour ==0 && nowDt.min < DayswitchBufferMin)||
                                 (nowDt.hour == 23 && DayswitchBufferMin > 60 - DayswitchBufferMin))){
                                    return(0);
                                 }
   CurrSpread =SymbolInfoDouble(TradeSym,SYMBOL_ASK) - SymbolInfoDouble(TradeSym,SYMBOL_BID);
   buyPendingCount =0;
   for(buyPendingCountScanIdx =0; ordinfo.SelectByIndex(buyPendingCountScanIdx);buyPendingCountScanIdx++){
      if(ordinfo.Magic() != ActiveMagic || 
      ordinfo.Symbol()   != TradeSym    ||
      ordinfo.OrderType() != ORDER_TYPE_BUY_STOP) 
      continue;
      buyPendingCount=buyPendingCount+1;    
   }
   if(buyPendingCount > MaxPendingOrders){
      highestBuyPendingPrice=0.0;
      highestBuyPendingTicket=0;
      for(buyPendingWorstScanIdx =0; ordinfo.SelectByIndex(buyPendingWorstScanIdx);buyPendingWorstScanIdx++){
         if(ordinfo.Magic() != ActiveMagic ||
            ordinfo.Symbol() !=TradeSym ||
            ordinfo.OrderType()  != ORDER_TYPE_BUY_STOP ||
            !(ordinfo.PriceOpen() > highestBuyPendingPrice)
      )
      continue;
      highestBuyPendingTicket =(long)ordinfo.Ticket();
      highestBuyPendingPrice = ordinfo.PriceOpen();
      }
      if(highestBuyPendingTicket!=0){
         trade.OrderDelete(highestBuyPendingTicket);
         deleteBuyTicket = highestBuyPendingTicket;
         for(buyMapClearIdx=0;buyMapClearIdx<100;buyMapClearIdx=buyMapClearIdx+1){  
            if(!(OrderPriceMap[buyMapClearIdx][0]==deleteBuyTicket)) continue;
            OrderPriceMap[buyMapClearIdx][0]=0.0;
            OrderPriceMap[buyMapClearIdx][1]=0.0;
            break;

         }

      }
   }

   //Sell oders 
   sellPendingCount=0;

   for(sellPendingCountScanIdx =0;ordinfo.SelectByIndex(sellPendingCountScanIdx);sellPendingCountScanIdx++){
      if(ordinfo.Magic() != ActiveMagic ||
         ordinfo.Symbol() != TradeSym || 
         ordinfo.OrderType() !=ORDER_TYPE_SELL_STOP)
         continue;
         //if the above match we increase sellPendingCount by 1
        sellPendingCount=sellPendingCount +1;

   }
   if(sellPendingCount > MaxPendingOrders){
      // here we delete the lowest price
      lowestSellPendingPrice  = DBL_MAX;
      lowestSellPendingTicket = 0;
      for(sellPendingWorstScanIdx =0;ordinfo.SelectByIndex(sellPendingWorstScanIdx);sellPendingWorstScanIdx++){
         if(ordinfo.Magic() !=ActiveMagic || 
            ordinfo.Symbol()!= TradeSym ||
            ordinfo.OrderType() !=ORDER_TYPE_SELL_STOP||
            ! (ordinfo.PriceOpen()<lowestSellPendingPrice)
         )
         continue;

         //update the value
         lowestSellPendingTicket =(long)ordinfo.Ticket();
         lowestSellPendingPrice=ordinfo.PriceOpen();

      }
      if(lowestSellPendingTicket !=0){
         trade.OrderDelete(lowestSellPendingTicket);
         deletedSellTicket = lowestSellPendingTicket;
         for(sellMapClearIdx =0;sellMapClearIdx<100;sellMapClearIdx=sellMapClearIdx+1){
            if(!(OrderPriceMap[sellMapClearIdx][0]==deletedSellTicket)) continue;
            OrderPriceMap[sellMapClearIdx][0]=0.0;
            OrderPriceMap[sellMapClearIdx][1]=0.0;
            break;

         }
      }
   }
   if(PerStrategyPendingRescanBars !=iBars(TradeSym,RescanTf)){
      //if there is a new bar
      PerStrategyPendingRescanBars=iBars(TradeSym,RescanTf);
      for(pendingLoopCounter =0; pendingLoopCounter<MaxPendingOrders;pendingLoopCounter++){
         ProcessStrategyEntries();
      }

   }
   if(LastHour != nowDt.hour){
      LastHour =nowDt.hour;
      orderMapEntryStillOpen=false;
      //do a proper cleanup
      for(orderMapScanIdx=0;orderMapScanIdx<100; orderMapScanIdx + 1){
         mapStoredTicket=(long)OrderPriceMap[orderMapScanIdx][0];
         orderMapEntryStillOpen=false;
         for(orderMapTicketScanIdx=0;posinfo.SelectByIndex(orderMapTicketScanIdx);orderMapScanIdx++){
            currentScanTicket =(long)posinfo.Ticket();
            if(mapStoredTicket != currentScanTicket) continue;
            orderMapEntryStillOpen = true;           
         }
         if(!orderMapEntryStillOpen){
            for(orderMapTicketScanIdx = 0; ordinfo.SelectByIndex(orderMapTicketScanIdx);orderMapScanIdx++){
               currentScanTicket=(long)ordinfo.Ticket();
               if(mapStoredTicket != currentScanTicket) continue;
               orderMapEntryStillOpen=true;
            }
         }
         //we check whether the 100 orders are still valid
         if(orderMapEntryStillOpen) continue;
         OrderPriceMap[orderMapScanIdx][0] =0.0;
         OrderPriceMap[orderMapScanIdx][1]=0.0;


      }
   }

   ProcessStrategyEntries();
   return(0);
}

//+------------------------------------------------------------------+
//| FindSwingPoint - Locate the most recent valid fractal high/low   |
//+------------------------------------------------------------------+
double FindSwingPoint(ENUM_TIMEFRAMES timeframe, bool findHigh){
   
   bool   found = false;
   bool   leftOk = false;
   bool   rightOk = false;
   int    barIdx;
   int    rightScan; ///know which side we are looking
   int    leftScan;
   double candidateExtreme;
   int    candidateBar;
   double historicalExtreme;
   int    histIdx;
   double normalizedPrice;
   int    ordIdx;
   bool   dupFound;
   double result;

   
   barIdx = FractalRight + 1;

   do{
      leftOk = true;
      rightOk = true;

      for (rightScan = barIdx;rightScan >= barIdx - FractalLeft;rightScan-- ){
         if ( findHigh ? ( iHigh(TradeSym,timeframe,rightScan) > iHigh(TradeSym,timeframe,barIdx) ) :
                         ( iLow(TradeSym,timeframe,rightScan) < iLow(TradeSym,timeframe,barIdx) ) ){
            rightOk = false;
         }
      }

      for ( leftScan = barIdx; leftScan <= barIdx + FractalRight; leftScan++ ){
         if ( findHigh ? ( iHigh(TradeSym,timeframe,leftScan) > iHigh(TradeSym,timeframe,barIdx) ) :
                         ( iLow(TradeSym,timeframe,leftScan) < iLow(TradeSym,timeframe,barIdx) ) ){
            leftOk = false;
         }
      }

      if ( rightOk && leftOk && ( findHigh ?
           ( iHigh(TradeSym,timeframe,barIdx) > FractalMinDist * PipFactor + SymbolInfoDouble(TradeSym,SYMBOL_ASK) ) :
           ( iLow(TradeSym,timeframe,barIdx)  < SymbolInfoDouble(TradeSym,SYMBOL_BID) - FractalMinDist * PipFactor ) ) ){

         candidateExtreme = findHigh ? iHigh(TradeSym,timeframe,barIdx) :
                                       iLow(TradeSym,timeframe,barIdx);
         candidateBar     = barIdx;

         historicalExtreme = findHigh ? iHigh(TradeSym,FractalTf,0) :
                                        iLow(TradeSym,FractalTf,0);
         
         for ( histIdx = 1; histIdx <= candidateBar; histIdx += 1 ){
            if ( findHigh ? ( iHigh(TradeSym,FractalTf,histIdx) > historicalExtreme ) :
                            ( iLow(TradeSym,FractalTf,histIdx) < historicalExtreme ) ){
               historicalExtreme = findHigh ? iHigh(TradeSym,FractalTf,histIdx) :
                                              iLow(TradeSym,FractalTf,histIdx);
            }
         }

         if ( findHigh ? ( candidateExtreme >= historicalExtreme ) :
                         ( candidateExtreme <= historicalExtreme ) ){

            normalizedPrice = NormalizeDouble(candidateExtreme, SymDigits);

            dupFound = false;
            for ( ordIdx = 0; ordinfo.SelectByIndex(ordIdx); ordIdx++ ){
               if ( findHigh ){
                  if ( ordinfo.Magic() != ActiveMagic ||
                       ordinfo.Symbol() != TradeSym ||
                       ordinfo.OrderType() != ORDER_TYPE_BUY_STOP ||
                       !( MathAbs( ordinfo.PriceOpen() - ( BuyEntryOffset * PipFactor + normalizedPrice ) ) < PendingDedupDist * PipFactor ) )
                     continue;
               }
               else{
                  if ( ordinfo.Magic() != ActiveMagic ||
                       ordinfo.Symbol() != TradeSym ||
                       ordinfo.OrderType() != ORDER_TYPE_SELL_STOP ||
                       !( MathAbs( ordinfo.PriceOpen() - ( normalizedPrice - SellEntryOffset * PipFactor ) ) < PendingDedupDist * PipFactor ) )
                     continue;
               }
               dupFound = true;
               break;
            }

            if ( !dupFound ){
               found = true;
               result = normalizedPrice;
               if ( findHigh ){ SwingHigh = result; }
               else{ SwingLow = result; }
               break;
            }
         }
      }

      barIdx++;
      if ( barIdx <= FractalMaxSearch ) continue;

      if ( findHigh ){ SwingHigh = 0.0; }
      else{ SwingLow = 0.0; }
      break;

   } while(!found);

   return( findHigh ? SwingHigh : SwingLow );
}

void CalculateLotSize(){
  double calculatedLots;
  calculatedLots =StrategyLots;
  if(Lotsizing_Method==0){
    calculatedLots = FixedLots;
    if(calculatedLots < SymbolInfoDouble(TradeSym,SYMBOL_VOLUME_MIN)){
      calculatedLots = SymbolInfoDouble(TradeSym,SYMBOL_VOLUME_MIN);
    }
    StrategyLots = calculatedLots;
    return;
  }
  // calculating the lotsize based on risk parameters

  double slDollars = SLDist * PipFactor;
  double riskDivisorValue =0.0;
  if(Lotsizing_Method ==1){
    WeightedRiskDivisor = TieredLotEff;
    riskDivisorValue    = WeightedRiskDivisor;

  }
  if(Lotsizing_Method==2){
    riskDivisorValue = RiskScaling;

  }

  if((Lotsizing_Method==1 || Lotsizing_Method==2) && slDollars>0.0){
    calculatedLots =riskDivisorValue * AccountInfoDouble(ACCOUNT_BALANCE) * 0.0001 * riskWeight / slDollars;

  }
  // do some validation
  if(calculatedLots < SymbolInfoDouble(TradeSym,SYMBOL_VOLUME_STEP)){
    calculatedLots =SymbolInfoDouble(TradeSym,SYMBOL_VOLUME_STEP);
  }
  if(calculatedLots>MaxLotCap){
    calculatedLots=MaxLotCap;
  }
  if(calculatedLots < SymbolInfoDouble(TradeSym,SYMBOL_VOLUME_MIN)){
    calculatedLots = SymbolInfoDouble(TradeSym,SYMBOL_VOLUME_MIN);
  }
  //CHECK if the broker has a maximum allowed volume
  if(calculatedLots > SymbolInfoDouble(TradeSym,SYMBOL_VOLUME_MAX) && SymbolInfoDouble(TradeSym,SYMBOL_VOLUME_MAX)!=0.0){
    calculatedLots = SymbolInfoDouble( TradeSym,SYMBOL_VOLUME_MAX);
  }

  //Round Down The lot Size
  if(SymbolInfoDouble(TradeSym,SYMBOL_VOLUME_STEP)==0.1){
    StrategyLots = NormalizeDouble((MathFloor(calculatedLots * 10.0))/10.0,1);
    return;
  }
  // Normalize the function 
  StrategyLots = NormalizeDouble(MathFloor(calculatedLots*100)/100.0,2);
}

void ProcessStrategyEntries(){
  // variable local
  int expireIdx;
  datetime  nowTime;
  datetime  orderExpireTime;
  int       buyPosCount;
  int       buyPosScanIdx;
  int       buyPendDeleteIdx;
  int       sellPosCount;
  int       sellPosScanIdx;
  int       sellPendDeleteIdx;
  bool      deleteThisOrder;
  CalculateLotSize();

  if(StrategyLots>MaxLotCap){ 

    StrategyLots=MaxLotCap;

  }
  if(Virtual_expiration){
    expireIdx =0;
    //here loop through all arders
    while(ordinfo.SelectByIndex(expireIdx)){
      deleteThisOrder =false;
      if(ordinfo.Magic()== ActiveMagic && ordinfo.Symbol() == TradeSym){
        nowTime =TimeCurrent();
        orderExpireTime = ordinfo.TimeSetup() + PendingExpirySeconds;

        if(nowTime >= orderExpireTime){
          deleteThisOrder = trade.OrderDelete(ordinfo.Ticket());
        }
      }
      if(!deleteThisOrder ) expireIdx ++;


    }
  }// end of vertual expiration
  // check how many posistions are there

  buyPosCount=0; 
  for(buyPosScanIdx=0; posinfo.SelectByIndex(buyPosScanIdx); buyPosCount ++){
    //loop the orders
    if(posinfo.Magic() != ActiveMagic || posinfo.Symbol() != TradeSym || posinfo.PositionType() != POSITION_TYPE_BUY) continue;
    buyPosCount = buyPosCount + 1;

  }
  // Here if the calculate  buy position is less than MaxPosition we place an order true means its buy stop and false means sell stop
  if(buyPosCount < MaxPositions){
    PlaceEntry(true);

  }
  //Here if the positions becomes either
  else{ 
    buyPendDeleteIdx =0; 
    while(ordinfo.SelectByIndex(buyPendDeleteIdx)){
      deleteThisOrder=false;
      if(ordinfo.Magic() == ActiveMagic && 
      ordinfo.Symbol() == TradeSym &&
        ordinfo.OrderType() == ORDER_TYPE_BUY_STOP){
          deleteThisOrder = trade.OrderDelete(ordinfo.Ticket()); // delete the order if the codition is satisfied
        }
        if(!deleteThisOrder) buyPendDeleteIdx ++;
    }
  }
  // Here we do the same for the Sell orders
  sellPosCount =0;

  for(sellPosScanIdx =0; posinfo.SelectByIndex(sellPosScanIdx); sellPosScanIdx++){
      if(posinfo.Magic() != ActiveMagic || 
      posinfo.Symbol() != TradeSym ||
      posinfo.PositionType() != POSITION_TYPE_SELL)
      continue;
      sellPosCount= sellPosCount + 1;
  }
  if(sellPosCount < MaxPositions){
    PlaceEntry(false);
  }
  else{
    sellPendDeleteIdx =0;
    // Go through all the orders
    while (ordinfo.SelectByIndex(sellPendDeleteIdx)){
      deleteThisOrder =false;
      if(ordinfo.Magic()== ActiveMagic &&
         ordinfo.Symbol() == TradeSym &&
         ordinfo.OrderType() == ORDER_TYPE_SELL_STOP){
          deleteThisOrder = trade.OrderDelete(ordinfo.Ticket());
         }
         if(!deleteThisOrder) sellPendDeleteIdx ++;
    }
  }

}
//+------------------------------------------------------------------+
//| PlaceEntry - Place a pending buy/sell stop at swing point        |
//+------------------------------------------------------------------+
bool PlaceEntry( bool isBuy ){

   bool      swingFound;
   double    entryPrice;
   double    slippageEntryPrice;
   double    slPrice;
   double    tpPrice;
   double    swingPrice;
   int       pendIdx;
   bool      dupFound;
   int       pendCount;
   int       pendCountIdx;
   double    worstPendingPrice;
   int       pendScanIdx;
   double    entryPriceCheck;
   int       pendScanIdx2;
   bool      betterPendingExists;
   bool      volumeValid;
   int       maxOrdersLimit;
   bool      orderLimitOk;
   int       lastErrorCode;
   double    filledEntryPrice;
   long      newTicket;
   ENUM_ORDER_TYPE_TIME pendTimeType;
   int       mapSlot;
   int       pendType;

   //--- 1. Decide pending order type based on isBuy
   pendType = (int)( isBuy ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP );

   //--- 2. Find the relevant swing point
   if ( isBuy ){
      FindSwingPoint(FractalTf, true);
      swingPrice = SwingHigh;
   } else {
      FindSwingPoint(FractalTf, false);
      swingPrice = SwingLow;
   }

   swingFound = false;
   dupFound = false;

   //--- 3. Duplicate check across pending orders
   for ( pendIdx = 0; ordinfo.SelectByIndex(pendIdx); pendIdx = pendIdx + 1 ){
      if ( ordinfo.Magic() != ActiveMagic ||
           ordinfo.Symbol() != TradeSym ||
           (int)ordinfo.OrderType() != pendType )
         continue;

      if ( !( MathAbs( ordinfo.PriceOpen() - ( isBuy ? ( BuyEntryOffset * PipFactor + swingPrice ) :
                                                  ( swingPrice - SellEntryOffset * PipFactor ) ) ) < PendingDedupDist * PipFactor ) )
         continue;

      dupFound = true;
      break;
   }

   if ( !dupFound ){

      //--- 4. Count existing pending orders of this type
      pendCount = 0;

      for ( pendCountIdx = 0; ordinfo.SelectByIndex(pendCountIdx); pendCountIdx = pendCountIdx + 1 ){
         if ( ordinfo.Magic() != ActiveMagic ||
              ordinfo.Symbol() != TradeSym ||
              (int)ordinfo.OrderType() != pendType )
            continue;
         pendCount = pendCount + 1;
      }

      //--- 5. If at max, find the worst existing pending price
      if ( pendCount == MaxPendingOrders ){
         worstPendingPrice = isBuy ? DBL_MAX : 0.0;
         for ( pendScanIdx = 0; ordinfo.SelectByIndex(pendScanIdx); pendScanIdx = pendScanIdx + 1 ){
            if ( ordinfo.Magic() != ActiveMagic ||
                 ordinfo.Symbol() != TradeSym ||
                 (int)ordinfo.OrderType() != pendType )
               continue;
            if ( isBuy ? !( ordinfo.PriceOpen() < worstPendingPrice ) :
                         !( ordinfo.PriceOpen() > worstPendingPrice ) )
               continue;
            worstPendingPrice = ordinfo.PriceOpen();
         }

         //--- 6. If new swing is worse than all existing, bail
         if ( isBuy ){
            if ( SwingHigh > worstPendingPrice ){
               return(false);
            }
         }
         else{
            if ( SwingLow < worstPendingPrice ){
               return(false);
            }
         }
      }

      //--- 7. If we reach here, no duplicate + room for new order (or better than worst)
      if ( isBuy ){
         swingFound = true;
         LastSwingHigh = NormalizeDouble(SwingHigh, SymDigits);
      }
      else{
         swingFound = true;
         LastSwingLow = NormalizeDouble(SwingLow, SymDigits);
      }

      //--- 8. Bail if swing is invalid (0)
      if ( isBuy ){
         if ( LastSwingHigh == 0.0 ){ return(false); }
      }
      else{
         if ( LastSwingLow == 0.0 ){ return(false); }
      }

      //--- 9. If swing found, calculate entry price with offset
      if ( swingFound ){
         if ( isBuy ){
            entryPrice = NormalizeDouble( LastSwingHigh + BuyEntryOffset * PipFactor, SymDigits );
         }
         else{
            entryPrice = NormalizeDouble( LastSwingLow - SellEntryOffset * PipFactor, SymDigits );
         }

         entryPriceCheck = entryPrice;
         betterPendingExists = false;

         //--- 10. Second duplicate check: is there already a BETTER pending order?
         for ( pendScanIdx2 = 0; ordinfo.SelectByIndex(pendScanIdx2); pendScanIdx2 = pendScanIdx2 + 1 ){
            if ( ordinfo.Magic() != ActiveMagic ||
                 ordinfo.Symbol() != TradeSym ||
                 (int)ordinfo.OrderType() != pendType )
               continue;

            if ( isBuy ? !( ordinfo.PriceOpen() <= entryPriceCheck ) :
                         !( ordinfo.PriceOpen() >= entryPriceCheck ) )
               continue;

            betterPendingExists = true;
            break;
         }

         if ( betterPendingExists ){
            return(false);
         }

         //--- 11. Margin check
         ENUM_ORDER_TYPE marginOrderType = (isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
         double marginPrice = (isBuy ? SymbolInfoDouble(TradeSym, SYMBOL_ASK) :
                                       SymbolInfoDouble(TradeSym, SYMBOL_BID));
         double marginRequired = 0.0;

         if ( !OrderCalcMargin(marginOrderType, TradeSym, StrategyLots, marginPrice, marginRequired) ||
              AccountInfoDouble(ACCOUNT_MARGIN_FREE) - marginRequired <= 0.0 ){
            return(false);
         }

         //--- 12. Calculate SL/TP prices
         if ( isBuy ){
            slippageEntryPrice = entryPrice;
            slPrice = NormalizeDouble( entryPrice - SLDist * PipFactor, SymDigits );
            tpPrice = NormalizeDouble( TPDist * PipFactor + entryPrice, SymDigits );
         }
         else{
            slippageEntryPrice = entryPrice;
            slPrice = NormalizeDouble( SLDist * PipFactor + entryPrice, SymDigits );
            tpPrice = NormalizeDouble( entryPrice - TPDist * PipFactor, SymDigits );
         }

         //--- 13. Volume validation
         if ( StrategyLots < SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MIN) ){
            volumeValid = false;
         }
         else if ( StrategyLots > SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MAX) ){
            volumeValid = false;
         }
         else if ( MathAbs( NormalizeDouble( StrategyLots / SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_STEP), 0 ) *
                            SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_STEP) - StrategyLots ) > 0.0000001 ){
            volumeValid = false;
         }
         else{
            volumeValid = true;
         }

         //--- 14. Broker max orders limit check
         maxOrdersLimit = (int)AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);

         if ( maxOrdersLimit == 0 ){
            orderLimitOk = true;
         }
         else{
            orderLimitOk = ( PositionsTotal() + OrdersTotal() ) < maxOrdersLimit;
         }

         if ( ( !volumeValid ) || ( !orderLimitOk ) ){
            return(false);
         }

         //--- 15. Freeze/stop level check
         if ( ( isBuy ? ( SymbolInfoDouble(TradeSym, SYMBOL_ASK) < slippageEntryPrice - FreezeLevelDist * PipFactor &&
                          SymbolInfoDouble(TradeSym, SYMBOL_ASK) < slippageEntryPrice - StopLevelDist * PipFactor ) :
                        ( SymbolInfoDouble(TradeSym, SYMBOL_BID) > FreezeLevelDist * PipFactor + slippageEntryPrice &&
                          SymbolInfoDouble(TradeSym, SYMBOL_BID) > StopLevelDist * PipFactor + slippageEntryPrice ) ) ){

            //--- 16. Configure trade object
            trade.SetExpertMagicNumber(ActiveMagic);
            trade.SetTypeFilling(ORDER_FILLING_RETURN);

            //--- 17. Calculate expiration
            if ( PendingExpiryHrs > 0 ){
               PendingExpiry = TimeCurrent() + PendingExpirySeconds;
            }
            else{
               PendingExpiry = 0;
            }
            if ( Virtual_expiration ){
               PendingExpiry = 0;
            }

            //--- 18. Determine expiration type
            pendTimeType = ( PendingExpiry > 0 ) ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;

            //--- 19. Send the order
            if ( trade.OrderOpen( TradeSym, isBuy ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP,
                                  StrategyLots, 0, slippageEntryPrice, slPrice, tpPrice,
                                  pendTimeType, PendingExpiry, ActiveComment ) ){
               LastTradeTicket = (int)trade.ResultOrder();
            }
            else{
               LastTradeTicket = -1;
            }

            //--- 20. Handle result / errors
            if ( LastTradeTicket <= 0 ){
               lastErrorCode = GetLastError();
               if ( lastErrorCode == 132 ){
                  ResetLastError();
               }
            }
            else{
               filledEntryPrice = entryPrice;
               newTicket = LastTradeTicket;

               //--- 21. Record in OrderPriceMap
               for ( mapSlot = 0; mapSlot < 100; mapSlot = mapSlot + 1 ){
                  if ( !( OrderPriceMap[mapSlot][0] == 0.0 ) ) continue;
                  OrderPriceMap[mapSlot][0] = (double)newTicket;
                  OrderPriceMap[mapSlot][1] = filledEntryPrice;
                  break;
               }
            }
         }
         return(true);
      }
   }

   return(false);
}
///manage position function look on everymin or whatever users uses

bool ManageOrders(bool isBuy){
bool               modified =false;      // this is to verify if a particular position have been modified
bool               orderModified = false;
double             effectiveSL;
double             tpRefPrice;
int                orderIdx;
double             currentSL;
double             currentTP;
long               orderTicket;
double             openPrice;
double             orderLots;
datetime           openTime;
int                orderType;
int                orderMagic;
string             orderSymbol;
double             entryRefPrice;
int                digitsTemp;
long               mapTicket;
int                mapScanIdx;
double             mapPrice;
double             entryPriceForMap;
long               newMapTicket;
int                mapSlotIdx;
long               adaptTrailTicket;
double             adaptTrailDistParam;
double             adaptTrailRefPrice;
int                adaptTrailDirection;
double             adaptTrailComputed;
bool               adaptTrailFound;
int                adaptTrailScanIdx;   
int                adaptTrailSaveScanIdx;
double             newVSlValue;
long               newVSlTicket;
int                vSlSaveIdx;

effectiveSL        =0.0;
tpRefPrice         =0.0;
for(orderIdx = 0; posinfo.SelectByIndex(orderIdx); orderIdx ++){
   modified = false; 
   // whatever position is modified we gonna get this its information
   currentSL =       NormalizeDouble(posinfo.StopLoss(),SymDigits);   //Here we get The Stoploss
   currentTP =       NormalizeDouble(posinfo.TakeProfit(),SymDigits);  // Here we get the Take profit
   orderTicket=      (long)posinfo.Ticket();                           //Here we get the ticket of the position
   openPrice  =      NormalizeDouble(posinfo.PriceOpen(),SymDigits);   // Here we get the entry Price
   orderLots  =      posinfo.Volume();                                 //Here we get the lot type
   openTime   =      (datetime)posinfo.Time();                         // Here we get when was the position was opened
   orderType  =      (int)posinfo.PositionType();                      //Here we get the type of order 
   orderMagic =      (int)posinfo.Magic();                             // Here we get the magic number
   orderSymbol =      posinfo.Symbol();                                /// Here we get the Symbol

   if(orderType == (isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL) && 
      orderMagic == ActiveMagic &&
      orderSymbol == TradeSym){
         // Here we check whether the current Stoploss is zero if so we place it
         if(currentSL == 0.0){
            currentSL = isBuy ? NormalizeDouble(openPrice - SLDist * PipFactor,SymDigits) :
                                NormalizeDouble(SLDist * PipFactor + openPrice,SymDigits);
            trade.PositionModify(orderTicket,currentSL,currentTP);

         }
         // we do The Same for the Take Profit
         if(currentTP ==0.0){
            currentTP = isBuy ? NormalizeDouble(TPDist * PipFactor + openPrice,SymDigits):
                                NormalizeDouble(openPrice - TPDist * PipFactor,SymDigits) ;
            trade.PositionModify(orderTicket,currentSL,currentTP);

         }
         digitsTemp = SymDigits;
         mapTicket  = orderTicket;
         mapPrice   =0.0;

         // we loopThrough orderpriceMap
         for(mapScanIdx=0;mapScanIdx<100;mapScanIdx=mapScanIdx+1){
            //check the ticket index of orderprice array
            if(!(OrderPriceMap[mapScanIdx][0] == mapTicket)) continue;
            //if the ticket match
            mapPrice = OrderPriceMap[mapScanIdx][1];
            break;

         }
         entryRefPrice = NormalizeDouble(mapPrice,digitsTemp);
         if(entryRefPrice == 0.0){
            entryPriceForMap  =openPrice;
            newMapTicket      = orderTicket;
            //look for empty slot
            for(mapSlotIdx =0; mapSlotIdx <100; mapSlotIdx=mapSlotIdx+1){
               if(!(OrderPriceMap[mapSlotIdx][0]==0.0))  continue;  //Here is to look whether there is a valid ticket number
               //if there is a blank space which is zero as soon is found
               OrderPriceMap[mapScanIdx][0]= (double)newMapTicket;
               OrderPriceMap[mapSlotIdx][1] = entryPriceForMap;
               break;

            }
            entryRefPrice = openPrice;
         }
         tpRefPrice = entryRefPrice;
          // we do a check here
          if(isBuy? (currentSL < NormalizeDouble(openPrice- SLDist * PipFactor - CurrSpread , SymDigits)):
                     (currentSL>NormalizeDouble(SLDist * PipFactor + openPrice + CurrSpread,SymDigits))){
                        currentSL =isBuy? NormalizeDouble(openPrice-SLDist*PipFactor-CurrSpread,SymDigits) :
                                   NormalizeDouble(SLDist *PipFactor +openPrice+CurrSpread,SymDigits);

                        trade.PositionModify(orderTicket,currentSL,currentTP);
                     }
          if(isBuy ? (SymbolInfoDouble(TradeSym,SYMBOL_BID)<openPrice - SLDist * PipFactor - CurrSpread):
                     (SymbolInfoDouble(TradeSym,SYMBOL_ASK) >SLDist * PipFactor + openPrice + CurrSpread)){
                        trade.PositionClose(orderTicket,(ulong)(CurrSpread));
                        return(true);
                     }

      
      // Here is about trailing fuctionality


      adaptTrailTicket     =orderTicket;
      adaptTrailDistParam  =SLDist;
      adaptTrailRefPrice   =openPrice;
      adaptTrailComputed   =isBuy ? 1:2;  // what is the direction of the trail if it is 1(buy ) 2 (sell)
      adaptTrailComputed   =0.0;
      adaptTrailFound      =false;

      for(adaptTrailScanIdx=0;adaptTrailScanIdx<VirtualSLStoreSize;adaptTrailScanIdx++){
         if(VirtualSLStore[adaptTrailScanIdx][0]==adaptTrailTicket){
            adaptTrailComputed = VirtualSLStore [adaptTrailSaveScanIdx][1]; // here we update the trail computed to index 
            adaptTrailFound = true;
            break;
         }
      }
      adaptTrailDirection=0;
      //if we are not able to find the trail stoploss
      if(!(adaptTrailFound)){
         if(adaptTrailDirection == 1){
            adaptTrailComputed=NormalizeDouble(adaptTrailRefPrice - adaptTrailDistParam * PipFactor,SymDigits);
         }
         if(adaptTrailDirection==2){
            adaptTrailComputed =NormalizeDouble(adaptTrailDistParam * PipFactor +adaptTrailRefPrice,SymDigits);
         }
         for(adaptTrailSaveScanIdx=0;adaptTrailSaveScanIdx<VirtualSLStoreSize;adaptTrailSaveScanIdx++){
            if(VirtualSLStore[adaptTrailSaveScanIdx][0]==0.0){
               VirtualSLStore[adaptTrailSaveScanIdx][0]=(double)adaptTrailTicket;
               VirtualSLStore[adaptTrailSaveScanIdx][1]=adaptTrailComputed;
               break;
            }
         }
      }
      VirtualSL   = adaptTrailComputed;
      effectiveSL = VirtualSL;
//    Here we do a check
      if(isBuy ? (SymbolInfoDouble(TradeSym,SYMBOL_BID) < effectiveSL) :
                  (SymbolInfoDouble(TradeSym,SYMBOL_ASK) > effectiveSL)){
                     trade.PositionClose(orderTicket,(ulong)(CurrSpread));
                     return(true);
                  }
      double Bid=SymbolInfoDouble(TradeSym,SYMBOL_BID);
      double Ask=SymbolInfoDouble(TradeSym,SYMBOL_ASK);
       // Here we check whether we have enough profit before trailing is triggered
       if( TrailDist>0.0 && ( isBuy ? 
                              // This is for the buy operations
                               (Bid > (TrailDist + TrailStep)* PipFactor + currentSL && 
                                Bid>TrailMinProfit * PipFactor + tpRefPrice && 
                                Bid<currentTP-FreezeLevelDist && currentSL< TrailMaxSL * PipFactor + openPrice):
                              //This is for the sell Operations
                                (Ask < currentSL-(TrailDist + TrailStep) * PipFactor && 
                                 Ask < tpRefPrice-TrailMinProfit * PipFactor && 
                                 Ask>currentTP + FreezeLevelDist && 
                                 currentSL > openPrice - TrailMaxSL * PipFactor
                              )
       )){
         // If the conditions are met
         currentSL =isBuy ? NormalizeDouble(SymbolInfoDouble(TradeSym,SYMBOL_BID) - TrailDist * PipFactor,SymDigits):
                            NormalizeDouble(SymbolInfoDouble(TradeSym,SYMBOL_ASK) + TrailDist * PipFactor,SymDigits);
         if(isBuy ? (currentSL < SymbolInfoDouble(TradeSym,SYMBOL_BID)- StopLevelDist): // this will calculate how much distance the broker allows us to place the stop loss
                     (currentSL>SymbolInfoDouble(TradeSym,SYMBOL_ASK) + StopLevelDist)){
                     // If it is above that
                     trade.PositionModify(orderTicket,currentSL,currentTP);
                     modified =true;

                     }
       }
       //salvaging function this is where when at a loss how much we will Trail the stoploss to be triggered
       if(SalvageExitDist >0.0 && (isBuy? 
                                    (Ask < currentTP -salvageExitPct * PipFactor &&
                                     Ask < tpRefPrice - SalvageTrigger * PipFactor &&
                                     Bid< currentTP - FreezeLevelDist):
                                    (Bid>currentTP + SalvageExitDist * PipFactor && 
                                     Bid> tpRefPrice + SalvageTrigger * PipFactor &&
                                     Ask>currentTP + FreezeLevelDist)
                                    )
                                 ){
                                    currentTP =isBuy ? NormalizeDouble(SymbolInfoDouble(TradeSym,SYMBOL_BID) + SalvageExitDist * PipFactor,SymDigits):
                                                       NormalizeDouble(SymbolInfoDouble(TradeSym,SYMBOL_BID) - SalvageExitDist * PipFactor,SymDigits);
                                    if(isBuy? (currentTP>SymbolInfoDouble(TradeSym,SYMBOL_ASK) + StopLevelDist):
                                               (currentTP < SymbolInfoDouble(TradeSym,SYMBOL_BID)-StopLevelDist)){
                                                trade.PositionModify(orderTicket,currentSL,currentTP);
                                                modified = true;

                                               }

                                 }
                                 //Break Even functionality
                                 if(BeTrigger >0.0 && (isBuy ? 
                                                        (Bid>BeTrigger * PipFactor + openPrice && 
                                                         BeLockDist * PipFactor + openPrice > currentSL && Bid >BeLockDist*PipFactor + openPrice + StopLevelDist &&
                                                         Bid < currentTP- FreezeLevelDist):
                                                        (Ask < openPrice - BeTrigger * PipFactor && 
                                                         currentSL > openPrice - BeLockDist * PipFactor && 
                                                         Ask < openPrice-BeLockDist* PipFactor-StopLevelDist&&
                                                         Ask > currentTP + FreezeLevelDist)))
                                                         {
                                                            currentSL = isBuy? NormalizeDouble(BeLockDist * PipFactor + openPrice,SymDigits):
                                                                               NormalizeDouble(openPrice - BeLockDist  * PipFactor,SymDigits);
                                                            if(isBuy ? (currentSL < SymbolInfoDouble(TradeSym,SYMBOL_BID) - StopLevelDist):
                                                                        (currentSL<SymbolInfoDouble(TradeSym, SYMBOL_ASK) + StopLevelDist)){
                                                                           trade.PositionModify(orderTicket,currentSL,currentTP);
                                                                           modified=true;
                                                                        }
                                                         }
                                 VirtualSL =currentSL;
                                 if(isBuy? (SymbolInfoDouble(TradeSym,SYMBOL_BID)<currentSL):
                                            (SymbolInfoDouble(TradeSym,SYMBOL_ASK)>currentSL)){
                                             trade.PositionClose(orderTicket,(ulong)(CurrSpread));
                                             return(true);
                                            }
                               // update the table properly
                               if(NormalizeDouble(effectiveSL,SymDigits)!= NormalizeDouble(VirtualSL,SymDigits)){
                                 newVSlValue = NormalizeDouble(VirtualSL,SymDigits);
                                 newVSlTicket = orderTicket;
                                 for(vSlSaveIdx =0; vSlSaveIdx < VirtualSLStoreSize;vSlSaveIdx = vSlSaveIdx +1){
                                    if(VirtualSLStore[vSlSaveIdx][0]==newVSlTicket){
                                       VirtualSLStore[vSlSaveIdx][1] = newVSlValue;
                                       break;
                                    }
                                 }

                               }
                              }




      if(modified){
         orderModified =true;
      }
      

}
return(orderModified);
}


