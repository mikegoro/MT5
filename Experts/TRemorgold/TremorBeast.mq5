//+------------------------------------------------------------------+
//|                                                          wakawaka.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+

#property copyright "Mikey"
#property link "Mikey"
#property version "1.00"
#property strict
#property  description "TramorBeast EA"

#include<Trade\Trade.mqh>
 CTrade trade;
 COrderInfo ordinfo;
 CPositionInfo positionInfo;
//+------------------------------------------------------------------+
//|  Enum for lotsize calculation                                    |
//+------------------------------------------------------------------+
 enum enum_lotsizing{
   Manual_lotsize=0,
   Tiered_lotsizing=1,
   RiskCalefactor=2,
 };

//+------------------------------------------------------------------+
//| Trade Setup                                                      |
//+------------------------------------------------------------------+

input group "====TRADE SETUP===="
input int InpMagic=456788;
input string TradeComment="TramorBeast";


//+------------------------------------------------------------------+
//| Money Management /Lotsize calculations                           
//+------------------------------------------------------------------+

input group "====Money management/Lotsize calculations===="
input enum_lotsizing Lotsizing_method  =1; //lotsizing calculation method
input double TieredLot                 =30; //Tiered lotsizing Risk Meter (1-100 max)
double TieredLotEff                   =0;  // Runtime:TieredLot Clamped to valid 1-100 range
input double FixedLots               = 0.01; //fixed Lots
input double riskScaling            =1;

//+------------------------------------------------------------------+
//| Prop and entry Adjustments                                       |
//+------------------------------------------------------------------+

input group "====PROPFIRM AND ADJUSTMENTS===="
input double AdjustEntry         =0; //Adjust entry (in points)
input double AdjustSL            =0; //Adjust SL(in points)
input double AdjustTP            =0; //Adjust TP(in points)
input double AdjustTrailSL       =0; //Adjust trailing SL(in points)
input double AdjustSalvageExit   =0; //Adjust Salvage exit(in points)
input double AdjustBreakEven     =0; //Adjust Break Even(in points)

//+------------------------------------------------------------------+
//| Strategy parameters                                              |           
//+------------------------------------------------------------------+

input group "==== Strategy parameters ===="
input ENUM_TIMEFRAMES fractalTF=PERIOD_M5; //FRACTAl Detectiontime Frame;
input ENUM_TIMEFRAMES rescanTF=PERIOD_M15; //ENTREY RESCAN TIMEFRAME

input int fractalRight                =5 ; // fractual right bars
input int fractalLeft                =5; // fractual left bars
input int fractalMaxSearch            =200; // fractual max search(bars)

input int maxPending                  =3;     // max pending orders
input int pendExpiryHrs               =15;    // pending order Expiry (hours)

input  ENUM_TIMEFRAMES exitScanTf=    PERIOD_M1; //Exit Scan Timeframe
input int maxPositions                =10; //max positions

input double fractalMinDistPct        =0.02; //fractal min Clearance (% of price)
input double pendDedupDist            =5.0; //pending Dedup Distance(points)

input double buyEntryPct              =-0.08; //Buy Entry Offset(% of price)
input double sellEntryPct             =-0.08; //sell Offset(% of price)

input double slPct                    =2; // Stop loss (%of price)
input double tpPct                    =0.7; //take profit (%of Price)

input double trailPct                 =0.2;  //Trailing SL Distance3 (%of price)
input double trailMinProfitPct        =0.2;  //Trailing sl min Profit Trigger (% of price)
input double trailMaxSLPct            =1;     //Trailing Sl max (% of price)

input double salvageTriggerPct        =1; //salvage Trigger (% of  Price)
input double salvageExitPct           =0.15; //salvage Exit (%of Price)

input double beTriggerPct              =0.1; //Breakeven Trigger (%of price)
input double beLockPct                =0.025; //Breakeven Lock (%of price)

input double riskWeight               =0.055; //Risk weight

//+------------------------------------------------------------------+
//| Global  Variables                                                |           
//+------------------------------------------------------------------+
double  CurrSpread;  //This is to look for the broker's current Spread  in Points
ENUM_TIMEFRAMES FractalTf;
ENUM_TIMEFRAMES RescanTf;
int    FractalRight;
int    FractalLeft;
int    FractalMaxSearch;
int    MaxPendingOrders;
int    MaxPositions;
double PendingDedupDist;
int    PendingExpiryHrs;
int    ActiveMagic;
ENUM_TIMEFRAMES ExitScanTf;
int      SymDigits;
double    StopLevelDist;
double   PipFactor;
double    FreezeLevelDist;
string   ActiveComment;
string    TradeSym;
double    SymPoint;

int          DayswitchBufferMin=30;
double       FractalMinDist;
double       BuyEntryOffset;
double       sellEntryOffset;
bool         virtual_expiration=true;

double      SLDist;
double      TPDist;
double      TrailDist;
double      TrailMinProfit;
double      TrailMaxSL;
double      TrailStep=0.1;
double      SalvageExitDist;
double      SalvageTrigger;
double      BeTrigger; 
double      BeLockDist;

double      MaxLotCap=100.0;
double      WeightedRiskDivisor=1.0;


double     LastSwingHigh=0.0;
double     LastSwingLow=0.0;
double     virtualSL=0.0;


double     VirtualSLStore[20][2];
double     OrderPriceMap[100][2];
int        VirtualSLStoreSize=20;

double      StrategyLots=0.01;
int         LastTradeTicket=0;
int         PendingExpirySeconds;


double      SwingLow=0.0;   //valiables to store the last swing low 
double      SwingHigh=0.0;  // variable to store the last swing High;


int        LastHour=0;
datetime   PendingExpiry=0;
int        PerStrategyRescanBars=0;
int        PerStrategyPendingRescanBars=0;












int OnInit()
  {
//---
   int  vslResetOuterIdx;
   int  vslResetInnerIdx;
   MqlDateTime nowDT;

   TieredLotEff=TieredLot;
   if (TieredLotEff>100) TieredLotEff=100.0;
   if(TieredLotEff<0.0)  TieredLotEff=1.0;

   ActiveComment=TradeComment;
   ActiveMagic=InpMagic;
   TradeSym=Symbol();
   SymPoint =SymbolInfoDouble(TradeSym,SYMBOL_POINT);  //GETTING THE VALUE OF THE SYMBOL POINT
   PipFactor=SymPoint;

   if(((double)SymbolInfoInteger(TradeSym,SYMBOL_DIGITS)==3.0 ||(double)SymbolInfoInteger(TradeSym,SYMBOL_DIGITS)==5.0))
     {
      PipFactor=SymPoint*10.0;
     }
   if(SymbolInfoInteger(TradeSym,SYMBOL_DIGITS)==1){
      PipFactor=SymPoint*10.0;
     }
   SymDigits=(int)SymbolInfoInteger(TradeSym,SYMBOL_DIGITS); //getting the values of symbol digits
   CurrSpread=SymbolInfoDouble(TradeSym,SYMBOL_ASK)-SymbolInfoDouble(TradeSym,SYMBOL_BID);  //GETTING THE SPREAD OF THE BROKER
   StopLevelDist=(double)SymbolInfoInteger(TradeSym,SYMBOL_TRADE_STOPS_LEVEL)*SymPoint;    //Getting the Stop Level Distance
   FreezeLevelDist=(double)SymbolInfoInteger(TradeSym,SYMBOL_TRADE_FREEZE_LEVEL)*SymPoint;  

   FractalTf=fractalTF;
   RescanTf=rescanTF;
  FractalRight=fractalRight;
  FractalLeft=fractalLeft;
  FractalMaxSearch=fractalMaxSearch;
  MaxPendingOrders=maxPending;
  MaxPositions=maxPositions;
  PendingDedupDist=pendDedupDist; 
  PendingExpiryHrs=pendExpiryHrs;
  ExitScanTf=exitScanTf;

  ActivateStrategyContext();
//..validation:User must not input <=0 fopr critical distance
  if(SLDist<=0.0){
    SLDist=1.0;
  }
if (TPDist<=0.0)
{
  TPDist=1.0;
}
//.. validation :BE Lock must be smaller than BE trigger
if (BeLockDist>BeTrigger){
  BeLockDist=BeTrigger/2;
}

//-- validation Broker minimum stop and freeze levels
if(TrailDist!=0.0 && TrailDist<FreezeLevelDist/PipFactor){
  TrailDist=FreezeLevelDist/PipFactor;
}
if(TrailDist!=0.0 &&TrailDist<StopLevelDist/PipFactor){
  TrailDist=StopLevelDist/PipFactor;
}
if(SLDist<StopLevelDist*2.0/PipFactor){
  SLDist=StopLevelDist*2.0/PipFactor;
}
if(TPDist<StopLevelDist*2.0/PipFactor){
  TPDist=StopLevelDist*2.0/PipFactor;
}

if(FractalMinDist<StopLevelDist*2.0/PipFactor){
  FractalMinDist=StopLevelDist*2.0/PipFactor;
}
//---validation:Fractal Parameters
if(FractalRight<1){
  FractalRight=1;
}
if(FractalLeft<1){
  FractalLeft=1;
}
if(FractalMinDist<0.01){
  FractalMinDist=0.1;
}

///--- pending expiry calculatio(conver hours to seconds)
PendingExpirySeconds=PendingExpiryHrs*60*60;

if(PendingExpiryHrs>0){
    PendingExpiry=TimeCurrent()+PendingExpirySeconds;
}
else{
  PendingExpiry=0;
}

//--virtual expiration overrides broker expiration
if(virtual_expiration){
  PendingExpiry=0;
}

//---Find initial swing points
FindSwingPoint(FractalTf,true);
FindSwingPoint(FractalTf,false);

LastSwingHigh=NormalizeDouble(SwingHigh,SymDigits);
LastSwingLow=NormalizeDouble(SwingLow,SymDigits);
//--refresh broker freeze level
FreezeLevelDist=(double)SymbolInfoInteger(TradeSym,SYMBOL_TRADE_FREEZE_LEVEL);
virtualSL=0.0;
//---Cap MaxLotCap to brokers max volume
if(MaxLotCap>SymbolInfoDouble(TradeSym,SYMBOL_VOLUME_MAX)){
MaxLotCap=SymbolInfoDouble(TradeSym,SYMBOL_VOLUME_MAX);
}

//----iNITIALIZE vIRTUAL SL store to zeros (20 rows x2 cols)
for(vslResetOuterIdx=0; vslResetOuterIdx<VirtualSLStoreSize;vslResetOuterIdx++){
  for(vslResetInnerIdx=0; vslResetInnerIdx<2;vslResetInnerIdx++){
    VirtualSLStore[vslResetOuterIdx][vslResetInnerIdx]=0.0;
  }
}

//--Record Current hour

TimeToStruct(TimeCurrent(),nowDT);
LastHour=nowDT.hour;


//Reset Per-strategy rescan bar counters
PerStrategyPendingRescanBars=0;
PerStrategyRescanBars=0;


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
void OnTick()
  {
//---
ActivateStrategyContext();
RunStrategyTick();
   
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Startegy  functions                                              |
//+------------------------------------------------------------------+

void ActivateStrategyContext(){
  CurrSpread=SymbolInfoDouble(TradeSym,SYMBOL_ASK)-SymbolInfoDouble(TradeSym,SYMBOL_BID);
  StopLevelDist=(double)SymbolInfoInteger(TradeSym,SYMBOL_TRADE_STOPS_LEVEL)*SymPoint;
  FreezeLevelDist=(double)SymbolInfoInteger(TradeSym,SYMBOL_TRADE_FREEZE_LEVEL)*SymPoint;

  double currentRefPrice=SymbolInfoDouble(TradeSym,SYMBOL_BID);

  FractalMinDist  =fractalMinDistPct / 100.0*currentRefPrice / PipFactor;
  BuyEntryOffset  =AdjustEntry + NormalizeDouble(buyEntryPct / 100.0 * currentRefPrice / PipFactor, 0);
  BuyEntryOffset  =AdjustEntry + NormalizeDouble(sellEntryPct / 100.0 * currentRefPrice / PipFactor, 0);
  SLDist          =AdjustSL + slPct / 100.0 * currentRefPrice / PipFactor;
  TPDist          =AdjustTP + tpPct / 100.0 * currentRefPrice / PipFactor;
  TrailDist       =AdjustTrailSL + trailPct / 100 * currentRefPrice /  PipFactor;
  TrailMinProfit  =trailMinProfitPct / 100.0 * currentRefPrice / PipFactor;
  TrailMaxSL      =trailMaxSLPct / 100.0 * currentRefPrice / PipFactor;
  SalvageExitDist =AdjustSalvageExit + salvageExitPct / 100 * currentRefPrice / PipFactor;
  SalvageTrigger  =salvageTriggerPct / 100.0 * currentRefPrice/PipFactor;
  BeTrigger       =beTriggerPct / 100 * currentRefPrice/PipFactor;
  BeLockDist      =AdjustBreakEven + beLockPct / 100.0 * currentRefPrice / PipFactor;
}
//+------------------------------------------------------------------+
//| RunStrategyTick - calls both buy and sell entry functions       /                                             
//+------------------------------------------------------------------+
void RunStrategyTick(){
  PlaceEntry(true);
  PlaceEntry(false);
  CloseAll(0);
}

//+------------------------------------------------------------------+
//| FindSwingPoint - Locate The most recent Valid Fractal high/Low   /                                             
//+------------------------------------------------------------------+

double FindSwingPoint(ENUM_TIMEFRAMES timeframe,bool findHigh){
  bool found  = false;
  bool olderOk = false;
  bool newerOk = false;
  int barIdx;
  int newerScan;
  int olderScan;
  double candidateExtreme;
  int candidateBar;
  double historicalExtreme;
  int histIdx;
  double normalizedPrice;
  int ordIdx;
  bool dupFound;
  double result;
  
  newerOk =false;
  barIdx =FractalLeft+1;
  do{
    olderOk = true;
    newerOk = true;

    for(newerScan=barIdx;newerScan>=barIdx-FractalLeft;newerScan--){
      if(findHigh?(iHigh(TradeSym,timeframe,newerScan)>iHigh(TradeSym,timeframe,barIdx)):
        (iLow(TradeSym,timeframe,newerScan)<iLow(TradeSym,timeframe,barIdx))
    
    ){
      newerOk  =false;
    }

    }

    for(olderScan = barIdx; olderScan <= barIdx + FractalRight; olderScan++ ){
      if(findHigh ? (iHigh(TradeSym,timeframe,olderScan) > iHigh(TradeSym,timeframe,barIdx)):
       (iLow(TradeSym,timeframe,olderScan) < iLow(TradeSym,timeframe,barIdx))){
        olderOk=false;
       }
    }
    if(newerOk && olderOk && (findHigh ?
    (iHigh(TradeSym,timeframe,barIdx) > FractalMinDist * PipFactor + SymbolInfoDouble(TradeSym,SYMBOL_ASK)):
    (iLow(TradeSym,timeframe,barIdx) < SymbolInfoDouble(TradeSym,SYMBOL_BID)-FractalMinDist * PipFactor ) ) ){
      candidateExtreme= findHigh ? iHigh(TradeSym,timeframe,barIdx):
                                   iLow(TradeSym,timeframe,barIdx);
      candidateBar=barIdx;
      historicalExtreme=findHigh ? iHigh(TradeSym,FractalTf,0):
                                    iLow(TradeSym,FractalTf,0);

      for(histIdx=1;histIdx<=candidateBar;histIdx+=1){
        if(findHigh?(iHigh(TradeSym,FractalTf,histIdx) > historicalExtreme):
                    (iLow(TradeSym,FractalTf,histIdx) < historicalExtreme)){
                      historicalExtreme = findHigh ? iHigh(TradeSym,FractalTf,histIdx):
                                                      iLow(TradeSym,FractalTf,histIdx);

                    }
      }

      if(findHigh ? (candidateExtreme >= historicalExtreme):
                    (candidateExtreme <= historicalExtreme)){
                      normalizedPrice=NormalizeDouble(candidateExtreme,SymDigits);
                      dupFound=false;
                      for(ordIdx = 0; ordinfo.SelectByIndex(ordIdx) ; ordIdx++){
                        if(findHigh){
                          if(ordinfo.Magic()!=ActiveMagic ||
                           ordinfo.Symbol()!= TradeSym ||
                           ordinfo.OrderType()!= ORDER_TYPE_BUY_STOP ||!
                           (MathAbs(ordinfo.PriceOpen()-(normalizedPrice-sellEntryOffset*PipFactor))< pendDedupDist*PipFactor))
                                 continue;
                        }else{
                          if(ordinfo.Magic() !=ActiveMagic ||
                          ordinfo.Symbol() != TradeSym ||
                          ordinfo.OrderType() != ORDER_TYPE_SELL_STOP ||  
                          !(MathAbs(ordinfo.PriceOpen()-(normalizedPrice-sellEntryOffset*PipFactor))<PendingDedupDist*PipFactor))
                          continue;
                        
                        
                        }
                        dupFound=true;
                        break;

                      }

                      if(!dupFound){
                        found=true;
                        result=normalizedPrice;
                        if(findHigh){SwingHigh=result;}
                        else{SwingLow=result;}
                        break;
                      }
                    }


    }
    barIdx++;
    if(barIdx<=FractalMaxSearch)continue;
    if(findHigh){SwingHigh=0.0;}
    else{SwingLow=0.0;}

  }while (!found);

  return(findHigh ? SwingHigh:SwingLow);
}

//+------------------------------------------------------------------+
//| PriceEntry- Place a pending buy/sell Stop at Swing Point         /                                             
//+------------------------------------------------------------------+
bool PlaceEntry(bool isBuy){
   bool   swingFound;
   double entryPrice;
   double slippageEntryPrice;
   double slPrice;
   double tpPrice;
   double swingPrice;
   int    pendIdx;
   bool   dupfound;
   int    pendCount;
   int    pendCountIdx;
   double worstPendingPrice;
   int    pendScanIdx;
   double entryPriceCheck;
   int    pendScanidx2;
   bool betterPendingExists;
   bool   volumeValid;
   int    maxOrdersLimit;
   bool   orderLimitOk;
   int    lastErrorCode;
   double filledEntryPrice;
   long   newTicket;
   ENUM_ORDER_TYPE_TIME pendTimeType;
   int    mapSlot;
   int    pendType;

   //---1. Decide pending order type based on isBuy

  pendType=(int)(isBuy?ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP);

  //--2. Find the relevant swing point
  if(isBuy){
    FindSwingPoint(FractalTf,true);
    swingPrice=SwingHigh;
  }else{
    FindSwingPoint(FractalTf,false);
    swingPrice=SwingLow;
  }
  swingFound=false;
  dupfound=false;
   //3. Duplicate check across pending Orders
   for(pendIdx=0; ordinfo.SelectByIndex(pendIdx);pendIdx=pendIdx+1){
    if(ordinfo.Magic()!=ActiveMagic ||
     ordinfo.Symbol() !=TradeSym || 
     (int)ordinfo.OrderType() !=pendType)
     continue;
     if(!(MathAbs(ordinfo.PriceOpen()-(isBuy ? (BuyEntryOffset * PipFactor + swingPrice) : 
                                                (swingPrice-sellEntryOffset * PipFactor))) < PendingDedupDist * PipFactor))
                                                continue;
        dupfound=true;
        break; 

   }
   if(!dupfound){
    //---4. Count exixting pending orders of this type
    pendCount=0;
    for(pendCountIdx=0; ordinfo.SelectByIndex(pendCountIdx); pendCountIdx = pendCountIdx + 1){
      if(ordinfo.Magic() != ActiveMagic || ordinfo.Symbol() != TradeSym || (int)ordinfo.OrderType() != pendType)
      continue;
      pendCount = pendCount + 1;
    }

    //---5. If at max, find the worst existing pending Price
    if( pendCount== MaxPendingOrders){
      worstPendingPrice=isBuy ? DBL_MAX :0.0;
      for(pendScanIdx=0;ordinfo.SelectByIndex(pendScanIdx); pendScanIdx = pendScanIdx + 1){
        if(ordinfo.Magic()!= ActiveMagic || ordinfo.Symbol() != TradeSym || (int)ordinfo.OrderType() != pendType)
        continue;
        if(isBuy ? !( ordinfo.PriceOpen()< worstPendingPrice):!(ordinfo.PriceOpen() > worstPendingPrice))
        continue;
        worstPendingPrice= ordinfo.PriceOpen();

      }
      //---6. if new Swing is worse than exsiting , bail
      if (isBuy){
        if(SwingHigh>worstPendingPrice){
          return(false);
        }
      }
      else{
        if(SwingLow<worstPendingPrice){
          return(false);
        }
      }
    }
    if(isBuy){
      swingFound=true;
      LastSwingHigh=NormalizeDouble(SwingHigh,SymDigits);
    }
    else{
      swingFound=true;
      LastSwingLow = NormalizeDouble(SwingLow,SymDigits);
    }
    //--- 8 Bail if swing is invalid(0)
    if(isBuy){
      if(LastSwingHigh == 0.0){return(false);}
    }
    else{
      if(LastSwingLow == 0.0 ){return(false);}
    }


//--- 9. if Swing Found, calculate entry Price with offset
 if(swingFound){
  if(isBuy){
    entryPrice = NormalizeDouble(LastSwingHigh + BuyEntryOffset * PipFactor,SymDigits);
  }
  else{
    entryPrice=NormalizeDouble(LastSwingLow -sellEntryOffset * PipFactor, SymDigits);
  }
  entryPriceCheck = entryPrice;
  betterPendingExists=false;
 }
  //--- 10. Second duplicate Check: is there already a BETTER PENDING order?
  for( pendScanidx2 =0; ordinfo.SelectByIndex(pendScanidx2); pendScanidx2 = pendScanidx2 + 1){
    if(ordinfo.Magic() != ActiveMagic || 
    ordinfo.Symbol() != TradeSym || (int)ordinfo.OrderType() != pendType)
    continue;
    betterPendingExists = true;
    break;
  }
  if(betterPendingExists){
    return(false);
  }
  //--- 11. Margin Check
  ENUM_ORDER_TYPE marginOrderType =(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
  double marginPrice = (isBuy ? SymbolInfoDouble(TradeSym,SYMBOL_ASK):
                                SymbolInfoDouble(TradeSym,SYMBOL_BID));
  double marginRequired =0.0;

  if(!OrderCalcMargin(marginOrderType,TradeSym,StrategyLots,marginPrice,marginRequired)||
  AccountInfoDouble(ACCOUNT_MARGIN_FREE)- marginRequired <= 0.0){
    return(false);
  }

  //--- 12. calculate SL/TP prices
  if(isBuy){
    slippageEntryPrice = entryPrice;
    slPrice = NormalizeDouble( entryPrice - SLDist * PipFactor, SymDigits);
    tpPrice = NormalizeDouble(TPDist * PipFactor + entryPrice, SymDigits);
  }else{
    slippageEntryPrice = entryPrice;
    slPrice = NormalizeDouble(SLDist * PipFactor + entryPrice, SymDigits);
    tpPrice =NormalizeDouble(entryPrice - TPDist * PipFactor, SymDigits);
  }
  ///--- 13. Volume validation
  if(StrategyLots < SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MIN)){
    volumeValid = false;
  }else if( StrategyLots> SymbolInfoDouble(TradeSym,SYMBOL_VOLUME_MAX)){
    volumeValid = false;

  }
  else if(MathAbs(NormalizeDouble(StrategyLots / SymbolInfoDouble(TradeSym,SYMBOL_VOLUME_STEP),0) * 
                 SymbolInfoDouble(TradeSym,SYMBOL_VOLUME_STEP) - StrategyLots) > 0.0000001 ){
                  volumeValid=false;
                 }
                 else{
                  volumeValid=true;
                 }
  //--14 . Broker max orders limit check

  maxOrdersLimit= (int) AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
  if(maxOrdersLimit==0){
    orderLimitOk=true;
  }else{
    orderLimitOk=(PositionsTotal() + OrdersTotal()) < maxOrdersLimit;
  }
  if((!volumeValid) || (!orderLimitOk)){
    return(false);
  }

  //--- 15 . Freeze/Stop Level Check
  if( ( isBuy? (SymbolInfoDouble(TradeSym,SYMBOL_ASK) < slippageEntryPrice - FreezeLevelDist * PipFactor && 
            SymbolInfoDouble(TradeSym,SYMBOL_ASK) < slippageEntryPrice - StopLevelDist * PipFactor) :
            (SymbolInfoDouble(TradeSym,SYMBOL_BID) > FreezeLevelDist * PipFactor + slippageEntryPrice && 
            SymbolInfoDouble(TradeSym, SYMBOL_BID) > StopLevelDist   * PipFactor + slippageEntryPrice))){
              //---16. Configure trade object
              trade .SetExpertMagicNumber(ActiveMagic);
              trade.SetTypeFilling(ORDER_FILLING_RETURN);

              //-- 17. CALCULATE expiration
              if(PendingExpiryHrs > 0){
                PendingExpiry = TimeCurrent() + PendingExpirySeconds;
              }
              else{
                PendingExpiry=0;
              }
              if(virtual_expiration){
                PendingExpiry=0;
              }
              //----18. Determine expiration type
              pendTimeType=(PendingExpiry>0)? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;

              // 19. Send the order
              if(trade.OrderOpen(TradeSym, isBuy ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP,
                                StrategyLots,0,slippageEntryPrice,slPrice,tpPrice,
                                pendTimeType,PendingExpiry, ActiveComment 
                )){
                  LastTradeTicket = (int)trade.ResultOrder();
                }
                else{
                  LastTradeTicket =-1;
                }

                //--- 20 Handle resulst /errors
                if(LastTradeTicket <= 0){
                  lastErrorCode = GetLastError();
                  if(lastErrorCode == 132){
                    ResetLastError();
                  }
                  else{
                    filledEntryPrice = entryPrice;
                    newTicket = LastTradeTicket;

                    //---- 21. Record in OrderPriceMap
                    for(mapSlot=0; mapSlot<100; mapSlot = mapSlot+1){
                      if(!(OrderPriceMap[mapSlot][0])) continue;
                      OrderPriceMap[mapSlot][0] = (double)newTicket;
                      OrderPriceMap[mapSlot][1] = filledEntryPrice;
                      break;
                    }
                  }
                }


            }
  }
  return(true);

}

//+------------------------------------------------------------------+
//| CloseAll - Placeholder for order cleanup (to be added)           /                                             
//+------------------------------------------------------------------+

void CloseAll(int reasen){

}