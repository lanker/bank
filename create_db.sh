sqlite3 swedbank.db <<SQL
  CREATE TABLE swedbank (
    id INTEGER PRIMARY KEY,
    date INTEGER,
    subject TEXT,
    amount INTEGER
  );
  CREATE TABLE balance (
    id INTEGER PRIMARY KEY,
    date INTEGER,
    balance INTEGER
  );
SQL
