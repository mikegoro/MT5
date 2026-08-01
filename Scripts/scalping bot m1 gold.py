import MetaTrader5 as mt5
import pandas as pd
from datetime import datetime

# Step 1: Try to connect to the running MT5 terminal
if not mt5.initialize():
    print("initialize() failed")
    print("Error code:", mt5.last_error())
    quit()

print("Successfully connected to MetaTrader 5")
print("Terminal version:", mt5.version())
print("Terminal build:", mt5.terminal_info().build)
print("Account number:", mt5.account_info().login)
print("Account balance:", mt5.account_info().balance)
print("Account equity:", mt5.account_info().equity)

# Step 2: Set the symbol (change this to your broker's exact gold symbol)
symbol = "XAUUSD"          # ← Change if your broker uses GOLD, XAUUSDm, XAUUSD., etc.

# Make sure the symbol is visible/selected in Market Watch
if not mt5.symbol_select(symbol, True):
    print(f"Failed to select symbol {symbol}")
    print("Error:", mt5.last_error())
    mt5.shutdown()
    quit()

print(f"Symbol {symbol} selected successfully")

# Step 3: Get current market prices (bid & ask)
tick = mt5.symbol_info_tick(symbol)
if tick is not None:
    print(f"Current Bid: {tick.bid}")
    print(f"Current Ask: {tick.ask}")
    print(f"Spread: {tick.ask - tick.bid} points")
else:
    print("Failed to get tick data")

# Step 4: Get recent 1-minute candles (last 50 bars)
rates = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_M1, 0, 50)
if rates is None or len(rates) == 0:
    print("Failed to get rates")
    print("Error:", mt5.last_error())
else:
    df = pd.DataFrame(rates)
    df['time'] = pd.to_datetime(df['time'], unit='s')
    print("\nLast 5 candles (1-minute):")
    print(df[['time', 'open', 'high', 'low', 'close', 'tick_volume']].tail())

# Step 5: Clean up
print("\nTest finished. Shutting down connection...")
mt5.shutdown()