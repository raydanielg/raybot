#property strict

#include "OrderManager.mqh"
#include "RiskManager.mqh"

input string SignalFileName = "signals.json";
input string EquityFileName = "equity.json";
input double MaxLot = 0.05;
input int MaxTrades = 3;
input int TimerSeconds = 1;

COrderManager OrderManager;
CRiskManager RiskManager;
string LastSignalTimestamp = "";

int OnInit()
{
   RiskManager.Configure(MaxLot, MaxTrades);
   EventSetTimer(TimerSeconds);
   WriteEquity();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   WriteEquity();
}

void OnTimer()
{
   WriteEquity();
   ProcessSignal();
}

void ProcessSignal()
{
   string raw = ReadFile(SignalFileName);
   if(raw == "")
      return;

   string timestamp = JsonString(raw, "timestamp");
   if(timestamp == "" || timestamp == LastSignalTimestamp)
      return;

   string symbol = JsonString(raw, "symbol");
   string action = JsonString(raw, "action");
   double lot = JsonDouble(raw, "lot_size");
   double stopLoss = JsonDouble(raw, "stop_loss");
   double takeProfit = JsonDouble(raw, "take_profit");

   LastSignalTimestamp = timestamp;

   if(symbol != _Symbol || action == "HOLD")
      return;

   if(!RiskManager.CanOpenTrade())
      return;

   lot = RiskManager.NormalizeLot(lot);

   if(action == "BUY")
      OrderManager.OpenBuy(lot, stopLoss, takeProfit);

   if(action == "SELL")
      OrderManager.OpenSell(lot, stopLoss, takeProfit);
}

string ReadFile(string fileName)
{
   int handle = FileOpen(fileName, FILE_READ | FILE_TXT | FILE_COMMON);
   if(handle == INVALID_HANDLE)
      return "";

   string content = "";
   while(!FileIsEnding(handle))
      content += FileReadString(handle);

   FileClose(handle);
   return content;
}

void WriteEquity()
{
   int handle = FileOpen(EquityFileName, FILE_WRITE | FILE_TXT | FILE_COMMON);
   if(handle == INVALID_HANDLE)
      return;

   int openPositions = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol)
         openPositions++;
   }

   string payload = "{";
   payload += "\"balance\":" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + ",";
   payload += "\"equity\":" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + ",";
   payload += "\"open_positions\":" + IntegerToString(openPositions);
   payload += "}";

   FileWriteString(handle, payload);
   FileClose(handle);
}

string JsonString(string raw, string key)
{
   string pattern = "\"" + key + "\"";
   int keyPos = StringFind(raw, pattern);
   if(keyPos < 0)
      return "";

   int colon = StringFind(raw, ":", keyPos);
   int firstQuote = StringFind(raw, "\"", colon + 1);
   int secondQuote = StringFind(raw, "\"", firstQuote + 1);

   if(firstQuote < 0 || secondQuote < 0)
      return "";

   return StringSubstr(raw, firstQuote + 1, secondQuote - firstQuote - 1);
}

double JsonDouble(string raw, string key)
{
   string pattern = "\"" + key + "\"";
   int keyPos = StringFind(raw, pattern);
   if(keyPos < 0)
      return 0.0;

   int colon = StringFind(raw, ":", keyPos);
   int comma = StringFind(raw, ",", colon + 1);
   int endBrace = StringFind(raw, "}", colon + 1);
   int endPos = comma > 0 ? comma : endBrace;

   if(colon < 0 || endPos < 0)
      return 0.0;

   string value = StringSubstr(raw, colon + 1, endPos - colon - 1);
   StringTrimLeft(value);
   StringTrimRight(value);

   if(value == "null")
      return 0.0;

   return StringToDouble(value);
}
