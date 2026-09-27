/**
 * WebSocket连接管理器 - 优化版
 * 
 * 功能：管理WebSocket连接、角色索引、心跳检测
 * 优化：双索引结构、原生ping/pong、批量推送
 */

const WebSocket = require('ws');
const { Logger } = require('./utils');

// 🔥 ACK重试上限：超过此次数后停止重试，消息保留在离线队列等待上线补推
const MAX_RETRIES = 2;

class WSManager {
  constructor() {
    // 双索引结构
    this.clientsByAccount = new Map();  // account -> { account, type, ws }
    this.clientsByRole = new Map();     // role -> Set<account>

    // 🔥 注册时间追踪（毫秒时间戳），用于防止注册后立即触发 sync_notifications 导致重复推送
    this.registerTimes = new Map();     // account -> timestamp

    // 🔥 待确认 ACK 消息追踪（connection 断开时回滚 pending→failed，确保补推）
    this._pendingACKs = new Map();     // key: `${account}:${msgId}` -> { account, msgId, sentAt }

    // 🔥 ACK 超时追踪：5秒未收到回执则自动重试，超过最大次数后停止
    this._ackTimeouts = new Map();     // key: `${account}:${msgId}` -> NodeJS.Timeout
    // 🔥 每条消息的已用重试次数（key: `${account}:${msgId}` -> number），防止无限重试死循环
    this._retryCounts = new Map();     // key: `${account}:${msgId}` -> number

    // 统计信息
    this.stats = {
      totalConnections: 0,
      connectionsByRole: { 1: 0, 2: 0, 3: 0 },
      peakConnections: 0
    };
  }

  /**
   * 添加待确认 ACK 的消息 ID
   * @param {string} account - 用户账号
   * @param {string} msgId - 消息 ID
   */
  addPendingACK(account, msgId) {
    const key = `${account}:${msgId}`;
    this._pendingACKs.set(key, { account, msgId, sentAt: Date.now() });
  }

  /**
   * 从待确认 ACK 中移除已确认的消息
   * @param {string} account - 用户账号
   * @param {string} msgId - 消息 ID
   */
  removePendingACK(account, msgId) {
    const key = `${account}:${msgId}`;
    this._pendingACKs.delete(key);
    // 同时清除超时计时器
    this.removeACKTimeout(account, msgId);
  }

  /**
   * 清除指定消息的 ACK 超时计时器及重试计数
   * @param {string} account - 用户账号
   * @param {string} msgId - 消息 ID
   */
  removeACKTimeout(account, msgId) {
    const key = `${account}:${msgId}`;
    const timer = this._ackTimeouts.get(key);
    if (timer) {
      clearTimeout(timer);
      this._ackTimeouts.delete(key);
    }
    // 同步清除重试计数
    this._retryCounts.delete(key);
  }

  /**
   * 追踪 ACK 超时：首次推送后启动5秒计时器，超时自动重试一次，超过最大重试次数则停止
   * @param {string} account - 用户账号
   * @param {string} msgId - 消息 ID
   * @param {WebSocket} ws - WebSocket实例
   * @param {Object} msgData - 消息数据
   * @param {number} retryCount - 已用重试次数（0 = 首次推送，非零 = 重试后的再次追踪）
   */
  trackACKTimeout(account, msgId, ws, msgData, retryCount = 0) {
    const key = `${account}:${msgId}`;
    // 清除旧计时器（重试时会覆盖）
    this.removeACKTimeout(account, msgId);

    // 🔥 5秒后触发：若仍未收到ACK，则重试推送一次（若已达最大次数则停止）
    const timer = setTimeout(() => {
      this._ackTimeouts.delete(key);
      // 先回滚待确认记录（使其留在离线队列中供后续补推）
      this.rollbackPendingACKs(account);
      Logger.warn('WS_MANAGER', `⏰ ACK超时(5s)，当前重试次数: ${retryCount}, 消息: ${account} -> ${msgId}`);

      if (retryCount >= MAX_RETRIES) {
        Logger.warn('WS_MANAGER', `🚫 ACK重试已达上限(${MAX_RETRIES}次)，停止重试，消息保留在离线队列: ${account} -> ${msgId}`);
        return;
      }

      // 🔥 二次重试：重新发送消息并再次追踪ACK
      this._retryPushOnce(account, msgId, ws, msgData, retryCount + 1);
    }, 5000);

    this._ackTimeouts.set(key, timer);
  }

  /**
   * 二次重试推送：重新发送消息并再次追踪ACK（带重试计数，防止死循环）
   * @param {string} account - 用户账号
   * @param {string} msgId - 原始消息 ID
   * @param {WebSocket} ws - WebSocket实例
   * @param {Object} msgData - 消息数据
   * @param {number} retryCount - 本次重试的次数（第几次重试）
   */
  _retryPushOnce(account, msgId, ws, msgData, retryCount = 1) {
    if (ws.readyState !== WebSocket.OPEN) {
      Logger.warn('WS_MANAGER', `⚠️ 重试推送失败：${account} 连接已断开`);
      return;
    }
    // 生成新ID区分重试包，但保留原始msgId用于离线队列追踪
    const retryMsgData = { ...msgData, _id: `${msgId}_retry`, _retry: true };
    try {
      ws.send(JSON.stringify(retryMsgData), (err) => {
        if (err) {
          Logger.error('WS_MANAGER', `❌ 重试推送失败: ${account} -> ${msgId}`, err);
          // 重试发送失败，彻底回滚（保留在离线队列）
          this.rollbackPendingACKs(account);
          return;
        }
        Logger.info('WS_MANAGER', `🔄 重试推送成功: ${account} -> ${msgId} (第${retryCount}次)`);
        // 记录重试次数
        this._retryCounts.set(`${account}:${msgId}`, retryCount);
        // 重新追踪ACK超时（覆盖旧的计时器，传入当前重试次数）
        this.addPendingACK(account, msgId);
        this.trackACKTimeout(account, msgId, ws, retryMsgData, retryCount);
      });
    } catch (err) {
      Logger.error('WS_MANAGER', `❌ 重试推送异常: ${account} -> ${msgId}`, err);
      this.rollbackPendingACKs(account);
    }
  }

  /**
   * 断开连接时回滚所有待确认消息：pending → failed（保留在离线队列供补推）
   * @param {string} account - 用户账号
   * @returns {Array<{msgId: string}>} 回滚的消息列表
   */
  rollbackPendingACKs(account) {
    const rolledBack = [];
    for (const [key, val] of this._pendingACKs.entries()) {
      if (val.account === account) {
        this._pendingACKs.delete(key);
        rolledBack.push({ msgId: val.msgId });
      }
    }
    if (rolledBack.length > 0) {
      Logger.info('WS_MANAGER', `🔄 回滚 ${rolledBack.length} 条待确认消息（保持 pending，等待补推）: ${account}`);
    }
    return rolledBack;
  }

  /**
   * 添加客户端连接
   * @param {string} account - 用户账号
   * @param {number} type - 用户角色
   * @param {WebSocket} ws - WebSocket实例
   * @param {boolean} [verified=false] - 是否已通过会话Token鉴权
   */
  addClient(account, type, ws, verified = false) {
    // 如果账号已存在，关闭旧连接
    if (this.clientsByAccount.has(account)) {
      const oldClient = this.clientsByAccount.get(account);
      try {
        oldClient.ws.close();
        Logger.info('WS_MANAGER', `⚠️ 关闭 ${account} 的旧连接`);
      } catch (e) {
        Logger.error('WS_MANAGER', '关闭旧连接失败', e);
      }
      this.removeClient(account);
    }

    // 🔥 Bug修复：设置ws的account属性，方便反向查找
    ws._account = account;
    ws._type = type;

    // ✅ 会话Token鉴权标记（可选）：已校验token为true，旧客户端兜底为false
    ws._verified = verified;

    // 添加到双索引
    const client = { account, type, ws, verified };
    this.clientsByAccount.set(account, client);

    if (!this.clientsByRole.has(type)) {
      this.clientsByRole.set(type, new Set());
    }
    this.clientsByRole.get(type).add(account);

    // 更新统计
    this.stats.totalConnections = this.clientsByAccount.size;
    this.stats.connectionsByRole[type] = (this.stats.connectionsByRole[type] || 0) + 1;
    if (this.stats.totalConnections > this.stats.peakConnections) {
      this.stats.peakConnections = this.stats.totalConnections;
    }

    // 🔥 记录注册时间，用于防重复同步（isRecentlyRegistered 依赖此字段）
    this.registerTimes.set(account, Date.now());

    Logger.info('WS_MANAGER', `✅ 客户端上线: ${account} (角色: ${type}), 在线数: ${this.stats.totalConnections}`);
  }

  /**
   * 通过WebSocket实例获取账号（优化版：O(1)复杂度）
   * @param {WebSocket} ws - WebSocket实例
   * @returns {string|null} 用户账号
   */
  getAccountByWs(ws) {
    return ws._account || null;
  }

  /**
   * 移除客户端连接
   * @param {string} account - 用户账号
   */
  removeClient(account) {
    const client = this.clientsByAccount.get(account);
    if (!client) return;

    // 🔥 断开前回滚所有待确认消息（pending 保留，确保下次补推）
    this.rollbackPendingACKs(account);
    // 🔥 同时清除所有 ACK 超时计时器及重试计数，避免无效重试
    for (const [key, timer] of this._ackTimeouts.entries()) {
      if (key.startsWith(`${account}:`)) {
        clearTimeout(timer);
        this._ackTimeouts.delete(key);
        this._retryCounts.delete(key);
      }
    }

    // 从角色索引中移除
    const roleSet = this.clientsByRole.get(client.type);
    if (roleSet) {
      roleSet.delete(account);
      if (roleSet.size === 0) {
        this.clientsByRole.delete(client.type);
      }
    }

    // 从账号索引中移除
    this.clientsByAccount.delete(account);

    // 🔥 Bug修复：清理ws上的自定义属性
    try {
      delete client.ws._account;
      delete client.ws._type;
    } catch (e) {
      // 忽略删除属性失败
    }

    // 更新统计
    this.stats.totalConnections = this.clientsByAccount.size;
    this.stats.connectionsByRole[client.type] = Math.max(0, (this.stats.connectionsByRole[client.type] || 1) - 1);

    Logger.info('WS_MANAGER', `❌ 客户端下线: ${account}, 在线数: ${this.stats.totalConnections}`);
  }

  /**
   * 获取客户端信息
   * @param {string} account - 用户账号
   * @returns {Object|null} 客户端信息
   */
  getClient(account) {
    return this.clientsByAccount.get(account) || null;
  }

  /**
   * 获取指定角色的所有客户端账号
   * @param {number} role - 角色类型
   * @returns {Set<string>} 账号集合
   */
  getClientsByRole(role) {
    return this.clientsByRole.get(role) || new Set();
  }

  /**
   * 判断账号是否刚注册（用于防重复同步）
   * @param {string} account - 账号
   * @param {number} maxAgeMs - 最大年龄（毫秒），默认3000ms
   * @returns {boolean} 是否在保护期内
   */
  isRecentlyRegistered(account, maxAgeMs = 3000) {
    const registeredAt = this.registerTimes.get(account);
    if (!registeredAt) return false;
    return Date.now() - registeredAt < maxAgeMs;
  }

  /**
   * 向指定角色推送消息
   * @param {number|Array} targetRole - 目标角色（单个或数组）
   * @param {Object} msgData - 消息数据
   * @returns {Promise<Object>} 推送结果统计
   */
  async broadcastToRole(targetRole, msgData) {
    const msgId = msgData.id || msgData._id;
    let successCount = 0;
    let failCount = 0;
    let offlineCount = 0;

    // 确定目标角色列表
    const roles = Array.isArray(targetRole) ? targetRole : [targetRole];

    Logger.info('WS_MANAGER', `📤 开始推送消息 ${msgId} 到角色 ${JSON.stringify(roles)}`);

    // 遍历每个目标角色，收集所有发送任务并行执行
    const sendPromises = [];
    for (const role of roles) {
      const accounts = this.getClientsByRole(role);
      
      for (const account of accounts) {
        const client = this.getClient(account);
        
        if (!client || client.ws.readyState !== WebSocket.OPEN) {
          offlineCount++;
          continue;
        }

        sendPromises.push(
          new Promise((resolve) => {
            client.ws.send(JSON.stringify(msgData), (err) => {
              if (err) {
                Logger.error('WS_MANAGER', `❌ 推送到${account}失败`, err);
                resolve('fail');
              } else {
                resolve('success');
              }
            });
          })
        );
      }
    }

    // 并行等待所有发送完成
    const results = await Promise.allSettled(sendPromises);
    for (const r of results) {
      if (r.status === 'fulfilled') {
        if (r.value === 'success') successCount++;
        else failCount++;
      } else {
        failCount++;
      }
    }

    const result = {
      success: successCount,
      fail: failCount,
      offline: offlineCount,
      total: successCount + failCount + offlineCount
    };

    Logger.info('WS_MANAGER', `✅ 推送完成 - 成功: ${result.success}, 失败: ${result.fail}, 离线: ${result.offline}`);
    
    return result;
  }

  /**
   * 向单个用户推送消息
   * @param {string} account - 用户账号
   * @param {Object} msgData - 消息数据
   * @returns {Promise<boolean>} 是否推送成功
   */
  async sendToUser(account, msgData) {
    const client = this.getClient(account);

    if (!client || client.ws.readyState !== WebSocket.OPEN || client.ws._socket?.writable === false) {
      Logger.warn('WS_MANAGER', `⚠️ ${account} 不在线、连接不可用或 socket 已关闭`);
      return false;
    }

    // 🔥 额外检查：socket 是否已销毁或无法写入（半开连接检测）
    const socket = client.ws._socket;
    if (socket && (socket.destroyed || socket.writable === false)) {
      Logger.warn('WS_MANAGER', `⚠️ ${account} socket已销毁，标记为离线`);
      this.removeClient(account);
      return false;
    }

    try {
      await new Promise((resolve, reject) => {
        client.ws.send(JSON.stringify(msgData), (err) => {
          if (err) reject(err);
          else resolve();
        });
      });

      // 🔥 发送成功不等于送达成功，返回 'pending' 等待 ACK
      Logger.debug('WS_MANAGER', `📨 已发送(待确认)给 ${account}`);
      return 'pending';
    } catch (err) {
      Logger.error('WS_MANAGER', `❌ 推送到${account}失败`, err);
      return false;
    }
  }

  /**
   * 获取在线用户统计
   * @returns {Object} 统计信息
   */
  getStats() {
    return {
      ...this.stats,
      onlineUsers: this.stats.totalConnections,
      roles: Object.fromEntries(this.clientsByRole.entries())
    };
  }

  /**
   * 获取所有在线客户端（用于全局遍历）
   * @returns {Map} 客户端Map
   */
  getAllClients() {
    return this.clientsByAccount;
  }
}

// 创建全局单例
const wsManager = new WSManager();

module.exports = wsManager;
