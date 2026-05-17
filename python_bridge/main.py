from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import logging
import os
from pathlib import Path
import time

try:
    import MetaTrader5 as mt5
except ImportError:
    mt5 = None

from market_analyzer import MarketAnalyzer
from trade_executor import TradeExecutor
from strategy_engine import StrategyEngine


def parse_args() -> argparse.Namespace:
	parser = argparse.ArgumentParser(description="Raybot signal generation service")
	parser.add_argument("--symbol", default="XAUUSD", help="Trading symbol")
	parser.add_argument("--interval", type=int, default=10, help="Loop interval in seconds")
	parser.add_argument(
		"--lot-size",
		type=float,
		default=0.01,
		help="Lot size for emitted MT5 order requests",
	)
	parser.add_argument(
		"--strategy-id",
		default="raybot-v1",
		help="Strategy identifier embedded in order request payloads",
	)
	parser.add_argument(
		"--no-emit-orders",
		action="store_false",
		dest="emit_orders",
		help="Disable MT5 order request file emission",
	)
	parser.set_defaults(emit_orders=True)
	parser.add_argument(
		"--no-sync-acks",
		action="store_false",
		dest="sync_acks",
		help="Disable reconciliation from MT5 order response file",
	)
	parser.set_defaults(sync_acks=True)
	parser.add_argument(
		"--feed-file",
		default="data/market_tick.json",
		help="Path to MT5 JSON market feed file",
	)
	parser.add_argument(
		"--feed-max-age",
		type=int,
		default=5,
		help="Maximum accepted market feed age in seconds",
	)
	parser.add_argument(
		"--cycles",
		type=int,
		default=1,
		help="Number of iterations. Use 0 or negative for infinite loop.",
	)
	parser.add_argument(
		"--max-runtime-seconds",
		type=int,
		default=0,
		help="Maximum wall-clock runtime in seconds. Use 0 for unlimited runtime.",
	)
	parser.add_argument(
		"--signal-history-limit",
		type=int,
		default=400,
		help="Maximum number of signal records to keep in data/signals.json",
	)
	parser.add_argument(
		"--order-history-limit",
		type=int,
		default=400,
		help="Maximum number of order records to keep in data/order_requests.json",
	)
	parser.add_argument(
		"--ack-history-limit",
		type=int,
		default=4000,
		help="Maximum number of acknowledgement records to keep in data/order_response_history.jsonl",
	)
	return parser.parse_args()


def configure_error_log(root: Path) -> None:
	error_log = root / "logs" / "errors.log"
	error_log.parent.mkdir(parents=True, exist_ok=True)

	logger = logging.getLogger("raybot-errors")
	logger.setLevel(logging.ERROR)
	if not logger.handlers:
		logger.addHandler(logging.FileHandler(error_log))


def run() -> int:
	args = parse_args()
	root = Path(__file__).resolve().parents[1]
	feed_file = Path(args.feed_file)
	if not feed_file.is_absolute():
		feed_file = root / feed_file

	# Load configuration
	config_file = root / "config" / "settings.json"
	with open(config_file, "r", encoding="utf-8") as f:
		config = json.load(f)

	configure_error_log(root)
	
	logging.basicConfig(
		level=logging.INFO,
		format="%(asctime)s | %(levelname)s | %(message)s",
		handlers=[
			logging.FileHandler(root / "logs" / "trading.log"),
			logging.StreamHandler()
		]
	)
	logger = logging.getLogger(__name__)
	
	# Initialize MT5
	mt5_connected = False
	if mt5:
		try:
			from dotenv import load_dotenv
			load_dotenv(root / ".env")
			
			account = int(os.getenv("MT5_ACCOUNT", "0"))
			password = os.getenv("MT5_PASSWORD", "")
			server = os.getenv("MT5_SERVER", "")
			
			if account and password and server:
				if mt5.initialize(login=account, password=password, server=server):
					mt5_connected = True
					logger.info(f"MT5 connected to account {account}")
					
					# Enable symbol for trading
					if not mt5.symbol_select(args.symbol, True):
						logger.warning(f"Failed to select symbol {args.symbol}")
						# Try to find a tradable symbol
						symbols = mt5.symbols_get()
						if symbols:
							# Check all symbols for trade mode
							tradable_symbols = []
							for s in symbols:
								info = mt5.symbol_info(s.name)
								if info and info.trade_mode == mt5.SYMBOL_TRADE_MODE_FULL:
									tradable_symbols.append(s.name)
							
							logger.info(f"Tradable symbols (full trading): {tradable_symbols[:10]}")
							
							if tradable_symbols:
								# Use first tradable symbol
								args.symbol = tradable_symbols[0]
								if mt5.symbol_select(args.symbol, True):
									logger.info(f"Selected tradable symbol: {args.symbol}")
								else:
									logger.warning(f"Still failed to select {args.symbol}")
							else:
								logger.warning("No tradable symbols found")
								logger.info(f"Available symbols: {[s.name for s in symbols[:20]]}")
					else:
						logger.info(f"Successfully selected symbol: {args.symbol}")
				else:
					logger.warning(f"MT5 connection failed: {mt5.last_error()}")
			else:
				logger.warning("MT5 credentials not configured")
		except Exception as e:
			logger.warning(f"MT5 initialization error: {e}")
	
	analyzer = MarketAnalyzer(
		symbol=args.symbol,
		feed_file=feed_file,
		max_feed_age_seconds=args.feed_max_age,
	)
	executor = TradeExecutor(root)
	strategy_engine = StrategyEngine(config)

	logger.info(f"XAUUSD Scalper started at {datetime.utcnow().isoformat()}")

	cycle = 0
	started_at = time.monotonic()
	while True:
		cycle += 1
		if args.sync_acks:
			executor.reconcile_latest_order_response(
				max_history_records=max(0, args.ack_history_limit)
			)

		# Fetch market data
		snapshot = analyzer.fetch_market_snapshot()
		
		# Convert snapshot to dictionary for strategy engine
		from dataclasses import asdict
		market_data = asdict(snapshot)
		
		# Add additional fields needed by strategies
		market_data["ema_50"] = None  # Will be calculated or fetched
		market_data["ema_200"] = None  # Will be calculated or fetched
		
		# Analyze with strategy engine
		trading_signal = strategy_engine.analyze_market(market_data)
		
		# Store signal
		from market_analyzer import TradeSignal
		signal_data = TradeSignal(
			symbol=args.symbol,
			action=trading_signal.action,
			confidence=trading_signal.confidence,
			entry=trading_signal.price,
			stop_loss=0.0,
			take_profit=0.0,
			reason=trading_signal.reason,
			timestamp=trading_signal.timestamp
		)
		
		executor.persist_signal(signal_data, max_records=max(1, args.signal_history_limit))
		
		logger.info(f"Signal generated: {trading_signal.action} confidence={trading_signal.confidence} reason={trading_signal.reason}")
		
		# Update equity data from MT5
		if mt5_connected:
			try:
				account_info = mt5.account_info()
				if account_info:
					open_positions = mt5.positions_total()
					equity_data = {
						"balance": account_info.balance,
						"equity": account_info.equity,
						"open_positions": open_positions,
						"timestamp": datetime.utcnow().isoformat()
					}
					equity_file = root / "data" / "equity.json"
					equity_file.write_text(json.dumps(equity_data, indent=2))
			except Exception as e:
				logger.warning(f"Failed to update equity data: {e}")
		
		# Execute trades automatically via MT5
		if mt5_connected and trading_signal.action in ["BUY", "SELL"]:
			try:
				symbol_info = mt5.symbol_info(args.symbol)
				if symbol_info:
					# Check if trading is allowed
					logger.info(f"Symbol {args.symbol} - Trade mode: {symbol_info.trade_mode}, Visible: {symbol_info.visible}")
					
					tick = mt5.symbol_info_tick(args.symbol)
					if tick:
						request = {
							"action": mt5.TRADE_ACTION_DEAL,
							"symbol": args.symbol,
							"volume": trading_signal.lot_size,
							"type": mt5.ORDER_TYPE_BUY if trading_signal.action == "BUY" else mt5.ORDER_TYPE_SELL,
							"price": tick.ask if trading_signal.action == "BUY" else tick.bid,
							"deviation": 20,
							"magic": 234000,
							"comment": f"Strategy: {args.strategy_id}",
							"type_time": mt5.ORDER_TIME_GTC,
							"type_filling": mt5.ORDER_FILLING_IOC,
						}
						result = mt5.order_send(request)
						if result.retcode == mt5.TRADE_RETCODE_DONE:
							logger.info(f"[SUCCESS] MT5 Trade executed: {trading_signal.action} {trading_signal.lot_size} lots @ {request['price']}")
						else:
							logger.warning(f"[FAILED] MT5 Trade failed: {result.retcode} - {result.comment}")
							logger.warning(f"   Request: {request}")
					else:
						logger.warning(f"Failed to get tick data for {args.symbol}")
				else:
					logger.warning(f"Symbol info not available for {args.symbol}")
			except Exception as e:
				logger.warning(f"Failed to execute MT5 trade: {e}")
		
		if args.emit_orders and trading_signal.action in ["BUY", "SELL"]:
			order_request = {
				"symbol": args.symbol,
				"side": trading_signal.action,
				"action": trading_signal.action,
				"price": trading_signal.price,
				"lot_size": trading_signal.lot_size,
				"volume": trading_signal.lot_size,
				"strategy_id": args.strategy_id,
				"timestamp": trading_signal.timestamp
			}
			executor.persist_order_request(
				order_request,
				max_records=max(1, args.order_history_limit),
			)
			logger.info(f"Order request emitted: {args.symbol} {trading_signal.action} {trading_signal.lot_size} lots")

		print(
			f"[{datetime.now(timezone.utc).isoformat()}] "
			f"cycle={cycle} {trading_signal.action} {args.symbol} @ {trading_signal.price} "
			f"conf={trading_signal.confidence}"
		)

		if args.cycles > 0 and cycle >= args.cycles:
			break

		if args.max_runtime_seconds > 0:
			elapsed = time.monotonic() - started_at
			if elapsed >= args.max_runtime_seconds:
				break

		time.sleep(max(1, args.interval))

	logger.info("XAUUSD Scalper stopped")
	return 0


if __name__ == "__main__":
	raise SystemExit(run())
