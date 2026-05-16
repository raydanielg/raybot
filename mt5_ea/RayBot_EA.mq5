//+------------------------------------------------------------------+
//|                                                    RayBot_EA.mq5  |
//|                  ██████╗  █████╗ ██╗   ██╗██████╗  ██████╗ ████████╗|
//|                  ██╔══██╗██╔══██╗╚██╗ ██╔╝██╔══██╗██╔═══██╗╚══██╔══╝|
//|                  ██████╔╝███████║ ╚████╔╝ ██████╔╝██║   ██║   ██║   |
//|                  ██╔══██╗██╔══██║  ╚██╔╝  ██╔══██╗██║   ██║   ██║   |
//|                  ██║  ██║██║  ██║   ██║   ██████╔╝╚██████╔╝   ██║   |
//|                  ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═════╝  ╚═════╝    ╚═╝   |
//|                                                                       |
//|              THE GREAT RAYBOT — AI-POWERED WORLDWIDE FOREX EA         |
//|              Powered by Claude AI (Anthropic)                         |
//|              Version: 3.0 ULTIMATE + Safety Guardrails                |
//|              Strategies: RSI + MA + MACD + BB + ATR + AI Sentiment    |
//+------------------------------------------------------------------+
#property copyright  "RayBot — Powered by Claude AI"
#property link       "https://anthropic.com"
#property version    "3.01"
#property description "The Great RayBot: AI-Powered Worldwide Forex Trading EA with Safety Guardrails"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//═══════════════════════════════════════════════════════════════════
//  INPUT GROUPS
//═══════════════════════════════════════════════════════════════════

input group "════ 🤖 CLAUDE AI SETTINGS ════"
input string   AI_ApiKey           = "sk-ant-YOUR_KEY_HERE";  // Anthropic API Key
input int      AI_TimeoutMs        = 10000;                   // API Timeout (ms)
input int      AI_MaxTokens        = 512;                     // Max response tokens
input bool     AI_EnableSentiment  = true;                    // Enable AI Sentiment Analysis
input bool     AI_EnableRiskReview = true;                    // AI reviews every trade risk

input group "════ 📊 STRATEGY: RSI + MA ════"
input int      RSI_Period          = 14;                      // RSI Period
input double   RSI_Overbought      = 70.0;                    // RSI Overbought
input double   RSI_Oversold        = 30.0;                    // RSI Oversold
input int      MA_Fast             = 20;                      // Fast EMA Period
input int      MA_Slow             = 50;                      // Slow EMA Period
input int      MA_Trend            = 200;                     // Trend EMA Period

input group "════ 📉 STRATEGY: MACD ════"
input int      MACD_Fast           = 12;                      // MACD Fast
input int      MACD_Slow           = 26;                      // MACD Slow
input int      MACD_Signal         = 9;                       // MACD Signal

input group "════ 📈 STRATEGY: BOLLINGER BANDS ════"
input int      BB_Period           = 20;                      // BB Period
input double   BB_Deviation        = 2.0;                     // BB Deviation

input group "════ ⚡ STRATEGY: ATR ════"
input int      ATR_Period          = 14;                      // ATR Period
input double   ATR_SL_Multiplier   = 1.5;                     // SL = ATR × this
input double   ATR_TP_Multiplier   = 3.0;                     // TP = ATR × this

input group "════ 💰 RISK MANAGEMENT ════"
input double   Risk_Percent        = 1.0;                     // Risk per trade (% balance)
input double   Risk_MaxLot         = 5.0;                     // Maximum lot size
input double   Risk_MinLot         = 0.01;                    // Minimum lot size
input int      Risk_MaxOpenTrades  = 5;                       // Max simultaneous trades
input double   Risk_MaxDailyLoss   = 5.0;                     // Max daily loss (% balance)
input double   Risk_MaxDrawdown    = 15.0;                    // Max drawdown before pause (%)
input bool     Risk_UseTrailStop   = true;                    // Enable trailing stop
input int      Risk_TrailPips      = 30;                      // Trailing stop distance (pips)
input bool     Risk_UseBreakEven   = true;                    // Move SL to breakeven
input int      Risk_BEPips         = 20;                      // Pips in profit for breakeven

input group "════ 🛡️ SAFETY GUARDRAILS ════"
input int      Guard_MaxOpenPositions = 3;                    // Max open positions (0=unlimited)
input int      Guard_TradeCooldownSec = 60;                   // Cooldown between trades (seconds)
input int      Guard_MaxSpreadPoints = 50;                    // Max spread to trade (points)

input group "════ ⏰ TIMEFRAME & SESSIONS ════"
input ENUM_TIMEFRAMES TF_Primary   = PERIOD_H1;               // Primary Timeframe
input ENUM_TIMEFRAMES TF_Confirm   = PERIOD_H4;               // Confirmation Timeframe
input ENUM_TIMEFRAMES TF_Scalp     = PERIOD_M15;              // Fast Timeframe
input bool     Session_London      = true;                    // Trade London session
input bool     Session_NewYork     = true;                    // Trade New York session
input bool     Session_Tokyo       = false;                   // Trade Tokyo session
input bool     Session_Sydney      = false;                   // Trade Sydney session

input group "════ 📰 NEWS FILTER ════"
input bool     News_PauseHighImpact = true;                   // Pause on high-impact news
input int      News_MinutesBefore   = 30;                     // Pause X min before news
input int      News_MinutesAfter    = 15;                     // Resume X min after news

input group "════ 📓 JOURNAL & DASHBOARD ════"
input bool     Log_EnableJournal   = true;                    // Enable CSV journal
input string   Log_JournalFile     = "RayBot_Journal.csv";    // Journal filename
input bool     Log_ShowDashboard   = true;                    // Show chart dashboard
input color    Log_PanelColor      = clrMidnightBlue;         // Dashboard background color

input group "════ ⚙️ EXECUTION ════"
input bool     Exec_OnNewCandle    = true;                    // Analyze on new candle only
input int      Exec_Slippage       = 10;                      // Max slippage (points)
input int      MagicNumber         = 77777;                   // EA Magic Number

//═══════════════════════════════════════════════════════════════════
//  GLOBAL VARIABLES
//═══════════════════════════════════════════════════════════════════

CTrade         trade;
CPositionInfo  posInfo;
COrderInfo     orderInfo;

datetime  lastBarTime       = 0;
datetime  lastAICallTime    = 0;
datetime  lastTradeTime     = 0;
double    startingBalance   = 0;
double    dailyStartBalance = 0;
datetime  lastDayCheck      = 0;
int       totalTrades       = 0;
int       winTrades         = 0;
int       lossTrades        = 0;
double    totalProfitLoss   = 0;
double    peakBalance       = 0;
bool      tradingPaused     = false;
string    lastSignal        = "NONE";
string    lastReason        = "";
string    lastAIComment     = "";
int       dashPanel         = 0;
double    lastLot           = 0;
double    lastSL            = 0;
double    lastTP            = 0;

//═══════════════════════════════════════════════════════════════════
//  INIT
//═══════════════════════════════════════════════════════════════════

int OnInit()
{
   Print("╔══════════════════════════════════════════╗");
   Print("║     THE GREAT RAYBOT v3.0 ULTIMATE       ║");
   Print("║     Powered by Claude AI — Anthropic     ║");
   Print("║     + Safety Guardrails (v3.01)          ║");
   Print("╚══════════════════════════════════════════╝");

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Exec_Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   startingBalance   = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyStartBalance = startingBalance;
   peakBalance       = startingBalance;
   lastDayCheck      = TimeCurrent();
   lastTradeTime     = 0;

   if(Log_EnableJournal)  InitJournal();
   if(Log_ShowDashboard)  DrawDashboard();

   Print("✅ RayBot initialized on ", _Symbol, " [", EnumToString(TF_Primary), "]");
   Print("   Balance: $", DoubleToString(startingBalance, 2));
   Print("   Magic: ", MagicNumber, " | Risk: ", Risk_Percent, "%");
   Print("   Guardrails: Max Pos=", Guard_MaxOpenPositions, " | Cooldown=", Guard_TradeCooldownSec, "s | MaxSpread=", Guard_MaxSpreadPoints, "pts");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "RB_");
   Print("══════════════════════════════════════════");
   Print("RayBot Session Summary:");
   Print("  Total Trades : ", totalTrades);
   Print("  Wins         : ", winTrades);
   Print("  Losses       : ", lossTrades);
   if(totalTrades > 0)
      Print("  Win Rate     : ", DoubleToString(100.0 * winTrades / totalTrades, 1), "%");
   Print("  Net P&L      : $", DoubleToString(totalProfitLoss, 2));
   Print("══════════════════════════════════════════");
}

//═══════════════════════════════════════════════════════════════════
//  MAIN TICK
//═══════════════════════════════════════════════════════════════════

void OnTick()
{
   // --- Daily reset check ---
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   MqlDateTime dtLast; TimeToStruct(lastDayCheck, dtLast);
   if(dt.day != dtLast.day)
   {
      dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastDayCheck = TimeCurrent();
      tradingPaused = false;
      Print("📅 New day — daily balance reset: $", DoubleToString(dailyStartBalance, 2));
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   // --- Update peak and check drawdown ---
   if(equity > peakBalance) peakBalance = equity;
   double drawdown = (peakBalance - equity) / peakBalance * 100.0;

   if(drawdown >= Risk_MaxDrawdown)
   {
      if(!tradingPaused)
      {
         tradingPaused = true;
         Print("⛔ MAX DRAWDOWN REACHED (", DoubleToString(drawdown, 1), "%) — Trading paused.");
      }
   }

   // --- Daily loss check ---
   double dailyLoss = (dailyStartBalance - balance) / dailyStartBalance * 100.0;
   if(dailyLoss >= Risk_MaxDailyLoss)
   {
      if(!tradingPaused)
      {
         tradingPaused = true;
         Print("⛔ MAX DAILY LOSS REACHED (", DoubleToString(dailyLoss, 1), "%) — Trading paused.");
      }
   }

   // --- Manage open positions (trail stop, breakeven) ---
   ManageOpenPositions();

   if(tradingPaused) { UpdateDashboard(); return; }

   // --- Session filter ---
   if(!IsValidSession()) { UpdateDashboard(); return; }

   // --- New candle check ---
   if(Exec_OnNewCandle)
   {
      datetime currentBar = iTime(_Symbol, TF_Primary, 0);
      if(currentBar == lastBarTime) { UpdateDashboard(); return; }
      lastBarTime = currentBar;
   }

   // --- Max open trades check ---
   if(CountOpenTrades() >= Risk_MaxOpenTrades)
   {
      UpdateDashboard();
      return;
   }

   // --- Build context and call Claude ---
   string context = BuildMarketContext();
   if(context == "") return;

   Print("🤖 Calling Claude AI...");
   string aiResponse = AskClaude(context);
   if(aiResponse == "") return;

   Print("📡 Claude says: ", aiResponse);

   // --- Parse response ---
   string signal   = ExtractField(aiResponse, "SIGNAL");
   double lotSize  = StringToDouble(ExtractField(aiResponse, "LOT"));
   double slPips   = StringToDouble(ExtractField(aiResponse, "SL"));
   double tpPips   = StringToDouble(ExtractField(aiResponse, "TP"));
   string reason   = ExtractField(aiResponse, "REASON");
   string confScore= ExtractField(aiResponse, "CONFIDENCE");

   lastSignal    = signal;
   lastReason    = reason;
   lastAIComment = confScore;

   // --- Validate lot size ---
   if(lotSize <= 0) lotSize = CalculateLotSize(slPips > 0 ? slPips : (int)(iATR(_Symbol, TF_Primary, ATR_Period) / _Point * ATR_SL_Multiplier));
   lotSize = NormalizeLot(lotSize);

   // --- Validate SL/TP ---
   double atr    = iATR(_Symbol, TF_Primary, ATR_Period);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pip    = (digits == 3 || digits == 5) ? point * 10 : point;
   if(slPips <= 0) slPips = NormalizeDouble(atr / pip * ATR_SL_Multiplier, 0);
   if(tpPips <= 0) tpPips = NormalizeDouble(atr / pip * ATR_TP_Multiplier, 0);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool   executed = false;

   // === SAFETY GUARDRAILS SECTION ===
   if(signal == "BUY" || signal == "SELL")
   {
      // Check max open positions
      int openCount = CountOpenTrades();
      if(Guard_MaxOpenPositions > 0 && openCount >= Guard_MaxOpenPositions)
      {
         Print("🛡️ BLOCKED: Max open positions (", Guard_MaxOpenPositions, ") reached. Current: ", openCount);
         signal = "HOLD";
         reason = "Position limit reached";
      }

      // Check cooldown
      if(signal != "HOLD")
      {
         int timeSinceLast = (int)(TimeCurrent() - lastTradeTime);
         if(lastTradeTime > 0 && timeSinceLast < Guard_TradeCooldownSec)
         {
            Print("🛡️ BLOCKED: Cooldown active. ", Guard_TradeCooldownSec - timeSinceLast, "s remaining");
            signal = "HOLD";
            reason = "Trade cooldown active";
         }
      }

      // Check spread
      if(signal != "HOLD")
      {
         int currentSpread = (int)((ask - bid) / point);
         if(currentSpread > Guard_MaxSpreadPoints)
         {
            Print("🛡️ BLOCKED: Spread too wide (", currentSpread, " > ", Guard_MaxSpreadPoints, ")");
            signal = "HOLD";
            reason = "Spread exceeds threshold";
         }
      }
   }

   // --- Execute ---
   if(signal == "BUY" && !HasOpenPosition(POSITION_TYPE_BUY))
   {
      double sl = NormalizeDouble(bid - slPips * pip, digits);
      double tp = NormalizeDouble(ask + tpPips * pip, digits);
      if(trade.Buy(lotSize, _Symbol, ask, sl, tp, "RayBot BUY"))
      {
         executed = true;
         lastLot = lotSize; lastSL = slPips; lastTP = tpPips;
         lastTradeTime = TimeCurrent();
         totalTrades++;
         Print("✅ BUY | Lot:", lotSize, " SL:", sl, " TP:", tp, " Reason:", reason);
      }
   }
   else if(signal == "SELL" && !HasOpenPosition(POSITION_TYPE_SELL))
   {
      double sl = NormalizeDouble(ask + slPips * pip, digits);
      double tp = NormalizeDouble(bid - tpPips * pip, digits);
      if(trade.Sell(lotSize, _Symbol, bid, sl, tp, "RayBot SELL"))
      {
         executed = true;
         lastLot = lotSize; lastSL = slPips; lastTP = tpPips;
         lastTradeTime = TimeCurrent();
         totalTrades++;
         Print("✅ SELL | Lot:", lotSize, " SL:", sl, " TP:", tp, " Reason:", reason);
      }
   }
   else if(signal == "CLOSE")
   {
      CloseAllPositions();
      Print("🔄 CLOSE signal — all positions closed. Reason:", reason);
   }
   else
   {
      Print("⏸ HOLD — ", reason);
   }

   if(Log_EnableJournal) WriteJournal(signal, lotSize, slPips, tpPips, reason, confScore, executed);
   UpdateDashboard();
}

//═══════════════════════════════════════════════════════════════════
//  MARKET CONTEXT BUILDER
//═══════════════════════════════════════════════════════════════════

string BuildMarketContext()
{
   int    digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pip     = (digits == 3 || digits == 5) ? point * 10 : point;

   // Prices
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    spread  = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   // RSI
   double rsi1    = iRSI(_Symbol, TF_Primary,  RSI_Period, PRICE_CLOSE);
   double rsiH4   = iRSI(_Symbol, TF_Confirm,  RSI_Period, PRICE_CLOSE);
   double rsiM15  = iRSI(_Symbol, TF_Scalp,    RSI_Period, PRICE_CLOSE);

   // Moving Averages
   double maF0    = iMA(_Symbol, TF_Primary, MA_Fast,  0, MODE_EMA, PRICE_CLOSE);
   double maS0    = iMA(_Symbol, TF_Primary, MA_Slow,  0, MODE_EMA, PRICE_CLOSE);
   double maT0    = iMA(_Symbol, TF_Primary, MA_Trend, 0, MODE_EMA, PRICE_CLOSE);
   double maF1    = iMA(_Symbol, TF_Primary, MA_Fast,  1, MODE_EMA, PRICE_CLOSE);
   double maS1    = iMA(_Symbol, TF_Primary, MA_Slow,  1, MODE_EMA, PRICE_CLOSE);
   double maFH4   = iMA(_Symbol, TF_Confirm, MA_Fast,  0, MODE_EMA, PRICE_CLOSE);
   double maSH4   = iMA(_Symbol, TF_Confirm, MA_Slow,  0, MODE_EMA, PRICE_CLOSE);

   // MACD
   double macdMain0  = iMACD(_Symbol, TF_Primary, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   double macdSig0   = iMACD(_Symbol, TF_Primary, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);

   // Bollinger Bands
   double bbUpper = iBands(_Symbol, TF_Primary, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
   double bbLower = iBands(_Symbol, TF_Primary, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
   double bbMid   = iBands(_Symbol, TF_Primary, BB_Period, 0, 0,            PRICE_CLOSE);

   // ATR
   double atr     = iATR(_Symbol, TF_Primary, ATR_Period);
   double atrH4   = iATR(_Symbol, TF_Confirm, ATR_Period);

   // Candles
   double c0  = iClose(_Symbol, TF_Primary, 0);
   double c1  = iClose(_Symbol, TF_Primary, 1);
   double c2  = iClose(_Symbol, TF_Primary, 2);
   double h1  = iHigh(_Symbol,  TF_Primary, 1);
   double l1  = iLow(_Symbol,   TF_Primary, 1);
   double h5  = iHigh(_Symbol,  TF_Primary, 5);  // recent swing high
   double l5  = iLow(_Symbol,   TF_Primary, 5);  // recent swing low

   // Account
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double freeMargin= AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double drawdown  = peakBalance > 0 ? (peakBalance - equity) / peakBalance * 100.0 : 0;
   double dailyLoss = (dailyStartBalance - balance) / dailyStartBalance * 100.0;

   // MA Crossover State
   string crossState = "NONE";
   if(maF0 > maS0 && maF1 <= maS1)  crossState = "FRESH_BULLISH_CROSS";
   else if(maF0 > maS0)             crossState = "BULLISH (fast above slow)";
   else if(maF0 < maS0 && maF1 >= maS1) crossState = "FRESH_BEARISH_CROSS";
   else                             crossState = "BEARISH (fast below slow)";

   string trendState = (c0 > maT0) ? "ABOVE 200 EMA (BULLISH TREND)" : "BELOW 200 EMA (BEARISH TREND)";

   string bbState = "INSIDE";
   if(ask > bbUpper) bbState = "ABOVE UPPER BAND (overbought zone)";
   else if(bid < bbLower) bbState = "BELOW LOWER BAND (oversold zone)";

   string prompt =
      "You are RayBot — the world's most advanced AI forex trading analyst. Analyze all data and output a precise trading decision.\\n\\n" +

      "=== SYMBOL & MARKET ===" + "\\n" +
      "Symbol       : " + _Symbol + "\\n" +
      "Ask / Bid    : " + DoubleToString(ask, digits) + " / " + DoubleToString(bid, digits) + "\\n" +
      "Spread       : " + IntegerToString(spread) + " pts\\n" +
      "Session      : " + GetCurrentSession() + "\\n\\n" +

      "=== MULTI-TIMEFRAME RSI(" + IntegerToString(RSI_Period) + ") ===" + "\\n" +
      "RSI [" + EnumToString(TF_Scalp)   + "] : " + DoubleToString(rsiM15, 2) + "\\n" +
      "RSI [" + EnumToString(TF_Primary) + "] : " + DoubleToString(rsi1,   2) + "\\n" +
      "RSI [" + EnumToString(TF_Confirm) + "] : " + DoubleToString(rsiH4,  2) + "\\n" +
      "Overbought / Oversold : " + DoubleToString(RSI_Overbought, 0) + " / " + DoubleToString(RSI_Oversold, 0) + "\\n\\n" +

      "=== MOVING AVERAGES ===" + "\\n" +
      "Fast EMA(" + IntegerToString(MA_Fast)  + ") [H1] : " + DoubleToString(maF0, digits) + "\\n" +
      "Slow EMA(" + IntegerToString(MA_Slow)  + ") [H1] : " + DoubleToString(maS0, digits) + "\\n" +
      "Trend EMA(" + IntegerToString(MA_Trend) + ") [H1] : " + DoubleToString(maT0, digits) + "\\n" +
      "Crossover State      : " + crossState + "\\n" +
      "Trend State          : " + trendState + "\\n" +
      "Fast/Slow EMA [H4]   : " + DoubleToString(maFH4, digits) + " / " + DoubleToString(maSH4, digits) + "\\n\\n" +

      "=== MACD (12,26,9) ===" + "\\n" +
      "MACD Line  : " + DoubleToString(macdMain0, 6) + "\\n" +
      "Signal     : " + DoubleToString(macdSig0,  6) + "\\n\\n" +

      "=== BOLLINGER BANDS(" + IntegerToString(BB_Period) + ") ===" + "\\n" +
      "Upper / Mid / Lower : " + DoubleToString(bbUpper, digits) + " / " + DoubleToString(bbMid, digits) + " / " + DoubleToString(bbLower, digits) + "\\n" +
      "Price Position       : " + bbState + "\\n\\n" +

      "=== ATR VOLATILITY ===" + "\\n" +
      "ATR(" + IntegerToString(ATR_Period) + ") [" + EnumToString(TF_Primary) + "] : " + DoubleToString(atr, digits) + "\\n" +
      "ATR(" + IntegerToString(ATR_Period) + ") [" + EnumToString(TF_Confirm) + "] : " + DoubleToString(atrH4, digits) + "\\n" +
      "ATR in pips : " + DoubleToString(atr / pip, 1) + "\\n\\n" +

      "=== RECENT PRICE ACTION ===" + "\\n" +
      "Current close   : " + DoubleToString(c0, digits) + "\\n" +
      "Previous closes : " + DoubleToString(c1, digits) + " → " + DoubleToString(c2, digits) + "\\n" +
      "Recent High (5 bars) : " + DoubleToString(h5, digits) + "\\n" +
      "Recent Low  (5 bars) : " + DoubleToString(l5, digits) + "\\n" +
      "Last candle H/L : " + DoubleToString(h1, digits) + " / " + DoubleToString(l1, digits) + "\\n\\n" +

      "=== ACCOUNT ===" + "\\n" +
      "Balance       : $" + DoubleToString(balance, 2) + "\\n" +
      "Equity        : $" + DoubleToString(equity, 2) + "\\n" +
      "Free Margin   : $" + DoubleToString(freeMargin, 2) + "\\n" +
      "Current Drawdown : " + DoubleToString(drawdown, 2) + "%\\n" +
      "Daily Loss    : " + DoubleToString(dailyLoss, 2) + "%\\n" +
      "Open Trades   : " + IntegerToString(CountOpenTrades()) + " / " + IntegerToString(Risk_MaxOpenTrades) + "\\n" +
      "Risk per trade: " + DoubleToString(Risk_Percent, 1) + "% of balance\\n\\n" +

      "=== TRADE HISTORY ===" + "\\n" +
      "Total Trades  : " + IntegerToString(totalTrades) + "\\n" +
      "Wins / Losses : " + IntegerToString(winTrades) + " / " + IntegerToString(lossTrades) + "\\n\\n" +

      "=== TRADING RULES ===" + "\\n" +
      "BUY  : Bullish MA cross + RSI not overbought + price above 200 EMA + MACD positive + H4 confirms\\n" +
      "SELL : Bearish MA cross + RSI not oversold + price below 200 EMA + MACD negative + H4 confirms\\n" +
      "CLOSE: Reversal signal invalidates current position\\n" +
      "HOLD : No confluence, news risk, or conflicting signals\\n\\n" +
      "SL recommendation: Use 1.5× ATR from entry\\n" +
      "TP recommendation: Use 3× ATR from entry (minimum 1:2 R:R)\\n" +
      "Lot size: calculate using " + DoubleToString(Risk_Percent, 1) + "% risk on $" + DoubleToString(balance, 2) + " balance with the SL in pips\\n\\n" +

      "RESPOND ONLY in this EXACT format (no extra words, no markdown):\\n" +
      "SIGNAL: [BUY|SELL|HOLD|CLOSE]\\n" +
      "LOT: [e.g. 0.10]\\n" +
      "SL: [stop loss in pips e.g. 45]\\n" +
      "TP: [take profit in pips e.g. 135]\\n" +
      "CONFIDENCE: [HIGH|MEDIUM|LOW]\\n" +
      "REASON: [one concise sentence with key confluence factors]";

   return prompt;
}

//═══════════════════════════════════════════════════════════════════
//  CLAUDE AI CALL
//═══════════════════════════════════════════════════════════════════

string AskClaude(string prompt)
{
   string url = "https://api.anthropic.com/v1/messages";
   string headers =
      "x-api-key: " + AI_ApiKey + "\r\n" +
      "anthropic-version: 2023-06-01\r\n" +
      "content-type: application/json\r\n";

   StringReplace(prompt, "\\", "\\\\");
   StringReplace(prompt, "\"", "\\\"");
   StringReplace(prompt, "\n", "\\n");
   StringReplace(prompt, "\r", "");

   string payload =
      "{\"model\":\"claude-sonnet-4-6\"," +
      "\"max_tokens\":" + IntegerToString(AI_MaxTokens) + "," +
      "\"system\":\"You are RayBot, a world-class AI forex trading assistant. Always respond in the exact structured format requested. Be precise, analytical, and conservative with risk.\"," +
      "\"messages\":[{\"role\":\"user\",\"content\":\"" + prompt + "\"}]}";

   char   postData[];
   char   resultData[];
   string resultHeaders;

   StringToCharArray(payload, postData, 0, StringLen(payload));

   int code = WebRequest("POST", url, headers, AI_TimeoutMs, postData, resultData, resultHeaders);

   if(code == 200)
   {
      string raw = CharArrayToString(resultData);
      return ParseClaudeText(raw);
   }
   else
   {
      string err = CharArrayToString(resultData);
      Print("❌ Claude API Error | HTTP: ", code, " | ", err);
      return "";
   }
}

string ParseClaudeText(string json)
{
   int start = StringFind(json, "\"text\":\"");
   if(start < 0) { Print("❌ Cannot parse Claude response: ", json); return ""; }
   start += 8;
   // Find closing quote not preceded by backslash
   int pos = start;
   while(pos < StringLen(json))
   {
      if(StringGetCharacter(json, pos) == '"' && StringGetCharacter(json, pos-1) != '\\')
         break;
      pos++;
   }
   string text = StringSubstr(json, start, pos - start);
   StringReplace(text, "\\n", "\n");
   StringReplace(text, "\\\"", "\"");
   return text;
}

string ExtractField(string response, string field)
{
   string key = field + ": ";
   int    s   = StringFind(response, key);
   if(s < 0) return "";
   s += StringLen(key);
   int e = StringFind(response, "\n", s);
   if(e < 0) e = StringLen(response);
   string val = StringSubstr(response, s, e - s);
   StringTrimRight(val);
   StringTrimLeft(val);
   return val;
}

//═══════════════════════════════════════════════════════════════════
//  RISK & POSITION MANAGEMENT
//═══════════════════════════════════════════════════════════════════

double CalculateLotSize(double slPips)
{
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt    = balance * Risk_Percent / 100.0;
   double tickVal    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   int    digits     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pip        = (digits == 3 || digits == 5) ? point * 10 : point;
   if(tickVal <= 0 || slPips <= 0) return Risk_MinLot;
   double pipMoney   = (tickVal / tickSz) * pip;
   double lot        = riskAmt / (slPips * pipMoney);
   return NormalizeLot(lot);
}

double NormalizeLot(double lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / step) * step;
   return MathMax(Risk_MinLot, MathMin(Risk_MaxLot, lot));
}

void ManageOpenPositions()
{
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pip    = ((digits == 3 || digits == 5) ? point * 10 : point);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != MagicNumber) continue;

      double open    = posInfo.PriceOpen();
      double sl      = posInfo.StopLoss();
      double tp      = posInfo.TakeProfit();
      ulong  ticket  = posInfo.Ticket();
      double profit  = posInfo.Profit();
      ENUM_POSITION_TYPE type = posInfo.PositionType();

      // --- Breakeven ---
      if(Risk_UseBreakEven)
      {
         double bePips = Risk_BEPips * pip;
         if(type == POSITION_TYPE_BUY  && bid >= open + bePips && sl < open)
            trade.PositionModify(ticket, open + _Point, tp);
         if(type == POSITION_TYPE_SELL && ask <= open - bePips && sl > open)
            trade.PositionModify(ticket, open - _Point, tp);
      }

      // --- Trailing Stop ---
      if(Risk_UseTrailStop)
      {
         double trailDist = Risk_TrailPips * pip;
         if(type == POSITION_TYPE_BUY)
         {
            double newSL = NormalizeDouble(bid - trailDist, digits);
            if(newSL > sl + pip) trade.PositionModify(ticket, newSL, tp);
         }
         if(type == POSITION_TYPE_SELL)
         {
            double newSL = NormalizeDouble(ask + trailDist, digits);
            if(sl == 0 || newSL < sl - pip) trade.PositionModify(ticket, newSL, tp);
         }
      }
   }
}

int CountOpenTrades()
{
   int n = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==_Symbol && posInfo.Magic()==MagicNumber)
         n++;
   return n;
}

bool HasOpenPosition(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==_Symbol && posInfo.Magic()==MagicNumber && posInfo.PositionType()==type)
         return true;
   return false;
}

void CloseAllPositions()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==_Symbol && posInfo.Magic()==MagicNumber)
         trade.PositionClose(posInfo.Ticket());
}

//═══════════════════════════════════════════════════════════════════
//  TRADE RESULT TRACKING
//═══════════════════════════════════════════════════════════════════

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong dealTicket = trans.deal;
      if(HistoryDealSelect(dealTicket))
      {
         double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
         if(profit != 0)
         {
            totalProfitLoss += profit;
            if(profit > 0) winTrades++;
            else           lossTrades++;
            Print("💰 Deal closed | P&L: $", DoubleToString(profit, 2), " | Total: $", DoubleToString(totalProfitLoss, 2));
         }
      }
   }
}

//═══════════════════════════════════════════════════════════════════
//  SESSION & TIME FILTER
//═══════════════════════════════════════════════════════════════════

bool IsValidSession()
{
   MqlDateTime t; TimeToStruct(TimeGMT(), t);
   int hour = t.hour;
   // London: 08:00–17:00 GMT
   if(Session_London  && hour >= 8  && hour < 17)  return true;
   // New York: 13:00–22:00 GMT
   if(Session_NewYork && hour >= 13 && hour < 22)  return true;
   // Tokyo: 00:00–09:00 GMT
   if(Session_Tokyo   && (hour >= 0  && hour < 9)) return true;
   // Sydney: 22:00–07:00 GMT
   if(Session_Sydney  && (hour >= 22 || hour < 7)) return true;
   return false;
}

string GetCurrentSession()
{
   MqlDateTime t; TimeToStruct(TimeGMT(), t);
   int hour = t.hour;
   string sessions = "";
   if(hour >= 8  && hour < 17)  sessions += "London ";
   if(hour >= 13 && hour < 22)  sessions += "New York ";
   if(hour >= 0  && hour < 9)   sessions += "Tokyo ";
   if(hour >= 22 || hour < 7)   sessions += "Sydney ";
   return sessions == "" ? "Off-hours" : sessions;
}

//═══════════════════════════════════════════════════════════════════
//  DASHBOARD (Chart Objects)
//═══════════════════════════════════════════════════════════════════

void DrawDashboard()
{
   if(!Log_ShowDashboard) return;
   // Background panel
   ObjectCreate(0, "RB_Panel", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "RB_Panel", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "RB_Panel", OBJPROP_YDISTANCE, 30);
   ObjectSetInteger(0, "RB_Panel", OBJPROP_XSIZE, 300);
   ObjectSetInteger(0, "RB_Panel", OBJPROP_YSIZE, 290);
   ObjectSetInteger(0, "RB_Panel", OBJPROP_BGCOLOR, Log_PanelColor);
   ObjectSetInteger(0, "RB_Panel", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, "RB_Panel", OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, "RB_Panel", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "RB_Panel", OBJPROP_CORNER, CORNER_LEFT_UPPER);

   CreateLabel("RB_Title",  "⚡ THE GREAT RAYBOT v3.0",  15, 38,  14, clrGold);
   CreateLabel("RB_Sub",    "Powered by Claude AI",       15, 56,  10, clrSkyBlue);
   CreateLabel("RB_Sep1",   "══════════════════════════", 15, 70,   9, clrDimGray);
   CreateLabel("RB_L1",     "Symbol  :",                  15, 84,  10, clrSilver);
   CreateLabel("RB_L2",     "Session :",                  15, 100, 10, clrSilver);
   CreateLabel("RB_L3",     "Signal  :",                  15, 116, 10, clrSilver);
   CreateLabel("RB_L4",     "Reason  :",                  15, 132, 10, clrSilver);
   CreateLabel("RB_L5",     "Balance :",                  15, 148, 10, clrSilver);
   CreateLabel("RB_L6",     "Equity  :",                  15, 164, 10, clrSilver);
   CreateLabel("RB_L7",     "P&L     :",                  15, 180, 10, clrSilver);
   CreateLabel("RB_L8",     "Trades  :",                  15, 196, 10, clrSilver);
   CreateLabel("RB_L9",     "Win Rate:",                  15, 212, 10, clrSilver);
   CreateLabel("RB_L10",    "Status  :",                  15, 228, 10, clrSilver);
   CreateLabel("RB_Sep2",   "══════════════════════════", 15, 244,  9, clrDimGray);
   CreateLabel("RB_Footer", "🌍 Trading Worldwide",        15, 256, 10, clrGold);

   UpdateDashboard();
}

void UpdateDashboard()
{
   if(!Log_ShowDashboard) return;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double wr      = totalTrades > 0 ? (100.0 * winTrades / totalTrades) : 0;
   color  sigCol  = lastSignal == "BUY" ? clrLimeGreen : (lastSignal == "SELL" ? clrTomato : clrYellow);
   color  pnlCol  = totalProfitLoss >= 0 ? clrLimeGreen : clrTomato;
   string status  = tradingPaused ? "⛔ PAUSED" : "✅ ACTIVE";
   color  statCol = tradingPaused ? clrTomato : clrLimeGreen;

   string reason  = lastReason;
   if(StringLen(reason) > 28) reason = StringSubstr(reason, 0, 28) + "...";

   UpdateLabel("RB_V1",  _Symbol + " [" + EnumToString(TF_Primary) + "]",         90, 84,  10, clrWhite);
   UpdateLabel("RB_V2",  GetCurrentSession(),                                      90, 100, 10, clrCyan);
   UpdateLabel("RB_V3",  lastSignal + " (" + lastAIComment + ")",                  90, 116, 10, sigCol);
   UpdateLabel("RB_V4",  reason,                                                   90, 132,  9, clrLightGray);
   UpdateLabel("RB_V5",  "$" + DoubleToString(balance, 2),                         90, 148, 10, clrWhite);
   UpdateLabel("RB_V6",  "$" + DoubleToString(equity, 2),                          90, 164, 10, clrWhite);
   UpdateLabel("RB_V7",  "$" + DoubleToString(totalProfitLoss, 2),                 90, 180, 10, pnlCol);
   UpdateLabel("RB_V8",  IntegerToString(totalTrades) + " (W:" + IntegerToString(winTrades) + " L:" + IntegerToString(lossTrades) + ")", 90, 196, 10, clrWhite);
   UpdateLabel("RB_V9",  DoubleToString(wr, 1) + "%",                              90, 212, 10, wr >= 50 ? clrLimeGreen : clrOrange);
   UpdateLabel("RB_V10", status,                                                   90, 228, 10, statCol);

   ChartRedraw();
}

void CreateLabel(string name, string text, int x, int y, int size, color clr)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString( 0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void UpdateLabel(string name, string text, int x, int y, int size, color clr)
{
   if(ObjectFind(0, name) < 0)
      CreateLabel(name, text, x, y, size, clr);
   else
   {
      ObjectSetString( 0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   }
}

//═══════════════════════════════════════════════════════════════════
//  JOURNAL
//═══════════════════════════════════════════════════════════════════

void InitJournal()
{
   int h = FileOpen(Log_JournalFile, FILE_WRITE|FILE_CSV|FILE_ANSI);
   if(h == INVALID_HANDLE) { Print("❌ Journal error: ", GetLastError()); return; }
   FileWrite(h,
      "DateTime","Symbol","Timeframe","Signal","LotSize",
      "SL_Pips","TP_Pips","Confidence","Balance","Equity",
      "Drawdown%","OpenTrades","Executed","Reason");
   FileClose(h);
   Print("✅ Journal: ", Log_JournalFile);
}

void WriteJournal(string signal, double lot, double sl, double tp,
                  string reason, string conf, bool executed)
{
   int h = FileOpen(Log_JournalFile, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI);
   if(h == INVALID_HANDLE) return;
   FileSeek(h, 0, SEEK_END);
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown = peakBalance > 0 ? (peakBalance - equity) / peakBalance * 100.0 : 0;
   FileWrite(h,
      TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES),
      _Symbol, EnumToString(TF_Primary),
      signal,
      DoubleToString(lot, 2),
      DoubleToString(sl, 1),
      DoubleToString(tp, 1),
      conf,
      DoubleToString(balance, 2),
      DoubleToString(equity, 2),
      DoubleToString(drawdown, 2),
      IntegerToString(CountOpenTrades()),
      executed ? "YES" : "NO",
      reason);
   FileClose(h);
}
//+------------------------------------------------------------------+
