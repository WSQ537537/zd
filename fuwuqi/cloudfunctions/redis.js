/**
 * Redis/Memurai 连接管理模块
 * 
 * 功能：提供Redis兼容连接实例，用于缓存、已读状态存储等
 * 特性：自动重连、连接池、错误处理
 * 兼容：Memurai（Windows原生Redis兼容数据库）
 */

const Redis = require('ioredis');
const { Logger } = require('./utils');

// Redis/Memurai 配置（支持环境变量）
// Memurai 默认端口与 Redis 一致（6379），协议完全兼容
const REDIS_CONFIG = {
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT) || 6379,
  password: process.env.REDIS_PASSWORD || null,
  db: parseInt(process.env.REDIS_DB) || 0,
  // 连接池配置
  maxRetriesPerRequest: 3,
  connectTimeout: 10000,
  commandTimeout: 5000,
  // 自动重连策略
  retryStrategy(times) {
    const delay = Math.min(times * 50, 2000);
    Logger.warn('REDIS', `尝试第${times}次重连，延迟${delay}ms`);
    return delay;
  },
  // 保持连接活跃
  keepAlive: 30000,
  // 最大重试次数
  maxRetryDelay: 3000
};

// 创建Redis实例
let redisInstance = null;

/**
 * 获取Redis实例（单例模式）
 * @returns {Redis} Redis客户端实例
 */
function getRedis() {
  if (redisInstance) {
    return redisInstance;
  }

  redisInstance = new Redis(REDIS_CONFIG);

  // 监听连接事件
  redisInstance.on('connect', () => {
    Logger.info('REDIS', '✅ Redis连接成功', {
      host: REDIS_CONFIG.host,
      port: REDIS_CONFIG.port,
      db: REDIS_CONFIG.db
    });
  });

  redisInstance.on('ready', () => {
    Logger.info('REDIS', '🚀 Redis就绪，可以开始使用');
  });

  redisInstance.on('error', (err) => {
    Logger.error('REDIS', '❌ Redis连接错误', err);
  });

  redisInstance.on('close', () => {
    Logger.warn('REDIS', '⚠️ Redis连接关闭');
  });

  redisInstance.on('reconnecting', () => {
    Logger.info('REDIS', '🔄 Redis正在重连...');
  });

  return redisInstance;
}

/**
 * 关闭Redis连接
 */
async function closeRedis() {
  if (redisInstance) {
    try {
      await redisInstance.quit();
      Logger.info('REDIS', '✅ Redis连接已关闭');
    } catch (err) {
      Logger.error('REDIS', '关闭Redis连接失败', err);
    }
    redisInstance = null;
  }
}

/**
 * 测试Redis连接
 * @returns {Promise<boolean>} 是否连接成功
 */
async function testRedisConnection() {
  try {
    const redis = getRedis();
    const result = await redis.ping();
    Logger.info('REDIS', `Redis连接测试: ${result}`);
    return result === 'PONG';
  } catch (err) {
    Logger.error('REDIS', 'Redis连接测试失败', err);
    return false;
  }
}

module.exports = {
  getRedis,
  closeRedis,
  testRedisConnection
};
