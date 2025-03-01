#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

CTrade trade;
CPositionInfo positionInfo;

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
//| Expert Tick Function                                            |
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

    // Identify new support/resistance level if not already set
    if(supportResistanceLevel == 0)
    {
        supportResistanceLevel = IdentifySupportResistance();
        breakoutConfirmed = false;
        retestConfirmed = false;
    }

    // Check for breakout
    if(!breakoutConfirmed && IsBreakout(supportResistanceLevel))
    {
        breakoutConfirmed = true;
        isBullish = (currentPrice > supportResistanceLevel);
        Print(isBullish ? "Bullish" : "Bearish", " Breakout at ", supportResistanceLevel);
    }

    // Check for retest confirmation
    if(breakoutConfirmed && !retestConfirmed && IsRetestConfirmed(supportResistanceLevel, isBullish))
    {
        retestConfirmed = true;
        Print("Retest Confirmed at ", supportResistanceLevel);
    }

    // Validate trade entry before execution
    if(retestConfirmed && IsValidTrade(isBullish))
    {
        double atr = iATR(_Symbol, PERIOD_M15, 14);
        double sl = isBullish ? currentPrice - (atr * 2) : currentPrice + (atr * 2);
        double tp = isBullish ? currentPrice + (atr * 4) : currentPrice - (atr * 4);
        PlaceOrder(isBullish, sl, tp);
        breakoutConfirmed = false;
        retestConfirmed = false;
        supportResistanceLevel = 0;
    }
}

//+------------------------------------------------------------------+
//| Check If Position Is Open                                       |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
    for(int i=PositionsTotal()-1; i>=0; i--)
    {
        if(positionInfo.SelectByIndex(i) && positionInfo.Symbol() == _Symbol && positionInfo.Magic() == 12345)
            return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Identify Support/Resistance Levels                             |
//+------------------------------------------------------------------+
double IdentifySupportResistance()
{
    const int lookback = 50;
    double highs[], lows[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);
    CopyHigh(_Symbol, PERIOD_M15, 0, lookback, highs);
    CopyLow(_Symbol, PERIOD_M15, 0, lookback, lows);
    double highest = highs[0], lowest = lows[0];
    for(int i=1; i<lookback; i++)
    {
        if(highs[i] > highest) highest = highs[i];
        if(lows[i] < lowest) lowest = lows[i];
    }
    return NormalizeDouble((highest + lowest) / 2, _Digits);
}

//+------------------------------------------------------------------+
//| Breakout Detection Using ATR                                    |
//+------------------------------------------------------------------+
bool IsBreakout(double supportResistanceLevel)
{
    double atr = iATR(_Symbol, PERIOD_M15, 14);
    double buffer = atr * 0.5;
    double lastClose = iClose(_Symbol, PERIOD_M15, 1);
    return (lastClose > supportResistanceLevel + buffer) || (lastClose < supportResistanceLevel - buffer);
}

//+------------------------------------------------------------------+
//| Retest Confirmation Using Moving Averages                      |
//+------------------------------------------------------------------+
bool IsRetestConfirmed(double supportResistanceLevel, bool isBullish)
{
    double shortMA = iMA(_Symbol, PERIOD_M15, 10, 0, MODE_SMA, PRICE_CLOSE);
    double longMA = iMA(_Symbol, PERIOD_M15, 50, 0, MODE_SMA, PRICE_CLOSE);
    double lastClose = iClose(_Symbol, PERIOD_M15, 1);
    return (isBullish && shortMA > longMA && lastClose < supportResistanceLevel) ||
           (!isBullish && shortMA < longMA && lastClose > supportResistanceLevel);
}

//+------------------------------------------------------------------+
//| Trade Validation Using EMA 200, RSI, and 20-50 MA Trend Filter |
//+------------------------------------------------------------------+
bool IsValidTrade(bool isBullish)
{
    double rsi = iRSI(_Symbol, PERIOD_M15, 14, PRICE_CLOSE);
    double ema200_M15 = iMA(_Symbol, PERIOD_M15, 200, 0, MODE_EMA, PRICE_CLOSE);
    double ma20 = iMA(_Symbol, PERIOD_M15, 20, 0, MODE_SMA, PRICE_CLOSE);
    double ma50 = iMA(_Symbol, PERIOD_M15, 50, 0, MODE_SMA, PRICE_CLOSE);
    
    // Higher timeframe (H1) trend confirmation
    double ema200_H1 = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
    
    return (isBullish && ma20 > ma50 && ema200_M15 > ema200_H1 && rsi > 50) ||
           (!isBullish && ma50 > ma20 && ema200_M15 < ema200_H1 && rsi < 50);
}

//+------------------------------------------------------------------+
//| Trade Execution Function                                        |
//+------------------------------------------------------------------+
void PlaceOrder(bool isBuy, double sl, double tp)
{
    if(HasOpenPosition()) return;
    MqlTick lastTick;
    if(!SymbolInfoTick(_Symbol, lastTick)) return;
    double price = isBuy ? lastTick.ask : lastTick.bid;
    double lotSize = CalculateDynamicLotSize(sl, isBuy);
    if(lotSize <= 0) return;
    
    if(isBuy ? trade.Buy(lotSize, _Symbol, price, sl, tp) : trade.Sell(lotSize, _Symbol, price, sl, tp))
        Print("Trade opened: ", isBuy ? "Buy" : "Sell", " Lots: ", lotSize);
}

//+------------------------------------------------------------------+
//| Lot Size Calculation Function                                   |
//+------------------------------------------------------------------+
double CalculateDynamicLotSize(double slPrice, bool isBuy)
{
    double riskPercent = 1.0;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * riskPercent / 100;
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double riskPips = MathAbs(price - slPrice) / _Point;
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    if(tickValue <= 0 || tickSize <= 0) return 0;
    
    double pipValue = (tickValue / tickSize) * _Point * 10;
    double lotSize = riskAmount / (riskPips * pipValue);
    return lotSize;
}
