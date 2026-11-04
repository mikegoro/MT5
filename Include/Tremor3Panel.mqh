//+------------------------------------------------------------------+
//|                                                  Tremor3Panel.mqh |
//|                                                Copyright 2024, Tremor |
//|                                              https://www.Tremor.com |
//+------------------------------------------------------------------+
#property copyright "Tremor"
#property link      "https://www.Tremor.com"

#include <Controls\Defines.mqh>

// Circular include: pull variables from main EA file
#include<..\Experts\waYwARD\wayward.mq5>

#undef CONTROLS_DIALOG_COLOR_CLIENT_BG
#undef CONTROLS_FONT_NAME

#define CONTROLS_DIALOG_COLOR_CLIENT_BG clrMidnightBlue
#define CONTROLS_FONT_NAME "Consolas"

#include <Controls\Dialog.mqh>
#include <Controls\Label.mqh>
#include <Controls\Button.mqh>

input group "=== Panel Parameters ==="

static input int    InpWidth        = 300;              // Width of the Panel
static input int    InpHeight       = 470;              // Height of the Panel
static input int    InpFontSize     = 9;                // Font Size in the Panel
static input color  InpTxtColor     = clrPaleGreen;     // Text Color in the Panel
static input color  InpBgColor      = clrMidnightBlue;  // Panel Background Color

class CPropFirmPanel : public CAppDialog {

private:
   bool CreatePanel();
   
   // Beginning Balance labels
   CLabel BegBalance;
   CLabel BB_1D;
   CLabel BB_7D;
   CLabel BB_30D;
   CLabel BB_AT;
   
   // Equity High labels
   CLabel EquityHigh;
   CLabel EH_1D;
   CLabel EH_7D;
   CLabel EH_30D;
   CLabel EH_AT;
   
   // Drawdown labels
   CLabel Drawdown;
   CLabel DD_1D;
   CLabel DD_7D;
   CLabel DD_30D;
   CLabel DD_AT;
   
   // Profit labels
   CLabel Profit;
   CLabel Profit_1D;
   CLabel Profit_7D;
   CLabel Profit_30D;
   CLabel Profit_AT;

public:
   void   CPropFirmPanel();
   void   ~CPropFirmPanel();
   bool   OnInit();
   void   PanelChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam);
   void   Update();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
void CPropFirmPanel :: CPropFirmPanel(void) {
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
void CPropFirmPanel :: ~CPropFirmPanel(void) {
}

//+------------------------------------------------------------------+
//| CreatePanel                                                      |
//+------------------------------------------------------------------+
bool CPropFirmPanel :: CreatePanel(void){
   if(!this.Create(NULL,"Challenge Stats",0,0,60,InpWidth,InpHeight)) return false;
   
   BegBalance.Create(0,"BegBalance",0,10,10,1,1);
   BegBalance.Text("Beginning Balance");
   BegBalance.Color(clrGold);
   BegBalance.FontSize(InpFontSize+1);
   this.Add(BegBalance);
   
   BB_1D.Create(0,"BB_1D",0,50,30,1,1);
   BB_1D.Text("   Today   = ");
   BB_1D.Color(InpTxtColor);
   BB_1D.FontSize(InpFontSize);
   this.Add(BB_1D);
   
   BB_7D.Create(0,"BB_7D",0,50,45,1,1);
   BB_7D.Text("   7 Day   = ");
   BB_7D.Color(InpTxtColor);
   BB_7D.FontSize(InpFontSize);
   this.Add(BB_7D);
   
   BB_30D.Create(0,"BB_30D",0,50,60,1,1);
   BB_30D.Text("   30 Day  = ");
   BB_30D.Color(InpTxtColor);
   BB_30D.FontSize(InpFontSize);
   this.Add(BB_30D);
   
   BB_AT.Create(0,"BB_AT",0,50,75,1,1);
   BB_AT.Text("   All Time = ");
   BB_AT.Color(InpTxtColor);
   BB_AT.FontSize(InpFontSize);
   this.Add(BB_AT);
   
   EquityHigh.Create(0,"EquityHigh",0,10,100,1,1);
   EquityHigh.Text("Equity High");
   EquityHigh.Color(clrGold);
   EquityHigh.FontSize(InpFontSize+1);
   this.Add(EquityHigh);
   
   EH_1D.Create(0,"EH_1D",0,50,120,1,1);
   EH_1D.Text("   Today   = ");
   EH_1D.Color(InpTxtColor);
   EH_1D.FontSize(InpFontSize);
   this.Add(EH_1D);
   
   EH_7D.Create(0,"EH_7D",0,50,135,1,1);
   EH_7D.Text("   7 Day   = ");
   EH_7D.Color(InpTxtColor);
   EH_7D.FontSize(InpFontSize);
   this.Add(EH_7D);
   
   EH_30D.Create(0,"EH_30D",0,50,150,1,1);
   EH_30D.Text("   30 Day  = ");
   EH_30D.Color(InpTxtColor);
   EH_30D.FontSize(InpFontSize);
   this.Add(EH_30D);
   
   EH_AT.Create(0,"EH_AT",0,50,165,1,1);
   EH_AT.Text("   All Time = ");
   EH_AT.Color(InpTxtColor);
   EH_AT.FontSize(InpFontSize);
   this.Add(EH_AT);
   
   Drawdown.Create(0,"Drawdown",0,10,190,1,1);
   Drawdown.Text("DrawDown");
   Drawdown.Color(clrGold);
   Drawdown.FontSize(InpFontSize+1);
   this.Add(Drawdown);
   
   DD_1D.Create(0,"DD_1D",0,50,210,1,1);
   DD_1D.Text("   Today   = ");
   DD_1D.Color(InpTxtColor);
   DD_1D.FontSize(InpFontSize);
   this.Add(DD_1D);
   
   DD_7D.Create(0,"DD_7D",0,50,225,1,1);
   DD_7D.Text("   7 Day   = ");
   DD_7D.Color(InpTxtColor);
   DD_7D.FontSize(InpFontSize);
   this.Add(DD_7D);
   
   DD_30D.Create(0,"DD_30D",0,50,240,1,1);
   DD_30D.Text("   30 Day  = ");
   DD_30D.Color(InpTxtColor);
   DD_30D.FontSize(InpFontSize);
   this.Add(DD_30D);
   
   DD_AT.Create(0,"DD_AT",0,50,255,1,1);
   DD_AT.Text("   All Time = ");
   DD_AT.Color(InpTxtColor);
   DD_AT.FontSize(InpFontSize);
   this.Add(DD_AT);
   
   Profit.Create(0,"Profit",0,10,280,1,1);
   Profit.Text("Profit");
   Profit.Color(clrGold);
   Profit.FontSize(InpFontSize+1);
   this.Add(Profit);
   
   Profit_1D.Create(0,"Profit_1D",0,50,300,1,1);
   Profit_1D.Text("   Today   = ");
   Profit_1D.Color(InpTxtColor);
   Profit_1D.FontSize(InpFontSize);
   this.Add(Profit_1D);
   
   Profit_7D.Create(0,"Profit_7D",0,50,315,1,1);
   Profit_7D.Text("   7 Day   = ");
   Profit_7D.Color(InpTxtColor);
   Profit_7D.FontSize(InpFontSize);
   this.Add(Profit_7D);
   
   Profit_30D.Create(0,"Profit_30D",0,50,330,1,1);
   Profit_30D.Text("   30 Day  = ");
   Profit_30D.Color(InpTxtColor);
   Profit_30D.FontSize(InpFontSize);
   this.Add(Profit_30D);
   
   Profit_AT.Create(0,"Profit_AT",0,50,345,1,1);
   Profit_AT.Text("   All Time = ");
   Profit_AT.Color(InpTxtColor);
   Profit_AT.FontSize(InpFontSize);
   this.Add(Profit_AT);
   
   if(!Run()) return false;
   ChartRedraw();
   
   return true;
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
bool CPropFirmPanel :: OnInit(void){
   if(!this.CreatePanel()) return false;
   return true;
}

//+------------------------------------------------------------------+
//| PanelChartEvent                                                  |
//+------------------------------------------------------------------+
void CPropFirmPanel::PanelChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam){
   ChartEvent(id,lparam,dparam,sparam);
}

//+------------------------------------------------------------------+
//| Update                                                           |
//+------------------------------------------------------------------+
void CPropFirmPanel :: Update(void){
   // Beginning Balance
   BB_1D.Text("   Today   = "+(string)BegofDayBalance);
   BB_7D.Text("   7 Day   = "+(string)BegofWeekBalance);
   BB_30D.Text("   30 Day  = "+(string)BegofMonthBalance);
   BB_AT.Text("   All Time = "+(string)InitialBalance);
   
   // Equity High
   EH_1D.Text("   Today   = "+(string)EqHigh_1D);
   EH_7D.Text("   7 Day   = "+(string)EqHigh_7D);
   EH_30D.Text("   30 Day  = "+(string)EqHigh_30D);
   EH_AT.Text("   All Time = "+(string)EqHigh_AT);
   
   // Drawdown
   DD_1D.Text("   Today   = "+StringSubstr((string)DD_1D_Pct,0,4)+" %");
   DD_7D.Text("   7 Day   = "+StringSubstr((string)DD_7D_Pct,0,4)+" %");
   DD_30D.Text("   30 Day  = "+StringSubstr((string)DD_30D_Pct,0,4)+" %");
   DD_AT.Text("   All Time = "+StringSubstr((string)DD_AT_Pct,0,4)+" %");
   
   // Profit
   Profit_1D.Text("   Today   = "+StringSubstr((string)Prf_1D_Pct,0,4)+" %");
   Profit_7D.Text("   7 Day   = "+StringSubstr((string)Prf_7D_Pct,0,4)+" %");
   Profit_30D.Text("   30 Day  = "+StringSubstr((string)Prf_30D_Pct,0,4)+" %");
   Profit_AT.Text("   All Time = "+StringSubstr((string)Prf_AT_Pct,0,4)+" %");
   
   DD_1D.Color(InpTxtColor);
   DD_7D.Color(InpTxtColor);
   DD_30D.Color(InpTxtColor);
   DD_AT.Color(InpTxtColor);
   
   if(DD_1D_Pct < -MaxDDDay)      DD_1D.Color(clrTomato);
   if(DD_7D_Pct < -MaxDDWeek)     DD_7D.Color(clrTomato);
   if(DD_30D_Pct < -MaxDDMonth)   DD_30D.Color(clrTomato);
   if(DD_AT_Pct < -MaxDDTotal)    DD_AT.Color(clrTomato);
}
//+------------------------------------------------------------------+