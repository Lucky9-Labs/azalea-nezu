"""One-time VPS SQLite volume initialization; collection is a separate service."""

import os
import sqlite3
from pathlib import Path

directory = Path("/var/lib/azalea")
database = directory / "bronze.sqlite3"
reader_gid = int(os.environ["BRONZE_READ_GID"])

directory.mkdir(parents=True, exist_ok=True)
with sqlite3.connect(database) as connection:
    connection.executescript(Path("/opt/pi_bronze.sql").read_text())

os.chown(directory, 0, reader_gid)
os.chown(database, 0, reader_gid)
directory.chmod(0o750)
database.chmod(0o640)
print("VPS bronze SQLite volume initialized")
