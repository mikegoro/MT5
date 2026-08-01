//+------------------------------------------------------------------+
//|  Machine Learning SuperTrend EA [Mica Waire] — MQL5 Expert      |
//|  Author  : Mica Waire                                           |
//|  Version : v11.00 — Full EA conversion of ML SuperTrend v10.02  |
//+------------------------------------------------------------------+
//  CHANGELOG v11.00 (Mica Waire):
//  v11.00 — Converted indicator to trade-executing Expert Advisor
//  v11.00 — All state updated once per CLOSED bar (fixes per-tick
//           RMA/queue corruption present in the indicator)
//  v11.00 — Risk Guard now driven by REAL closed-trade PnL
//  v11.00 — Higher-timeframe SuperTrend alignment filter
//  v11.00 — Confidence gating with A/B grades (A+ signals only mode)
//  v11.00 — Regime-grid expectancy veto (skip historically losing states)
//  v11.00 — Session filter, spread cap, overextension + candle-body vetoes
//  v11.00 — Risk-percent position sizing, ATR stop/target, ST-line trail
//  v11.00 — Daily equity drawdown stop (prop-firm guard)
//  v11.00 — Live signals settle into win-rate stats as 5-bar exits mature
//+------------------------------------------------------------------+
#property copyright "Mica Waire — ML SuperTrend EA v11.00"
#property version   "11.00"
#property strict

#include <Trade\Trade.mqh>

CTrade g_trade;

//==========================================================================
// ENUMS
//==========================================================================
enum ENUM_SIGNAL_MODE
{
   SignalAuto      = 0,  // Auto (regime decides)
   SignalReversal  = 1,  // Reversal
   SignalBreakout  = 2   // Breakout
};

enum ENUM_SOURCE_TYPE
{
   SRC_OPEN   = 0, // open
   SRC_HIGH   = 1, // high
   SRC_LOW    = 2, // low
   SRC_CLOSE  = 3, // close
   SRC_HL2    = 4, // hl2
   SRC_HLC3   = 5, // hlc3
   SRC_OHLC4  = 6, // ohlc4
   SRC_HLCC4  = 7  // hlcc4
};

enum ENUM_TRADE_GRADE
{
   GradeAOnly = 0,  // A signals only
   GradeAB    = 1   // A and B signals
};

//==========================================================================
// GROUP — TRADING
//==========================================================================
input group "=== TRADING ==="
input long   InpMagic                        = 110011;   // Magic Number
input double InpRiskPct                      = 0.5;      // Risk % of Balance per Trade
input double InpFixedLots                    = 0.0;      // Fixed Lots (0 = use Risk %)
input int    InpMaxSpreadPoints              = 60;       // Max Spread (points, 0 = off)
input bool   InpCloseOnReverse               = true;     // Close on Opposite Signal
input bool   InpTrailWithST                  = true;     // Trail SL on SuperTrend Line
input bool   InpUseBreakEven                 = true;     // Move SL to BreakEven
input double InpBETriggerATR                 = 1.0;      // BE Trigger (xATR profit)
input int    InpBEOffsetPoints               = 10;       // BE Offset (points)
input int    InpSlippagePoints               = 30;       // Max Slippage (points)

//==========================================================================
// GROUP — A+ SIGNAL GATES
//==========================================================================
input group "=== A+ SIGNAL GATES ==="
input bool   InpUseHTFFilter                 = true;         // HTF Trend Alignment
input ENUM_TIMEFRAMES InpHTF                 = PERIOD_H1;    // Higher Timeframe
input double InpMinConfidence                = 0.60;         // Min Confidence (B grade)
input double InpGradeAConf                   = 0.75;         // A-Grade Confidence
input ENUM_TRADE_GRADE InpTradeGrade         = GradeAOnly;   // Tradable Grades
input bool   InpUseGridVeto                  = true;         // Regime-Grid Expectancy Veto
input double InpGridVetoThr                  = 0.0;          // Veto if Cell Expectancy Below
input double InpGridVetoMinConf              = 0.25;         // Min Cell Confidence for Veto
input double InpMaxStretchATR                = 1.0;          // Max Chase Beyond Fresh Flip (xATR)
input double InpMinBodyPct                   = 0.40;         // Min Candle Body (% of range)
input bool   InpUseSessionFilter             = true;         // Session Filter (server time)
input int    InpSessionStartHour             = 9;            // Session Start Hour
input int    InpSessionEndHour               = 22;           // Session End Hour
input bool   InpCloseFriday                  = true;         // Flatten Friday Evening
input int    InpFridayCloseHour              = 21;           // Friday Flatten Hour

//==========================================================================
// GROUP — SIGNAL MODE
//==========================================================================
input group "=== SIGNAL MODE ==="
input ENUM_SIGNAL_MODE InpSignalMode         = SignalAuto;   // Signal Type
input bool   InpRequireNewExtreme            = false;        // Require Fresh Pivot
input int    InpMinBarsBetweenSigs           = 10;           // Signal Spacing (bars)

//==========================================================================
// GROUP — VOLATILITY ENVELOPE
//==========================================================================
input group "=== VOLATILITY ENVELOPE ==="
input int    InpSensitivity                  = 30;    // Lookback Window
input int    InpATRPeriod                    = 24;    // Smoothing Period
input double InpMultiplier                   = 1.4;   // Band Width
input ENUM_SOURCE_TYPE InpSourceType         = SRC_HLCC4; // Price Basis
input bool   InpUseATR                       = true;  // True Range Mode (RMA=true, EMA=false)

//==========================================================================
// GROUP — MOMENTUM FILTER
//==========================================================================
input group "=== MOMENTUM FILTER ==="
input bool   InpEnableRSI                    = true;  // RSI Active
input int    InpRSILen                       = 14;    // RSI Length
input int    InpRSILookbackTop               = 50;    // Hot Zone Memory
input int    InpRSILookbackBot               = 50;    // Cold Zone Memory
input int    InpRSITop                       = 70;    // RSI Hot Level
input int    InpRSIBot                       = 30;    // RSI Cold Level

//==========================================================================
// GROUP — FLOW ANALYSIS
//==========================================================================
input group "=== FLOW ANALYSIS ==="
input int    InpVolLookback                  = 3;     // Sample Depth
input double InpVolMultiplier                = 1.2;   // Surge Threshold
input bool   InpRequireVolSpike              = false; // Require Surge
input bool   InpEnableTickPressure           = true;  // Pressure Sensor

//==========================================================================
// GROUP — SIGNAL QUALITY
//==========================================================================
input group "=== SIGNAL QUALITY ==="
input bool   InpMajorLevelsOnly              = false; // Key Levels Only
input double InpMajorLevelDepth              = 4.5;   // Key Level Depth (xATR)

//==========================================================================
// GROUP — MASTER DIAL / AUTO-TUNE
//==========================================================================
input group "=== AUTO-TUNE ENGINE ==="
input int    InpDialK                        = 10;    // Reactivity 1-20
input bool   InpEnableBinLearning            = true;  // Micro-Batch Processing
input bool   InpEnableAdaptive               = true;  // Enable Auto-Tune
input bool   InpUseFaintCycle                = true;  // Background Test Matrix

//==========================================================================
// GROUP — OPTIMIZER
//==========================================================================
input group "=== OPTIMIZER ==="
input bool   InpLearnEnabled                 = true;  // Optimizer Enable
input double InpLearnRate                    = 0.25;  // Step Size
input int    InpRollN                        = 30;    // History Depth
input double InpWinHi                        = 0.62;  // Win Ceiling
input double InpWinLo                        = 0.38;  // Win Floor
input bool   InpUseATRNorm                   = true;  // Normalize Returns by ATR
input int    InpParamUpdateEvery             = 3;     // Update Cooldown (bars)
input double InpDeadbandMult                 = 0.01;  // Deadband Width
input double InpDeadbandLen                  = 0.25;  // Deadband Period
input double InpQuantStepMult                = 0.05;  // Quant Step Width
input double InpQuantStepStop                = 0.02;  // Quant Step Guard
input double InpQuantStepTP                  = 0.02;  // Quant Step Target
input double InpQuantStepBrk                 = 0.01;  // Quant Step Edge
input int    InpRevertEvery                  = 200;   // Anchor Revert Interval
input double InpRevertStep                   = 0.01;  // Anchor Revert Strength
input double InpPnLCapUSD                    = 750.0; // PnL Cap per Probe (sim)

//==========================================================================
// GROUP — RISK GUARD (REAL PNL)
//==========================================================================
input group "=== RISK GUARD ==="
input int    InpMaxTradesPerSession          = 20;       // Max Entries Per Day
input double InpMaxSessionLoss               = -1000.0;  // Daily Loss Limit USD (closed PnL)
input double InpMaxDailyDDPct                = 4.0;      // Daily Equity DD Stop % (0 = off)
input bool   InpFlattenOnDailyStop           = true;     // Close All on Daily Stop
input int    InpBaseCooldownBars             = 5;        // Base Pause After Loss (bars)
input int    InpMaxConsecLosses              = 3;        // Streak Limit
input bool   InpDynamicCooldown              = true;     // Scale Pause by Loss Size

//==========================================================================
// GROUP — CONTEXT MEMORY (REGIME GRID)
//==========================================================================
input group "=== REGIME GRID ==="
input bool   InpUseCognitiveMap              = true;  // Enable Regime Grid
input int    InpMapGridX                     = 8;     // Regime Bins
input int    InpMapGridY                     = 8;     // Volatility Bins
input double InpMapSigma                     = 0.8;   // Neighbor Blend Radius
input int    InpMapHalfLife                  = 50;    // Decay Half-Life (samples)
input int    InpMapConfScale                 = 20;    // Confidence Ramp (samples)
input double InpMapWeightMax                 = 0.65;  // Max Grid Influence
input double InpVolMaxRatio                  = 2.5;   // Vol Ratio Ceiling

//==========================================================================
// GROUP — DECAY TRACES
//==========================================================================
input group "=== DECAY TRACES ==="
input bool   InpUseSTM                       = true;  // Enable Trace Buffer
input int    InpSTMSize                      = 30;    // Buffer Depth
input double InpSTMDecay                     = 0.02;  // Fade Rate per Bar
input int    InpSTMConsolidateEvery          = 200;   // Merge Interval bars
input double InpSTMMAETailThr                = 0.8;   // Adverse Move Threshold
input double InpSTMTailTightenCap            = 0.02;  // Guard Tighten Cap

//==========================================================================
// GROUP — MISC
//==========================================================================
input group "=== MISC ==="
input double InpStopMult                     = 1.00;   // Guard xATR (initial)
input double InpTPMult                       = 2.00;   // Target xATR (initial)
input double InpBreakoutBuf                  = 0.20;   // Edge Buffer xATR
input double InpTradeSizeUSD                 = 1000.0; // Probe Sim Position USD
input int    InpWarmupBars                   = 2000;   // Warm-up Bars at Start
input bool   InpAlertPopup                   = false;  // Popup Alert on Trade
input bool   InpAlertPush                    = false;  // Push Notification on Trade
input bool   InpShowDashboard                = true;   // Show Info Dashboard

//==========================================================================
// STRUCTS
//==========================================================================
struct Probe
{
   double entry;
   long   bar;
   int    dir;
   bool   active;
   double atr_val;
};

struct GridCell
{
   double mean_atr_ret;
   double down_ewm;
   int    count;
   double conf;
   double d_mult;
   double d_len;
   double d_stop;
   double d_tp;
   double d_brk;
};

struct DecayTrace
{
   double atr_ret;
   double mae_atr;
   double regime;
   double vol_norm;
   double energy;
   int    dir;
};

struct BatchSample
{
   double atr_ret;
   double mae_atr;
   double pnl_usd;
   double conf;
};

struct PendingSig
{
   int    dir;      // +1 long, -1 short
   double entry;    // closed-bar close at signal
   long   bar;      // g_barNum when fired
};

//==========================================================================
// GLOBALS
//==========================================================================
int h_atr14 = INVALID_HANDLE;
int h_atr   = INVALID_HANDLE;
int h_rsi   = INVALID_HANDLE;
int h_adx   = INVALID_HANDLE;

// Adaptive params
double g_mult, g_atrLen, g_stopMult, g_tpMult, g_brkBuf, g_sensitivity;

// Signal SuperTrend state (chart TF, adaptive)
double g_sig_up=0, g_sig_dn=0; int g_sig_trend=1; double g_sig_rma=0;
int    g_sig_trend_prev=1;

// HTF SuperTrend state (fixed params — stability filter)
double g_htf_up=0, g_htf_dn=0; int g_htf_trend=1; double g_htf_rma=0;
datetime g_htf_lastBar=0;

// Signal flags
int g_topFlag=0, g_topFlagPrev=0;
int g_botFlag=0, g_botFlagPrev=0;
long g_lastSigBar=-9999;

// Regime
double g_regime=0.5;
long   g_lastRegBar=-99;

// Rolling queues (one push per CLOSED bar)
double g_highs[], g_lows[], g_rsis[], g_vols[];

// Test matrix
Probe g_probesL[], g_probesS[];

// Rolling probe stats
double g_rollUSD_L[], g_rollATR_L[];
double g_rollUSD_S[], g_rollATR_S[];
double g_gp_L=0,g_gl_L=0,g_gp_S=0,g_gl_S=0;
int    g_tot_L=0,g_win_L=0,g_tot_S=0,g_win_S=0;
double g_consecLoss_L=0, g_consecLoss_S=0;
double g_sharpe_L=0, g_sortino_L=0;
double g_sharpe_S=0, g_sortino_S=0;

// Actual signal outcome counters — settled via pending queue as exits mature
int    g_sig_tot_L=0, g_sig_win_L=0;
int    g_sig_tot_S=0, g_sig_win_S=0;
PendingSig g_pending[];

// Regime grid
GridCell g_grid[];

// Decay traces
DecayTrace g_decay[];

// Micro-batch
BatchSample g_batchL[], g_batchS[];
bool   g_firedL=false, g_firedS=false;
double g_muBL=0, g_muBS=0;
double g_dMultBL=0,g_dLenBL=0,g_dStopBL=0,g_dTPBL=0,g_dBrkBL=0;
double g_dMultBS=0,g_dLenBS=0,g_dStopBS=0,g_dTPBS=0,g_dBrkBS=0;

// Optimizer state
long   g_lastParamBar=-1;

// Risk guard — REAL PnL
long   g_cooldownUntil=0;
int    g_tradesSession=0;
double g_sessionPnL=0;        // closed real PnL today
int    g_consecLosses=0;
double g_dayStartEquity=0;
bool   g_dailyStopHit=false;

// Pressure sensor (EWM flows, once per bar)
double g_pressure=0, g_bullFlow=0, g_bearFlow=0;
double g_pressureLog[];

// Bar bookkeeping
long     g_barNum=0;
datetime g_lastBarTime=0;
datetime g_lastSessionDay=0;
bool     g_warmupDone=false;

// Last-bar cache for execution/dashboard
double g_lastATR=0.0001;
double g_lastConf=0;
string g_lastSignalStr="--";
double g_volNorm=0.5;

// Dashboard
#define DASH_PREFIX "MLSTEA_"

//==========================================================================
// UTILITIES
//==========================================================================
double Clamp(double v,double lo,double hi){return MathMax(lo,MathMin(hi,v));}
double Quantize(double x,double step){return step==0?x:MathRound(x/step)*step;}

void QPush(double &arr[],double val,int cap)
{
   int sz=ArraySize(arr);
   if(sz>=cap){for(int i=0;i<sz-1;i++)arr[i]=arr[i+1];arr[sz-1]=val;}
   else{ArrayResize(arr,sz+1);arr[sz]=val;}
}
void QPushB(BatchSample &arr[], BatchSample &val, int cap)
{
   int sz=ArraySize(arr);
   if(sz>=cap){for(int i=0;i<sz-1;i++)arr[i]=arr[i+1];arr[sz-1]=val;}
   else{ArrayResize(arr,sz+1);arr[sz]=val;}
}
double QAvg(double &arr[],int n)
{
   int sz=ArraySize(arr); if(sz==0||n<=0)return 0;
   double s=0;int c=0;
   for(int i=MathMax(0,sz-n);i<sz;i++){s+=arr[i];c++;}
   return c>0?s/c:0;
}
double QMax(double &arr[],int n)
{
   int sz=ArraySize(arr);if(sz==0||n<=0)return -1e18;
   double m=arr[MathMax(0,sz-n)];
   for(int i=MathMax(0,sz-n)+1;i<sz;i++)if(arr[i]>m)m=arr[i];
   return m;
}
double QMin(double &arr[],int n)
{
   int sz=ArraySize(arr);if(sz==0||n<=0)return 1e18;
   double m=arr[MathMax(0,sz-n)];
   for(int i=MathMax(0,sz-n)+1;i<sz;i++)if(arr[i]<m)m=arr[i];
   return m;
}
double QAvgFull(double &arr[])
{
   int sz=ArraySize(arr);if(sz==0)return 0;
   double s=0;for(int i=0;i<sz;i++)s+=arr[i];return s/sz;
}
double QWinRate(double &arr[])
{
   int sz=ArraySize(arr);if(sz==0)return 0.5;
   double w=0;for(int i=0;i<sz;i++)if(arr[i]>0)w++;return w/sz;
}
double QSortino(double &arr[])
{
   int sz=ArraySize(arr);if(sz==0)return 0;
   double mean=QAvgFull(arr),ddSum=0;int ddCnt=0;
   for(int i=0;i<sz;i++)if(arr[i]<0){ddSum+=arr[i]*arr[i];ddCnt++;}
   if(ddCnt==0)return 0;
   double dd=MathSqrt(ddSum/ddCnt);
   return dd>0?mean/dd:0;
}
double QSharpe(double &arr[])
{
   int sz=ArraySize(arr);if(sz<2)return 0;
   double mean=QAvgFull(arr);
   double ssq=0;
   for(int i=0;i<sz;i++)ssq+=(arr[i]-mean)*(arr[i]-mean);
   double sd=MathSqrt(ssq/sz);
   return sd>0?mean/sd:0;
}
void UpdateSharpeSortino()
{
   g_sharpe_L  = QSharpe(g_rollATR_L);
   g_sortino_L = QSortino(g_rollATR_L);
   g_sharpe_S  = QSharpe(g_rollATR_S);
   g_sortino_S = QSortino(g_rollATR_S);
}

//==========================================================================
// SUPERTREND STEP (one call per CLOSED bar)
//==========================================================================
void ST_Step(double src,double mult,int period,bool useRMA,
             double prevClose,double curClose,double tr,
             double &up,double &dn,int &trend,double &rmaVal)
{
   double alpha=1.0/MathMax(1,period);
   if(useRMA) rmaVal=(rmaVal==0)?tr:rmaVal+alpha*(tr-rmaVal);
   else       rmaVal=(rmaVal==0)?tr:(2.0/(period+1))*tr+(1.0-2.0/(period+1))*rmaVal;

   double band=mult*rmaVal;
   double newUp=src-band, newDn=src+band;
   if(up!=0) newUp=(prevClose>up)?MathMax(newUp,up):newUp;
   if(dn!=0) newDn=(prevClose<dn)?MathMin(newDn,dn):newDn;
   up=newUp; dn=newDn;
   if(trend==-1&&curClose>dn)trend=1;
   else if(trend==1&&curClose<up)trend=-1;
}

//==========================================================================
// HURST / ENTROPY / REGIME  (arrays are series: idx+i = older)
//==========================================================================
double CalcHurst(const double &closeArr[],int idx,int total,int len)
{
   int L=MathMax(len,16);
   if(idx+L>=total)return 0.5;
   double mean=0;
   for(int i=0;i<L;i++)mean+=closeArr[idx+i];
   mean/=L;
   double cum=0,maxC=0,minC=0,ssq=0;
   for(int i=0;i<L;i++)
   {
      double dev=closeArr[idx+i]-mean;
      cum+=dev;
      if(cum>maxC)maxC=cum;
      if(cum<minC)minC=cum;
      ssq+=dev*dev;
   }
   double R=maxC-minC;
   double S=MathSqrt(ssq/L);
   if(S==0||L<=1)return 0.5;
   return Clamp(MathLog(R/S)/MathLog(L),0.0,1.0);
}
double CalcEntropy(const double &closeArr[],int idx,int total,int len)
{
   int L=MathMax(len,16);
   if(idx+L>=total)return 0.0;
   double ups=0,dns=0;
   for(int i=1;i<=L;i++)
   {
      double d=closeArr[idx+i-1]-closeArr[idx+i];
      if(d>0)ups++;else if(d<0)dns++;
   }
   double tot=ups+dns;if(tot==0)return 0;
   double p1=ups/tot,p2=dns/tot,H=0;
   if(p1>0)H-=p1*MathLog(p1);
   if(p2>0)H-=p2*MathLog(p2);
   return Clamp(H/MathLog(2.0),0.0,1.0);
}
double DetectRegime(const double &closeArr[],int idx,int total,double adxVal)
{
   double H=CalcHurst(closeArr,idx,total,64);
   double Ent=CalcEntropy(closeArr,idx,total,64);
   double trend_str=Clamp(adxVal/50.0,0,1);
   return Clamp(0.35*(1-Ent)+0.35*Clamp((H-0.5)*2,0,1)+0.30*trend_str,0.0,1.0);
}

//==========================================================================
// GRID FUNCTIONS
//==========================================================================
int GridIdx(int ix,int iy){return ix*InpMapGridY+iy;}
double Gauss(int dx,int dy,double s){return MathExp(-(dx*dx+dy*dy)/(2*s*s));}
int Bucket(double x,int bins){return(int)Clamp(MathFloor(x*bins),0,bins-1);}

void GridUpdate(int ix,int iy,double atr_ret,
                double dM,double dL,double dS,double dT,double dB)
{
   int idx=GridIdx(ix,iy);
   if(idx<0||idx>=ArraySize(g_grid))return;
   double alpha=1.0-MathExp(-MathLog(2.0)/MathMax(1,InpMapHalfLife));
   GridCell c=g_grid[idx];
   c.mean_atr_ret=c.mean_atr_ret*(1-alpha)+atr_ret*alpha;
   double dn2=atr_ret<0?atr_ret*atr_ret:0.0;
   c.down_ewm=c.down_ewm*(1-alpha)+dn2*alpha;
   c.count++;
   c.conf=1.0-MathExp(-(double)c.count/MathMax(1,InpMapConfScale));
   c.d_mult=c.d_mult*(1-alpha)+dM*alpha;
   c.d_len =c.d_len *(1-alpha)+dL*alpha;
   c.d_stop=c.d_stop*(1-alpha)+dS*alpha;
   c.d_tp  =c.d_tp  *(1-alpha)+dT*alpha;
   c.d_brk =c.d_brk *(1-alpha)+dB*alpha;
   g_grid[idx]=c;
}

void GridRecommend(int ix,int iy,
                   double &m,double &l,double &s,double &t,double &b,double &confOut)
{
   double wsum=0,wconf=0;
   m=0;l=0;s=0;t=0;b=0;confOut=0;
   for(int dx=-1;dx<=1;dx++)for(int dy=-1;dy<=1;dy++)
   {
      int nx=(int)Clamp(ix+dx,0,InpMapGridX-1);
      int ny=(int)Clamp(iy+dy,0,InpMapGridY-1);
      int idx2=GridIdx(nx,ny);
      if(idx2<0||idx2>=ArraySize(g_grid))continue;
      GridCell c=g_grid[idx2];
      if(c.count==0)continue;
      double w=Gauss(dx,dy,InpMapSigma);
      wsum+=w; double cf=c.conf; wconf+=w*cf;
      m+=w*cf*c.d_mult; l+=w*cf*c.d_len; s+=w*cf*c.d_stop;
      t+=w*cf*c.d_tp;   b+=w*cf*c.d_brk;
   }
   if(wsum==0)return;
   double den=wconf==0?wsum:wconf;
   m/=den;l/=den;s/=den;t/=den;b/=den;
   confOut=Clamp(wconf/wsum,0.0,1.0);
}

// Weighted expectancy of the neighborhood — used as an A+ veto:
// negative learned edge in this market state blocks the signal.
void GridExpectancy(int ix,int iy,double &expOut,double &confOut)
{
   expOut=0;confOut=0;
   double wsum=0,esum=0,wconf=0;
   for(int dx=-1;dx<=1;dx++)for(int dy=-1;dy<=1;dy++)
   {
      int nx=(int)Clamp(ix+dx,0,InpMapGridX-1);
      int ny=(int)Clamp(iy+dy,0,InpMapGridY-1);
      int idx2=GridIdx(nx,ny);
      if(idx2<0||idx2>=ArraySize(g_grid))continue;
      GridCell c=g_grid[idx2];
      if(c.count==0)continue;
      double w=Gauss(dx,dy,InpMapSigma)*c.conf;
      wsum+=w; esum+=w*c.mean_atr_ret; wconf+=Gauss(dx,dy,InpMapSigma)*c.conf;
   }
   if(wsum<=0)return;
   expOut=esum/wsum;
   confOut=Clamp(wconf/9.0,0.0,1.0);
}

//==========================================================================
// DECAY TRACES
//==========================================================================
void DecayPush(double atr_ret,double mae_atr,double regime,double vol,int dir)
{
   int sz=ArraySize(g_decay);
   ArrayResize(g_decay,sz+1);
   g_decay[sz].atr_ret=atr_ret; g_decay[sz].mae_atr=mae_atr;
   g_decay[sz].regime=regime;   g_decay[sz].vol_norm=vol;
   g_decay[sz].energy=1.0;      g_decay[sz].dir=dir;
   while(ArraySize(g_decay)>InpSTMSize)
   { for(int i=0;i<ArraySize(g_decay)-1;i++)g_decay[i]=g_decay[i+1];
     ArrayResize(g_decay,ArraySize(g_decay)-1); }
}
void DecayStep()
{
   for(int i=ArraySize(g_decay)-1;i>=0;i--)
   {
      g_decay[i].energy*=(1.0-InpSTMDecay);
      if(g_decay[i].energy<0.05)
      {
         for(int j=i;j<ArraySize(g_decay)-1;j++)g_decay[j]=g_decay[j+1];
         ArrayResize(g_decay,ArraySize(g_decay)-1);
      }
   }
}
double DecayTailFeedback()
{
   int n=ArraySize(g_decay);if(n==0)return 0;
   double sumW=0,sumTail=0;
   for(int i=0;i<n;i++)
   {
      sumW+=g_decay[i].energy;
      if(g_decay[i].mae_atr>InpSTMMAETailThr)sumTail+=g_decay[i].energy;
   }
   double frac=sumW>0?sumTail/sumW:0;
   double k=Clamp((frac-0.25)/0.75,0.0,1.0);
   return -InpSTMTailTightenCap*k;
}

//==========================================================================
// MASTER DIAL
//==========================================================================
void MasterParams(int K,
   int &N,int &stride,double &Wmin,double &wBatch,
   double &cMult,double &cLen,double &cStop,double &cTP,double &cBrk,
   double &dbMult,double &dbLen,double &alpha)
{
   double k=((double)K-1.0)/19.0;
   N     =(int)Clamp(MathRound(20.0-16.0*k),4,20);
   stride=MathMax(1,(int)MathRound(N*(1.0-0.9*k)));
   Wmin  =MathMax(0.0,(double)N*(0.80-0.40*k));
   wBatch=0.25+0.35*k;
   cMult =0.02+0.06*k; cLen=0.5+1.5*k;
   cStop =0.01+0.04*k; cTP =0.01+0.03*k; cBrk=0.005+0.025*k;
   dbMult=MathMax(0.003,InpDeadbandMult*(1.0-0.6*k));
   dbLen =MathMax(0.10, InpDeadbandLen *(1.0-0.6*k));
   alpha =Clamp(0.25+0.40*k,0.20,0.65);
}

//==========================================================================
// MICRO-BATCH FIRE
//==========================================================================
bool BatchFire(BatchSample &bin[],int N,int stride,double Wmin,
               double cM,double cL,double cS,double cT,double cB,
               double &dM,double &dL,double &dS,double &dT,double &dBrk,double &muOut)
{
   dM=0;dL=0;dS=0;dT=0;dBrk=0;muOut=0;
   int sz=ArraySize(bin);if(sz<N)return false;
   double sumW=0,sumRet=0,wNeg=0,sumNegVar=0,sumMAE=0,gpW=0,glW=0;
   for(int i=0;i<N;i++)
   {
      double wC=Clamp(bin[i].conf,0,1);
      double wQ=1.0/(1.0+MathMax(0,bin[i].mae_atr));
      double w=wC*wQ; sumW+=w; sumRet+=w*bin[i].atr_ret;
      if(bin[i].atr_ret<0){wNeg+=w;sumNegVar+=w*(bin[i].atr_ret*bin[i].atr_ret);}
      sumMAE+=w*bin[i].mae_atr;
      if(bin[i].pnl_usd>0)gpW+=w*bin[i].pnl_usd;
      else if(bin[i].pnl_usd<0)glW+=w*(-bin[i].pnl_usd);
   }
   double mu=sumW>0?sumRet/sumW:0;
   double sr=(wNeg>0&&sumNegVar>0)?mu/MathSqrt(sumNegVar/wNeg):0;
   double pf=glW>0?gpW/glW:(gpW>0?9.99:0.0);
   double mae=sumW>0?sumMAE/sumW:0;
   double confF=Wmin>0?Clamp(sumW/Wmin,0.0,1.5):1.0;
   muOut=mu;
   bool good=(mu>0)&&(pf>1.15)&&(sr>0.8);
   bool bad =(mu<0)||(pf<0.95)||(sr<0.2);
   if(good){dM=-cM*confF;dL=-cL*confF;dS=-cS*confF;dT=+cT*0.5*confF;dBrk=-cB*confF;}
   if(bad) {dM=+cM*confF;dL=+cL*confF;dS=(mae>0.6?-cS:+0.5*cS)*confF;dT=-0.3*cT*confF;dBrk=+cB*confF;}
   for(int j=0;j<stride&&ArraySize(bin)>0;j++)
   {
      for(int k2=0;k2<ArraySize(bin)-1;k2++)bin[k2]=bin[k2+1];
      ArrayResize(bin,ArraySize(bin)-1);
   }
   return true;
}

//==========================================================================
// OPTIMIZER PROPOSALS
//==========================================================================
void LearnProposals(double winrate,double avgUsd,double avgAtr,
                    double sortino,double avgMAE,double pf,
                    double avgWin,double avgLoss,int sampleCount,
                    double curMult,double curLen,double sharpe,int consecLoss,
                    double &dMult,double &dLen,double &dStop,double &dTP,double &dBrk)
{
   dMult=0;dLen=0;dStop=0;dTP=0;dBrk=0;
   if(!InpLearnEnabled||!InpEnableAdaptive||sampleCount<=0)return;
   double conf=1.0/MathSqrt(MathMax(1.0,(double)sampleCount));
   double step=InpLearnRate*conf;
   double pb=ArraySize(g_pressureLog)>=5?QAvg(g_pressureLog,5):0;
   if(MathAbs(pb)>0.2)step*=(1+MathAbs(pb)*0.5);
   bool weak  =(winrate<InpWinLo)&&(InpUseATRNorm?avgAtr<0:avgUsd<0);
   bool strong=(winrate>InpWinHi)&&(InpUseATRNorm?avgAtr>0:avgUsd>0);
   if(weak)  {dMult+=+0.08*step;dLen+=+curLen*0.05*step;}
   if(strong){dMult+=-0.05*step;dLen+=-curLen*0.03*step;}
   if(avgMAE>0.60)dMult+=+0.02*step;
   if(sortino<0)  dMult+=+0.04*step;
   if(sortino>1.2)dMult+=-0.03*step;
   if(winrate>InpWinHi&&pf>0&&pf<1.2)dTP+=+0.02*step;
   if(winrate<InpWinLo&&avgLoss>avgWin*1.2)dStop+=-0.03*step;
   if(winrate<InpWinLo&&avgLoss<=avgWin*1.2)dStop+=+0.02*step;
   if(g_regime>=0.7&&(InpUseATRNorm?avgAtr>0:avgUsd>0))dBrk+=-0.02*step;
   if(g_regime<=0.3&&(InpUseATRNorm?avgAtr<0:avgUsd<0))dBrk+=+0.02*step;
   if(sharpe<0.5) dMult+=+0.02*step;
   if(sortino>1.5)dMult+=-0.02*step;
   if(consecLoss>=3)dStop+=+0.03*step;
}

//==========================================================================
// TEST MATRIX PROBE MANAGEMENT
//==========================================================================
void OpenProbe(Probe &book[],int dir,double entryPrice,double atrVal,long barNum)
{
   int freeIdx=-1;
   for(int i=0;i<ArraySize(book);i++)if(!book[i].active){freeIdx=i;break;}
   if(freeIdx==-1){ArrayResize(book,ArraySize(book)+1);freeIdx=ArraySize(book)-1;}
   book[freeIdx].entry=entryPrice;book[freeIdx].bar=barNum;
   book[freeIdx].dir=dir;book[freeIdx].active=true;book[freeIdx].atr_val=atrVal;
}
int CountActive(Probe &book[])
{
   int c=0;for(int i=0;i<ArraySize(book);i++)if(book[i].active)c++;return c;
}
bool CloseMatured(Probe &book[],int dir,double loHold,double hiHold,
                  double closePrice,long barNum,
                  double &usd,double &atrR,double &mae)
{
   usd=EMPTY_VALUE;atrR=0;mae=0;
   long oldest=LONG_MAX;int idx=-1;
   for(int i=0;i<ArraySize(book);i++)
   {
      if(!book[i].active)continue;
      if(barNum-book[i].bar>=5&&book[i].bar<oldest){oldest=book[i].bar;idx=i;}
   }
   if(idx<0)return false;
   Probe p=book[idx];
   double ret=(closePrice-p.entry)*p.dir;
   double pct=p.entry!=0?ret/p.entry:0;
   usd=pct*InpTradeSizeUSD;
   atrR=p.atr_val!=0?ret/p.atr_val:0;
   double maeP=dir==1?MathMax(0,p.entry-loHold):MathMax(0,hiHold-p.entry);
   mae=p.atr_val!=0?maeP/p.atr_val:0;
   book[idx].active=false;
   return true;
}

//==========================================================================
// RISK GUARD — driven by REAL closed-trade PnL
//==========================================================================
bool DailyEquityOk()
{
   if(InpMaxDailyDDPct<=0||g_dayStartEquity<=0)return true;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   return eq > g_dayStartEquity*(1.0-InpMaxDailyDDPct/100.0);
}
bool CanTrade(long barNum)
{
   if(g_dailyStopHit)return false;
   return barNum>g_cooldownUntil&&
          g_tradesSession<InpMaxTradesPerSession&&
          g_sessionPnL>InpMaxSessionLoss&&
          g_consecLosses<InpMaxConsecLosses&&
          DailyEquityOk();
}
void ApplyRiskGuard(double pnl,long barNum)
{
   g_sessionPnL+=pnl;
   if(pnl<0)
   {
      g_consecLosses++;
      double lossMag=MathAbs(pnl);
      if(InpDynamicCooldown)
      {
         double denom=MathMax(1.0,AccountInfoDouble(ACCOUNT_BALANCE)*0.001);
         double sc=lossMag/denom;
         g_cooldownUntil=barNum+(long)MathMin(50.0,InpBaseCooldownBars*(1.0+sc));
      }
      else g_cooldownUntil=barNum+InpBaseCooldownBars;
   }
   else if(pnl>0) g_consecLosses=0;
}
void CheckSessionReset(datetime barTime)
{
   MqlDateTime dt_now, dt_last;
   TimeToStruct(barTime,          dt_now);
   TimeToStruct(g_lastSessionDay, dt_last);
   if(g_lastSessionDay==0 || dt_now.day!=dt_last.day || dt_now.mon!=dt_last.mon)
   {
      g_tradesSession  = 0;
      g_sessionPnL     = 0;
      g_consecLosses   = 0;
      g_dailyStopHit   = false;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_lastSessionDay = barTime;
   }
}

//==========================================================================
// HTF SUPERTREND FILTER — stepped once per closed HTF bar, fixed params
//==========================================================================
double SrcPrice(double o,double h,double l,double c)
{
   switch(InpSourceType)
   {
      case SRC_OPEN:  return o;
      case SRC_HIGH:  return h;
      case SRC_LOW:   return l;
      case SRC_CLOSE: return c;
      case SRC_HL2:   return (h+l)/2.0;
      case SRC_HLC3:  return (h+l+c)/3.0;
      case SRC_OHLC4: return (o+h+l+c)/4.0;
      default:        return (h+l+c*2.0)/4.0; // hlcc4
   }
}
void UpdateHTF(datetime asOfTime)
{
   if(!InpUseHTFFilter)return;
   if(PeriodSeconds(InpHTF)<=PeriodSeconds(_Period))return; // filter needs a HIGHER TF
   int hs=iBarShift(_Symbol,InpHTF,asOfTime,false);
   if(hs<0)return;
   hs+=1; // last COMPLETED HTF bar as of this chart bar
   datetime ht=iTime(_Symbol,InpHTF,hs);
   if(ht==0||ht<=g_htf_lastBar)return;
   double o=iOpen(_Symbol,InpHTF,hs),h=iHigh(_Symbol,InpHTF,hs);
   double l=iLow(_Symbol,InpHTF,hs), c=iClose(_Symbol,InpHTF,hs);
   double c1=iClose(_Symbol,InpHTF,hs+1);
   if(c1==0)c1=c;
   double tr=MathMax(h-l,MathMax(MathAbs(h-c1),MathAbs(l-c1)));
   double src=SrcPrice(o,h,l,c);
   ST_Step(src,InpMultiplier,InpATRPeriod,InpUseATR,c1,c,tr,
           g_htf_up,g_htf_dn,g_htf_trend,g_htf_rma);
   g_htf_lastBar=ht;
}
bool HTFAllows(int dir)
{
   if(!InpUseHTFFilter)return true;
   if(PeriodSeconds(InpHTF)<=PeriodSeconds(_Period))return true;
   return (dir>0&&g_htf_trend==1)||(dir<0&&g_htf_trend==-1);
}

//==========================================================================
// SESSION / TIME GATES
//==========================================================================
bool InSession(datetime t)
{
   if(!InpUseSessionFilter)return true;
   MqlDateTime dt;TimeToStruct(t,dt);
   int s=InpSessionStartHour,e=InpSessionEndHour;
   if(s==e)return true;
   if(s<e) return dt.hour>=s&&dt.hour<e;
   return dt.hour>=s||dt.hour<e; // overnight wrap
}
bool FridayFlattenTime(datetime t)
{
   if(!InpCloseFriday)return false;
   MqlDateTime dt;TimeToStruct(t,dt);
   return dt.day_of_week==5&&dt.hour>=InpFridayCloseHour;
}

//==========================================================================
// TRADE EXECUTION
//==========================================================================
int OurPositionDir()  // +1 long, -1 short, 0 none (first matching position)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0)continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic)continue;
      return PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
   }
   return 0;
}
void CloseOurPositions(string reason)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0)continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic)continue;
      if(!g_trade.PositionClose(tk))
         PrintFormat("ML ST EA: close failed (%s) ticket=%I64u ret=%d",
                     reason,tk,(int)g_trade.ResultRetcode());
      else
         PrintFormat("ML ST EA: closed ticket=%I64u (%s)",tk,reason);
   }
}
double NormalizeLots(double lots)
{
   double minL=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxL=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double stp =SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(stp>0)lots=MathFloor(lots/stp)*stp;
   return Clamp(lots,minL,maxL);
}
double CalcLots(double slDist)
{
   if(InpFixedLots>0)return NormalizeLots(InpFixedLots);
   if(slDist<=0)return 0;
   double riskMoney=AccountInfoDouble(ACCOUNT_BALANCE)*InpRiskPct/100.0;
   double tickVal =SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickVal<=0||tickSize<=0)return 0;
   double lossPerLot=slDist/tickSize*tickVal;
   if(lossPerLot<=0)return 0;
   double lots=riskMoney/lossPerLot;
   lots=NormalizeLots(lots);
   double minL=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   // Refuse to trade if even the minimum lot risks more than 2x the intended amount
   if(lots<=0||minL*lossPerLot>riskMoney*2.0)return 0;
   return lots;
}
void SendTradeAlert(string msg)
{
   Print("ML ST EA: ",msg);
   if(InpAlertPopup)Alert("ML ST EA — ",msg);
   if(InpAlertPush) SendNotification("ML ST EA — "+msg);
}
void TryOpen(int dir,double conf,string grade)
{
   // spread gate
   if(InpMaxSpreadPoints>0)
   {
      long sp=SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
      if(sp>InpMaxSpreadPoints)
      {
         PrintFormat("ML ST EA: signal skipped — spread %d > %d pts",(int)sp,InpMaxSpreadPoints);
         return;
      }
   }
   int cur=OurPositionDir();
   if(cur==dir)return; // already positioned this way
   if(cur!=0)
   {
      if(!InpCloseOnReverse)return;
      CloseOurPositions("reverse signal");
   }

   double atr=g_lastATR;
   double slDist=Clamp(g_stopMult,0.3,3.0)*atr;
   double tpDist=Clamp(g_tpMult,0.5,5.0)*atr;

   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   long   stopsLvl=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double minDist=(stopsLvl+2)*pt;
   if(slDist<minDist)slDist=minDist;
   if(tpDist<minDist)tpDist=minDist;

   double price=(dir>0)?SymbolInfoDouble(_Symbol,SYMBOL_ASK)
                       :SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl=(dir>0)?price-slDist:price+slDist;
   double tp=(dir>0)?price+tpDist:price-tpDist;
   sl=NormalizeDouble(sl,_Digits);
   tp=NormalizeDouble(tp,_Digits);

   double lots=CalcLots(slDist);
   if(lots<=0)
   {
      Print("ML ST EA: signal skipped — lot size resolves to 0 (risk too small for min lot?)");
      return;
   }

   string cmt=StringFormat("MLST %s c%.0f",grade,conf*100.0);
   bool ok=(dir>0)?g_trade.Buy(lots,_Symbol,0.0,sl,tp,cmt)
                  :g_trade.Sell(lots,_Symbol,0.0,sl,tp,cmt);
   if(ok)
   {
      g_tradesSession++;
      SendTradeAlert(StringFormat("%s %s %.2f lots @ %.5f SL %.5f TP %.5f grade %s conf %.0f%%",
                     dir>0?"BUY":"SELL",_Symbol,lots,price,sl,tp,grade,conf*100.0));
   }
   else
      PrintFormat("ML ST EA: order failed ret=%d (%s)",
                  (int)g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
}
void ManagePositions()
{
   double atr=g_lastATR;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0)continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic)continue;

      bool isLong=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL=PositionGetDouble(POSITION_SL);
      double curTP=PositionGetDouble(POSITION_TP);
      double px=isLong?SymbolInfoDouble(_Symbol,SYMBOL_BID)
                      :SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double newSL=curSL;

      if(InpUseBreakEven&&atr>0)
      {
         double prof=isLong?px-entry:entry-px;
         if(prof>=InpBETriggerATR*atr)
         {
            double be=isLong?entry+InpBEOffsetPoints*pt:entry-InpBEOffsetPoints*pt;
            if(isLong?(be>newSL||newSL==0):(be<newSL||newSL==0))newSL=be;
         }
      }
      if(InpTrailWithST)
      {
         double line=isLong?g_sig_up:g_sig_dn;
         if(line>0)
         {
            if(isLong &&line>newSL&&line<px)newSL=line;
            if(!isLong&&(line<newSL||newSL==0)&&line>px)newSL=line;
         }
      }
      if(newSL!=curSL&&MathAbs(newSL-curSL)>pt)
      {
         newSL=NormalizeDouble(newSL,_Digits);
         if(!g_trade.PositionModify(tk,newSL,curTP))
            PrintFormat("ML ST EA: trail modify failed ticket=%I64u ret=%d",
                        tk,(int)g_trade.ResultRetcode());
      }
   }
}

//==========================================================================
// DASHBOARD — created once, text updated in place (no per-tick churn)
//==========================================================================
void DashLabel(string id,int x,int y,string text,color clr)
{
   string nm=DASH_PREFIX+id;
   if(ObjectFind(0,nm)<0)
   {
      ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,nm,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,8);
      ObjectSetString (0,nm,OBJPROP_FONT,"Courier New");
      ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,nm,OBJPROP_ZORDER,1);
   }
   ObjectSetString (0,nm,OBJPROP_TEXT,text==""?" ":text);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,clr);
}
void DashInitBG(int rows)
{
   string nm=DASH_PREFIX+"BG";
   if(ObjectFind(0,nm)>=0)return;
   ObjectCreate(0,nm,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,nm,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,8);
   ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,18);
   ObjectSetInteger(0,nm,OBJPROP_XSIZE,300);
   ObjectSetInteger(0,nm,OBJPROP_YSIZE,rows*15+10);
   ObjectSetInteger(0,nm,OBJPROP_BGCOLOR,clrBlack);
   ObjectSetInteger(0,nm,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,clrBlack);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,nm,OBJPROP_ZORDER,0);
}
void DashDeleteAll()
{
   int total=ObjectsTotal(0,0,-1);
   for(int i=total-1;i>=0;i--)
   {
      string nm=ObjectName(0,i,0,-1);
      if(StringFind(nm,DASH_PREFIX)==0)ObjectDelete(0,nm);
   }
}
void UpdateDashboard()
{
   if(!InpShowDashboard)return;
   color W=clrWhite,G=C'60,220,90',R=C'220,70,70',Y=C'230,205,55',C=C'60,200,225',GR=C'160,160,170';

   int rows=16;
   DashInitBG(rows);
   int x=14,y=22,dy=15,row=0;

   string regime_str; color regClr;
   if(g_regime>0.65)      { regime_str="TREND"; regClr=G; }
   else if(g_regime<0.35) { regime_str="RANGE"; regClr=Y; }
   else                   { regime_str="MIXED"; regClr=GR;}

   bool isBull=(g_sig_trend==1);
   string htfStr=!InpUseHTFFilter?"OFF":(g_htf_trend==1?"BULL":"BEAR");

   double wrL=(g_sig_tot_L>0)?(double)g_sig_win_L/g_sig_tot_L:0;
   double wrS=(g_sig_tot_S>0)?(double)g_sig_win_S/g_sig_tot_S:0;

   bool riskOk=CanTrade(g_barNum);
   long barsLeft=g_cooldownUntil-g_barNum;

   DashLabel("T0",x,y+dy*row++,"ML SuperTrend EA v11 — Mica Waire",C);
   DashLabel("T1",x,y+dy*row++,StringSubstr(_Symbol,0,8)+" "+EnumToString((ENUM_TIMEFRAMES)_Period),C);
   DashLabel("L0",x,y+dy*row++,"Trend  : "+(isBull?"BULL":"BEAR")+"   HTF: "+htfStr,isBull?G:R);
   DashLabel("L1",x,y+dy*row++,"Regime : "+regime_str+StringFormat("  (%.2f)",g_regime),regClr);
   DashLabel("L2",x,y+dy*row++,StringFormat("Conf   : %.0f%%   Last: %s",g_lastConf*100.0,g_lastSignalStr),Y);
   DashLabel("L3",x,y+dy*row++,StringFormat("Mult %.2f  ATR %.0f  Stop %.2f  TP %.2f",g_mult,g_atrLen,g_stopMult,g_tpMult),W);
   DashLabel("L4",x,y+dy*row++,"Risk   : "+(riskOk?"ACTIVE":"PAUSED"),riskOk?G:R);
   DashLabel("L5",x,y+dy*row++,StringFormat("Day PnL: %.0f$  Trades %d/%d",g_sessionPnL,g_tradesSession,InpMaxTradesPerSession),g_sessionPnL>=0?G:R);
   DashLabel("L6",x,y+dy*row++,StringFormat("Streak : %dL   Cooldown: %s",g_consecLosses,barsLeft>0?IntegerToString((int)barsLeft)+" b":"--"),g_consecLosses>0?R:G);
   DashLabel("L7",x,y+dy*row++,StringFormat("EqStop : %s  DayStartEq %.0f",g_dailyStopHit?"HIT":"ok",g_dayStartEquity),g_dailyStopHit?R:GR);
   DashLabel("H0",x,y+dy*row++,"-- SIGNAL STATS (5-bar exits) --",GR);
   DashLabel("S0",x,y+dy*row++,StringFormat("Long   : %s  (%d/%d)",g_sig_tot_L>0?DoubleToString(wrL*100,1)+"%":"N/A",g_sig_win_L,g_sig_tot_L),wrL>=0.5&&g_sig_tot_L>0?G:(g_sig_tot_L==0?GR:R));
   DashLabel("S1",x,y+dy*row++,StringFormat("Short  : %s  (%d/%d)",g_sig_tot_S>0?DoubleToString(wrS*100,1)+"%":"N/A",g_sig_win_S,g_sig_tot_S),wrS>=0.5&&g_sig_tot_S>0?G:(g_sig_tot_S==0?GR:R));
   DashLabel("S2",x,y+dy*row++,StringFormat("Sharpe : L %.2f  S %.2f (sim)",g_sharpe_L,g_sharpe_S),W);
   DashLabel("S3",x,y+dy*row++,StringFormat("PF sim : L %s  S %s",
             (g_gl_L>0&&g_gp_L>0)?DoubleToString(g_gp_L/g_gl_L,2):"N/A",
             (g_gl_S>0&&g_gp_S>0)?DoubleToString(g_gp_S/g_gl_S,2):"N/A"),W);
   DashLabel("S4",x,y+dy*row++,StringFormat("Session: %s  Spread cap %d",InpUseSessionFilter?StringFormat("%02d-%02d",InpSessionStartHour,InpSessionEndHour):"OFF",InpMaxSpreadPoints),GR);

   ChartRedraw(0);
}

//==========================================================================
// PROCESS ONE CLOSED BAR — the whole brain runs here, once per bar.
// shift = 1 for live; larger during warm-up replay.
//==========================================================================
void ProcessBar(int shift,bool live)
{
   // ---- fetch bar window (series: [0] = the closed bar at `shift`) ----
   MqlRates r[];
   ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,_Period,shift,8,r)<8)return;

   double a1[],rs1[],ax1[],a14w[];
   ArraySetAsSeries(a1,true);ArraySetAsSeries(rs1,true);
   ArraySetAsSeries(ax1,true);ArraySetAsSeries(a14w,true);
   if(CopyBuffer(h_atr,0,shift,1,a1)<1)return;
   if(CopyBuffer(h_rsi,0,shift,1,rs1)<1)return;
   int nAdx=(h_adx!=INVALID_HANDLE)?CopyBuffer(h_adx,0,shift,1,ax1):0;
   int n14=CopyBuffer(h_atr14,0,shift,100,a14w);

   double cATR =(a1[0]!=EMPTY_VALUE&&a1[0]>0)?a1[0]:g_lastATR;
   double cRSI =(rs1[0]!=EMPTY_VALUE)?rs1[0]:50.0;
   double cADX =(nAdx>0&&ax1[0]!=EMPTY_VALUE)?ax1[0]:25.0;
   double cATR14=cATR;
   if(n14>0&&a14w[0]!=EMPTY_VALUE&&a14w[0]>0)cATR14=a14w[0];

   double cl[];
   ArraySetAsSeries(cl,true);
   int nCl=CopyClose(_Symbol,_Period,shift,80,cl);

   g_barNum++;
   long barNum=g_barNum;

   double h_=r[0].high,l_=r[0].low,c_=r[0].close,o_=r[0].open;
   double c1=r[1].close;
   double tv=(double)r[0].tick_volume;
   datetime bt=r[0].time;

   CheckSessionReset(bt);

   double tr=MathMax(h_-l_,MathMax(MathAbs(h_-c1),MathAbs(l_-c1)));
   double src=SrcPrice(o_,h_,l_,c_);
   g_lastATR=cATR;

   // ---- signal SuperTrend (adaptive params) ----
   int    sLen=(int)Clamp(g_atrLen,5,100);
   double sMult=Clamp(g_mult,0.5,5.0);
   ST_Step(src,sMult,sLen,InpUseATR,c1,c_,tr,g_sig_up,g_sig_dn,g_sig_trend,g_sig_rma);

   // ---- HTF SuperTrend ----
   UpdateHTF(bt);

   // ---- regime (every 7 bars) ----
   if(barNum-g_lastRegBar>=7&&nCl>=79)
   {
      g_regime=DetectRegime(cl,0,nCl,cADX);
      g_lastRegBar=barNum;
   }

   // ---- volatility normalization ----
   double volNorm=0.5;
   if(n14>1)
   {
      double aAvg=0;int ac=0;
      for(int vi=0;vi<n14;vi++){if(a14w[vi]!=EMPTY_VALUE&&a14w[vi]>0){aAvg+=a14w[vi];ac++;}}
      if(ac>0){aAvg/=ac;volNorm=aAvg>0?Clamp((cATR14/aAvg)/InpVolMaxRatio,0,1):0.5;}
   }
   g_volNorm=volNorm;

   // ---- rolling queues: exactly ONE push per closed bar ----
   QPush(g_highs,h_,500);QPush(g_lows,l_,500);
   QPush(g_rsis,cRSI,500);
   if(tv>0)QPush(g_vols,tv,500);

   // ---- pressure sensor (EWM flows) ----
   if(InpEnableTickPressure)
   {
      g_bullFlow*=0.85;g_bearFlow*=0.85;
      if(c_>c1)g_bullFlow+=tv;else if(c_<c1)g_bearFlow+=tv;
      double tf=g_bullFlow+g_bearFlow;
      g_pressure=tf>0?(g_bullFlow-g_bearFlow)/tf:0;
      QPush(g_pressureLog,g_pressure,20);
   }

   //=== BACKGROUND TEST MATRIX + OPTIMIZER =================================
   if(InpEnableAdaptive&&InpUseFaintCycle&&barNum>5)
   {
      double loHold=l_,hiHold=h_;
      for(int hb=1;hb<5;hb++)
      {if(r[hb].low<loHold)loHold=r[hb].low;if(r[hb].high>hiHold)hiHold=r[hb].high;}

      double lUsd,lAtr,lMae,sUsd,sAtr,sMae;
      bool lClosed=CloseMatured(g_probesL,+1,loHold,hiHold,c_,barNum,lUsd,lAtr,lMae);
      bool sClosed=CloseMatured(g_probesS,-1,loHold,hiHold,c_,barNum,sUsd,sAtr,sMae);

      if(lClosed&&lUsd!=EMPTY_VALUE)
      {
         g_tot_L++;if(lUsd>0){g_win_L++;g_consecLoss_L=0;}else g_consecLoss_L++;
         if(lUsd>=0)g_gp_L+=lUsd;else g_gl_L+=(-lUsd);
         double cap=Clamp(lUsd,-InpPnLCapUSD,InpPnLCapUSD);
         QPush(g_rollUSD_L,cap,InpRollN);QPush(g_rollATR_L,lAtr,InpRollN);
         if(InpUseSTM)DecayPush(lAtr,lMae,g_regime,volNorm,+1);
         if(InpEnableBinLearning)
         {
            double gm,gl2,gs,gt,gb,gc;
            GridRecommend(Bucket(g_regime,InpMapGridX),Bucket(volNorm,InpMapGridY),gm,gl2,gs,gt,gb,gc);
            BatchSample bs;bs.atr_ret=lAtr;bs.mae_atr=lMae;bs.pnl_usd=lUsd;bs.conf=gc;
            QPushB(g_batchL,bs,200);
         }
      }
      if(sClosed&&sUsd!=EMPTY_VALUE)
      {
         g_tot_S++;if(sUsd>0){g_win_S++;g_consecLoss_S=0;}else g_consecLoss_S++;
         if(sUsd>=0)g_gp_S+=sUsd;else g_gl_S+=(-sUsd);
         double cap=Clamp(sUsd,-InpPnLCapUSD,InpPnLCapUSD);
         QPush(g_rollUSD_S,cap,InpRollN);QPush(g_rollATR_S,sAtr,InpRollN);
         if(InpUseSTM)DecayPush(sAtr,sMae,g_regime,volNorm,-1);
         if(InpEnableBinLearning)
         {
            double gm,gl2,gs,gt,gb,gc;
            GridRecommend(Bucket(g_regime,InpMapGridX),Bucket(volNorm,InpMapGridY),gm,gl2,gs,gt,gb,gc);
            BatchSample bs;bs.atr_ret=sAtr;bs.mae_atr=sMae;bs.pnl_usd=sUsd;bs.conf=gc;
            QPushB(g_batchS,bs,200);
         }
      }

      if(InpUseSTM)
      {
         DecayStep();
         if(InpSTMConsolidateEvery>0&&barNum%InpSTMConsolidateEvery==0&&ArraySize(g_decay)>0&&InpUseCognitiveMap)
         {
            double dSD=DecayTailFeedback();
            int posIdx=-1,negIdx=-1;double posMag=-1,negMag=-1;
            for(int di=0;di<ArraySize(g_decay);di++)
            {
               double mag=MathAbs(g_decay[di].atr_ret)*g_decay[di].energy;
               if(g_decay[di].atr_ret>=0&&mag>posMag){posMag=mag;posIdx=di;}
               if(g_decay[di].atr_ret< 0&&mag>negMag){negMag=mag;negIdx=di;}
            }
            if(posIdx>=0)GridUpdate(Bucket(g_decay[posIdx].regime,InpMapGridX),Bucket(g_decay[posIdx].vol_norm,InpMapGridY),g_decay[posIdx].atr_ret,0,0,dSD,0,0);
            if(negIdx>=0)GridUpdate(Bucket(g_decay[negIdx].regime,InpMapGridX),Bucket(g_decay[negIdx].vol_norm,InpMapGridY),g_decay[negIdx].atr_ret,0,0,dSD,0,0);
         }
      }

      if(CountActive(g_probesL)<5)OpenProbe(g_probesL,+1,o_,cATR,barNum);
      if(CountActive(g_probesS)<5)OpenProbe(g_probesS,-1,o_,cATR,barNum);

      //=== OPTIMIZER ===
      int lc=ArraySize(g_rollATR_L),sc2=ArraySize(g_rollATR_S);
      if((lc>=5||sc2>=5)&&(g_lastParamBar<0||barNum-g_lastParamBar>=InpParamUpdateEvery))
      {
         double wrL=QWinRate(g_rollUSD_L),auL=QAvgFull(g_rollUSD_L);
         double wrS=QWinRate(g_rollUSD_S),auS=QAvgFull(g_rollUSD_S);
         double aaL=QAvgFull(g_rollATR_L),aaS=QAvgFull(g_rollATR_S);
         double soL=QSortino(g_rollATR_L),soS=QSortino(g_rollATR_S);
         UpdateSharpeSortino();
         double pfL=g_gl_L>0?g_gp_L/g_gl_L:(g_gp_L>0?9.99:0.0);
         double pfS=g_gl_S>0?g_gp_S/g_gl_S:(g_gp_S>0?9.99:0.0);
         double awL=g_win_L>0?g_gp_L/g_win_L:0;
         double alL=(g_tot_L-g_win_L)>0?g_gl_L/(g_tot_L-g_win_L):0;
         double awS=g_win_S>0?g_gp_S/g_win_S:0;
         double alS=(g_tot_S-g_win_S)>0?g_gl_S/(g_tot_S-g_win_S):0;

         double dML,dLL,dSL,dTL,dBL,dMS,dLS,dSS,dTS,dBS;
         LearnProposals(wrL,auL,aaL,soL,0,pfL,awL,alL,lc,g_mult,g_atrLen,g_sharpe_L,(int)g_consecLoss_L,dML,dLL,dSL,dTL,dBL);
         LearnProposals(wrS,auS,aaS,soS,0,pfS,awS,alS,sc2,g_mult,g_atrLen,g_sharpe_S,(int)g_consecLoss_S,dMS,dLS,dSS,dTS,dBS);

         double netM=(lc>0?dML:0)+(sc2>0?dMS:0);
         double netL2=(lc>0?dLL:0)+(sc2>0?dLS:0);
         double netS2=(lc>0?dSL:0)+(sc2>0?dSS:0);
         double netT=(lc>0?dTL:0)+(sc2>0?dTS:0);
         double netB=(lc>0?dBL:0)+(sc2>0?dBS:0);

         int ix=Bucket(g_regime,InpMapGridX),iy=Bucket(volNorm,InpMapGridY);
         double gm,gl3,gs,gt,gb,gc;
         GridRecommend(ix,iy,gm,gl3,gs,gt,gb,gc);
         double wg=Clamp(gc,0,InpMapWeightMax);

         double tMult_MG=InpMultiplier*(1+gm)*wg+g_mult*(1+netM)*(1-wg);
         double tLen_MG =(double)InpATRPeriod+gl3*wg+(g_atrLen+netL2)*(1-wg);
         double tStop_MG=InpStopMult*(1+gs)*wg+g_stopMult*(1+netS2)*(1-wg);
         double tTP_MG  =InpTPMult*(1+gt)*wg+g_tpMult*(1+netT)*(1-wg);
         double tBrk_MG =InpBreakoutBuf*(1+gb)*wg+g_brkBuf*(1+netB)*(1-wg);

         int N_b,str_b;double Wmin_b,wb2,cM,cL2,cS2,cT2,cB2,dbM,dbL2,aE;
         MasterParams(InpDialK,N_b,str_b,Wmin_b,wb2,cM,cL2,cS2,cT2,cB2,dbM,dbL2,aE);
         if(InpEnableBinLearning)
         {
            double mu2;
            g_firedL=BatchFire(g_batchL,N_b,str_b,Wmin_b,cM,cL2,cS2,cT2,cB2,g_dMultBL,g_dLenBL,g_dStopBL,g_dTPBL,g_dBrkBL,mu2);g_muBL=mu2;
            g_firedS=BatchFire(g_batchS,N_b,str_b,Wmin_b,cM,cL2,cS2,cT2,cB2,g_dMultBS,g_dLenBS,g_dStopBS,g_dTPBS,g_dBrkBS,mu2);g_muBS=mu2;
         }
         double wb3=(g_firedL||g_firedS)?wb2:0.0;
         double wL3=(g_firedL&&(!g_firedS||MathAbs(g_muBL)>=MathAbs(g_muBS)))?0.7:(g_firedL&&g_firedS?0.3:(g_firedL?1.0:0.0));
         double wS3=(g_firedS&&(!g_firedL||MathAbs(g_muBS)> MathAbs(g_muBL)))?0.7:(g_firedL&&g_firedS?0.3:(g_firedS?1.0:0.0));
         double tMult_b=g_mult*(1+wL3*g_dMultBL+wS3*g_dMultBS);
         double tLen_b =g_atrLen+(wL3*g_dLenBL+wS3*g_dLenBS);
         double tStop_b=g_stopMult*(1+wL3*g_dStopBL+wS3*g_dStopBS);
         double tTP_b  =g_tpMult*(1+wL3*g_dTPBL+wS3*g_dTPBS);
         double tBrk_b =g_brkBuf*(1+wL3*g_dBrkBL+wS3*g_dBrkBS);

         double tMf=tMult_MG*(1-wb3)+tMult_b*wb3;
         double tLf=tLen_MG *(1-wb3)+tLen_b *wb3;
         double tSf=tStop_MG*(1-wb3)+tStop_b*wb3;
         double tTf=tTP_MG  *(1-wb3)+tTP_b  *wb3;
         double tBf=tBrk_MG *(1-wb3)+tBrk_b *wb3;

         if(MathAbs(tMf-g_mult)>dbM||MathAbs(tLf-g_atrLen)>dbL2)
         {
            g_mult     +=aE*(Clamp(Quantize(tMf,InpQuantStepMult),0.5,5.0)-g_mult);
            g_atrLen   +=aE*(Clamp(MathRound(tLf),5,100)-g_atrLen);
            g_stopMult +=aE*(Clamp(Quantize(tSf,InpQuantStepStop),0.3,3.0)-g_stopMult);
            g_tpMult   +=aE*(Clamp(Quantize(tTf,InpQuantStepTP),0.5,5.0)-g_tpMult);
            g_brkBuf   +=aE*(Clamp(Quantize(tBf,InpQuantStepBrk),0.0,3.0)-g_brkBuf);
            g_lastParamBar=barNum;
         }

         if(InpRevertEvery>0&&barNum%InpRevertEvery==0)
         {
            g_mult   +=InpRevertStep*(InpMultiplier-g_mult);
            g_atrLen +=InpRevertStep*((double)InpATRPeriod-g_atrLen);
         }

         if(InpUseCognitiveMap)
         {
            if(lClosed&&lUsd!=EMPTY_VALUE)GridUpdate(ix,iy,lAtr,netM,netL2,netS2,netT,netB);
            if(sClosed&&sUsd!=EMPTY_VALUE)GridUpdate(ix,iy,sAtr,netM,netL2,netS2,netT,netB);
         }
      }
   }

   //=== SETTLE PENDING SIGNALS (real 5-bar-exit stats) =====================
   for(int p=ArraySize(g_pending)-1;p>=0;p--)
   {
      if(barNum-g_pending[p].bar<5)continue;
      if(g_pending[p].dir>0){g_sig_tot_L++;if(c_>g_pending[p].entry)g_sig_win_L++;}
      else                  {g_sig_tot_S++;if(c_<g_pending[p].entry)g_sig_win_S++;}
      for(int q=p;q<ArraySize(g_pending)-1;q++)g_pending[q]=g_pending[q+1];
      ArrayResize(g_pending,ArraySize(g_pending)-1);
   }

   //=== SIGNAL GENERATION ===================================================
   int szH=ArraySize(g_highs);
   int sens=(int)Clamp(g_sensitivity,2,MathMin(100.0,(double)(szH-1)));
   int lb  =MathMax(1,(int)(g_sensitivity/10.0));

   if(szH<sens+lb){g_sig_trend_prev=g_sig_trend;return;}

   double hiNow=QMax(g_highs,sens);
   double hiPrev=QMax(g_highs,sens+lb);
   double loNow=QMin(g_lows,sens);
   double loPrev=QMin(g_lows,sens+lb);

   bool isNewHigh=(hiNow!=hiPrev&&hiNow>hiPrev);
   bool isNewLow =(loNow!=loPrev&&loNow<loPrev);

   if(InpMajorLevelsOnly)
   {
      double atrLvl=cATR*InpMajorLevelDepth;
      isNewHigh=isNewHigh&&(h_-QMin(g_lows,sens))>atrLvl;
      isNewLow =isNewLow &&(QMax(g_highs,sens)-l_)>atrLvl;
   }

   bool rsiCold=true,rsiHot=true;
   if(InpEnableRSI)
   {
      int szR=ArraySize(g_rsis);
      bool fc=false,fh=false;
      for(int ri=szR-1;ri>=MathMax(0,szR-InpRSILookbackBot);ri--)
         if(g_rsis[ri]<InpRSIBot){fc=true;break;}
      for(int ri=szR-1;ri>=MathMax(0,szR-InpRSILookbackTop);ri--)
         if(g_rsis[ri]>InpRSITop){fh=true;break;}
      rsiCold=fc;rsiHot=fh;
   }

   bool volSurge=true;
   if(InpRequireVolSpike)
   {
      int szV=ArraySize(g_vols);
      double vAvg=szV>0?QAvg(g_vols,InpVolLookback):1;
      volSurge=tv>InpVolMultiplier*vAvg;
   }

   bool buyF =rsiCold&&volSurge;
   bool sellF=rsiHot &&volSurge;
   bool canSig=(barNum-g_lastSigBar)>=InpMinBarsBetweenSigs && CanTrade(barNum);

   // effective mode: Auto lets the regime pick
   ENUM_SIGNAL_MODE mode=InpSignalMode;
   if(mode==SignalAuto)
      mode=(g_regime>0.65)?SignalBreakout:SignalReversal;

   bool doBuy=false,doSell=false;

   if(mode==SignalReversal&&canSig)
   {
      g_topFlagPrev=g_topFlag;
      g_botFlagPrev=g_botFlag;
      if(g_sig_trend==-1)                 g_topFlag=0;
      else if(isNewHigh&&g_sig_trend==1)  g_topFlag=1;
      if(g_sig_trend==1)                  g_botFlag=0;
      else if(isNewLow&&g_sig_trend==-1)  g_botFlag=1;

      bool rSell=(g_topFlagPrev==1&&g_topFlag==0)||(!InpRequireNewExtreme&&g_sig_trend_prev==1&&g_sig_trend==-1);
      bool rBuy =(g_botFlagPrev==1&&g_botFlag==0)||(!InpRequireNewExtreme&&g_sig_trend_prev==-1&&g_sig_trend==1);

      if(rSell&&sellF)doSell=true;
      else if(rBuy&&buyF)doBuy=true;
   }
   if(mode==SignalBreakout&&canSig)
   {
      if(isNewHigh&&g_sig_trend==1 &&sellF)doSell=true;
      if(isNewLow &&g_sig_trend==-1&&buyF) doBuy =true;
   }

   //=== A+ GATES ============================================================
   string vetoReason="";
   if(doBuy||doSell)
   {
      int dir=doBuy?1:-1;

      // 1) HTF alignment
      if(!HTFAllows(dir))vetoReason="HTF";

      // 2) Session window
      if(vetoReason==""&&!InSession(bt))vetoReason="session";
      if(vetoReason==""&&FridayFlattenTime(bt))vetoReason="friday";

      // 3) Overextension: a fresh flip sits ~mult*RMA from the new band by
      //    construction, so only the EXCESS beyond that distance is a chase
      if(vetoReason==""&&cATR>0)
      {
         double structural=Clamp(g_mult,0.5,5.0)*g_sig_rma;
         double dist=doBuy?(c_-g_sig_up):(g_sig_dn-c_);
         double excess=(dist-structural)/cATR;
         if(excess>InpMaxStretchATR)vetoReason="stretch";
      }

      // 4) Candle body confirmation
      if(vetoReason=="")
      {
         double range=h_-l_;
         double body=MathAbs(c_-o_);
         bool bodyOk=range>0&&body/range>=InpMinBodyPct&&
                     ((doBuy&&c_>o_)||(doSell&&c_<o_));
         if(!bodyOk)vetoReason="body";
      }

      // 5) Regime-grid expectancy veto
      if(vetoReason==""&&InpUseGridVeto)
      {
         double gExp,gCf;
         GridExpectancy(Bucket(g_regime,InpMapGridX),Bucket(volNorm,InpMapGridY),gExp,gCf);
         if(gCf>=InpGridVetoMinConf&&gExp<InpGridVetoThr)vetoReason="grid";
      }

      if(vetoReason!=""){doBuy=false;doSell=false;
         if(live)PrintFormat("ML ST EA: %s signal vetoed (%s)",dir>0?"BUY":"SELL",vetoReason);}
   }

   //=== CONFIDENCE + GRADE ==================================================
   double confScore=0.0;
   string grade="";
   if(doBuy||doSell)
   {
      int ix2=Bucket(g_regime,InpMapGridX),iy2=Bucket(volNorm,InpMapGridY);
      double gm2,gl2x,gs2,gt2,gb2,gc2;
      GridRecommend(ix2,iy2,gm2,gl2x,gs2,gt2,gb2,gc2);
      confScore=gc2;
      if(doBuy  && cRSI<InpRSIBot+20) confScore=MathMin(1.0,confScore+0.2);
      if(doSell && cRSI>InpRSITop-20) confScore=MathMin(1.0,confScore+0.2);
      if(volSurge && InpRequireVolSpike) confScore=MathMin(1.0,confScore+0.1);
      if(doBuy  && g_sig_trend==1 && g_regime>0.5) confScore=MathMin(1.0,confScore+0.1);
      if(doSell && g_sig_trend==-1&& g_regime>0.5) confScore=MathMin(1.0,confScore+0.1);
      // pressure agreement boost
      double pb=ArraySize(g_pressureLog)>=5?QAvg(g_pressureLog,5):0;
      if(doBuy &&pb> 0.15)confScore=MathMin(1.0,confScore+0.1);
      if(doSell&&pb<-0.15)confScore=MathMin(1.0,confScore+0.1);
      // HTF agreement boost when the filter itself is disabled
      if(!InpUseHTFFilter)
      {
         int dir=doBuy?1:-1;
         if((dir>0&&g_htf_trend==1)||(dir<0&&g_htf_trend==-1))
            confScore=MathMin(1.0,confScore+0.1);
      }

      if(confScore>=InpGradeAConf)      grade="A";
      else if(confScore>=InpMinConfidence)grade="B";
      else { doBuy=false;doSell=false;
         if(live)PrintFormat("ML ST EA: signal below min confidence (%.0f%%)",confScore*100.0); }
   }

   //=== RECORD + EXECUTE ====================================================
   if(doBuy||doSell)
   {
      int dir=doBuy?1:-1;
      g_lastSigBar=barNum;
      g_lastConf=confScore;
      g_lastSignalStr=StringFormat("%s %s %.0f%%",dir>0?"BUY":"SELL",grade,confScore*100.0);

      // stats settlement queue (all graded signals, traded or not)
      int psz=ArraySize(g_pending);
      ArrayResize(g_pending,psz+1);
      g_pending[psz].dir=dir;g_pending[psz].entry=c_;g_pending[psz].bar=barNum;

      bool gradeOk=(grade=="A")||(grade=="B"&&InpTradeGrade==GradeAB);
      if(live&&gradeOk)
         TryOpen(dir,confScore,grade);
      else if(live)
         PrintFormat("ML ST EA: %s signal grade %s logged, not traded (grade filter)",
                     dir>0?"BUY":"SELL",grade);
   }

   g_sig_trend_prev=g_sig_trend;

   //=== LIVE POSITION MANAGEMENT ===========================================
   if(live)
   {
      // daily equity stop
      if(!g_dailyStopHit&&!DailyEquityOk())
      {
         g_dailyStopHit=true;
         SendTradeAlert("DAILY EQUITY STOP HIT — trading paused until next session");
         if(InpFlattenOnDailyStop)CloseOurPositions("daily equity stop");
      }
      if(FridayFlattenTime(TimeCurrent()))CloseOurPositions("friday flatten");
      ManagePositions();
      UpdateDashboard();
   }
}

//==========================================================================
// WARM-UP — replay history once so adaptive state matches a long-running EA
//==========================================================================
void RunWarmup()
{
   int total=Bars(_Symbol,_Period);
   int wb=MathMin(InpWarmupBars,total-120);
   if(wb<50){Print("ML ST EA: not enough history for warm-up (",total," bars)");return;}
   Print("ML ST EA: warming up over ",wb," bars...");
   for(int shift=wb;shift>=2;shift--)
      ProcessBar(shift,false);
   PrintFormat("ML ST EA: warm-up done. mult=%.2f atrLen=%.0f stop=%.2f tp=%.2f regime=%.2f",
               g_mult,g_atrLen,g_stopMult,g_tpMult,g_regime);
}

//==========================================================================
// OnInit / OnDeinit / OnTick / OnTradeTransaction
//==========================================================================
int OnInit()
{
   h_atr  =iATR(_Symbol,_Period,InpATRPeriod);
   h_atr14=iATR(_Symbol,_Period,14);
   h_rsi  =iRSI(_Symbol,_Period,InpRSILen,PRICE_CLOSE);
   h_adx  =iADX(_Symbol,_Period,14);
   if(h_atr==INVALID_HANDLE||h_rsi==INVALID_HANDLE||h_atr14==INVALID_HANDLE)
   {Alert("ML ST EA: Handle creation failed! Check symbol/period.");return INIT_FAILED;}

   g_mult=InpMultiplier; g_atrLen=InpATRPeriod;
   g_stopMult=InpStopMult; g_tpMult=InpTPMult;
   g_brkBuf=InpBreakoutBuf; g_sensitivity=InpSensitivity;

   int cells=InpMapGridX*InpMapGridY;
   ArrayResize(g_grid,cells);
   for(int i=0;i<cells;i++)
   {
      g_grid[i].mean_atr_ret=0;g_grid[i].down_ewm=0;g_grid[i].count=0;
      g_grid[i].conf=0;g_grid[i].d_mult=0;g_grid[i].d_len=0;
      g_grid[i].d_stop=0;g_grid[i].d_tp=0;g_grid[i].d_brk=0;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);

   if(InpUseHTFFilter&&PeriodSeconds(InpHTF)<=PeriodSeconds(_Period))
      Print("ML ST EA: WARNING — HTF must be higher than chart TF; HTF filter disabled.");

   g_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_warmupDone=false;
   g_lastBarTime=0;

   Print("ML ST EA v11.00 initialized. Magic=",InpMagic,
         " Risk=",DoubleToString(InpRiskPct,2),"% Grade=",
         InpTradeGrade==GradeAOnly?"A only":"A+B");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(h_atr  !=INVALID_HANDLE)IndicatorRelease(h_atr);
   if(h_atr14!=INVALID_HANDLE)IndicatorRelease(h_atr14);
   if(h_rsi  !=INVALID_HANDLE)IndicatorRelease(h_rsi);
   if(h_adx  !=INVALID_HANDLE)IndicatorRelease(h_adx);
   DashDeleteAll();
}

void OnTick()
{
   // lazy warm-up: wait until indicator handles have data
   if(!g_warmupDone)
   {
      if(BarsCalculated(h_atr)<InpATRPeriod*3||BarsCalculated(h_rsi)<InpRSILen*2)return;
      RunWarmup();
      g_warmupDone=true;
      g_lastBarTime=iTime(_Symbol,_Period,0);
      UpdateDashboard();
      return;
   }

   // once per NEW bar — everything stateful lives in ProcessBar
   datetime t0=iTime(_Symbol,_Period,0);
   if(t0!=g_lastBarTime)
   {
      g_lastBarTime=t0;
      ProcessBar(1,true);
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD)return;
   if(!HistoryDealSelect(trans.deal))return;
   if(HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=InpMagic)return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol)return;
   ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT&&entry!=DEAL_ENTRY_OUT_BY)return;

   double pnl=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)
             +HistoryDealGetDouble(trans.deal,DEAL_SWAP)
             +HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
   ApplyRiskGuard(pnl,g_barNum);
   PrintFormat("ML ST EA: trade closed pnl=%.2f  dayPnL=%.2f  streak=%dL",
               pnl,g_sessionPnL,g_consecLosses);
   UpdateDashboard();
}
//+------------------------------------------------------------------+
