from __future__ import annotations

from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess

import pandas as pd
import streamlit as st

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
LOG_DIR = ROOT / "logs"

SIGNALS_FILE = DATA_DIR / "signals.json"
ORDERS_FILE = DATA_DIR / "order_requests.json"
LATEST_ORDER_FILE = DATA_DIR / "order_request.latest.json"
LATEST_ACK_FILE = DATA_DIR / "order_response.latest.json"
ACK_HISTORY_FILE = DATA_DIR / "order_response_history.jsonl"
MARKET_TICK_FILE = DATA_DIR / "market_tick.json"
TRADING_LOG_FILE = LOG_DIR / "trading.log"


def load_json(path: Path, default):
    if not path.exists() or path.stat().st_size == 0:
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return default


def load_jsonl_tail(path: Path, max_lines: int = 20) -> list[dict]:
    if not path.exists() or path.stat().st_size == 0:
        return []

    lines = path.read_text(encoding="utf-8").splitlines()[-max_lines:]
    out: list[dict] = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


def to_df(records: list[dict]) -> pd.DataFrame:
    if not records:
        return pd.DataFrame()
    return pd.DataFrame(records)


def now_utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def parse_utc(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def compute_feed_age_seconds(feed: dict) -> float | None:
    ts = str(feed.get("timestamp", "")).strip()
    parsed = parse_utc(ts)
    if parsed is None:
        return None
    return max(0.0, (datetime.now(timezone.utc) - parsed).total_seconds())


def run_single_cycle(symbol: str, lot_size: float, emit_orders: bool, sync_acks: bool) -> tuple[int, str, str]:
    cmd = [
        "python3",
        "python_bridge/main.py",
        "--cycles",
        "1",
        "--interval",
        "1",
        "--symbol",
        symbol,
        "--lot-size",
        str(lot_size),
    ]

    if not emit_orders:
        cmd.append("--no-emit-orders")
    if not sync_acks:
        cmd.append("--no-sync-acks")

    result = subprocess.run(
        cmd,
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    return result.returncode, result.stdout, result.stderr


st.set_page_config(page_title="Raybot Trading Dashboard", layout="wide")

st.markdown(
    """
    <style>
        .block-container {padding-top: 1.2rem;}
        .status-card {
            padding: 0.8rem 1rem;
            border-radius: 12px;
            background: linear-gradient(120deg, #f8fbff 0%, #eef6ff 100%);
            border: 1px solid #d7e8ff;
        }
        .status-title {
            font-size: 0.85rem;
            color: #4a5870;
            margin-bottom: 0.2rem;
        }
        .status-value {
            font-size: 1.1rem;
            font-weight: 700;
            color: #14233a;
        }
    </style>
    """,
    unsafe_allow_html=True,
)

st.title("Raybot Trading Dashboard")
st.caption(f"Workspace: {ROOT}")

with st.sidebar:
    st.header("Engine Controls")
    if st.button("Refresh Dashboard", use_container_width=True):
        st.rerun()

    symbol = st.text_input("Symbol", value="XAUUSD")
    lot_size = st.number_input("Lot Size", min_value=0.01, max_value=100.0, value=0.01, step=0.01)
    emit_orders = st.checkbox("Emit Orders", value=True)
    sync_acks = st.checkbox("Sync Acks", value=True)

    if st.button("Run One Trading Cycle", use_container_width=True):
        with st.spinner("Running one cycle..."):
            code, out, err = run_single_cycle(symbol, lot_size, emit_orders, sync_acks)
        if code == 0:
            st.success("Cycle completed")
        else:
            st.error(f"Cycle failed (exit code {code})")
        with st.expander("Cycle output", expanded=True):
            st.text_area("stdout", out or "<empty>", height=150)
            st.text_area("stderr", err or "<empty>", height=110)

    st.divider()
    st.info(
        "Continuous mode command:\n"
        "python3 python_bridge/main.py --cycles 0 --interval 1"
    )

signals = load_json(SIGNALS_FILE, [])
orders = load_json(ORDERS_FILE, [])
latest_order = load_json(LATEST_ORDER_FILE, {})
latest_ack = load_json(LATEST_ACK_FILE, {})
feed = load_json(MARKET_TICK_FILE, {})
ack_history = load_jsonl_tail(ACK_HISTORY_FILE, max_lines=80)

signals_df = to_df(signals)
orders_df = to_df(orders)
ack_df = to_df(ack_history)

feed_age = compute_feed_age_seconds(feed)
latest_signal = signals[-1] if signals else {}
latest_signal_action = str(latest_signal.get("action", "n/a"))
latest_signal_conf = latest_signal.get("confidence", "n/a")

pending_count = int((orders_df.get("status") == "PENDING").sum()) if not orders_df.empty else 0
filled_count = int((orders_df.get("status") == "FILLED").sum()) if not orders_df.empty else 0
rejected_count = int((orders_df.get("status") == "REJECTED").sum()) if not orders_df.empty else 0

header_cols = st.columns(5)
cards = [
    ("Signals", str(len(signals))),
    ("Orders", str(len(orders))),
    ("Pending", str(pending_count)),
    ("Latest Action", latest_signal_action),
    ("Feed Age (s)", "n/a" if feed_age is None else f"{feed_age:.1f}"),
]
for idx, (title, value) in enumerate(cards):
    header_cols[idx].markdown(
        f"<div class='status-card'><div class='status-title'>{title}</div>"
        f"<div class='status-value'>{value}</div></div>",
        unsafe_allow_html=True,
    )

st.markdown("### Engine Snapshot")
snapshot_left, snapshot_right = st.columns(2)
with snapshot_left:
    st.json(feed if feed else {"status": "no market tick"})
with snapshot_right:
    st.json(latest_ack if latest_ack else {"status": "no latest ack"})

tabs = st.tabs(["Overview", "Signals", "Orders", "Acknowledgements", "Console"])

with tabs[0]:
    st.subheader("Trading Overview")
    if not signals_df.empty:
        plot_df = signals_df.copy()
        plot_df["timestamp"] = pd.to_datetime(plot_df["timestamp"], utc=True, errors="coerce")
        plot_df = plot_df.dropna(subset=["timestamp"]).sort_values("timestamp")
        if not plot_df.empty:
            plot_df = plot_df.tail(150)
            st.line_chart(plot_df.set_index("timestamp")["entry"], height=260)

    count_cols = st.columns(3)
    count_cols[0].metric("FILLED", filled_count)
    count_cols[1].metric("PENDING", pending_count)
    count_cols[2].metric("REJECTED", rejected_count)

    if not signals_df.empty:
        action_counts = signals_df["action"].value_counts().rename_axis("action").reset_index(name="count")
        st.bar_chart(action_counts.set_index("action"), height=220)

with tabs[1]:
    st.subheader("Signals Explorer")
    actions = ["ALL", "BUY", "SELL", "HOLD"]
    selected_action = st.selectbox("Action Filter", options=actions, index=0)
    rows = st.slider("Rows", min_value=20, max_value=300, value=80, step=10)

    filtered_signals = signals_df.copy()
    if not filtered_signals.empty and selected_action != "ALL":
        filtered_signals = filtered_signals[filtered_signals["action"] == selected_action]

    if filtered_signals.empty:
        st.caption("No signals matching filter")
    else:
        st.dataframe(filtered_signals.tail(rows), use_container_width=True, height=430)

with tabs[2]:
    st.subheader("Orders Explorer")
    status_filter = st.multiselect(
        "Status Filter",
        options=["PENDING", "FILLED", "REJECTED", "IGNORED"],
        default=["PENDING", "FILLED", "REJECTED", "IGNORED"],
    )
    orders_rows = st.slider("Order Rows", min_value=20, max_value=400, value=120, step=20)

    filtered_orders = orders_df.copy()
    if not filtered_orders.empty and status_filter:
        filtered_orders = filtered_orders[filtered_orders["status"].isin(status_filter)]

    if filtered_orders.empty:
        st.caption("No orders matching filter")
    else:
        st.dataframe(filtered_orders.tail(orders_rows), use_container_width=True, height=430)

    st.markdown("#### Latest Order Request")
    st.json(latest_order if latest_order else {"status": "no latest request"})

with tabs[3]:
    st.subheader("Acknowledgements")
    st.markdown("#### Latest Ack")
    st.json(latest_ack if latest_ack else {"status": "no latest ack"})

    st.markdown("#### Ack History")
    if ack_df.empty:
        st.caption("No acknowledgement history entries")
    else:
        ack_rows = st.slider("Ack Rows", min_value=10, max_value=200, value=60, step=10)
        st.dataframe(ack_df.tail(ack_rows), use_container_width=True, height=410)

with tabs[4]:
    st.subheader("Console")
    if TRADING_LOG_FILE.exists():
        lines = TRADING_LOG_FILE.read_text(encoding="utf-8").splitlines()
        log_rows = st.slider("Log Tail Rows", min_value=20, max_value=300, value=80, step=20)
        st.code("\n".join(lines[-log_rows:]) or "<empty>", language="text")
    else:
        st.caption("No trading log file found")

st.caption(f"Last dashboard render: {now_utc_iso()} | Latest confidence: {latest_signal_conf}")
