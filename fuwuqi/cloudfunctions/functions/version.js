const { dbPool } = require('../utils');
const fs = require('fs');
const fsPromises = require('fs').promises;
const path = require('path');
const { SERVER_HOST } = require('../config'); // ✅ 公网地址统一配置

// 核心：更新文件夹路径（确保后端项目根目录下有 update 文件夹）
const UPDATE_DIR = path.join(__dirname, 'update'); // version.js 同级目录创建 update 文件夹

// 数据集合：所有正式/内测版本统一存到 version 集合，用 updateType 区分
const VERSION_COL = 'version';

/**
 * 自动获取 Update 文件夹里的安装包信息
 * @param {string} type - 更新类型：wgt/apk（默认apk）
 */
async function getUpdatePackage(type = 'apk') {
  try {
    try {
      await fsPromises.access(UPDATE_DIR);
    } catch (err) {
      await fsPromises.mkdir(UPDATE_DIR, { recursive: true });
      return null;
    }

    const ext = type === 'wgt' ? '.wgt' : '.apk';
    const files = await fsPromises.readdir(UPDATE_DIR);
    const packageFile = files.find(file => file.endsWith(ext));

    if (!packageFile) return null;

    return {
      fileName: packageFile,
      downloadUrl: `${SERVER_HOST}/update/${packageFile}`
    };
  } catch (err) {
    console.error('读取 Update 文件夹失败：', err);
    return null;
  }
}

/**
 * 从 version 集合中查找正式版本（updateType = apk/wgt，或无 updateType 字段的旧记录）
 */
async function findFormalVersion(col) {
  const formal = await col.findOne({ $or: [
    { updateType: 'apk' },
    { updateType: 'wgt' },
    { updateType: { $exists: false } },
  ]});
  return formal;
}

/**
 * 从 version 集合中查找内测版本（updateType = beta）
 */
async function findBetaVersion(col) {
  return await col.findOne({ updateType: 'beta' });
}

/**
 * 一次性数据迁移：把旧的 beta_versions / beta_signups 集合数据迁移到 version 集合
 */
async function migrateLegacyData(col) {
  try {
    const oldBetaCol = dbPool.getCollection('beta_versions');
    const oldSignCol = dbPool.getCollection('beta_signups');

    // 1. 迁移旧 beta_versions
    const oldBetas = await oldBetaCol.find({}).toArray();
    if (oldBetas.length > 0) {
      const existing = await findBetaVersion(col);
      if (!existing) {
        const ob = oldBetas[0];
        const betaRecord = {
          version: ob.version,
          url: ob.url,
          updateInfo: ob.updateInfo || '',
          updateType: 'beta',
          startTs: ob.startTs || 0,
          endTs: ob.endTs || 0,
          startTimeStr: ob.startTimeStr || ob.startTime || '',
          endTimeStr: ob.endTimeStr || ob.endTime || '',
          pushEnabled: ob.pushEnabled !== false,
          signedAccounts: [],
          updateTime: new Date().toLocaleString(),
        };
        const result = await col.insertOne(betaRecord);
        const signups = await oldSignCol.find({}).toArray();
        if (signups.length > 0) {
          betaRecord.signedAccounts = signups.map(s => s.account).filter(Boolean);
          await col.updateOne({ _id: result.insertedId }, { $set: { signedAccounts: betaRecord.signedAccounts } });
        }
        console.log(`[迁移] 旧内测记录已迁移到 version 集合: ${ob.version}`);
      }
      await oldBetaCol.deleteMany({});
      console.log('[迁移] 已清空旧 beta_versions 集合');
    }

    // 迁移 beta_signups
    const remainingSignups = await oldSignCol.countDocuments({});
    if (remainingSignups > 0) {
      const beta = await findBetaVersion(col);
      if (beta) {
        const signups = await oldSignCol.find({}).toArray();
        const accounts = signups.map(s => s.account).filter(Boolean);
        const existingAccounts = Array.isArray(beta.signedAccounts) ? beta.signedAccounts : [];
        const merged = Array.from(new Set([...existingAccounts, ...accounts]));
        await col.updateOne({ _id: beta._id }, { $set: { signedAccounts: merged } });
        console.log(`[迁移] 已将 ${accounts.length} 条报名记录合并到 version 集合 signedAccounts`);
      }
      await oldSignCol.deleteMany({});
      console.log('[迁移] 已清空旧 beta_signups 集合');
    }
  } catch (e) {
    console.warn('[迁移] 旧数据迁移失败（可能不存在旧集合，可忽略）:', e.message);
  }
}

/**
 * 版本管理核心函数
 */
async function versionHandler(params) {
  try {
    const col = dbPool.getCollection(VERSION_COL);

    // 启动时自动迁移旧数据（仅第一次）
    if (!versionHandler._migrated) {
      versionHandler._migrated = true;
      await migrateLegacyData(col);
    }

    console.log(`[版本处理][${new Date().toLocaleString()}] action: ${params.action}`);

    // ==================== 正式更新 ====================

    // 1. 自动模式：读取 Update 文件夹并更新版本信息
    if (params.action === 'auto') {
      let packageInfo = await getUpdatePackage('apk');
      let updateType = 'apk';

      if (!packageInfo) {
        packageInfo = await getUpdatePackage('wgt');
        updateType = 'wgt';
      }

      if (!packageInfo) {
        return { success: false, message: '未找到安装包' };
      }

      const versionMatch = packageInfo.fileName.match(/v(\d+\.\d+\.\d+)/);
      const version = versionMatch ? versionMatch[1] : '1.0.0';

      // 只清除正式版本记录，保留内测记录
      await col.deleteMany({ $or: [
        { updateType: 'apk' },
        { updateType: 'wgt' },
        { updateType: { $exists: false } },
      ]});

      await col.insertOne({
        version, url: packageInfo.downloadUrl, updateInfo: '',
        updateType, updateTime: new Date().toLocaleString(), fileName: packageInfo.fileName
      });

      console.log('正式版本信息已读取');
      return { success: true, message: '版本信息已读取', data: { version, url: packageInfo.downloadUrl, updateInfo: '', updateType } };
    }

    // 2. 获取正式版本信息
    if (params.action === 'get') {
      const versionData = await findFormalVersion(col);

      if (!versionData) {
        let packageInfo = await getUpdatePackage('apk');
        let updateType = 'apk';
        if (!packageInfo) { packageInfo = await getUpdatePackage('wgt'); updateType = 'wgt'; }
        if (!packageInfo) return { success: false, message: '暂无版本信息' };
        const versionMatch = packageInfo.fileName.match(/v(\d+\.\d+\.\d+)/);
        const version = versionMatch ? versionMatch[1] : '1.0.0';
        return { success: true, data: { version, url: packageInfo.downloadUrl, updateInfo: '', updateType } };
      }

      return { success: true, data: { version: versionData.version, url: versionData.url, updateInfo: versionData.updateInfo || '', updateType: versionData.updateType || 'wgt' } };
    }

    // 3. 管理员手动设置正式版本
    if (params.action === 'set') {
      const { version, url, updateInfo, updateType = 'wgt' } = params;
      if (!version) return { success: false, message: '版本号不能为空' };

      let downloadUrl = url;
      if (!url) {
        const packageInfo = await getUpdatePackage(updateType);
        if (!packageInfo) return { success: false, message: '未找到安装包' };
        downloadUrl = packageInfo.downloadUrl;
      }

      // 只删除正式版本记录，保留内测记录
      await col.deleteMany({ $or: [
        { updateType: 'apk' },
        { updateType: 'wgt' },
        { updateType: { $exists: false } },
      ]});

      await col.insertOne({ version, url: downloadUrl, updateInfo: updateInfo || '', updateType, updateTime: new Date().toLocaleString() });

      console.log('正式版本信息已更新');
      return { success: true, message: '更新成功' };
    }

    // ==================== 内测更新（统一存入 version 集合） ====================

    // 4. 保存/更新内测版本信息
    if (params.action === 'saveBeta') {
      const { version, url, startTime, endTime, updateInfo, pushEnabled } = params;

      if (!version || !startTime || !endTime) {
        return { success: false, message: '版本号、开始时间、结束时间不能为空' };
      }

      const existing = await findBetaVersion(col);

      // 将内部时间转为时间戳存储
      const startTs = new Date(startTime).getTime();
      const endTs = new Date(endTime).getTime();

      const newRecord = {
        version,
        url: url || '',          // 仅后端存储，不返回给前端
        updateInfo: updateInfo || '',
        updateType: 'beta',
        startTs,
        endTs,
        startTimeStr: startTime,
        endTimeStr: endTime,
        pushEnabled: !!pushEnabled,
        updateTime: new Date().toLocaleString()
      };

      if (existing) {
        // 覆盖更新本条记录，保留已有的 signedAccounts
        const result = await col.updateOne(
          { _id: existing._id },
          { $set: newRecord }
        );
        console.log(`[saveBeta] 已覆盖更新内测记录: ${version}`);
        return { success: true, message: '保存成功（已覆盖）', data: { updated: true } };
      } else {
        // 插入新记录
        newRecord.signedAccounts = [];
        await col.insertOne(newRecord);
        console.log(`[saveBeta] 已保存新内测记录: ${version}`);
        return { success: true, message: '保存成功', data: { inserted: true } };
      }
    }

    // 5. 获取内测版本信息
    if (params.action === 'getBeta') {
      const record = await findBetaVersion(col);

      if (!record) return { success: true, data: null, message: '暂无内测版本' };

      return {
        success: true,
        data: {
          version: record.version,
          url: record.url,
          updateInfo: record.updateInfo || '',
          startTimeStr: record.startTimeStr || record.startTime || '',
          endTimeStr: record.endTimeStr || record.endTime || '',
          startTs: record.startTs || 0,
          endTs: record.endTs || 0,
          pushEnabled: record.pushEnabled !== false,
          signedAccounts: record.signedAccounts || [],
        }
      };
    }

    // 6. 删除内测记录（管理员清除）
    if (params.action === 'deleteBeta') {
      const result = await col.deleteMany({ updateType: 'beta' });
      console.log(`[deleteBeta] 已清除 ${result.deletedCount} 条内测记录`);
      return { success: true, message: '已清除' };
    }

    // 7. 用户报名内测（直接写入 version 记录的 signedAccounts 字段）
    if (params.action === 'signupBeta') {
      const user = params.user || params.account;
      if (!user) return { success: false, message: '用户标识不能为空' };

      const beta = await findBetaVersion(col);
      if (!beta) return { success: false, message: '暂无内测版本，无法报名' };

      // 检查是否已报名
      const existingAccounts = Array.isArray(beta.signedAccounts) ? beta.signedAccounts : [];
      if (existingAccounts.includes(user)) {
        return { success: true, message: '已报名过', data: { alreadySigned: true, account: user } };
      }

      // 确保 signedAccounts 字段存在并添加用户
      await col.updateOne(
        { _id: beta._id },
        { $addToSet: { signedAccounts: user } }
      );

      console.log(`[内测] ${user} 报名成功（已写入 version 集合 signedAccounts）`);
      return { success: true, message: '报名成功', data: { account: user } };
    }

    // 8. 获取用户内测状态
    if (params.action === 'getBetaStatus') {
      const user = params.user || params.account;
      if (!user) return { success: false, message: '用户标识不能为空' };

      const beta = await findBetaVersion(col);

      // 如果内测版本不存在
      if (!beta) {
        return { success: true, data: { hasBeta: false, signedUp: false, canDownload: false, timeStatus: 'noBeta', pushEnabled: false } };
      }

      const now = Date.now();
      const inRange = now >= beta.startTs && now <= beta.endTs;
      let timeStatus = 'noBeta';
      if (now < beta.startTs) timeStatus = 'notStarted';
      else if (now > beta.endTs) timeStatus = 'ended';
      else timeStatus = 'active';

      const signedAccounts = Array.isArray(beta.signedAccounts) ? beta.signedAccounts : [];
      const signedUp = signedAccounts.includes(user);
      const pushEnabled = beta.pushEnabled !== false;

      return {
        success: true,
        data: {
          hasBeta: true,
          signedUp,
          inRange,
          timeStatus,
          pushEnabled,
          endTs: beta.endTs,
          startTs: beta.startTs,
          version: beta.version,
          url: beta.url,
          updateInfo: beta.updateInfo || '',
          startTimeStr: beta.startTimeStr || beta.startTime || '',
          endTimeStr: beta.endTimeStr || beta.endTime || '',
        }
      };
    }

    // 9. 获取内测下载链接（需验证权限）
    if (params.action === 'downloadBeta') {
      const user = params.user || params.account;
      if (!user) return { success: false, message: '用户标识不能为空' };

      const beta = await findBetaVersion(col);
      if (!beta) return { success: false, message: '暂无内测版本' };

      const signedAccounts = Array.isArray(beta.signedAccounts) ? beta.signedAccounts : [];
      if (!signedAccounts.includes(user)) {
        return { success: false, message: '未报名内测，无下载资格' };
      }

      const now = Date.now();
      if (now > beta.endTs) {
        return { success: false, message: '内测已结束' };
      }

      return {
        success: true,
        data: { url: beta.url, version: beta.version }
      };
    }

    return { success: false, message: '无效的action' };

  } catch (err) {
    console.error('❌ 版本管理函数错误：', err);
    return { success: false, message: '版本服务异常：' + err.message };
  }
}

module.exports = { versionHandler };
