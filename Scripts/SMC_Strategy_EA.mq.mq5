//+------------------------------------------------------------------+
//|                                             SMC_Strategy_EA.mq5  |
//|                         Smart Money Concepts starter EA for MT5  |
//+------------------------------------------------------------------+
#property copyright "Codex"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

enum TradeDirection
{
   TradeBoth = 0,
   TradeLongOnly = 1,
   TradeShortOnly = 2
};

input TradeDirection InpTradeDirection = TradeBoth;
input int             InpSwingLeft = 3;
input int             InpSwingRight = 3;
input int             InpStructureLookback = 220;
input bool            InpRequireLiquiditySweep = true;
input bool            InpRequireFairValueGap = true;
input int             InpFvgLookbackBars = 4;
input int             InpSignalExpiryBars = 8;

input double          InpRiskPercent = 1.0;
input double          InpFixedLot = 0.0;
input double          InpRewardRisk = 2.0;
input int             InpStopBufferPoints = 100;
input int             InpMaxSpreadPoints = 35;
input int             InpSlippagePoints = 10;
input ulong           InpMagicNumber = 20260502;
input bool            InpOnePositionPerSymbol = true;

input bool            InpUseSessionFilter = false;
input int             InpSessionStartHour = 8;
input int             InpSessionEndHour = 18;

input bool            InpMoveToBreakeven = true;
input double          InpBreakevenAtR = 1.0;
input int             InpBreakevenPlusPoints = 10;

CTrade TradeObj;

datetime lastBarTime = 0;
datetime lastBullBosTime = 0;
datetime lastBearBosTime = 0;
datetime lastBullSweepTime = 0;
datetime lastBearSweepTime = 0;
datetime lastBullTradeTime = 0;
datetime lastBearTradeTime = 0;

double lastSwingHigh = 0.0;
double prevSwingHigh = 0.0;
double lastSwingLow = 0.0;
double prevSwingLow = 0.0;

int barsSinceBullBos = 9999;
int barsSinceBearBos = 9999;
int barsSinceBullSweep = 9999;
int barsSinceBearSweep = 9999;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   TradeObj.SetExpertMagicNumber(InpMagicNumber);
   TradeObj.SetDeviationInPoints(InpSlippagePoints);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert tick                                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   ManageOpenPositions();

   if(!IsNewBar())
      return;

   UpdateMarketStructure();

   if(!TradingAllowedNow())
      return;

   if(InpOnePositionPerSymbol && HasOpenPosition())
      return;

   if(CurrentSpreadPoints() > InpMaxSpreadPoints)
      return;

   CheckForEntry();
}

//+------------------------------------------------------------------+
//| Bar timing                                                        |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == lastBarTime)
      return false;

   lastBarTime = currentBarTime;
   return true;
}

//+------------------------------------------------------------------+
//| Structure and SMC signal detection                                |
//+------------------------------------------------------------------+
void UpdateMarketStructure()
{
   barsSinceBullBos++;
   barsSinceBearBos++;
   barsSinceBullSweep++;
   barsSinceBearSweep++;

   FindRecentSwings();

   double close1 = iClose(_Symbol, _Period, 1);
   double high1 = iHigh(_Symbol, _Period, 1);
   double low1 = iLow(_Symbol, _Period, 1);

   if(lastSwingHigh > 0.0 && close1 > lastSwingHigh && lastBullBosTime != iTime(_Symbol, _Period, 1))
   {
      lastBullBosTime = iTime(_Symbol, _Period, 1);
      barsSinceBullBos = 0;
   }

   if(lastSwingLow > 0.0 && close1 < lastSwingLow && lastBearBosTime != iTime(_Symbol, _Period, 1))
   {
      lastBearBosTime = iTime(_Symbol, _Period, 1);
      barsSinceBearBos = 0;
   }

   if(prevSwingLow > 0.0 && low1 < prevSwingLow && close1 > prevSwingLow && lastBullSweepTime != iTime(_Symbol, _Period, 1))
   {
      lastBullSweepTime = iTime(_Symbol, _Period, 1);
      barsSinceBullSweep = 0;
   }

   if(prevSwingHigh > 0.0 && high1 > prevSwingHigh && close1 < prevSwingHigh && lastBearSweepTime != iTime(_Symbol, _Period, 1))
   {
      lastBearSweepTime = iTime(_Symbol, _Period, 1);
      barsSinceBearSweep = 0;
   }
}

void FindRecentSwings()
{
   lastSwingHigh = 0.0;
   prevSwingHigh = 0.0;
   lastSwingLow = 0.0;
   prevSwingLow = 0.0;

   bool foundHigh = false;
   bool foundLow = false;

   int maxBars = MathMin(InpStructureLookback, Bars(_Symbol, _Period) - InpSwingRight - 2);
   if(maxBars <= InpSwingRight + 1)
      return;

   for(int shift = InpSwingRight + 1; shift < maxBars; shift++)
   {
      if(IsSwingHigh(shift))
      {
         if(!foundHigh)
         {
            lastSwingHigh = iHigh(_Symbol, _Period, shift);
            foundHigh = true;
         }
         else
         {
            prevSwingHigh = iHigh(_Symbol, _Period, shift);
            break;
         }
      }
   }

   for(int shift = InpSwingRight + 1; shift < maxBars; shift++)
   {
      if(IsSwingLow(shift))
      {
         if(!foundLow)
         {
            lastSwingLow = iLow(_Symbol, _Period, shift);
            foundLow = true;
         }
         else
         {
            prevSwingLow = iLow(_Symbol, _Period, shift);
            break;
         }
      }
   }
}

bool IsSwingHigh(const int shift)
{
   double value = iHigh(_Symbol, _Period, shift);

   for(int i = 1; i <= InpSwingLeft; i++)
      if(iHigh(_Symbol, _Period, shift + i) >= value)
         return false;

   for(int i = 1; i <= InpSwingRight; i++)
      if(iHigh(_Symbol, _Period, shift - i) > value)
         return false;

   return true;
}

bool IsSwingLow(const int shift)
{
   double value = iLow(_Symbol, _Period, shift);

   for(int i = 1; i <= InpSwingLeft; i++)
      if(iLow(_Symbol, _Period, shift + i) <= value)
         return false;

   for(int i = 1; i <= InpSwingRight; i++)
      if(iLow(_Symbol, _Period, shift - i) < value)
         return false;

   return true;
}

void CheckForEntry()
{
   bool bullSetup = barsSinceBullBos <= InpSignalExpiryBars;
   bool bearSetup = barsSinceBearBos <= InpSignalExpiryBars;

   if(InpRequireLiquiditySweep)
   {
      bullSetup = bullSetup && barsSinceBullSweep <= InpSignalExpiryBars;
      bearSetup = bearSetup && barsSinceBearSweep <= InpSignalExpiryBars;
   }

   if(InpRequireFairValueGap)
   {
      bullSetup = bullSetup && HasBullishFvg(InpFvgLookbackBars);
      bearSetup = bearSetup && HasBearishFvg(InpFvgLookbackBars);
   }

   if(bullSetup && InpTradeDirection != TradeShortOnly && lastBullTradeTime != lastBullBosTime)
      OpenBuy();

   if(bearSetup && InpTradeDirection != TradeLongOnly && !HasOpenPosition() && lastBearTradeTime != lastBearBosTime)
      OpenSell();
}

bool HasBullishFvg(const int lookbackBars)
{
   for(int shift = 1; shift <= lookbackBars; shift++)
   {
      double lowA = iLow(_Symbol, _Period, shift);
      double highC = iHigh(_Symbol, _Period, shift + 2);

      if(lowA > highC)
         return true;
   }

   return false;
}

bool HasBearishFvg(const int lookbackBars)
{
   for(int shift = 1; shift <= lookbackBars; shift++)
   {
      double highA = iHigh(_Symbol, _Period, shift);
      double lowC = iLow(_Symbol, _Period, shift + 2);

      if(highA < lowC)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Order execution                                                   |
//+------------------------------------------------------------------+
void OpenBuy()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopLoss = lastSwingLow - InpStopBufferPoints * _Point;

   if(stopLoss <= 0.0 || stopLoss >= ask)
      return;

   double takeProfit = ask + (ask - stopLoss) * InpRewardRisk;
   double lots = CalculateLots(ask - stopLoss);

   if(lots <= 0.0)
      return;

   if(TradeObj.Buy(lots, _Symbol, ask, NormalizePrice(stopLoss), NormalizePrice(takeProfit), "SMC buy"))
      lastBullTradeTime = lastBullBosTime;
}

void OpenSell()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLoss = lastSwingHigh + InpStopBufferPoints * _Point;

   if(stopLoss <= bid)
      return;

   double takeProfit = bid - (stopLoss - bid) * InpRewardRisk;
   double lots = CalculateLots(stopLoss - bid);

   if(lots <= 0.0)
      return;

   if(TradeObj.Sell(lots, _Symbol, bid, NormalizePrice(stopLoss), NormalizePrice(takeProfit), "SMC sell"))
      lastBearTradeTime = lastBearBosTime;
}

double CalculateLots(const double stopDistancePrice)
{
   if(InpFixedLot > 0.0)
      return NormalizeLots(InpFixedLot);

   if(InpRiskPercent <= 0.0 || stopDistancePrice <= 0.0)
      return 0.0;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPercent / 100.0;
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;

   double lossPerLot = stopDistancePrice / tickSize * tickValue;
   if(lossPerLot <= 0.0)
      return 0.0;

   return NormalizeLots(riskMoney / lossPerLot);
}

double NormalizeLots(const double lots)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double normalized = MathFloor(lots / stepLot) * stepLot;
   normalized = MathMax(minLot, MathMin(maxLot, normalized));

   return normalized;
}

double NormalizePrice(const double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
//| Trade filters and management                                      |
//+------------------------------------------------------------------+
bool TradingAllowedNow()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return false;

   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return false;

   if(!InpUseSessionFilter)
      return true;

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   if(InpSessionStartHour == InpSessionEndHour)
      return true;

   if(InpSessionStartHour < InpSessionEndHour)
      return now.hour >= InpSessionStartHour && now.hour < InpSessionEndHour;

   return now.hour >= InpSessionStartHour || now.hour < InpSessionEndHour;
}

int CurrentSpreadPoints()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return (int)MathRound((ask - bid) / _Point);
}

bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == (long)InpMagicNumber)
         return true;
   }

   return false;
}

void ManageOpenPositions()
{
   if(!InpMoveToBreakeven)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double stopLoss = PositionGetDouble(POSITION_SL);
      double takeProfit = PositionGetDouble(POSITION_TP);
      double currentPrice = type == POSITION_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double initialRisk = MathAbs(openPrice - stopLoss);
      if(initialRisk <= 0.0)
         continue;

      if(type == POSITION_TYPE_BUY)
      {
         double targetPrice = openPrice + initialRisk * InpBreakevenAtR;
         double breakevenStop = NormalizePrice(openPrice + InpBreakevenPlusPoints * _Point);

         if(currentPrice >= targetPrice && stopLoss < breakevenStop)
            TradeObj.PositionModify(ticket, breakevenStop, takeProfit);
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double targetPrice = openPrice - initialRisk * InpBreakevenAtR;
         double breakevenStop = NormalizePrice(openPrice - InpBreakevenPlusPoints * _Point);

         if(currentPrice <= targetPrice && (stopLoss > breakevenStop || stopLoss == 0.0))
            TradeObj.PositionModify(ticket, breakevenStop, takeProfit);
      }
   }
}
