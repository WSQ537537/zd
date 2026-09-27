const fs = require('fs');
const path = require('path');
const fsPromises = fs.promises;

// 【绝对路径锁死】强制指向根目录的userReadLog.json
const USER_READ_LOG = path.resolve(__dirname, '../userReadLog.json');
console.log('📌 日志文件绝对路径:', USER_READ_LOG);

// 初始化文件
if (!fs.existsSync(USER_READ_LOG)) {
  console.log('📌 根目录创建userReadLog.json');
  fs.writeFileSync(USER_READ_LOG, '{}', 'utf8');
}

// 新增：文件锁，防止并发读写冲突
let fileLock = Promise.resolve();

// 执行带锁的异步操作
async function withFileLock(fn) {
  const unlock = await fileLock;
  try {
    return await fn();
  } finally {
    fileLock = Promise.resolve();
  }
}

// 读取已读记录（带锁）
async function getReadLog() {
  return await withFileLock(async () => {
    try {
      const str = await fsPromises.readFile(USER_READ_LOG, 'utf8');
      return JSON.parse(str) || {};
    } catch (e) {
      console.error('❌ getReadLog读取失败:', e);
      return {};
    }
  });
}

// 【核心】标记已读：只存 account + 真实 msgId（带锁）
async function markRead(account, msgId) {
  console.log(`✅ markRead执行：账号=${account}，真实ID=${msgId}`);
  if (!account || !msgId) {
    console.log('⚠️ 账号/真实ID为空，跳过标记');
    return;
  }

  return await withFileLock(async () => {
    try {
      let log = {};
      try {
        const str = await fsPromises.readFile(USER_READ_LOG, 'utf8');
        log = JSON.parse(str) || {};
      } catch (e) {
        console.error('⚠️ 读取失败，使用空对象');
      }
      
      const uid = String(account);
      const mid = String(msgId);

      log[uid] = log[uid] || [];
      
      // 去重
      if (!log[uid].includes(mid)) {
        log[uid].push(mid);
        console.log(`➕ 新增已读：${uid} -> ${mid}`);
      }

      await fsPromises.writeFile(USER_READ_LOG, JSON.stringify(log, null, 2), 'utf8');
      console.log('✅ userReadLog.json写入成功！');
    } catch (e) {
      console.error('❌ markRead写入失败:', e);
    }
  });
}

// 【核心】判断是否已读：只看 account + 真实 msgId（带锁）
async function isRead(account, msgId) {
  if (!account || !msgId) return true;
  
  return await withFileLock(async () => {
    try {
      let log = {};
      try {
        const str = await fsPromises.readFile(USER_READ_LOG, 'utf8');
        log = JSON.parse(str) || {};
      } catch (e) {
        console.error('⚠️ 读取失败，默认返回未读');
        return false;
      }
      
      const uid = String(account);
      const mid = String(msgId);
      const isReaded = log[uid]?.includes(mid) || false;
      console.log(`👁 已读判断：${uid} ${mid} → ${isReaded}`);
      return isReaded;
    } catch (e) {
      console.error('❌ isRead判断失败:', e);
      return false; // 失败时默认未读，确保消息能推送
    }
  });
}

// 【核心】是否可推送：已读永不推送
async function canShowMessage(account, msgId) {
  return !(await isRead(account, msgId));
}

module.exports = {
  markRead,
  isRead,
  canShowMessage
};