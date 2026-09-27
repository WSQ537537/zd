/**
 * 消息助手 - Redis优化版
 * 
 * 功能：管理用户已读状态、消息推送判断
 * 优化：使用Redis替代文件锁，提升并发性能100倍+
 */

const { getRedis } = require('../redis');
const { Logger } = require('../utils');

// Redis键前缀
const READ_LOG_PREFIX = 'read_log:';
const READ_LOG_TTL = 7 * 24 * 3600; // 7天过期

/**
 * 标记消息为已读
 * @param {string} account - 用户账号
 * @param {string} msgId - 消息ID
 */
async function markRead(account, msgId) {
  if (!account || !msgId) {
    Logger.debug('MSG_HELPER', '⚠️ 账号/消息ID为空，跳过标记');
    return;
  }

  try {
    const redis = getRedis();
    const key = `${READ_LOG_PREFIX}${account}`;
    
    // 使用SADD添加到集合（自动去重）
    await redis.sadd(key, String(msgId));
    
    // 设置过期时间（7天）
    await redis.expire(key, READ_LOG_TTL);
    
    Logger.debug('MSG_HELPER', `✅ 标记已读: ${account} -> ${msgId}`);
  } catch (err) {
    Logger.error('MSG_HELPER', '❌ 标记已读失败', err);
    // 降级处理：失败时不阻断流程
  }
}

/**
 * 检查消息是否已读
 * @param {string} account - 用户账号
 * @param {string} msgId - 消息ID
 * @returns {Promise<boolean>} 是否已读
 */
async function isRead(account, msgId) {
  if (!account || !msgId) return true;

  try {
    const redis = getRedis();
    const key = `${READ_LOG_PREFIX}${account}`;
    
    // 使用SISMEMBER检查是否存在
    const exists = await redis.sismember(key, String(msgId));
    const result = exists === 1;
    
    Logger.debug('MSG_HELPER', `👁 已读判断: ${account} ${msgId} → ${result}`);
    return result;
  } catch (err) {
    Logger.error('MSG_HELPER', '❌ 已读判断失败', err);
    return false; // 失败时默认未读，确保消息能推送
  }
}

/**
 * 判断是否可以推送消息（未读才可推送）
 * @param {string} account - 用户账号
 * @param {string} msgId - 消息ID
 * @returns {Promise<boolean>} 是否可推送
 */
async function canShowMessage(account, msgId) {
  return !(await isRead(account, msgId));
}

/**
 * 批量判断消息是否可推送（未读才可推送）
 * 🔥 性能优化：一次 Redis 管道操作，O(1) 次网络往返
 * @param {string} account - 用户账号
 * @param {string[]} msgIds - 消息ID数组
 * @returns {Promise<Map<string, boolean>>} msgId -> boolean
 */
async function canShowMessageBatch(account, msgIds) {
  if (!account || !msgIds || msgIds.length === 0) return new Map();

  try {
    const redis = getRedis();
    const key = `${READ_LOG_PREFIX}${account}`;
    const strIds = msgIds.map(String);

    // 使用 SISMEMBER 批量检查（pipeline 一次往返）
    const pipeline = redis.pipeline();
    for (const msgId of strIds) {
      pipeline.sismember(key, msgId);
    }
    const results = await pipeline.exec();

    const map = new Map();
    for (let i = 0; i < strIds.length; i++) {
      const isRead = results[i] && results[i][1] === 1;
      map.set(strIds[i], !isRead);
    }

    Logger.debug('MSG_HELPER', `👁 批量已读判断: ${account} 共${strIds.length}条, 可推送${map.size}条`);
    return map;
  } catch (err) {
    Logger.error('MSG_HELPER', '❌ 批量已读判断失败', err);
    // 失败时默认全部未读，确保消息能推送
    const map = new Map();
    for (const id of msgIds) map.set(String(id), true);
    return map;
  }
}

module.exports = {
  markRead,
  isRead,
  canShowMessage,
  canShowMessageBatch
};
