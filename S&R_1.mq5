#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

CTrade trade;
CPositionInfo positionInfo;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(12345);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    static double supportResistanceLevel = 0;
    static bool breakoutConfirmed = false;
    static bool retestConfirmed = false;
    static bool isBullish = false;
    
    MqlTick lastTick;
    if(!SymbolInfoTick(_Symbol, lastTick)) return;
    double currentPrice = lastTick.bid;

    // Reset logic when new S/R level forms
    if(supportResistanceLevel == 0)
    {
        supportResistanceLevel = IdentifySupportResistance();
        breakoutConfirmed = false;
        retestConfirmed = false;
    }

    // Breakout Detection with 10-pip buffer
    if(!breakoutConfirmed)
    {
        double buffer = 10 * _Point;
        if(currentPrice > supportResistanceLevel + buffer)
        {
            breakoutConfirmed = true;
            isBullish = true;
            Print("Bullish Breakout at ", supportResistanceLevel);
        }
        else if(currentPrice < supportResistanceLevel - buffer)
        {
            breakoutConfirmed = true;
            isBullish = false;
            Print("Bearish Breakout at ", supportResistanceLevel);
        }
    }

    // Retest Logic with 5-pip buffer
    if(breakoutConfirmed && !retestConfirmed)
    {
        double buffer = 5 * _Point;
        if((isBullish && currentPrice <= supportResistanceLevel + buffer) ||
           (!isBullish && currentPrice >= supportResistanceLevel - buffer))
        {
            retestConfirmed = true;
            Print("Retest Confirmed at ", supportResistanceLevel);
        }
    }

    // Trade Execution with margin check
    if(retestConfirmed)
    {
        double sl = isBullish ? currentPrice - 20 * _Point : currentPrice + 20 * _Point;
        double tp = isBullish ? currentPrice + 60 * _Point : currentPrice - 60 * _Point;
        
        if((isBullish && IsHammerCandlestick()) || (!isBullish && IsInvertedHammerCandlestick()))
        {
            PlaceOrder(isBullish, sl, tp);
            // Reset flags after trade attempt
            breakoutConfirmed = false;
            retestConfirmed = false;
            supportResistanceLevel = 0;
        }
    }
}

//+------------------------------------------------------------------+
//| Safe Order Placement Function                                   |
//+------------------------------------------------------------------+
void PlaceOrder(bool isBuy, double sl, double tp)
{
    if(HasOpenPosition()) return;

    MqlTick lastTick;
    if(!SymbolInfoTick(_Symbol, lastTick)) return;
    
    double price = isBuy ? lastTick.ask : lastTick.bid;
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    sl = NormalizeDouble(sl, digits);
    tp = NormalizeDouble(tp, digits);
    price = NormalizeDouble(price, digits);

    if(sl <= 0 || tp <= 0 || price <= 0) return;

    double lotSize = CalculateDynamicLotSize(sl, isBuy);  // Pass isBuy parameter here
    if(lotSize <= 0) return;

    for(int i=0; i<3; i++)
    {
        if(isBuy ? trade.Buy(lotSize, _Symbol, price, sl, tp) 
                 : trade.Sell(lotSize, _Symbol, price, sl, tp))
        {
            Print("Trade opened: ", isBuy ? "Buy" : "Sell", " Lots: ", lotSize);
            break;
        }
        else
        {
            Print("Order failed. Error: ", GetLastError());
            Sleep(100);
            SymbolInfoTick(_Symbol, lastTick);
        }
    }
}

//+------------------------------------------------------------------+
//| Robust Lot Size Calculation                                     |
//+------------------------------------------------------------------+
double CalculateDynamicLotSize(double slPrice, bool isBuy)  // Add isBuy parameter here
{
    double riskPercent = 1.0;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(balance <= 0) return 0;
    
    // Get symbol information with validation
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    if(point <= 0 || tickValue <= 0 || tickSize <= 0)
    {
        Print("Invalid symbol parameters");
        return 0;
    }

    // Calculate risk amounts
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double riskPips = MathAbs(price - slPrice)/point;
    if(riskPips <= 0)
    {
        Print("Invalid risk calculation");
        return 0;
    }

    // Calculate base lot size
    double riskAmount = balance * riskPercent / 100;
    double pipValue = (tickValue / tickSize) * point * 10; // 1 pip value
    double lotSize = riskAmount / (riskPips * pipValue);

    // Apply broker constraints
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = NormalizeDouble(
        MathFloor(lotSize/lotStep) * lotStep,
        (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)
    );
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

    // Margin safety check
    double marginRequired;
    if(!OrderCalcMargin(
        isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
        _Symbol,
        lotSize,
        isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID),
        marginRequired
    ))
    {
        Print("Margin calculation failed");
        return 0;
    }

    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    if(marginRequired > freeMargin)
    {
        // Auto-adjust lot size to available margin
        double maxAffordableLot = freeMargin / (marginRequired/lotSize);
        maxAffordableLot = NormalizeDouble(
            MathFloor(maxAffordableLot/lotStep) * lotStep,
            (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)
        );
        lotSize = MathMax(minLot, MathMin(maxAffordableLot, lotSize));
        
        Print("Adjusted lot size to ", lotSize, " based on available margin");
    }

    return lotSize;
}

// Rest of the functions (HasOpenPosition, IdentifySupportResistance, 
// IsHammerCandlestick, IsInvertedHammerCandlestick) remain unchanged
//+------------------------------------------------------------------+
//| Position Check                                                  |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
    for(int i=PositionsTotal()-1; i>=0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == 12345)
                return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Support/Resistance Identification                              |
//+------------------------------------------------------------------+
double IdentifySupportResistance()
{
    const int lookback = 50;
    double highs[];
    double lows[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);
    
    CopyHigh(_Symbol, PERIOD_M15, 0, lookback, highs);
    CopyLow(_Symbol, PERIOD_M15, 0, lookback, lows);
    
    double avgHigh = 0, avgLow = 0;
    for(int i=0; i<lookback; i++)
    {
        avgHigh += highs[i];
        avgLow += lows[i];
    }
    return NormalizeDouble((avgHigh/lookback + avgLow/lookback)/2, _Digits);
}

//+------------------------------------------------------------------+
//| Candlestick Pattern Recognition (Fixed Division Errors)         |
//+------------------------------------------------------------------+
bool IsHammerCandlestick()
{
    double open = iOpen(_Symbol, PERIOD_M5, 1);
    double close = iClose(_Symbol, PERIOD_M5, 1);
    double high = iHigh(_Symbol, PERIOD_M5, 1);
    double low = iLow(_Symbol, PERIOD_M5, 1);
    
    double body = MathAbs(close - open);
    double range = high - low;
    
    // Prevent division by zero
    if(range <= 0 || body <= 0) return false;
    
    double lowerWick = MathMin(open, close) - low;
    return (body/range < 0.2) && (lowerWick/body >= 2);
}

bool IsInvertedHammerCandlestick()
{
    double open = iOpen(_Symbol, PERIOD_M5, 1);
    double close = iClose(_Symbol, PERIOD_M5, 1);
    double high = iHigh(_Symbol, PERIOD_M5, 1);
    double low = iLow(_Symbol, PERIOD_M5, 1);
    
    double body = MathAbs(close - open);
    double range = high - low;
    
    // Prevent division by zero
    if(range <= 0 || body <= 0) return false;
    
    double upperWick = high - MathMax(open, close);
    return (body/range < 0.2) && (upperWick/body >= 2);
}
