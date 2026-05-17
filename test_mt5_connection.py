import os
from dotenv import load_dotenv
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[0]
load_dotenv(ROOT_DIR / ".env")

try:
    import MetaTrader5 as mt5
except ImportError:
    print("MetaTrader5 package not installed")
    exit(1)

account = os.getenv("MT5_ACCOUNT")
password = os.getenv("MT5_PASSWORD")
server = os.getenv("MT5_SERVER")

print(f"Account: {account}")
print(f"Password: {'*' * len(password) if password else 'None'}")
print(f"Server: {server}")
print()

if not account or not password or not server:
    print("Credentials are missing from .env")
    exit(1)

print("Attempting to connect to MT5...")
if not mt5.initialize(login=int(account), password=password, server=server):
    print(f"MT5 initialization failed: {mt5.last_error()}")
    exit(1)

print("MT5 connected successfully!")
print(f"Account balance: {mt5.account_info().balance}")
print(f"Account equity: {mt5.account_info().equity}")
print(f"Account currency: {mt5.account_info().currency}")

mt5.shutdown()
