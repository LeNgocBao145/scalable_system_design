import 'dotenv/config';

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
