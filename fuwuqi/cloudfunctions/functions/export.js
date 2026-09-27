const { dbPool } = require('../utils');
const ExcelJS = require('exceljs');
const path = require('path');
const fs = require('fs');
const https = require('https');
const http = require('http');

const EXPORT_DIR = path.join(__dirname, '..', 'exports');

if (!fs.existsSync(EXPORT_DIR)) {
  fs.mkdirSync(EXPORT_DIR, { recursive: true });
}

// ====================== 样式常量 ======================
const HEADER_FILL   = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF4A90D9' } };
const HEADER_FONT   = { bold: true, color: { argb: 'FFFFFFFF' }, size: 11 };
const HEADER_ALIGN  = { vertical: 'middle', horizontal: 'center', wrapText: true };
const DATA_ALIGN    = { vertical: 'middle', horizontal: 'center' };
const TOTAL_FILL    = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFFFF3E0' } };
const TOTAL_FONT    = { bold: true, color: { argb: 'FFE65100' } };
const ZEBRA_1       = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFFFFFFF' } };
const ZEBRA_2       = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFF7F9FC' } };
const LIGHT_BORDER  = { top: { style: 'thin', color: { argb: 'FFD9DEE7' } }, bottom: { style: 'thin', color: { argb: 'FFD9DEE7' } }, left: { style: 'thin', color: { argb: 'FFD9DEE7' } }, right: { style: 'thin', color: { argb: 'FFD9DEE7' } } };
const HEADER_BORDER = { top: { style: 'medium', color: { argb: 'FF2E75B6' } }, bottom: { style: 'thin', color: { argb: 'FFD9DEE7' } }, left: { style: 'thin', color: { argb: 'FFD9DEE7' } }, right: { style: 'thin', color: { argb: 'FFD9DEE7' } } };

// ====================== 工具函数 ======================
function cleanOldExports() {
  try {
    const files = fs.readdirSync(EXPORT_DIR);
    const now = Date.now();
    files.forEach(f => {
      const fp = path.join(EXPORT_DIR, f);
      if (now - fs.statSync(fp).mtimeMs > 3600000) fs.unlinkSync(fp);
    });
  } catch (_) {}
}

function fmtDate(d) {
  if (!d) return '';
  const dt = d instanceof Date ? d : new Date(d);
  if (isNaN(dt.getTime())) return String(d || '');
  const y = dt.getFullYear();
  const m = String(dt.getMonth() + 1).padStart(2, '0');
  const dd = String(dt.getDate()).padStart(2, '0');
  const h = String(dt.getHours()).padStart(2, '0');
  const mi = String(dt.getMinutes()).padStart(2, '0');
  return `${y}-${m}-${dd} ${h}:${mi}`;
}

/**
 * 专业样式：表头（蓝色填充+粗边框）+ 冻结首行 + 自动筛选
 */
function styleSheet(sheet, colCount) {
  const colLetter = String.fromCharCode(64 + colCount);
  const headerRow = sheet.getRow(1);
  headerRow.font    = HEADER_FONT;
  headerRow.fill    = HEADER_FILL;
  headerRow.alignment = HEADER_ALIGN;
  headerRow.height  = 28;
  for (let i = 1; i <= colCount; i++) {
    headerRow.getCell(i).border = HEADER_BORDER;
  }
  headerRow.commit();
  sheet.views = [{ state: 'frozen', ySplit: 1 }];
  sheet.autoFilter = { from: 'A1', to: `${colLetter}1` };
}

/**
 * 数据行：斑马纹交替 + 浅灰细边框 + 居中对齐
 */
function addDataRow(sheet, rowData, rowNum) {
  const row  = sheet.getRow(rowNum);
  const fill = (rowNum % 2 === 0) ? ZEBRA_1 : ZEBRA_2;
  rowData.forEach((val, i) => {
    const cell = row.getCell(i + 1);
    cell.value  = val !== undefined && val !== null ? val : '';
    cell.alignment = DATA_ALIGN;
    cell.fill    = fill;
    cell.border  = LIGHT_BORDER;
  });
  row.commit();
}

/**
 * 空数据提示：动态合并所有列
 */
function addEmptyMessage(sheet, message) {
  const colCount = sheet.columns ? sheet.columns.length : 7;
  const colLetter = String.fromCharCode(64 + colCount);
  sheet.getCell('A2').value = message;
  sheet.getCell('A2').font  = { italic: true, color: { argb: 'FF999999' }, size: 12 };
  sheet.getCell('A2').alignment = { horizontal: 'center', vertical: 'middle' };
  sheet.mergeCells(`A2:${colLetter}2`);
}

// ====================== 数据获取 ======================
async function getStudentNameMap() {
  const userColl = dbPool.getCollection('user');
  const students = await userColl.find({
    $or: [{ type: 2 }, { type: '2' }]
  }).project({ account: 1, remark: 1 }).toArray();
  const map = {};
  students.forEach(s => { map[s.account] = s.remark || s.account; });
  console.log(`[EXPORT] nameMap: found ${Object.keys(map).length} students`);
  return map;
}

async function getExamRecords(filters, nameMap) {
  const coll = dbPool.getCollection('examrecord');
  const cond = {};

  if (filters.examStartDate && filters.examEndDate) {
    cond.submitTime = {
      $gte: new Date(filters.examStartDate + 'T00:00:00'),
      $lte: new Date(filters.examEndDate + 'T23:59:59')
    };
  }
  if (filters.examStudentFilter === 'selected' && Array.isArray(filters.examSelectedStudents) && filters.examSelectedStudents.length > 0) {
    cond.account = { $in: filters.examSelectedStudents };
  }
  if (filters.examPaperFilter === 'selected' && filters.selectedExamId) {
    cond.examId = filters.selectedExamId;
  }

  console.log(`[EXPORT] exam query cond:`, JSON.stringify(cond));
  const records = await coll.find(cond).sort({ account: 1, submitTime: -1 }).toArray();
  console.log(`[EXPORT] exam raw records: ${records.length}`);

  return records.map(r => ({
    account:  r.account  || '',
    name:     nameMap[r.account] || r.account || '',
    examId:   r.examId   || '',
    examName: r.examName || '',
    subject:  r.subject  || '',
    submitTime: r.submitTime,
    totalScore: Number(r.totalScore) || 0,
    questions: Array.isArray(r.questions) ? r.questions : []
  }));
}

async function getStudyRecords(filters, nameMap) {
  const coll = dbPool.getCollection('timerecord');
  const cond = {};

  let startDate = filters.studyStartDate;
  let endDate   = filters.studyEndDate;

  if (filters.rangeId) {
    const timeColl = dbPool.getCollection('time');
    const rangeDoc = await timeColl.findOne({ _id: filters.rangeId });
    if (rangeDoc) {
      startDate = rangeDoc.startDate;
      endDate   = rangeDoc.endDate;
      console.log(`[EXPORT] timerange: ${rangeDoc.name} (${startDate} ~ ${endDate})`);
    } else {
      console.log(`[EXPORT] WARNING: rangeId "${filters.rangeId}" not found`);
    }
  }

  if (startDate && endDate) {
    cond.date = { $gte: startDate, $lte: endDate };
  }
  if (filters.studyStudentFilter === 'selected' && Array.isArray(filters.studySelectedStudents) && filters.studySelectedStudents.length > 0) {
    cond.userid = { $in: filters.studySelectedStudents };
  }

  console.log(`[EXPORT] study query cond:`, JSON.stringify(cond));
  const records = await coll.find(cond).sort({ date: 1, userid: 1 }).toArray();
  console.log(`[EXPORT] study raw records: ${records.length}`);

  return records.map(r => ({
    account: r.userid || '',
    name:    nameMap[r.userid] || r.userid || '',
    date:    r.date || '',
    chinese: Number(r.chinese) || 0,
    math:    Number(r.math)    || 0,
    english: Number(r.english) || 0,
    other:   Number(r.other)   || 0,
    total:   (Number(r.chinese) || 0) + (Number(r.math) || 0) + (Number(r.english) || 0) + (Number(r.other) || 0)
  }));
}

// ====================== 考试数据表 ======================
async function buildExamSheets(workbook, records, filters) {
  // ── Sheet 1: 考试-成绩汇总 ──────────────────────────────
  const s1 = workbook.addWorksheet('考试-成绩汇总', { properties: { tabColor: { argb: 'FF4A90D9' } } });
  const s1Cols = [
    { header: '账号/备注', key: 'account',  width: 18 },
    { header: '试卷名称',  key: 'examName', width: 32 },
    { header: '科目',      key: 'subject',  width: 10 },
    { header: '总分',      key: 'totalScore', width: 10 },
    { header: '提交时间',  key: 'submitTime', width: 22 },
  ];
  s1.columns = s1Cols;
  if (records.length === 0) {
    addEmptyMessage(s1, '该筛选条件下暂无考试数据');
  } else {
    records.forEach((r, i) => addDataRow(s1, [
      `${r.account}（${r.name}）`, r.examName, r.subject, r.totalScore, fmtDate(r.submitTime)
    ], i + 2));
    const totalRow = s1.getRow(records.length + 2);
    totalRow.getCell(1).value = '合计';
    totalRow.getCell(4).value = records.reduce((s, r) => s + r.totalScore, 0);
    totalRow.getCell(5).value = `${records.length} 条记录`;
    totalRow.font = TOTAL_FONT; totalRow.fill = TOTAL_FILL; totalRow.alignment = DATA_ALIGN;
    totalRow.commit();
  }
  styleSheet(s1, s1Cols.length);

  // ── Sheet 2: 考试-答题明细（按账号合并账号/备注列）────
  const s2 = workbook.addWorksheet('考试-答题明细', { properties: { tabColor: { argb: 'FFE86452' } } });
  const s2Cols = [
    { header: '账号/备注', key: 'account',  width: 18 },
    { header: '试卷',      key: 'examName', width: 28 },
    { header: '题号',      key: 'qIdx',     width: 8  },
    { header: '题型',      key: 'qType',    width: 10 },
    { header: '题目',      key: 'qTitle',   width: 50 },
    { header: '满分',      key: 'qScore',   width: 8  },
    { header: '得分',      key: 'qUserScore', width: 8 },
    { header: '学生答案',  key: 'qUserAns', width: 30 },
    { header: '标准答案',  key: 'qStdAns',  width: 30 },
    { header: '解析',      key: 'qAnalysis',width: 40 },
  ];
  s2.columns = s2Cols;
  if (records.length === 0) {
    addEmptyMessage(s2, '该筛选条件下暂无答题明细');
  } else {
    let rowIdx = 2;
    let hasQuestions = false;
    // 合并行状态：记录每个账号/备注连续相同段的首行和长度
    let lastAccount = null, lastName = null;
    let accStartRow = null, nameStartRow = null;
    let accMergeRows = 0, nameMergeRows = 0;

    const flushMerge = () => {
      if (accMergeRows > 1 && accStartRow !== null) {
        s2.mergeCells(`A${accStartRow}:A${accStartRow + accMergeRows - 1}`);
        s2.mergeCells(`B${nameStartRow}:B${nameStartRow + nameMergeRows - 1}`);
      }
    };

    records.forEach(r => {
      if (r.questions.length === 0) return;
      hasQuestions = true;
      r.questions.forEach((q, qi) => {
        const rowNum = rowIdx++;
        const isSameGroup = (r.account === lastAccount && r.name === lastName);
        if (!isSameGroup) {
          flushMerge();
          accStartRow    = rowNum;
          nameStartRow   = rowNum;
          accMergeRows   = 0;
          nameMergeRows  = 0;
          lastAccount    = r.account;
          lastName       = r.name;
        }
        addDataRow(s2, [
          `${r.account}（${r.name}）`, r.examName, qi + 1, q.type || '',
          (q.title || '').substring(0, 200),
          Number(q.score) || 0, Number(q.userScore) || 0,
          (q.userAnswer || '').toString().substring(0, 200),
          (q.standardAnswer || '').toString().substring(0, 200),
          (q.analysis || '').substring(0, 200)
        ], rowNum);
        accMergeRows++;
        nameMergeRows++;
      });
    });
    flushMerge();
    if (!hasQuestions) addEmptyMessage(s2, '答题记录中暂无题目明细数据');
  }
  styleSheet(s2, s2Cols.length);

  // ── Sheet 3: 考试-学生汇总（按账号+试卷合并）─────────
  const s3 = workbook.addWorksheet('考试-学生汇总', { properties: { tabColor: { argb: 'FF9C27B0' } } });
  const s3Cols = [
    { header: '账号/备注', key: 'account', width: 18 },
    { header: '试卷名称',  key: 'examName', width: 28 },
    { header: '科目',      key: 'subject', width: 10 },
    { header: '总分',      key: 'totalScore', width: 10 },
    { header: '单选(得分/满分)', key: 'single', width: 16 },
    { header: '多选(得分/满分)', key: 'multi', width: 16 },
    { header: '填空(得分/满分)', key: 'fill', width: 16 },
    { header: '简答(得分/满分)', key: 'short', width: 16 },
    { header: '提交时间',   key: 'submitTime', width: 22 },
  ];
  s3.columns = s3Cols;
  if (records.length === 0) {
    addEmptyMessage(s3, '该筛选条件下暂无学生汇总数据');
  } else {
    const calScore = list => !Array.isArray(list) ? 0 : list.reduce((s, q) => s + (Number(q.userScore) || 0), 0);
    const calTotal = list => !Array.isArray(list) ? 0 : list.reduce((s, q) => s + (Number(q.score) || 0), 0);

    // 按账号+试卷合并（分组键为 account + examName）
    let lastKey  = null;
    let accStart = null, nameStart = null;
    let accRows  = 0, nameRows = 0;

    const flushMerge = () => {
      if (accRows > 1 && accStart !== null) {
        s3.mergeCells(`A${accStart}:A${accStart + accRows - 1}`);
        s3.mergeCells(`B${nameStart}:B${nameStart + nameRows - 1}`);
      }
    };

    records.forEach((r, i) => {
      const rowNum = i + 2;
      const groupKey = `${r.account}||${r.examName}`;
      const isSameGroup = (groupKey === lastKey);
      if (!isSameGroup) {
        flushMerge();
        accStart   = rowNum;
        nameStart  = rowNum;
        accRows    = 0;
        nameRows   = 0;
        lastKey    = groupKey;
      }

      const qs = r.questions || [];
      addDataRow(s3, [
        `${r.account}（${r.name}）`, r.subject, r.totalScore,
        `${calScore(qs.filter(q => q.type === 'single'))}/${calTotal(qs.filter(q => q.type === 'single'))}`,
        `${calScore(qs.filter(q => q.type === 'multi'))}/${calTotal(qs.filter(q => q.type === 'multi'))}`,
        `${calScore(qs.filter(q => q.type === 'fill'))}/${calTotal(qs.filter(q => q.type === 'fill'))}`,
        `${calScore(qs.filter(q => q.type === 'short'))}/${calTotal(qs.filter(q => q.type === 'short'))}`,
        fmtDate(r.submitTime)
      ], rowNum);
      accRows++;
      nameRows++;
    });
    flushMerge();

    const totalRow = s3.getRow(records.length + 2);
    totalRow.getCell(1).value = '合计';
    totalRow.getCell(4).value = records.reduce((s, r) => s + r.totalScore, 0);
    totalRow.getCell(5).value = `${records.length} 条`;
    totalRow.font = TOTAL_FONT; totalRow.fill = TOTAL_FILL; totalRow.alignment = DATA_ALIGN;
    totalRow.commit();
  }
  styleSheet(s3, s3Cols.length);

  // ── Sheet 4: 考试-科目统计 ───────────────────────────
  const s4 = workbook.addWorksheet('考试-科目统计', { properties: { tabColor: { argb: 'FFFF7043' } } });
  const s4Cols = [
    { header: '科目',     key: 'subject',   width: 10 },
    { header: '考试次数', key: 'count',     width: 12 },
    { header: '平均分',   key: 'avgScore',  width: 12 },
    { header: '最高分',   key: 'maxScore',  width: 12 },
    { header: '最低分',   key: 'minScore',  width: 12 },
    { header: '及格数',   key: 'passCount', width: 10 },
    { header: '及格率',   key: 'passRate',  width: 10 },
  ];
  s4.columns = s4Cols;
  if (records.length === 0) {
    addEmptyMessage(s4, '该筛选条件下暂无科目统计数据');
  } else {
    const subjMap = {};
    records.forEach(r => {
      const subj = r.subject || '未知';
      if (!subjMap[subj]) subjMap[subj] = { subject: subj, scores: [] };
      subjMap[subj].scores.push(r.totalScore);
    });
    Object.values(subjMap).forEach((s, i) => {
      const scores = s.scores;
      const sum    = scores.reduce((a, b) => a + b, 0);
      const passC  = scores.filter(x => x >= 60).length;
      addDataRow(s4, [
        s.subject, scores.length,
        scores.length > 0 ? Math.round(sum / scores.length * 10) / 10 : 0,
        scores.length > 0 ? Math.max(...scores) : 0,
        scores.length > 0 ? Math.min(...scores) : 0,
        passC,
        scores.length > 0 ? Math.round(passC / scores.length * 100) + '%' : '0%'
      ], i + 2);
    });
  }
  styleSheet(s4, s4Cols.length);
}

// ====================== 学习数据表 ======================
async function buildStudySheets(workbook, records, filters) {
  const showChinese = filters.studySubjectFilter !== 'selected' || (filters.studySelectedSubjects || []).includes('chinese');
  const showMath    = filters.studySubjectFilter !== 'selected' || (filters.studySelectedSubjects || []).includes('math');
  const showEnglish = filters.studySubjectFilter !== 'selected' || (filters.studySelectedSubjects || []).includes('english');
  const showOther   = filters.studySubjectFilter !== 'selected' || (filters.studySelectedSubjects || []).includes('other');

  // 学生维度聚合（按账号合并同一学生多天的记录）
  const studentMap = {};
  records.forEach(r => {
    if (!studentMap[r.account]) {
      studentMap[r.account] = { account: r.account, name: r.name, chinese: 0, math: 0, english: 0, other: 0, total: 0, days: 0 };
    }
    const s = studentMap[r.account];
    s.chinese += r.chinese; s.math += r.math;
    s.english += r.english; s.other += r.other;
    s.total  += r.total;   s.days   += 1;
  });
  const studentList = Object.values(studentMap);

  // ── Sheet 1: 学习-时长汇总 ────────────────────────────
  const s1 = workbook.addWorksheet('学习-时长汇总', { properties: { tabColor: { argb: 'FF5AD8A6' } } });
  const s1Cols = [{ header: '账号/备注', key: 'account', width: 18 }, { header: '学习天数', key: 'days', width: 12 }];
  if (showChinese) s1Cols.push({ header: '语文(分钟)', key: 'chinese', width: 14 });
  if (showMath)    s1Cols.push({ header: '数学(分钟)', key: 'math',    width: 14 });
  if (showEnglish) s1Cols.push({ header: '英语(分钟)', key: 'english', width: 14 });
  if (showOther)   s1Cols.push({ header: '其他(分钟)', key: 'other',   width: 14 });
  s1Cols.push({ header: '总计(分钟)', key: 'total', width: 14 });
  s1.columns = s1Cols;
  if (studentList.length === 0) {
    addEmptyMessage(s1, '该筛选条件下暂无学习数据');
  } else {
    studentList.forEach((s, i) => {
      const row = [`${s.account}（${s.name}）`, s.days];
      if (showChinese) row.push(s.chinese);
      if (showMath)    row.push(s.math);
      if (showEnglish) row.push(s.english);
      if (showOther)   row.push(s.other);
      row.push(s.total);
      addDataRow(s1, row, i + 2);
    });
    const totalRow = s1.getRow(studentList.length + 2);
    totalRow.getCell(1).value = '合计';
    totalRow.getCell(2).value = `${studentList.length} 人`;
    let colIdx = 3;
    if (showChinese) totalRow.getCell(colIdx++).value = studentList.reduce((s, r) => s + r.chinese, 0);
    if (showMath)    totalRow.getCell(colIdx++).value = studentList.reduce((s, r) => s + r.math,    0);
    if (showEnglish) totalRow.getCell(colIdx++).value = studentList.reduce((s, r) => s + r.english, 0);
    if (showOther)   totalRow.getCell(colIdx++).value = studentList.reduce((s, r) => s + r.other,   0);
    totalRow.getCell(colIdx).value = studentList.reduce((s, r) => s + r.total, 0);
    totalRow.font = TOTAL_FONT; totalRow.fill = TOTAL_FILL; totalRow.alignment = DATA_ALIGN;
    totalRow.commit();
  }
  styleSheet(s1, s1Cols.length);

  // ── Sheet 2: 学习-每日明细（按账号合并账号/备注列）────
  const s2 = workbook.addWorksheet('学习-每日明细', { properties: { tabColor: { argb: 'FFF6BD16' } } });
  const s2Cols = [{ header: '账号/备注', key: 'account', width: 18 }, { header: '日期', key: 'date', width: 14 }];
  if (showChinese) s2Cols.push({ header: '语文(分钟)', key: 'chinese', width: 14 });
  if (showMath)    s2Cols.push({ header: '数学(分钟)', key: 'math',    width: 14 });
  if (showEnglish) s2Cols.push({ header: '英语(分钟)', key: 'english', width: 14 });
  if (showOther)   s2Cols.push({ header: '其他(分钟)', key: 'other',   width: 14 });
  s2Cols.push({ header: '当日合计(分钟)', key: 'total', width: 16 });
  s2.columns = s2Cols;
  if (records.length === 0) {
    addEmptyMessage(s2, '该筛选条件下暂无每日明细数据');
  } else {
    // 按账号/备注合并（按 userid + date 排序后自然连续）
    let lastAcct = null;
    let acctStart = null;
    let acctRows = 0;

    const flushMerge = () => {
      if (acctRows > 1 && acctStart !== null) {
        s2.mergeCells(`A${acctStart}:A${acctStart + acctRows - 1}`);
      }
    };

    records.forEach((r, i) => {
      const rowNum = i + 2;
      const isSameGroup = (r.account === lastAcct);
      if (!isSameGroup) {
        flushMerge();
        acctStart  = rowNum;
        acctRows   = 0;
        lastAcct   = r.account;
      }
      const row = [`${r.account}（${r.name}）`, r.date];
      if (showChinese) row.push(r.chinese);
      if (showMath)    row.push(r.math);
      if (showEnglish) row.push(r.english);
      if (showOther)   row.push(r.other);
      row.push(r.total);
      addDataRow(s2, row, rowNum);
      acctRows++;
    });
    flushMerge();
  }
  styleSheet(s2, s2Cols.length);
}

// ====================== 图表生成 ======================
function httpGetImage(urlStr) {
  return new Promise(resolve => {
    const lib = urlStr.startsWith('https') ? https : http;
    const req = lib.get(urlStr, { timeout: 20000 }, res => {
      if (res.statusCode !== 200) { res.resume(); resolve(null); return; }
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve(chunks.length > 0 ? Buffer.concat(chunks) : null));
    });
    req.on('error', () => resolve(null));
    req.on('timeout', () => { req.destroy(); resolve(null); });
  });
}

function httpPostImage(hostname, pathStr, postData) {
  return new Promise(resolve => {
    const options = { hostname, path: pathStr, method: 'POST', timeout: 20000,
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(postData) } };
    const req = https.request(options, res => {
      if (res.statusCode !== 200) { res.resume(); resolve(null); return; }
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve(chunks.length > 0 ? Buffer.concat(chunks) : null));
    });
    req.on('error', () => resolve(null));
    req.on('timeout', () => { req.destroy(); resolve(null); });
    req.write(postData);
    req.end();
  });
}

async function getChartImage(chartConfig, width, height) {
  const w = width || 900;
  const h = height || 550;
  const postData  = JSON.stringify({ chart: chartConfig, format: 'png', width: w, height: h, backgroundColor: 'white' });
  const getUrl    = `https://quickchart.io/chart?c=${encodeURIComponent(JSON.stringify(chartConfig))}&f=png&w=${w}&h=${h}&bkg=white`;
  let img = await httpGetImage(getUrl);
  if (img) { console.log('[EXPORT] chart GET succeeded, size:', img.length); return img; }
  console.log('[EXPORT] trying chart POST...');
  img = await httpPostImage('quickchart.io', '/chart', postData);
  if (img) { console.log('[EXPORT] chart POST succeeded, size:', img.length); return img; }
  console.log('[EXPORT] all chart API attempts failed');
  return null;
}

/**
 * 图例数据表（柱状图/饼图生成失败时的降级方案）
 */
function buildChartDataTable(sheet, startRow, title, headers, data) {
  sheet.getCell(`A${startRow}`).value   = title;
  sheet.getCell(`A${startRow}`).font    = { bold: true, size: 13 };
  const headerRow = sheet.getRow(startRow + 1);
  headers.forEach((h, i) => {
    const cell = headerRow.getCell(i + 1);
    cell.value = h; cell.font = HEADER_FONT; cell.fill = HEADER_FILL;
    cell.alignment = HEADER_ALIGN; cell.border = HEADER_BORDER;
  });
  headerRow.commit();
  data.forEach((row, i) => {
    const r = sheet.getRow(startRow + 2 + i);
    const fill = ((startRow + 2 + i) % 2 === 0) ? ZEBRA_1 : ZEBRA_2;
    row.forEach((val, j) => {
      const cell = r.getCell(j + 1);
      cell.value = val; cell.alignment = DATA_ALIGN; cell.fill = fill; cell.border = LIGHT_BORDER;
    });
    r.commit();
  });
  return startRow + 2 + data.length + 2;
}

// 图表在 Excel 中的展示尺寸（像素）—— ExcelJS ext 单位为像素
const BAR_IMG_EXT  = { width: 900, height: 550 };
const PIE_IMG_EXT  = { width: 700, height: 550 };

async function buildExamCharts(workbook, summary) {
  if (!summary || !summary.subjectStats?.length) { console.log('[EXPORT] exam charts: no data, skipping'); return; }
  const sheet = workbook.addWorksheet('考试-图表', { properties: { tabColor: { argb: 'FF9B59B6' } } });

  const barConfig = {
    type: 'bar',
    data: {
      labels: summary.subjectStats.map(s => s.subject),
      datasets: [{ label: '平均分', data: summary.subjectStats.map(s => s.avgScore),
        backgroundColor: ['rgba(91,143,249,0.7)','rgba(90,216,166,0.7)','rgba(246,189,22,0.7)','rgba(232,100,82,0.7)'],
        barPercentage: 0.5, categoryPercentage: 0.7 }]
    },
    options: { scales: { y: { beginAtZero: true, max: 100 } },
      plugins: {
        title: { display: true, text: '各科平均分', font: { size: 18 } },
        legend: { labels: { font: { size: 14 } } },
        datalabels: { display: true, anchor: 'end', align: 'top', font: { weight: 'bold', size: 14 } }
      }
    }
  };
  const pieConfig = summary.scoreDistribution?.length ? {
    type: 'pie',
    data: {
      labels: summary.scoreDistribution.map(s => s.range),
      datasets: [{ data: summary.scoreDistribution.map(s => s.count),
        backgroundColor: ['rgba(232,100,82,0.8)','rgba(250,173,20,0.8)','rgba(255,214,102,0.8)','rgba(90,216,166,0.8)','rgba(91,143,249,0.8)'] }]
    },
    options: { plugins: { legend: { position: 'bottom', labels: { font: { size: 14 } } }, tooltip: { enabled: true } } }
  } : null;

  let nextRow = 1;
  const [barImg, pieImg] = await Promise.all([
    getChartImage(barConfig, 900, 550),
    pieConfig ? getChartImage(pieConfig, 700, 550) : Promise.resolve(null)
  ]);

  if (barImg) {
    sheet.getCell('A1').value = '各科平均分（柱状图）';
    sheet.getCell('A1').font = { bold: true, size: 12 };
    const imgId = workbook.addImage({ buffer: barImg, extension: 'png' });
    sheet.addImage(imgId, { tl: { col: 0, row: 1 }, ext: BAR_IMG_EXT });
    nextRow = 32;
  } else {
    sheet.getCell('A1').value = '各科平均分（数据表）';
    sheet.getCell('A1').font = { bold: true, size: 12 };
    nextRow = buildChartDataTable(sheet, 1, '各科平均分', ['科目', '平均分', '考试数'],
      summary.subjectStats.map(s => [s.subject, s.avgScore, s.count]));
  }

  if (pieConfig) {
    if (pieImg) {
      sheet.getCell(`A${nextRow}`).value = '分数段分布（饼状图）';
      sheet.getCell(`A${nextRow}`).font = { bold: true, size: 12 };
      const imgId = workbook.addImage({ buffer: pieImg, extension: 'png' });
      sheet.addImage(imgId, { tl: { col: 0, row: nextRow + 1 }, ext: PIE_IMG_EXT });
    } else {
      nextRow = buildChartDataTable(sheet, nextRow, '分数段分布', ['分数段', '人数'],
        summary.scoreDistribution.map(s => [s.range, s.count]));
    }
  }
}

async function buildStudyCharts(workbook, summary) {
  if (!summary) { console.log('[EXPORT] study charts: no data, skipping'); return; }
  const sheet = workbook.addWorksheet('学习-图表', { properties: { tabColor: { argb: 'FF1ABC9C' } } });

  const pieConfig = summary.subjectTotals?.length ? {
    type: 'pie',
    data: {
      labels: summary.subjectTotals.map(s => s.subject),
      datasets: [{ data: summary.subjectTotals.map(s => s.totalMinutes),
        backgroundColor: ['rgba(91,143,249,0.8)','rgba(90,216,166,0.8)','rgba(246,189,22,0.8)','rgba(232,100,82,0.8)'] }]
    },
    options: { plugins: { legend: { position: 'bottom', labels: { font: { size: 14 } } }, tooltip: { enabled: true } } }
  } : null;

  const top10 = summary.studentTotals?.slice(0, 10) || [];
  const barConfig = top10.length ? {
    type: 'bar',
    data: {
      labels: top10.map(s => s.name),
      datasets: [{ label: '学习时长(分钟)', data: top10.map(s => s.totalMinutes), backgroundColor: 'rgba(90,216,166,0.7)',
        barPercentage: 0.5, categoryPercentage: 0.7 }]
    },
    options: { indexAxis: 'y',
      plugins: {
        title: { display: true, text: '学生学习时长TOP10', font: { size: 18 } },
        legend: { display: true, position: 'top', labels: { font: { size: 14, weight: 'bold' }, padding: 16 } },
        tooltip: { enabled: true }
      }
    }
  } : null;

  let nextRow = 1;
  const [pieImg, barImg] = await Promise.all([
    pieConfig ? getChartImage(pieConfig, 700, 550) : Promise.resolve(null),
    barConfig ? getChartImage(barConfig, 900, 550) : Promise.resolve(null)
  ]);

  if (pieConfig) {
    if (pieImg) {
      sheet.getCell('A1').value = '科目时长占比（饼状图）';
      sheet.getCell('A1').font = { bold: true, size: 12 };
      const imgId = workbook.addImage({ buffer: pieImg, extension: 'png' });
      sheet.addImage(imgId, { tl: { col: 0, row: 1 }, ext: PIE_IMG_EXT });
      nextRow = 32;
    } else {
      nextRow = buildChartDataTable(sheet, 1, '科目时长统计', ['科目', '总时长(分钟)'],
        summary.subjectTotals.map(s => [s.subject, s.totalMinutes]));
    }
  }

  if (barConfig) {
    if (barImg) {
      sheet.getCell(`A${nextRow}`).value = '学生学习时长TOP10（柱状图）';
      sheet.getCell(`A${nextRow}`).font = { bold: true, size: 12 };
      const imgId = workbook.addImage({ buffer: barImg, extension: 'png' });
      sheet.addImage(imgId, { tl: { col: 0, row: nextRow + 1 }, ext: BAR_IMG_EXT });
    } else {
      nextRow = buildChartDataTable(sheet, nextRow, '学生学习时长TOP10', ['排名', '姓名', '总时长(分钟)'],
        top10.map((s, i) => [i + 1, s.name, s.totalMinutes]));
    }
  }
}

// ====================== 导出概览表 ======================
function buildSummarySheet(workbook, summary) {
  const sheet = workbook.addWorksheet('导出概览', { properties: { tabColor: { argb: 'FF333333' } } });
  sheet.columns = [{ key: 'col1', width: 22 }, { key: 'col2', width: 32 }];

  sheet.getCell('A1').value = '数据导出概览';
  sheet.getCell('A1').font = { bold: true, size: 12 };
  sheet.mergeCells('A1:B1');

  const rows = [
    ['导出时间', new Date().toLocaleString('zh-CN')],
    ['导出类型', summary.exportType || '未知'],
  ];
  if (summary.exam) {
    rows.push(['', '']);
    rows.push(['—— 考试数据 ——', '']);
    rows.push(['学生数', summary.exam.totalStudents ?? 0]);
    rows.push(['试卷数', summary.exam.totalExams ?? 0]);
    rows.push(['记录数', summary.exam.totalRecords ?? 0]);
    rows.push(['平均分', summary.exam.avgScore ?? 0]);
    rows.push(['及格率', `${summary.exam.passRate ?? 0}%`]);
  }
  if (summary.study) {
    rows.push(['', '']);
    rows.push(['—— 学习数据 ——', '']);
    rows.push(['学生数', summary.study.totalStudents ?? 0]);
    rows.push(['学习天数', summary.study.totalDays ?? 0]);
    rows.push(['记录数', summary.study.totalRecords ?? 0]);
    if (summary.study.subjectTotals) {
      summary.study.subjectTotals.forEach(s => rows.push([`${s.subject}总时长`, `${s.totalMinutes} 分钟`]));
    }
  }

  rows.forEach((row, i) => {
    const r = sheet.getRow(i + 3);
    r.getCell(1).value = row[0];
    r.getCell(2).value = row[1];
    if (row[0].includes('——')) r.font = { bold: true, color: { argb: 'FF4A90D9' } };
    r.commit();
  });
}

// ====================== 汇总统计 ======================
function buildSummary(records, type) {
  if (type === 'exam') {
    const subjectStats = {};
    const scoreRanges  = { '0-59': 0, '60-69': 0, '70-79': 0, '80-89': 0, '90-100': 0 };
    let totalScore = 0, count = 0, passCount = 0;
    const students = new Set(), exams = new Set();

    records.forEach(r => {
      const score = Number(r.totalScore) || 0;
      totalScore += score; count++;
      if (score >= 60) passCount++;
      students.add(r.account); exams.add(r.examId);
      const subj = r.subject || '未知';
      if (!subjectStats[subj]) subjectStats[subj] = { subject: subj, totalScore: 0, count: 0 };
      subjectStats[subj].totalScore += score;
      subjectStats[subj].count++;
      if (score < 60)         scoreRanges['0-59']++;
      else if (score < 70)    scoreRanges['60-69']++;
      else if (score < 80)    scoreRanges['70-79']++;
      else if (score < 90)    scoreRanges['80-89']++;
      else                    scoreRanges['90-100']++;
    });

    return {
      totalStudents: students.size, totalExams: exams.size, totalRecords: count,
      avgScore: count > 0 ? Math.round(totalScore / count * 10) / 10 : 0,
      passRate: count > 0 ? Math.round(passCount / count * 100) : 0,
      subjectStats: Object.values(subjectStats).map(s => ({
        subject: s.subject,
        avgScore: s.count > 0 ? Math.round(s.totalScore / s.count * 10) / 10 : 0,
        count: s.count
      })),
      scoreDistribution: Object.entries(scoreRanges).map(([range, cnt]) => ({ range, count: cnt }))
    };
  } else {
    const subjectTotals = { chinese: 0, math: 0, english: 0, other: 0 };
    const studentMap    = {};
    const days          = new Set();
    const students      = new Set();

    records.forEach(r => {
      subjectTotals.chinese += r.chinese;
      subjectTotals.math    += r.math;
      subjectTotals.english += r.english;
      subjectTotals.other   += r.other;
      days.add(r.date); students.add(r.account);
      if (!studentMap[r.account]) studentMap[r.account] = { account: r.account, name: r.name, total: 0 };
      studentMap[r.account].total += r.total;
    });

    return {
      totalStudents: students.size, totalDays: days.size, totalRecords: records.length,
      subjectTotals: [
        { subject: '语文', totalMinutes: subjectTotals.chinese },
        { subject: '数学', totalMinutes: subjectTotals.math },
        { subject: '英语', totalMinutes: subjectTotals.english },
        { subject: '其他', totalMinutes: subjectTotals.other }
      ],
      studentTotals: Object.values(studentMap).map(s => ({
        account: s.account, name: s.name, totalMinutes: s.total
      })).sort((a, b) => b.totalMinutes - a.totalMinutes)
    };
  }
}

// ====================== 主入口 ======================
async function exportData(data) {
  cleanOldExports();
  console.log(`[EXPORT][${new Date().toLocaleString()}] 请求：${data.exportType || 'unknown'}`);

  const workbook = new ExcelJS.Workbook();
  workbook.creator = 'zdxt';
  workbook.created = new Date();

  console.log('[EXPORT] loading student name map...');
  const nameMap = await getStudentNameMap();
  console.log(`[EXPORT] nameMap loaded: ${Object.keys(nameMap).length} students`);

  const summary = { exportType: data.exportType };
  const debug   = { exportType: data.exportType, examSection: false, examRecords: 0, studySection: false, studyRecords: 0, nameMapSize: Object.keys(nameMap).length, sheets: [] };

  if (data.exportType === 'all' || data.exportType === 'exam') {
    console.log('[EXPORT] --- EXAM DATA SECTION ---');
    debug.examSection = true;
    const records = await getExamRecords(data, nameMap);
    debug.examRecords = records.length;
    console.log(`[EXPORT] exam records: ${records.length}`);
    await buildExamSheets(workbook, records, data);
    summary.exam = buildSummary(records, 'exam');
    console.log(`[EXPORT] exam summary:`, JSON.stringify(summary.exam));
    try { await buildExamCharts(workbook, summary.exam); }
    catch (err) { console.log('[EXPORT] exam charts failed:', err.message); }
  }

  if (data.exportType === 'all' || data.exportType === 'study') {
    console.log('[EXPORT] --- STUDY DATA SECTION ---');
    debug.studySection = true;
    const records = await getStudyRecords(data, nameMap);
    debug.studyRecords = records.length;
    console.log(`[EXPORT] study records: ${records.length}`);
    await buildStudySheets(workbook, records, data);
    summary.study = buildSummary(records, 'study');
    console.log(`[EXPORT] study summary:`, JSON.stringify(summary.study));
    try { await buildStudyCharts(workbook, summary.study); }
    catch (err) { console.log('[EXPORT] study charts failed:', err.message); }
  }

  buildSummarySheet(workbook, summary);

  const filename = `导出数据_${new Date().toISOString().slice(0, 10)}_${Date.now()}.xlsx`;
  const filepath = path.join(EXPORT_DIR, filename);
  await workbook.xlsx.writeFile(filepath);
  const fileStat = fs.statSync(filepath);
  debug.sheets = workbook.worksheets.map(s => ({ name: s.name, rowCount: s.rowCount }));
  debug.fileSize = fileStat.size;
  console.log(`[EXPORT] file saved: ${filepath} (${fileStat.size} bytes)`);
  console.log(`[EXPORT] sheets: ${debug.sheets.map(s => `${s.name}(${s.rowCount}行)`).join(', ')}`);
  console.log('[EXPORT] ====== END export ======');

  return { success: true, url: `/exports/${encodeURIComponent(filename)}`, filename, summary, debug };
}

module.exports = {
  exportHandler: async (params) => {
    try {
      const { action, ...data } = params;
      console.log(`[EXPORT] handler called, action=${action}, exportType=${data.exportType}`);
      switch (action) {
        case 'export':
          return await exportData(data);
        case 'debug':
          const nameMap = await getStudentNameMap();
          const examColl = dbPool.getCollection('examrecord');
          const recordColl = dbPool.getCollection('timerecord');
          const examCount  = await examColl.countDocuments();
          const recordCount = await recordColl.countDocuments();
          const timeRanges = await dbPool.getCollection('time').find({ type: 'timeRange' }).toArray();
          const examSample = await examColl.findOne({}, { projection: { _id: 0 } });
          return { success: true, data: {
            studentCount: Object.keys(nameMap).length,
            examRecordCount: examCount,
            timerecordCount: recordCount,
            timeRangeCount: timeRanges.length,
            timeRanges: timeRanges.map(r => ({ id: r._id, name: r.name, start: r.startDate, end: r.endDate })),
            examSample: examSample ? Object.keys(examSample) : null
          }};
        default:
          return { success: false, message: '无效的 action' };
      }
    } catch (err) {
      console.error('[EXPORT] handler error:', err);
      return { success: false, message: err.message };
    }
  }
};
