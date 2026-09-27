/**
 * 离线消息队列 - MongoDB持久化版
 * 
 * 功能：存储用户离线时的消息，上线后补推
 * 优化：使用MongoDB替代内存Map，支持服务器重启、分布式部署
 */

const { dbPool, Logger } = require('./utils');

const OFFLINE_COLLECTION = 'record'; // 你指定的集合名
const OFFLINE_MSG_TTL = 7 * 24 * 3600; // 7天过期

/**
 * 添加离线消息到队列
 * @param {string} account - 用户账号
 * @param {Object} msgData - 消息数据
 * @param {number} role - 用户角色
 */
async function addToOfflineQueue(account, msgData, role) {
  try {
    const collection = dbPool.getCollection(OFFLINE_COLLECTION);
    const msgId = msgData.id || msgData._id;
    
    if (!msgId) {
      Logger.warn('OFFLINE_QUEUE', '⚠️ 消息缺少ID，跳过离线存储');
      return;
    }

    // 检查是否已存在（避免重复），包括 pending 和 delivered 状态
    const exists = await collection.findOne({
      account,
      msgId: String(msgId),
    });

    if (exists) {
      Logger.debug('OFFLINE_QUEUE', `⏭️ 消息已存在离线队列: ${account} -> ${msgId} (status: ${exists.status})`);
      return;
    }

    // 插入离线消息
    await collection.insertOne({
      account,
      msgId: String(msgId),
      msgData,
      role,
      status: 'pending', // pending/delivered/expired
      createdAt: new Date(),
      expireAt: new Date(Date.now() + OFFLINE_MSG_TTL * 1000)
    });

    Logger.debug('OFFLINE_QUEUE', `➕ 离线消息已存储: ${account} -> ${msgId}`);
  } catch (err) {
    Logger.error('OFFLINE_QUEUE', '❌ 存储离线消息失败', err);
  }
}

/**
 * 获取用户的离线消息（自动过滤过期消息）
 * @param {string} account - 用户账号
 * @returns {Promise<Array>} 离线消息列表
 */
async function getOfflineMessages(account) {
  try {
    const collection = dbPool.getCollection(OFFLINE_COLLECTION);
    const now = new Date();
    
    // 🔥 优化：查询时过滤过期消息（TTL索引可能延迟，这里双重保险）
    const messages = await collection.find({
      account,
      status: 'pending',
      expireAt: { $gt: now } // 只返回未过期的消息
    }).sort({ createdAt: 1 }).toArray();

    // 🔥 优化：检查并清理已过期但未被TTL删除的消息
    const expiredMessages = await collection.find({
      account,
      status: 'pending',
      expireAt: { $lte: now }
    }).toArray();
    
    if (expiredMessages.length > 0) {
      Logger.debug('OFFLINE_QUEUE', `🗑️ 发现${expiredMessages.length}条过期未清理消息`);
      // 异步清理过期消息（不阻塞主流程）
      collection.updateMany(
        { 
          account, 
          status: 'pending',
          expireAt: { $lte: now }
        },
        { $set: { status: 'expired' } }
      ).catch(err => Logger.error('OFFLINE_QUEUE', '清理过期消息失败', err));
    }

    Logger.info('OFFLINE_QUEUE', `📥 获取 ${account} 的离线消息: ${messages.length}条`);
    return messages;
  } catch (err) {
    Logger.error('OFFLINE_QUEUE', '❌ 获取离线消息失败', err);
    return [];
  }
}

/**
 * 标记离线消息为已送达
 * @param {string} account - 用户账号
 * @param {string} msgId - 消息ID
 */
async function markOfflineDelivered(account, msgId) {
  try {
    const collection = dbPool.getCollection(OFFLINE_COLLECTION);
    
    await collection.updateOne(
      { account, msgId: String(msgId) },
      { $set: { status: 'delivered', deliveredAt: new Date() } }
    );

    Logger.debug('OFFLINE_QUEUE', `✅ 标记离线消息已送达: ${account} -> ${msgId}`);
  } catch (err) {
    Logger.error('OFFLINE_QUEUE', '❌ 标记送达失败', err);
  }
}

/**
 * 批量清理过期的离线消息
 * （由TTL索引自动清理，此方法用于手动清理）
 */
async function cleanExpiredOfflineMessages() {
  try {
    const collection = dbPool.getCollection(OFFLINE_COLLECTION);
    
    const result = await collection.deleteMany({
      expireAt: { $lt: new Date() }
    });

    if (result.deletedCount > 0) {
      Logger.info('OFFLINE_QUEUE', `🗑️ 清理过期离线消息: ${result.deletedCount}条`);
    }
  } catch (err) {
    Logger.error('OFFLINE_QUEUE', '❌ 清理过期消息失败', err);
  }
}

/**
 * 批量标记离线消息为已送达
 * @param {string} account - 用户账号
 * @param {string[]} msgIds - 消息ID数组
 */
async function markOfflineDeliveredBatch(account, msgIds) {
  try {
    const collection = dbPool.getCollection(OFFLINE_COLLECTION);
    const now = new Date();

    const bulkOps = msgIds.map(msgId => ({
      updateOne: {
        filter: { account, msgId: String(msgId) },
        update: { $set: { status: 'delivered', deliveredAt: now } }
      }
    }));

    await collection.bulkWrite(bulkOps, { ordered: false });

    Logger.debug('OFFLINE_QUEUE', `✅ 批量标记 ${msgIds.length} 条离线消息已送达: ${account}`);
  } catch (err) {
    Logger.error('OFFLINE_QUEUE', '❌ 批量标记送达失败', err);
  }
}

/**
 * 删除指定 msgId 的所有离线消息记录（管理员删除通知时用）
 * @param {string} msgId - 消息ID
 */
async function removeOfflineMessagesByMsgId(msgId) {
  try {
    const collection = dbPool.getCollection(OFFLINE_COLLECTION);
    const result = await collection.deleteMany({ msgId: String(msgId) });
    Logger.info('OFFLINE_QUEUE', `🗑️ 已清除离线队列中 msgId=${msgId} 的 ${result.deletedCount} 条待推送记录`);
    return result.deletedCount;
  } catch (err) {
    Logger.error('OFFLINE_QUEUE', '❌ 清除离线消息失败', err);
    return 0;
  }
}

/**
 * 初始化离线消息集合的索引
 * （在服务器启动时调用一次）
 */
async function initOfflineIndexes() {
  try {
    const collection = dbPool.getCollection(OFFLINE_COLLECTION);
    
    // 创建复合索引：加速查询用户的待推送消息
    await collection.createIndex(
      { account: 1, status: 1 },
      { name: 'idx_account_status' }
    );

    // 创建TTL索引：自动删除7天前的消息
    await collection.createIndex(
      { expireAt: 1 },
      { 
        name: 'idx_expire_at',
        expireAfterSeconds: 0 
      }
    );

    Logger.info('OFFLINE_QUEUE', '✅ 离线消息索引创建成功');
  } catch (err) {
    Logger.error('OFFLINE_QUEUE', '❌ 创建索引失败', err);
  }
}

module.exports = {
  addToOfflineQueue,
  getOfflineMessages,
  markOfflineDelivered,
  markOfflineDeliveredBatch,
  cleanExpiredOfflineMessages,
  initOfflineIndexes,
  removeOfflineMessagesByMsgId
};
