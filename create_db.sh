sqlite3 swedbank.db <<SQL
  CREATE TABLE swedbank (
    id INTEGER PRIMARY KEY,
    date INTEGER,
    subject TEXT,
    amount INTEGER
  );
SQL
