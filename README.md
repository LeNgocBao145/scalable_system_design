# Technical Documentation

## Kiến Trúc Hệ Thống

### Tổng Quan
Hệ thống được thiết kế theo kiến trúc phân tán với load balancing và database replication để đảm bảo khả năng mở rộng và hiệu suất cao.

### Sơ Đồ Kiến Trúc

```
                                    ┌─────────────────┐
                                    │   Client/User   │
                                    └────────┬────────┘
                                             │
                                             ▼
                                    ┌─────────────────┐
                                    │  Nginx (8080)   │
                                    │  Load Balancer  │
                                    └────────┬────────┘
                                             │
                        ┌────────────────────┴────────────────────┐
                        │                                         │
                        ▼                                         ▼
              ┌──────────────────┐                      ┌──────────────────┐
              │   API Node A     │                      │   API Node B     │
              │   (Port 3000)    │                      │   (Port 3001)    │
              └───────┬──────────┘                      └───────┬──────────┘
                      │                                         │
            ┌─────────┴─────────────────────────────┐           │       
            │                  ┌────────────────────│───────────┴────────┐
        (WRITE)             (WRITE)	          (READ)               (READ)
            │                  │                    │                    │ 
            ▼                  ▼                    ▼                    ▼
     ┌────────────────────────────┐             ┌────────────────────────────┐
     │ PostgreSQL Master (5432)   │             │ PostgreSQL Slave (5433)    │
     │ - WRITE operations         │───────────> │ - READ operations          │
     └────────────────────────────┘ Replication └────────────────────────────┘

```

### Các Thành Phần

1. **Nginx Load Balancer** (Port 8080)
   - Phân phối traffic đến các API nodes
   - Round-robin load balancing

2. **API Nodes** (Node A: 3000, Node B: 3001)
   - Express.js REST API
   - Write operations → Master DB
   - Read operations → Slave DB

3. **PostgreSQL Master** (Port 5432)
   - Xử lý tất cả write operations
   - Streaming replication đến Slave

4. **PostgreSQL Slave** (Port 5433)
   - Read replica
   - Hot standby mode

---

## Các Bước Triển Khai Kỹ Thuật

### Giai Đoạn 1: Thiết Lập Database Replication

#### Bước 1.1: Cấu Hình Master Node

**Tạo init script:** `init-master.sh`

```bash
# Tạo replication user
CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'password';

# Tạo application user
CREATE USER app_user WITH PASSWORD 'password';
GRANT ALL PRIVILEGES ON DATABASE products_db TO app_user;

# Cấu hình replication settings
wal_level = replica
max_wal_senders = 3
wal_keep_size = 64
```

**Cấu hình trong docker-compose.yml:**
```yaml
postgres-master:
  image: postgres:15-alpine
  ports:
    - "5432:5432"
  volumes:
    - ./init-master.sh:/docker-entrypoint-initdb.d/02-init-master.sh
```

#### Bước 1.2: Cấu Hình Slave Node

**Tạo init script:** `init-slave.sh`

```bash
# Đợi master
until PGPASSWORD=$POSTGRES_PASSWORD psql -h postgres-master -U $POSTGRES_USER -c '\q'; do
    sleep 2
done

# Base backup từ master
pg_basebackup -h postgres-master -D ${PGDATA} -U replicator -R -X stream

# Bật hot standby
echo "hot_standby = on" >> ${PGDATA}/postgresql.conf
```

**Cấu hình trong docker-compose.yml:**
```yaml
postgres-slave:
  image: postgres:15-alpine
  ports:
    - "5433:5432"
  command: ["sh", "/usr/local/bin/init-slave.sh"]
  depends_on:
    postgres-master:
      condition: service_healthy
```

#### Bước 1.3: Xác Minh Đồng Bộ

**Khởi động databases:**
```bash
docker-compose up -d postgres-master postgres-slave
```

**Thêm dữ liệu vào Master:**
```bash
docker exec -it postgres-master psql -U postgres -d products_db \
  -c "INSERT INTO products (name, price) VALUES ('Test Product', 99.99);"
```

**Kiểm tra Slave:**
```bash
docker exec -it postgres-slave psql -U postgres -d products_db \
  -c "SELECT * FROM products WHERE name='Test Product';"
```

**Xác minh trạng thái replication:**
```bash
# Trên Master
docker exec -it postgres-master psql -U postgres \
  -c "SELECT * FROM pg_stat_replication;"

# Trên Slave
docker exec -it postgres-slave psql -U postgres \
  -c "SELECT pg_is_in_recovery();"
```

---

### Giai Đoạn 2: Phát Triển API & Tách Biệt Read/Write

#### Bước 2.1: Triển Khai Connection Strings

**Tạo config.js với hai connection strings:**

```javascript
export default {
  master: {
    host: process.env.MASTER_HOST || 'localhost',  // Master IP
    port: process.env.MASTER_PORT || 5432,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME
  },
  slave: {
    host: process.env.SLAVE_HOST || 'localhost',   // Slave IP
    port: process.env.SLAVE_PORT || 5433,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME
  }
};
```

#### Bước 2.2: Tạo Các Connection Pools Riêng Biệt

**Tạo db.js:**

```javascript
import pg from 'pg';
import config from './config.js';

const masterPool = new Pool(config.master);  // Cho WRITE operations
const slavePool = new Pool(config.slave);    // Cho READ operations

export { masterPool, slavePool };
```

#### Bước 2.3: Triển Khai API Logic Với Tách Biệt Read/Write

**Tạo server.js:**

```javascript
import express from 'express';
import { masterPool, slavePool } from './db.js';

const app = express();
app.use(express.json());

// WRITE operation - Dùng Master
app.post('/products', async (req, res) => {
  const { name, price } = req.body;
  const result = await masterPool.query(
    'INSERT INTO products (name, price) VALUES ($1, $2) RETURNING *',
    [name, price]
  );
  res.status(201).json({ data: result.rows[0] });
});

// READ operation - Dùng Slave
app.get('/products', async (req, res) => {
  const result = await slavePool.query('SELECT * FROM products');
  res.json({
    processed_by: process.env.NODE_ID,  // Server ID
    data: result.rows
  });
});

app.listen(process.env.PORT);
```

#### Bước 2.4: Build Docker Image

```bash
cd src
docker build -t scalable-api:latest .
```

---

### Giai Đoạn 3: Hạ Tầng & Load Balancing

#### Bước 3.1: Triển Khai Hai API Instances

**Cấu hình trong docker-compose.yml:**

```yaml
api-node-a:
  image: scalable-api:latest
  environment:
    PORT: 3000
    NODE_ID: Node_A              # Server ID
    MASTER_HOST: postgres-master # Master IP
    SLAVE_HOST: postgres-slave   # Slave IP
  ports:
    - "3000:3000"

api-node-b:
  image: scalable-api:latest
  environment:
    PORT: 3001
    NODE_ID: Node_B              # Server ID
    MASTER_HOST: postgres-master
    SLAVE_HOST: postgres-slave
  ports:
    - "3001:3001"
```

#### Bước 3.2: Cấu Hình Load Balancer

**Tạo nginx.conf:**

```nginx
http {
    upstream api_backend {
        server api-node-a:3000;
        server api-node-b:3001;
    }

    server {
        listen 80;
        location / {
            proxy_pass http://api_backend;
        }
    }
}
```

#### Bước 3.3: Triển Khai Load Balancer

**Cấu hình trong docker-compose.yml:**

```yaml
nginx:
  image: nginx:alpine
  ports:
    - "8080:80"
  volumes:
    - ./nginx.conf:/etc/nginx/nginx.conf:ro
  depends_on:
    - api-node-a
    - api-node-b
```

#### Bước 3.4: Khởi Động Tất Cả Services

```bash
docker-compose up -d
```

---

### Giai Đoạn 4: Xác Minh & Kiểm Tra Tải

#### Bước 4.1: Xác Minh Load Balancing (Server ID Chuyển Đổi)

**Gửi nhiều GET requests:**

```bash
# Request 1
curl http://localhost:8080/products
# Response: {"processed_by": "Node_A", ...}

# Request 2
curl http://localhost:8080/products
# Response: {"processed_by": "Node_B", ...}

# Request 3
curl http://localhost:8080/products
# Response: {"processed_by": "Node_A", ...}
```

**Xác minh Server ID chuyển đổi giữa Node_A và Node_B**

#### Bước 4.2: Xác Minh Tách Biệt Read/Write

**Ghi vào Master qua Load Balancer:**

```bash
curl -X POST http://localhost:8080/products \
  -H "Content-Type: application/json" \
  -d '{"name":"iPhone 16","price":1299.99}'
```

**Xác minh dữ liệu trên Master:**

```bash
docker exec -it postgres-master psql -U postgres -d products_db \
  -c "SELECT * FROM products WHERE name='iPhone 16';"
```

**Xác minh dữ liệu đã replicate sang Slave:**

```bash
docker exec -it postgres-slave psql -U postgres -d products_db \
  -c "SELECT * FROM products WHERE name='iPhone 16';"
```

**Đọc từ Slave qua Load Balancer:**

```bash
curl http://localhost:8080/products
# Sẽ bao gồm product vừa tạo
```

#### Bước 4.3: Kiểm Tra Tải Với Nhiều Requests

**Sử dụng curl loop:**

```bash
# Gửi 10 GET requests
for i in {1..10}; do
  curl -s http://localhost:8080/products | grep processed_by
done
```

**Kết quả mong đợi (luân phiên):**
```
"processed_by": "Node_A"
"processed_by": "Node_B"
"processed_by": "Node_A"
"processed_by": "Node_B"
...
```

**Sử dụng Postman:**
1. Tạo GET request đến `http://localhost:8080/products`
2. Sử dụng Collection Runner
3. Đặt iterations thành 20
4. Xác minh `processed_by` luân phiên giữa Node_A và Node_B

---

## Chi Tiết Cấu Hình

### 1. Cấu Hình Nginx

**File:** `nginx.conf`

```nginx
events {
    worker_connections 1024;
}

http {
    upstream api_backend {
        server api-node-a:3000;
        server api-node-b:3001;
    }

    server {
        listen 80;

        location / {
            proxy_pass http://api_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }
}
```

**Các Thiết Lập Quan Trọng:**
- `upstream api_backend`: Định nghĩa backend servers
- `proxy_pass`: Forward requests đến backend pool
- Headers: Preserve client information

---

### 2. Cấu Hình Database

#### Thiết Lập PostgreSQL Master

**File:** `init-master.sh`

```bash
# Replication User
CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'password';

# Application User
CREATE USER app_user WITH PASSWORD 'password';
GRANT ALL PRIVILEGES ON DATABASE products_db TO app_user;

# Replication Settings
listen_addresses = '*'
wal_level = replica
max_wal_senders = 3
wal_keep_size = 64
max_replication_slots = 3
```

**Các Tham Số Quan Trọng:**
- `wal_level = replica`: Bật replication
- `max_wal_senders = 3`: Số lượng kết nối replication đồng thời tối đa
- `wal_keep_size = 64`: Kích thước lưu giữ WAL (MB)

#### Thiết Lập PostgreSQL Slave

**File:** `init-slave.sh`

```bash
# Base backup từ master
pg_basebackup -h postgres-master -D ${PGDATA} -U replicator -R -X stream

# Cài đặt riêng cho slave
listen_addresses = '*'
hot_standby = on
```

**Các Tham Số Quan Trọng:**
- `hot_standby = on`: Cho phép read queries trên replica
- `-R`: Tự động tạo standby.signal và connection info

---

### 3. Logic Kết Nối Database Của API

#### Cấu Hình Kết Nối

**File:** `src/config.js`

```javascript
export default {
  master: {
    host: process.env.MASTER_HOST || 'localhost',
    port: process.env.MASTER_PORT || 5432,
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || 'password',
    database: process.env.DB_NAME || 'products_db'
  },
  slave: {
    host: process.env.SLAVE_HOST || 'localhost',
    port: process.env.SLAVE_PORT || 5433,
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || 'password',
    database: process.env.DB_NAME || 'products_db'
  },
  server: {
    port: process.env.PORT || 3000,
    nodeId: process.env.NODE_ID || 'Node_A'
  }
};
```

#### Connection Pools

**File:** `src/db.js`

```javascript
import pg from 'pg';
import config from './config.js';

const { Pool } = pg;

const masterPool = new Pool(config.master);  // Write operations
const slavePool = new Pool(config.slave);    // Read operations

export { masterPool, slavePool };
```

#### API Endpoints

**File:** `src/server.js`

```javascript
// POST /products - Ghi vào Master
app.post('/products', async (req, res) => {
  const result = await masterPool.query(
    'INSERT INTO products (name, price) VALUES ($1, $2) RETURNING *',
    [name, price]
  );
});

// GET /products - Đọc từ Slave
app.get('/products', async (req, res) => {
  const result = await slavePool.query('SELECT * FROM products ORDER BY id');
});
```

**Tách Biệt Read/Write:**
- Write operations (POST, PUT, DELETE) → `masterPool`
- Read operations (GET) → `slavePool`

---

### 4. Database Schema

**File:** `src/schema.sql`

```sql
CREATE TABLE IF NOT EXISTS products (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  price NUMERIC(10, 2) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

---

### 5. Biến Môi Trường

**File:** `.env`

```env
# PostgreSQL Admin
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=products_db

# Replication User
REPLICATION_USER=replicator
REPLICATION_PASSWORD=1234567890

# Application User
DB_USER=app_user
DB_PASSWORD=090909lol
DB_NAME=products_db
```

---

## Hướng Dẫn Cài Đặt

### Yêu Cầu

- Docker & Docker Compose
- Git
- Các port khả dụng: 8080, 3000, 3001, 5432, 5433

### Hướng Dẫn Cài Đặt Từng Bước

#### Lưu ý quan trọng

**Nếu bạn dùng Docker Desktop trên Windows:**

Tuyệt đối không được chạy docker-compose trên cmd hay git bash của Windows mà phải dùng WSL vì sẽ bị lỗi path của các file mà tôi mount trong docker-compose.yml. Docker Desktop sẽ luôn nhận diện file mount của tôi là thư mục thay vì là file.

**Cách sử dụng WSL:**
```bash
# Mở WSL terminal (Ubuntu/Debian)
wsl
```

#### 1. Clone Repository

```bash
git clone <repository-url>
cd scalable_system_design
```

#### 2. Cấu Hình Môi Trường

```bash
# Copy và chỉnh sửa file .env
cp .env.example .env
# Chỉnh sửa .env với thông tin của bạn
```

#### 3. Build Docker Image cho API

```bash
cd src
docker build -t scalable-api:latest .
cd ..
```

#### 4. Khởi Động Các Services

```bash
docker-compose up -d
```

**Thứ tự khởi động:**
1. postgres-master (với healthcheck)
2. postgres-slave (đợi master)
3. api-node-a & api-node-b (đợi databases)
4. nginx (đợi API nodes)

#### 5. Kiểm Tra Cài Đặt

**Kiểm tra containers:**
```bash
docker-compose ps
```

**Kiểm tra Master-Slave Replication:**
```bash
# Kết nối đến master
docker exec -it postgres-master psql -U postgres -d products_db -c "SELECT * FROM products;"

# Kết nối đến slave
docker exec -it postgres-slave psql -U postgres -d products_db -c "SELECT * FROM products;"
```

**Kiểm tra API:**
```bash
# Tạo product (ghi vào master)
curl -X POST http://localhost:8080/products \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Product","price":99.99}'

# Lấy products (đọc từ slave)
curl http://localhost:8080/products
```

#### 6. Theo Dõi Logs

```bash
# Tất cả services
docker-compose logs -f

# Service cụ thể
docker-compose logs -f nginx
docker-compose logs -f api-node-a
docker-compose logs -f postgres-master
```

#### 7. Dừng Services

```bash
docker-compose down

# Xóa volumes (xóa dữ liệu)
docker-compose down -v
```

---

## Kiểm Tra Replication

### Kiểm Tra Trạng Thái Replication

**Trên Master:**
```bash
docker exec -it postgres-master psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

**Trên Slave:**
```bash
docker exec -it postgres-slave psql -U postgres -c "SELECT pg_is_in_recovery();"
```

### Kiểm Tra Đồng Bộ Dữ Liệu

```bash
# Thêm dữ liệu vào master
docker exec -it postgres-master psql -U postgres -d products_db \
  -c "INSERT INTO products (name, price) VALUES ('Sync Test', 123.45);"

# Kiểm tra trên slave (sẽ xuất hiện trong vài giây)
docker exec -it postgres-slave psql -U postgres -d products_db \
  -c "SELECT * FROM products WHERE name='Sync Test';"
```

---

## API Endpoints

### POST /products
Tạo sản phẩm mới (ghi vào master)

**Request:**
```json
{
  "name": "Product Name",
  "price": 99.99
}
```

**Response:**
```json
{
  "message": "Product created successfully",
  "data": {
    "id": 1,
    "name": "Product Name",
    "price": "99.99",
    "created_at": "2024-01-01T00:00:00.000Z"
  }
}
```

### GET /products
Lấy tất cả sản phẩm (đọc từ slave)

**Response:**
```json
{
  "processed_by": "Node_A",
  "count": 10,
  "data": [...]
}
```

---

## Xử Lý Sự Cố

### Replication Không Hoạt Động

```bash
# Kiểm tra logs của master
docker-compose logs postgres-master

# Kiểm tra logs của slave
docker-compose logs postgres-slave

# Kiểm tra replication user
docker exec -it postgres-master psql -U postgres -c "\du"
```

### Lỗi Kết Nối API

```bash
# Kiểm tra logs của API
docker-compose logs api-node-a

# Kiểm tra kết nối database
docker exec -it api-node-a ping postgres-master
docker exec -it api-node-a ping postgres-slave
```

### Lỗi Load Balancer

```bash
# Kiểm tra cấu hình nginx
docker exec -it nginx-lb nginx -t

# Reload nginx
docker exec -it nginx-lb nginx -s reload
```
