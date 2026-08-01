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
#property  description "Waka waka EA"

#include <Trade\Trade.mqh>
      CTrade         Trade;
      CPositionInfo  posInfo;
      COrderInfo     ordInfo;
int OnInit()
  {
//---
   
//---
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
   
  }
//+------------------------------------------------------------------+
