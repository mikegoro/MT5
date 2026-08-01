//+------------------------------------------------------------------+
//|                         FundedWithEA_FVG.mq5                     |
//|                        Copyright FundedWithEA                    |
//+------------------------------------------------------------------+
#property copyright "FundedWithEA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>
#include <Trade\DealInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_FVG_STRATEGY
  {
   STRATEGY_SILVER_BULLET = 0  // Silver Bullet
  };

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "== EA SETTINGS =="
input ENUM_FVG_STRATEGY  InpStrategy       = STRATEGY_SILVER_BULLET; // FVG Strategy
input int                InpMagicNumber    = 101010;                  // Magic Number
input int                InpDeviation      = 10;                      // Slippage (points)

input group "== Silver Bullet : Session & Day Settings =="
input string             InpCutoffTime        = "10:00";              // Cutoff Time (HH:MM)
input int                InpSweepCloseBars    = 3;                    // Sweep Close-Back Candles (max)
input int                InpFractalStrength   = 2;                    // MSS Fractal Strength (candles each side)
input int                InpMSSLookback       = 30;                   // MSS Fractal Lookback (bars max)
input int                InpMSSTimeLapse      = 0;                    // MSS Confirmation Candles (0 = No Expiry)

input group "== Chart Display =="
input bool               InpShowDayLevels  = true;                    // Show Day High/Low Lines
input color              InpDayLevelColor  = clrGold;                 // Day High/Low Line Color
input color              InpBuyMSSColor    = clrLime;                 // MSS Buy Line Color
input color              InpSellMSSColor   = clrCrimson;              // MSS Sell Line Color

input group "== Trade Settings =="
input double             InpLotSize        = 0.01;                    // Lot Size
input double             InpSL_Points      = 200;                     // Stop Loss (points)
input double             InpTP_Points      = 400;                     // Take Profit (points)

//+------------------------------------------------------------------+
//| TRADE OBJECTS                                                    |
//+------------------------------------------------------------------+
CTrade            trade;
CPositionInfo     posinfo;
COrderInfo        ordinfo;

//+------------------------------------------------------------------+
//| GLOBAL STATE                                                     |
//+------------------------------------------------------------------+

// --- Validation ---
bool     G_InputsValid      = false;
string   G_TradeComment     = "";          // Set in OnInit, used in all trade calls

// --- Day Level State ---
double   G_DayHigh          = 0.0;
double   G_DayLow           = 0.0;
bool     G_LevelsCaptured   = false;
datetime G_LastCaptureDate  = 0;

// --- Candle Tracking ---
datetime G_LastBarTime      = 0;

// --- Liquidity Sweep State ---
bool     G_BuySweepFound    = false;   // true once first valid bull sweep locked in
double   G_SweepLow         = 0.0;     // lowest point of the sweep candle
datetime G_SweepTime        = 0;       // open time of sweep candle
int      G_SweepBar         = -1;      // shift of sweep candle at detection time

bool     G_SellSweepFound   = false;   // true once first valid bear sweep locked in
double   G_SweepHigh        = 0.0;     // highest point of the sweep candle
datetime G_SweepHighTime    = 0;
int      G_SweepHighBar     = -1;

// --- MSS State ---
bool     G_BuyMSSFound      = false;   // fractal high locked for buy setup
double   G_BuyMSSLevel      = 0.0;
datetime G_BuyMSSTime       = 0;
bool     G_BuyMSSConfirmed  = false;   // close above MSSLevel confirmed
bool     G_BuyMSSInvalid    = false;   // timelapse expired, setup dead for today
int      G_BuyMSSBar        = -1;      // bar shift when MSS fractal was locked

bool     G_SellMSSFound     = false;   // fractal low locked for sell setup
double   G_SellMSSLevel     = 0.0;
datetime G_SellMSSTime      = 0;
bool     G_SellMSSConfirmed = false;   // close below MSSLevel confirmed
bool     G_SellMSSInvalid   = false;   // timelapse expired, setup dead for today
int      G_SellMSSBar       = -1;      // bar shift when MSS fractal was locked

// --- Chart Object Names ---
const string OBJ_ERROR_LABEL  = "FWE_InputError";
const string OBJ_DAY_HIGH     = "FWE_DayHigh";
const string OBJ_DAY_LOW      = "FWE_DayLow";

//+------------------------------------------------------------------+
//| HELPER: Build trade comment                                      |
//+------------------------------------------------------------------+
string BuildComment()
  {
   string sName = "";
   switch(InpStrategy)
     {
      case STRATEGY_SILVER_BULLET: sName = "Silver Bullet"; break;
      default:                     sName = "Unknown";        break;
     }
   return "FundedWithEA FVG " + sName;
  }

//+------------------------------------------------------------------+
//| HELPER: Strict xx:xx time parser                                 |
//| Returns seconds-since-midnight, or -1 on any format/range error  |
//+------------------------------------------------------------------+
int ParseTime(const string t)
  {
   // Must be exactly 5 characters: digit digit colon digit digit
   if(StringLen(t) != 5)           return -1;
   if(StringGetCharacter(t, 2) != ':') return -1;

   string hStr = StringSubstr(t, 0, 2);
   string mStr = StringSubstr(t, 3, 2);

   // Both halves must be purely numeric
   for(int i = 0; i < 2; i++)
     {
      ushort hc = StringGetCharacter(hStr, i);
      ushort mc = StringGetCharacter(mStr, i);
      if(hc < '0' || hc > '9') return -1;
      if(mc < '0' || mc > '9') return -1;
     }

   int h = (int)StringToInteger(hStr);
   int m = (int)StringToInteger(mStr);

   if(h < 0 || h > 23) return -1;
   if(m < 0 || m > 59) return -1;

   return h * 3600 + m * 60;
  }

//+------------------------------------------------------------------+
//| HELPER: Current server time-of-day in seconds                   |
//+------------------------------------------------------------------+
int CurrentTimeSeconds()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.hour * 3600 + dt.min * 60 + dt.sec;
  }

//+------------------------------------------------------------------+
//| CHART: Show bold error label centred on chart                   |
//+------------------------------------------------------------------+
void ShowErrorLabel(const string msg)
  {
   if(ObjectFind(0, OBJ_ERROR_LABEL) >= 0)
      ObjectDelete(0, OBJ_ERROR_LABEL);

   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

   ObjectCreate(0, OBJ_ERROR_LABEL, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, OBJ_ERROR_LABEL, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, OBJ_ERROR_LABEL, OBJPROP_XDISTANCE, chartW / 2);
   ObjectSetInteger(0, OBJ_ERROR_LABEL, OBJPROP_YDISTANCE, chartH / 2);
   ObjectSetInteger(0, OBJ_ERROR_LABEL, OBJPROP_ANCHOR,    ANCHOR_CENTER);
   ObjectSetString (0, OBJ_ERROR_LABEL, OBJPROP_TEXT,      "⚠  " + msg);
   ObjectSetString (0, OBJ_ERROR_LABEL, OBJPROP_FONT,      "Arial Bold");
   ObjectSetInteger(0, OBJ_ERROR_LABEL, OBJPROP_FONTSIZE,  14);
   ObjectSetInteger(0, OBJ_ERROR_LABEL, OBJPROP_COLOR,     clrRed);
   ObjectSetInteger(0, OBJ_ERROR_LABEL, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, OBJ_ERROR_LABEL, OBJPROP_ZORDER,    999);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| CHART: Remove error label when inputs are valid                  |
//+------------------------------------------------------------------+
void ClearErrorLabel()
  {
   if(ObjectFind(0, OBJ_ERROR_LABEL) >= 0)
     {
      ObjectDelete(0, OBJ_ERROR_LABEL);
      ChartRedraw(0);
     }
  }

//+------------------------------------------------------------------+
//| VALIDATION: Single function for ALL input checks                 |
//| Add new checks here as more inputs/strategies are introduced     |
//+------------------------------------------------------------------+
bool ValidateInputs()
  {
   // --- Magic Number ---
   if(InpMagicNumber <= 0)
     {
      ShowErrorLabel("Invalid Magic Number — must be greater than 0");
      return false;
     }

   // --- Deviation ---
   if(InpDeviation < 0)
     {
      ShowErrorLabel("Invalid Slippage — must be 0 or greater");
      return false;
     }

   // --- Lot Size ---
   if(InpLotSize <= 0.0)
     {
      ShowErrorLabel("Invalid Lot Size — must be greater than 0");
      return false;
     }

   // --- Silver Bullet inputs ---
   if(InpStrategy == STRATEGY_SILVER_BULLET)
     {
      if(ParseTime(InpCutoffTime) < 0)
        {
         ShowErrorLabel("Invalid Cutoff Time \"" + InpCutoffTime
                        + "\" — use format xx:xx  (e.g. 10:00)");
         return false;
        }
      if(InpSweepCloseBars < 1)
        {
         ShowErrorLabel("Sweep Close-Back Candles must be >= 1");
         return false;
        }
      if(InpFractalStrength < 1)
        {
         ShowErrorLabel("MSS Fractal Strength must be >= 1");
         return false;
        }
      if(InpMSSLookback < InpFractalStrength * 2 + 1)
        {
         ShowErrorLabel("MSS Lookback too small for chosen Fractal Strength");
         return false;
        }
      if(InpMSSTimeLapse < 0)
        {
         ShowErrorLabel("MSS Confirmation Candles must be >= 0  (0 = No Expiry)");
         return false;
        }
     }

   // All checks passed
   ClearErrorLabel();
   return true;
  }

//+------------------------------------------------------------------+
//| CHART: Draw Day High / Day Low dashed line                      |
//+------------------------------------------------------------------+
void DrawDayLevel(const string objName, const double price,
                  const color clr,      const string label)
  {
   datetime dayStart = iTime(_Symbol, PERIOD_D1, 0);  // broker midnight
   datetime dayEnd   = dayStart + 86400;

   if(ObjectFind(0, objName) >= 0)
      ObjectDelete(0, objName);

   ObjectCreate(0, objName, OBJ_TREND, 0, dayStart, price, dayEnd, price);
   ObjectSetInteger(0, objName, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, objName, OBJPROP_STYLE,      STYLE_DASH);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT,  false);
   ObjectSetInteger(0, objName, OBJPROP_RAY_LEFT,   false);
   ObjectSetString (0, objName, OBJPROP_TEXT,       label);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| STEP 1: Capture Day High/Low at cutoff time (new candle)        |
//+------------------------------------------------------------------+
void CheckDayLevelCutoff()
  {
   // Detect new calendar day via D1 bar open (broker midnight)
   datetime today = iTime(_Symbol, PERIOD_D1, 0);

   if(G_LastCaptureDate != today)
     {
      G_LevelsCaptured  = false;
      G_LastCaptureDate = today;
      G_DayHigh         = 0.0;
      G_DayLow          = 0.0;
      // Reset sweep state for new day
      G_BuySweepFound   = false;
      G_SweepLow        = 0.0;
      G_SweepTime       = 0;
      G_SweepBar        = -1;
      G_SellSweepFound  = false;
      G_SweepHigh       = 0.0;
      G_SweepHighTime   = 0;
      G_SweepHighBar    = -1;
      // Reset MSS state for new day
      G_BuyMSSFound      = false;
      G_BuyMSSLevel      = 0.0;
      G_BuyMSSTime       = 0;
      G_BuyMSSConfirmed  = false;
      G_BuyMSSInvalid    = false;
      G_BuyMSSBar        = -1;
      G_SellMSSFound     = false;
      G_SellMSSLevel     = 0.0;
      G_SellMSSTime      = 0;
      G_SellMSSConfirmed = false;
      G_SellMSSInvalid   = false;
      G_SellMSSBar       = -1;
      ObjectDelete(0, "FWE_BuyMSS");
      ObjectDelete(0, "FWE_BuyMSS_Lbl");
      ObjectDelete(0, "FWE_SellMSS");
      ObjectDelete(0, "FWE_SellMSS_Lbl");
      ObjectDelete(0, OBJ_DAY_HIGH);
      ObjectDelete(0, OBJ_DAY_LOW);
     }

   if(G_LevelsCaptured) return;

   int cutoffSec  = ParseTime(InpCutoffTime);   // already validated
   int currentSec = CurrentTimeSeconds();

   if(currentSec < cutoffSec) return;

   // Scan every M1 bar from broker midnight to now
   datetime dayStart = iTime(_Symbol, PERIOD_D1, 0);
   int totalBars = Bars(_Symbol, PERIOD_M1, dayStart, TimeCurrent());
   if(totalBars <= 0) return;

   double highBuf[], lowBuf[];
   if(CopyHigh(_Symbol, PERIOD_M1, 0, totalBars, highBuf) <= 0) return;
   if(CopyLow (_Symbol, PERIOD_M1, 0, totalBars, lowBuf)  <= 0) return;

   G_DayHigh        = highBuf[ArrayMaximum(highBuf)];
   G_DayLow         = lowBuf [ArrayMinimum(lowBuf)];
   G_LevelsCaptured = true;

   if(InpShowDayLevels)
     {
      DrawDayLevel(OBJ_DAY_HIGH, G_DayHigh, InpDayLevelColor, "Day High");
      DrawDayLevel(OBJ_DAY_LOW,  G_DayLow,  InpDayLevelColor, "Day Low");
     }

   PrintFormat("[FWE] Day Levels captured | Cutoff: %s | High: %.5f | Low: %.5f",
               InpCutoffTime, G_DayHigh, G_DayLow);
  }

//+------------------------------------------------------------------+
//| MANAGE POSITIONS (every tick)                                   |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posinfo.SelectByIndex(i)) continue;
      if(posinfo.Magic()  != InpMagicNumber) continue;
      if(posinfo.Symbol() != _Symbol)        continue;

      // Trailing / Break-even logic per strategy goes here
     }
  }

//+------------------------------------------------------------------+
//| CHECK FOR ENTRY — routes to active strategy                     |
//+------------------------------------------------------------------+
void CheckForEntry()
  {
   switch(InpStrategy)
     {
      case STRATEGY_SILVER_BULLET:
         SilverBullet_Entry();
         break;
     }
  }

//+------------------------------------------------------------------+
//| SILVER BULLET — Step 2: Detect Liquidity Sweep                  |
//| Called on every new candle AFTER levels are captured            |
//+------------------------------------------------------------------+
void SilverBullet_DetectSweep()
  {
   // --- BUY SETUP: price swept below DayLow then closed back above ---
   if(!G_BuySweepFound)
     {
      // Walk completed bars (shift 1 = last closed candle, onwards)
      for(int i = 1; i <= InpSweepCloseBars; i++)
        {
         double lo    = iLow (_Symbol, PERIOD_CURRENT, i);
         double cl    = iClose(_Symbol, PERIOD_CURRENT, i);

         // Wick pierced below DayLow AND candle closed back above DayLow
         if(lo < G_DayLow && cl > G_DayLow)
           {
            G_BuySweepFound = true;
            G_SweepLow      = lo;
            G_SweepTime     = iTime(_Symbol, PERIOD_CURRENT, i);
            G_SweepBar      = i;

            string objName      = "FWE_SweepBuy_" + TimeToString(G_SweepTime);
            double arrowOffset  = 5 * _Point;          // buffer below sweep low
            if(ObjectFind(0, objName) < 0)
              {
               ObjectCreate(0, objName, OBJ_ARROW, 0, G_SweepTime, lo - arrowOffset);
               ObjectSetInteger(0, objName, OBJPROP_ARROWCODE,  233);   // up arrow
               ObjectSetInteger(0, objName, OBJPROP_COLOR,      clrLime);
               ObjectSetInteger(0, objName, OBJPROP_WIDTH,      4);
               ObjectSetInteger(0, objName, OBJPROP_ANCHOR,     ANCHOR_TOP);  // top of arrow sits at price, arrow points up
               ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
               ObjectSetString (0, objName, OBJPROP_TEXT,       "Buy Sweep");
               ChartRedraw(0);
              }

            PrintFormat("[FWE] BUY Sweep locked | Time: %s | SweepLow: %.5f",
                        TimeToString(G_SweepTime), G_SweepLow);
            break;   // first valid sweep only
           }
        }
     }

   // --- SELL SETUP: price swept above DayHigh then closed back below ---
   if(!G_SellSweepFound)
     {
      for(int i = 1; i <= InpSweepCloseBars; i++)
        {
         double hi = iHigh (_Symbol, PERIOD_CURRENT, i);
         double cl = iClose(_Symbol, PERIOD_CURRENT, i);

         if(hi > G_DayHigh && cl < G_DayHigh)
           {
            G_SellSweepFound = true;
            G_SweepHigh      = hi;
            G_SweepHighTime  = iTime(_Symbol, PERIOD_CURRENT, i);
            G_SweepHighBar   = i;

            string objName      = "FWE_SweepSell_" + TimeToString(G_SweepHighTime);
            double arrowOffset  = 5 * _Point;          // buffer above sweep high
            if(ObjectFind(0, objName) < 0)
              {
               ObjectCreate(0, objName, OBJ_ARROW, 0, G_SweepHighTime, hi + arrowOffset);
               ObjectSetInteger(0, objName, OBJPROP_ARROWCODE,  234);   // down arrow
               ObjectSetInteger(0, objName, OBJPROP_COLOR,      clrCrimson);
               ObjectSetInteger(0, objName, OBJPROP_WIDTH,      4);
               ObjectSetInteger(0, objName, OBJPROP_ANCHOR,     ANCHOR_BOTTOM);  // bottom of arrow sits at price, arrow points down
               ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
               ObjectSetString (0, objName, OBJPROP_TEXT,       "Sell Sweep");
               ChartRedraw(0);
              }

            PrintFormat("[FWE] SELL Sweep locked | Time: %s | SweepHigh: %.5f",
                        TimeToString(G_SweepHighTime), G_SweepHigh);
            break;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| SILVER BULLET — Step 3: Lock MSS Fractal Level                  |
//| Scans backwards from sweep candle for most recent fractal        |
//| Stays within current day (broker midnight) and InpMSSLookback   |
//+------------------------------------------------------------------+
void SilverBullet_DetectMSS()
  {
   datetime dayStart  = iTime(_Symbol, PERIOD_D1, 0);   // broker midnight
   int      strength  = InpFractalStrength;

   // --- BUY: find most recent fractal HIGH before the sweep ---
   if(G_BuySweepFound && !G_BuyMSSFound)
     {
      // sweepBar is the confirmed sweep candle shift at time of detection.
      // We start scanning from sweepBar+1 (one bar older than sweep candle)
      // up to sweepBar + InpMSSLookback, but never before day start.
      int scanStart = G_SweepBar + 1;
      int scanEnd   = G_SweepBar + InpMSSLookback;

      for(int i = scanStart; i <= scanEnd; i++)
        {
         // Boundary: don't cross broker midnight
         if(iTime(_Symbol, PERIOD_CURRENT, i) < dayStart) break;

         // Need 'strength' bars on each side — ensure they exist
         if(i - strength < 0) break;

         double centerHigh = iHigh(_Symbol, PERIOD_CURRENT, i);
         bool   isFractal  = true;

         // Left side (older bars = higher shift numbers)
         for(int l = 1; l <= strength; l++)
           {
            if(iHigh(_Symbol, PERIOD_CURRENT, i + l) >= centerHigh)
              { isFractal = false; break; }
           }
         if(!isFractal) continue;

         // Right side (newer bars = lower shift numbers)
         for(int r = 1; r <= strength; r++)
           {
            if(iHigh(_Symbol, PERIOD_CURRENT, i - r) >= centerHigh)
              { isFractal = false; break; }
           }
         if(!isFractal) continue;

         // First (most recent) fractal high found — lock it
         G_BuyMSSFound  = true;
         G_BuyMSSLevel  = centerHigh;
         G_BuyMSSTime   = iTime(_Symbol, PERIOD_CURRENT, i);
         G_BuyMSSBar    = i;

         // Draw dashed MSS Buy line spanning the current day
         string objName    = "FWE_BuyMSS";
         string objLblName = "FWE_BuyMSS_Lbl";
         if(ObjectFind(0, objName)    >= 0) ObjectDelete(0, objName);
         if(ObjectFind(0, objLblName) >= 0) ObjectDelete(0, objLblName);
         datetime lineEnd    = dayStart + 86400;
         // Line starts from fractal high candle → end of day
         ObjectCreate(0, objName, OBJ_TREND, 0, G_BuyMSSTime, G_BuyMSSLevel, lineEnd, G_BuyMSSLevel);
         ObjectSetInteger(0, objName, OBJPROP_COLOR,      InpBuyMSSColor);
         ObjectSetInteger(0, objName, OBJPROP_STYLE,      STYLE_DASH);
         ObjectSetInteger(0, objName, OBJPROP_WIDTH,      1);
         ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT,  false);
         ObjectSetInteger(0, objName, OBJPROP_RAY_LEFT,   false);
         ObjectSetString (0, objName, OBJPROP_TEXT,       "MSS Buy Unconfirmed");
         ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
         // Label at start of line (fractal candle)
         ObjectCreate(0, objLblName, OBJ_TEXT, 0, G_BuyMSSTime, G_BuyMSSLevel);
         ObjectSetString (0, objLblName, OBJPROP_TEXT,      "MSS BUY Unconfirmed");
         ObjectSetString (0, objLblName, OBJPROP_FONT,      "Arial Bold");
         ObjectSetInteger(0, objLblName, OBJPROP_FONTSIZE,  9);
         ObjectSetInteger(0, objLblName, OBJPROP_COLOR,     clrDodgerBlue);
         ObjectSetInteger(0, objLblName, OBJPROP_ANCHOR,    ANCHOR_LEFT);
         ObjectSetInteger(0, objLblName, OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0, objLblName, OBJPROP_HIDDEN,    true);
         ChartRedraw(0);

         PrintFormat("[FWE] BUY MSS locked | Fractal High: %.5f | Time: %s",
                     G_BuyMSSLevel, TimeToString(G_BuyMSSTime));
         break;
        }
     }

   // --- SELL: find most recent fractal LOW before the sweep ---
   if(G_SellSweepFound && !G_SellMSSFound)
     {
      int scanStart = G_SweepHighBar + 1;
      int scanEnd   = G_SweepHighBar + InpMSSLookback;

      for(int i = scanStart; i <= scanEnd; i++)
        {
         if(iTime(_Symbol, PERIOD_CURRENT, i) < dayStart) break;
         if(i - strength < 0) break;

         double centerLow = iLow(_Symbol, PERIOD_CURRENT, i);
         bool   isFractal = true;

         for(int l = 1; l <= strength; l++)
           {
            if(iLow(_Symbol, PERIOD_CURRENT, i + l) <= centerLow)
              { isFractal = false; break; }
           }
         if(!isFractal) continue;

         for(int r = 1; r <= strength; r++)
           {
            if(iLow(_Symbol, PERIOD_CURRENT, i - r) <= centerLow)
              { isFractal = false; break; }
           }
         if(!isFractal) continue;

         G_SellMSSFound  = true;
         G_SellMSSLevel  = centerLow;
         G_SellMSSTime   = iTime(_Symbol, PERIOD_CURRENT, i);
         G_SellMSSBar    = i;

         string objName    = "FWE_SellMSS";
         string objLblName = "FWE_SellMSS_Lbl";
         if(ObjectFind(0, objName)    >= 0) ObjectDelete(0, objName);
         if(ObjectFind(0, objLblName) >= 0) ObjectDelete(0, objLblName);
         datetime lineEnd    = dayStart + 86400;
         // Line starts from fractal low candle → end of day
         ObjectCreate(0, objName, OBJ_TREND, 0, G_SellMSSTime, G_SellMSSLevel, lineEnd, G_SellMSSLevel);
         ObjectSetInteger(0, objName, OBJPROP_COLOR,      InpSellMSSColor);
         ObjectSetInteger(0, objName, OBJPROP_STYLE,      STYLE_DASH);
         ObjectSetInteger(0, objName, OBJPROP_WIDTH,      1);
         ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT,  false);
         ObjectSetInteger(0, objName, OBJPROP_RAY_LEFT,   false);
         ObjectSetString (0, objName, OBJPROP_TEXT,       "MSS Sell Unconfirmed");
         ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
         // Label at start of line (fractal candle)
         ObjectCreate(0, objLblName, OBJ_TEXT, 0, G_SellMSSTime, G_SellMSSLevel);
         ObjectSetString (0, objLblName, OBJPROP_TEXT,      "MSS SELL Unconfirmed");
         ObjectSetString (0, objLblName, OBJPROP_FONT,      "Arial Bold");
         ObjectSetInteger(0, objLblName, OBJPROP_FONTSIZE,  9);
         ObjectSetInteger(0, objLblName, OBJPROP_COLOR,     clrDodgerBlue);
         ObjectSetInteger(0, objLblName, OBJPROP_ANCHOR,    ANCHOR_LEFT);
         ObjectSetInteger(0, objLblName, OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0, objLblName, OBJPROP_HIDDEN,    true);
         ChartRedraw(0);

         PrintFormat("[FWE] SELL MSS locked | Fractal Low: %.5f | Time: %s",
                     G_SellMSSLevel, TimeToString(G_SellMSSTime));
         break;
        }
     }
  }

//+------------------------------------------------------------------+
//| SILVER BULLET — Step 4: MSS Confirmation                        |
//| Waits for close above/below MSSLevel after sweep                |
//+------------------------------------------------------------------+
void SilverBullet_ConfirmMSS()
  {
   // --- BUY: wait for close above G_BuyMSSLevel ---
   if(G_BuyMSSFound && !G_BuyMSSConfirmed && !G_BuyMSSInvalid)
     {
      // Check TimeLapse expiry (0 = no expiry)
      // G_BuyMSSBar was the shift at lock time; each new candle it increments by 1
      // We track candles elapsed since MSS lock by comparing bar times
      if(InpMSSTimeLapse > 0)
        {
         // Count bars that have closed since the MSS fractal was detected
         int barsSinceMSS = iBarShift(_Symbol, PERIOD_CURRENT, G_BuyMSSTime, false);
         // subtract the fractal's own bar so count starts from candle after fractal
         int candlesElapsed = barsSinceMSS - 1;
         if(candlesElapsed > InpMSSTimeLapse)
           {
            G_BuyMSSInvalid = true;
            // Update label to show invalidation
            ObjectSetString(0, "FWE_BuyMSS_Lbl", OBJPROP_TEXT, "MSS BUY Invalid");
            ObjectSetInteger(0, "FWE_BuyMSS_Lbl", OBJPROP_COLOR, clrGray);
            ObjectSetInteger(0, "FWE_BuyMSS",     OBJPROP_COLOR, clrGray);
            ChartRedraw(0);
            PrintFormat("[FWE] BUY MSS Invalidated — TimeLapse of %d candles exceeded", InpMSSTimeLapse);
            return;
           }
        }

      // Check bar 1 (last closed candle) close above MSSLevel
      double lastClose = iClose(_Symbol, PERIOD_CURRENT, 1);
      if(lastClose > G_BuyMSSLevel)
        {
         G_BuyMSSConfirmed = true;
         ObjectSetString (0, "FWE_BuyMSS_Lbl", OBJPROP_TEXT,  "MSS BUY Confirmed");
         ObjectSetInteger(0, "FWE_BuyMSS_Lbl", OBJPROP_COLOR, clrAqua);
         ChartRedraw(0);
         PrintFormat("[FWE] BUY MSS Confirmed | Close: %.5f > MSSLevel: %.5f",
                     lastClose, G_BuyMSSLevel);
        }
     }

   // --- SELL: wait for close below G_SellMSSLevel ---
   if(G_SellMSSFound && !G_SellMSSConfirmed && !G_SellMSSInvalid)
     {
      if(InpMSSTimeLapse > 0)
        {
         int barsSinceMSS   = iBarShift(_Symbol, PERIOD_CURRENT, G_SellMSSTime, false);
         int candlesElapsed = barsSinceMSS - 1;
         if(candlesElapsed > InpMSSTimeLapse)
           {
            G_SellMSSInvalid = true;
            ObjectSetString (0, "FWE_SellMSS_Lbl", OBJPROP_TEXT,  "MSS SELL Invalid");
            ObjectSetInteger(0, "FWE_SellMSS_Lbl", OBJPROP_COLOR, clrGray);
            ObjectSetInteger(0, "FWE_SellMSS",      OBJPROP_COLOR, clrGray);
            ChartRedraw(0);
            PrintFormat("[FWE] SELL MSS Invalidated — TimeLapse of %d candles exceeded", InpMSSTimeLapse);
            return;
           }
        }

      double lastClose = iClose(_Symbol, PERIOD_CURRENT, 1);
      if(lastClose < G_SellMSSLevel)
        {
         G_SellMSSConfirmed = true;
         ObjectSetString (0, "FWE_SellMSS_Lbl", OBJPROP_TEXT,  "MSS SELL Confirmed");
         ObjectSetInteger(0, "FWE_SellMSS_Lbl", OBJPROP_COLOR, clrAqua);
         ChartRedraw(0);
         PrintFormat("[FWE] SELL MSS Confirmed | Close: %.5f < MSSLevel: %.5f",
                     lastClose, G_SellMSSLevel);
        }
     }
  }

//+------------------------------------------------------------------+
//| SILVER BULLET — Entry Logic                                      |
//+------------------------------------------------------------------+
void SilverBullet_Entry()
  {
   if(!G_LevelsCaptured) return;

   // Step 2 — Sweep detection
   SilverBullet_DetectSweep();

   // Step 3 — MSS fractal lock (only runs after sweep found, until MSS locked)
   if((G_BuySweepFound  && !G_BuyMSSFound) ||
      (G_SellSweepFound && !G_SellMSSFound))
      SilverBullet_DetectMSS();

   // Step 4 — MSS confirmation (runs after MSS locked, until confirmed or invalidated)
   if((G_BuyMSSFound  && !G_BuyMSSConfirmed  && !G_BuyMSSInvalid) ||
      (G_SellMSSFound && !G_SellMSSConfirmed && !G_SellMSSInvalid))
      SilverBullet_ConfirmMSS();

   // Step 5+ entry logic goes here
  }

//+------------------------------------------------------------------+
//| ON INIT                                                          |
//+------------------------------------------------------------------+
int OnInit()
  {
   G_InputsValid = ValidateInputs();
   if(!G_InputsValid)
      return INIT_PARAMETERS_INCORRECT;

   // --- Chart Appearance ---
   ChartSetInteger(0, CHART_SHOW_GRID,          false);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL,  clrLime);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR,  clrCrimson);
   ChartSetInteger(0, CHART_COLOR_CHART_UP,     clrLime);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN,   clrCrimson);
   ChartRedraw(0);

   // --- Trade Setup ---
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviation);
   G_TradeComment   = BuildComment();

   G_LastBarTime    = 0;
   G_LevelsCaptured = false;

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| ON DEINIT                                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ClearErrorLabel();
   ObjectDelete(0, OBJ_DAY_HIGH);
   ObjectDelete(0, OBJ_DAY_LOW);
   ObjectDelete(0, "FWE_BuyMSS");
   ObjectDelete(0, "FWE_BuyMSS_Lbl");
   ObjectDelete(0, "FWE_SellMSS");
   ObjectDelete(0, "FWE_SellMSS_Lbl");
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| ON TICK                                                          |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!G_InputsValid) return;

   //--- EVERY TICK ---------------------------------------------------
   ManagePositions();

   //--- EVERY NEW CANDLE ---------------------------------------------
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == G_LastBarTime) return;
   G_LastBarTime = currentBarTime;

   CheckDayLevelCutoff();   // Step 1 — Silver Bullet
   CheckForEntry();         // Strategy entry logic
  }
//+------------------------------------------------------------------+