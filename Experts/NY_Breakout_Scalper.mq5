//+------------------------------------------------------------------+
//|                                           NY_Breakout_Scalper.mq5 |
//|  NY-open range breakout scalper for XAUUSD.                       |
//|                                                                   |
//|  - Builds the pre-NY range (default 13:30-16:30 broker time,      |
//|    i.e. late London through 09:30 ET on a GMT+3 broker).          |
//|  - At NY open places a buy stop above the range high and a sell   |
//|    stop below the range low (small buffer), OCO: first fill       |
//|    cancels the sibling. One setup per day.                        |
//|  - SL = fraction of the range (clamped), TP = R multiple,         |
//|    breakeven at +1R, optional point trailing.                     |
//|  - Orders expire at window end; positions force-closed at the     |
//|    session close hour. No overnight exposure.                     |
//|  - Designed to be validated with real ticks + random execution    |
//|    delay: distances are wide enough that slippage is a cost,      |
//|    not the whole edge.                                            |
//+------------------------------------------------------------------+
#property copyright "built for backtesting"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

CTrade        trade;
CPositionInfo positionInfo;
COrderInfo    orderInfo;

enum ENUM_BO_LOT_MODE
  {
   BO_RISK_PCT = 0,   // Risk % of balance per trade
   BO_FIXED    = 1,   // Fixed lots
   BO_FLIP     = 2    // Lots per $100 balance (aggressive compounding)
  };

input group "=== General ==="
input long   InpMagicNumber   = 20260707;   // Magic number
input int    InpSlippage      = 50;         // Slippage (points)

input group "=== Session (broker time, GMT+3 assumed) ==="
input int    InpRangeStartHour = 13;        // Range start hour
input int    InpRangeStartMin  = 30;        // Range start minute
input int    InpRangeEndHour   = 16;        // Range end hour = NY open
input int    InpRangeEndMin    = 30;        // Range end minute
input int    InpWindowEndHour  = 19;        // Last hour to hold pending orders
input int    InpCloseHour      = 20;        // Force-close positions at this hour

input group "=== Breakout Setup ==="
input int    InpBufferPts     = 50;         // Entry buffer beyond range (points)
input int    InpMinRangePts   = 300;        // Skip day if range smaller (points)
input int    InpMaxRangePts   = 2500;       // Skip day if range larger (points)
input int    InpMaxSpreadPts  = 60;         // Skip setup if spread wider (points)

input group "=== Risk / Exits ==="
input double InpSLRangeFrac   = 0.50;       // SL = this fraction of range
input int    InpMinSLPts      = 300;        // SL floor (points)
input int    InpMaxSLPts      = 1500;       // SL cap (points)
input double InpTPRR          = 1.5;        // TP at this R multiple
input bool   InpUseBreakEven  = true;       // Move SL to BE at +1R
input int    InpBEBufferPts   = 30;         // BE lock-in beyond entry (points)
input int    InpTrailPts      = 0;          // Trail SL by points after BE (0=off)

input group "=== Money Management ==="
input ENUM_BO_LOT_MODE InpLotMode = BO_RISK_PCT; // Lot mode
input double InpRiskPercent   = 1.0;        // Risk % (risk mode)
input double InpFixedLots     = 0.01;       // Fixed lots (fixed mode)
input double InpLotsPer100    = 0.20;       // Lots per $100 (flip mode)

double lotStep = 0, minLot = 0, maxLot = 0;
long   lastSetupDay = 0;                    // day marker: one setup per day

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
  }
//+------------------------------------------------------------------+
void OnTick()
  {
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   ManagePositions(dt);
   ManagePendings(dt);
   TrySetup(now, dt);
  }
//+------------------------------------------------------------------+
//| Breakeven / trailing / session close for our open positions      |
//+------------------------------------------------------------------+
void ManagePositions(const MqlDateTime &dt)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!positionInfo.SelectByIndex(i))
         continue;
      if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != InpMagicNumber)
         continue;

      ulong  ticket = positionInfo.Ticket();

      if(dt.hour >= InpCloseHour)
        {
         trade.PositionClose(ticket);
         continue;
        }

      double entry = positionInfo.PriceOpen();
      double sl    = positionInfo.StopLoss();
      double tp    = positionInfo.TakeProfit();
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(positionInfo.PositionType() == POSITION_TYPE_BUY)
        {
         double slDist = entry - sl;
         if(slDist <= 0)
            continue;
         double newSL = sl;
         if(InpUseBreakEven && sl < entry && bid - entry >= slDist)
            newSL = NormalizeDouble(entry + InpBEBufferPts * _Point, _Digits);
         if(InpTrailPts > 0 && newSL >= entry)
            newSL = MathMax(newSL, NormalizeDouble(bid - InpTrailPts * _Point, _Digits));
         if(newSL > sl + _Point / 2)
            trade.PositionModify(ticket, newSL, tp);
        }
      else
        {
         double slDist = sl - entry;
         if(slDist <= 0)
            continue;
         double newSL = sl;
         if(InpUseBreakEven && sl > entry && entry - ask >= slDist)
            newSL = NormalizeDouble(entry - InpBEBufferPts * _Point, _Digits);
         if(InpTrailPts > 0 && newSL <= entry)
            newSL = MathMin(newSL, NormalizeDouble(ask + InpTrailPts * _Point, _Digits));
         if(newSL < sl - _Point / 2)
            trade.PositionModify(ticket, newSL, tp);
        }
     }
  }
//+------------------------------------------------------------------+
//| OCO handling and window cleanup for our pending orders           |
//+------------------------------------------------------------------+
void ManagePendings(const MqlDateTime &dt)
  {
   bool havePosition = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!positionInfo.SelectByIndex(i))
         continue;
      if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
        {
         havePosition = true;
         break;
        }
     }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!orderInfo.SelectByIndex(i))
         continue;
      if(orderInfo.Symbol() != _Symbol || orderInfo.Magic() != InpMagicNumber)
         continue;
      // OCO: a fill on one side kills the other; window end kills both
      if(havePosition || dt.hour >= InpWindowEndHour)
         trade.OrderDelete(orderInfo.Ticket());
     }
  }
//+------------------------------------------------------------------+
//| Once per day at NY open: build the range, place the OCO straddle |
//+------------------------------------------------------------------+
void TrySetup(datetime now, const MqlDateTime &dt)
  {
   long dayMarker = (long)dt.year * 1000 + dt.day_of_year;
   if(dayMarker == lastSetupDay)
      return;
   if(dt.day_of_week == SATURDAY || dt.day_of_week == SUNDAY)
      return;

   datetime midnight  = now - (now % 86400);
   datetime rangeFrom = midnight + InpRangeStartHour * 3600 + InpRangeStartMin * 60;
   datetime rangeTo   = midnight + InpRangeEndHour * 3600 + InpRangeEndMin * 60;

   if(now < rangeTo)
      return;                       // NY not open yet
   if(dt.hour >= InpWindowEndHour)
     {
      lastSetupDay = dayMarker;     // too late today
      return;
     }

   // nothing of ours may be live when a new setup is placed
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!positionInfo.SelectByIndex(i))
         continue;
      if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
         return;
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!orderInfo.SelectByIndex(i))
         continue;
      if(orderInfo.Symbol() == _Symbol && orderInfo.Magic() == InpMagicNumber)
         return;
     }

   MqlRates rates[];
   int copied = CopyRates(_Symbol, PERIOD_M1, rangeFrom, rangeTo, rates);
   if(copied < 30)
      return;                       // history not ready yet, retry next tick

   double rangeHigh = rates[0].high;
   double rangeLow  = rates[0].low;
   for(int i = 1; i < copied; i++)
     {
      if(rates[i].high > rangeHigh) rangeHigh = rates[i].high;
      if(rates[i].low  < rangeLow)  rangeLow  = rates[i].low;
     }

   double rangePts = (rangeHigh - rangeLow) / _Point;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spreadPts = (ask - bid) / _Point;

   lastSetupDay = dayMarker;        // one attempt per day from here on

   if(rangePts < InpMinRangePts || rangePts > InpMaxRangePts)
     {
      PrintFormat("setup skipped: range %.0f pts outside [%d, %d]",
                  rangePts, InpMinRangePts, InpMaxRangePts);
      return;
     }
   if(spreadPts > InpMaxSpreadPts)
     {
      PrintFormat("setup skipped: spread %.0f pts > %d", spreadPts, InpMaxSpreadPts);
      return;
     }

   double slPts = MathMin(MathMax(rangePts * InpSLRangeFrac, InpMinSLPts), InpMaxSLPts);
   double slDist = slPts * _Point;
   double tpDist = slDist * InpTPRR;
   double buffer = InpBufferPts * _Point;

   datetime expiry = midnight + InpWindowEndHour * 3600;

   double buyPrice = NormalizeDouble(rangeHigh + buffer + spreadPts * _Point, _Digits);
   double buySL    = NormalizeDouble(buyPrice - slDist, _Digits);
   double buyTP    = NormalizeDouble(buyPrice + tpDist, _Digits);

   double sellPrice = NormalizeDouble(rangeLow - buffer, _Digits);
   double sellSL    = NormalizeDouble(sellPrice + slDist, _Digits);
   double sellTP    = NormalizeDouble(sellPrice - tpDist, _Digits);

   double buyLots  = CalcLots(slPts, ORDER_TYPE_BUY, buyPrice);
   double sellLots = CalcLots(slPts, ORDER_TYPE_SELL, sellPrice);
   if(buyLots < minLot || sellLots < minLot)
     {
      Print("setup skipped: lot size below minimum (margin or risk too small)");
      return;
     }

   trade.OrderOpen(_Symbol, ORDER_TYPE_BUY_STOP, buyLots, 0, buyPrice,
                   buySL, buyTP, ORDER_TIME_SPECIFIED, expiry, "NY_BO");
   trade.OrderOpen(_Symbol, ORDER_TYPE_SELL_STOP, sellLots, 0, sellPrice,
                   sellSL, sellTP, ORDER_TIME_SPECIFIED, expiry, "NY_BO");

   PrintFormat("setup: range %.2f-%.2f (%.0f pts) buy@%.2f sell@%.2f sl=%.0fpts lots=%.2f",
               rangeLow, rangeHigh, rangePts, buyPrice, sellPrice, slPts, buyLots);
  }
//+------------------------------------------------------------------+
//| Lot sizing with margin fit (integer lot steps, market-type check)|
//+------------------------------------------------------------------+
double CalcLots(double slPts, ENUM_ORDER_TYPE marketType, double price)
  {
   double lots = 0;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(InpLotMode == BO_FIXED)
      lots = InpFixedLots;
   else if(InpLotMode == BO_FLIP)
      lots = balance * InpLotsPer100 / 100.0;
   else
     {
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickSize <= 0 || tickValue <= 0 || slPts <= 0)
         return 0;
      double moneyPerPointPerLot = tickValue * (_Point / tickSize);
      double riskMoney = balance * InpRiskPercent / 100.0;
      lots = riskMoney / (slPts * moneyPerPointPerLot);
     }

   int k = (int)MathFloor(lots / lotStep + 0.0000001);
   int kMin = (int)MathCeil(minLot / lotStep - 0.0000001);
   int kMax = (int)MathFloor(maxLot / lotStep + 0.0000001);
   if(k > kMax) k = kMax;

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginRequired = 0;
   for(; k >= kMin; k--)
     {
      double tryLots = NormalizeDouble(k * lotStep, 2);
      if(OrderCalcMargin(marketType, _Symbol, tryLots, price, marginRequired) &&
         marginRequired < freeMargin * 0.45)   // both OCO legs must fit
         return tryLots;
     }
   return 0;
  }
//+------------------------------------------------------------------+
