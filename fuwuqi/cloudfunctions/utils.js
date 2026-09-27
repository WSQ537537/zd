const { MongoClient, ObjectId } = require('mongodb');
const fs = require('fs');
const path = require('path');
const { queryCache } = require('./cache'); // 引入缓存模块

// ========== 数据库连接池管理（优化1：避免重复创建连接） ==========
class DatabasePool {
  constructor() {
    this.client = null;
    this.db = null;
    this.isConnected = false;
    this.connecting = false;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 5;
    this.reconnectDelay = 2000; // 初始重连延迟2秒
    this.collectionCache = new Map(); // 集合引用缓存
  }

  async connect(url = 'mongodb://localhost:27017', dbName = 'zdxt') {
    // 防止并发连接
    if (this.isConnected && this.db) {
      return this.db;
    }

    if (this.connecting) {
      // 等待已有连接完成
      return new Promise((resolve, reject) => {
        const checkInterval = setInterval(() => {
          if (this.isConnected) {
            clearInterval(checkInterval);
            resolve(this.db);
          } else if (!this.connecting) {
            clearInterval(checkInterval);
            reject(new Error('数据库连接失败'));
          }
        }, 100);
      });
    }

    this.connecting = true;

    try {
      console.log(`[数据库][${new Date().toLocaleString()}] 正在连接...`);
      
      this.client = new MongoClient(url, {
        maxPoolSize: 10, // 连接池大小
        minPoolSize: 2,  // 最小连接数
        serverSelectionTimeoutMS: 5000, // 服务器选择超时
        socketTimeoutMS: 45000, // Socket超时
        connectTimeoutMS: 10000, // 连接超时
        heartbeatFrequencyMS: 10000, // 心跳检测频率
      });

      await this.client.connect();
      this.db = this.client.db(dbName);
      this.isConnected = true;
      this.connecting = false;
      this.reconnectAttempts = 0;

      // 监听连接关闭事件
      this.client.on('close', () => {
        console.warn(`[数据库][${new Date().toLocaleString()}] 连接已关闭`);
        this.isConnected = false;
        this._handleReconnect(url, dbName);
      });

      this.client.on('error', (err) => {
        console.error(`[数据库][${new Date().toLocaleString()}] 连接错误:`, err.message);
        this.isConnected = false;
        this._handleReconnect(url, dbName);
      });

      console.log(`[数据库][${new Date().toLocaleString()}] ✅ 连接成功`);
      return this.db;
    } catch (err) {
      this.connecting = false;
      console.error(`[数据库][${new Date().toLocaleString()}] ❌ 连接失败:`, err.message);
      throw err;
    }
  }

  async _handleReconnect(url, dbName) {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error(`[数据库][${new Date().toLocaleString()}] 达到最大重连次数，停止重连`);
      return;
    }

    this.reconnectAttempts++;
    const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1); // 指数退避
    
    console.log(`[数据库][${new Date().toLocaleString()}] ${delay/1000}秒后尝试第${this.reconnectAttempts}次重连...`);
    
    setTimeout(async () => {
      try {
        await this.connect(url, dbName);
      } catch (err) {
        console.error(`[数据库][${new Date().toLocaleString()}] 重连失败:`, err.message);
      }
    }, delay);
  }

  getCollection(colName) {
    if (!this.db) {
      throw new Error('数据库未连接');
    }
    // 缓存集合引用，避免重复创建
    let col = this.collectionCache.get(colName);
    if (!col) {
      col = this.db.collection(colName);
      this.collectionCache.set(colName, col);
    }
    return col;
  }

  async close() {
    if (this.client) {
      await this.client.close();
      this.isConnected = false;
      this.db = null;
      console.log(`[数据库][${new Date().toLocaleString()}] 连接已关闭`);
    }
  }
}

// 创建全局数据库连接池实例
const dbPool = new DatabasePool();

// ========== 统一日志系统（优化2：分级日志、可追踪） ==========
class Logger {
  static levels = {
    DEBUG: 0,
    INFO: 1,
    WARN: 2,
    ERROR: 3,
  };

  static currentLevel = process.env.LOG_LEVEL ? Logger.levels[process.env.LOG_LEVEL] : Logger.levels.INFO;

  static _formatMessage(level, module, message, data = null) {
    const timestamp = new Date().toLocaleString();
    const levelStr = `[${level}]`;
    const moduleStr = module ? `[${module}]` : '';
    let log = `${levelStr}[${timestamp}]${moduleStr} ${message}`;
    
    if (data) {
      log += '\n' + JSON.stringify(data, null, 2);
    }
    
    return log;
  }

  static debug(module, message, data = null) {
    if (Logger.currentLevel <= Logger.levels.DEBUG) {
      console.log(Logger._formatMessage('DEBUG', module, message, data));
    }
  }

  static info(module, message, data = null) {
    if (Logger.currentLevel <= Logger.levels.INFO) {
      console.log(Logger._formatMessage('INFO', module, message, data));
    }
  }

  static warn(module, message, data = null) {
    if (Logger.currentLevel <= Logger.levels.WARN) {
      console.warn(Logger._formatMessage('WARN', module, message, data));
    }
  }

  static error(module, message, error = null, data = null) {
    if (Logger.currentLevel <= Logger.levels.ERROR) {
      const errorMsg = error ? `${message} - ${error.message}` : message;
      console.error(Logger._formatMessage('ERROR', module, errorMsg, data));
      if (error && error.stack) {
        console.error(error.stack);
      }
    }
  }

  // 请求追踪日志
  static requestTrace(requestId, module, message, data = null) {
    Logger.info(module, `[Request:${requestId}] ${message}`, data);
  }
}

// ========== 统一异常处理（优化3：分级捕获、精准错误信息） ==========
class AppError extends Error {
  constructor(code, message, statusCode = 500, data = null) {
    super(message);
    this.code = code;
    this.statusCode = statusCode;
    this.data = data;
    this.timestamp = new Date().toISOString();
  }
}

function handleError(error, context = '') {
  if (error instanceof AppError) {
    Logger.error(context || 'APP', `业务错误 [${error.code}]: ${error.message}`, error, error.data);
    return {
      success: false,
      code: error.code,
      msg: error.message,
      data: error.data,
      timestamp: error.timestamp
    };
  }

  // MongoDB相关错误
  if (error.name === 'MongoError' || error.name === 'MongoServerError') {
    Logger.error(context || 'DB', `数据库错误: ${error.message}`, error);
    return {
      success: false,
      code: 'DB_ERROR',
      msg: '数据库操作失败，请稍后重试',
      timestamp: new Date().toISOString()
    };
  }

  // 参数验证错误
  if (error.name === 'ValidationError') {
    Logger.warn(context || 'VALIDATION', `参数验证失败: ${error.message}`, error);
    return {
      success: false,
      code: 'VALIDATION_ERROR',
      msg: '参数验证失败',
      details: error.message,
      timestamp: new Date().toISOString()
    };
  }

  // 未知错误
  Logger.error(context || 'UNKNOWN', `未知错误: ${error.message}`, error);
  return {
    success: false,
    code: 'INTERNAL_ERROR',
    msg: '服务器内部错误',
    timestamp: new Date().toISOString()
  };
}

// ========== 参数校验工具（优化4：数据校验、防脏数据） ==========
class Validator {
  static required(value, fieldName) {
    if (value === undefined || value === null || value === '') {
      throw new AppError('MISSING_PARAM', `${fieldName} 不能为空`, 400);
    }
    return value;
  }

  static string(value, fieldName, maxLength = 1000) {
    Validator.required(value, fieldName);
    if (typeof value !== 'string') {
      throw new AppError('INVALID_TYPE', `${fieldName} 必须是字符串`, 400);
    }
    if (value.length > maxLength) {
      throw new AppError('TOO_LONG', `${fieldName} 长度不能超过${maxLength}`, 400);
    }
    return value.trim();
  }

  static number(value, fieldName, min = null, max = null) {
    Validator.required(value, fieldName);
    const num = Number(value);
    if (isNaN(num)) {
      throw new AppError('INVALID_NUMBER', `${fieldName} 必须是数字`, 400);
    }
    if (min !== null && num < min) {
      throw new AppError('TOO_SMALL', `${fieldName} 不能小于${min}`, 400);
    }
    if (max !== null && num > max) {
      throw new AppError('TOO_LARGE', `${fieldName} 不能大于${max}`, 400);
    }
    return num;
  }

  static array(value, fieldName) {
    Validator.required(value, fieldName);
    if (!Array.isArray(value)) {
      throw new AppError('INVALID_TYPE', `${fieldName} 必须是数组`, 400);
    }
    return value;
  }

  static objectId(value, fieldName) {
    Validator.required(value, fieldName);
    if (!ObjectId.isValid(value)) {
      throw new AppError('INVALID_ID', `${fieldName} 格式不正确`, 400);
    }
    return new ObjectId(value);
  }

  // 清理HTML标签，防止XSS
  static sanitizeHtml(str) {
    if (typeof str !== 'string') return str;
    return str.replace(/<[^>]*>/g, '').trim();
  }

  // 验证邮箱格式
  static email(value, fieldName) {
    Validator.required(value, fieldName);
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(value)) {
      throw new AppError('INVALID_EMAIL', `${fieldName} 邮箱格式不正确`, 400);
    }
    return value.toLowerCase().trim();
  }
}

// ========== 请求节流器（优化5：防重复请求） ==========
class RequestThrottle {
  constructor() {
    this.pendingRequests = new Map();
  }

  async throttle(key, fn, timeout = 5000) {
    // 如果相同请求正在进行中，返回已有的Promise
    if (this.pendingRequests.has(key)) {
      Logger.debug('THROTTLE', `请求被节流: ${key}`);
      return this.pendingRequests.get(key);
    }

    const promise = fn().finally(() => {
      this.pendingRequests.delete(key);
    });

    this.pendingRequests.set(key, promise);

    // 设置超时清理
    setTimeout(() => {
      if (this.pendingRequests.has(key)) {
        this.pendingRequests.delete(key);
        Logger.warn('THROTTLE', `请求超时清理: ${key}`);
      }
    }, timeout);

    return promise;
  }
}

const requestThrottle = new RequestThrottle();

// ========== 查询缓存辅助函数（优化6：减少数据库查询） ==========

/**
 * 带缓存的数据库查询
 * @param {string} cacheKey - 缓存键
 * @param {Function} queryFn - 查询函数
 * @param {number} ttl - 缓存时间（毫秒），默认30秒
 * @returns {Promise<any>} 查询结果
 */
async function cachedQuery(cacheKey, queryFn, ttl = 30000) {
  return await queryCache.getOrSet(cacheKey, queryFn, ttl);
}

/**
 * 清除指定缓存
 * @param {string} cacheKey - 缓存键或前缀
 */
function invalidateCache(cacheKey) {
  if (cacheKey.endsWith('*')) {
    // 通配符删除
    const prefix = cacheKey.slice(0, -1);
    for (const key of queryCache.cache.keys()) {
      if (key.startsWith(prefix)) {
        queryCache.delete(key);
      }
    }
  } else {
    queryCache.delete(cacheKey);
  }
}

/**
 * 获取缓存统计信息
 * @returns {Object} 统计信息
 */
function getCacheStats() {
  return queryCache.getStats();
}

// ========== 导出工具函数 ==========
module.exports = {
  dbPool,
  Logger,
  AppError,
  handleError,
  Validator,
  requestThrottle,
  queryCache,
  cachedQuery,
  invalidateCache,
  getCacheStats,
};