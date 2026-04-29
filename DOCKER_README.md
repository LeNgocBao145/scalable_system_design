# Scalable System Design - Docker Setup

## Kiến trúc

```
                    ┌─────────────┐
                    │   Nginx LB  │ :8080
                    │ Round Robin │
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              │                         │
         ┌────▼────┐              ┌────▼────┐
         │ Node A  │              │ Node B  │
         │  :3000  │              │  :3001  │
         └────┬────┘              └────┬────┘
              │                         │
              └────────────┬────────────┘
                           │
              ┌────────────┴────────────┐
              │                         │
         ┌────▼────┐              ┌────▼────┐
         │ Master  │─────────────▶│  Slave  │
         │  :5432  │  Replication │  :5433  │
         │ (Write) │              │  (Read) │
         └─────────┘              └─────────┘
```

## Khởi chạy

```bash
# Build và start tất cả services
docker-compose up -d --build

# Kiểm tra status
docker-compose ps

# Setup replication (chạy sau khi containers đã start)
bash setup-replication.sh
```

## Kiểm tra Load Balancer

```bash
# POST request (ghi vào Master)
curl -X POST http://localhost:8080/products \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Product","price":99.99}'

# GET request (đọc từ Slave) - chạy nhiều lần để thấy Round Robin
curl http://localhost:8080/products
curl http://localhost:8080/products
curl http://localhost:8080/products
```

Response sẽ có `processed_by: Node_A` hoặc `Node_B` xen kẽ.

## Kiểm tra Replication

```bash
# Insert vào Master
docker exec -it postgres-master psql -U postgres -d products_db -c "INSERT INTO products (name, price) VALUES ('Direct Insert', 123.45);"

# Query từ Slave
docker exec -it postgres-slave psql -U postgres -d products_db -c "SELECT * FROM products;"
```

## Chaos Test - Tắt 1 Node

```bash
# Tắt Node A
docker stop api-node-a

# Test API vẫn hoạt động qua Node B
curl http://localhost:8080/products

# Bật lại Node A
docker start api-node-a
```

## Logs

```bash
# Xem logs tất cả services
docker-compose logs -f

# Xem logs từng service
docker-compose logs -f nginx
docker-compose logs -f api-node-a
docker-compose logs -f postgres-master
```

## Dọn dẹp

```bash
docker-compose down -v
```
