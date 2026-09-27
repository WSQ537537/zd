const http = require('http');
const fs = require('fs');
const fsPromises = require('fs').promises;
const path = require('path');
const WebSocket = require('ws');
// const { MongoClient } = require('mongodb'); // Removed, using dbPool now
const { canShowMessage, canShowMessageBatch, markRead } = require('./functions/messageHelper_redis'); // ✅ 使用Redis版
const { userHandler } = require('./functions/user');
const { videoHandler } = require('./functions/video');
const { examHandler } = require('./functions/exam');
const { timeHandler } = require('./functions/time');
const { noticeHandler } = require('./functions/notice');
const { versionHandler } = require('./functions/version');
const { signHandler, getBigScreenHtml } = require('./functions/sign');
const { exportHandler } = require('./functions/export');
const { explainHandler, getExplainHtml, getSession, setPendingScreenWs, clearPendingScreenWs } = require('./functions/explain');

// ========== 引入优化工具类 ==========
const { dbPool, Logger, handleError, requestThrottle } = require('./utils');
const { getRedis, closeRedis, testRedisConnection } = require('./redis'); // ✅ Redis连接
const wsManager = require('./wsManager'); // ✅ WebSocket管理器
const offlineQueue = require('./offlineQueue'); // ✅ 离线消息队列
const { SERVER_HOST } = require('./config'); // ✅ 公网地址统一配置（唯一改地址处）

// ========== 核心路径配置 + MongoDB配置 ==========
// 背景图状态码：内存维护；上传时更新为时间戳，删除时归零
// 服务器启动时从文件 mtime 恢复，避免重启归零导致前端缓存失效
let bgStateHash = 0;
const UPDATE_DIR = path.join(__dirname, 'functions', 'update');
const VIDEO_DIR = path.join(__dirname, 'functions', 'videos');
const PICTURE_DIR = path.join(__dirname, 'functions', 'Pictures');
const BG_DIR = path.join(__dirname, 'bg');
const PORT = 3000;

const MONGO_URL = 'mongodb://localhost:27017';
const DB_NAME = 'zdxt';
const COL_NAME = 'video';

// ========== 初始化数据库连接池 + Redis ==========
(async () => {
  try {
    await dbPool.connect(MONGO_URL, DB_NAME);
    Logger.info('SERVER', '✅ MongoDB连接池已就绪');
    
    // ✅ 测试Redis连接
    const redisOk = await testRedisConnection();
    if (redisOk) {
      Logger.info('SERVER', '✅ Redis连接成功');
    } else {
      Logger.warn('SERVER', '⚠️ Redis连接失败，将使用降级方案');
    }
    
    // ✅ 初始化离线消息索引
    await offlineQueue.initOfflineIndexes();
    
    // 恢复背景图状态码：若 background.png 存在，用文件 mtime 作为状态码
    const bgFilePath = path.join(BG_DIR, 'background.png');
    try {
      const stat = await fsPromises.stat(bgFilePath);
      bgStateHash = Math.max(stat.mtimeMs, stat.birthtimeMs);
      Logger.info('SERVER', `🖼️ 背景图状态码已恢复：${bgStateHash}（mtime=${stat.mtimeMs}）`);
    } catch {
      bgStateHash = 0;
      Logger.info('SERVER', '🖼️ 无背景图文件，状态码=0');
    }
    
    Logger.info('SERVER', '🚀 服务器启动完成，所有服务已就绪');
  } catch (err) {
    Logger.error('SERVER', '❌ 服务初始化失败', err);
    process.exit(1);
  }
})();

// 优雅关闭
process.on('SIGTERM', async () => {
  Logger.info('SERVER', '收到 SIGTERM 信号，正在关闭...');
  await dbPool.close();
  await closeRedis(); // ✅ 关闭Redis连接
  process.exit(0);
});

process.on('SIGINT', async () => {
  Logger.info('SERVER', '收到 SIGINT 信号，正在关闭...');
  await dbPool.close();
  await closeRedis(); // ✅ 关闭Redis连接
  process.exit(0);
});

// 创建HTTP服务
const server = http.createServer(async (req, res) => {
  // 生成请求ID用于追踪
  const requestId = `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS, HEAD, PUT, DELETE');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Range, Authorization');
  res.setHeader('Access-Control-Max-Age', '86400');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // ========== 统一错误处理包装函数 ==========
  const safeHandle = async (handler, context) => {
    try {
      const result = await handler();
      return result;
    } catch (error) {
      Logger.error(context, `请求失败 [${requestId}]`, error);
      return handleError(error, context);
    }
  };

  // ========== 响应辅助函数 ==========
  const sendJson = (data, statusCode = 200) => {
    if (!res.headersSent) {
      res.writeHead(statusCode, { 'Content-Type': 'application/json;charset=utf-8' });
      res.end(JSON.stringify(data));
    }
  };

  // ========== 通用API处理函数（优化：统一错误处理+请求节流） ==========
  const handleApiRequest = async (handler, context, throttleTimeout = 5000) => {
    let requestData = '';

    req.on('data', (chunk) => { 
      requestData += chunk.toString();
      // 防止超大请求体（限制10MB）
      if (requestData.length > 10 * 1024 * 1024) {
        Logger.error(context, '请求体过大');
        sendJson({ success: false, msg: '请求数据过大' }, 413);
        req.destroy();
      }
    });
    
    req.on('end', async () => {
      try {
        // 解析请求参数 - 支持多种格式
        let params;
        
        if (!requestData || requestData.trim() === '') {
          // 空请求体，使用默认空对象
          params = {};
        } else {
          try {
            // 判断数据格式类型
            const contentType = req.headers['content-type'] || '';
            const trimmedData = requestData.trim();
            
            if (contentType.includes('application/x-www-form-urlencoded') || 
                (!contentType.includes('application/json') && !trimmedData.startsWith('{') && !trimmedData.startsWith('['))) {
              // URL编码格式：action=getExamList&userId=123
              const querystring = require('querystring');
              params = querystring.parse(trimmedData);
            } else {
              // JSON格式：{"action":"getExamList","userId":"123"}
              params = JSON.parse(trimmedData);
            }
          } catch (parseErr) {
            Logger.error(context, '参数解析失败', { error: parseErr.message });
            sendJson({ success: false, msg: '参数格式错误' }, 400);
            return;
          }
        }

        // 生成节流key（优化：仅使用 action + 关键ID，避免对 params 做昂贵的 JSON.stringify。
        // 大请求体如图片上传 Base64 数 MB 时，每次序列化开销很大）
        const throttleKey = `${context}_${params.action || 'unknown'}_${params.examId || params.account || params.id || ''}`;

        // 使用请求节流（优化：防重复请求）
        const result = await requestThrottle.throttle(
          throttleKey,
          async () => {
            Logger.info(context, `处理请求 [${requestId}]`, { action: params.action });
            return await handler(params);
          },
          throttleTimeout
        );

        // 返回结果
        sendJson(result);
      } catch (err) {
        Logger.error(context, `接口异常 [${requestId}]`, err);
        const errorResult = handleError(err, context);
        sendJson(errorResult, errorResult.statusCode || 400);
      }
    });
  };

  // ========== 大屏页面 ==========
  if (req.url === '/display' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'text/html;charset=utf-8' });
    res.end(getBigScreenHtml());
    return;
  }

  // ========== 通知媒体静态服务（统一至 Pictures） ==========
  if (req.method === 'GET' && req.url.startsWith('/notice-media/')) {
    const fileName = path.basename(req.url);
    const filePath = path.join(__dirname, 'functions', 'Pictures', fileName);
    fs.stat(filePath, (err, stats) => {
      if (err || !stats.isFile()) {
        res.writeHead(404);
        res.end('File not found');
        return;
      }
      const ext = path.extname(filePath).toLowerCase();
      let contentType = 'application/octet-stream';
      if (ext === '.jpg' || ext === '.jpeg') contentType = 'image/jpeg';
      else if (ext === '.png') contentType = 'image/png';
      else if (ext === '.gif') contentType = 'image/gif';
      else if (ext === '.mp4') contentType = 'video/mp4';
      res.writeHead(200, { 'Content-Type': contentType });
      fs.createReadStream(filePath).pipe(res);
    });
    return;
  }

  // ========== 导出文件下载 ==========
  if (req.method === 'GET' && req.url.startsWith('/exports/')) {
    const fileName = decodeURIComponent(path.basename(req.url));
    const filePath = path.join(__dirname, 'exports', fileName);
    fs.stat(filePath, (err, stats) => {
      if (err || !stats.isFile()) {
        res.writeHead(404);
        res.end('File not found');
        return;
      }
      res.writeHead(200, {
        'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'Content-Disposition': `attachment; filename="${encodeURIComponent(fileName)}"`,
        'Content-Length': stats.size,
        'Cache-Control': 'no-cache'
      });
      fs.createReadStream(filePath).pipe(res);
    });
    return;
  }

  // ========== 背景图状态码接口 ==========
  if (req.url === '/api/getBgState' && req.method === 'GET') {
    const hasBg = fs.existsSync(path.join(BG_DIR, 'background.png'));
    res.writeHead(200, { 'Content-Type': 'application/json;charset=utf-8' });
    res.end(JSON.stringify({ success: true, state: bgStateHash, hasBg }));
    return;
  }

  // ========== 背景图静态访问 ==========
  if (req.method === 'GET' && req.url === '/bg/background.png') {
    try {
      const bgPath = path.join(BG_DIR, 'background.png');
      try { await fsPromises.access(bgPath); }
      catch {
        res.writeHead(404, { 'Content-Type': 'application/json;charset=utf-8' });
        res.end(JSON.stringify({ success: false, message: '背景图未上传' }));
        return;
      }
      const stat = await fsPromises.stat(bgPath);
      const fileSize = stat.size;
      const ext = path.extname(bgPath).toLowerCase();
      let contentType = 'image/png';
      if (ext === '.jpg' || ext === '.jpeg') contentType = 'image/jpeg';
      if (ext === '.gif') contentType = 'image/gif';
      if (ext === '.webp') contentType = 'image/webp';

      res.writeHead(200, {
        'Content-Type': contentType,
        'Content-Length': fileSize,
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0'
      });
      fs.createReadStream(bgPath).pipe(res);
    } catch (err) {
      console.error(`[背景图服务错误][${new Date().toLocaleString()}]：`, err);
      if (!res.headersSent) {
        res.writeHead(500, { 'Content-Type': 'application/json;charset=utf-8' });
        res.end(JSON.stringify({ success: false, message: '背景图读取失败' }));
      }
    }
    return;
  }

  // ========== 背景图上传接口 ==========
  if (req.url === '/api/setBg' && req.method === 'POST') {
    const contentType = req.headers['content-type'] || '';
    if (contentType.includes('multipart/form-data')) {
      let body = [];
      const boundaryMatch = contentType.match(/boundary=(.+)/);
      const boundary = boundaryMatch ? boundaryMatch[1] : '';

      req.on('data', (chunk) => { body.push(chunk); });
      req.on('end', async () => {
        try {
          const buffer = Buffer.concat(body);
          const parts = parseMultipart(buffer, boundary);
          if (!parts.files.file) {
            res.writeHead(400, { 'Content-Type': 'application/json;charset=utf-8' });
            res.end(JSON.stringify({ success: false, message: '未上传图片文件' }));
            return;
          }
          try { await fsPromises.access(BG_DIR); }
          catch { await fsPromises.mkdir(BG_DIR, { recursive: true }); }
          const bgPath = path.join(BG_DIR, 'background.png');
          await fsPromises.writeFile(bgPath, parts.files.file.data);
          bgStateHash = Date.now();
          console.log(`[背景图服务][${new Date().toLocaleString()}] 背景图保存成功：${bgPath}，状态码=${bgStateHash}`);
          res.writeHead(200, { 'Content-Type': 'application/json;charset=utf-8' });
          res.end(JSON.stringify({
            success: true,
            message: '背景图上传成功',
            url: `${SERVER_HOST}/bg/background.png`,
            state: bgStateHash
          }));
        } catch (err) {
          console.error(`[背景图上传错误][${new Date().toLocaleString()}]：`, err);
          if (!res.headersSent) {
            res.writeHead(500, { 'Content-Type': 'application/json;charset=utf-8' });
            res.end(JSON.stringify({ success: false, message: '背景图上传失败：' + err.message }));
          }
        }
      });
    } else {
      res.writeHead(400, { 'Content-Type': 'application/json;charset=utf-8' });
      res.end(JSON.stringify({ success: false, message: '仅支持multipart/form-data格式上传图片' }));
    }
    return;
  }

  // ========== 背景图删除接口 ==========
  if (req.url === '/api/deleteBg' && req.method === 'POST') {
    try {
      const bgPath = path.join(BG_DIR, 'background.png');
      try {
        await fsPromises.access(bgPath);
        await fsPromises.unlink(bgPath);
        bgStateHash = 0;
        console.log(`[背景图服务][${new Date().toLocaleString()}] 背景图删除成功，状态码已重置为0`);
        res.writeHead(200, { 'Content-Type': 'application/json;charset=utf-8' });
        res.end(JSON.stringify({ success: true, message: '背景图删除成功', state: 0 }));
      } catch {
        bgStateHash = 0;
        res.writeHead(200, { 'Content-Type': 'application/json;charset=utf-8' });
        res.end(JSON.stringify({ success: true, message: '暂无背景图可删除', state: 0 }));
      }
    } catch (err) {
      console.error(`[背景图删除错误][${new Date().toLocaleString()}]：`, err);
      res.writeHead(500, { 'Content-Type': 'application/json;charset=utf-8' });
      res.end(JSON.stringify({ success: false, message: '背景图删除失败：' + err.message }));
    }
    return;
  }

  // ========== 安装包下载服务 ==========
  if (req.method === 'GET' && req.url.startsWith('/update/')) {
    try {
      const fileName = path.basename(req.url);
      const apkPath = path.join(UPDATE_DIR, fileName);
      try { await fsPromises.access(apkPath); }
      catch {
        console.error(`[更新服务][${new Date().toLocaleString()}] 安装包不存在：`, apkPath);
        res.writeHead(404, { 'Content-Type': 'application/json;charset=utf-8' });
        res.end(JSON.stringify({ success: false, message: '安装包不存在' }));
        return;
      }
      const stat = await fsPromises.stat(apkPath);
      const fileSize = stat.size;
      const range = req.headers.range;
      const ext = path.extname(fileName).toLowerCase();
      let contentType = 'application/vnd.android.package-archive';
      if (ext === '.wgt') contentType = 'application/octet-stream';

      res.setHeader('Content-Type', contentType);
      res.setHeader('Content-Disposition', `attachment; filename="${fileName}"`);
      res.setHeader('Cache-Control', 'public, max-age=31536000');

      if (range) {
        const parts = range.replace(/bytes=/, "").split("-");
        const start = parseInt(parts[0], 10);
        const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;
        if (isNaN(start) || start >= fileSize) {
          res.writeHead(416, {
            'Content-Range': `bytes */${fileSize}`,
            'Content-Type': 'application/json;charset=utf-8'
          });
          res.end(JSON.stringify({ success: false, message: '请求范围超出文件大小' }));
          return;
        }
        const chunkSize = end - start + 1;
        res.writeHead(206, {
          'Content-Range': `bytes ${start}-${end}/${fileSize}`,
          'Accept-Ranges': 'bytes',
          'Content-Length': chunkSize
        });
        fs.createReadStream(apkPath, { start, end }).pipe(res);
      } else {
        res.writeHead(200, { 'Content-Length': fileSize });
        fs.createReadStream(apkPath).pipe(res);
      }
    } catch (err) {
      console.error(`[更新服务错误][${new Date().toLocaleString()}]：`, err);
      if (!res.headersSent) {
        res.writeHead(500, { 'Content-Type': 'application/json;charset=utf-8' });
        res.end(JSON.stringify({ success: false, message: '安装包下载失败' }));
      }
    }
    return;
  }

  // ========== 静态视频服务（优化：使用连接池） ==========
  if (req.method === 'GET' && req.url.startsWith('/videos/')) {
    try {
      const fileName = path.basename(req.url);
      Logger.debug('VIDEO', `请求视频: ${fileName} [${requestId}]`);
      
      // 使用连接池查询（优化：避免重复创建连接）
      const collection = dbPool.getCollection(COL_NAME);
      const video = await collection.findOne({ fileName: fileName });
      
      if (!video) {
        Logger.warn('VIDEO', `数据库无此视频: ${fileName}`);
        sendJson({ success: false, message: '视频不存在（数据库无记录）' }, 404);
        return;
      }

      const videoPath = path.join(VIDEO_DIR, fileName);
      try { await fsPromises.access(videoPath); }
      catch {
        Logger.error('VIDEO', `本地文件不存在: ${videoPath}`);
        sendJson({ success: false, message: '视频文件已被删除' }, 404);
        return;
      }

      const stat = await fsPromises.stat(videoPath);
      const fileSize = stat.size;
      const range = req.headers.range;
      if (range) {
        const parts = range.replace(/bytes=/, "").split("-");
        const start = parseInt(parts[0], 10);
        const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;
        if (isNaN(start) || start >= fileSize) {
          res.writeHead(416, {
            'Content-Range': `bytes */${fileSize}`,
            'Content-Type': 'application/json;charset=utf-8'
          });
          res.end(JSON.stringify({ success: false, message: '请求范围超出文件大小' }));
          return;
        }
        const chunkSize = end - start + 1;
        const stream = fs.createReadStream(videoPath, { start, end });
        res.writeHead(206, {
          'Content-Range': `bytes ${start}-${end}/${fileSize}`,
          'Accept-Ranges': 'bytes',
          'Content-Length': chunkSize,
          'Content-Type': 'video/mp4',
          'Cache-Control': 'public, max-age=31536000'
        });
        stream.pipe(res);
        stream.on('error', (err) => {
          console.error(`[视频流错误][${new Date().toLocaleString()}]：`, err);
          if (!res.headersSent) {
            res.writeHead(500, { 'Content-Type': 'application/json;charset=utf-8' });
            res.end(JSON.stringify({ success: false, message: '视频读取失败' }));
          }
        });
      } else {
        res.writeHead(200, {
          'Content-Type': 'video/mp4',
          'Content-Length': fileSize,
          'Accept-Ranges': 'bytes',
          'Cache-Control': 'public, max-age=31536000'
        });
        fs.createReadStream(videoPath).pipe(res);
      }
    } catch (err) {
      console.error(`[视频服务错误][${new Date().toLocaleString()}]：`, err);
      if (!res.headersSent) {
        res.writeHead(500, { 'Content-Type': 'application/json;charset=utf-8' });
        res.end(JSON.stringify({ success: false, message: '服务器内部错误：' + err.message }));
      }
    }
    return;
  }

  // ========== 静态图片服务 ==========
  if (req.method === 'GET' && req.url.startsWith('/Pictures/')) {
    try {
      const fileName = path.basename(req.url);
      const imgPath = path.join(PICTURE_DIR, fileName);
      try { await fsPromises.access(imgPath); }
      catch {
        console.error(`[图片服务][${new Date().toLocaleString()}] 图片不存在：`, imgPath);
        res.writeHead(404, { 'Content-Type': 'application/json;charset=utf-8' });
        res.end(JSON.stringify({ success: false, message: '图片不存在' }));
        return;
      }
      const stat = await fsPromises.stat(imgPath);
      const fileSize = stat.size;
      const range = req.headers.range;
      const ext = path.extname(fileName).toLowerCase();
      let contentType = 'image/png';
      if (ext === '.jpg' || ext === '.jpeg') contentType = 'image/jpeg';
      if (ext === '.gif') contentType = 'image/gif';
      if (ext === '.webp') contentType = 'image/webp';

      if (range) {
        const parts = range.replace(/bytes=/, "").split("-");
        const start = parseInt(parts[0], 10);
        const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;
        if (isNaN(start) || start >= fileSize) {
          res.writeHead(416, { 'Content-Range': `bytes */${fileSize}` });
          res.end();
          return;
        }
        const chunkSize = end - start + 1;
        const stream = fs.createReadStream(imgPath, { start, end });
        res.writeHead(206, {
          'Content-Range': `bytes ${start}-${end}/${fileSize}`,
          'Accept-Ranges': 'bytes',
          'Content-Length': chunkSize,
          'Content-Type': contentType,
          'Cache-Control': 'public, max-age=31536000'
        });
        stream.pipe(res);
      } else {
        res.writeHead(200, {
          'Content-Type': contentType,
          'Content-Length': fileSize,
          'Accept-Ranges': 'bytes',
          'Cache-Control': 'public, max-age=31536000'
        });
        fs.createReadStream(imgPath).pipe(res);
      }
    } catch (err) {
      console.error(`[图片服务错误][${new Date().toLocaleString()}]：`, err);
      if (!res.headersSent) {
        res.writeHead(500, { 'Content-Type': 'application/json;charset=utf-8' });
        res.end(JSON.stringify({ success: false, message: '服务器内部错误' }));
      }
    }
    return;
  }

  // ========== 版本接口（优化：使用统一处理） ==========
  if (req.url === '/api/version' && req.method === 'POST') {
    await handleApiRequest(async (params) => {
      return await versionHandler(params);
    }, 'VERSION');
    return;
  }

  // ========== 用户接口 ==========
  if (req.url === '/api/user' && req.method === 'POST') {
    await handleApiRequest(async (params) => {
      return await userHandler(params);
    }, 'USER', 5000);
    return;
  }

  // ========== 视频接口（优化：multipart和JSON分别处理） ==========
  if (req.url === '/api/video' && req.method === 'POST') {
    const contentType = req.headers['content-type'] || '';
    if (contentType.includes('multipart/form-data')) {
      let body = [];
      const boundaryMatch = contentType.match(/boundary=(.+)/);
      const boundary = boundaryMatch ? boundaryMatch[1] : '';
      
      req.on('data', (chunk) => { 
        body.push(chunk);
        // 防止超大文件上传（限制100MB）
        if (body.reduce((acc, cur) => acc + cur.length, 0) > 100 * 1024 * 1024) {
          Logger.error('VIDEO', '上传文件过大');
          sendJson({ success: false, message: '文件过大' }, 413);
          req.destroy();
        }
      });
      
      req.on('end', async () => {
        try {
          const buffer = Buffer.concat(body);
          const parts = parseMultipart(buffer, boundary);
          const params = {
            action: parts.fields.action || 'write',
            name: parts.fields.name || '',
            subject: parts.fields.subject || '',
            videoId: parts.fields.videoId || '',
            file: parts.files.file?.data,
            fileName: parts.files.file?.name || ''
          };
          
          const result = await videoHandler(params);
          sendJson(result);
        } catch (err) {
          Logger.error('VIDEO', '上传失败', err);
          sendJson({ success: false, message: '上传失败：' + err.message }, 400);
        }
      });
    } else {
      await handleApiRequest(async (params) => {
        return await videoHandler(params);
      }, 'VIDEO');
    }
    return;
  }

  // ========== 试卷接口（优化：支持多种Content-Type + 统一错误处理） ==========
  if (req.url === '/api/exam' && req.method === 'POST') {
    await handleApiRequest(async (params) => {
      // 兼容不同Content-Type的参数解析已在handleApiRequest中处理
      return await examHandler(params);
    }, 'EXAM');
    return;
  }

  // ========== 时长接口（优化：统一错误处理） ==========
  if (req.url === '/api/time' && req.method === 'POST') {
    await handleApiRequest(async (params) => {
      return await timeHandler(params);
    }, 'TIME');
    return;
  }

  // ========== 通知接口【最小侵入版 · 不动notice内部逻辑】 ==========
  if (req.url === '/api/notice' && req.method === 'POST') {
    const contentType = req.headers['content-type'] || '';

    // 如果是文件上传，我们直接把完整 req 传给 noticeHandler，让它自己解析
    // 完全不拦截、不解析、不修改，100% 保持你原来的逻辑
    if (contentType.includes('multipart/form-data')) {
      try {
        const result = await noticeHandler(req, { action: 'upload' });
        sendJson(result);
      } catch (err) {
        Logger.error('NOTICE', '上传失败', err);
        sendJson({ success: false, message: '上传失败：' + err.message }, 400);
      }
      return;
    }

    // 普通 JSON 请求，使用统一处理
    await handleApiRequest(async (params) => {
      return await noticeHandler(req, params);
    }, 'NOTICE');
    return;
  }

  // ========== 签到接口（优化：统一错误处理） ==========
  if (req.url === '/api/sign' && req.method === 'POST') {
    await handleApiRequest(async (params) => {
      return await signHandler(params);
    }, 'SIGN');
    return;
  }

  // ========== 数据导出接口 ==========
  if (req.url === '/api/export' && req.method === 'POST') {
    await handleApiRequest(async (params) => {
      return await exportHandler(params);
    }, 'EXPORT', 120000);
    return;
  }

  // ========== 讲解接口（HTTP） ==========
  if (req.url === '/api/explain' && req.method === 'POST') {
    await handleApiRequest(async (params) => {
      // sendCmd 已通过 WebSocket 替代，不再处理 HTTP 请求
      if (params.action === 'sendCmd') {
        return { success: false, msg: 'sendCmd 已通过 WebSocket 发送，请勿使用 HTTP' };
      }
      return await explainHandler(params);
    }, 'EXPLAIN');
    return;
  }

  // ========== 讲解大屏页面 ==========
  if (req.url === '/explain' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'text/html;charset=utf-8' });
    res.end(getExplainHtml());
    return;
  }

  // ========== 404 处理 ==========
  res.writeHead(404, { 'Content-Type': 'application/json;charset=utf-8' });
  res.end(JSON.stringify({ success: false, message: '接口不存在' }));
});

// ========== 辅助函数：解析 multipart（性能优化版 · 不大内存） ==========
function parseMultipart(buffer, boundary) {
  const parts = { fields: {}, files: {} };
  if (!boundary) return parts;

  const separator = Buffer.from(`--${boundary}\r\n`, 'utf8');
  const endSeparator = Buffer.from(`--${boundary}--`, 'utf8');

  let start = buffer.indexOf(separator);
  while (start !== -1) {
    const next = buffer.indexOf(separator, start + separator.length);
    if (next === -1) break;

    const block = buffer.slice(start + separator.length, next);
    const headEnd = block.indexOf('\r\n\r\n');
    if (headEnd === -1) {
      start = next;
      continue;
    }

    const head = block.slice(0, headEnd).toString('utf8');
    const body = block.slice(headEnd + 4);

    const nameMatch = head.match(/name="([^"]+)"/);
    if (!nameMatch) {
      start = next;
      continue;
    }
    const field = nameMatch[1];

    const filenameMatch = head.match(/filename="([^"]*)"/);
    if (filenameMatch && filenameMatch[1]) {
      parts.files[field] = {
        name: filenameMatch[1],
        data: body
      };
    } else {
      parts.fields[field] = body.toString('utf8').trim();
    }

    start = next;
  }

  const endPos = buffer.indexOf(endSeparator);
  if (endPos !== -1 && start !== -1) {
    const block = buffer.slice(start + separator.length, endPos);
    const headEnd = block.indexOf('\r\n\r\n');
    if (headEnd !== -1) {
      const head = block.slice(0, headEnd).toString('utf8');
      const body = block.slice(headEnd + 4);
      const nameMatch = head.match(/name="([^"]+)"/);
      if (nameMatch) {
        const field = nameMatch[1];
        const filenameMatch = head.match(/filename="([^"]*)"/);
        if (filenameMatch && filenameMatch[1]) {
          parts.files[field] = {
            name: filenameMatch[1],
            data: body
          };
        } else {
          parts.fields[field] = body.toString('utf8').trim();
        }
      }
    }
  }

  return parts;
}

// ========== WebSocket 服务（优化版：使用wsManager + 原生心跳） ==========
// ⚠️ 关键修复：使用 noServer 模式 + 手动路由
// 原因：当两个 WebSocket.Server 都绑定同一个 HTTP server 且设置 path 时，
// 每个服务器都会注册自己的 upgrade 监听器。路径不匹配的一方会调用
// abortHandshake(socket, 400) 往 socket 写入 HTTP 400 并销毁它，
// 导致另一个服务器也无法正常处理连接——主推送和讲解大屏同时被破坏。
// 改用 noServer 后，只有一个统一的 upgrade 处理器按路径分发，
// 不会触发 abortHandshake。
const wss = new WebSocket.Server({
  noServer: true,
  clientTracking: true,
  perMessageDeflate: false,
  maxPayload: 1024 * 1024, // 1MB最大负载
});

const explainWss = new WebSocket.Server({ noServer: true });

// ✅ 统一的 upgrade 处理器：按路径路由到对应的 WebSocket 服务器
server.on('upgrade', (req, socket, head) => {
  const idx = req.url.indexOf('?');
  const pathname = idx !== -1 ? req.url.slice(0, idx) : req.url;

  if (pathname === '/explain-ws') {
    explainWss.handleUpgrade(req, socket, head, (ws) => {
      explainWss.emit('connection', ws, req);
    });
  } else {
    wss.handleUpgrade(req, socket, head, (ws) => {
      wss.emit('connection', ws, req);
    });
  }
});
explainWss.on('connection', (ws, req) => {
  ws.isAlive = true;
  Logger.info('EXPLAIN_WS', '新连接建立');

  // ✅ 立即发送 connected 消息，让客户端知道连接成功
  // 客户端收到后会发送 admin_join 或 screen_join
  ws.send(JSON.stringify({ type: 'connected', examId: null }));

  ws.on('message', async (msg) => {
    try {
      const data = JSON.parse(msg.toString());

      // 心跳
      if (data.type === 'pong') {
        ws.isAlive = true;
        return;
      }
      if (data.type === 'ping') {
        ws.send(JSON.stringify({ type: 'pong' }));
        return;
      }

      // 管理员加入（建立管理连接，不覆盖大屏连接）
      if (data.type === 'admin_join') {
        const session = getSession();
        if (session) {
          session.adminWs = ws;
          // 更新 connected 消息，带上 examId
          ws.send(JSON.stringify({ type: 'connected', examId: session.examId }));
          Logger.info('EXPLAIN_WS', `管理员已加入讲解 ${session.examId}, screenWs readyState=${session.screenWs?.readyState}`);
        } else {
          Logger.warn('EXPLAIN_WS', '管理员 join 但无 session');
        }
        return;
      }

      // 大屏加入：自动关联当前讲解（无码直连）
      if (data.type === 'screen_join') {
        // ✅ 无论 session 是否存在，都暂存大屏 ws
        // 解决时序竞态：大屏先连接时 session 不存在，ws 会丢失
        setPendingScreenWs(ws);
        Logger.info('EXPLAIN_WS', '大屏 ws 已暂存到 pendingScreenWs');

        const session = getSession();
        if (session) {
          session.screenWs = ws;
          ws.send(JSON.stringify({ type: 'connected', examId: session.examId }));
          Logger.info('EXPLAIN_WS', `大屏已加入讲解 ${session.examId}`);
          // 立即推送当前题目，确保重连后大屏能恢复显示
          if (session.currentQuestion) {
            ws.send(JSON.stringify({
              type: 'start',
              examId: session.examId,
              examName: session.examName,
              questionIndex: session.currentQuestionIndex ?? 0,
              totalQuestions: session.totalQuestions ?? 0,
              question: session.currentQuestion,
            }));
          } else if (session.questions && session.questions.length > 0) {
            // 极端时序：session 存在但 currentQuestion 为空（如 startExplaining 刚创建还没收到题目）
            // 推送第一题作为兜底
            const firstQ = session.questions[0];
            if (firstQ) {
              session.currentQuestion = firstQ;
              session.currentQuestionIndex = 0;
              ws.send(JSON.stringify({
                type: 'start',
                examId: session.examId,
                examName: session.examName,
                questionIndex: 0,
                totalQuestions: session.totalQuestions,
                question: firstQ,
              }));
            }
          }
        } else {
          Logger.info('EXPLAIN_WS', '大屏已连接，但暂无讲解进行中，等待老师发起讲解');
        }
        return;
      }

      // 大屏注册（兼容旧逻辑，带 examId 的显式注册）
      if (data.type === 'screen_register') {
        const examId = data.examId || null;
        if (examId) {
          const session = getSession();
          if (session && session.examId === examId) {
            session.screenWs = ws;
            ws.send(JSON.stringify({ type: 'connected', examId }));
          }
        }
        return;
      }

      // 管理员指令：通过 adminWs 实时推送到 screenWs（替代 HTTP sendCmd）
      if (data.type === 'cmd') {
        const session = getSession();
        if (!session) {
          Logger.warn('EXPLAIN_WS', `cmd 无 session: ${data.cmd}`);
          return;
        }
        const { cmd, questionIndex, ...rest } = data;
        const qIndex = questionIndex ?? 0;
        Logger.info('EXPLAIN_WS', `收到 cmd: ${cmd}, qIndex=${qIndex}, screenWs readyState=${session.screenWs?.readyState}, adminWs=${!!session.adminWs}`);

        // 结束讲解：直接清理 session 并通知大屏
        if (cmd === 'endExplaining') {
          const session = getSession();
          if (session && session.screenWs && session.screenWs.readyState === WebSocket.OPEN) {
            session.screenWs.send(JSON.stringify({ type: 'end' }));
          }
          removeSession();
          Logger.info('EXPLAIN_WS', '讲解已结束，session 已清除');
          return;
        }

        // 开始讲解：通过 HTTP 处理（需要创建 session）
        if (cmd === 'startExplaining') {
          // 通过 HTTP 触发（保持现有逻辑）
          return;
        }

        if (session.screenWs && session.screenWs.readyState === WebSocket.OPEN) {
          // 导航类指令和显隐类指令：从 session 获取完整题目数据
          let question = null;
          if (['next', 'prev', 'jump', 'question', 'show-answer', 'show-analysis'].includes(cmd) && session.questions) {
            question = session.questions[qIndex] || null;
            session.currentQuestion = question;
            session.currentQuestionIndex = qIndex;
          }
          const payload = {
            type: cmd,
            questionIndex: qIndex,
            examId: session.examId,
            ...(question ? { question } : {}),
          };
          if (session.examName) payload.examName = session.examName;
          if (session.totalQuestions) payload.totalQuestions = session.totalQuestions;
          // 透传额外字段（统计/答错/切tab等）
          for (const key of ['correctUsers', 'wrongUsers', 'account', 'userAnswer', 'tab']) {
            if (rest[key] !== undefined) payload[key] = rest[key];
          }
          Logger.info('EXPLAIN_WS', `转发 cmd 到大屏: ${cmd}, questionIndex=${qIndex}`);
          session.screenWs.send(JSON.stringify(payload));
          return;
        }
        // screenWs 离线，忽略
        Logger.warn('EXPLAIN_WS', `screenWs 离线，忽略 cmd: ${cmd}, readyState=${session.screenWs?.readyState}`);
        return;
      }

      Logger.debug('EXPLAIN_WS', `收到消息: ${JSON.stringify(data)}`);
    } catch (e) {
      Logger.error('EXPLAIN_WS', '处理消息失败', e);
    }
  });

  ws.on('close', () => {
    // ✅ 清理 pendingScreenWs
    clearPendingScreenWs(ws);

    const session = getSession();
    if (session) {
      if (session.screenWs === ws) {
        Logger.info('EXPLAIN_WS', '大屏断开');
        session.screenWs = null;
      }
      if (session.adminWs === ws) {
        Logger.info('EXPLAIN_WS', '管理员连接断开');
        session.adminWs = null;
      }
    }
  });

  ws.on('error', (err) => {
    Logger.error('EXPLAIN_WS', '错误', err);
  });

  // 监听原生 pong 帧，标记连接存活（配合下方 explainHeartbeatInterval 使用）
  ws.on('pong', () => {
    ws.isAlive = true;
  });
});

// ✅ explainWss 服务端心跳（与主推送 WS 独立，互不干扰）
// 每30秒 ping 一次，清理无响应的半开连接，防止 session.screenWs 指向死连接
const explainHeartbeatInterval = setInterval(() => {
  explainWss.clients.forEach(ws => {
    try {
      const socket = ws._socket;
      if (!socket || socket.destroyed || socket.writable === false) {
        // socket 已销毁或不可写，清理 session 中的引用
        const session = getSession();
        if (session) {
          if (session.screenWs === ws) {
            Logger.info('EXPLAIN_WS', '🧹 清理半开大屏连接（socket不可写）');
            session.screenWs = null;
          }
          if (session.adminWs === ws) {
            Logger.info('EXPLAIN_WS', '🧹 清理半开管理员连接（socket不可写）');
            session.adminWs = null;
          }
        }
        clearPendingScreenWs(ws);
        ws.terminate();
        return;
      }
      ws.ping();
    } catch (e) {
      Logger.error('EXPLAIN_WS', 'ping 发送异常，断开连接', e);
      const session = getSession();
      if (session) {
        if (session.screenWs === ws) session.screenWs = null;
        if (session.adminWs === ws) session.adminWs = null;
      }
      clearPendingScreenWs(ws);
      ws.terminate();
      return;
    }
    ws.isAlive = false;
  });
}, 30000);

if (explainHeartbeatInterval.unref) {
  explainHeartbeatInterval.unref();
}

// ✅ 删除旧的clients Map、heartbeatTimers、offlineMessageQueue
// 现在使用 wsManager 和 offlineQueue 模块

// ✅ 全局心跳定时器（每30秒检查一次，移动端弱网下不过于激进）
// 🔥 核心修复：先发送ping，再标记isAlive=false
// 原因：原来在ping前先设isAlive=false，若pong回包延迟到达，
// 会错过本次检测周期，被错误判定为下线；
// 改为先ping后标记，确保pong无论何时到达都能被正确识别。
const heartbeatInterval = setInterval(() => {
  wss.clients.forEach(ws => {
    // 🔥 先ping（不修改isAlive），pong到达后再标记false
    try {
      const socket = ws._socket;
      if (!socket || socket.destroyed || socket.writable === false) {
        // socket已销毁或不可写，立即断开
        const account = wsManager.getAccountByWs(ws);
        if (account) {
          wsManager.removeClient(account);
          Logger.info('WS', `✅ 已移除半开连接客户端: ${account}`);
        }
        ws.terminate();
        return;
      }
      ws.ping(); // 原生ping帧，客户端自动回复pong → ws.on('pong')回调设置isAlive=true
    } catch (e) {
      Logger.error('WS', 'ping发送异常，断开连接', e);
      const account = wsManager.getAccountByWs(ws);
      if (account) wsManager.removeClient(account);
      ws.terminate();
      return;
    }

    // 🔥 ping发送成功后，才标记isAlive=false
    // 这样pong帧到达时能覆盖回true，不会出现race condition
    ws.isAlive = false;
  });
}, 30000);

// 防止定时器阻止进程退出
if (heartbeatInterval.unref) {
  heartbeatInterval.unref();
}

async function getLatestNoticeForUser(account) {
  try {
    const collection = dbPool.getCollection('text');
    const twelveHours = 12 * 60 * 60 * 1000;
    const now = Date.now();
    return await collection.findOne({
      type: { $in: ['system', 'department'] },
      createTime: { $gte: new Date(now - twelveHours) }
    }, { sort: { createTime: -1 } });
  } catch (e) {
    Logger.error('WS', '获取最新通知失败', e);
    return null;
  }
}

async function getLatestExamForStudent() {
  try {
    const collection = dbPool.getCollection('exam');
    const twelveHours = 12 * 60 * 60 * 1000;
    const now = Date.now();
    return await collection.findOne({
      createTime: { $gte: new Date(now - twelveHours) }
    }, { sort: { createTime: -1 } });
  } catch (e) {
    Logger.error('WS', '获取最新试卷失败', e);
    return null;
  }
}

async function getLatestFeedbackForAdmin() {
  try {
    const collection = dbPool.getCollection('text');
    return await collection.findOne({
      type: 'feedback',
      status: 'unhandled'
    }, { sort: { createTime: -1 } });
  } catch (e) {
    Logger.error('WS', '获取最新反馈失败', e);
    return null;
  }
}

async function getLatestAppealForAdmin() {
  try {
    const collection = dbPool.getCollection('user');
    return await collection.findOne({
      appealStatus: 'pending'
    }, { sort: { _id: -1 } });
  } catch (e) {
    Logger.error('WS', '获取最新申诉失败', e);
    return null;
  }
}

// ✅ 新增：推送离线消息（从MongoDB record集合读取）
async function pushOfflineMessages(account, type, ws) {
  try {
    Logger.info('OFFLINE', `📤 开始为 ${account} 补推离线消息`);

    // ✅ 从 MongoDB record 集合获取离线消息
    const offlineMsgs = await offlineQueue.getOfflineMessages(account);

    if (offlineMsgs.length === 0) {
      Logger.info('OFFLINE', `✅ ${account} 无离线消息`);
      return;
    }

    // 🔥 批量预检：一次 Redis pipeline 检查所有消息是否已读（替代 N 次单条 SISMEMBER）
    const msgIds = offlineMsgs.map(m => m.msgId);
    const canShowMap = await canShowMessageBatch(account, msgIds);

    let successCount = 0;
    let skipCount = 0;
    let failCount = 0;
    const toSend = [];
    const toSkip = [];

    for (const offlineMsg of offlineMsgs) {
      const msgId = offlineMsg.msgId;
      if (!canShowMap.get(msgId)) {
        toSkip.push(msgId);
        continue;
      }
      toSend.push(offlineMsg);
    }

    // 🔥 分批并发推送（限制并发数10，避免大量离线消息瞬间打爆客户端）
    const OFFLINE_CONCURRENCY = 10;

    for (let i = 0; i < toSend.length; i += OFFLINE_CONCURRENCY) {
      const batch = toSend.slice(i, i + OFFLINE_CONCURRENCY);
      const sendPromises = batch.map(async offlineMsg => {
        if (ws.readyState !== WebSocket.OPEN) {
          Logger.warn('OFFLINE', `⚠️ ${account} 连接已断开，停止推送`);
          return false;
        }
        try {
          await new Promise((resolve, reject) => {
            ws.send(JSON.stringify(offlineMsg.msgData), (err) => {
              if (err) reject(err);
              else resolve();
            });
          });
          wsManager.addPendingACK(account, offlineMsg.msgId);
          wsManager.trackACKTimeout(account, offlineMsg.msgId, ws, offlineMsg.msgData, 0);
          Logger.info('OFFLINE', `📨 推送离线消息(待确认+超时追踪): ${offlineMsg.msgId}`);
          return true;
        } catch (err) {
          Logger.error('OFFLINE', `❌ 推送离线消息失败: ${offlineMsg.msgId}`, err);
          return false;
        }
      });
      const batchResults = await Promise.all(sendPromises);
      successCount += batchResults.filter(r => r).length;
      failCount += batchResults.filter(r => !r).length;
      // 批次间检查连接是否仍然有效
      if (i + OFFLINE_CONCURRENCY < toSend.length && ws.readyState !== WebSocket.OPEN) {
        Logger.warn('OFFLINE', `⚠️ ${account} 连接中断，剩余${toSend.length - i - OFFLINE_CONCURRENCY}条待下次补推`);
        break;
      }
    }

    // 🔥 并行标记已跳过的消息（已读/被删）
    if (toSkip.length > 0) {
      await offlineQueue.markOfflineDeliveredBatch(account, toSkip);
      skipCount = toSkip.length;
    }

    Logger.info('OFFLINE', `✅ ${account} 离线消息补推完成: 成功${successCount}, 跳过${skipCount}, 失败${failCount}`);
  } catch (e) {
    Logger.error('OFFLINE', `❌ 补推离线消息失败：${e.message}`);
  }
}


wss.on('connection', (ws, req) => {
  ws.isAlive = true;
  Logger.info('WS', '新WebSocket连接建立');

  ws.on('message', async (msg) => {
    try {
      const data = JSON.parse(msg.toString());
      
      // 处理客户端心跳 pong
      if (data.type === 'pong') {
        ws.isAlive = true;
        return;
      }
      // 处理客户端心跳 ping：回复 pong，同时标记连接存活
      if (data.type === 'ping') {
        ws.isAlive = true;
        ws.send(JSON.stringify({ type: 'pong' }));
        return;
      }
      
      // 处理ACK确认
      if (data.action === 'ack' && data.msgId) {
        // ✅ 从wsManager获取当前连接的account
        const account = wsManager.getAccountByWs(ws);
        if (account) {
          await markRead(account, data.msgId);
          // 🔥 收到ACK才标记离线消息为已送达，避免误判
          await offlineQueue.markOfflineDelivered(account, data.msgId);
          // 🔥 从待确认列表中移除（ACK成功）
          wsManager.removePendingACK(account, data.msgId);
          // 🔥 同时清除 ACK 超时计时器，防止超时后触发无效重试
          wsManager.removeACKTimeout(account, data.msgId);
          Logger.debug('WS', `✅ 标记消息已读并送达确认: ${account} -> ${data.msgId}`);
        } else {
          Logger.warn('WS', `⚠️ ACK失败: 无法获取当前连接的account`);
        }
        return;
      }

      // 🔥 新增：同步未读通知 — 客户端唤醒时请求补推
      if (data.action === 'sync_notifications') {
        const account = wsManager.getAccountByWs(ws);
        if (!account) {
          Logger.warn('WS', `⚠️ sync_notifications: 无法获取account`);
          return;
        }
        // 🔥 防重：注册后3秒内 pushOfflineMessages 已在执行，跳过避免重复推送
        if (wsManager.isRecentlyRegistered(account, 3000)) {
          Logger.debug('WS', `⏭️ ${account} 刚注册，跳过 sync_notifications（由 pushOfflineMessages 处理）`);
          return;
        }
        try {
          const pendingMsgs = await offlineQueue.getOfflineMessages(account);
          // 🔥 使用客户端发送的 lastCheck 时间戳过滤，避免重复推送已处理的消息
          const lastCheck = data.lastCheck ? parseInt(data.lastCheck) : 0;
          const filteredMsgs = lastCheck > 0
            ? pendingMsgs.filter(m => {
                const ct = m.msgData?.createTime;
                return ct && new Date(ct).getTime() > lastCheck;
              })
            : pendingMsgs;
          if (filteredMsgs.length > 0) {
            // 🔥 批量预检：Redis pipeline 一次检查所有消息是否已读
            const msgIds = filteredMsgs.map(r => r.msgId);
            const canShowMap = await canShowMessageBatch(account, msgIds);

            const toPush = filteredMsgs.filter(r => canShowMap.get(r.msgId));
            if (toPush.length === 0) {
              // 全部已读，批量标记交付
              await offlineQueue.markOfflineDeliveredBatch(account, msgIds);
              Logger.debug('WS', `✅ 客户端 ${account} 无未读通知（已全读）`);
              return;
            }

            Logger.info('WS', `🔄 客户端 ${account} 请求补推，发现 ${toPush.length} 条未读通知（共${filteredMsgs.length}条，已过滤lastCheck）`);

            // 🔥 并行发送 — 不立即标记交付，等待客户端ACK确认后再标记
            const sendResults = await Promise.all(
              toPush.map(record =>
                new Promise((resolve) => {
                  if (ws.readyState === WebSocket.OPEN) {
                    ws.send(JSON.stringify(record.msgData), (err) => {
                      if (err) {
                        Logger.error('WS', `❌ 补推失败: ${record.msgId}`, err);
                        resolve(false);
                      } else {
                        // 🔥 记录待确认状态 + 5秒ACK超时追踪，断线时回滚确保补推
                        wsManager.addPendingACK(account, record.msgId);
                        wsManager.trackACKTimeout(account, record.msgId, ws, record.msgData, 0);
                        Logger.debug('WS', `📤 补推通知(待确认+超时追踪): ${record.msgId}`);
                        resolve(true);
                      }
                    });
                  } else {
                    resolve(false);
                  }
                })
              )
            );

            // 🔥 发送失败的消息保持 pending 状态（不标记为 delivered），让下次 sync 或重连自动重试
            // 只有收到客户端 ACK 后才会标记为 delivered（见 ACK 处理逻辑）
            const failedIds = toPush.filter((_, i) => !sendResults[i]).map(r => r.msgId);
            if (failedIds.length > 0) {
              Logger.warn('WS', `⚠️ 补推发送失败 ${failedIds.length} 条，保持 pending 待下次重试: ${failedIds.join(', ')}`);
            }
            Logger.info('WS', `✅ 补推完成: 成功${sendResults.filter(r=>r).length}条(待ACK), 失败${failedIds.length}条(保持pending)`);
          } else {
            Logger.debug('WS', `✅ 客户端 ${account} 无遗漏通知`);
          }
        } catch (err) {
          Logger.error('WS', `❌ 补推通知失败`, err);
        }
        return;
      }

      // ✅ 处理客户端主动断开通知
      if (data.action === 'disconnect') {
        const account = wsManager.getAccountByWs(ws);
        if (account) {
          wsManager.removeClient(account);
          Logger.info('WS', `📥 收到客户端断开通知: ${account}, 原因: ${data.reason || 'unknown'}`);
        } else {
          Logger.info('WS', `📥 收到客户端断开通知 (未注册), 原因: ${data.reason || 'unknown'}`);
        }
        ws.close();
        return;
      }
      
      if (data.action === 'register' && data.account && data.type) {
        const account = data.account;
        const type = Number(data.type);

        // ✅ 使用wsManager管理连接
        wsManager.addClient(account, type, ws, false);

        ws.send(JSON.stringify({
          type: 'system',
          msg: '连接成功',
          verified: null
        }));

        // 🔥 延迟1秒后推送离线消息，确保客户端完全准备好
        setTimeout(async () => {
          try {
            // 检查连接是否仍然有效
            if (ws.readyState !== WebSocket.OPEN) {
              Logger.warn('WS', `⚠️ ${account} 连接已断开，跳过离线消息推送`);
              return;
            }
            
            await pushOfflineMessages(account, type, ws);
            Logger.info('WS', `✅ ${account} 离线消息补推完成`);
          } catch (err) {
            Logger.error('WS', '❌ 推送离线消息失败', err);
          }
        }, 1000);
      }
    } catch (e) {
      Logger.error('WS', '处理消息失败', e);
    }
  });

  // 原生 pong 帧监听：客户端自动回复的 pong 标记连接存活
  ws.on('pong', () => {
    ws.isAlive = true;
  });

  ws.on('close', (code, reason) => {
    const account = wsManager.getAccountByWs(ws);
    if (account) {
      wsManager.removeClient(account);
    } else {
      // 🔥 code=1006 表示异常断开（网络中断/进程被杀），此时ws可能尚未注册或被主动断开已清理
      // 这是正常现象，降级为DEBUG日志，避免误报
      if (code === 1006) {
        Logger.debug('WS', `📴 连接异常断开(code=1006)，未找到account，可能是网络中断或主动断开`);
      } else {
        Logger.warn('WS', `⚠️ close事件中未找到对应的account (code=${code}, reason=${reason.toString()})`);
      }
    }
  });

  ws.on('error', (err) => {
    Logger.error('WS', '❌ WebSocket错误', err);
    
    // 🔥 Bug修复：使用优化后的方法获取账号（O(1)复杂度）
    const account = wsManager.getAccountByWs(ws);
    if (account) {
      wsManager.removeClient(account);
    } else {
      Logger.warn('WS', '⚠️ error事件中未找到对应的account');
    }
  });
});

global.pushMsg = async function (targetRole, msgData, isAppeal = false) {
  const realMsgId = msgData.id || msgData._id;
  const createTime = msgData.createTime;
  const msgType = msgData.type;

  if (!realMsgId || !createTime) {
    Logger.warn('PUSH', '⚠️ 消息缺少ID或时间，跳过');
    return;
  }

  // 检查消息是否过期（24小时或7天）
  const msgTime = new Date(createTime).getTime();
  const now = Date.now();

  // 系统/部门/试卷通知：24小时过期
  const needTimeLimit = ['system', 'department', 'exam'].includes(msgType);
  if (needTimeLimit) {
    const twentyFourHours = 24 * 60 * 60 * 1000;
    if (now - msgTime > twentyFourHours) {
      Logger.debug('PUSH', `⏭️ 消息${realMsgId}超过24小时，跳过`);
      return;
    }
  }

  // 申诉/反馈消息：7天过期
  const needSevenDayLimit = ['appeal', 'feedback'].includes(msgType);
  if (needSevenDayLimit) {
    const sevenDays = 7 * 24 * 60 * 60 * 1000;
    if (now - msgTime > sevenDays) {
      Logger.debug('PUSH', `⏭️ 申诉/反馈消息${realMsgId}超过7天，跳过`);
      return;
    }
  }

  Logger.info('PUSH', `📤 开始推送消息 ${realMsgId} 到角色 ${JSON.stringify(targetRole)}`);

  // 🔥 全量优化：批量查询 + 批量已读判断 + 分批并发推送
  // 旧实现：N个用户串行，N次Redis + N次MongoDB + N次WS发送
  // 新实现：1次用户查询 + 1次Redis管道 + 批量离线入库 + 并发WS发送
  try {
    const roles = Array.isArray(targetRole) ? targetRole : [targetRole];
    const userCollection = dbPool.getCollection('user');

    // 1️⃣ 并行查询各角色用户列表
    const roleUserResults = await Promise.all(
      roles.map(role => userCollection.find({ type: role }, { projection: { account: 1 } }).toArray())
    );

    let totalOnline = 0;
    let totalOffline = 0;
    let totalSkipped = 0;

    for (let ri = 0; ri < roles.length; ri++) {
      const role = roles[ri];
      const allUsers = roleUserResults[ri];
      const accounts = allUsers.map(u => u.account).filter(Boolean);

      if (accounts.length === 0) {
        Logger.info('PUSH', `🔍 角色 ${role} 无用户，跳过`);
        continue;
      }

      Logger.info('PUSH', `🔍 角色 ${role} 共有 ${accounts.length} 个用户`);

      // 2️⃣ 批量判断已读（Redis pipeline 一次往返，O(1) 网络开销）
      const redis = getRedis();
      const pipeline = redis.pipeline();
      for (const account of accounts) {
        pipeline.sismember(`read_log:${account}`, String(realMsgId));
      }
      const results = await pipeline.exec();

      const unreadAccounts = [];
      for (let i = 0; i < accounts.length; i++) {
        const isRead = results[i] && results[i][1] === 1;
        if (!isRead) {
          unreadAccounts.push(accounts[i]);
        }
      }
      totalSkipped += accounts.length - unreadAccounts.length;
      Logger.debug('PUSH', `📊 角色 ${role}: 已读跳过 ${accounts.length - unreadAccounts.length}人, 待推送 ${unreadAccounts.length}人`);

      if (unreadAccounts.length === 0) continue;

      // 3️⃣ 批量写入离线队列（所有未读用户都入队，作为兜底）
      // 先构造批量文档，一次性 insertMany
      const offlineDocs = unreadAccounts.map(account => ({
        account,
        msgId: String(realMsgId),
        msgData,
        role,
        status: 'pending',
        createdAt: new Date(),
        expireAt: new Date(Date.now() + 7 * 24 * 3600 * 1000)
      }));

      const recordCollection = dbPool.getCollection('record');
      // 🔥 使用 bulkWrite + upsert 模式避免重复（替代逐条 findOne + insertOne）
      const bulkOps = offlineDocs.map(doc => ({
        updateOne: {
          filter: { account: doc.account, msgId: doc.msgId },
          update: { $setOnInsert: doc },
          upsert: true
        }
      }));
      await recordCollection.bulkWrite(bulkOps, { ordered: false });
      Logger.debug('PUSH', `💾 批量写入离线队列: ${unreadAccounts.length}条`);

      // 4️⃣ 区分在线/离线用户，在线用户并发实时推送
      // 🔥 修复：强制退出的 App，WS readyState 仍为 OPEN 但底层 socket 已死（半开连接）
      // 增加 socket.writable 检查，避免向已退出进程推送并误标记为已送达
      const onlineAccounts = [];
      const offlineAccounts = [];
      for (const account of unreadAccounts) {
        const client = wsManager.getClient(account);
        if (client && client.ws.readyState === WebSocket.OPEN && client.ws._socket?.writable !== false) {
          onlineAccounts.push(account);
        } else {
          offlineAccounts.push(account);
        }
      }
      totalOffline += offlineAccounts.length;

      // 🔥 并发推送（限制并发数为20，避免瞬间打爆连接）
      const CONCURRENCY = 20;
      let sentCount = 0;
      let failCount = 0;

      for (let i = 0; i < onlineAccounts.length; i += CONCURRENCY) {
        const batch = onlineAccounts.slice(i, i + CONCURRENCY);
        const sendPromises = batch.map(async account => {
          try {
            const sent = await wsManager.sendToUser(account, msgData);
            if (sent === 'pending') {
              // 🔥 已发送但待确认，启动5秒ACK超时追踪（超时自动重试1次）
              wsManager.addPendingACK(account, realMsgId);
              // 🔥 修复：client 不能从外层闭包获取（已被覆盖），在回调内重新查询
              const pushClient = wsManager.getClient(account);
              wsManager.trackACKTimeout(account, realMsgId, pushClient?.ws, msgData, 0);
              Logger.debug('PUSH', `📨 ${account} 已发送(待确认+超时追踪), 保留在离线队列`);
              return true; // 不标记为已送达，等待ACK
            }
            if (sent) {
              await offlineQueue.markOfflineDelivered(account, realMsgId);
              return true;
            }
            return false;
          } catch (err) {
            Logger.error('PUSH', `❌ 推送到 ${account} 异常`, err);
            return false;
          }
        });
        const results = await Promise.all(sendPromises);
        sentCount += results.filter(r => r).length;
        failCount += results.filter(r => !r).length;
      }

      totalOnline += sentCount;
      totalOffline += failCount; // 失败的保留在离线队列

      Logger.info('PUSH', `📊 角色 ${role}: 在线推送成功 ${sentCount}, 失败 ${failCount}, 纯离线 ${offlineAccounts.length}, 已读跳过 ${accounts.length - unreadAccounts.length}`);
    }

    Logger.info('PUSH', `✅ 消息推送完成: 在线${totalOnline}, 离线${totalOffline}, 已读跳过${totalSkipped}`);
  } catch (err) {
    Logger.error('PUSH', '❌ 消息推送失败', err);
  }
};

// 启动服务
server.listen(PORT, () => {
  console.log(`✅ 服务已启动：http://localhost:${PORT}`);
});

process.on('uncaughtException', (err) => {
  console.error('🚨 服务异常：', err);
});
process.on('unhandledRejection', (reason, promise) => {
  console.error('🚨 异步异常：', reason);
});