const { ObjectId } = require('mongodb');
// const { canShowMessage, markRead } = require('./messageHelper_redis'); // ✅ 使用Redis版
const { dbPool } = require('../utils');
const wsManager = require('../wsManager');
const offlineQueue = require('../offlineQueue');
const fs = require('fs');
const fsPromises = require('fs').promises;
const path = require('path');
const crypto = require('crypto');

const COLLECTION_NAME = 'text';

// 上传目录（统一至 Pictures，与试卷图片共用同一目录）
const UPLOAD_DIR = path.join(__dirname, 'Pictures');
(async () => {
  try {
    await fsPromises.mkdir(UPLOAD_DIR, { recursive: true });
  } catch (e) {
    // 目录已存在或其他错误，忽略
  }
})();

function generateFileName(originalName) {
  const ext = path.extname(originalName);
  return `${Date.now()}_${crypto.randomBytes(8).toString('hex')}${ext}`;
}

// 广播通知删除给在线客户端（按类型决定推送目标）
// type='feedback' 只推管理员(1)；type='system'|'department' 推全部[1,2,3]
async function broadcastNoticeDeleted(noticeId, type) {
  const msg = { action: 'notice_deleted', id: noticeId };
  if (type === 'feedback') {
    // 反馈只通知管理员，不向学生/家长推送
    await wsManager.broadcastToRole(1, msg);
  } else {
    // 系统/部门通知：向管理员、学生、家长广播
    for (const role of [1, 2, 3]) {
      await wsManager.broadcastToRole(role, msg);
    }
  }
}

async function handleFileUpload(req) {
  return new Promise((resolve, reject) => {
    const contentType = req.headers['content-type'];
    if (!contentType || !contentType.includes('multipart/form-data')) {
      return reject(new Error('不是 multipart 请求'));
    }
    const boundary = contentType.split('boundary=')[1];
    if (!boundary) return reject(new Error('缺少 boundary'));

    let body = [];
    req.on('data', chunk => body.push(chunk));
    req.on('end', async () => {
      const buffer = Buffer.concat(body);
      const boundaryBuf = Buffer.from(`--${boundary}`);

      let pos = 0;
      let fileFound = false;
      let fileName = null;
      let fileData = null;

      // 循环查找所有部分
      while (pos < buffer.length) {
        // 查找下一个 boundary
        let boundaryIndex = buffer.indexOf(boundaryBuf, pos);
        if (boundaryIndex === -1) break;
        let partStart = boundaryIndex + boundaryBuf.length;
        // 跳过 \r\n
        while (buffer[partStart] === 13 || buffer[partStart] === 10) partStart++;
        // 查找头部结束位置
        let headerEnd = buffer.indexOf(Buffer.from('\r\n\r\n'), partStart);
        if (headerEnd === -1) break;
        const headers = buffer.slice(partStart, headerEnd).toString();
        //console.log('📎 部分头部:', headers);

        // 检查是否是文件字段 (name="file")
        const nameMatch = headers.match(/name="([^"]+)"/);
        if (nameMatch && nameMatch[1] === 'file') {
          // 提取文件名
          let filenameMatch = headers.match(/filename="([^"]+)"/);
          if (!filenameMatch) {
            // 尝试 filename*=UTF-8''...
            filenameMatch = headers.match(/filename\*=UTF-8''([^\s]+)/);
          }
          if (!filenameMatch) {
            return reject(new Error('未找到文件名'));
          }
          fileName = decodeURIComponent(filenameMatch[1]);
          // 文件数据开始位置
          const dataStart = headerEnd + 4;
          // 查找下一个 boundary 作为结束
          let dataEnd = buffer.indexOf(boundaryBuf, dataStart);
          if (dataEnd === -1) dataEnd = buffer.length;
          // 去掉末尾的 \r\n（边界标记前的 CRLF）：仅当文件数据足够长且末尾确为 CRLF 时去除
          if (dataEnd - dataStart >= 2 && buffer[dataEnd - 2] === 13 && buffer[dataEnd - 1] === 10) dataEnd -= 2;
          fileData = buffer.slice(dataStart, dataEnd);
          fileFound = true;
          break;
        }
        // 移动到下一个部分
        pos = headerEnd;
      }

      if (!fileFound || !fileData) {
        return reject(new Error('未找到文件数据'));
      }

      const generatedName = generateFileName(fileName);
      const filePath = path.join(UPLOAD_DIR, generatedName);
      await fsPromises.writeFile(filePath, fileData);
      resolve({ fileName: generatedName, originalName: fileName, filePath });
    });
    req.on('error', reject);
  });
}
// 注意：此函数签名改为 (req, params)，支持文件上传
async function noticeHandler(req, params) {
  // 文件上传请求
  if (req && req.method === 'POST' && params && params.action === 'upload') {
    try {
      const { fileName } = await handleFileUpload(req);
      const fileUrl = `/notice-media/${fileName}`;
      return { success: true, url: fileUrl };
    } catch (err) {
      console.error('文件上传失败:', err);
      return { success: false, message: '上传失败' };
    }
  }

  try {
    const collection = dbPool.getCollection(COLLECTION_NAME);
    // 🔥 新增：添加 replyContent 参数
    const { action, type, content, id, studentId, status, studentRemark, _id, mediaList, replyContent, replyMediaList } = params;

    if (action === 'send') {
      if (!type) return { success: false, message: '类型不能为空' };
      if (!content && (!mediaList || !mediaList.length)) {
        return { success: false, message: '内容或媒体不能为空' };
      }
      const insertData = {
        type,
        content: content || '',
        mediaList: mediaList || [],
        createTime: new Date()
      };
      if (type === 'feedback') {
        insertData.studentId = studentId || '';
        insertData.studentRemark = studentRemark || '';
        insertData.status = status || 'unhandled';
      }
      const result = await collection.insertOne(insertData);
      
      // ✅ 根据不同类型推送通知
      if (global.pushMsg) {
        if (type === 'system' || type === 'department') {
          // 系统/部门通知：推送给学生和家长
          await global.pushMsg([2, 3], {
            id: result.insertedId.toString(),
            title: '新通知',
            content: '有新通知，请及时查看！',
            createTime: new Date(),
            type
          });
        } else if (type === 'feedback') {
          // 反馈：推送给管理员
          await global.pushMsg(1, {
            id: result.insertedId.toString(),
            title: '新反馈',
            content: `收到新的用户反馈，请及时处理！`,
            createTime: new Date(),
            type: 'feedback'
          });
        }
      }
      
      return { success: true, message: '发送成功' };
    }

    else if (action === 'list') {
      const page = parseInt(params.page) || 1;
      const limit = Math.min(parseInt(params.limit) || 10, 100);
      const skip = (page - 1) * limit;

      // 并行执行 count、find、readRecords 三个独立查询组
      const [systemCount, departmentCount, systemList, departmentList, readRecords] = await Promise.all([
        collection.countDocuments({ type: 'system' }),
        collection.countDocuments({ type: 'department' }),
        collection.find({ type: 'system' }).sort({ createTime: -1 }).skip(skip).limit(limit).toArray(),
        collection.find({ type: 'department' }).sort({ createTime: -1 }).skip(skip).limit(limit).toArray(),
        studentId
          ? dbPool.getCollection('noticeread').find({ studentId }).toArray()
          : Promise.resolve([])
      ]);

      // 计算已读标记与各类型已读数量（依赖 readRecords，串行处理）
      let readSet = new Set();
      let systemReadCount = 0;
      let departmentReadCount = 0;
      if (studentId && readRecords.length > 0) {
        readRecords.forEach(r => readSet.add(r.noticeId));
        if (readSet.size > 0) {
          const typeResult = await collection
            .find({ _id: { $in: Array.from(readSet).map(id => new ObjectId(id)) } })
            .project({ _id: 1, type: 1 })
            .toArray();
          const idTypeMap = new Map(typeResult.map(item => [item._id.toString(), item.type]));
          readSet.forEach(id => {
            const t = idTypeMap.get(id);
            if (t === 'system') systemReadCount++;
            else if (t === 'department') departmentReadCount++;
          });
        }
      }

      const format = (item) => ({
        id: item._id.toString(),
        type: item.type,
        content: item.content,
        mediaList: item.mediaList || [],
        createTime: item.createTime,
        isRead: readSet.has(item._id.toString())
      });
      const systemUnread = systemCount - systemReadCount;
      const departmentUnread = departmentCount - departmentReadCount;
      return {
        success: true,
        data: {
          systemList: systemList.map(format),
          departmentList: departmentList.map(format),
          pagination: {
            page,
            limit,
            systemTotal: systemCount,
            departmentTotal: departmentCount,
            systemUnread,
            departmentUnread
          }
        }
      };
    }

    else if (action === 'markRead') {
      if (!studentId || !id) return { success: false, message: '缺少参数' };
      const readColl = dbPool.getCollection('noticeread');
      await readColl.updateOne(
        { studentId, noticeId: id },
        { $set: { studentId, noticeId: id, readTime: new Date() } },
        { upsert: true }
      );
      return { success: true };
    }

    else if (action === 'getFeedback') {
      if (!studentId) return { success: false, message: '学生ID不能为空' };
      const feedbackList = await collection.find({ type: 'feedback', studentId }).sort({ createTime: -1 }).toArray();
      return {
        success: true,
        data: feedbackList.map(item => ({
          id: item._id.toString(),
          content: item.content,
          createTime: item.createTime,
          status: item.status || 'unhandled',
          studentRemark: item.studentRemark || '',
          mediaList: item.mediaList || [],
          replyContent: item.replyContent || '',
          replyMediaList: item.replyMediaList || [],
          replyTime: item.replyTime || null
        }))
      };
    }

    else if (action === 'adminList') {
      const allFeedback = await collection.find({ type: 'feedback' }).sort({ createTime: -1 }).toArray();
      return { success: true, data: allFeedback };
    }

    else if (action === 'handle') {
      if (!_id) return { success: false, message: '反馈ID不能为空' };
      
      // 🔥 新增：支持传入回复内容
      const updateData = { status: 'handled' };
      if (replyContent !== undefined && replyContent !== null) {
        updateData.replyContent = replyContent;
        updateData.replyTime = new Date().toISOString();
      }
      if (replyMediaList !== undefined && replyMediaList !== null) {
        updateData.replyMediaList = replyMediaList;
      }
      
      await collection.updateOne({ _id: new ObjectId(_id) }, { $set: updateData });
      return { success: true, message: '处理成功' };
    }

    else if (action === 'delete') {
      if (!id) return { success: false, message: 'ID不能为空' };
      try {
        const notice = await collection.findOne({ _id: new ObjectId(id) });
        console.log('📌 要删除的通知:', notice);

        if (notice && notice.mediaList && Array.isArray(notice.mediaList)) {
          for (const item of notice.mediaList) {
            try {
              const url = item.url;
              const fileName = url.split('/').pop();
              const realPath = path.join(UPLOAD_DIR, fileName);
              try {
                await fsPromises.unlink(realPath);
              } catch (e) {
                if (e.code !== 'ENOENT') console.log('⚠️ 删除文件出错:', e.message);
              }
            } catch (e) {}
          }
        }
        if (notice && notice.replyMediaList && Array.isArray(notice.replyMediaList)) {
          for (const item of notice.replyMediaList) {
            try {
              const url = item.url;
              const fileName = url.split('/').pop();
              const realPath = path.join(UPLOAD_DIR, fileName);
              try {
                await fsPromises.unlink(realPath);
              } catch (e) {
                if (e.code !== 'ENOENT') console.log('⚠️ 删除回复图片出错:', e.message);
              }
            } catch (e) {}
          }
        }

        const result = await collection.deleteOne({ _id: new ObjectId(id) });
        if (result.deletedCount > 0) {
          // 清除该消息在所有用户的离线队列中（未接收用户不再推送）
          await offlineQueue.removeOfflineMessagesByMsgId(id);
          // 🔥 广播删除通知给所有在线客户端，让已收到该通知的设备同步清除
          if (notice && notice.type) {
            await broadcastNoticeDeleted(id, notice.type);
          } else {
            // 未查询到 type 时，默认向所有角色广播
            await broadcastNoticeDeleted(id, 'system');
          }
        }
        return result.deletedCount > 0
          ? { success: true, message: '删除成功' }
          : { success: false, message: '未找到记录' };
      } catch (err) {
        console.error('❌ 删除异常:', err);
        return { success: false, message: '删除失败：' + err.message };
      }
    }

    // 👇 单独删除媒体文件接口（修复编辑/新建删媒体不删文件）
    else if (action === 'deleteMediaFile') {
      try {
        const { url } = params;
        if (!url) return { success: false, message: '缺少文件URL' };

        // 从URL里提取文件名（比如 /notice-media/xxx.jpg → 取 xxx.jpg）
        const fileName = url.split('/').pop();
        // 拼接文件在服务器的真实路径
        const realPath = path.join(UPLOAD_DIR, fileName);

        // 如果文件存在，就删除
        try {
          await fsPromises.unlink(realPath);
          console.log('✅ 单独删除媒体文件成功:', realPath);
        } catch (e) {
          console.log('⚠️ 文件不存在或删除失败:', realPath, e.message);
        }
        return { success: true };
      } catch (e) {
        console.log('❌ 单独删除媒体失败:', e.message);
        return { success: false, message: e.message };
      }
    }

    else if (action === 'update') {
      if (!id) return { success: false, message: '通知ID不能为空' };
      const updateData = {};
      if (content !== undefined) updateData.content = content;
      if (mediaList !== undefined) updateData.mediaList = mediaList;
      if (Object.keys(updateData).length === 0) {
        return { success: false, message: '没有要更新的字段' };
      }
      try {
        // ========== 新增：自动删除不在新列表里的旧文件 ==========
        // 1. 先查原来的通知
        const oldNotice = await collection.findOne({ _id: new ObjectId(id) });
        if (oldNotice && oldNotice.mediaList && mediaList) {
          // 2. 把新的媒体URL存成集合
          const newUrls = new Set(mediaList.map(m => m.url));
          // 3. 遍历旧媒体，不在新集合里的就删文件
          for (const oldItem of oldNotice.mediaList) {
            if (!newUrls.has(oldItem.url)) {
              try {
                const fname = oldItem.url.split('/').pop();
                const fpath = path.join(UPLOAD_DIR, fname);
                await fsPromises.unlink(fpath);
                console.log('✅ 编辑时删除旧文件:', fpath);
              } catch (e) {
                console.log('⚠️ 删旧文件失败:', e.message);
              }
            }
          }
        }

        // 4. 再更新数据库
        const result = await collection.updateOne({ _id: new ObjectId(id) }, { $set: updateData });
        return result.matchedCount > 0 ? { success: true, message: '修改成功' } : { success: false, message: '未找到该通知' };
      } catch (err) {
        return { success: false, message: 'ID格式错误' };
      }
    }

    else if (action === 'deleteBatch') {
      // 批量删除指定ID的通知（系统通知/学习通知）
      const { ids, type } = params;
      if (!ids || !Array.isArray(ids) || ids.length === 0) {
        return { success: false, message: 'ID列表不能为空' };
      }
      if (!type || (type !== 'system' && type !== 'department')) {
        return { success: false, message: '类型必须为 system 或 department' };
      }
      try {
        const objectIds = ids.map(id => new ObjectId(id));
        const result = await collection.deleteMany({ _id: { $in: objectIds }, type: type });

        if (result.deletedCount > 0) {
          // 清除已删通知在离线队列中的待推送记录
          for (const id of ids) {
            await offlineQueue.removeOfflineMessagesByMsgId(id);
          }
        }
        return { success: true, message: `已删除 ${result.deletedCount} 条${type === 'system' ? '系统' : '学习'}通知` };
      } catch (err) {
        console.error('❌ 批量删除通知异常:', err);
        return { success: false, message: '批量删除失败：' + err.message };
      }
    }

    else if (action === 'deleteAll') {
      try {
        const allFeedback = await collection.find({ type: 'feedback' }).toArray();
        const feedbackIds = allFeedback.map(f => f._id.toString());

        for (const f of allFeedback) {
          const allMedia = [...(f.mediaList || []), ...(f.replyMediaList || [])];
          await Promise.all(allMedia.map(async (item) => {
            try {
              const fileName = item.url.split('/').pop();
              await fsPromises.unlink(path.join(UPLOAD_DIR, fileName));
            } catch (e) {
              if (e.code !== 'ENOENT') console.log('⚠️ 批量删除图片出错:', e.message);
            }
          }));
        }

        const result = await collection.deleteMany({ type: 'feedback' });

        if (result.deletedCount > 0) {
          for (const fid of feedbackIds) {
            await offlineQueue.removeOfflineMessagesByMsgId(fid);
          }
        }
        return { success: true, message: `已删除 ${result.deletedCount} 条反馈` };
      } catch (err) {
        console.error('❌ 批量删除反馈异常:', err);
        return { success: false, message: '批量删除失败：' + err.message };
      }
    }

    else {
      return { success: false, message: '无效的 action' };
    }
  } catch (err) {
    console.error('通知接口异常:', err);
    return { success: false, message: '服务器内部错误' };
  }
}

exports.noticeHandler = noticeHandler;





