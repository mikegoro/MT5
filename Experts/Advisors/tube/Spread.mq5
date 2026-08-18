//+------------------------------------------------------------------+
//|                                                  SpreadMonitor.mq5 |
//|                                                    Spread Logger  |
//|                                          Logs spreads to CSV file |
//+------------------------------------------------------------------+
#property copyright "Spread Monitor"
#property version   "1.00"
#property strict

//--- Input enums
enum enumHour
  {
   Inactive=0, _0100=1, _0200=2, _0300=3, _0400=4, _0500=5, _0600=6, _0700=7,
   _0800=8, _0900=9, _1000=10, _1100=11, _1200=12, _1300=13, _1400=14, _1500=15,
   _1600=16, _1700=17, _1800=18, _1900=19, _2000=20, _2100=21, _2200=22, _2300=23
  };

enum ENUM_LOG_MODE
  {
   LOG_ALL = 0,           // Log all times
   LOG_WINDOW_ONLY = 1    // Log only during specified hours
  };

//--- Input parameters
input group "=== Time Settings ==="
input ENUM_LOG_MODE InpLogMode = LOG_ALL;      // Logging mode
input enumHour     InpStartHour = _0300;       // Start hour (Inactive = midnight)
input enumHour     InpEndHour   = _2300;       // End hour (Inactive = midnight)

input group "=== File Settings ==="
input string   InpFolderName     = "SpreadLogs\\";  // Folder name (inside Files folder)
input bool     InpDailyFile      = true;            // Create new file daily
input bool     InpIncludeHeaders = true;            // Include headers in CSV

input group "=== Logging Settings ==="
input int      InpLogFrequency   = 5;               // Log every N seconds (0 = every tick)
input int      InpTickFrequency  = 10;              // Log every N ticks (if seconds=0)
input int      InpSpreadPeriod   = 30;              // Spread averaging period
input double   InpSpreadThreshold = 0;              // Alert when spread exceeds (points, 0=off)

input group "=== Display Settings ==="
input bool     InpShowChart      = true;            // Show info on chart

//--- Dashboard constants
#define DASH_PREFIX   "SPRD_"
#define CELL_W        140
#define CELL_H        22
#define BORDER_PX     1
#define DASH_X        10
#define DASH_Y        20
#define CLR_BORDER    C'30,30,30'
#define CLR_SEP       C'60,60,60'

//--- Global variables
string         g_symbol;
int            g_digits;
double         g_point;
int            g_spreadPeriod;
double         g_spreadHistory[];
double         g_currentSpread = 0;
double         g_averageSpread = 0;
int            g_tickCounter = 0;
datetime       g_lastLogTime = 0;
datetime       g_lastFileCheck = 0;
string         g_currentFileName = "";
int            g_fileHandle = -1;
int            g_writeCounter = 0;
string         g_buffer = "";
bool           g_isNewDay = true;
int            g_lastDay = 0;
double         g_maxSpread = 0;
double         g_minSpread = DBL_MAX;
int            g_spikeCount = 0;
int            g_outsideWindowCount = 0;
datetime       g_lastLogAttempt = 0;
bool           g_firstUpdate = true;
datetime       g_startTime = 0;
double         g_spreadSum = 0;
int            g_spreadCount = 0;
double         g_runningAvg = 0;
bool           g_dashboardVisible = true;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_symbol = _Symbol;
   g_digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   g_point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   g_spreadPeriod = InpSpreadPeriod;
   g_startTime = TimeCurrent();
   
   // Initialize spread history
   ArrayResize(g_spreadHistory, g_spreadPeriod);
   ArrayInitialize(g_spreadHistory, 0);
   
   // Get initial spread
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   g_currentSpread = NormalizeDouble(ask - bid, g_digits);
   
   // Initialize history with current spread
   for(int i = 0; i < g_spreadPeriod; i++)
      g_spreadHistory[i] = g_currentSpread;
   g_averageSpread = g_currentSpread;
   
   // Update min/max
   g_minSpread = g_currentSpread;
   g_maxSpread = g_currentSpread;
   g_runningAvg = g_currentSpread;
   g_spreadSum = g_currentSpread;
   g_spreadCount = 1;
   
   // Create folder if it doesn't exist
   if(!FolderCreate(InpFolderName))
     {
      int error = GetLastError();
      if(error != 5019) // 5019 = folder already exists
         Print("Folder creation error: ", error);
     }
   
   // Open first file
   if(!OpenLogFile())
      return(INIT_FAILED);
   
   // Initialize monitoring
   g_lastLogTime = TimeCurrent();
   g_lastDay = getDayOfYear(TimeCurrent());
   
   // Set timer for periodic flush (every minute)
   EventSetTimer(60);
   
   // Hide test indicators
   TesterHideIndicators(true);
   
   // Display startup info
   string timeInfo = (InpLogMode == LOG_ALL) ? "ALL TIMES" : 
                     StringFormat("%02d:00 - %02d:00", (int)InpStartHour, (int)InpEndHour);
   Print("Spread Monitor started for ", g_symbol);
   Print("Logging mode: ", (InpLogMode == LOG_ALL ? "All times" : "Time window only"));
   Print("Active hours: ", timeInfo);
   Print("Logging every ", (InpLogFrequency > 0 ? (string)InpLogFrequency + " seconds" : (string)InpTickFrequency + " ticks"));
   Print("Spread period: ", g_spreadPeriod);
   
   // Force initial dashboard display even before first tick
   if(InpShowChart)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      bool inWindow = IsTradingHour(dt.hour);
      DrawDashboard(TimeCurrent(), inWindow);
     }
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // Flush and close file
   if(g_fileHandle != -1)
     {
      if(StringLen(g_buffer) > 0)
         FileWriteString(g_fileHandle, g_buffer);
      FileClose(g_fileHandle);
      g_fileHandle = -1;
     }
   
   // Delete dashboard objects
   DashDeleteAll();
   
   // Show final stats
   string stats = "\n═══════════════════════════════════════════════════════════\n";
   stats += "  SPREAD MONITOR SUMMARY\n";
   stats += "═══════════════════════════════════════════════════════════\n";
   stats += "  Symbol          : " + g_symbol + "\n";
   stats += "  Running Time    : " + TimeToString(TimeCurrent() - g_startTime, TIME_SECONDS) + "\n";
   stats += "  Min Spread      : " + DoubleToString(g_minSpread / g_point, 1) + " points\n";
   stats += "  Max Spread      : " + DoubleToString(g_maxSpread / g_point, 1) + " points\n";
   stats += "  Avg Spread      : " + DoubleToString((g_minSpread + g_maxSpread) / 2 / g_point, 1) + " points (approx)\n";
   stats += "  Spikes Detected : " + (string)g_spikeCount + "\n";
   stats += "  Records Logged  : " + (string)g_writeCounter + "\n";
   stats += "═══════════════════════════════════════════════════════════";
   Print(stats);
   
   Comment("");
   EventKillTimer();
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   g_tickCounter++;
   
   //--- Get current spread
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   g_currentSpread = NormalizeDouble(ask - bid, g_digits);
   
   //--- Update running average
   g_spreadSum += g_currentSpread;
   g_spreadCount++;
   g_runningAvg = g_spreadSum / g_spreadCount;
   
   //--- Update spread history
   UpdateSpreadHistory(g_currentSpread);
   g_averageSpread = CalculateAverageSpread();
   
   //--- Check for new day (for daily file rotation)
   datetime currentTime = TimeCurrent();
   int currentDay = getDayOfYear(currentTime);
   if(currentDay != g_lastDay)
     {
      g_lastDay = currentDay;
      g_isNewDay = true;
      
      // Close current file and open new one if daily rotation is enabled
      if(InpDailyFile)
        {
         if(g_fileHandle != -1)
           {
            if(StringLen(g_buffer) > 0)
               FileWriteString(g_fileHandle, g_buffer);
            FileClose(g_fileHandle);
            g_fileHandle = -1;
            g_buffer = "";
           }
         OpenLogFile();
        }
     }
   
   //--- Get current hour
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   int currentHour = dt.hour;
   
   //--- Check if we should log
   bool shouldLog = false;
   
   // First check if we're in the trading window
   bool inWindow = IsTradingHour(currentHour);
   
   if(InpLogMode == LOG_ALL || inWindow)
     {
      // Check logging frequency
      if(InpLogFrequency > 0)
        {
         // Log every N seconds
         if(currentTime - g_lastLogTime >= InpLogFrequency)
           {
            shouldLog = true;
            g_lastLogTime = currentTime;
           }
        }
      else
        {
         // Log every N ticks
         if(g_tickCounter % InpTickFrequency == 0)
            shouldLog = true;
        }
     }
   else
     {
      // Not in trading window - just count and skip logging
      if(g_tickCounter % 100 == 0) // Count only occasionally to avoid spam
         g_outsideWindowCount++;
     }
   
   //--- Log data
   if(shouldLog)
     {
      LogSpreadData(currentTime, ask, bid, inWindow);
      g_writeCounter++;
      
      // Check for spread threshold
      if(InpSpreadThreshold > 0)
        {
         double spreadPoints = g_currentSpread / g_point;
         if(spreadPoints > InpSpreadThreshold)
           {
            g_spikeCount++;
            Print("⚠ SPREAD SPIKE! ", DoubleToString(spreadPoints, 1), " points at ", 
                  TimeToString(currentTime, TIME_DATE|TIME_SECONDS));
           }
        }
      
      // Update min/max
      if(g_currentSpread < g_minSpread)
         g_minSpread = g_currentSpread;
      if(g_currentSpread > g_maxSpread)
         g_maxSpread = g_currentSpread;
     }
   
   //--- Show info on chart
   if(InpShowChart && g_dashboardVisible)
      DrawDashboard(currentTime, inWindow);
  }

//+------------------------------------------------------------------+
//| Timer function (for periodic flush)                             |
//+------------------------------------------------------------------+
void OnTimer()
  {
   // Flush buffer every minute
   if(g_fileHandle != -1 && StringLen(g_buffer) > 0)
     {
      FileWriteString(g_fileHandle, g_buffer);
      g_buffer = "";
     }
   
   // Update dashboard every minute even if market is closed
   if(InpShowChart && g_dashboardVisible)
     {
      datetime currentTime = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(currentTime, dt);
      bool inWindow = IsTradingHour(dt.hour);
      
      // Update spread values
      double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
      g_currentSpread = NormalizeDouble(ask - bid, g_digits);
      UpdateSpreadHistory(g_currentSpread);
      g_averageSpread = CalculateAverageSpread();
      
      // Update min/max
      if(g_currentSpread < g_minSpread && g_currentSpread > 0)
         g_minSpread = g_currentSpread;
      if(g_currentSpread > g_maxSpread)
         g_maxSpread = g_currentSpread;
      
      DrawDashboard(currentTime, inWindow);
     }
  }

//+------------------------------------------------------------------+
//| Chart event handler (for manual refresh)                        |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_KEYDOWN)
     {
      // Press 'R' to refresh/rotate log file
      if((int)lparam == 82) // 'R' key
        {
         Print("🔄 Manual refresh triggered");
         if(g_fileHandle != -1)
           {
            if(StringLen(g_buffer) > 0)
               FileWriteString(g_fileHandle, g_buffer);
            FileClose(g_fileHandle);
            g_fileHandle = -1;
            g_buffer = "";
           }
         OpenLogFile();
        }
      // Press 'D' to toggle dashboard
      if((int)lparam == 68) // 'D' key
        {
         g_dashboardVisible = !g_dashboardVisible;
         if(g_dashboardVisible)
           {
            Print("📊 Dashboard enabled");
            datetime currentTime = TimeCurrent();
            MqlDateTime dt;
            TimeToStruct(currentTime, dt);
            bool inWindow = IsTradingHour(dt.hour);
            DrawDashboard(currentTime, inWindow);
           }
         else
           {
            Print("📊 Dashboard disabled");
            DashDeleteAll();
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Update spread history (rolling window)                          |
//+------------------------------------------------------------------+
void UpdateSpreadHistory(double newSpread)
  {
   // Shift left
   for(int i = 0; i < g_spreadPeriod - 1; i++)
      g_spreadHistory[i] = g_spreadHistory[i + 1];
   // Add new at the end
   g_spreadHistory[g_spreadPeriod - 1] = newSpread;
  }

//+------------------------------------------------------------------+
//| Calculate average spread                                         |
//+------------------------------------------------------------------+
double CalculateAverageSpread()
  {
   double sum = 0;
   int count = 0;
   for(int i = 0; i < g_spreadPeriod; i++)
     {
      if(g_spreadHistory[i] > 0)
        {
         sum += g_spreadHistory[i];
         count++;
        }
     }
   if(count == 0)
      return g_currentSpread;
   return NormalizeDouble(sum / count, g_digits);
  }

//+------------------------------------------------------------------+
//| Log spread data to CSV file                                      |
//+------------------------------------------------------------------+
void LogSpreadData(datetime time, double ask, double bid, bool inWindow)
  {
   // Check if file is open
   if(g_fileHandle == -1)
     {
      if(!OpenLogFile())
         return;
     }
   
   // Format data
   string timeStr = TimeToString(time, TIME_DATE|TIME_SECONDS);
   string symbol = g_symbol;
   string spreadPoints = DoubleToString(g_currentSpread / g_point, 1);
   string spreadPips = DoubleToString(g_currentSpread / g_point / 10, 1);
   string avgSpreadPoints = DoubleToString(g_averageSpread / g_point, 1);
   string avgSpreadPips = DoubleToString(g_averageSpread / g_point / 10, 1);
   string askPrice = DoubleToString(ask, g_digits);
   string bidPrice = DoubleToString(bid, g_digits);
   string inWindowStr = inWindow ? "YES" : "NO";
   
   // Build CSV line
   string line = StringFormat("%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
                              timeStr,
                              symbol,
                              spreadPoints,
                              spreadPips,
                              avgSpreadPoints,
                              avgSpreadPips,
                              askPrice,
                              bidPrice,
                              IntegerToString(g_tickCounter),
                              inWindowStr);
   
   // Add to buffer
   g_buffer += line;
   
   // Flush buffer if it gets too large (every 100 records)
   if(g_writeCounter % 100 == 0)
     {
      FileWriteString(g_fileHandle, g_buffer);
      g_buffer = "";
     }
  }

//+------------------------------------------------------------------+
//| Open log file with proper naming                                 |
//+------------------------------------------------------------------+
bool OpenLogFile()
  {
   // Close existing file if open
   if(g_fileHandle != -1)
     {
      if(StringLen(g_buffer) > 0)
         FileWriteString(g_fileHandle, g_buffer);
      FileClose(g_fileHandle);
      g_fileHandle = -1;
      g_buffer = "";
     }
   
   // Build filename
   string fileName;
   if(InpDailyFile)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      string dateStr = StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day);
      fileName = StringFormat("%s%s_%s_%s.csv", InpFolderName, g_symbol, dateStr, "spread_log");
     }
   else
     {
      fileName = StringFormat("%s%s_%s.csv", InpFolderName, g_symbol, "spread_log");
     }
   
   g_currentFileName = fileName;
   
   // Check if file exists
   bool fileExists = FileIsExist(fileName);
   
   // Open file (append mode)
   g_fileHandle = FileOpen(fileName, FILE_WRITE|FILE_READ|FILE_CSV|FILE_ANSI, ",");
   
   if(g_fileHandle == -1)
     {
      Print("Error opening file: ", fileName, " Error: ", GetLastError());
      return false;
     }
   
   // Write headers if file is new or if headers are requested
   if(!fileExists && InpIncludeHeaders)
     {
      string headers = "DateTime,Symbol,Spread_Points,Spread_Pips,AvgSpread_Points,AvgSpread_Pips,Ask,Bid,TickCount,InWindow\n";
      FileWriteString(g_fileHandle, headers);
     }
   
   Print("📁 Log file opened: ", fileName);
   return true;
  }

//+------------------------------------------------------------------+
//| DASHBOARD FUNCTIONS                                              |
//+------------------------------------------------------------------+

//--- Delete all dashboard objects
void DashDeleteAll()
  {
   int total=ObjectsTotal(0,0,-1);
   for(int i=total-1;i>=0;i--)
     {
      string nm=ObjectName(0,i,0,-1);
      if(StringFind(nm,DASH_PREFIX)==0)
         ObjectDelete(0,nm);
     }
  }

//--- Draw one cell: background rect + text label
void DashCell_(int row,int col,string label,string val,color bgClr,color txtClr)
  {
   int slotX = DASH_X  + col*(CELL_W + BORDER_PX);
   int slotY = DASH_Y  + row*(CELL_H + BORDER_PX);
   int bx    = slotX + BORDER_PX;
   int by    = slotY + BORDER_PX;
   int bw    = CELL_W - BORDER_PX;
   int bh    = CELL_H - BORDER_PX;

   // Background rectangle
   string bgNm = DASH_PREFIX+"BG_"+IntegerToString(row)+"_"+IntegerToString(col);
   if(ObjectFind(0,bgNm)<0) 
      ObjectCreate(0,bgNm,OBJ_RECTANGLE_LABEL,0,0,0);
   
   ObjectSetInteger(0,bgNm,OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bgNm,OBJPROP_XDISTANCE, bx);
   ObjectSetInteger(0,bgNm,OBJPROP_YDISTANCE, by);
   ObjectSetInteger(0,bgNm,OBJPROP_XSIZE,     bw);
   ObjectSetInteger(0,bgNm,OBJPROP_YSIZE,     bh);
   ObjectSetInteger(0,bgNm,OBJPROP_BGCOLOR,   bgClr);
   ObjectSetInteger(0,bgNm,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bgNm,OBJPROP_COLOR,     CLR_BORDER);
   ObjectSetInteger(0,bgNm,OBJPROP_BACK,      false);
   ObjectSetInteger(0,bgNm,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,bgNm,OBJPROP_ZORDER,    0);

   // Text label
   string txt = (label!="") ? label+": "+val : val;
   string lbNm = DASH_PREFIX+"LB_"+IntegerToString(row)+"_"+IntegerToString(col);
   if(ObjectFind(0,lbNm)<0) 
      ObjectCreate(0,lbNm,OBJ_LABEL,0,0,0);
   
   ObjectSetInteger(0,lbNm,OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0,lbNm,OBJPROP_XDISTANCE, bx+5);
   ObjectSetInteger(0,lbNm,OBJPROP_YDISTANCE, by+3);
   ObjectSetString (0,lbNm,OBJPROP_TEXT,      txt);
   ObjectSetInteger(0,lbNm,OBJPROP_COLOR,     txtClr);
   ObjectSetInteger(0,lbNm,OBJPROP_FONTSIZE,  9);
   ObjectSetString (0,lbNm,OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0,lbNm,OBJPROP_BACK,      false);
   ObjectSetInteger(0,lbNm,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,lbNm,OBJPROP_ZORDER,    1);
  }

//--- Draw a full-width horizontal separator line
void DashSepLine(int afterRow)
  {
   int totalW = 3*(CELL_W+BORDER_PX)+BORDER_PX;
   int y      = DASH_Y + (afterRow+1)*(CELL_H+BORDER_PX);

   string nm = DASH_PREFIX+"SEP_"+IntegerToString(afterRow);
   if(ObjectFind(0,nm)<0) 
      ObjectCreate(0,nm,OBJ_RECTANGLE_LABEL,0,0,0);
   
   ObjectSetInteger(0,nm,OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE, DASH_X);
   ObjectSetInteger(0,nm,OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0,nm,OBJPROP_XSIZE,     totalW);
   ObjectSetInteger(0,nm,OBJPROP_YSIZE,     2);
   ObjectSetInteger(0,nm,OBJPROP_BGCOLOR,   CLR_SEP);
   ObjectSetInteger(0,nm,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,     CLR_SEP);
   ObjectSetInteger(0,nm,OBJPROP_BACK,      false);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,nm,OBJPROP_ZORDER,    2);
  }

//--- Main dashboard drawing function
void DrawDashboard(datetime currentTime, bool inWindow)
  {
   if(!InpShowChart){ DashDeleteAll(); return; }

   // Delete all existing dashboard objects
   DashDeleteAll();

   // Format numbers
   double spreadPoints = g_currentSpread / g_point;
   double spreadPips = spreadPoints / 10;
   double avgPoints = g_averageSpread / g_point;
   double minPoints = g_minSpread / g_point;
   double maxPoints = g_maxSpread / g_point;
   double runningAvgPoints = g_runningAvg / g_point;

   // Status indicators
   string timeStatus = (InpLogMode == LOG_ALL) ? "LOGGING ALL TIMES" : 
                       (inWindow ? "ACTIVE WINDOW" : "OUTSIDE WINDOW");
   string marketStatus = (g_tickCounter > 0) ? "LIVE" : "WAITING";
   string windowInfo = (InpLogMode != LOG_ALL) ? StringFormat("%02d:00 - %02d:00", (int)InpStartHour, (int)InpEndHour) : "24/7";

   // Determine spread health
   string healthStr;
   color healthClr;
   if(spreadPoints <= 10)      { healthStr = "EXCELLENT"; healthClr = C'60,220,90'; }
   else if(spreadPoints <= 20) { healthStr = "GOOD";      healthClr = C'230,205,55'; }
   else if(spreadPoints <= 50) { healthStr = "MODERATE";  healthClr = C'255,165,0'; }
   else                        { healthStr = "HIGH";      healthClr = C'220,70,70'; }

   // Calculate running time
   int seconds = (int)(currentTime - g_startTime);
   int hours = seconds / 3600;
   int minutes = (seconds % 3600) / 60;
   int secs = seconds % 60;
   string runningTime = StringFormat("%02d:%02d:%02d", hours, minutes, secs);

   // Colour palette
   color clrHeader = C'20,30,50';
   color clrColHdr = C'25,35,55';
   color clrRowA   = C'30,35,45';
   color clrRowB   = C'35,40,50';
   color clrGreenBg = C'0,40,20';
   color clrRedBg   = C'40,0,0';
   color txtWhite  = clrWhite;
   color txtGray   = C'160,160,170';
   color txtGreen  = C'60,220,90';
   color txtRed    = C'220,70,70';
   color txtYellow = C'230,205,55';
   color txtCyan   = C'60,200,225';
   color txtOrange = C'255,165,0';

   // Draw solid black background
   int totalW = 3*(CELL_W+BORDER_PX)+BORDER_PX;
   int totalH = 13*(CELL_H+BORDER_PX)+BORDER_PX+4;
   string bgMain = DASH_PREFIX+"MAINBG";
   if(ObjectFind(0,bgMain)<0) 
      ObjectCreate(0,bgMain,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bgMain,OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bgMain,OBJPROP_XDISTANCE, DASH_X);
   ObjectSetInteger(0,bgMain,OBJPROP_YDISTANCE, DASH_Y);
   ObjectSetInteger(0,bgMain,OBJPROP_XSIZE,     totalW);
   ObjectSetInteger(0,bgMain,OBJPROP_YSIZE,     totalH);
   ObjectSetInteger(0,bgMain,OBJPROP_BGCOLOR,   clrBlack);
   ObjectSetInteger(0,bgMain,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bgMain,OBJPROP_COLOR,     clrBlack);
   ObjectSetInteger(0,bgMain,OBJPROP_BACK,      false);
   ObjectSetInteger(0,bgMain,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,bgMain,OBJPROP_ZORDER,    0);

   //──────────────────────────────────────────────────────────
   // ROW 0 — Title
   //──────────────────────────────────────────────────────────
   DashCell_(0,0,"","SPREAD MONITOR", clrHeader, txtCyan);
   DashCell_(0,1,"","v1.00",          clrHeader, txtGray);
   DashCell_(0,2,""," ",              clrHeader, txtCyan);

   //──────────────────────────────────────────────────────────
   // ROW 1 — Column headers
   //──────────────────────────────────────────────────────────
   DashCell_(1,0,"","STATUS",    clrColHdr, txtGray);
   DashCell_(1,1,"","SPREAD",    clrColHdr, txtGray);
   DashCell_(1,2,"","STATS",     clrColHdr, txtGray);
   DashSepLine(1);

   //──────────────────────────────────────────────────────────
   // ROW 2
   //──────────────────────────────────────────────────────────
   color statusBg = (g_tickCounter > 0) ? clrGreenBg : clrRedBg;
   color statusClr = (g_tickCounter > 0) ? txtGreen : txtRed;
   DashCell_(2,0,"Market", marketStatus, statusBg, statusClr);
   DashCell_(2,1,"Current", DoubleToString(spreadPoints, 1)+" pts", clrRowA, txtWhite);
   DashCell_(2,2,"Spikes", IntegerToString(g_spikeCount), clrRowA, txtYellow);

   //──────────────────────────────────────────────────────────
   // ROW 3
   //──────────────────────────────────────────────────────────
   string timeStatusDisplay = timeStatus;
   color timeClr = (inWindow || InpLogMode == LOG_ALL) ? txtGreen : txtRed;
   DashCell_(3,0,"Time", timeStatusDisplay+" ["+windowInfo+"]", clrRowB, timeClr);
   DashCell_(3,1,"Health", healthStr, clrRowB, healthClr);
   DashCell_(3,2,"Records", IntegerToString(g_writeCounter), clrRowB, txtWhite);

   //──────────────────────────────────────────────────────────
   // ROW 4
   //──────────────────────────────────────────────────────────
   string statusStr = (g_tickCounter > 0) ? "RUNNING" : "WAITING";
   DashCell_(4,0,"Status", statusStr, clrRowA, txtCyan);
   DashCell_(4,1,"Avg("+IntegerToString(g_spreadPeriod)+")", DoubleToString(avgPoints, 1)+" pts", clrRowA, txtWhite);
   DashCell_(4,2,"Ticks", IntegerToString(g_tickCounter), clrRowA, txtGray);

   //──────────────────────────────────────────────────────────
   // ROW 5
   //──────────────────────────────────────────────────────────
   DashCell_(5,0,"Symbol", g_symbol, clrRowB, txtCyan);
   DashCell_(5,1,"Running", DoubleToString(runningAvgPoints, 1)+" pts", clrRowB, txtWhite);
   DashCell_(5,2,"Window", (InpLogMode==LOG_ALL?"24/7":"Restricted"), clrRowB, (InpLogMode==LOG_ALL?txtGreen:txtYellow));

   //──────────────────────────────────────────────────────────
   // ROW 6
   //──────────────────────────────────────────────────────────
   DashCell_(6,0,"TF", EnumToString(_Period), clrRowA, txtCyan);
   DashCell_(6,1,"Min/Max", DoubleToString(minPoints, 1)+"/"+DoubleToString(maxPoints, 1)+" pts", clrRowA, txtWhite);
   DashCell_(6,2,"Log Freq", (InpLogFrequency>0?IntegerToString(InpLogFrequency)+"s":IntegerToString(InpTickFrequency)+" ticks"), clrRowA, txtGray);
   DashSepLine(6);

   //──────────────────────────────────────────────────────────
   // ROW 7 — Settings section header
   //──────────────────────────────────────────────────────────
   DashCell_(7,0,"","SETTINGS", clrHeader, txtGray);
   DashCell_(7,1,""," ",        clrHeader, txtGray);
   DashCell_(7,2,""," ",        clrHeader, txtGray);
   DashSepLine(7);

   //──────────────────────────────────────────────────────────
   // ROW 8 — Settings
   //──────────────────────────────────────────────────────────
   string rotStr = InpDailyFile ? "Daily" : "Continuous";
   string thrStr = (InpSpreadThreshold > 0) ? DoubleToString(InpSpreadThreshold, 1)+" pts" : "Disabled";
   DashCell_(8,0,"Rotation", rotStr, clrRowA, txtWhite);
   DashCell_(8,1,"Period", IntegerToString(g_spreadPeriod)+" bars", clrRowA, txtWhite);
   DashCell_(8,2,"Threshold", thrStr, clrRowA, (InpSpreadThreshold>0?txtYellow:txtGray));

   //──────────────────────────────────────────────────────────
   // ROW 9 — More settings
   //──────────────────────────────────────────────────────────
   string modeStr = (InpLogMode == LOG_ALL) ? "All Times" : "Window Only";
   DashCell_(9,0,"Mode", modeStr, clrRowB, txtWhite);
   DashCell_(9,1,"Running", runningTime, clrRowB, txtYellow);
   DashCell_(9,2,"Outside", IntegerToString(g_outsideWindowCount), clrRowB, txtGray);
   DashSepLine(9);

   //──────────────────────────────────────────────────────────
   // ROW 10 — File info
   //──────────────────────────────────────────────────────────
   string fileNameShort = g_currentFileName;
   if(StringLen(fileNameShort) > 35)
      fileNameShort = StringSubstr(fileNameShort, StringLen(fileNameShort)-35);
   DashCell_(10,0,"","FILE", clrColHdr, txtGray);
   DashCell_(10,1,"", fileNameShort, clrRowA, txtCyan);
   DashCell_(10,2,"", " ", clrRowA, txtGray);

   //──────────────────────────────────────────────────────────
   // ROW 11 — Controls
   //──────────────────────────────────────────────────────────
   DashCell_(11,0,"","[R] Refresh", clrHeader, txtYellow);
   DashCell_(11,1,"","[D] Toggle", clrHeader, txtYellow);
   DashCell_(11,2,"", " ", clrHeader, txtGray);
   DashSepLine(11);

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Trading-hour window. Start == End (e.g. both Inactive) means no  |
//| time filter; Start > End wraps past midnight (e.g. 22:00-03:00). |
//+------------------------------------------------------------------+
bool IsTradingHour(int hour)
  {
   int startH = (int)InpStartHour;
   int endH   = (int)InpEndHour;
   
   // If both are Inactive (0), treat as ALL HOURS
   if(startH == 0 && endH == 0)
      return true;
   
   // If start == end but not both 0, treat as 24-hour window
   if(startH == endH)
      return true;
   
   // Normal window (e.g., 3:00 - 23:00)
   if(startH < endH)
      return (hour >= startH && hour < endH);
   
   // Overnight window (e.g., 22:00 - 3:00)
   return (hour >= startH || hour < endH);
  }

//+------------------------------------------------------------------+
//| Get day of year (0-365)                                          |
//+------------------------------------------------------------------+
int getDayOfYear(datetime time)
  {
   MqlDateTime dt;
   TimeToStruct(time, dt);
   
   // Simple calculation
   int daysInMonth[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
   
   // Check for leap year
   bool isLeap = (dt.year % 4 == 0 && dt.year % 100 != 0) || (dt.year % 400 == 0);
   if(isLeap)
      daysInMonth[1] = 29;
   
   int dayOfYear = dt.day;
   for(int i = 0; i < dt.mon - 1; i++)
      dayOfYear += daysInMonth[i];
   
   return dayOfYear;
  }
//+------------------------------------------------------------------+