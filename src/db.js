import pg from 'pg';
import config from './config.js';

const { Pool } = pg;

const masterPool = new Pool(config.master);
const slavePool = new Pool(config.slave);

export { masterPool, slavePool };
