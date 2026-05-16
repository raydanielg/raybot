#ifndef ORDER_MANAGER_MQH
#define ORDER_MANAGER_MQH

#include <Trade/Trade.mqh>

class COrderManager
{
private:
   CTrade m_trade;

public:
   bool OpenBuy(double lot, double stopLoss, double takeProfit)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      return m_trade.Buy(lot, _Symbol, ask, stopLoss, takeProfit, "AI XAUUSD BUY");
   }

   bool OpenSell(double lot, double stopLoss, double takeProfit)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      return m_trade.Sell(lot, _Symbol, bid, stopLoss, takeProfit, "AI XAUUSD SELL");
   }
};

#endif
