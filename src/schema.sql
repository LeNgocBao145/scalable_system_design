\c products_db;

CREATE TABLE IF NOT EXISTS products (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  price NUMERIC(10, 2) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Mock Data
INSERT INTO products (name, price) VALUES
  ('Laptop Dell XPS 13', 1299.99),
  ('iPhone 15 Pro', 999.00),
  ('Samsung Galaxy S24', 849.99),
  ('MacBook Pro M3', 1999.00),
  ('Sony WH-1000XM5', 399.99),
  ('iPad Air', 599.00),
  ('Apple Watch Series 9', 429.00),
  ('AirPods Pro', 249.00),
  ('Logitech MX Master 3', 99.99),
  ('Dell UltraSharp Monitor', 549.00);
