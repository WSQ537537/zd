const { ObjectId } = require('mongodb');
const { dbPool } = require('../utils');
const fsPromises = require('fs').promises; // 统一异步fs
const path = require('path');
const crypto = require('crypto');
const { SERVER_HOST } = require('../config'); // ✅ 公网地址统一配置

// MongoDB 集合名
const colName = 'video';

// 本地存储视频的文件夹（和启动文件统一）
const VIDEO_DIR = path.join(__dirname, 'videos');
// 公网地址前缀（从统一配置读取，更换地址只需改 config.js）
const PUBLIC_PREFIX = `${SERVER_HOST}/videos/`;

/**
 * 视频处理器：上传 / 查询 / 查询全部 / 删除
 * @param {Object} reqData - 请求数据（包含file、fileName、以及其他参数）
 * @returns {Promise<Object>} 统一格式结果
 */
async function videoHandler(reqData) {
  // 修复：直接使用完整请求数据，不拆分丢失 action
  const params = reqData;
  const file = reqData.file;
  const fileName = reqData.fileName;

  // 每次请求仅记录一行：action + 关键信息，不打印完整参数与文件 Buffer（避免刷屏）
  console.log(
    `[视频处理][${new Date().toLocaleString()}] 请求：${params.action}`,
    file ? { fileName, fileSizeMB: (file.length / 1024 / 1024).toFixed(2) + ' MB' } : {}
  );

  // 参数校验
  if (!params.action) {
    console.error(`[视频处理][${new Date().toLocaleString()}] 错误：缺少 action 参数`);
    return { success: false, msg: "缺少 action 参数（write/get/getAll/delete）" };
  }

  try {
    const collection = dbPool.getCollection(colName);

    // 确保videos文件夹存在
    try {
      await fsPromises.access(VIDEO_DIR);
    } catch (e) {
      await fsPromises.mkdir(VIDEO_DIR, { recursive: true }); // 异步创建
      console.log(`[视频处理][${new Date().toLocaleString()}] 创建videos文件夹：${VIDEO_DIR}`);
    }

    // 分支逻辑
    switch (params.action) {
      // 上传视频
      case 'write':
        if (!params.name) return { success: false, msg: "请填写视频名称" };
        if (!params.subject) return { success: false, msg: "请选择科目类型" };
        
        // 判断是在线视频还是本地视频
        const isOnline = params.isOnline === true || params.isOnline === 'true';
        
        if (isOnline) {
          // 在线视频上传：需要 url 参数
          if (!params.url) return { success: false, msg: "请提供视频链接" };
          
          // 验证URL格式
          try {
            new URL(params.url);
          } catch (e) {
            return { success: false, msg: "视频链接格式无效" };
          }
          
          // 直接保存在线视频信息到数据库
          const result = await collection.insertOne({
            name: params.name,
            subject: params.subject,
            fileName: '', // 在线视频没有本地文件名
            url: params.url, // 使用提供的在线链接
            createTime: new Date(),
            isOnline: true // 标记为在线视频
          });

          return {
            success: true,
            msg: "在线视频上传成功",
            data: {
              videoId: result.insertedId.toString(),
              name: params.name,
              subject: params.subject,
              url: params.url,
              isOnline: true
            }
          };
        } else {
          // 本地视频上传：需要 file 参数
          if (!file) return { success: false, msg: "请选择视频文件" };
          if (!fileName) return { success: false, msg: "无法获取文件名" };

          // 生成唯一文件名（保留原扩展名）
          const ext = path.extname(fileName) || '.mp4';
          const uniqueName = crypto.randomBytes(16).toString('hex') + ext;
          const savePath = path.join(VIDEO_DIR, uniqueName);
          const playUrl = PUBLIC_PREFIX + uniqueName;

          // 保存文件（异步写入）
          await fsPromises.writeFile(savePath, file);
          console.log(`[视频上传][${new Date().toLocaleString()}] 文件保存成功：${savePath}`);

          // 写入数据库
          const result = await collection.insertOne({
            name: params.name,
            subject: params.subject,
            fileName: uniqueName,
            url: playUrl,
            createTime: new Date(), // 🔥 修复：应该是 new Date() 而不是 new date()
            isOnline: false // 标记为本地视频
          });

          return {
            success: true,
            msg: "视频上传成功",
            data: {
              videoId: result.insertedId.toString(),
              name: params.name,
              subject: params.subject,
              url: playUrl,
              isOnline: false
            }
          };
        }

      // 查询单个视频
      case 'get':
        if (!params.videoId) return { success: false, msg: "请提供 videoId" };
        
        try {
          const video = await collection.findOne({
            _id: new ObjectId(params.videoId)
          });
          
          return video ?
            { success: true, msg: "查询成功", data: video } :
            { success: false, msg: "视频不存在" };
        } catch (err) {
          return { success: false, msg: "videoId格式错误" };
        }

      // 查询全部视频（支持按科目过滤 + 分页）— 并行化 count + find
      case 'getAll':
        const query = params.subject && params.subject !== '' ? { subject: params.subject } : {};
        const videoPage = parseInt(params.page) || 1;
        const videoLimit = Math.min(parseInt(params.limit) || 10, 100);
        const videoSkip = (videoPage - 1) * videoLimit;
        const [totalVideos, allVideos] = await Promise.all([
          collection.countDocuments(query),
          collection.find(query).sort({ createTime: -1 }).skip(videoSkip).limit(videoLimit).toArray()
        ]);

        // 将ObjectId转为字符串，方便前端使用
        const formattedVideos = allVideos.map(video => ({
          ...video,
          _id: video._id.toString(),
          videoId: video._id.toString() // 增加兼容字段
        }));

        return { success: true, msg: "查询成功", data: formattedVideos, pagination: { page: videoPage, limit: videoLimit, total: totalVideos, totalPages: Math.ceil(totalVideos / videoLimit) } };

      // 删除视频
      case 'delete':
        if (!params.videoId) return { success: false, msg: "请提供 videoId" };
        
        try {
          const targetVideo = await collection.findOne({
            _id: new ObjectId(params.videoId)
          });
          
          if (!targetVideo) return { success: false, msg: "视频不存在" };

          // 删除本地文件（异步）
          const filePath = path.join(VIDEO_DIR, targetVideo.fileName);
          // 只有本地视频才有 fileName，且文件存在才删除
          if (targetVideo.fileName) {
            try {
              await fsPromises.access(filePath);
              await fsPromises.unlink(filePath);
              console.log(`[视频删除][${new Date().toLocaleString()}] 本地文件删除成功：${filePath}`);
            } catch (e) {
              // 文件不存在，忽略
            }
          }

          // 删除数据库记录
          await collection.deleteOne({ _id: new ObjectId(params.videoId) });
          
          return { success: true, msg: "视频删除成功" };
        } catch (err) {
          return { success: false, msg: "videoId格式错误" };
        }

      // 无效action
      default:
        return { success: false, msg: `无效的 action：${params.action}` };
    }
  } catch (err) {
    console.error(`[视频处理异常][${new Date().toLocaleString()}]：${err.message}`);
    return { success: false, msg: `服务器内部错误：${err.message}` };
  }
}

module.exports = { videoHandler };