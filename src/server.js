import express from 'express';
import { masterPool, slavePool } from './db.js';
import config from './config.js';

const app = express();
app.use(express.json());

app.post('/products', async (req, res) => {
  const { name, price } = req.body;
  
  if (!name || !price) {
    return res.status(400).json({ error: 'Name and price are required' });
  }

  try {
    const result = await masterPool.query(
      'INSERT INTO products (name, price) VALUES ($1, $2) RETURNING *',
      [name, price]
    );
    
    res.status(201).json({
      message: 'Product created successfully',
      data: result.rows[0]
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/products', async (req, res) => {
  try {
    const result = await slavePool.query('SELECT * FROM products ORDER BY id');
    
    res.json({
      processed_by: config.server.nodeId,
      count: result.rows.length,
      data: result.rows
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(config.server.port, () => {
  console.log(`${config.server.nodeId} running on port ${config.server.port}`);
});
