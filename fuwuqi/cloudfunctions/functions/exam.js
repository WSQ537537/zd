const { ObjectId } = require('mongodb');
const { dbPool, cachedQuery, invalidateCache } = require('../utils');
const fs = require('fs');
const fsPromises = require('fs').promises;
const path = require('path');
const { v4: uuidv4 } = require('uuid'); // 新增：UUID生成
const { SERVER_HOST } = require('../config'); // ✅ 公网地址统一配置
const colName = 'exam';
// 新增：答题记录集合（全小写 examrecord）
const recordColName = 'examrecord';

// ========== 日志辅助：过滤请求参数中的大字段（如图片 Base64），避免控制台刷出海量乱码 ==========
function summarizeParams(params) {
  if (!params) return {};
  const summary = {};
  for (const [k, v] of Object.entries(params)) {
    if (typeof v === 'string' && v.length > 200) {
      summary[k] = `[长字符串 ${v.length} 字符，已省略]`;
    } else if (Array.isArray(v) && v.length > 0) {
      summary[k] = `[数组 长度${v.length}]`;
    } else {
      summary[k] = v;
    }
  }
  return summary;
}

// ========== 核心修改：图片存储路径（适配 Cloud Functions/Functions 目录） ==========
// 图片文件夹路径：和当前 exam.js 同级的 Pictures 文件夹
const imgSaveDir = path.join(__dirname, 'Pictures');
// 确保Pictures文件夹存在（异步）
fsPromises.access(imgSaveDir).catch(() => fsPromises.mkdir(imgSaveDir, { recursive: true }));

/**
 * 辅助函数：提取字符串中的纯大写字母（忽略所有空格、符号、顿号、小写字母等）
 * @param {string} str - 待处理字符串
 * @returns {string} 仅保留大写字母的结果
 */
function extractPureLetters(str) {
  if (!str) return '';
  // 先转大写，再只保留A-Z字母，忽略所有其他字符
  return str.toString().toUpperCase().replace(/[^A-Z]/g, '');
}

/**
 * 辅助函数：计算字符串相似度（余弦相似度，用于文字类题目判分）
 * @param {string} str1 - 用户答案
 * @param {string} str2 - 标准答案
 * @returns {number} 相似度（0-1）
 */
function calculateSimilarity(str1, str2) {
  if (!str1 || !str2) return 0;
  if (str1 === str2) return 1;

  // 构建字符频率映射
  const getCharFreq = (str) => {
    const freq = {};
    for (const char of str) {
      freq[char] = (freq[char] || 0) + 1;
    }
    return freq;
  };

  const freq1 = getCharFreq(str1);
  const freq2 = getCharFreq(str2);

  // 计算余弦相似度
  let dotProduct = 0;
  let norm1 = 0;
  let norm2 = 0;

  // 计算点积和向量1的模
  for (const char in freq1) {
    norm1 += freq1[char] * freq1[char];
    if (freq2[char]) {
      dotProduct += freq1[char] * freq2[char];
    }
  }

  // 计算向量2的模
  for (const char in freq2) {
    norm2 += freq2[char] * freq2[char];
  }

  if (norm1 === 0 || norm2 === 0) return 0;
  return dotProduct / (Math.sqrt(norm1) * Math.sqrt(norm2));
}

/**
 * 辅助函数：判断是否为纯数字（包括整数/小数）
 * @param {string} str - 待判断字符串
 * @returns {boolean}
 */
function isPureNumber(str) {
  if (typeof str !== 'string') str = String(str);
  return /^-?\d+(\.\d+)?$/.test(str.trim());
}

/**
 * 辅助函数：判断是否为数字/公式类型（包含数字、运算符、括号等）
 * @param {string} str - 待判断字符串
 * @returns {boolean}
 */
function isNumberOrFormula(str) {
  if (!str) return false;
  // 包含数字、+、-、*、/、=、()、. 等符号，且非纯文字
  return /^[\d\+\-\*\/=\(\)\. ]+$/.test(str.trim());
}

/**
 * 核心修复：给题目绑定真实分值（解决创建/编辑时分值未写入的问题）
 * @param {Array} questions - 原始题目列表
 * @param {Array} perTypeTime - 题型分数配置（[{type: 'single', score: 5}, ...]）
 * @returns {Array} 绑定好分值的题目列表
 */
function bindQuestionRealScore(questions, perTypeTime) {
  if (!Array.isArray(questions)) return questions;
  
  // 🔥 修复：如果 perTypeTime 为空，直接返回原始题目（保留所有字段）
  if (!Array.isArray(perTypeTime) || perTypeTime.length === 0) {
    return questions;
  }
  
  // 构建题型-分数映射
  const typeScoreMap = {};
  perTypeTime.forEach(item => {
    if (item && item.type != null) {
      typeScoreMap[item.type] = Number(item.score) || 0;
    }
  });

  // 给每道题绑定真实分值
  return questions.map(question => {
    const originalScore = question.score || 0;
    const newScore = typeScoreMap[question.type] || originalScore;
    
    return {
      ...question,
      score: newScore // 优先取题型配置分，兜底取题目自身分
    };
  });
}

/**
 * 试卷处理器：创建 / 编辑 / 按ID查询 / 列表查询 / 提交试卷 / 判断是否已答 / 获取详情 / 删除试卷 / 试卷统计 / 重判题目
 * 新增：uploadQuestionImage（上传题目图片）、bindImageToQuestion（绑定图片到题目）、rejudgeQuestion（重判题目）、getParentExamStatistics（家长端统计）
 * @param {Object} params - 前端传参
 * @returns {Promise<Object>} 统一格式结果
 */
async function examHandler(params) {
  // 每次请求仅记录一行：action + 关键 ID，不再打印完整参数（避免图片 Base64 等大字段刷屏）
  console.log(`[试卷处理][${new Date().toLocaleString()}] 请求：${params.action}`, summarizeParams(params));

  if (!params.action) {
    console.error(`[试卷处理][${new Date().toLocaleString()}] 错误：缺少 action 参数`);
    return { success: false, msg: "缺少 action 参数（createExam/updateExam/getExamById/getExamList/submitExam/isAnswered/getUserExamDetail/deleteExam/getExamStatistics/getParentExamStatistics/uploadQuestionImage/bindImageToQuestion/deleteQuestionImage/rejudgeQuestion）" };
  }

  const examCollection = dbPool.getCollection(colName);
  // 初始化答题记录集合
  const recordCollection = dbPool.getCollection(recordColName);

  try {

    // ========== 新增：家长端统计接口（仅返回绑定学生数据） ==========
    if (params.action === 'getParentExamStatistics') {
      try {
        const parentAccount = params.parentAccount?.toString().trim() || '';
        // 🚀 性能优化：支持按单个学生分页查询（与学员端 getUserExamList 分页一致）
        const reqStudentAccount = params.studentAccount?.toString().trim() || '';
        const pageNum = parseInt(params.page) || 1;
        const limitNum = Math.min(parseInt(params.limit) || 10, 100);
        const skip = (pageNum - 1) * limitNum;
        let boundStudents = [];

        // 1. 初始化用户集合（提前声明，供后续备注查询复用）
        const userCollection = dbPool.getCollection('user');

        // 如果是家长，先获取绑定学生列表
        if (parentAccount) {
          const parent = await userCollection.findOne(
            { account: parentAccount, type: 3 },
            { projection: { boundStudents: 1 } }
          );
          boundStudents = parent?.boundStudents || [];
        }

        // 2. 构建查询条件：仅查询当前选中学生（家长端学习/考试界面默认只加载一位学生）
        let query;
        if (reqStudentAccount && boundStudents.includes(reqStudentAccount)) {
          query = { account: reqStudentAccount };
        } else if (boundStudents.length > 0) {
          query = { account: { $in: boundStudents } };
        } else {
          query = { account: { $exists: false } };
        }

        // 3. 先查询绑定学生的备注信息
        const studentRemarkMap = {};
        const remarkAccounts = boundStudents.length > 0 ? boundStudents : (reqStudentAccount ? [reqStudentAccount] : []);
        if (remarkAccounts.length > 0) {
          const studentsInfo = await userCollection.find(
            { account: { $in: remarkAccounts }, type: 2 }
          ).toArray();
          studentsInfo.forEach(s => { studentRemarkMap[s.account] = s.remark || ''; });
        }

        // 4. 分页查询答题记录（首次加载最近10条，滚动到底部加载更多）
        const [pagedRecords, total] = await Promise.all([
          recordCollection
            .find(query, { projection: { questions: 0 } })
            .sort({ submitTime: -1 })
            .skip(skip)
            .limit(limitNum)
            .toArray(),
          recordCollection.countDocuments(query)
        ]);

        const totalPages = Math.ceil(total / limitNum);

        if (!pagedRecords || pagedRecords.length === 0) {
          // 这里保留return，直接返回结果，终止函数执行
          return {
            success: true,
            data: {
              userList: [],
              pagination: { page: pageNum, limit: limitNum, total: 0, totalPages: 0 }
            }
          };
        }

        // 5. 按用户分组（复用管理员端的分组逻辑）
        const userMap = {};
        for (const record of pagedRecords) {
          const account = record.account;
          const examId = record.examId;

          if (!userMap[account]) {
            userMap[account] = {
              account: account,
              remark: studentRemarkMap[account] || '', // 使用学生真实备注
              examList: []
            };
          }

          const existExam = userMap[account].examList.find(
            item => item.examId === examId
          );

          if (!existExam) {
            // 🚀 性能优化：列表仅返回摘要字段，题目详情改为点击时通过
            // getUserExamDetail 按需拉取
            const examData = {
              examId: examId || '',
              examName: record.examName || `试卷${examId}`,
              submitTime: record.submitTime || new Date(),
              totalScore: record.totalScore || 0,
              remark: record.remark || ''
            };

            userMap[account].examList.push(examData);
          }
        }

        const userList = Object.values(userMap);

        // 核心：这里return后，函数直接终止，不会走到下面的switch分支
        return {
          success: true,
          data: {
            userList: userList,
            pagination: { page: pageNum, limit: limitNum, total, totalPages }
          }
        };

      } catch (err) {
        console.error('getParentExamStatistics error：', err);
        return {
          success: false,
          msg: '家长端统计失败：' + err.message
        };
      }
    }
    

    // ========== 新增：上传题目图片（完整修复版） ==========
    if (params.action === 'uploadQuestionImage') {
      if (!params.base64Data) {
        return { success: false, msg: "缺少图片Base64数据" };
      }

      try {
        // 1. 严格清洗Base64数据（核心修复：去掉前缀+换行+空格）
        const base64Str = params.base64Data;
        const pureBase64 = base64Str.replace(/^data:image\/\w+;base64,/, ''); // 去掉前缀
        const cleanBase64 = pureBase64.replace(/\s+/g, ''); // 去掉所有换行/空格
        
        // 2. 转换为Buffer并校验有效性
        const buffer = Buffer.from(cleanBase64, 'base64');
        if (buffer.length < 100) { // 过滤空/无效数据
          return { success: false, msg: "图片数据无效（长度过小）" };
        }
        
        // 3. 强制统一为jpg格式（最兼容，避免格式混乱）
        const fileName = `${uuidv4()}.jpg`;
        const savePath = path.join(imgSaveDir, fileName);
        
        // 4. 异步写入文件
        await fsPromises.writeFile(savePath, buffer, { flag: 'w' });
        
        // 5. 生成可访问的图片链接（适配启动文件的静态服务路径）
        const imgUrl = `${SERVER_HOST}/Pictures/${fileName}`;
        
        console.log(`[图片上传][${new Date().toLocaleString()}] 成功：${fileName}（${buffer.length}字节）`);
        
        return {
          success: true,
          msg: "图片上传成功",
          imgUrl: imgUrl,
          fileName: fileName
        };
      } catch (err) {
        console.error(`[图片上传失败][${new Date().toLocaleString()}]：${err.message}`);
        return { success: false, msg: `图片上传失败：${err.message}` };
      }
    }

    // ========== 新增：绑定图片到题目 ==========
    if (params.action === 'bindImageToQuestion') {
      const { examId, questionIndex, imgUrl } = params;
      if (!examId || questionIndex === undefined || !imgUrl) {
        return { success: false, msg: "缺少试卷ID/题目索引/图片链接参数" };
      }

      // 使用点表示法直接更新嵌套字段，无需先查询整个文档
      await examCollection.updateOne(
        { _id: new ObjectId(examId) },
        { $set: { [`questions.${questionIndex}.imgUrl`]: imgUrl, updateTime: new Date() } }
      );
      invalidateCache(`exam_byId_${examId}`); // 优化：写操作后主动失效缓存

      console.log(`[图片绑定][${new Date().toLocaleString()}] 试卷${examId}第${questionIndex+1}题绑定图片：${imgUrl}`);
      
      return {
        success: true,
        msg: "图片绑定到题目成功",
        data: { examId, questionIndex, imgUrl }
      };
    }

    // ========== 新增：删除题目图片 ==========
    if (params.action === 'deleteQuestionImage') {
      const { examId, questionIndex, imgUrl } = params;
      if (!examId || questionIndex === undefined || !imgUrl) {
        return { success: false, msg: "缺少试卷ID/题目索引/图片链接参数" };
      }

      try {
        // 1. 从文件系统删除图片文件
        let fileName = '';
        try {
          // 从URL中提取文件名（兼容带参数和不带参数的URL）
          const match = imgUrl.match(/\/Pictures\/([^?]+)/);
          if (match && match[1]) {
            fileName = match[1];
            const filePath = path.join(imgSaveDir, fileName);
            
            // 检查文件是否存在并删除
            try {
              await fsPromises.unlink(filePath);
              console.log(`[图片删除][${new Date().toLocaleString()}] 已删除文件：${fileName}`);
            } catch (unlinkErr) {
              if (unlinkErr.code === 'ENOENT') {
                console.warn(`[图片删除][${new Date().toLocaleString()}] 文件不存在：${fileName}`);
              } else {
                console.error(`[图片删除][${new Date().toLocaleString()}] 文件删除失败：`, unlinkErr);
              }
            }
          }
        } catch (fileErr) {
          console.error(`[图片删除][${new Date().toLocaleString()}] 文件删除失败：`, fileErr);
          // 文件删除失败不阻断数据库更新
        }

        // 2. 使用点表示法直接清除题目中的图片链接，无需先查询整个文档
        await examCollection.updateOne(
          { _id: new ObjectId(examId) },
          { $set: { [`questions.${questionIndex}.imgUrl`]: null, updateTime: new Date() } }
        );
        invalidateCache(`exam_byId_${examId}`); // 优化：写操作后主动失效缓存

        console.log(`[图片删除][${new Date().toLocaleString()}] 试卷${examId}第${questionIndex+1}题图片已删除`);
        
        return {
          success: true,
          msg: "图片删除成功",
          data: { examId, questionIndex, deletedFile: fileName }
        };
      } catch (err) {
        console.error(`[图片删除失败][${new Date().toLocaleString()}]：`, err);
        return { success: false, msg: `图片删除失败：${err.message}` };
      }
    }

    // ========== 新增：重判题目（修改题目得分） ==========
    if (params.action === 'rejudgeQuestion') {
      // 参数校验
      if (!params.account || !params.examId || !params.qType || params.qIndex === undefined || params.newScore === undefined) {
        return { success: false, msg: "缺少参数：account/examId/qType/qIndex/newScore" };
      }

      // 转换参数类型
      const account = params.account.toString().trim();
      const examId = params.examId;
      const qType = params.qType; // single/multi/fill/short
      const qIndex = Number(params.qIndex); // 全局题号索引
      const newScore = Number(params.newScore);

      // 校验分数合法性
      if (newScore < 0) {
        return { success: false, msg: "分数不能为负数" };
      }

      // 1. 查询答题记录
      const record = await recordCollection.findOne({
        account: account,
        examId: examId
      });

      if (!record) {
        return { success: false, msg: "未找到该用户的答题记录" };
      }

      // 2. 根据全局索引直接定位题目
      if (!Array.isArray(record.questions)) {
        return { success: false, msg: "答题记录中无题目数据" };
      }

      if (qIndex < 0 || qIndex >= record.questions.length) {
        return { success: false, msg: `题号 ${qIndex} 超出范围` };
      }

      // 校验题型是否匹配
      const targetQuestion = record.questions[qIndex];
      if (targetQuestion.type !== qType) {
        return { success: false, msg: `题号 ${qIndex} 的题型为"${targetQuestion.type}"，与请求的"${qType}"不匹配` };
      }

      // 3. 校验分数不超过题目满分
      const maxScore = Number(targetQuestion.score || 0);
      if (newScore > maxScore) {
        return { success: false, msg: `分数不能超过题目满分（${maxScore}分）` };
      }

      // 4. 保存旧分数，计算差值
      const oldScore = Number(targetQuestion.userScore || 0);
      const scoreDiff = newScore - oldScore;

      // 5. 更新题目得分（直接用全局索引 qIndex）
      record.questions[qIndex].userScore = newScore;

      // 6. 重新计算各题型总分和试卷总分
      // 按题型过滤题目
      const singleList = record.questions.filter(q => q.type === 'single');
      const multiList = record.questions.filter(q => q.type === 'multi');
      const fillList = record.questions.filter(q => q.type === 'fill');
      const shortList = record.questions.filter(q => q.type === 'short');

      // 计算各题型总分
      const calTypeScore = (list) => list.reduce((sum, q) => sum + Number(q.userScore || 0), 0);
      const singleScore = calTypeScore(singleList);
      const multiScore = calTypeScore(multiList);
      const fillScore = calTypeScore(fillList);
      const shortScore = calTypeScore(shortList);

      // 计算试卷总分
      const totalScore = singleScore + multiScore + fillScore + shortScore;

      // 7. 更新答题记录
      await recordCollection.updateOne(
        { _id: record._id },
        { 
          $set: { 
            questions: record.questions,
            totalScore: totalScore,
            // 存储各题型总分（方便前端展示）
            singleScore: singleScore,
            multiScore: multiScore,
            fillScore: fillScore,
            shortScore: shortScore,
            updateTime: new Date()
          } 
        }
      );

      console.log(`[重判题目][${new Date().toLocaleString()}] 用户${account} 试卷${examId} ${qType}题型第${qIndex+1}题：${oldScore}分 → ${newScore}分，总分变化：${scoreDiff}分`);
      invalidateCache('exam_statistics_all'); // 优化：答题分数变更，主动失效统计缓存

      return {
        success: true,
        msg: "重判成功",
        data: {
          oldScore: oldScore,
          newScore: newScore,
          totalScore: totalScore,
          scoreDiff: scoreDiff
        }
      };
    }
    // ========== 新增：删除用户单条试卷答题记录 ==========
    if (params.action === 'deleteExamRecord') {
      // 参数校验
      if (!params.account || !params.examId) {
        return { success: false, msg: "缺少参数：account/examId" };
      }

      // 1. 查询答题记录
      const record = await recordCollection.findOne({
        account: params.account.toString().trim(),
        examId: params.examId
      });

      if (!record) {
        return { success: false, msg: "未找到该答题记录" };
      }

      // 2. 删除答题记录
      await recordCollection.deleteOne({
        _id: record._id
      });

      console.log(`[删除答题记录][${new Date().toLocaleString()}] 用户${params.account} 试卷${params.examId} 答题记录已删除`);
      invalidateCache('exam_statistics_all'); // 优化：答题记录删除，主动失效统计缓存

      return {
        success: true,
        msg: "答题记录删除成功"
      };
    }

    switch (params.action) {
      // 1. 创建/发布试卷（核心修复：给题目绑定真实分值后再入库）
      case 'createExam':
        if (!params.examName) return { success: false, msg: "请填写试卷名称" };
        if (!params.subject) return { success: false, msg: "请选择科目" };
        if (!params.examTime) return { success: false, msg: "请选择考试时间" };
        if (!params.questions || params.questions.length === 0) return { success: false, msg: "请生成题目后再发布" };

        // 处理每题计时数据（确保格式正确）
        let perTypeTimeData = null;
        if (params.timingType === 'perQuestionTime' && Array.isArray(params.perTypeTime)) {
          perTypeTimeData = params.perTypeTime.map(item => ({
            type: item.type || '',
            score: Number(item.score) || 0,
            time: Number(item.time) || 0
          }));
        }

        // 核心修复：给题目绑定真实分值
        const questionsWithRealScore = bindQuestionRealScore(params.questions, perTypeTimeData);

        const examData = {
          examName: params.examName,
          subject: params.subject,
          examTime: params.examTime,
          status: params.status || '自由',
          timingType: params.timingType || 'totalTime',
          totalTime: params.timingType === 'totalTime' ? (params.totalTime ? Number(params.totalTime) : null) : null,
          perTypeTime: perTypeTimeData,
          questions: questionsWithRealScore, // 存入绑定好分值的题目
          createTime: new Date(),
          updateTime: new Date()
        };

        const result = await examCollection.insertOne(examData);
        invalidateCache(`exam_byId_${result.insertedId}`); // 优化：写操作后主动失效缓存
        console.log(`[试卷创建][${new Date().toLocaleString()}] 成功，ID：${result.insertedId}`);
        
       // 发推送：给所有学生（type=2），带上type字段
        if (global.pushMsg) {
          await global.pushMsg(2, {
            id: result.insertedId.toString(),
            title: '新试卷发布',
            content: `【${examData.subject}】${examData.examName} 已发布，请及时完成！`,
            createTime: new Date(),
            type: 'exam' // 【关键！必须加，用于区分消息类型】
          });
        }
        return {
          success: true,
          msg: "试卷发布成功",
          examId: result.insertedId.toString()
        };

      // ========== 核心修复：编辑/更新试卷（绑定真实分值后入库） ==========
      case 'updateExam':
        if (!params.examId) return { success: false, msg: "请提供要修改的试卷ID" };
        if (!params.examName) return { success: false, msg: "请填写试卷名称" };
        if (!params.subject) return { success: false, msg: "请选择科目" };
        if (!params.examTime) return { success: false, msg: "请选择考试时间" };
        if (!params.questions || params.questions.length === 0) return { success: false, msg: "试卷题目不能为空" };

        // 处理每题计时数据（确保格式正确）
        let updatePerTypeTime = null;
        if (params.timingType === 'perQuestionTime' && Array.isArray(params.perTypeTime)) {
          updatePerTypeTime = params.perTypeTime.map(item => ({
            type: item.type || '',
            score: Number(item.score) || 0,
            time: Number(item.time) || 0
          }));
        }

        // 核心修复：给题目绑定真实分值
        const updatedQuestionsWithRealScore = bindQuestionRealScore(params.questions, updatePerTypeTime);

        // 构造更新数据（只更新需要修改的字段，保留createTime）
        const updateData = {
          $set: {
            examName: params.examName,
            subject: params.subject,
            examTime: params.examTime,
            status: params.status || '自由',
            timingType: params.timingType || 'totalTime',
            totalTime: params.timingType === 'totalTime' ? (params.totalTime ? Number(params.totalTime) : null) : null,
            perTypeTime: updatePerTypeTime, // 修复：存储格式化后的每题计时数据
            questions: updatedQuestionsWithRealScore, // 存入绑定好分值的题目
            updateTime: new Date() // 更新时间戳
          }
        };

        // 执行更新（根据examId匹配原数据）
        const updateResult = await examCollection.updateOne(
          { _id: new ObjectId(params.examId) }, // 条件：匹配原试卷ID
          updateData // 更新内容
        );

        if (updateResult.matchedCount === 0) {
          return { success: false, msg: "试卷不存在，无法修改" };
        }

        invalidateCache(`exam_byId_${params.examId}`); // 优化：写操作后主动失效缓存
        console.log(`[试卷更新][${new Date().toLocaleString()}] 成功，ID：${params.examId}`);
        return {
          success: true,
          msg: "试卷修改成功",
          examId: params.examId
        };

      // 2. 按ID查询试卷（优化：保留imgUrl字段 + 确保分值正确返回）
      case 'getExamById':
        if (!params.examId) return { success: false, msg: "请提供 examId" };

        // 优化：高频读取接口加缓存（TTL 30 秒），写操作后通过 invalidateCache 主动失效
        const exam = await cachedQuery(
          `exam_byId_${params.examId}`,
          async () => examCollection.findOne({ _id: new ObjectId(params.examId) }),
          30000
        );

        if (!exam) return { success: false, msg: "试卷不存在" };

        // ========== 优化：解析perTypeTime为分数/时间映射 ==========
        // 🔥 核心修复：使用 != null 检查而不是 truthy 检查，因为 0 是有效值
        const scoreMap = {};
        const timeMap = {};
        if (Array.isArray(exam.perTypeTime)) {
          exam.perTypeTime.forEach(item => {
            if (item.type && item.score != null) scoreMap[item.type] = item.score;
            if (item.type && item.time != null) timeMap[item.type] = item.time;
          });
        }

        // 如果是每题计时模式，解析perTypeTime（数组格式：[{type: 'single', time: 30}, ...]）
        const timeMapForQuestion = {};
        if (exam.timingType === 'perQuestionTime' && Array.isArray(exam.perTypeTime)) {
          exam.perTypeTime.forEach(item => {
            if (item.type && item.time) {
              timeMapForQuestion[item.type] = Number(item.time); // 确保时间是数字类型
            }
          });
        }

     
        // 给每道题绑定对应题型的时间 + 保留imgUrl字段 + 确保分值优先取题目自身（已绑定）
        const questionsWithTime = exam.questions.map(q => {
          const resolvedScore = q.type && scoreMap[q.type] != null
            ? Number(scoreMap[q.type])
            : q.score != null
              ? Number(q.score)
              : 0;
          const resolvedTime = q.type && timeMapForQuestion[q.type] != null
            ? Number(timeMapForQuestion[q.type])
            : q.questionTime != null
              ? Number(q.questionTime)
              : 30;

          return {
            ...q,
            score: resolvedScore,
            questionTime: resolvedTime,
            imgUrl: q.imgUrl || ''
          };
        });
        // ========== 映射结束 ==========

        const formattedExam = {
          examId: exam._id.toString(),
          examName: exam.examName,
          subject: exam.subject,
          examTime: exam.examTime,
          status: exam.status,
          timingType: exam.timingType,
          totalTime: exam.totalTime,
          perTypeTime: exam.perTypeTime,
          questionTypeScores: scoreMap, // 新增：返回分数映射
          questionTypeTimes: timeMap,   // 新增：返回时间映射
          questions: questionsWithTime // 返回带时间、分数和图片链接的题目列表
        };

        return {
          success: true,
          msg: "查询成功",
          data: formattedExam
        };

      // 3. 查询试卷列表（核心修复：返回perTypeTime和分数/时间映射）
      case 'getExamList':
        const { page = 1, limit = 10 } = params;
        // 确保参数为整数类型，避免 MongoDB 报错
        const pageNum = parseInt(page) || 1;
        const limitNum = Math.min(parseInt(limit) || 10, 100);
        const skip = (pageNum - 1) * limitNum;

        const [exams, total] = await Promise.all([
          examCollection
            .find({}, {
              projection: {
                examName: 1,
                subject: 1,
                examTime: 1,
                status: 1,
                timingType: 1,
                totalTime: 1,
                perTypeTime: 1, // 新增：返回每题计时数据
                createTime: 1
              }
            })
            .sort({ createTime: -1 })
            .skip(skip)
            .limit(limitNum)
            .toArray(),
          examCollection.countDocuments()
        ]);

        const formattedExams = exams.map(item => {
          // 解析perTypeTime为前端需要的questionTypeScores/questionTypeTimes
          const scoreMap = {};
          const timeMap = {};
          if (Array.isArray(item.perTypeTime)) {
            item.perTypeTime.forEach(pt => {
              if (pt.type && pt.score) scoreMap[pt.type] = pt.score;
              if (pt.type && pt.time) timeMap[pt.type] = pt.time;
            });
          }
          return {
            examId: item._id.toString(),
            examName: item.examName,
            subject: item.subject,
            examTime: item.examTime,
            status: item.status,
            timingType: item.timingType,
            totalTime: item.totalTime,
            createTime: item.createTime,
            questionTypeScores: scoreMap, // 前端需要的分数映射
            questionTypeTimes: timeMap,   // 前端需要的时间映射
            perTypeTime: item.perTypeTime
          };
        });

        return {
          success: true,
          msg: "查询成功",
          list: formattedExams,
          pagination: {
            page: Number(page),
            limit: Number(limit),
            total,
            totalPages: Math.ceil(total / limitNum)
          }
        };

      // ========== 新增：获取当前用户的试卷列表（带作答状态） ==========
      case 'getUserExamList':
        if (!params.account) {
          return { success: false, msg: "缺少用户账号参数" };
        }
        
        const userAccount = params.account.toString().trim();
        // 🔥 修复：使用不同的变量名避免与getExamList中的变量重复声明
        const { page: userPage = 1, limit: userLimit = 20 } = params;
        const userPageNum = parseInt(userPage) || 1;
        const userLimitNum = Math.min(parseInt(userLimit) || 20, 100);
        const userSkip = (userPageNum - 1) * userLimitNum;

        try {
          // 1. 并行查询所有试卷和总数
          const [exams, total] = await Promise.all([
            examCollection
              .find({}, {
                projection: {
                  examName: 1,
                  subject: 1,
                  examTime: 1,
                  status: 1,
                  timingType: 1,
                  totalTime: 1,
                  perTypeTime: 1,
                  createTime: 1
                }
              })
              .sort({ createTime: -1 })
              .skip(userSkip)
              .limit(userLimitNum)
              .toArray(),
            examCollection.countDocuments()
          ]);

          if (exams.length === 0) {
            return {
              success: true,
              msg: "查询成功",
              list: [],
              pagination: {
                page: Number(userPage),
                limit: Number(userLimit),
                total: 0,
                totalPages: 0
              }
            };
          }

          // 2. 查询该用户的所有答题记录
          const examIds = exams.map(exam => exam._id.toString());
          const records = await recordCollection.find({
            account: userAccount,
            examId: { $in: examIds }
          }).toArray();

          // 3. 创建答题记录映射（examId -> true）
          const answeredMap = {};
          records.forEach(record => {
            answeredMap[record.examId.toString()] = true;
          });

          // 4. 给每张试卷添加isDone标记
          const formattedExamsWithStatus = exams.map(item => {
            const examIdStr = item._id.toString();
            
            // 解析perTypeTime为前端需要的questionTypeScores/questionTypeTimes
            const scoreMap = {};
            const timeMap = {};
            if (Array.isArray(item.perTypeTime)) {
              item.perTypeTime.forEach(pt => {
                if (pt.type && pt.score) scoreMap[pt.type] = pt.score;
                if (pt.type && pt.time) timeMap[pt.type] = pt.time;
              });
            }
            
            return {
              examId: examIdStr,
              examName: item.examName,
              subject: item.subject,
              examTime: item.examTime,
              status: item.status,
              timingType: item.timingType,
              totalTime: item.totalTime,
              questionTypeScores: scoreMap,
              questionTypeTimes: timeMap,
              perTypeTime: item.perTypeTime,
              isDone: !!answeredMap[examIdStr]  // 核心：添加作答状态标记
            };
          });

          return {
            success: true,
            msg: "查询成功",
            list: formattedExamsWithStatus,
            pagination: {
              page: Number(userPage),
              limit: Number(userLimit),
              total,
              totalPages: Math.ceil(total / userLimitNum)
            }
          };

        } catch (err) {
          console.error(`[getUserExamList error][${new Date().toLocaleString()}]：`, err);
          return {
            success: false,
            msg: `查询失败：${err.message}`
          };
        }

      // 新增：判断用户是否已答过该试卷（修复账号类型问题）
      case 'isAnswered':
        if (!params.account || !params.examId) {
          return { success: false, msg: "缺少账号/试卷ID参数" };
        }
        const accountStr = params.account.toString().trim();
        const examIdStr = params.examId.toString();
        const answeredRecord = await recordCollection.findOne({
          account: accountStr,  // 统一使用字符串类型
          examId: examIdStr     // 统一使用字符串类型
        });
        return {
          success: true,
          isAnswered: !!answeredRecord // 有记录=true，无记录=false
        };

      // ========== 新增：批量检查多个试卷的作答状态（解决性能问题） ==========
      case 'batchIsAnswered':
        if (!params.account || !Array.isArray(params.examIds) || params.examIds.length === 0) {
          return { success: false, msg: "缺少账号或试卷ID列表参数" };
        }
        
        const accountStr2 = params.account.toString().trim();
        const examIds2 = params.examIds.map(id => id.toString());
        
        try {
          // 批量查询所有答题记录
          const records = await recordCollection.find({
            account: accountStr2,   // 统一使用字符串类型
            examId: { $in: examIds2 }  // 统一使用字符串类型
          }).toArray();
          
          // 构建结果映射
          const result = {};
          examIds2.forEach(examId => {
            result[examId] = false; // 默认未作答
          });
          
          // 标记已作答的试卷
          records.forEach(record => {
            result[record.examId.toString()] = true;
          });
          
          return {
            success: true,
            data: result
          };
        } catch (err) {
          console.error(`[批量检查作答状态失败][${new Date().toLocaleString()}]：`, err);
          return { 
            success: false, 
            msg: `批量检查失败：${err.message}` 
          };
        }

      // 新增：获取用户试卷详情（仅修复originExam为空的兜底逻辑 + 新增备注返回）
      case 'getUserExamDetail':
        if (!params.account || !params.examId) {
          return { 
            code: -1, 
            msg: "缺少账号/试卷ID参数", 
            data: {} 
          };
        }
        
        // 1. 并行查询答题记录和原试卷信息
        const [userRecord, originExam] = await Promise.all([
          recordCollection.findOne({
            account: params.account.toString().trim(),
            examId: params.examId
          }),
          examCollection.findOne({
            _id: new ObjectId(params.examId)
          })
        ]);
        
        if (!userRecord) {
          return { 
            code: -1, 
            msg: "暂无答题记录", 
            data: { examDetail: [] } 
          };
        }
        
        // 3. 组装详情数据（匹配前端格式）
        let examDetail = [];
        let totalScore = 0;
        
        // ========== 仅修改此处：新增originExam为空的兜底逻辑 ==========
        if (!originExam) {
          // 原试卷不存在时，仅展示答题记录中的基础信息
          examDetail = userRecord.questions.map((q, idx) => ({
            questionId: idx + 1,
            title: q.title || `第${idx+1}题`,
            type: q.type || 'unknown',
            options: q.options || [],
            score: q.score || 0,
            userScore: q.userScore || 0, // 直接读取数据库中的userScore
            userAnswer: q.userAnswer || null,
            standardAnswer: null,
            analysis: '暂无解析'
          }));
        } else if (userRecord.questions && originExam.questions) {
          // 原有逻辑保留（现在直接读取数据库中的userScore，无需前端计算）
          examDetail = userRecord.questions.map((q, idx) => {
            const originQ = originExam.questions[idx] || {};
            
            return {
              questionId: idx + 1, // 题目ID（序号）
              title: q.title || originQ.title || `第${idx+1}题`,
              type: originQ.type || q.type || 'unknown',
              options: q.options || originQ.options || [],
              score: q.score || originQ.score || 0, // 优先取答题记录中的分值（已绑定）
              userScore: q.userScore || 0, // 直接读取数据库中的userScore
              userAnswer: q.userAnswer || null,
              standardAnswer: q.standardAnswer || originQ.answer || originQ.standardAnswer || null,
              analysis: originQ.analysis || '暂无解析',
              imgUrl: originQ.imgUrl || '' // 新增：返回图片链接
            };
          });
          // 计算总分（从数据库的userScore累加）
          totalScore = userRecord.questions.reduce((sum, q) => sum + (q.userScore || 0), 0);
        }
        // ========== 兜底逻辑结束 ==========
        
        // 4. 返回前端需要的格式（新增remark字段）
        return {
          code: 0,
          msg: "查询成功",
          data: {
            paperName: userRecord.examName || originExam?.examName || `试卷${params.examId}`,
            submitTime: userRecord.submitTime,
            totalScore: totalScore,
            remark: userRecord.remark || '', // 新增：返回备注
            examDetail: examDetail
          }
        };

      // 4. 提交试卷 + 存入 examrecord 集合（核心修改：单选/多选判分逻辑 + 新增备注存储）
      case 'submitExam':
        // 参数校验（核心：替换userId为account）
        if (!params.account) return { success: false, msg: "缺少用户账号（account）" };
        if (!params.examId) return { success: false, msg: "缺少试卷ID（examId）" };
        if (!params.answers || params.answers.length === 0) return { success: false, msg: "缺少答题数据（answers）" };

        // 查询试卷基础信息（用于记录试卷名称、科目）
        const targetExam = await examCollection.findOne({ _id: new ObjectId(params.examId) });
        if (!targetExam) return { success: false, msg: "试卷不存在" };

        // ========== 核心新增：完整实现自定义判分逻辑 ==========
        let totalUserScore = 0; // 总分
        const scoredQuestions = params.answers.map((ansItem, index) => {
          const originalQuestion = targetExam.questions[index] || {};
          // 统一处理空值和空格
          const rawUserAnswer = (ansItem.answer || '').toString().trim();
          const rawStandardAnswer = (ansItem.standardAnswer || originalQuestion.answer || '').toString().trim();
          // 优先取题目自身分值（已绑定），兜底取题型配置
          const score = Number(originalQuestion.score || ansItem.score || 0);
          let userScore = 0;

          // 判分规则（严格按你的要求实现）
          switch (ansItem.type || originalQuestion.type) {
            // 1. 单选：只匹配纯字母，完全一致得满分
            case 'single':
              // 提取纯字母（忽略空格、符号、顿号等）
              const userSingle = extractPureLetters(rawUserAnswer);
              const stdSingle = extractPureLetters(rawStandardAnswer);
              if (userSingle === stdSingle && userSingle) {
                userScore = score;
              }
              break;

            // 2. 多选：只匹配纯字母，少选且选对按比例得分
            case 'multi':
              // 提取纯字母并排序（避免顺序问题）
              const userMulti = extractPureLetters(rawUserAnswer).split('').sort().join('');
              const stdMulti = extractPureLetters(rawStandardAnswer).split('').sort().join('');
              
              if (stdMulti) {
                // 拆分标准答案为数组
                const stdArr = stdMulti.split('');
                // 拆分用户答案为数组
                const userArr = userMulti.split('');
                
                // 计算用户选对的数量（交集）
                const correctCount = userArr.filter(ans => stdArr.includes(ans)).length;
                // 检查是否多选（用户答案包含非标准答案）
                const isOverSelect = userArr.some(ans => !stdArr.includes(ans));
                
                // 判分规则：少选且选对按比例得分，多选/选错得0分
                if (correctCount > 0 && !isOverSelect) {
                  userScore = Math.round(score * (correctCount / stdArr.length));
                }
              }
              break;

            // 3. 填空：数字完全一致/文字相似度≥90%才得分
            case 'fill':
              // 纯数字类型：必须完全一致
              if (isPureNumber(rawStandardAnswer)) {
                if (rawUserAnswer === rawStandardAnswer) {
                  userScore = score;
                }
              } 
              // 文字类型：相似度≥90%
              else {
                const similarity = calculateSimilarity(rawUserAnswer, rawStandardAnswer);
                if (similarity >= 0.9) {
                  userScore = score;
                }
              }
              break;

            // 4. 简答：数字/公式≥90%得满分，文字按相似度比例得分
            case 'short':
              // 数字/公式类型：相似度≥90%得满分
              if (isNumberOrFormula(rawStandardAnswer)) {
                const similarity = calculateSimilarity(rawUserAnswer, rawStandardAnswer);
                if (similarity >= 0.9) {
                  userScore = score;
                }
              }
              // 文字类型：按相似度比例得分
              else {
                const similarity = calculateSimilarity(rawUserAnswer, rawStandardAnswer);
                userScore = Math.round(score * similarity);
              }
              break;

            default:
              userScore = 0;
          }

          totalUserScore += userScore;

          // 返回带userScore的题目数据
          return {
            title: originalQuestion.title || ansItem.questionTitle || `第${index+1}题`,
            type: ansItem.type || originalQuestion.type || 'unknown',
            options: originalQuestion.options || [],
            score: score, // 存入题目真实分值
            userScore: userScore, // 写入每题得分
            userAnswer: rawUserAnswer || null,
            standardAnswer: rawStandardAnswer,
            analysis: ansItem.analysis || originalQuestion.analysis || '',
            imgUrl: originalQuestion.imgUrl || '' // 新增：保留图片链接
          };
        });
        // ========== 判分逻辑结束 ==========

        // 构造答题记录数据（核心：增加userScore字段 + 新增remark字段）
        const recordData = {
          account: params.account.toString().trim(), // 转字符串+去空格
          examId: params.examId,                // 试卷ID
          examName: targetExam.examName,        // 试卷名称
          subject: targetExam.subject,          // 科目
          submitTime: new Date(),               // 提交时间
          totalScore: totalUserScore,           // 新增：用户总分
          remark: params.remark || '',          // 新增：存储备注
          questions: scoredQuestions            // 带userScore的题目数据
        };

        // 插入到 examrecord 集合
        await recordCollection.insertOne(recordData);
        invalidateCache('exam_statistics_all'); // 优化：答题记录变更，主动失效统计缓存
        console.log(`[答题记录][${new Date().toLocaleString()}] 用户${params.account}提交试卷${params.examId}成功，总分：${totalUserScore}，备注：${params.remark || '无'}，已存入examrecord集合`);

        return {
          success: true,
          msg: "交卷成功，答题记录已保存",
          totalScore: totalUserScore // 返回总分给前端
        };

      // ========== 核心新增：删除试卷 + 级联删除答题记录 ==========
      case 'deleteExam':
        if (!params.examId) return { success: false, msg: "请提供要删除的试卷ID" };

        // 1. 先查询试卷，获取题目中的图片列表
        const examToDelete = await examCollection.findOne({ _id: new ObjectId(params.examId) });
        if (!examToDelete) {
          return { success: false, msg: "试卷不存在" };
        }

        // 2. 收集所有题目的图片文件名（去重）
        const imageFileNames = new Set();
        if (examToDelete.questions && Array.isArray(examToDelete.questions)) {
          examToDelete.questions.forEach(question => {
            if (question.imgUrl) {
              // 从 URL 中提取文件名，例如：{SERVER_HOST}/Pictures/xxx.jpg
              const match = question.imgUrl.match(/\/Pictures\/([^?]+)/);
              if (match && match[1]) {
                imageFileNames.add(match[1]);
              }
            }
          });
        }

        // 3. 并发删除图片文件（不阻塞等待，单个失败不影响整体）
        await Promise.all(
          Array.from(imageFileNames).map(async (fileName) => {
            const filePath = path.join(imgSaveDir, fileName);
            try {
              await fsPromises.unlink(filePath);
            } catch (err) {
              if (err.code !== 'ENOENT') {
                console.error(`删除图片文件失败: ${filePath}`, err);
              }
            }
          })
        );

        // 4. 并行删除答题记录和试卷本身
        const [deleteRecordResult, deleteExamResult] = await Promise.all([
          recordCollection.deleteMany({
            examId: params.examId
          }),
          examCollection.deleteOne({
            _id: new ObjectId(params.examId)
          })
        ]);
        console.log(`[删除答题记录][${new Date().toLocaleString()}] 试卷${params.examId}：删除${deleteRecordResult.deletedCount}条记录`);

        if (deleteExamResult.deletedCount === 0) {
          return { success: false, msg: "试卷不存在，删除失败" };
        }

        invalidateCache('exam_statistics_all'); // 优化：试卷及记录被删除，主动失效统计缓存
        console.log(`[删除试卷][${new Date().toLocaleString()}] 成功，ID：${params.examId}，已删除 ${imageFileNames.size} 个关联图片`);
        return {
          success: true,
          msg: "试卷及所有答题记录已删除，关联图片已清理",
          deletedExamCount: deleteExamResult.deletedCount,
          deletedRecordCount: deleteRecordResult.deletedCount,
          deletedImageCount: imageFileNames.size
        };

      // ========== 核心新增：试卷统计（返回所有用户+所有答题记录 + 新增备注返回） ==========
      case 'getExamStatistics':
        try {
          // 优化：对统计结果加缓存（TTL 30 秒），写操作（submitExam/rejudgeQuestion/deleteExamRecord/deleteExam）后主动失效
          const statsResult = await cachedQuery('exam_statistics_all', async () => {
            // 1. 从答题记录表取所有记录（不做任何用户过滤）
            // P1 性能项：此处 .toArray() 会将 examrecord 集合中所有答题记录全部加载进内存
            // 优化：仅投影必要字段，避免传输完整文档（含 questions 大数组时内存占用大）
            const allRecords = await recordCollection
              .find({}, {
                projection: {
                  account: 1,
                  examId: 1,
                  examName: 1,
                  submitTime: 1,
                  totalScore: 1,
                  remark: 1,
                  questions: 1
                }
              })
              .sort({ account: 1, submitTime: -1 })
              .toArray();

            if (!allRecords || allRecords.length === 0) {
              return { success: true, data: { userList: [] } };
            }

            // 1. 先查询所有学生的备注信息
            const distinctAccounts = [...new Set(allRecords.map(r => r.account))];
            const userCollection = dbPool.getCollection('user');
            const studentsInfo = await userCollection
              .find({ account: { $in: distinctAccounts }, type: 2 }, { projection: { account: 1, remark: 1 } })
              .toArray();
            const studentRemarkMap = {};
            studentsInfo.forEach(s => { studentRemarkMap[s.account] = s.remark || ''; });

            // 2. 按用户分组（核心修复：完善题型列表和分数计算 + 新增备注）
            const userMap = {};

            for (const record of allRecords) {
              const account = record.account;
              const examId = record.examId;

              // 初始化用户
              if (!userMap[account]) {
                userMap[account] = {
                  account: account,
                  remark: studentRemarkMap[account] || '', // 使用学生真实备注
                  examList: []
                };
              }

              // 该用户的试卷是否已存在
              const existExam = userMap[account].examList.find(
                item => item.examId === examId
              );

              if (!existExam) {
                // 核心修复：确保questions数组存在
                const questions = Array.isArray(record.questions) ? record.questions : [];

                // 按题型过滤题目列表（兼容多种 type 命名规范）
                const normalizeType = (t) => {
                  if (!t) return '';
                  const s = t.toString().toLowerCase().trim();
                  // 英文规范
                  if (['single', '单选'].includes(s)) return 'single';
                  if (['multi', 'multiple', '多选题', '多项选择'].includes(s)) return 'multi';
                  if (['fill', '填空', '填空题'].includes(s)) return 'fill';
                  if (['short', '简答', '简答题', 'essay'].includes(s)) return 'short';
                  return s; // 保持原值
                };
                const singleList = questions.filter(q => normalizeType(q.type) === 'single');
                const multiList = questions.filter(q => normalizeType(q.type) === 'multi');
                const fillList = questions.filter(q => normalizeType(q.type) === 'fill');
                const shortList = questions.filter(q => normalizeType(q.type) === 'short');

                // 安全的分数计算函数
                const calScore = (list) => {
                  if (!Array.isArray(list)) return 0;
                  return list.reduce((sum, q) => sum + (q.userScore || 0), 0);
                };
                
                const calTotal = (list) => {
                  if (!Array.isArray(list)) return 0;
                  return list.reduce((sum, q) => sum + (q.score || 0), 0);
                };

                // 构造试卷数据（完整兜底 + 新增remark字段）
                const examData = {
                  examId: examId || '',
                  examName: record.examName || `试卷${examId}`,
                  submitTime: record.submitTime || new Date(),
                  totalScore: record.totalScore || 0,
                  remark: record.remark || '', // 新增：备注字段
                  questions: questions,
                  // 题型列表（兜底为空数组）
                  singleList: singleList || [],
                  multiList: multiList || [],
                  fillList: fillList || [],
                  shortList: shortList || [],
                  // 各题型得分/总分（兜底为0）
                  singleScore: calScore(singleList),
                  singleTotalScore: calTotal(singleList),
                  multiScore: calScore(multiList),
                  multiTotalScore: calTotal(multiList),
                  fillScore: calScore(fillList),
                  fillTotalScore: calTotal(fillList),
                  shortScore: calScore(shortList),
                  shortTotalScore: calTotal(shortList)
                };

                userMap[account].examList.push(examData);
              }
            }

            // 3. 转成数组返回
            const userList = Object.values(userMap);

            return {
              success: true,
              data: {
                userList: userList
              }
            };
          }, 30000);
          return statsResult;

        } catch (err) {
          console.error('getExamStatistics error：', err);
          return {
            success: false,
            msg: '统计失败：' + err.message
          };
        }

      // 无效action（原有逻辑不变）
      default:
        return { success: false, msg: `无效的 action：${params.action}` };
    }

  } catch (err) {
    console.error(`[试卷处理异常][${new Date().toLocaleString()}]：`, err.stack);
    return { success: false, msg: `服务器内部错误：${err.message}` };
  }
}

module.exports = { examHandler };