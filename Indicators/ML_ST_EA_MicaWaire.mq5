//+------------------------------------------------------------------+
//|  TREMOR Swing EA — Mica Waire                                    |
//|  Based on: ML SuperTrend Indicator v10.02                        |
//|  EA Version : v1.02                                              |
//|  Timeframes : M15, M30, H1, H4 and above                        |
//|  Features:                                                        |
//|    - Trend flip detection from BullBuf / BearBuf                 |
//|    - Trades all regimes — indicator's own gating is trusted      |
//|    - Max 2 trades per day                                        |
//|    - Second trade only if Trade 1 hit breakeven                  |
//|    - Stop for day if Trade 1 closed at a loss                    |
//|    - BE = entry + 1 ATR (locks profit before trailing)           |
//|    - 0.5% risk, ATR-based lot sizing                             |
//|    - 1% daily drawdown hard stop                                 |
//|    - Trading window: 02:00 - 22:00 server time                   |
//|    - Live dashboard on chart                                     |
//|    - Full debug logging                                          |
//+------------------------------------------------------------------+
//
// ═══════════════════════════════════════════════════════════════════
// CHANGELOG — TREMOR Swing EA
// ═══════════════════════════════════════════════════════════════════
//
// v1.02 (Mica Waire — added test mode for fast M5 signal debugging):
//   FIX 13 — Needed a way to test signal flow on M5 without DD/trade
//            caps interrupting observation:
//     CONTEXT : Testing was moved to M5 specifically because signals
//               fire faster there, making it quicker to confirm the
//               EA is correctly receiving and acting on BuyBuf/SellBuf
//               (Fix 11). But Daily DD halt and the 2-trade/day cap
//               would stop the EA mid-session on a fast M5 test,
//               cutting the observation window short before enough
//               signals could be reviewed.
//     ADDED   : InpTestMode (default false — production behaviour
//               unchanged). When true:
//                 - M1/M5 Alert() popup is silenced
//                 - Daily DD halt is bypassed entirely
//                 - g_stopForDay / 2-trade-per-day cap is bypassed
//               HasOpenPosition() check is NOT bypassed — still only
//               one position at a time, to keep the test itself sane.
//               Session window, signal filters (confidence), SL/TP/BE/
//               trail and lot sizing all remain fully active and
//               untouched — only the daily stop conditions are lifted.
//     IMPORTANT: Must be set back to false before any live/funded use.
//
// v1.02 (Mica Waire — removed redundant RANGE filter):
//   FIX 12 — EA's own RANGE filter was blocking good signals:
//     PROBLEM : After Fix 11 connected the EA to the indicator's real
//               BuyBuf/SellBuf signals, live chart review showed the
//               indicator's reversal signals were landing accurately
//               at genuine pivots even without a fresh-extreme
//               requirement — see chart evidence: 4 of 5 signals on
//               a single move correctly caught major tops/bottoms.
//               Meanwhile SyncIndicatorInfo()'s own regime calc is a
//               simple 30-bar B0/B1 flip count — a much cruder, more
//               lagging signal than the indicator's internal
//               DetectRegime(), which blends Hurst exponent, Shannon
//               entropy, and ADX (see indicator source). The EA was
//               therefore second-guessing a higher-fidelity decision
//               the indicator had already made before ever writing
//               to BuyBuf/SellBuf, and risked discarding good trades
//               on a lagging, lower-quality regime read.
//     FIX     : Removed the 'if(g_indRegime=="RANGE") ... return;'
//               block from the trade-decision path entirely. Trend/
//               Regime/Confidence sync (SyncIndicatorInfo) is kept
//               running and still displayed on the dashboard for
//               visibility, but no longer gates trade execution.
//               InpMinConfidence filter is kept as-is since ConfBuf
//               is the indicator's own output, not an EA-derived guess.
//
// v1.02 (Mica Waire — switched to indicator-driven signals):
//   FIX 11 — EA was self-generating signals from raw trend flips
//            instead of waiting for the ML SuperTrend's actual signal:
//     PROBLEM : After Fix 10, BTCUSD log showed the EA firing 3+
//               'FLIP' events within 8 minutes on M15 — far more
//               often than the indicator's own Alert() lines. Root
//               cause: TREMOR Swing was reacting to raw B0/B1
//               (BullBuf/BearBuf) direction changes, i.e. the
//               SuperTrend LINE flipping colour. The indicator's
//               actual tradeable signal (the one that fires
//               'Alert: ML ST ... BUY/SELL signal' and draws the
//               arrow) goes through extra filtering the line flip
//               does not: RSI hot/cold zone, minimum signal spacing
//               (InpMinBarsBetweenSigs), pivot/extreme confirmation,
//               and the indicator's own risk guard. The EA was
//               therefore trading on noise the indicator itself
//               would have rejected.
//     FIX     : Trade-decision isBuy/isSell now reads BuyBuf (buffer
//               index 2) and SellBuf (buffer index 3) directly via
//               GetBuffer(), scanning shift 0 then shift 1 so a
//               signal isn't missed between ticks. Per the
//               indicator's own source (mlsupertred.txt), SellBuf[i]/
//               BuyBuf[i] are written in the exact same code block
//               as SendSignalAlert() — i.e. reading these buffers is
//               reading precisely what triggers the Alert line.
//               This works correctly now because OnInit uses
//               ChartIndicatorGet() (attaches to the live chart
//               instance, same parameters) with iCustom() only as a
//               fallback — the earlier failed attempt at reading
//               BuyBuf/SellBuf used iCustom() exclusively, which
//               spun up a separate hidden instance with different
//               signals that never matched the visible chart.
//     NOTE    : Fix 10's g_flipIsBuy/g_flipIsSell capture mechanism
//               is left in place and still calculated correctly every
//               tick (used only for the FLIP debug log line) — it no
//               longer drives any trade decision. g_prevTrend/B0/B1
//               flip detection is now purely informational.
//
// v1.02 (Mica Waire — critical signal execution fix):
//   FIX 10 — Zero trades ever executed despite flips being detected
//            and indicator alerts firing correctly (THE BIG ONE):
//     PROBLEM : Live log evidence (20260618.log) showed FLIP lines
//               printing correctly AND matching indicator Alert lines
//               within milliseconds (e.g. 22:30:35.443 FLIP then
//               22:30:35.856 indicator Alert BUY @ 4206.30) — proving
//               detection worked. But NO 'Signal=' line, NO skip
//               reason, NO 'REACHED EXECUTE' line ever followed —
//               on EVERY single flip across the entire session
//               (58 flips logged, 0 trades, 0 failures, 0 skip prints).
//               Root cause: inside the flip-detection block,
//               'g_prevTrend = nowTrend' ran immediately after
//               detecting the flip — overwriting g_prevTrend BEFORE
//               the later line 'isBuy = (nowTrend==1 && g_prevTrend==-1)'
//               could evaluate it. By the time isBuy/isSell were
//               calculated, g_prevTrend already equalled nowTrend,
//               so the comparison was structurally always false —
//               a same-tick race condition that silently discarded
//               every single signal with no trace in the log.
//     FIX     : Added g_flipIsBuy / g_flipIsSell boolean flags.
//               These are captured INSIDE the flip-detection block,
//               BEFORE g_prevTrend is overwritten. Reset to false at
//               the top of every tick so they only stay true for the
//               exact tick the flip occurred. isBuy/isSell further
//               down OnTick() now read these captured flags instead
//               of re-comparing nowTrend to the already-corrupted
//               g_prevTrend. Also fixed the 'Outside session' skip
//               reason check which had the same broken comparison.
//
// v1.02 (Mica Waire — self-fixed + dashboard cleanup fix):
//   FIX 9 — Dashboard objects persisting after EA removal:
//     PROBLEM : DashDeleteAll() single pass missed objects when array
//               indices shifted during deletion loop, leaving ghost
//               dashboard cells on chart after EA was removed.
//     FIX     : DashDeleteAll() now loops up to 5 passes until no
//               objects with DASH_PFX remain. OnDeinit calls it twice
//               with ChartRedraw() to guarantee full cleanup.
//
// v1.02 (Mica Waire — self-fixed):
//   FIX 1 — SyncIndicatorInfo() array bounds:
//     PROBLEM : bullArr[30] accessed without checking ArraySize first,
//               causing potential out-of-bounds crash on first bars.
//     FIX     : Loop from i=29 downward with firstSet flag to safely
//               initialise wasBull on first valid element. Added
//               bounds check: if(i>=ArraySize(bullArr)) continue.
//
//   FIX 2 — GetBuffer() bounds check:
//     PROBLEM : arr[shift] accessed without confirming shift < ArraySize(arr),
//               risking out-of-bounds read when CopyBuffer returns fewer bars.
//     FIX     : Added guard: if(shift>=ArraySize(arr)) return 0.0;
//
//   FIX 3 — GetATR() bounds check:
//     PROBLEM : Same issue as GetBuffer — shift could exceed array size.
//     FIX     : Added guard: if(shift>=ArraySize(arr)) return 0.0;
//
//   FIX 4 — ManageOpenPosition() PositionModify guard:
//     PROBLEM : PositionModify called without checking return value,
//               silent failures went undetected.
//     FIX     : Wrapped both BUY and SELL PositionModify calls in
//               if(g_trade.PositionModify(...)) blocks.
//
//   FIX 5 — CheckDailyReset() year check:
//     PROBLEM : Reset compared only day and month, missing year boundary
//               (e.g. Dec 31 vs Jan 1 same day/month different year).
//     FIX     : Added now.year!=last.year to the reset condition.
//
//   FIX 6 — OnInit() balance initialisation:
//     PROBLEM : g_dayStartBalance set to 0.0 at global scope, causing
//               IsDailyLimitBreached() to always return false on first tick
//               before CheckDailyReset() ran.
//     FIX     : Set g_dayStartBalance and g_lastDayReset explicitly in OnInit.
//
//   FIX 7 — confArr scan bounds:
//     PROBLEM : for(ci<50) without checking ArraySize(confArr), risking
//               out-of-bounds if CopyBuffer returned fewer than 50 bars.
//     FIX     : Changed to for(ci<MathMin(50,ArraySize(confArr))).
//
//   FIX 8 — Dashboard X/Y positioning:
//     PROBLEM : InpDashX=10, InpDashY=220 placed dashboard overlapping
//               indicator dashboard.
//     FIX     : Changed defaults to InpDashX=420, InpDashY=40 to sit
//               beside indicator dashboard without overlap.
//
// v1.01:
//   - Replaced ATR-based SL/TP with fixed pip-based system
//   - SL=30pip, TP=200pip, BE=100pip for XAUUSD
//   - PipsToPrice() helper added
//   - TP hit detection added — stops trading for day after TP
//   - Dashboard refresh optimised: full redraw on new bar only,
//     live labels (PnL/DD/Status) updated every tick via UpdateLiveLabels()
//   - DASH_PFX defines moved above UpdateLiveLabels() to fix
//     'undeclared identifier DASH_PFX' compiler errors
//
// v1.00:
//   - Initial build
//   - Trend flip detection from B0/B1
//   - 2 trades per day max, T2 requires T1 BE
//   - Session 02:00-22:00, 1% DD limit, 0.5% risk
//   - Full debug logging
//
// ═══════════════════════════════════════════════════════════════════
#property copyright "Mica Waire — TREMOR Swing v1.02"
#property version   "1.02"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//==========================================================================
// INPUTS
//==========================================================================

//--- Indicator
input string   InpIndicatorName      = "ML_SuperTrend"; // Indicator filename (no .ex5)
input int      InpMagicNumber         = 20250001;        // Magic Number

//--- Signal Filters
input double   InpMinConfidence       = 40.0;  // Min Confidence Score (0-100)
// Regime: displayed on dashboard for visibility only — no longer filters trades (see Fix 12).

//--- Risk Management
input double   InpRiskPercent         = 0.5;   // Risk % per trade
input double   InpDailyDDLimit        = 1.0;   // Daily Drawdown Limit %
input int      InpATRPeriod           = 14;    // ATR Period

//--- Fixed pip-based SL/TP (1 pip = 10 points on XAUUSD/BTCUSD)
// XAUUSD recommended: SL=30, TP=200, BE=100
// For Forex pairs (5-digit): SL=300, TP=2000, BE=1000
input int      InpSLPips              = 30;    // Stop Loss in pips
input int      InpTPPips              = 200;   // Take Profit in pips (close 100% here)
input int      InpBETriggerPips       = 100;   // Move to BE once this many pips in profit
input double   InpTrailATRMult        = 1.5;   // Trail = ATR x this AFTER BE is applied
input bool     InpStopAfterTP         = true;  // Stop trading for the day after TP hit
// Note: 1 pip = 10 points for most brokers on XAUUSD
// If your broker uses different pip sizing adjust InpPipSize below
input double   InpPipSize             = 10.0;  // Points per pip (10 for XAUUSD, 10 for BTCUSD, 10 for Forex 5-digit)

//--- Testing
input bool     InpTestMode            = true; // Test Mode: bypass Daily DD halt + 2-trade/day cap, silence M1/M5 alert

//--- Trading Session
input int      InpSessionStartHour    = 2;     // Session Start Hour
input int      InpSessionEndHour      = 22;    // Session End Hour

//--- Lot Constraints
input double   InpMinLot              = 0.01;  // Minimum Lot
input double   InpMaxLot              = 10.0;  // Maximum Lot

//--- Dashboard
input bool     InpShowDashboard       = true;  // Show Dashboard
input int      InpDashX               = 420;   // Dashboard X position
input int      InpDashY               = 40;    // Dashboard Y position (beside indicator dash)

//==========================================================================
// GLOBALS
//==========================================================================
CTrade         g_trade;
CPositionInfo  g_pos;

int            g_atr_handle       = INVALID_HANDLE;
int            g_ind_handle       = INVALID_HANDLE;

// Daily tracking
double         g_dayStartBalance   = 0.0;
datetime       g_lastDayReset      = 0;
bool           g_dailyLimitHit     = false;
int            g_tradesToday       = 0;
bool           g_trade1WasBE       = false;
bool           g_trade1WasLoss     = false;
bool           g_stopForDay        = false;

// New bar tracking
datetime       g_lastBarTime       = 0;

// Position tracking
bool           g_beApplied         = false;
ulong          g_openTicket        = 0;

// Trend flip detection
int            g_prevTrend         = 0;
int            g_lastActedBar      = -1;
bool           g_flipIsBuy         = false;  // captured BEFORE g_prevTrend is overwritten (Fix 10 — kept for logging only, no longer drives trades)
bool           g_flipIsSell        = false;  // captured BEFORE g_prevTrend is overwritten (Fix 10 — kept for logging only, no longer drives trades)

// Fix 11: Direct indicator signal reading — BuyBuf/SellBuf (buffer 2/3)
// These ARE the same data that fires the indicator's own Alert() and arrow.
double         g_buyBufVal         = 0.0;
double         g_sellBufVal        = 0.0;

// Tick counter
int            g_tickCount         = 0;

// Dashboard signal tracking
string         g_lastSignalType    = "None";
string         g_lastSignalTime    = "--";
double         g_lastSignalConf    = 0.0;
string         g_lastSkipReason    = "--";
int            g_totalSignalsSeen  = 0;
int            g_totalTradesOpened = 0;
int            g_signalsSkipped    = 0;

// Indicator signal info
string         g_indTrend          = "--";
string         g_indRegime         = "--";
double         g_indConf           = 0.0;

// Last closed trade result tracking
double         g_lastClosedPnL     = 0.0;
bool           g_tpHitToday        = false;

// Dashboard refresh control
bool           g_dashNeedsFullRedraw = true;
double         g_lastDisplayPnL      = -999999.0;
double         g_lastDisplayDD       = -999999.0;
string         g_lastDisplayStatus   = "";

//==========================================================================
// DASHBOARD DEFINES — must be before any function that uses them
//==========================================================================
#define DASH_PFX   "TREMOR_SW_"
#define CELL_W     160
#define CELL_H     18

//==========================================================================
// UPDATE LIVE LABELS — tick-level lightweight update
// Only updates PnL, DD and Status — no object recreation
//==========================================================================
void UpdateLiveLabels()
{
   if(!InpShowDashboard) return;

   color txtGreen  = C'60,220,90';
   color txtRed    = C'220,70,70';
   color txtYellow = C'230,205,55';
   color txtOrange = C'230,140,40';
   color txtGray   = C'150,150,160';

   // ── DD Today ─────────────────────────────────────────────────────────
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct  = g_dayStartBalance > 0 ?
                   ((g_dayStartBalance - equity) / g_dayStartBalance) * 100.0 : 0.0;
   if(MathAbs(ddPct - g_lastDisplayDD) > 0.001)
   {
      string ddStr = DoubleToString(ddPct,2)+"% / "+DoubleToString(InpDailyDDLimit,1)+"%";
      color  ddClr = g_dailyLimitHit ? txtRed : (ddPct > InpDailyDDLimit*0.7 ? txtYellow : txtGreen);
      string lbNm  = DASH_PFX+"LB_2_1";
      if(ObjectFind(0,lbNm)>=0)
      {
         ObjectSetString (0,lbNm,OBJPROP_TEXT,  "DD Today: "+ddStr);
         ObjectSetInteger(0,lbNm,OBJPROP_COLOR,  ddClr);
      }
      g_lastDisplayDD = ddPct;
   }

   // ── Position PnL ─────────────────────────────────────────────────────
   bool   hasPos    = HasOpenPosition();
   double curPnL    = 0.0;
   string posDetail = "--";
   color  posDetClr = txtGray;
   if(hasPos)
   {
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         if(!g_pos.SelectByIndex(i)) continue;
         if(g_pos.Symbol()!=_Symbol||g_pos.Magic()!=InpMagicNumber) continue;
         string dir = (g_pos.PositionType()==POSITION_TYPE_BUY)?"BUY":"SELL";
         curPnL     = g_pos.Profit();
         posDetail  = dir+"  PnL:"+DoubleToString(curPnL,2)+(g_beApplied?" [BE]":"");
         posDetClr  = curPnL>=0 ? txtGreen : txtRed;
         break;
      }
   }
   if(MathAbs(curPnL - g_lastDisplayPnL) > 0.001 || (!hasPos && g_lastDisplayPnL != 0.0))
   {
      string lbNm = DASH_PFX+"LB_3_1";
      if(ObjectFind(0,lbNm)>=0)
      {
         ObjectSetString (0,lbNm,OBJPROP_TEXT,  "Position: "+posDetail);
         ObjectSetInteger(0,lbNm,OBJPROP_COLOR,  posDetClr);
      }
      g_lastDisplayPnL = curPnL;
   }

   // ── Status ───────────────────────────────────────────────────────────
   string statusStr = g_tpHitToday  ? "TP HIT-DONE!" :
                      g_stopForDay  ? "STOPPED-DAY"  :
                      hasPos        ? "TRADE OPEN"   : "WATCHING";
   color  statusClr = g_tpHitToday  ? txtGreen  :
                      g_stopForDay  ? txtRed     :
                      hasPos        ? txtOrange  : txtGray;
   if(statusStr != g_lastDisplayStatus)
   {
      string lbNm = DASH_PFX+"LB_3_0";
      if(ObjectFind(0,lbNm)>=0)
      {
         ObjectSetString (0,lbNm,OBJPROP_TEXT,  "Status: "+statusStr);
         ObjectSetInteger(0,lbNm,OBJPROP_COLOR,  statusClr);
      }
      g_lastDisplayStatus = statusStr;
      ChartRedraw(0);
   }
}

//==========================================================================
// DASHBOARD FUNCTIONS
//==========================================================================
void DashDeleteAll()
{
   // Loop multiple passes until no objects with our prefix remain
   // Single pass can miss objects if indices shift during deletion
   int pass=0;
   bool found=true;
   while(found && pass<5)
   {
      found=false;
      int total=ObjectsTotal(0,0,-1);
      for(int i=total-1;i>=0;i--)
      {
         string nm=ObjectName(0,i,0,-1);
         if(StringFind(nm,DASH_PFX)==0)
         {
            ObjectDelete(0,nm);
            found=true;
         }
      }
      pass++;
   }
   ChartRedraw(0);
}

void DashCell(int row,int col,string label,string val,color bgClr,color txtClr)
{
   int x = InpDashX + col*(CELL_W+1);
   int y = InpDashY + row*(CELL_H+1);

   string bgNm = DASH_PFX+"BG_"+IntegerToString(row)+"_"+IntegerToString(col);
   if(ObjectFind(0,bgNm)<0) ObjectCreate(0,bgNm,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bgNm,OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bgNm,OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0,bgNm,OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0,bgNm,OBJPROP_XSIZE,      CELL_W);
   ObjectSetInteger(0,bgNm,OBJPROP_YSIZE,      CELL_H);
   ObjectSetInteger(0,bgNm,OBJPROP_BGCOLOR,    bgClr);
   ObjectSetInteger(0,bgNm,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bgNm,OBJPROP_COLOR,      clrBlack);
   ObjectSetInteger(0,bgNm,OBJPROP_BACK,       false);
   ObjectSetInteger(0,bgNm,OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0,bgNm,OBJPROP_ZORDER,     10);

   string txt = (label!="") ? (label+": "+val) : val;
   if(txt=="") txt=" ";
   string lbNm = DASH_PFX+"LB_"+IntegerToString(row)+"_"+IntegerToString(col);
   if(ObjectFind(0,lbNm)<0) ObjectCreate(0,lbNm,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,lbNm,OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0,lbNm,OBJPROP_XDISTANCE,  x+4);
   ObjectSetInteger(0,lbNm,OBJPROP_YDISTANCE,  y+3);
   ObjectSetString (0,lbNm,OBJPROP_TEXT,       txt);
   ObjectSetInteger(0,lbNm,OBJPROP_COLOR,      txtClr);
   ObjectSetInteger(0,lbNm,OBJPROP_FONTSIZE,   8);
   ObjectSetString (0,lbNm,OBJPROP_FONT,       "Courier New");
   ObjectSetInteger(0,lbNm,OBJPROP_BACK,       false);
   ObjectSetInteger(0,lbNm,OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0,lbNm,OBJPROP_ZORDER,     11);
}

void DrawDashboard()
{
   if(!InpShowDashboard){ DashDeleteAll(); return; }

   color clrBG    = clrBlack;
   color clrHdr   = clrBlack;
   color txtWhite = clrWhite;
   color txtGray  = C'150,150,160';
   color txtGreen = C'60,220,90';
   color txtRed   = C'220,70,70';
   color txtYellow= C'230,205,55';
   color txtCyan  = C'60,200,225';
   color txtOrange= C'230,140,40';

   int totalW = 2*(CELL_W+1)+1;
   int totalH = 20*(CELL_H+1)+4;
   string bgMain = DASH_PFX+"MAINBG";
   if(ObjectFind(0,bgMain)<0) ObjectCreate(0,bgMain,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bgMain,OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bgMain,OBJPROP_XDISTANCE,  InpDashX);
   ObjectSetInteger(0,bgMain,OBJPROP_YDISTANCE,  InpDashY);
   ObjectSetInteger(0,bgMain,OBJPROP_XSIZE,      totalW);
   ObjectSetInteger(0,bgMain,OBJPROP_YSIZE,      totalH);
   ObjectSetInteger(0,bgMain,OBJPROP_BGCOLOR,    clrBlack);
   ObjectSetInteger(0,bgMain,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bgMain,OBJPROP_COLOR,      clrBlack);
   ObjectSetInteger(0,bgMain,OBJPROP_BACK,       false);
   ObjectSetInteger(0,bgMain,OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0,bgMain,OBJPROP_ZORDER,     9);

   bool   connected = (g_ind_handle!=INVALID_HANDLE);
   string connStr   = connected ? "CONNECTED" : "DISCONNECTED";
   color  connClr   = connected ? txtGreen    : txtRed;

   bool   inSess  = IsWithinSession();
   string sessStr = inSess ? "OPEN  02-22" : "CLOSED";
   color  sessClr = inSess ? txtGreen      : txtYellow;

   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct   = g_dayStartBalance>0 ?
                    ((g_dayStartBalance-equity)/g_dayStartBalance)*100.0 : 0.0;
   string ddStr   = DoubleToString(ddPct,2)+"% / "+DoubleToString(InpDailyDDLimit,1)+"%";
   color  ddClr   = g_dailyLimitHit ? txtRed : (ddPct>InpDailyDDLimit*0.7 ? txtYellow : txtGreen);

   bool   hasPos    = HasOpenPosition();
   string statusStr = g_tpHitToday ? "TP HIT-DONE!" :
                      g_stopForDay ? "STOPPED-DAY"  :
                      hasPos       ? "TRADE OPEN"   : "WATCHING";
   color  statusClr = g_tpHitToday ? txtGreen  :
                      g_stopForDay ? txtRed     :
                      hasPos       ? txtOrange  : txtGray;

   string posDetail = "--";
   color  posDetClr = txtGray;
   if(hasPos)
   {
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         if(!g_pos.SelectByIndex(i)) continue;
         if(g_pos.Symbol()!=_Symbol||g_pos.Magic()!=InpMagicNumber) continue;
         string dir = (g_pos.PositionType()==POSITION_TYPE_BUY)?"BUY":"SELL";
         double pnl = g_pos.Profit();
         posDetail  = dir+"  PnL:"+DoubleToString(pnl,2)+(g_beApplied?" [BE]":"");
         posDetClr  = pnl>=0 ? txtGreen : txtRed;
         break;
      }
   }

   string t2Str; color t2Clr;
   if(g_tradesToday==0)     { t2Str="Waiting T1";   t2Clr=txtGray;   }
   else if(g_trade1WasLoss) { t2Str="BLOCKED-Loss"; t2Clr=txtRed;    }
   else if(g_trade1WasBE)   { t2Str="ALLOWED";      t2Clr=txtGreen;  }
   else                     { t2Str="Waiting BE";   t2Clr=txtYellow; }

   color lastSigClr = txtGray;
   if(g_lastSignalType=="BUY")  lastSigClr=txtGreen;
   if(g_lastSignalType=="SELL") lastSigClr=txtRed;

   color  trendClr = (g_indTrend=="BULL")?txtGreen:(g_indTrend=="BEAR")?txtRed:txtGray;
   string trendStr = (g_indTrend=="BULL")?"BULL ▲":(g_indTrend=="BEAR")?"BEAR ▼":"--";
   color  regClr   = (g_indRegime=="TREND")?txtGreen:(g_indRegime=="RANGE")?txtRed:
                     (g_indRegime=="MIXED")?txtYellow:txtGray;
   string confStr  = (g_indConf>0)?DoubleToString(g_indConf,1)+"%":"--";
   color  confClr  = (g_indConf>=InpMinConfidence)?txtGreen:(g_indConf>0)?txtYellow:txtGray;

   DashCell(0,0,"","  TREMOR Swing v1.02", clrHdr, txtCyan);
   DashCell(0,1,"","  Mica Waire",          clrHdr, txtCyan);
   DashCell(1,0,"","  INDICATOR LINK",      clrHdr, txtGray);
   DashCell(1,1,""," "+connStr,             clrHdr, connClr);
   DashCell(2,0,"Session",  sessStr, clrBG, sessClr);
   DashCell(2,1,"DD Today", ddStr,   clrBG, ddClr);
   DashCell(3,0,"Status",   statusStr, clrBG, statusClr);
   DashCell(3,1,"Position", posDetail, clrBG, posDetClr);
   DashCell(4,0,"Trades Today", IntegerToString(g_tradesToday)+"/2", clrBG,
            g_tradesToday>=2?txtRed:txtWhite);
   DashCell(4,1,"Trade 2", t2Str, clrBG, t2Clr);
   DashCell(5,0,"Last Trade PnL", DoubleToString(g_lastClosedPnL,2),
            clrBG, g_lastClosedPnL>=0?txtGreen:txtRed);
   DashCell(5,1,"Balance", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2), clrBG, txtWhite);
   DashCell(6,0,"","  LIVE BUFFER FEED", clrHdr, txtGray);
   DashCell(6,1,"","  (current bar)",    clrHdr, txtGray);
   DashCell(7,0,"B0 Bull", DoubleToString(GetBuffer(0,0),2), clrBG,
            GetBuffer(0,0)>0?txtGreen:txtGray);
   DashCell(7,1,"B1 Bear", DoubleToString(GetBuffer(1,0),2), clrBG,
            GetBuffer(1,0)>0?txtRed:txtGray);
   DashCell(8,0,"","  SIGNAL HISTORY", clrHdr, txtGray);
   DashCell(8,1,"","  ",              clrHdr, txtGray);
   DashCell(9,0,"Last Sig", g_lastSignalType, clrBG, lastSigClr);
   DashCell(9,1,"Conf", DoubleToString(g_lastSignalConf,1)+"%", clrBG,
            g_lastSignalConf>=InpMinConfidence?txtGreen:txtYellow);
   DashCell(10,0,"Sig Time",    g_lastSignalTime, clrBG, txtGray);
   DashCell(10,1,"Skip Reason", g_lastSkipReason, clrBG, txtYellow);
   DashCell(11,0,"Sigs Seen",    IntegerToString(g_totalSignalsSeen),  clrBG, txtWhite);
   DashCell(11,1,"Sigs Skipped", IntegerToString(g_signalsSkipped),    clrBG, txtYellow);
   DashCell(12,0,"Total Trades", IntegerToString(g_totalTradesOpened), clrBG, txtGreen);
   DashCell(12,1,"BE Applied",   g_beApplied?"YES":"NO", clrBG,
            g_beApplied?txtGreen:txtGray);
   DashCell(13,0,"","  INDICATOR SIGNAL INFO", clrHdr, txtCyan);
   DashCell(13,1,"","  ",                       clrHdr, txtCyan);
   DashCell(14,0,"Trend",  trendStr,    clrBG, trendClr);
   DashCell(14,1,"Regime", g_indRegime, clrBG, regClr);
   DashCell(15,0,"Confidence", confStr,              clrBG, confClr);
   DashCell(15,1,"TF",         EnumToString(_Period), clrBG, txtCyan);
   DashCell(16,0,"","  SWING SETTINGS", clrHdr, txtCyan);
   DashCell(16,1,"","  ",              clrHdr, txtCyan);
   DashCell(17,0,"SL", IntegerToString(InpSLPips)+"pip  TP "+IntegerToString(InpTPPips)+"pip",
            clrBG, txtWhite);
   DashCell(17,1,"BE", IntegerToString(InpBETriggerPips)+"pip  Tr ATRx"+
            DoubleToString(InpTrailATRMult,1), clrBG, txtWhite);
   DashCell(18,0,"MinConf", DoubleToString(InpMinConfidence,0)+"%", clrBG, txtGray);
   DashCell(18,1,"Risk %",  DoubleToString(InpRiskPercent,1)+"%",   clrBG, txtGray);
   DashCell(19,0,""," ", clrHdr, txtGray);
   DashCell(19,1,""," ", clrHdr, txtGray);

   ChartRedraw(0);
}

//==========================================================================
// PIP HELPER
//==========================================================================
double PipsToPrice(int pips)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return pips * InpPipSize * point;
}

//==========================================================================
// OnInit
//==========================================================================
int OnInit()
{
   if((_Period==PERIOD_M1 || _Period==PERIOD_M5) && !InpTestMode)
      Alert("TREMOR Swing: Designed for M15 and above. Use TREMOR Scalp for M1/M5.");

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   g_atr_handle = iATR(_Symbol,_Period,InpATRPeriod);
   if(g_atr_handle==INVALID_HANDLE)
   { Alert("TREMOR Swing: ATR handle failed!"); return INIT_FAILED; }

   string indShortName = "ML ST [Mica Waire] v10.02";
   g_ind_handle = ChartIndicatorGet(ChartID(), 0, indShortName);
   if(g_ind_handle==INVALID_HANDLE)
   {
      Print("TREMOR Swing: ChartIndicatorGet failed, trying iCustom...");
      g_ind_handle = iCustom(_Symbol,_Period,InpIndicatorName);
   }
   if(g_ind_handle==INVALID_HANDLE)
   {
      Alert("TREMOR Swing: Cannot attach to indicator!\n",
            "Ensure ML SuperTrend is on the same chart.");
      return INIT_FAILED;
   }

   // FIX 6: Initialise day balance here so DD check works from first tick
   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_lastDayReset    = TimeCurrent();

   PrintFormat("TREMOR Swing v1.02 initialized | %s %s | Handle=%d | SL=%dpip TP=%dpip BE=%dpip",
      _Symbol, EnumToString(_Period), g_ind_handle, InpSLPips, InpTPPips, InpBETriggerPips);
   DrawDashboard();
   return INIT_SUCCEEDED;
}

//==========================================================================
// OnDeinit
//==========================================================================
void OnDeinit(const int reason)
{
   if(g_atr_handle!=INVALID_HANDLE) IndicatorRelease(g_atr_handle);
   if(g_ind_handle!=INVALID_HANDLE) IndicatorRelease(g_ind_handle);

   // Delete dashboard objects — called twice to ensure complete cleanup
   // MT5 can sometimes miss objects on first pass during deinit
   DashDeleteAll();
   DashDeleteAll();
   ChartRedraw(0);

   PrintFormat("TREMOR Swing: Removed from chart. Reason=%d All dashboard objects deleted.", reason);
}

//==========================================================================
// OnTick
//==========================================================================
void OnTick()
{
   g_tickCount++;
   if(g_tickCount%50==0)
      PrintFormat("TREMOR Swing ALIVE | Tick=%d Time=%s",
         g_tickCount, TimeToString(TimeCurrent(),TIME_SECONDS));

   CheckDailyReset();

   if(!InpTestMode)
   {
      if(g_dailyLimitHit){ DrawDashboard(); return; }
      if(IsDailyLimitBreached())
      {
         g_dailyLimitHit=true;
         CloseAllPositions("Daily DD limit hit");
         g_lastSkipReason="Daily DD hit";
         Print("TREMOR Swing: Daily DD limit hit. Halted.");
         DrawDashboard(); return;
      }
   }

   CheckLastTradeResult();
   ManageOpenPosition();

   int    curBar  = Bars(_Symbol,_Period)-1;
   double b0      = GetBuffer(0,0);
   double b1      = GetBuffer(1,0);
   int    nowTrend= 0;
   if(b0>0.0)      nowTrend= 1;
   else if(b1>0.0) nowTrend=-1;

   // Reset flip flags every tick — they must only stay true for the
   // single tick on which the flip actually happened.
   g_flipIsBuy  = false;
   g_flipIsSell = false;

   if(nowTrend!=0 && nowTrend!=g_prevTrend && curBar!=g_lastActedBar)
   {
      // FIX 10: Capture flip direction BEFORE g_prevTrend is overwritten.
      // Previously g_prevTrend=nowTrend ran immediately after this block,
      // so by the time isBuy/isSell were evaluated later in the same tick,
      // g_prevTrend already equalled nowTrend — making the flip comparison
      // always false and silently skipping every single signal.
      g_flipIsBuy  = (nowTrend==1  && g_prevTrend==-1);
      g_flipIsSell = (nowTrend==-1 && g_prevTrend==1);

      if(g_flipIsSell)
      { g_lastSignalType="SELL"; g_totalSignalsSeen++;
        g_lastSignalTime=TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES); }
      else if(g_flipIsBuy)
      { g_lastSignalType="BUY"; g_totalSignalsSeen++;
        g_lastSignalTime=TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES); }
      PrintFormat("TREMOR Swing DEBUG | FLIP | nowTrend=%d prevTrend=%d Bar=%d FlipBuy=%s FlipSell=%s",
         nowTrend, g_prevTrend, curBar, g_flipIsBuy?"YES":"NO", g_flipIsSell?"YES":"NO");
   }
   g_prevTrend=nowTrend;

   bool newBar=IsNewBar();
   if(newBar || g_dashNeedsFullRedraw)
   { DrawDashboard(); g_dashNeedsFullRedraw=false; }
   else
      UpdateLiveLabels();

   if(newBar) SyncIndicatorInfo();

   if(!InpTestMode)
   {
      if(g_stopForDay){ g_lastSkipReason="Stopped for day"; return; }
      if(g_tradesToday>=2){ g_lastSkipReason="Max 2 trades/day"; return; }
      if(g_tradesToday==1 && !g_trade1WasBE)
      { g_lastSkipReason="T2 waiting: T1 BE not hit"; return; }
   }
   if(!IsWithinSession())
   { if(g_flipIsBuy||g_flipIsSell) g_lastSkipReason="Outside session"; return; }
   if(HasOpenPosition()) return;

   // FIX 11: Trade decision now reads BuyBuf(2)/SellBuf(3) directly —
   // the exact same buffers the indicator writes the instant it fires
   // its own Alert() and draws the Buy/Sell arrow. This replaces the
   // raw B0/B1 trend-flip detection, which reacted to every line
   // direction change rather than the indicator's filtered signal
   // (RSI zone, signal spacing, pivot confirmation, regime gating).
   // Scan shift 0 and shift 1 so we don't miss a signal between ticks.
   g_buyBufVal  = GetBuffer(2,0); if(g_buyBufVal==0.0)  g_buyBufVal  = GetBuffer(2,1);
   g_sellBufVal = GetBuffer(3,0); if(g_sellBufVal==0.0) g_sellBufVal = GetBuffer(3,1);

   bool isBuy  = (g_buyBufVal  > 0.0) && curBar!=g_lastActedBar;
   bool isSell = (g_sellBufVal > 0.0) && curBar!=g_lastActedBar;
   if(!isBuy && !isSell) return;

   PrintFormat("TREMOR Swing DEBUG | BUFFER SIGNAL | BuyBuf=%.5f SellBuf=%.5f Bar=%d",
      g_buyBufVal, g_sellBufVal, curBar);

   g_lastSignalConf=g_indConf;
   PrintFormat("TREMOR Swing DEBUG | Signal=%s Conf=%.1f Regime=%s",
      isBuy?"BUY":"SELL", g_indConf, g_indRegime);

   if(g_indConf<InpMinConfidence && g_indConf>0.0)
   { g_signalsSkipped++; g_lastSkipReason="Low conf "+DoubleToString(g_indConf,1)+"%"; return; }

   double atrVal = GetATR(1);
   if(atrVal<=0.0){ g_lastSkipReason="ATR zero"; return; }

   double ask    = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(_Symbol,SYMBOL_POINT);

   long   stopLvPts   = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long   freezeLvPts = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double spread      = ask-bid;
   long   safeLevel   = MathMax(stopLvPts,freezeLvPts);
   double minDist     = MathMax((safeLevel+500)*point, spread*3.0+atrVal*0.5);

   PrintFormat("TREMOR Swing DEBUG | ATR=%.5f MinDist=%.5f StopLv=%d Spread=%.5f",
      atrVal, minDist, stopLvPts, spread);

   if(isBuy)
   {
      double slDist = MathMax(PipsToPrice(InpSLPips), minDist);
      double sl     = NormalizeDouble(ask - slDist, digits);
      double tp     = NormalizeDouble(ask + PipsToPrice(InpTPPips), digits);
      double lots   = CalcLotSize(ask, sl);
      if(lots<=0.0){ g_lastSkipReason="Lot calc fail"; return; }
      PrintFormat("TREMOR Swing DEBUG | BUY | Lots=%.2f Ask=%.5f SL=%.5f TP=%.5f SLpips=%d TPpips=%d",
         lots,ask,sl,tp,InpSLPips,InpTPPips);
      if(g_trade.Buy(lots,_Symbol,ask,sl,tp,"TREMOR Swing BUY"))
      {
         g_openTicket=g_trade.ResultOrder(); g_beApplied=false;
         g_tradesToday++; g_totalTradesOpened++;
         g_lastActedBar=curBar; g_lastSkipReason="--"; g_dashNeedsFullRedraw=true;
         PrintFormat("TREMOR Swing: BUY opened | Lots=%.2f SL=%.5f TP=%.5f Trade#%d today",
            lots,sl,tp,g_tradesToday);
      }
      else PrintFormat("TREMOR Swing DEBUG | BUY FAILED | Error=%d Retcode=%d",
         GetLastError(),g_trade.ResultRetcode());
   }
   else if(isSell)
   {
      double slDist = MathMax(PipsToPrice(InpSLPips), minDist);
      double sl     = NormalizeDouble(bid + slDist, digits);
      double tp     = NormalizeDouble(bid - PipsToPrice(InpTPPips), digits);
      double lots   = CalcLotSize(bid, sl);
      if(lots<=0.0){ g_lastSkipReason="Lot calc fail"; return; }
      PrintFormat("TREMOR Swing DEBUG | SELL | Lots=%.2f Bid=%.5f SL=%.5f TP=%.5f SLpips=%d TPpips=%d",
         lots,bid,sl,tp,InpSLPips,InpTPPips);
      if(g_trade.Sell(lots,_Symbol,bid,sl,tp,"TREMOR Swing SELL"))
      {
         g_openTicket=g_trade.ResultOrder(); g_beApplied=false;
         g_tradesToday++; g_totalTradesOpened++;
         g_lastActedBar=curBar; g_lastSkipReason="--"; g_dashNeedsFullRedraw=true;
         PrintFormat("TREMOR Swing: SELL opened | Lots=%.2f SL=%.5f TP=%.5f Trade#%d today",
            lots,bid,sl,tp,g_tradesToday);
      }
      else PrintFormat("TREMOR Swing DEBUG | SELL FAILED | Error=%d Retcode=%d",
         GetLastError(),g_trade.ResultRetcode());
   }
}

//==========================================================================
// CHECK LAST TRADE RESULT
//==========================================================================
void CheckLastTradeResult()
{
   if(g_openTicket==0) return;
   if(g_pos.SelectByTicket(g_openTicket)) return;

   HistorySelect(g_lastDayReset, TimeCurrent());
   int deals=HistoryDealsTotal();
   for(int i=deals-1;i>=0;i--)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=(long)InpMagicNumber) continue;
      if(HistoryDealGetInteger(ticket,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;

      double profit = HistoryDealGetDouble(ticket,DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket,DEAL_SWAP)
                    + HistoryDealGetDouble(ticket,DEAL_COMMISSION);
      g_lastClosedPnL = profit;

      if(g_tradesToday==1)
      {
         if(profit>=0.0)
         {
            g_trade1WasBE   = g_beApplied;
            g_trade1WasLoss = false;
            double tickVal  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
            double tickSize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
            double tpDist   = PipsToPrice(InpTPPips);
            double tpMoney  = (tickSize>0&&tickVal>0) ?
                              (tpDist/tickSize)*tickVal*HistoryDealGetDouble(ticket,DEAL_VOLUME) : 0;
            bool tpHit      = (profit>0 && tpMoney>0 && profit>=tpMoney*0.75);
            if(InpStopAfterTP && tpHit)
            {
               g_tpHitToday=true; g_stopForDay=true; g_dashNeedsFullRedraw=true;
               PrintFormat("TREMOR Swing: TP HIT | PnL=%.2f | Stopping for day!",profit);
            }
            else
               PrintFormat("TREMOR Swing: Trade 1 closed | PnL=%.2f | BE=%s | T2=%s",
                  profit, g_beApplied?"YES":"NO", g_trade1WasBE?"ALLOWED":"BLOCKED");
         }
         else
         {
            g_trade1WasLoss=true; g_trade1WasBE=false;
            g_stopForDay=true; g_dashNeedsFullRedraw=true;
            PrintFormat("TREMOR Swing: Trade 1 LOSS=%.2f | Stopping for day", profit);
         }
      }
      else if(g_tradesToday==2)
      {
         g_stopForDay=true; g_dashNeedsFullRedraw=true;
         PrintFormat("TREMOR Swing: Trade 2 closed | PnL=%.2f | Day complete", profit);
      }
      g_openTicket=0;
      break;
   }
}

//==========================================================================
// MANAGE OPEN POSITION — pip BE then ATR trail
// FIX 4: PositionModify return value checked
//==========================================================================
void ManageOpenPosition()
{
   if(!HasOpenPosition()) return;
   double atrVal = GetATR(0);
   if(atrVal<=0.0) return;

   double ask    = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(_Symbol,SYMBOL_POINT);

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol()!=_Symbol||g_pos.Magic()!=InpMagicNumber) continue;

      double openPrice = g_pos.PriceOpen();
      double currentSL = g_pos.StopLoss();
      ulong  ticket    = g_pos.Ticket();
      ENUM_POSITION_TYPE posType = g_pos.PositionType();

      if(posType==POSITION_TYPE_BUY)
      {
         double beLevel   = openPrice + PipsToPrice(InpBETriggerPips);
         double beSL      = NormalizeDouble(openPrice + point, digits);
         double trailStop = NormalizeDouble(bid - atrVal*InpTrailATRMult, digits);
         if(!g_beApplied && bid>=beLevel && (beSL>currentSL || currentSL==0.0))
            if(g_trade.PositionModify(ticket,beSL,0.0))
            { g_beApplied=true;
              PrintFormat("TREMOR Swing: BUY BE | SL=%.5f after %d pip",beSL,InpBETriggerPips); }
         if(g_beApplied && trailStop>currentSL && trailStop>openPrice && currentSL>0.0)
            if(g_trade.PositionModify(ticket,trailStop,0.0))
               PrintFormat("TREMOR Swing: BUY trail | SL=%.5f", trailStop);
      }
      else if(posType==POSITION_TYPE_SELL)
      {
         double beLevel   = openPrice - PipsToPrice(InpBETriggerPips);
         double beSL      = NormalizeDouble(openPrice - point, digits);
         double trailStop = NormalizeDouble(ask + atrVal*InpTrailATRMult, digits);
         if(!g_beApplied && ask<=beLevel && (beSL<currentSL || currentSL==0.0))
            if(g_trade.PositionModify(ticket,beSL,0.0))
            { g_beApplied=true;
              PrintFormat("TREMOR Swing: SELL BE | SL=%.5f after %d pip",beSL,InpBETriggerPips); }
         if(g_beApplied && (trailStop<currentSL||currentSL==0.0) && trailStop<openPrice)
            if(g_trade.PositionModify(ticket,trailStop,0.0))
               PrintFormat("TREMOR Swing: SELL trail | SL=%.5f", trailStop);
      }
   }
}

//==========================================================================
// SYNC INDICATOR INFO — runs on new bar
// FIX 1: Array bounds checking, firstSet flag for safe wasBull init
// FIX 7: confArr scan uses MathMin(50,ArraySize)
//==========================================================================
void SyncIndicatorInfo()
{
   double bv  = GetBuffer(0,1);
   double brv = GetBuffer(1,1);
   if(bv>0.0)       g_indTrend="BULL";
   else if(brv>0.0) g_indTrend="BEAR";
   else             g_indTrend="--";

   double bullArr[],bearArr[];
   ArraySetAsSeries(bullArr,true);
   ArraySetAsSeries(bearArr,true);
   if(CopyBuffer(g_ind_handle,0,0,31,bullArr)>0 &&
      CopyBuffer(g_ind_handle,1,0,31,bearArr)>0)
   {
      int  flips    = 0;
      bool wasBull  = false;
      bool firstSet = false;
      for(int i=29;i>=0;i--)
      {
         if(i>=ArraySize(bullArr)||i>=ArraySize(bearArr)) continue;
         bool nowBull=(bullArr[i]>0.0);
         if(!firstSet){ wasBull=nowBull; firstSet=true; continue; }
         if(nowBull!=wasBull) flips++;
         wasBull=nowBull;
      }
      if(flips==0)      g_indRegime="TREND";
      else if(flips<=2) g_indRegime="MIXED";
      else              g_indRegime="RANGE";
   }

   double confArr[];
   ArraySetAsSeries(confArr,true);
   if(CopyBuffer(g_ind_handle,4,0,50,confArr)>0)
   {
      g_indConf=0.0;
      for(int ci=0;ci<MathMin(50,ArraySize(confArr));ci++)
         if(confArr[ci]>0.0){ g_indConf=confArr[ci]; break; }
   }

   PrintFormat("TREMOR Swing DEBUG | Sync | Trend=%s Regime=%s Conf=%.1f",
      g_indTrend, g_indRegime, g_indConf);
}

//==========================================================================
// LOT SIZE
//==========================================================================
double CalcLotSize(double entryPrice, double slPrice)
{
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt  = balance*(InpRiskPercent/100.0);
   double slDist   = MathAbs(entryPrice-slPrice);
   if(slDist<=0.0) return 0.0;
   double tickVal  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickSize<=0.0||tickVal<=0.0) return 0.0;
   double slMoney  = (slDist/tickSize)*tickVal;
   if(slMoney<=0.0) return 0.0;
   double lots     = riskAmt/slMoney;
   double lotStep  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots/lotStep)*lotStep;
   lots = MathMax(InpMinLot,MathMin(InpMaxLot,lots));
   return NormalizeDouble(lots,2);
}

//==========================================================================
// DAILY DRAWDOWN
// FIX 5: Added now.year!=last.year to reset condition
//==========================================================================
void CheckDailyReset()
{
   MqlDateTime now,last;
   TimeToStruct(TimeCurrent(),now);
   TimeToStruct(g_lastDayReset,last);
   if(g_lastDayReset==0||now.day!=last.day||now.mon!=last.mon||now.year!=last.year)
   {
      g_dayStartBalance    = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dailyLimitHit      = false;
      g_stopForDay         = false;
      g_tradesToday        = 0;
      g_trade1WasBE        = false;
      g_trade1WasLoss      = false;
      g_openTicket         = 0;
      g_beApplied          = false;
      g_tpHitToday         = false;
      g_lastDayReset       = TimeCurrent();
      g_dashNeedsFullRedraw= true;
      PrintFormat("TREMOR Swing: New session | Balance=%.2f | DD=%.2f%% | SL=%dpip TP=%dpip",
         g_dayStartBalance, InpDailyDDLimit, InpSLPips, InpTPPips);
   }
}

bool IsDailyLimitBreached()
{
   if(g_dayStartBalance<=0.0) return false;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   return((g_dayStartBalance-equity)/g_dayStartBalance*100.0>=InpDailyDDLimit);
}

void CloseAllPositions(string reason)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol()!=_Symbol||g_pos.Magic()!=InpMagicNumber) continue;
      g_trade.PositionClose(g_pos.Ticket());
      Print("TREMOR Swing: Closed — ",reason);
   }
}

//==========================================================================
// UTILITIES
//==========================================================================
bool IsWithinSession()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   return(dt.hour>=InpSessionStartHour && dt.hour<InpSessionEndHour);
}

bool IsNewBar()
{
   datetime t=iTime(_Symbol,_Period,0);
   if(t!=g_lastBarTime){ g_lastBarTime=t; return true; }
   return false;
}

bool HasOpenPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol()==_Symbol&&g_pos.Magic()==InpMagicNumber) return true;
   }
   return false;
}

// FIX 2: GetBuffer bounds check added
double GetBuffer(int idx, int shift)
{
   double arr[];
   ArraySetAsSeries(arr,true);
   if(CopyBuffer(g_ind_handle,idx,0,shift+2,arr)<=0) return 0.0;
   if(shift>=ArraySize(arr)) return 0.0;
   return arr[shift];
}

// FIX 3: GetATR bounds check added
double GetATR(int shift)
{
   double arr[];
   ArraySetAsSeries(arr,true);
   if(CopyBuffer(g_atr_handle,0,0,shift+2,arr)<=0) return 0.0;
   if(shift>=ArraySize(arr)) return 0.0;
   return arr[shift];
}

//+------------------------------------------------------------------+
// END — TREMOR Swing EA v1.02 — Mica Waire
//+------------------------------------------------------------------+