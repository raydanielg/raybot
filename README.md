# AI-Powered XAUUSD Scalping System

## System Architecture Documentation

This document describes the high-level architecture, responsibilities, data flow, trading loop, risk behavior, and operational structure of the AI-powered XAUUSD scalping system.

---

## 1. High-Level Architecture

The system is designed in three main layers:

```text
┌─────────────────────────────────────────────────────────┐
│                    LAYER 1: AI BRAIN                    │
│                      Claude API                         │
│                                                         │
│  - Market analysis                                      │
│  - Signal generation                                    │
│  - Confidence scoring                                   │
└─────────────────────────────────────────────────────────┘
                            ↕
┌─────────────────────────────────────────────────────────┐
│                  LAYER 2: BRIDGE                        │
│                  Python Middleware                      │
│                                                         │
│  - Data formatting                                      │
│  - API communication                                    │
│  - Logging and state management                         │
└─────────────────────────────────────────────────────────┘
                            ↕
┌─────────────────────────────────────────────────────────┐
│                  LAYER 3: EXECUTION                     │
│                      MT5 EA                             │
│                                                         │
│  - Order execution                                      │
│  - Risk management                                      │
│  - Position tracking                                    │
└─────────────────────────────────────────────────────────┘
```

---

## 2. Data Flow

```text
MT5 Market Data → Python Bridge → Claude API → Decision → Python Bridge → MT5 Execution → Result → Back to Claude
```

| Step | Component | Action |
|---|---|---|
| 1 | MT5 EA | Collects price, volume, and indicator data |
| 2 | Python Bridge | Formats market data into JSON |
| 3 | Claude API | Analyzes the market and returns BUY, SELL, or HOLD |
| 4 | Python Bridge | Receives, validates, and stores the signal |
| 5 | MT5 EA | Executes the trade with SL and TP |
| 6 | System | Monitors open positions and updates equity |
| 7 | Loop | Repeats every minute during valid trading sessions |

---

## 3. Project Structure

Current project structure:

```text
raybot/
├── python_bridge/             # Python middleware layer
│   ├── main.py                # Main runtime entry point
│   ├── market_analyzer.py     # Market data analysis and formatting
│   ├── trade_executor.py      # Trade execution coordination
│   └── claude_client.py       # Claude API communication
│
├── mt5_ea/                    # MT5 execution layer
│   ├── XAUUSD_Scalper.mq5     # Main Expert Advisor
│   ├── OrderManager.mqh       # Order handling helpers
│   └── RiskManager.mqh        # Risk management helpers
│
├── data/                      # Shared runtime data
│   └── signals.json           # AI-generated trading signal data
│
├── logs/                      # Runtime logs
│   ├── trading.log            # Trading activity log
│   └── errors.log             # Error log
│
├── config/                    # Configuration files
├── .env                       # Secret credentials and account settings
├── run.bat                    # Windows launcher script
└── venv/                      # Python virtual environment
```

---

## 4. Component Responsibilities

### Brain: Claude API

| Responsibility | Description |
|---|---|
| Analyze trend | Checks trend structure, such as EMA 50 vs EMA 200 |
| Find liquidity | Identifies stop-hunt and liquidity zones |
| Measure volatility | Uses volatility indicators such as ATR |
| Score setup | Produces a confidence score from 0 to 100 |
| Output decision | Returns BUY, SELL, or HOLD |

### Bridge: Python

| Responsibility | Description |
|---|---|
| Fetch MT5 data | Gets latest candles, price, and indicators |
| Format to JSON | Prepares clean structured data for Claude |
| Send to Claude | Sends market context through an authenticated API request |
| Receive signal | Parses Claude's response |
| Validate signal | Checks confidence, session rules, spread, and risk limits |
| Forward to MT5 | Writes valid signals into a shared file |
| Log everything | Saves actions, errors, and AI decisions |

### Execution: MT5 EA

| Responsibility | Description |
|---|---|
| Read signal | Monitors signal data from the shared file |
| Calculate lot size | Applies equity and risk-based position sizing |
| Open trade | Executes market orders |
| Set SL/TP | Applies fixed or dynamic stop loss and take profit levels |
| Track positions | Enforces max open trade rules |
| Update equity | Writes account and position status back for Python |

---

## 5. Communication Method

The system uses file-based communication between Python and MT5.

```text
Python Bridge                    MT5 EA
     │                              │
     │  1. Write signal to file     │
     ├─────────────────────────────→│
     │        signal.json           │
     │                              │
     │  2. EA reads signal file     │
     │←─────────────────────────────┤
     │                              │
     │  3. EA executes trade        │
     │                              │
     │  4. EA writes equity file    │
     │←─────────────────────────────┤
     │        equity.json           │
     │                              │
     │  5. Bridge reads equity      │
     ├─────────────────────────────→│
```

This approach is simple, local, reliable, easy to debug, and avoids unnecessary socket or networking complexity.

---

## 6. Trading Loop

```text
START
  │
  ▼
Check trading session: London or New York?
  │
  ├── NO → Wait 5 minutes
  │
  └── YES
       │
       ▼
Collect market data: price, EMA, ATR, volume
       │
       ▼
Send data to Claude AI
       │
       ▼
Receive decision
       │
       ▼
Confidence > 70%?
       │
       ├── NO → Do nothing and wait
       │
       └── YES
            │
            ▼
Check active trades < 3
            │
            ├── NO → Wait for existing trades to close
            │
            └── YES
                 │
                 ▼
Calculate lot size
                 │
                 ▼
Execute BUY or SELL
                 │
                 ▼
Set SL and TP
                 │
                 ▼
Monitor trade until closed
                 │
                 ▼
Update equity and scaling state
                 │
                 ▼
Repeat
```

---

## 7. Scaling Logic

| Equity Level | Lot Size | Max Trades | Risk Style |
|---|---:|---:|---|
| $500 - $550 | 0.01 | 3 | Conservative |
| $551 - $625 | 0.02 | 3 | Moderate |
| $626 - $700 | 0.03 | 3 | Aggressive |
| $701 - $800 | 0.04 | 3 | Very aggressive |
| $800+ | 0.05+ | 3 | Profit lock and controlled scaling |

Formula:

```text
Lot = Base_Lot × (Current_Equity / Starting_Equity)
```

Scaling should only happen after a winning trade and should not increase during a losing streak.

---

## 8. Runtime Files and Purpose

| File | Purpose | Read/Write By |
|---|---|---|
| `data/market.json` | Latest price and indicator data | Python writes, Claude receives context |
| `data/signals.json` | Claude trading decision | Python writes, MT5 reads |
| `data/equity.json` | Current account balance and equity | MT5 writes, Python reads |
| `logs/trading.log` | Trading activity | Python and MT5 append |
| `logs/errors.log` | Runtime errors | Python and MT5 append |
| `logs/ai_decisions.log` | Claude responses and confidence scores | Python writes |
| `config/settings.json` | Risk limits and session rules | Python and MT5 read |
| `config/strategy.json` | EMA, ATR, and strategy settings | Python and MT5 read |

---

## 9. System States

| State | Trigger | Action |
|---|---|---|
| Normal | Equity is above starting balance | Trade normally and allow scaling |
| Caution | 5% loss within 1 hour | Reduce lot size by 50% |
| Stop | 10% daily loss | Stop trading and alert user |
| Boost | 15% daily gain | Increase lot size by 25% if rules allow |
| Hibernate | Outside London or New York sessions | Do not trade; monitor only |

---

## 10. Error Handling and Fail Safes

| Problem | Solution |
|---|---|
| Claude API unavailable | Retry after 1 minute and enter HOLD mode |
| MT5 disconnected | Reconnect attempts every 5 seconds |
| Spread too high | Cancel trade and wait before retrying |
| No Claude signal for 5 minutes | Enter HOLD mode and log warning |
| Equity drops below emergency level | Stop all trading immediately |

---

## 11. Performance Metrics

| Metric | Measurement |
|---|---|
| Win rate | Winning trades ÷ total trades × 100 |
| Profit factor | Gross profit ÷ gross loss |
| Average win | Total winning profit ÷ number of wins |
| Average loss | Total losing amount ÷ number of losses |
| Sharpe ratio | Return ÷ risk over a selected period |
| Drawdown | Peak-to-trough equity decline |
| Claude accuracy | Profitable AI signals ÷ total AI signals |

---

## 12. Startup Sequence

```text
1. Check that .env contains required credentials
2. Connect to MT5 and verify login
3. Load config files
4. Read current equity
5. Calculate starting lot size
6. Enter main loop
7. Wait for valid trading session
8. Start analysis and signal generation
```

---

## 13. Shutdown Sequence

```text
1. Stop accepting new signals
2. Manage or close open positions according to shutdown policy
3. Save final equity snapshot
4. Write end-of-session log
5. Disconnect from MT5
6. Exit gracefully
```

---

## Summary

| Layer | Technology | Role |
|---|---|---|
| Brain | Claude API | Analyzes and decides |
| Bridge | Python | Connects, validates, logs, and translates |
| Execution | MT5 and MQL5 | Executes and manages trades |
| Storage | JSON and log files | Persists signals, state, and history |

Core operating model:

- **Communication:** File-based JSON communication
- **Frequency:** One analysis cycle per minute
- **Market:** XAUUSD
- **Style:** Scalping
- **Growth target:** 3× equity
- **Max concurrent trades:** 3
- **Risk per trade:** 0.5% to 1%
