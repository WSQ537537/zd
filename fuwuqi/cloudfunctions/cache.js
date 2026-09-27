/**
 * 内存缓存管理器（优化：减少数据库查询）
 * 
 * 功能：提供短期内存缓存，适用于高频读取、低频变化的数据
 * 特性：自动过期清理、大小限制、LRU淘汰策略
 */

class MemoryCache {
  constructor(options = {}) {
    this.cache = new Map();
    this.maxSize = options.maxSize || 1000; // 最大缓存条目数
    this.defaultTTL = options.defaultTTL || 60 * 1000; // 默认TTL 60秒
    this.cleanupInterval = options.cleanupInterval || 5 * 60 * 1000; // 清理间隔5分钟
    
    // 统计信息
    this.stats = {
      hits: 0,
      misses: 0,
      sets: 0,
      deletes: 0,
      evictions: 0
    };
    
    // 启动定期清理
    this._startCleanup();
  }

  /**
   * 获取缓存
   * @param {string} key - 缓存键
   * @returns {*} 缓存值或null
   */
  get(key) {
    const item = this.cache.get(key);
    
    if (!item) {
      this.stats.misses++;
      return null;
    }
    
    // 检查是否过期
    if (Date.now() > item.expiry) {
      this.cache.delete(key);
      this.stats.misses++;
      return null;
    }
    
    // 更新访问时间（LRU）：先删除再重新插入，让Map自动维护访问顺序（最近访问的在末尾）
    this.cache.delete(key);
    this.cache.set(key, item);
    item.lastAccess = Date.now();
    this.stats.hits++;
    
    return item.value;
  }

  /**
   * 设置缓存
   * @param {string} key - 缓存键
   * @param {*} value - 缓存值
   * @param {number} ttl - 过期时间（毫秒），可选
   */
  set(key, value, ttl = null) {
    // 如果key已存在，先删除再重新插入，让Map自动维护插入顺序
    if (this.cache.has(key)) {
      this.cache.delete(key);
    }
    
    // 如果缓存已满，删除最久未访问的项
    if (this.cache.size >= this.maxSize) {
      this._evictLRU();
    }
    
    this.cache.set(key, {
      value,
      expiry: Date.now() + (ttl || this.defaultTTL),
      createdAt: Date.now(),
      lastAccess: Date.now()
    });
    
    this.stats.sets++;
  }

  /**
   * 删除缓存
   * @param {string} key - 缓存键
   */
  delete(key) {
    const deleted = this.cache.delete(key);
    if (deleted) {
      this.stats.deletes++;
    }
    return deleted;
  }

  /**
   * 清空所有缓存
   */
  clear() {
    this.cache.clear();
  }

  /**
   * 检查键是否存在
   * @param {string} key - 缓存键
   * @returns {boolean}
   */
  has(key) {
    const item = this.cache.get(key);
    if (!item) return false;
    
    // 检查是否过期
    if (Date.now() > item.expiry) {
      this.cache.delete(key);
      return false;
    }
    
    return true;
  }

  /**
   * 获取缓存统计信息
   * @returns {Object} 统计信息
   */
  getStats() {
    const total = this.stats.hits + this.stats.misses;
    const hitRate = total > 0 ? (this.stats.hits / total * 100).toFixed(2) : 0;
    
    return {
      ...this.stats,
      size: this.cache.size,
      maxSize: this.maxSize,
      hitRate: `${hitRate}%`
    };
  }

  /**
   * 获取或设置缓存（便捷方法）
   * @param {string} key - 缓存键
   * @param {Function} fetchFn - 获取数据的函数
   * @param {number} ttl - 过期时间（毫秒）
   * @returns {*} 缓存值或新获取的值
   */
  async getOrSet(key, fetchFn, ttl = null) {
    // 先尝试从缓存获取
    const cached = this.get(key);
    if (cached !== null) {
      return cached;
    }
    
    // 缓存未命中，获取新数据
    const value = await fetchFn();
    
    // 存入缓存
    this.set(key, value, ttl);
    
    return value;
  }

  /**
   * LRU淘汰：删除最久未访问的项（利用Map插入顺序，第一个key即为最久未访问的）
   * @private
   */
  _evictLRU() {
    // Map按插入顺序排列，第一个key就是最久未访问的
    const oldestKey = this.cache.keys().next().value;
    
    if (oldestKey !== undefined) {
      this.cache.delete(oldestKey);
      this.stats.evictions++;
    }
  }

  /**
   * 启动定期清理过期项
   * @private
   */
  _startCleanup() {
    this._cleanupTimer = setInterval(() => {
      this._cleanup();
    }, this.cleanupInterval);
    
    // 防止定时器阻止进程退出
    if (this._cleanupTimer.unref) {
      this._cleanupTimer.unref();
    }
  }

  /**
   * 清理过期项
   * @private
   */
  _cleanup() {
    const now = Date.now();
    let cleaned = 0;
    
    for (const [key, item] of this.cache.entries()) {
      if (now > item.expiry) {
        this.cache.delete(key);
        cleaned++;
      }
    }
    
    if (cleaned > 0) {
      // 可选：记录清理日志
      // console.log(`[Cache] 清理了 ${cleaned} 个过期项`);
    }
  }

  /**
   * 销毁缓存实例
   */
  destroy() {
    if (this._cleanupTimer) {
      clearInterval(this._cleanupTimer);
    }
    this.clear();
  }
}

// 创建全局缓存实例
const queryCache = new MemoryCache({
  maxSize: 500,
  defaultTTL: 30 * 1000, // 30秒
  cleanupInterval: 2 * 60 * 1000 // 2分钟清理一次
});

// 导出
module.exports = {
  MemoryCache,
  queryCache
};