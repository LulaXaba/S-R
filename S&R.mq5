#include <Trade/Trade.mqh> // Include the CTrade class

// Declare a global CTrade object
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Initialization code
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // Deinitialization code
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Define variables
   static double supportResistanceLevel = 0; // Stores the support/resistance level
   static bool breakoutConfirmed = false;    // Flag to confirm breakout
   static bool retestConfirmed = false;      // Flag to confirm retest
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID); // Current price

   // Step 1: Identify Support and Resistance
   if (supportResistanceLevel == 0)
     {
      supportResistanceLevel = IdentifySupportResistance();
     }

   // Step 2: Wait for Breakout
   if (!breakoutConfirmed && currentPrice > supportResistanceLevel)
     {
      breakoutConfirmed = true;
      Print("Breakout confirmed at: ", supportResistanceLevel);
     }

   // Step 3: Wait for Retest
   if (breakoutConfirmed && !retestConfirmed && currentPrice <= supportResistanceLevel)
     {
      retestConfirmed = true;
      Print("Retest confirmed at: ", supportResistanceLevel);
     }

   // Step 4: Entry on Price Action Confirmation (Hammer Candlestick)
   if (retestConfirmed && IsHammerCandlestick())
     {
      double stopLoss = currentPrice - (20 * Point()); // 20 pips stop loss
      double takeProfit = currentPrice + (60 * Point()); // 1:3 risk-reward ratio (60 pips)

      // Validate stop loss and take profit levels
      if (stopLoss < currentPrice && takeProfit > currentPrice)
        {
         // Open a buy order with market execution
         if (PositionSelect(_Symbol) == false) // Check if no position is already open
           {
            // Retry logic for requotes
            int retryCount = 3; // Number of retries
            for (int i = 0; i < retryCount; i++)
              {
               if (trade.Buy(0.01, _Symbol, 0, stopLoss, takeProfit)) // Use 0.1 lot size
                 {
                  Print("Buy order opened at market price. SL: ", stopLoss, " TP: ", takeProfit);
                  break; // Exit the retry loop if the order is successful
                 }
               else
                 {
                  Print("Requote encountered. Retrying... Attempt ", i + 1);
                  Sleep(100); // Wait for 100ms before retrying
                 }
              }
           }
        }
      else
        {
         Print("Invalid stop levels. SL: ", stopLoss, " TP: ", takeProfit);
        }
     }
  }
//+------------------------------------------------------------------+
//| Function to identify support/resistance level                    |
//+------------------------------------------------------------------+
double IdentifySupportResistance()
  {
   // Example: Use the previous day's high as resistance
   double previousDayHigh = iHigh(_Symbol, PERIOD_D1, 1);
   return previousDayHigh;
  }
//+------------------------------------------------------------------+
//| Function to check for hammer candlestick pattern                 |
//+------------------------------------------------------------------+
bool IsHammerCandlestick()
  {
   // Hammer candlestick criteria:
   // 1. Small body (less than 20% of the candle range)
   // 2. Long lower wick (at least 2x the body size)
   // 3. Little to no upper wick

   double open = iOpen(_Symbol, PERIOD_M5, 1);
   double close = iClose(_Symbol, PERIOD_M5, 1);
   double high = iHigh(_Symbol, PERIOD_M5, 1);
   double low = iLow(_Symbol, PERIOD_M5, 1);

   double bodySize = MathAbs(close - open);
   double candleRange = high - low;
   double lowerWick = MathMin(open, close) - low;
   double upperWick = high - MathMax(open, close);

   if (bodySize < 0.2 * candleRange && lowerWick >= 2 * bodySize && upperWick < bodySize)
     {
      return true;
     }
   return false;
  }
//+------------------------------------------------------------------+
//| Trade function                                                   |
//+------------------------------------------------------------------+
void OnTrade()
  {
   // Trade event handling code
  }
//+------------------------------------------------------------------+
