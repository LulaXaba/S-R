#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

CTrade trade;
CPositionInfo positionInfo;

// ORB Variables
static double ORB_High = 0;
static double ORB_Low = 0;
static bool ORB_Set = false;
const int ORB_StartHour = 9;
const int ORB_StartMinute = 30;
const int ORB_EndMinute = 45; // ORB from 9:30 to 9:45

//+------------------------------------------------------------------+
//| Expert Initialization                                           |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(12345);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
//| Check if Position Is Open                                       |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if (positionInfo.SelectByIndex(i))
        {
            if (positionInfo.Symbol() == _Symbol && positionInfo.Magic() == 12345) 
                return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Calculate Lot Size Dynamically                                 |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    double riskPercent = 1.0;  // Risk per trade (% of balance)
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    if (balance <= 0) return 0;
    
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    if (point <= 0 || tickValue <= 0 || tickSize <= 0)
    {
        Print("Invalid symbol parameters");
        return 0;
    }

    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double slDistance = 20 * _Point;  // Example: Fixed 20-pip Stop Loss
    
    if (slDistance <= 0)
    {
        Print("Invalid SL distance");
        return 0;
    }
    
    double riskAmount = balance * (riskPercent / 100.0);
    double pipValue = (tickValue / tickSize) * point * 10;
    double lotSize = riskAmount / (slDistance * pipValue);

    // Adjust lot size within broker limits
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Trade Execution Function                                        |
//+------------------------------------------------------------------+
void PlaceOrder(bool isBullish, double sl, double tp)
{
    if (HasOpenPosition())
    {
        Print("Position already exists - trade blocked");
        return;
    }
    
    MqlTick lastTick;
    if (!SymbolInfoTick(_Symbol, lastTick))
    {
        Print("Failed to get tick data");
        return;
    }
    
    double price = isBullish ? lastTick.ask : lastTick.bid;
    double volume = CalculateLotSize();

    if (volume <= 0)
    {
        Print("Invalid lot size calculation - Trade blocked");
        return;
    }
    
    if (isBullish)
    {
        if (trade.Buy(volume, _Symbol, price, sl, tp, "Bullish Breakout"))
            Print("Buy Order Placed: ", volume, " lots at ", price);
        else
            Print("Buy Order Failed: Error ", GetLastError());
    }
    else
    {
        if (trade.Sell(volume, _Symbol, price, sl, tp, "Bearish Breakout"))
            Print("Sell Order Placed: ", volume, " lots at ", price);
        else
            Print("Sell Order Failed: Error ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Check if Current Time is Within ORB Range                      |
//+------------------------------------------------------------------+
bool IsORBTime()
{
    MqlDateTime currTime;
    TimeCurrent(currTime);
    
    return (currTime.hour == ORB_StartHour && 
            currTime.min >= ORB_StartMinute &&
            currTime.min <= ORB_EndMinute);
}
