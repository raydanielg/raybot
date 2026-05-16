#ifndef RISK_MANAGER_MQH
#define RISK_MANAGER_MQH

class CRiskManager
{
private:
   double m_maxLot;
   int m_maxTrades;

public:
   CRiskManager()
   {
      m_maxLot = 0.05;
      m_maxTrades = 3;
   }

   void Configure(double maxLot, int maxTrades)
   {
      m_maxLot = maxLot;
      m_maxTrades = maxTrades;
   }

   double NormalizeLot(double lot)
   {
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double maxLot = MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), m_maxLot);

      if(lot < minLot)
         lot = minLot;

      if(lot > maxLot)
         lot = maxLot;

      return MathFloor(lot / step) * step;
   }

   bool CanOpenTrade()
   {
      int count = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol)
            count++;
      }

      return count < m_maxTrades;
   }
};

#endif
