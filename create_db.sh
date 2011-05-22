sqlite3 bank.db <<SQL
  CREATE TABLE transactions (
    id INTEGER PRIMARY KEY,
    date INTEGER,
    subject TEXT,
    amount INTEGER,
    bank TEXT
  );
  CREATE TABLE balance (
    id INTEGER PRIMARY KEY,
    date INTEGER,
    balance INTEGER,
    bank TEXT
  );
  CREATE TABLE fund (
    id INTEGER PRIMARY KEY,
    date INTEGER,
    value INTEGER,
    bank TEXT
  );
SQL
