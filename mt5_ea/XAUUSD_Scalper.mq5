#property strict

#include <Trade\Trade.mqh>

input string InpSymbol = "XAUUSD";
input ENUM_TIMEFRAMES InpAtrTimeframe = PERIOD_M1;
input int InpAtrPeriod = 14;
input int InpRsiPeriod = 14;
input string InpOutputFile = "market_tick.json";
input string InpOrderRequestFile = "order_request.latest.json";
input string InpOrderResponseFile = "order_response.latest.json";
input bool InpUseCommonFiles = true;
input int InpTradeDeviationPoints = 50;
input long InpMagicNumber = 260515;
input bool InpUseClaudeDirect = false;
input string InpAnthropicApiKey = "";
input string InpClaudeModel = "claude-sonnet-4-6";
input int InpClaudeTimeoutMs = 7000;
input int InpClaudeMaxTokens = 64;
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_M1;
input bool InpOnlyOnNewBar = true;
input double InpClaudeLotSize = 0.01;

// Safety Guardrails
input int InpMaxOpenPositions = 3;
input int InpTradeCooldownSeconds = 60;
input int InpMaxSpreadPoints = 50;

int g_atr_handle = INVALID_HANDLE;
int g_rsi_handle = INVALID_HANDLE;
string g_last_processed_request_id = "";
datetime g_last_claude_bar_time = 0;
datetime g_last_trade_time = 0;
int g_open_position_count = 0;

int BuildFileFlags(const int base_flags)
{
	int flags = base_flags | FILE_TXT | FILE_ANSI;
	if(InpUseCommonFiles)
		flags |= FILE_COMMON;
	return flags;
}

bool ReadTextFile(const string file_name, string &content)
{
	const int file_handle = FileOpen(file_name, BuildFileFlags(FILE_READ));
	if(file_handle == INVALID_HANDLE)
		return false;

	content = "";
	while(!FileIsEnding(file_handle))
	{
		content += FileReadString(file_handle);
		if(!FileIsEnding(file_handle))
			content += "\n";
	}

	FileClose(file_handle);
	return StringLen(content) > 0;
}

bool WriteTextFile(const string file_name, const string content)
{
	const int file_handle = FileOpen(file_name, BuildFileFlags(FILE_WRITE));
	if(file_handle == INVALID_HANDLE)
	{
		Print("FileOpen failed for ", file_name, ", error=", GetLastError());
		return false;
	}

	FileWriteString(file_handle, content);
	FileClose(file_handle);
	return true;
}

int SkipJsonWhitespace(const string text, int pos)
{
	const int text_len = StringLen(text);
	while(pos < text_len)
	{
		const int ch = StringGetCharacter(text, pos);
		if(ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n')
			break;
		pos++;
	}
	return pos;
}

bool JsonReadString(const string json, const string key, string &value)
{
	const string pattern = StringFormat("\"%s\"", key);
	const int key_pos = StringFind(json, pattern);
	if(key_pos < 0)
		return false;

	const int colon_pos = StringFind(json, ":", key_pos + StringLen(pattern));
	if(colon_pos < 0)
		return false;

	int start = SkipJsonWhitespace(json, colon_pos + 1);
	if(start >= StringLen(json) || StringGetCharacter(json, start) != '"')
		return false;

	start++;
	int end = start;
	while(end < StringLen(json))
	{
		const int ch = StringGetCharacter(json, end);
		if(ch == '"' && StringGetCharacter(json, end - 1) != '\\')
			break;
		end++;
	}

	if(end >= StringLen(json))
		return false;

	value = StringSubstr(json, start, end - start);
	return true;
}

bool JsonReadNumber(const string json, const string key, double &value)
{
	const string pattern = StringFormat("\"%s\"", key);
	const int key_pos = StringFind(json, pattern);
	if(key_pos < 0)
		return false;

	const int colon_pos = StringFind(json, ":", key_pos + StringLen(pattern));
	if(colon_pos < 0)
		return false;

	int start = SkipJsonWhitespace(json, colon_pos + 1);
	int end = start;
	while(end < StringLen(json))
	{
		const int ch = StringGetCharacter(json, end);
		if(ch == ',' || ch == '}' || ch == '\n' || ch == '\r')
			break;
		end++;
	}

	if(end <= start)
		return false;

	string token = StringSubstr(json, start, end - start);
	StringTrimLeft(token);
	StringTrimRight(token);
	if(StringLen(token) == 0)
		return false;

	value = StringToDouble(token);
	return true;
}

string EscapeJsonString(const string source)
{
	string out = source;
	StringReplace(out, "\\", "\\\\");
	StringReplace(out, "\"", "\\\"");
	StringReplace(out, "\n", " ");
	StringReplace(out, "\r", " ");
	return out;
}

string UnescapeJsonString(const string source)
{
	string out = source;
	StringReplace(out, "\\n", " ");
	StringReplace(out, "\\r", " ");
	StringReplace(out, "\\t", " ");
	StringReplace(out, "\\\"", "\"");
	StringReplace(out, "\\\\", "\\");
	return out;
}

bool JsonReadQuotedValueAt(const string json, const int first_quote_pos, string &value_out, int &next_pos)
{
	if(first_quote_pos < 0 || first_quote_pos >= StringLen(json))
		return false;
	if(StringGetCharacter(json, first_quote_pos) != '"')
		return false;

	const int start = first_quote_pos + 1;
	int end = start;
	while(end < StringLen(json))
	{
		if(StringGetCharacter(json, end) == '"')
		{
			int slash_count = 0;
			int check = end - 1;
			while(check >= start && StringGetCharacter(json, check) == '\\')
			{
				slash_count++;
				check--;
			}
			if((slash_count % 2) == 0)
				break;
		}
		end++;
	}

	if(end >= StringLen(json) || end <= start)
		return false;

	value_out = UnescapeJsonString(StringSubstr(json, start, end - start));
	next_pos = end + 1;
	return true;
}

bool ExtractJsonStringValuesByKey(const string json, const string key, string &joined_values)
{
	joined_values = "";
	const string pattern = StringFormat("\"%s\"", key);
	int search_pos = 0;
	bool found_any = false;

	while(true)
	{
		const int key_pos = StringFind(json, pattern, search_pos);
		if(key_pos < 0)
			break;

		const int colon_pos = StringFind(json, ":", key_pos + StringLen(pattern));
		if(colon_pos < 0)
			break;

		int value_start = SkipJsonWhitespace(json, colon_pos + 1);
		if(value_start >= StringLen(json) || StringGetCharacter(json, value_start) != '"')
		{
			search_pos = key_pos + StringLen(pattern);
			continue;
		}

		string chunk = "";
		int next_pos = value_start;
		if(JsonReadQuotedValueAt(json, value_start, chunk, next_pos))
		{
			StringTrimLeft(chunk);
			StringTrimRight(chunk);
			if(StringLen(chunk) > 0)
			{
				if(StringLen(joined_values) > 0)
					joined_values += " ";
				joined_values += chunk;
				found_any = true;
			}
			search_pos = next_pos;
		}
		else
		{
			search_pos = key_pos + StringLen(pattern);
		}
	}

	return found_any;
}

bool ParseClaudeResponseText(const string json, string &text_out)
{
	text_out = "";

	if(ExtractJsonStringValuesByKey(json, "text", text_out))
		return true;

	if(ExtractJsonStringValuesByKey(json, "output_text", text_out))
		return true;

	if(ExtractJsonStringValuesByKey(json, "completion", text_out))
		return true;

	if(ExtractJsonStringValuesByKey(json, "content", text_out))
		return true;

	return false;
}

bool IsWordChar(const int ch)
{
	if(ch >= 'A' && ch <= 'Z')
		return true;
	if(ch >= '0' && ch <= '9')
		return true;
	return ch == '_';
}

bool IsStandaloneWordAt(const string text, const int pos, const string word)
{
	if(pos < 0)
		return false;
	if(StringSubstr(text, pos, StringLen(word)) != word)
		return false;

	const int before = pos - 1;
	const int after = pos + StringLen(word);
	if(before >= 0 && IsWordChar(StringGetCharacter(text, before)))
		return false;
	if(after < StringLen(text) && IsWordChar(StringGetCharacter(text, after)))
		return false;

	return true;
}

int FindStandaloneWordPosition(const string text, const string word)
{
	int search_pos = 0;
	while(true)
	{
		const int pos = StringFind(text, word, search_pos);
		if(pos < 0)
			return -1;
		if(IsStandaloneWordAt(text, pos, word))
			return pos;
		search_pos = pos + 1;
	}
}

bool ContainsNegatedWord(const string text, const string word)
{
	if(FindStandaloneWordPosition(text, "NOT " + word) >= 0)
		return true;
	if(FindStandaloneWordPosition(text, "DO NOT " + word) >= 0)
		return true;
	if(FindStandaloneWordPosition(text, "DONT " + word) >= 0)
		return true;
	if(FindStandaloneWordPosition(text, "DON T " + word) >= 0)
		return true;
	if(FindStandaloneWordPosition(text, "NO " + word) >= 0)
		return true;

	return false;
}

string ExtractTradingSignal(const string response_text)
{
	string upper = response_text;
	StringToUpper(upper);
	StringReplace(upper, "\n", " ");
	StringReplace(upper, "\r", " ");
	StringReplace(upper, "\t", " ");
	StringReplace(upper, ".", " ");
	StringReplace(upper, ",", " ");
	StringReplace(upper, ";", " ");
	StringReplace(upper, ":", " ");
	StringReplace(upper, "!", " ");
	StringReplace(upper, "?", " ");
	StringReplace(upper, "(", " ");
	StringReplace(upper, ")", " ");
	StringReplace(upper, "[", " ");
	StringReplace(upper, "]", " ");
	StringReplace(upper, "{", " ");
	StringReplace(upper, "}", " ");
	StringReplace(upper, "\"", " ");
	StringReplace(upper, "'", " ");

	const int buy_pos = FindStandaloneWordPosition(upper, "BUY");
	const int sell_pos = FindStandaloneWordPosition(upper, "SELL");
	const int hold_pos = FindStandaloneWordPosition(upper, "HOLD");

	const bool buy_valid = (buy_pos >= 0 && !ContainsNegatedWord(upper, "BUY"));
	const bool sell_valid = (sell_pos >= 0 && !ContainsNegatedWord(upper, "SELL"));
	const bool hold_valid = (hold_pos >= 0 && !ContainsNegatedWord(upper, "HOLD"));

	const int valid_count = (buy_valid ? 1 : 0) + (sell_valid ? 1 : 0) + (hold_valid ? 1 : 0);
	if(valid_count == 1)
	{
		if(buy_valid)
			return "BUY";
		if(sell_valid)
			return "SELL";
		return "HOLD";
	}

	if(valid_count > 1)
	{
		int best_pos = 2147483647;
		string best_signal = "";
		if(buy_valid && buy_pos < best_pos)
		{
			best_pos = buy_pos;
			best_signal = "BUY";
		}
		if(sell_valid && sell_pos < best_pos)
		{
			best_pos = sell_pos;
			best_signal = "SELL";
		}
		if(hold_valid && hold_pos < best_pos)
		{
			best_pos = hold_pos;
			best_signal = "HOLD";
		}
		if(StringLen(best_signal) > 0)
			return best_signal;
	}

	return "";
}

bool IsNewSignalBar()
{
	datetime current_bar = iTime(InpSymbol, InpSignalTimeframe, 0);
	if(current_bar <= 0)
		return false;

	if(current_bar == g_last_claude_bar_time)
		return false;

	g_last_claude_bar_time = current_bar;
	return true;
}

string BuildClaudePrompt()
{
	const double close_1 = iClose(InpSymbol, InpSignalTimeframe, 1);
	const double close_2 = iClose(InpSymbol, InpSignalTimeframe, 2);
	const double rsi = ReadLatestFromHandle(g_rsi_handle);
	const double atr = ReadLatestFromHandle(g_atr_handle);
	const long spread = SymbolInfoInteger(InpSymbol, SYMBOL_SPREAD);

	const string prompt =
		"You are a forex trading assistant. Analyze this data and reply with ONLY one word: BUY, SELL, or HOLD.\\n"
		"Symbol: " + InpSymbol + "\\n"
		"Last close: " + DoubleToString(close_1, _Digits) + "\\n"
		"Previous close: " + DoubleToString(close_2, _Digits) + "\\n"
		"RSI(" + IntegerToString(InpRsiPeriod) + "): " + DoubleToString(rsi, 2) + "\\n"
		"ATR(" + IntegerToString(InpAtrPeriod) + "): " + DoubleToString(atr, _Digits) + "\\n"
		"Spread: " + IntegerToString((int)spread) + " points";

	return prompt;
}

bool AskClaude(const string prompt, string &raw_response, string &signal)
{
	if(StringLen(InpAnthropicApiKey) < 10)
	{
		Print("Claude direct mode enabled but API key is empty.");
		return false;
	}

	const string url = "https://api.anthropic.com/v1/messages";
	const string headers =
		"x-api-key: " + InpAnthropicApiKey + "\r\n"
		"anthropic-version: 2023-06-01\r\n"
		"content-type: application/json\r\n";

	const string payload =
		"{"
		"\"model\":\"" + EscapeJsonString(InpClaudeModel) + "\"," 
		"\"max_tokens\":" + IntegerToString(MathMax(32, InpClaudeMaxTokens)) + ","
		"\"messages\":[{"
		"\"role\":\"user\","
		"\"content\":\"" + EscapeJsonString(prompt) + "\""
		"}]"
		"}";

	char post_data[];
	char result_data[];
	string response_headers;

	StringToCharArray(payload, post_data, 0, WHOLE_ARRAY, CP_UTF8);
	if(ArraySize(post_data) > 0)
		ArrayResize(post_data, ArraySize(post_data) - 1);

	ResetLastError();
	const int code = WebRequest(
		"POST",
		url,
		headers,
		MathMax(1000, InpClaudeTimeoutMs),
		post_data,
		result_data,
		response_headers
	);

	if(code != 200)
	{
		Print("Claude API error. HTTP=", code, ", last_error=", GetLastError());
		return false;
	}

	raw_response = CharArrayToString(result_data, 0, -1, CP_UTF8);
	string text = "";
	if(!ParseClaudeResponseText(raw_response, text))
	{
		Print("Claude response parse failed.");
		return false;
	}

	signal = ExtractTradingSignal(text);
	return StringLen(signal) > 0;
}

void RunClaudeDirectMode()
{
	if(!InpUseClaudeDirect)
		return;

	if(InpOnlyOnNewBar && !IsNewSignalBar())
		return;

	const string prompt = BuildClaudePrompt();
	string raw_response = "";
	string signal = "";

	if(!AskClaude(prompt, raw_response, signal))
		return;

	Print("Claude signal: ", signal);

	if(signal == "BUY" || signal == "SELL")
	{
		// Apply guardrails before executing order
		g_open_position_count = CountOpenPositions();
		
		if(g_open_position_count >= InpMaxOpenPositions)
		{
			Print("BLOCKED: Max open positions (", InpMaxOpenPositions, ") reached. Current: ", g_open_position_count);
			return;
		}
		
		if(IsInCooldown())
		{
			Print("BLOCKED: Trade cooldown active");
			return;
		}
		
		if(!CheckSpreadValid())
		{
			Print("BLOCKED: Spread too wide for trade");
			return;
		}
		
		const string request_id = "claude-" + IntegerToString((int)TimeCurrent());
		ExecuteOrderRequest(request_id, signal, InpClaudeLotSize, 0.0, 0.0);
		g_last_trade_time = TimeCurrent();
	}
}

// === GUARDRAIL FUNCTIONS ===

int CountOpenPositions()
{
	int count = 0;
	for(int i = 0; i < PositionsTotal(); i++)
	{
		if(PositionSelectByTicket(i))
		{
			if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
				count++;
		}
	}
	return count;
}

bool CheckSpreadValid()
{
	MqlTick tick;
	if(!SymbolInfoTick(InpSymbol, tick))
		return false;
	
	const int current_spread = (int)(tick.ask - tick.bid) / SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
	if(current_spread > InpMaxSpreadPoints)
	{
		Print("WARNING: Spread too wide: ", current_spread, " > ", InpMaxSpreadPoints);
		return false;
	}
	return true;
}

bool IsInCooldown()
{
	const datetime time_since_last = TimeCurrent() - g_last_trade_time;
	if(time_since_last < InpTradeCooldownSeconds)
	{
		Print("INFO: Trade cooldown active. Seconds remaining: ", InpTradeCooldownSeconds - time_since_last);
		return true;
	}
	return false;
}

ENUM_ORDER_TYPE_FILLING ResolveFillingMode()
{
	long filling_mode = 0;
	if(!SymbolInfoInteger(InpSymbol, SYMBOL_FILLING_MODE, filling_mode))
		return ORDER_FILLING_FOK;

	if((filling_mode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
		return ORDER_FILLING_IOC;
	if((filling_mode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
		return ORDER_FILLING_FOK;
	return ORDER_FILLING_RETURN;
}

void WriteOrderResponse(
	const string request_id,
	const string status,
	const string message,
	const ulong order_ticket,
	const ulong deal_ticket,
	const uint retcode
)
{
	const string safe_message = EscapeJsonString(message);

	const string payload = StringFormat(
		"{\n"
		"  \"request_id\": \"%s\",\n"
		"  \"symbol\": \"%s\",\n"
		"  \"status\": \"%s\",\n"
		"  \"message\": \"%s\",\n"
		"  \"order_ticket\": %I64u,\n"
		"  \"deal_ticket\": %I64u,\n"
		"  \"retcode\": %u,\n"
		"  \"processed_at\": \"%s\"\n"
		"}\n",
		request_id,
		InpSymbol,
		status,
		safe_message,
		order_ticket,
		deal_ticket,
		retcode,
		FormatIsoUtc(TimeGMT())
	);

	WriteTextFile(InpOrderResponseFile, payload);
}

bool ExecuteOrderRequest(
	const string request_id,
	const string side,
	const double volume,
	const double stop_loss,
	const double take_profit
)
{
	MqlTick tick;
	if(!SymbolInfoTick(InpSymbol, tick))
	{
		WriteOrderResponse(request_id, "REJECTED", "SymbolInfoTick failed", 0, 0, 0);
		return false;
	}

	string side_upper = side;
	StringToUpper(side_upper);

	MqlTradeRequest request;
	MqlTradeResult result;
	ZeroMemory(request);
	ZeroMemory(result);

	request.action = TRADE_ACTION_DEAL;
	request.symbol = InpSymbol;
	request.magic = InpMagicNumber;
	request.deviation = InpTradeDeviationPoints;
	request.type_filling = ResolveFillingMode();
	request.type_time = ORDER_TIME_GTC;
	request.volume = MathMax(0.01, volume);
	request.sl = stop_loss;
	request.tp = take_profit;
	request.comment = "raybot:" + StringSubstr(request_id, 0, 20);

	if(side_upper == "BUY")
	{
		request.type = ORDER_TYPE_BUY;
		request.price = tick.ask;
	}
	else if(side_upper == "SELL")
	{
		request.type = ORDER_TYPE_SELL;
		request.price = tick.bid;
	}
	else
	{
		WriteOrderResponse(request_id, "IGNORED", "Unsupported side", 0, 0, 0);
		return false;
	}

	const bool submitted = OrderSend(request, result);
	if(!submitted)
	{
		WriteOrderResponse(request_id, "REJECTED", "OrderSend failed", result.order, result.deal, result.retcode);
		return false;
	}

	if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_DONE_PARTIAL)
	{
		WriteOrderResponse(request_id, "FILLED", result.comment, result.order, result.deal, result.retcode);
		return true;
	}

	WriteOrderResponse(request_id, "REJECTED", result.comment, result.order, result.deal, result.retcode);
	return false;
}

void ProcessLatestOrderRequest()
{
	string content;
	if(!ReadTextFile(InpOrderRequestFile, content))
		return;

	string request_id;
	string request_symbol;
	string side;
	double volume = 0.0;
	double stop_loss = 0.0;
	double take_profit = 0.0;

	if(!JsonReadString(content, "request_id", request_id))
		return;
	if(!JsonReadString(content, "symbol", request_symbol))
		return;
	if(!JsonReadString(content, "side", side))
		return;
	if(!JsonReadNumber(content, "volume", volume))
		return;

	JsonReadNumber(content, "stop_loss", stop_loss);
	JsonReadNumber(content, "take_profit", take_profit);

	if(request_id == g_last_processed_request_id)
		return;

	g_last_processed_request_id = request_id;

	if(request_symbol != InpSymbol)
	{
		WriteOrderResponse(request_id, "IGNORED", "Symbol mismatch", 0, 0, 0);
		return;
	}

	ExecuteOrderRequest(request_id, side, volume, stop_loss, take_profit);
}

string FormatIsoUtc(datetime when)
{
	MqlDateTime dt;
	TimeToStruct(when, dt);
	return StringFormat(
		"%04d-%02d-%02dT%02d:%02d:%02d+00:00",
		dt.year,
		dt.mon,
		dt.day,
		dt.hour,
		dt.min,
		dt.sec
	);
}

double ReadLatestFromHandle(const int handle)
{
	if(handle == INVALID_HANDLE)
		return 0.0;

	double values[];
	ArraySetAsSeries(values, true);
	if(CopyBuffer(handle, 0, 0, 1, values) != 1)
		return 0.0;

	return values[0];
}

double BuildMomentumValue()
{
	// Normalize RSI into [-1, 1] to match bridge expectations.
	const double rsi = ReadLatestFromHandle(g_rsi_handle);
	double momentum = (rsi - 50.0) / 50.0;
	if(momentum > 1.0)
		momentum = 1.0;
	if(momentum < -1.0)
		momentum = -1.0;
	return momentum;
}

bool WriteMarketTickJson()
{
	MqlTick tick;
	if(!SymbolInfoTick(InpSymbol, tick))
	{
		Print("SymbolInfoTick failed for ", InpSymbol, ", error=", GetLastError());
		return false;
	}

	const double atr = ReadLatestFromHandle(g_atr_handle);
	const double momentum = BuildMomentumValue();
	const string timestamp = FormatIsoUtc(TimeGMT());

	const string payload = StringFormat(
		"{\n"
		"  \"symbol\": \"%s\",\n"
		"  \"bid\": %.2f,\n"
		"  \"ask\": %.2f,\n"
		"  \"atr\": %.2f,\n"
		"  \"momentum\": %.3f,\n"
		"  \"timestamp\": \"%s\"\n"
		"}\n",
		InpSymbol,
		tick.bid,
		tick.ask,
		atr,
		momentum,
		timestamp
	);

	const int file_handle = FileOpen(InpOutputFile, BuildFileFlags(FILE_WRITE));
	if(file_handle == INVALID_HANDLE)
	{
		Print("FileOpen failed for ", InpOutputFile, ", error=", GetLastError());
		return false;
	}

	FileWriteString(file_handle, payload);
	FileClose(file_handle);
	return true;
}

int OnInit()
{
	g_atr_handle = iATR(InpSymbol, InpAtrTimeframe, InpAtrPeriod);
	if(g_atr_handle == INVALID_HANDLE)
	{
		Print("Failed to create ATR handle, error=", GetLastError());
		return INIT_FAILED;
	}

	g_rsi_handle = iRSI(InpSymbol, InpAtrTimeframe, InpRsiPeriod, PRICE_CLOSE);
	if(g_rsi_handle == INVALID_HANDLE)
	{
		Print("Failed to create RSI handle, error=", GetLastError());
		return INIT_FAILED;
	}

	Print("EA initialized. Tick feed file=", InpOutputFile, ", common=", InpUseCommonFiles);
	Print("Order request file=", InpOrderRequestFile, ", response file=", InpOrderResponseFile);
	if(InpUseClaudeDirect)
		Print("Claude direct mode enabled. Add https://api.anthropic.com to MT5 WebRequest allow-list.");
	return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
	if(g_atr_handle != INVALID_HANDLE)
		IndicatorRelease(g_atr_handle);
	if(g_rsi_handle != INVALID_HANDLE)
		IndicatorRelease(g_rsi_handle);
}

void OnTick()
{
	WriteMarketTickJson();
	ProcessLatestOrderRequest();
	RunClaudeDirectMode();
}
