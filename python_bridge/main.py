from __future__ import annotations

import argparse
from datetime import datetime, timezone
import logging
from pathlib import Path
import time

from claude_client import ClaudeClient
from market_analyzer import MarketAnalyzer
from trade_executor import TradeExecutor


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

	configure_error_log(root)
	analyzer = MarketAnalyzer(
		symbol=args.symbol,
		feed_file=feed_file,
		max_feed_age_seconds=args.feed_max_age,
	)
	executor = TradeExecutor(root)
	llm = ClaudeClient()

	cycle = 0
	started_at = time.monotonic()
	while True:
		cycle += 1
		if args.sync_acks:
			executor.reconcile_latest_order_response(
				max_history_records=max(0, args.ack_history_limit)
			)

		snapshot = analyzer.fetch_market_snapshot()
		signal = analyzer.analyze(snapshot)

		summary = llm.summarize_signal(signal)
		signal.reason = f"{signal.reason} | note={summary}"
		executor.persist_signal(signal, max_records=max(1, args.signal_history_limit))
		if args.emit_orders:
			order_request = executor.build_order_request(
				signal=signal,
				lot_size=args.lot_size,
				strategy_id=args.strategy_id,
			)
			if order_request is not None:
				executor.persist_order_request(
					order_request,
					max_records=max(1, args.order_history_limit),
				)

		print(
			f"[{datetime.now(timezone.utc).isoformat()}] "
			f"cycle={cycle} {signal.action} {signal.symbol} @ {signal.entry} "
			f"conf={signal.confidence}"
		)

		if args.cycles > 0 and cycle >= args.cycles:
			break

		if args.max_runtime_seconds > 0:
			elapsed = time.monotonic() - started_at
			if elapsed >= args.max_runtime_seconds:
				break

		time.sleep(max(1, args.interval))

	return 0


if __name__ == "__main__":
	raise SystemExit(run())
