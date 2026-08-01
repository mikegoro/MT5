//+------------------------------------------------------------------+
//|                                         SAR_EMA_MACD_Signals.mq5 |
//|                                                Saleh_Toodarvari  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Saleh_Toodarvari"
#property link      "https://mozilla.org/MPL/2.0/"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

// Plot 1: Parabolic SAR (Circles)
#property indicator_label1  "ParabolicSAR"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  C'41,98,255' // #2962FF equivalent
#property indicator_width1  1

// Plot 2: EMA 200 (Line)
#property indicator_label2  "EMA"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrBlue
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

// Plot 3: Buy Signal Label
#property indicator_label3  "Buy Label"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrGreen
#property indicator_width3  2

// Plot 4: Sell Signal Label
#property indicator_label4  "Sell Label"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrRed
#property indicator_width4  2

// Enums
enum ENUM_MA_TYPE {
   MA_TYPE_SMA, // SMA
   MA_TYPE_EMA  // EMA
};

// Inputs
input group "Parabolic SAR Settings"
input double sar_increment = 0.02;      // Step / Increment
input double sar_maximum = 0.2;         // Max Value

input group "EMA Settings"
input int ema_len = 200;                // Length
input int ema_offset = 0;               // Offset

input group "MACD Settings"
input int macd_fast_length = 12;        // Fast Length
input int macd_slow_length = 26;        // Slow Length
input int signal_length = 9;            // Signal Smoothing
input ENUM_MA_TYPE sma_source = MA_TYPE_EMA; // Oscillator MA Type
input ENUM_MA_TYPE sma_signal = MA_TYPE_EMA; // Signal Line MA Type

input group "Alert Settings"
input bool enable_alerts = true;        // Enable Alerts

// Indicator Buffers
double sar_buffer[];
double ema_buffer[];
double buy_buffer[];
double sell_buffer[];

// Internal Calculation Arrays
double fast_ma_arr[];
double slow_ma_arr[];
double macd_arr[];
double signal_arr[];
double delta_arr[];

// Indicator Handles
int sar_handle;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // Bind indicator buffers
   SetIndexBuffer(0, sar_buffer, INDICATOR_DATA);
   SetIndexBuffer(1, ema_buffer, INDICATOR_DATA);
   SetIndexBuffer(2, buy_buffer, INDICATOR_DATA);
   SetIndexBuffer(3, sell_buffer, INDICATOR_DATA);

   // Configure plots
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   // Set Plot 1 (SAR) as Dots
   PlotIndexSetInteger(0, PLOT_ARROW, 159); // 159 is a bullet/dot code
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Set Plot 2 (EMA) configurations
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(1, PLOT_SHIFT, ema_offset); // Apply the offset directly

   // Set Plot 3 & 4 (Signals) as Arrows
   PlotIndexSetInteger(2, PLOT_ARROW, 233); // Arrow Up code
   PlotIndexSetInteger(2, PLOT_ARROW_SHIFT, -15); // Displace visually below bar
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(3, PLOT_ARROW, 234); // Arrow Down code
   PlotIndexSetInteger(3, PLOT_ARROW_SHIFT, 15); // Displace visually above bar
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Initialize built-in Parabolic SAR handle
   sar_handle = iSAR(_Symbol, _Period, sar_increment, sar_maximum);
   if(sar_handle == INVALID_HANDLE)
   {
      Print("Failed to create native SAR handle");
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(sar_handle != INVALID_HANDLE)
      IndicatorRelease(sar_handle);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   // Check minimum bars needed for calculation
   int min_bars = MathMax(ema_len, MathMax(macd_slow_length, macd_fast_length)) + signal_length + 50;
   if(rates_total < min_bars) return(0);

   // Set timeseries direction matching Pine Script indexing (0 is newest, rates_total-1 is oldest)
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(time, true);

   ArraySetAsSeries(sar_buffer, true);
   ArraySetAsSeries(ema_buffer, true);
   ArraySetAsSeries(buy_buffer, true);
   ArraySetAsSeries(sell_buffer, true);

   // Manage internal arrays
   ArrayResize(fast_ma_arr, rates_total);
   ArrayResize(slow_ma_arr, rates_total);
   ArrayResize(macd_arr, rates_total);
   ArrayResize(signal_arr, rates_total);
   ArrayResize(delta_arr, rates_total);

   ArraySetAsSeries(fast_ma_arr, true);
   ArraySetAsSeries(slow_ma_arr, true);
   ArraySetAsSeries(macd_arr, true);
   ArraySetAsSeries(signal_arr, true);
   ArraySetAsSeries(delta_arr, true);

   // Clear historical buffers on full recalculation
   if(prev_calculated == 0)
   {
      ArrayInitialize(sar_buffer, EMPTY_VALUE);
      ArrayInitialize(ema_buffer, EMPTY_VALUE);
      ArrayInitialize(buy_buffer, EMPTY_VALUE);
      ArrayInitialize(sell_buffer, EMPTY_VALUE);
      ArrayInitialize(fast_ma_arr, 0.0);
      ArrayInitialize(slow_ma_arr, 0.0);
      ArrayInitialize(macd_arr, 0.0);
      ArrayInitialize(signal_arr, 0.0);
      ArrayInitialize(delta_arr, 0.0);
   }

   // 1. Retrieve Parabolic SAR data from native indicator
   double temp_sar[];
   if(CopyBuffer(sar_handle, 0, 0, rates_total, temp_sar) < 0)
   {
      Print("Error copying SAR data.");
      return(0);
   }
   // Map back to our series-reversed buffer
   for(int i = 0; i < rates_total; i++)
   {
      sar_buffer[i] = temp_sar[rates_total - 1 - i];
   }

   // 2. Calculate EMA 200
   CalculateEMA_Array(close, ema_buffer, ema_len, rates_total, prev_calculated);

   // 3. Calculate MACD Fast and Slow MA Line
   if(sma_source == MA_TYPE_SMA)
   {
      CalculateSMA_Array(close, fast_ma_arr, macd_fast_length, rates_total, prev_calculated);
      CalculateSMA_Array(close, slow_ma_arr, macd_slow_length, rates_total, prev_calculated);
   }
   else
   {
      CalculateEMA_Array(close, fast_ma_arr, macd_fast_length, rates_total, prev_calculated);
      CalculateEMA_Array(close, slow_ma_arr, macd_slow_length, rates_total, prev_calculated);
   }

   // 4. Calculate MACD
   int calc_limit = (prev_calculated == 0) ? (rates_total - 1) : 2;
   for(int i = calc_limit; i >= 0; i--)
   {
      macd_arr[i] = fast_ma_arr[i] - slow_ma_arr[i];
   }

   // 5. Calculate MACD Signal Line
   if(sma_signal == MA_TYPE_SMA)
      CalculateSMA_Array(macd_arr, signal_arr, signal_length, rates_total, prev_calculated);
   else
      CalculateEMA_Array(macd_arr, signal_arr, signal_length, rates_total, prev_calculated);

   // 6. Calculate MACD Delta
   for(int i = calc_limit; i >= 0; i--)
   {
      delta_arr[i] = macd_arr[i] - signal_arr[i];
   }

   // 7. Calculate signals and fill Arrow Buffers
   for(int i = calc_limit; i >= 0; i--)
   {
      if(i + 1 >= rates_total) continue;

      double ohlc4_val = (open[i] + high[i] + low[i] + close[i]) / 4.0;
      bool main_trend_bullish = (ohlc4_val >= ema_buffer[i]);

      bool sar_long = (sar_buffer[i] < low[i]);
      bool sar_short = (sar_buffer[i] > high[i]);

      // Crossovers on Series arrays: index [i] is current, [i+1] is previous bar
      bool macd_long = (delta_arr[i] > 0 && delta_arr[i+1] <= 0);
      bool macd_short = (delta_arr[i] < 0 && delta_arr[i+1] >= 0);

      bool buy_signal = sar_long && macd_long && main_trend_bullish;
      bool sell_signal = sar_short && macd_short && !main_trend_bullish;

      if(buy_signal)
         buy_buffer[i] = low[i];
      else
         buy_buffer[i] = EMPTY_VALUE;

      if(sell_signal)
         sell_buffer[i] = high[i];
      else
         sell_buffer[i] = EMPTY_VALUE;
   }

   // 8. Handle Alerts (Only triggers once when a signal bar officially closes)
   if(enable_alerts && !IsStopped())
   {
      static datetime last_alert_time = 0;
      datetime current_bar_time = time[0];

      // Avoid immediate alert on indicator drag/load
      if(last_alert_time == 0)
      {
         last_alert_time = current_bar_time;
      }

      if(current_bar_time != last_alert_time)
      {
         // Read closed bar (index 1)
         if(buy_buffer[1] != EMPTY_VALUE)
         {
            Alert("SAR EMA200 MACD Buy signal! - ", _Symbol, " (", EnumToString(_Period), ")");
            SendNotification("SAR EMA200 MACD Buy signal! - " + _Symbol);
            last_alert_time = current_bar_time;
         }
         else if(sell_buffer[1] != EMPTY_VALUE)
         {
            Alert("SAR EMA200 MACD Sell signal! - ", _Symbol, " (", EnumToString(_Period), ")");
            SendNotification("SAR EMA200 MACD Sell signal! - " + _Symbol);
            last_alert_time = current_bar_time;
         }
      }
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Custom EMA Array Calculator (Highly Optimized & Incremental)    |
//+------------------------------------------------------------------+
void CalculateEMA_Array(const double &src[], double &dst[], int period, int rates_total, int prev_calculated)
{
   double alpha = 2.0 / (period + 1.0);
   int first_idx = rates_total - period;
   if(first_idx < 0) return;

   if(prev_calculated == 0)
   {
      // First run: Calculate entire history
      double sum = 0;
      for(int i = 0; i < period; i++)
      {
         sum += src[first_idx + i];
      }
      dst[first_idx] = sum / period;

      for(int i = first_idx - 1; i >= 0; i--)
      {
         dst[i] = src[i] * alpha + dst[i + 1] * (1.0 - alpha);
      }
   }
   else
   {
      // Incremental run: Recalculate only the last active bars
      int limit = 2;
      for(int i = limit; i >= 0; i--)
      {
         if(i + 1 < rates_total)
         {
            dst[i] = src[i] * alpha + dst[i + 1] * (1.0 - alpha);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Custom SMA Array Calculator (Highly Optimized & Incremental)    |
//+------------------------------------------------------------------+
void CalculateSMA_Array(const double &src[], double &dst[], int period, int rates_total, int prev_calculated)
{
   int limit;
   if(prev_calculated == 0)
      limit = rates_total - period;
   else
      limit = 2;

   for(int i = limit; i >= 0; i--)
   {
      if(i + period <= rates_total)
      {
         double sum = 0;
         for(int j = 0; j < period; j++)
         {
            sum += src[i + j];
         }
         dst[i] = sum / period;
      }
   }
}