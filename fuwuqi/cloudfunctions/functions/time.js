const { dbPool } = require('../utils');

// 工具：将 Date 按本地时区格式化为 YYYY-MM-DD（避免 toISOString 的 UTC 偏移问题）
function formatDateLocal(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

// 工具：计算给定日期所在的 ISO 周字符串（如 "2026-W35"）
function getWeekStr(dateStr) {
  const d = new Date(dateStr + 'T00:00:00');
  const dayNum = d.getDay() || 7;
  d.setDate(d.getDate() + 4 - dayNum);
  const yearStart = new Date(d.getFullYear(), 0, 1);
  const weekNo = Math.ceil(((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
  return `${d.getFullYear()}-W${String(weekNo).padStart(2, '0')}`;
}

// ====================== 原有配置（默认周，向后兼容） ======================

// 1. 设置/更新 每日时长要求（默认周配置）
async function setTimeConfig(weekConfig) {
  const coll = dbPool.getCollection('time');
  // Bug修复：updateOne(filter, update) 参数顺序修正
  // 原代码把 {$set: ...} 当 filter、{upsert: true} 当 update，导致 upsert 永远不生效
  return await coll.updateOne(
    { _id: 'config' },
    { $set: { weekConfig, updatetime: new Date() } },
    { upsert: true }
  );
}

// 2. 获取每日时长要求（默认周配置）
async function getTimeConfig() {
  const coll = dbPool.getCollection('time');
  const doc = await coll.findOne({ _id: 'config' });
  return doc ? doc.weekConfig : [];
}

// 3. 核心：单条记录存储四科字段（无subject字段）
async function addStudyRecord(data) {
  const coll = dbPool.getCollection('timerecord');

  const { userid, date, subject, minutes, remark = '' } = data;

  // 任务时间范围校验：不在范围内时拒绝提交
  const timeColl = dbPool.getCollection('time');
  const ranges = await timeColl.find({ type: 'timeRange' }).toArray();
  if (ranges.length > 0) {
    let inRange = false;
    for (const r of ranges) {
      if (date >= (r.startDate || '') && date <= (r.endDate || '')) {
        inRange = true;
        break;
      }
    }
    if (!inRange) {
      return { success: false, message: '当前不在任务时间范围，学习数据无法保存' };
    }
  }

  const todayRecord = await coll.findOne({ userid, date });
  
  const newRecord = {
    chinese: 0,
    math: 0,
    english: 0,
    other: 0
  };

  if (todayRecord) {
    newRecord.chinese = todayRecord.chinese || 0;
    newRecord.math = todayRecord.math || 0;
    newRecord.english = todayRecord.english || 0;
    newRecord.other = todayRecord.other || 0;
  }

  switch (subject) {
    case 'chinese': newRecord.chinese += Number(minutes) || 0; break;
    case 'math': newRecord.math += Number(minutes) || 0; break;
    case 'english': newRecord.english += Number(minutes) || 0; break;
    case 'other': newRecord.other += Number(minutes) || 0; break;
  }

  return await coll.updateOne(
    { userid, date },
    {
      $set: {
        chinese: newRecord.chinese,
        math: newRecord.math,
        english: newRecord.english,
        other: newRecord.other,
        remark: remark || '',
        updatetime: new Date()
      },
      $setOnInsert: { createtime: new Date() }
    },
    { upsert: true }
  );
}

// 4. 获取用户当天四科完整记录
async function getUserStudyRecord(userid, date) {
  const coll = dbPool.getCollection('timerecord');
  const record = await coll.findOne({ userid, date });
  return {
    chinese: record?.chinese || 0,
    math: record?.math || 0,
    english: record?.english || 0,
    other: record?.other || 0
  };
}

// 5. 获取用户完整进度（按周）
async function getStudyProgress(userid, date) {
  const config = await getTimeConfig();
  const record = await getUserStudyRecord(userid, date);

  const progress = config.map(day => {
    const subjects = {};
    for (let key in day.subjects) {
      const require = day.subjects[key];
      const finished = record[key] || 0;
      subjects[key] = {
        require,
        finished,
        percent: require > 0 ? Math.round((finished / require) * 100) : 0
      };
    }
    return { weekday: day.weekday, subjects };
  });

  return progress;
}

// ====================== 任务时间范围 + 按周配置管理 ======================

// 7. 新增任务时间范围
async function addTaskTimeRange(rangeData) {
  const coll = dbPool.getCollection('time');
  const { name, startDate, endDate, weekConfig, weekConfigList } = rangeData;
  
  const rangeId = `range_${Date.now()}`;
  const doc = {
    _id: rangeId,
    type: 'timeRange',
    name: name || '未命名时间范围',
    startDate,
    endDate,
    weekConfig: weekConfig || [],          // 默认周配置（向后兼容）
    weekConfigList: weekConfigList || [],  // 按周配置列表（新）
    createTime: new Date(),
    updateTime: new Date()
  };
  
  await coll.insertOne(doc);
  return { rangeId, ...doc };
}

// 8. 获取所有任务时间范围（包含周配置）
async function getTaskTimeRanges() {
  const coll = dbPool.getCollection('time');
  const ranges = await coll.find({ type: 'timeRange' }).sort({ createTime: -1 }).toArray();
  return (ranges || []).map(r => ({
    ...r,
    weekConfig: r.weekConfig || [],
    weekConfigList: r.weekConfigList || []
  }));
}

// 8-bis. 获取单个时间范围的周配置详情（含默认周）
async function getRangeDetail(rangeId) {
  const coll = dbPool.getCollection('time');
  const doc = await coll.findOne({ _id: rangeId });
  if (!doc) return null;
  return {
    _id: doc._id,
    name: doc.name,
    startDate: doc.startDate,
    endDate: doc.endDate,
    weekConfig: doc.weekConfig || [],         // 默认周
    weekConfigList: doc.weekConfigList || []   // 按周列表
  };
}

// 8-ter. 获取范围内所有周的标识列表（含日期映射）
async function getRangeWeeks(rangeId) {
  const coll = dbPool.getCollection('time');
  const doc = await coll.findOne({ _id: rangeId });
  if (!doc) return [];

  const weeks = [];
  const list = doc.weekConfigList || [];

  // 根据 startDate/endDate 计算范围内所有完整周（用 T00:00:00 确保按本地时区解析）
  const startD = new Date(doc.startDate + 'T00:00:00');
  const endD = new Date(doc.endDate + 'T00:00:00');

  // 找到范围内的第一个周一
  const startDayOfWeek = startD.getDay() || 7; // 1=Mon ... 7=Sun
  const firstMonday = new Date(startD);
  firstMonday.setDate(startD.getDate() - (startDayOfWeek - 1));

  // 找到范围内的最后一个周日
  const endDayOfWeek = endD.getDay() || 7;
  const lastSunday = new Date(endD);
  lastSunday.setDate(endD.getDate() + (7 - endDayOfWeek));

  const configMap = {};
  for (const item of list) {
    if (item.startWeekStr && item.config) {
      configMap[item.startWeekStr] = item.config;
    }
  }

  // 从 firstMonday 到 lastSunday，每次推进一周
  const cursor = new Date(firstMonday);
  while (cursor <= lastSunday) {
    const monday = new Date(cursor);
    const sunday = new Date(cursor);
    sunday.setDate(cursor.getDate() + 6);

    // 裁剪到实际范围边界
    const effectiveMon = monday < startD ? startD : monday;
    const effectiveSun = sunday > endD ? endD : sunday;

    const weekStr = getWeekStr(formatDateLocal(effectiveMon));
    const isPartial = (effectiveMon > monday || effectiveSun < sunday);
    // 残缺周按实际范围内的日期展示，完整周用完整周一~周日
    const labelStart = isPartial ? effectiveMon : monday;
    const labelEnd = isPartial ? effectiveSun : sunday;
    const mStr = `${labelStart.getMonth() + 1}/${labelStart.getDate()}`;
    const sStr = `${labelEnd.getMonth() + 1}/${labelEnd.getDate()}`;

    // 只保留与实际范围有交集的周
    if (effectiveSun >= startD && effectiveMon <= endD) {
      weeks.push({
        weekStr,
        weekLabel: `第${String(weeks.length + 1)}周 (${mStr}-${sStr})`,
        mondayDate: formatDateLocal(monday),
        sundayDate: formatDateLocal(sunday),
        mondayInRange: formatDateLocal(effectiveMon),
        sundayInRange: formatDateLocal(effectiveSun),
        isPartialWeek: isPartial,
        config: configMap[weekStr] || []
      });
    }

    cursor.setDate(cursor.getDate() + 7);
  }

  return weeks;
}

// 9. 更新任务时间范围基本信息（含区间收缩/扩大清理逻辑）
async function updateTaskTimeRange(rangeId, updateData) {
  const coll = dbPool.getCollection('time');
  const doc = await coll.findOne({ _id: rangeId });
  if (!doc) return { matchedCount: 0 };

  const oldStartDate = doc.startDate || '';
  const oldEndDate = doc.endDate || '';
  const newStartDate = updateData.startDate || oldStartDate;
  const newEndDate = updateData.endDate || oldEndDate;

  // 区间向内缩小：需要删除原范围中、新范围之外的学习记录
  // 两种场景：开始时间延后（newStart > oldStart）以及/或结束时间提前（newEnd < oldEnd）
  if (newStartDate > oldStartDate || newEndDate < oldEndDate) {
    const recordColl = dbPool.getCollection('timerecord');
    const deleteConditions = [];
    if (newStartDate > oldStartDate) {
      deleteConditions.push({ date: { $gte: oldStartDate, $lt: newStartDate } });
    }
    if (newEndDate < oldEndDate) {
      deleteConditions.push({ date: { $gt: newEndDate, $lte: oldEndDate } });
    }
    const deleteCondition = deleteConditions.length === 1
      ? deleteConditions[0]
      : { $or: deleteConditions };
    const result = await recordColl.deleteMany(deleteCondition);
  }

  // 区间向外扩大：不删除任何数据，直接更新
  const updateFields = {};
  if (updateData.name !== undefined) updateFields.name = updateData.name;
  if (updateData.startDate !== undefined) updateFields.startDate = updateData.startDate;
  if (updateData.endDate !== undefined) updateFields.endDate = updateData.endDate;
  if (updateData.weekConfig !== undefined) updateFields.weekConfig = updateData.weekConfig;
  if (updateData.weekConfigList !== undefined) updateFields.weekConfigList = updateData.weekConfigList;
  updateFields.updateTime = new Date();

  return await coll.updateOne({ _id: rangeId }, { $set: updateFields });
}

// 10. 删除任务时间范围（同时删除范围内所有学生的学习记录）
async function deleteTaskTimeRange(rangeId) {
  const coll = dbPool.getCollection('time');
  const doc = await coll.findOne({ _id: rangeId });
  if (!doc) return { deletedCount: 0 };

  // 删除该时间范围内所有学生的学习进度记录
  const recordColl = dbPool.getCollection('timerecord');
  if (doc.startDate && doc.endDate) {
    const deleted = await recordColl.deleteMany({
      date: { $gte: doc.startDate, $lte: doc.endDate }
    });
  }

  return await coll.deleteOne({ _id: rangeId });
}

// 11. 保存某周的具体配置到范围
async function saveRangeWeekConfig(rangeId, weekStr, config) {
  const coll = dbPool.getCollection('time');
  const doc = await coll.findOne({ _id: rangeId });
  if (!doc) return { matchedCount: 0 };
  
  const list = doc.weekConfigList || [];
  const idx = list.findIndex(w => w.startWeekStr === weekStr);
  
  if (idx >= 0) {
    list[idx].config = config;
  } else {
    list.push({ startWeekStr: weekStr, config });
  }
  
  return await coll.updateOne(
    { _id: rangeId },
    { $set: { weekConfigList: list, updateTime: new Date() } }
  );
}

// 12. 将编辑器中的配置复制到范围内所有周（支持精细控制）
// options: { sourceConfig, copyMode: 'week'|'day', sourceWeekday: 1-7, subjectMode: 'all'|'chinese'|'math'|'english'|'other' }
async function copyWeekConfigToAll(rangeId, sourceWeekStr, options = {}) {
  const coll = dbPool.getCollection('time');
  const doc = await coll.findOne({ _id: rangeId });
  if (!doc) return { matchedCount: 0 };

  const list = doc.weekConfigList || [];

  // 使用前端传入的编辑器配置（而非数据库中已保存的），避免错乱
  const sourceConfig = options.sourceConfig || [];
  const rangeStart = doc.startDate;
  const rangeEnd = doc.endDate;

  const copyMode = options.copyMode || 'week';
  const sourceWeekday = options.sourceWeekday;
  const subjectMode = options.subjectMode || 'all';

  // 构建源配置的 weekday -> subjects 映射
  const sourceMap = {};
  for (const item of sourceConfig) {
    if (item.weekday) sourceMap[item.weekday] = item.subjects;
  }

  // 生成范围内所有周
  const startD = new Date(rangeStart + 'T00:00:00');
  const endD = new Date(rangeEnd + 'T00:00:00');
  const startDayOfWeek = startD.getDay() || 7;
  const firstMonday = new Date(startD);
  firstMonday.setDate(startD.getDate() - (startDayOfWeek - 1));
  const endDayOfWeek = endD.getDay() || 7;
  const lastSunday = new Date(endD);
  lastSunday.setDate(endD.getDate() + (7 - endDayOfWeek));

  // 构建已有配置的映射（用于隔离学科时保留其他科目）
  const configMap = {};
  for (const item of list) {
    if (item.startWeekStr) configMap[item.startWeekStr] = item;
  }

  const newList = [];
  const cursor = new Date(firstMonday);
  while (cursor <= lastSunday) {
    const monday = new Date(cursor);
    const sunday = new Date(cursor);
    sunday.setDate(cursor.getDate() + 6);

    const effectiveMon = monday < startD ? startD : monday;
    const effectiveSun = sunday > endD ? endD : sunday;

    if (effectiveSun >= startD && effectiveMon <= endD) {
      const weekStr = getWeekStr(formatDateLocal(effectiveMon));

      if (weekStr === sourceWeekStr) {
        // 源周：用前端传入的编辑器配置覆盖
        newList.push({ startWeekStr: weekStr, config: JSON.parse(JSON.stringify(sourceConfig)) });
      } else {
        const mondayStr = formatDateLocal(monday);
        // 获取目标周已有配置
        let existingMap = {};
        if (configMap[weekStr] && configMap[weekStr].config) {
          for (const item of configMap[weekStr].config) {
            if (item.weekday) existingMap[item.weekday] = item.subjects || {};
          }
        }

        const newConfig = [];
        for (let wd = 1; wd <= 7; wd++) {
          const dayDate = new Date(mondayStr + 'T00:00:00');
          dayDate.setDate(dayDate.getDate() + (wd - 1));
          const dayStr = formatDateLocal(dayDate);

          if (dayStr >= rangeStart && dayStr <= rangeEnd) {
            if (copyMode === 'day') {
              // 天对应天：只修改指定星期
              if (wd === sourceWeekday) {
                if (subjectMode === 'all') {
                  // 合并学科：覆盖该天全部科目
                  newConfig.push({
                    weekday: wd,
                    subjects: sourceMap[wd]
                      ? JSON.parse(JSON.stringify(sourceMap[wd]))
                      : { chinese: 0, math: 0, english: 0, other: 0 }
                  });
                } else {
                  // 隔离学科：只覆盖指定科目，保留其他
                  const merged = JSON.parse(JSON.stringify(existingMap[wd] || { chinese: 0, math: 0, english: 0, other: 0 }));
                  if (sourceMap[wd]) {
                    merged[subjectMode] = sourceMap[wd][subjectMode] || 0;
                  }
                  newConfig.push({ weekday: wd, subjects: merged });
                }
              } else {
                // 非目标星期：保留已有配置
                newConfig.push({
                  weekday: wd,
                  subjects: existingMap[wd]
                    ? JSON.parse(JSON.stringify(existingMap[wd]))
                    : { chinese: 0, math: 0, english: 0, other: 0 }
                });
              }
            } else {
              // 周对应周
              if (subjectMode === 'all') {
                newConfig.push({
                  weekday: wd,
                  subjects: sourceMap[wd]
                    ? JSON.parse(JSON.stringify(sourceMap[wd]))
                    : { chinese: 0, math: 0, english: 0, other: 0 }
                });
              } else {
                // 隔离学科：只覆盖指定科目
                const merged = JSON.parse(JSON.stringify(existingMap[wd] || { chinese: 0, math: 0, english: 0, other: 0 }));
                if (sourceMap[wd]) {
                  merged[subjectMode] = sourceMap[wd][subjectMode] || 0;
                }
                newConfig.push({ weekday: wd, subjects: merged });
              }
            }
          } else {
            newConfig.push({
              weekday: wd,
              subjects: { chinese: 0, math: 0, english: 0, other: 0 }
            });
          }
        }
        newList.push({ startWeekStr: weekStr, config: newConfig });
      }
    }

    cursor.setDate(cursor.getDate() + 7);
  }

  return await coll.updateOne(
    { _id: rangeId },
    { $set: { weekConfigList: newList, updateTime: new Date() } }
  );
}

// 13. 高级应用：直接设置指定值到范围内所有周
// options: { subjectMode: 'all'|'isolate', values: {all|chinese,math,english,other}, weekdays: [1-7], applyMode: 'weekly'|'daily' }
async function applyConfigToAll(rangeId, options = {}) {
  const coll = dbPool.getCollection('time');
  const doc = await coll.findOne({ _id: rangeId });
  if (!doc) return { matchedCount: 0 };

  const list = doc.weekConfigList || [];
  const rangeStart = doc.startDate;
  const rangeEnd = doc.endDate;

  const subjectMode = options.subjectMode || 'all';
  const applyMode = options.applyMode || 'weekly';
  const weekdays = options.weekdays || [];
  const weekdaySet = new Set(weekdays);

  // 子范围（可选）：custom 时仅作用于 [subStart, subEnd]，其余日期保持不变
  const subStart = options.subStart || null;
  const subEnd = options.subEnd || null;
  const subRange = subStart && subEnd ? { start: subStart, end: subEnd } : null;

  // 构建目标 subjects：null/undefined=保留原值；0=显式设为 0
  const vAll = options.values?.all;
  const targetSubjects = {
    chinese: subjectMode === 'all' ? vAll : options.values?.chinese,
    math: subjectMode === 'all' ? vAll : options.values?.math,
    english: subjectMode === 'all' ? vAll : options.values?.english,
    other: subjectMode === 'all' ? vAll : options.values?.other,
  };

  // 合并已有 subjects，仅覆盖被明确设置（非 null/undefined）的字段
  function mergeSubjects(base, target) {
    const out = {
      chinese: base?.chinese ?? 0,
      math: base?.math ?? 0,
      english: base?.english ?? 0,
      other: base?.other ?? 0,
    };
    for (const k of ['chinese', 'math', 'english', 'other']) {
      if (target[k] !== null && target[k] !== undefined) {
        out[k] = Number(target[k]);
      }
    }
    return out;
  }

  // 生成范围内所有周
  const startD = new Date(rangeStart + 'T00:00:00');
  const endD = new Date(rangeEnd + 'T00:00:00');
  const startDayOfWeek = startD.getDay() || 7;
  const firstMonday = new Date(startD);
  firstMonday.setDate(startD.getDate() - (startDayOfWeek - 1));
  const endDayOfWeek = endD.getDay() || 7;
  const lastSunday = new Date(endD);
  lastSunday.setDate(endD.getDate() + (7 - endDayOfWeek));

  // 构建已有配置的映射
  const configMap = {};
  for (const item of list) {
    if (item.startWeekStr) configMap[item.startWeekStr] = item;
  }

  const newList = [];
  const cursor = new Date(firstMonday);
  while (cursor <= lastSunday) {
    const monday = new Date(cursor);
    const sunday = new Date(cursor);
    sunday.setDate(cursor.getDate() + 6);

    const effectiveMon = monday < startD ? startD : monday;
    const effectiveSun = sunday > endD ? endD : sunday;

    if (effectiveSun >= startD && effectiveMon <= endD) {
      const weekStr = getWeekStr(formatDateLocal(effectiveMon));
      const mondayStr = formatDateLocal(monday);

      // 获取已有配置
      let existingMap = {};
      if (configMap[weekStr] && configMap[weekStr].config) {
        for (const item of configMap[weekStr].config) {
          if (item.weekday) existingMap[item.weekday] = item.subjects || {};
        }
      }

      const newConfig = [];
      for (let wd = 1; wd <= 7; wd++) {
        const dayDate = new Date(mondayStr + 'T00:00:00');
        dayDate.setDate(dayDate.getDate() + (wd - 1));
        const dayStr = formatDateLocal(dayDate);

        const inRange = dayStr >= rangeStart && dayStr <= rangeEnd;
        // 子范围内：按应用方式决定；子范围外：保留已有配置
        const inSub = !subRange || (dayStr >= subRange.start && dayStr <= subRange.end);

        if (inRange) {
          if (inSub) {
            // 判断是否应该应用
            const shouldApply = applyMode === 'daily' || weekdaySet.has(wd);
            if (shouldApply) {
              // 应用方式命中该星期：仅覆盖被设置的学科，未设置学科保留原值
              newConfig.push({
                weekday: wd,
                subjects: mergeSubjects(existingMap[wd], targetSubjects)
              });
            } else {
              // 应用方式未命中该星期：完全不受影响，保留原值
              newConfig.push({
                weekday: wd,
                subjects: existingMap[wd]
                  ? JSON.parse(JSON.stringify(existingMap[wd]))
                  : { chinese: 0, math: 0, english: 0, other: 0 }
              });
            }
          } else {
            // 子范围外，保留已有配置
            newConfig.push({
              weekday: wd,
              subjects: existingMap[wd]
                ? JSON.parse(JSON.stringify(existingMap[wd]))
                : { chinese: 0, math: 0, english: 0, other: 0 }
            });
          }
        } else {
          newConfig.push({
            weekday: wd,
            subjects: existingMap[wd]
              ? JSON.parse(JSON.stringify(existingMap[wd]))
              : { chinese: 0, math: 0, english: 0, other: 0 }
          });
        }
      }
      newList.push({ startWeekStr: weekStr, config: newConfig });
    }

    cursor.setDate(cursor.getDate() + 7);
  }

  return await coll.updateOne(
    { _id: rangeId },
    { $set: { weekConfigList: newList, updateTime: new Date() } }
  );
}

// ISO 周字符串转周一日期字符串 (YYYY-MM-DD)
function _isoWeekToMondayStr(weekStr) {
  try {
    const m = weekStr.match(/^(\d{4})-W(\d{2})$/);
    if (!m) return null;
    const year = parseInt(m[1]);
    const week = parseInt(m[2]);
    const jan1 = new Date(year, 0, 1);
    const dayOfWeek = jan1.getDay() || 7;
    const mondayOfW1 = new Date(year, 0, 1 + (8 - dayOfWeek) % 7);
    const monday = new Date(mondayOfW1);
    monday.setDate(mondayOfW1.getDate() + (week - 1) * 7);
    const y = monday.getFullYear();
    const mo = String(monday.getMonth() + 1).padStart(2, '0');
    const d = String(monday.getDate()).padStart(2, '0');
    return `${y}-${mo}-${d}`;
  } catch (_) {
    return null;
  }
}

// 14. 获取范围内某周的配置
async function getRangeWeekConfig(rangeId, weekStr) {
  const coll = dbPool.getCollection('time');
  const doc = await coll.findOne({ _id: rangeId });
  if (!doc) return null;
  
  const list = doc.weekConfigList || [];
  const item = list.find(w => w.startWeekStr === weekStr);
  if (item) return item.config;
  
  // 回退到默认周配置
  return doc.weekConfig || [];
}

// ====================== 进度查询（增强版） ======================

// 15. 管理员搜索用户进度（支持时间范围 + 指定周查询）
// options: { startDate, endDate, rangeId, weekOffset, weekStr }
async function searchUserProgress(searchKey, parentAccount, options = {}) {
  const timeColl = dbPool.getCollection('time');
  const recordColl = dbPool.getCollection('timerecord');

  const { startDate, endDate, rangeId, weekOffset, weekStr, studentAccount } = options;

  // 1. 获取配置：优先范围+周，再默认范围，最后全局默认
  let globalWeekTarget = Array(7).fill().map(() => ({ chinese: 0, math: 0, english: 0, other: 0 }));
  let configFound = false;

  if (rangeId) {
    const rangeDoc = await timeColl.findOne({ _id: rangeId });
    if (rangeDoc) {
      // 优先：范围内指定周配置
      if (weekStr) {
        const weekCfgList = rangeDoc.weekConfigList || [];
        const weekItem = weekCfgList.find(w => w.startWeekStr === weekStr);
        if (weekItem && weekItem.config && weekItem.config.length > 0) {
          weekItem.config.forEach(day => {
            const idx = (day.weekday || 1) - 1;
            if (idx >= 0 && idx < 7) {
              globalWeekTarget[idx] = day.subjects || { chinese: 0, math: 0, english: 0, other: 0 };
            }
          });
          configFound = true;
        }
      }
      // 其次：范围默认周配置（仅当周配置未找到时才回退）
      if (!configFound) {
        const defaultCfg = rangeDoc.weekConfig || [];
        if (defaultCfg.length > 0) {
          defaultCfg.forEach(day => {
            const idx = (day.weekday || 1) - 1;
            if (idx >= 0 && idx < 7) {
              globalWeekTarget[idx] = day.subjects || { chinese: 0, math: 0, english: 0, other: 0 };
            }
          });
          configFound = true;
        }
      }
    }
  }

  // 最后：全局默认配置（仅当范围配置都未找到时才回退）
  if (!configFound) {
    const configDoc = await timeColl.findOne({ _id: 'config' });
    (configDoc?.weekConfig || []).forEach(day => {
      const idx = (day.weekday || 1) - 1;
      if (idx >= 0 && idx < 7) {
        globalWeekTarget[idx] = day.subjects || { chinese: 0, math: 0, english: 0, other: 0 };
      }
    });
  }

  // 2. 构建搜索条件
  const searchCondition = {};
  let studentAccounts = [];
  
  if (parentAccount && parentAccount.trim() !== '') {
    try {
      const usersColl = dbPool.getCollection('user');
      const parent = await usersColl.findOne({ account: parentAccount, type: 3 });
      studentAccounts = parent?.boundStudents || [];
      if (studentAccounts.length === 0) return [];
      // 🚀 性能优化：家长端学习界面默认仅加载当前选中学生的学习记录，
      // 指定了 studentAccount 时只查该学生，避免全量拉取所有学生数据
      if (studentAccount && studentAccount.trim() !== '') {
        if (studentAccounts.includes(studentAccount)) {
          studentAccounts = [studentAccount];
        } else {
          return [];
        }
      }
      searchCondition.userid = { $in: studentAccounts };
    } catch (err) {
      console.error('获取绑定学生失败:', err);
      return [];
    }
  } else if (searchKey && searchKey.trim() !== '') {
    searchCondition.$or = [
      { userid: { $regex: searchKey, $options: 'i' } },
      { remark: { $regex: searchKey, $options: 'i' } }
    ];
  }

  // 3. 确定查询日期范围
  let mondayStr, sundayStr;
  let weekLabel;

  // 优先：有指定周时，用该周的日期（忽略 startDate/endDate）
  if (weekStr && rangeId) {
    const rangeDoc = await timeColl.findOne({ _id: rangeId });
    console.log(`[searchProgress] rangeId=${rangeId}, weekStr=${weekStr}`);
    if (rangeDoc) {
      const rangeStart = new Date(rangeDoc.startDate + 'T00:00:00');
      const rangeEnd = new Date(rangeDoc.endDate + 'T00:00:00');
      // 找到范围内匹配该 ISO 周的周一
      let foundMonday = null;
      for (let d = new Date(rangeStart); d <= rangeEnd; d.setDate(d.getDate() + 1)) {
        const ws = getWeekStr(formatDateLocal(d));
        if (ws === weekStr) {
          foundMonday = new Date(d);
          break;
        }
      }
      if (foundMonday) {
        const sunday = new Date(foundMonday);
        sunday.setDate(foundMonday.getDate() + 6);
        mondayStr = formatDateLocal(foundMonday);
        sundayStr = formatDateLocal(sunday);
        weekLabel = weekStr;
        console.log(`[searchProgress] found week: monday=${mondayStr}, sunday=${sundayStr}`);
      } else {
        console.log(`[searchProgress] WARNING: weekStr=${weekStr} NOT FOUND in range [${rangeDoc.startDate}, ${rangeDoc.endDate}]`);
      }
    } else {
      console.log(`[searchProgress] WARNING: rangeId=${rangeId} NOT FOUND in time collection`);
    }
  }

  // 其次：有范围日期但无周时，用范围的完整日期
  if (!mondayStr && startDate && endDate) {
    mondayStr = startDate;
    sundayStr = endDate;
    weekLabel = `${startDate} 至 ${endDate}`;
  } else {
    // 回退到 weekOffset
    if (!mondayStr) {
      const now = new Date();
      const day = now.getDay();
      const diff = day === 0 ? -6 : 1 - day;
      const monday = new Date(now);
      monday.setDate(now.getDate() + diff + (weekOffset || 0) * 7);
      const sunday = new Date(monday);
      sunday.setDate(monday.getDate() + 6);
      mondayStr = formatDateLocal(monday);
      sundayStr = formatDateLocal(sunday);
      weekLabel = (weekOffset || 0) === 0 ? '本周' : `第${weekOffset}周`;
    }
  }

  searchCondition.date = { $gte: mondayStr, $lte: sundayStr };
  console.log(`[searchProgress] query: searchCondition=${JSON.stringify(searchCondition)}, dateRange=[${mondayStr}, ${sundayStr}]`);

  // 4. 查询学习记录
  const records = await recordColl.find(searchCondition).toArray();
  console.log(`[searchProgress] records found: ${records.length}, studentAccounts=${JSON.stringify(studentAccounts)}`);

  // 5. 无数据时返回空骨架
  if (records.length === 0) {
    if (parentAccount && parentAccount.trim() !== '') {
      if (studentAccounts.length > 0) {
        const usersColl = dbPool.getCollection('user');
        const studentsInfo = await usersColl.find({ account: { $in: studentAccounts } }).toArray();
        const infoMap = {};
        studentsInfo.forEach(s => { infoMap[s.account] = s; });
        return studentAccounts.map(acc => ({
          name: acc || "未知",
          phone: infoMap[acc]?.remark || "无",
          weekData: Array(7).fill().map((_, idx) => ({
            yw: 0, ywTarget: globalWeekTarget[idx].chinese || 0,
            sx: 0, sxTarget: globalWeekTarget[idx].math || 0,
            en: 0, enTarget: globalWeekTarget[idx].english || 0,
            ot: 0, otTarget: globalWeekTarget[idx].other || 0
          }))
        }));
      }
    }
    return [];
  }

  // 6. 查询全部绑定学生的备注信息（含无记录学生，供空骨架显示备注）
  const infoAccounts = parentAccount && parentAccount.trim() !== ''
    ? (studentAccounts.length > 0 ? studentAccounts : [...new Set(records.map(r => r.userid))])
    : [...new Set(records.map(r => r.userid))];
  const usersColl = dbPool.getCollection('user');
  const studentsInfo = await usersColl.find({ account: { $in: infoAccounts }, type: 2 }).toArray();
  const infoMap = {};
  studentsInfo.forEach(s => { infoMap[s.account] = s; });

  // 7. 按 userid 分组（以全部绑定学生为基准，无记录的学生也生成空骨架，保证前端固定 7 天列表）
  const userMap = {};
  studentAccounts.forEach(acc => {
    if (acc) userMap[acc] = { name: acc, phone: infoMap[acc]?.remark || '无', records: [] };
  });
  records.forEach(record => {
    const userId = record.userid;
    if (!userMap[userId]) {
      userMap[userId] = { name: userId, phone: infoMap[userId]?.remark || '无', records: [] };
    }
    userMap[userId].records.push(record);
  });

  // 7. 生成每周数据
  const progressList = [];
  Object.keys(userMap).forEach(userId => {
    const userData = userMap[userId];
    const userWeekData = Array(7).fill().map((_, idx) => ({
      yw: 0, ywTarget: Number(globalWeekTarget[idx].chinese) || 0,
      sx: 0, sxTarget: Number(globalWeekTarget[idx].math) || 0,
      en: 0, enTarget: Number(globalWeekTarget[idx].english) || 0,
      ot: 0, otTarget: Number(globalWeekTarget[idx].other) || 0
    }));

    userData.records.forEach(record => {
      try {
        const recordDate = new Date(record.date);
        const recordWeekday = recordDate.getDay() === 0 ? 7 : recordDate.getDay();
        const weekIdx = recordWeekday - 1;
        if (weekIdx >= 0 && weekIdx < 7) {
          userWeekData[weekIdx].yw += Number(record.chinese) || 0;
          userWeekData[weekIdx].sx += Number(record.math) || 0;
          userWeekData[weekIdx].en += Number(record.english) || 0;
          userWeekData[weekIdx].ot += Number(record.other) || 0;
        }
      } catch (e) { /* ignore */ }
    });

    progressList.push({ name: userData.name, phone: userData.phone, weekData: userWeekData });
  });

  console.log(`[searchProgress] result: ${progressList.length} entries, totalWeekDataNonZero=${progressList.reduce((sum, u) => sum + u.weekData.filter((d, i) => d.yw > 0 || d.sx > 0 || d.en > 0 || d.ot > 0).length, 0)}`);
  return progressList;
}

// ====================== 数据导出 ======================
async function exportStudyData(data) {
  const recordColl = dbPool.getCollection('timerecord');
  const condition = {};

  if (data.startDate && data.endDate) {
    condition.date = { $gte: data.startDate, $lte: data.endDate };
  }

  if (data.accounts && data.accounts.length > 0) {
    condition.userid = { $in: data.accounts };
  }

  const records = await recordColl.find(condition).sort({ date: 1, userid: 1 }).toArray();

  const usersColl = dbPool.getCollection('user');
  const accounts = [...new Set(records.map(r => r.userid))];
  const students = await usersColl.find({ account: { $in: accounts } }).project({ account: 1, remark: 1 }).toArray();
  const nameMap = {};
  students.forEach(s => { nameMap[s.account] = s.remark || s.account; });

  return records.map(r => ({
    account: r.userid,
    name: nameMap[r.userid] || r.userid,
    date: r.date,
    chinese: Number(r.chinese) || 0,
    math: Number(r.math) || 0,
    english: Number(r.english) || 0,
    other: Number(r.other) || 0,
    total: (Number(r.chinese) || 0) + (Number(r.math) || 0) + (Number(r.english) || 0) + (Number(r.other) || 0)
  }));
}

// ====================== 导出主处理函数 ======================
module.exports = {
  timeHandler: async (params) => {
    try {
      const { action, ...data } = params;
      let result;

      switch (action) {
        case 'setConfig':
          result = await setTimeConfig(data.weekConfig);
          return { success: true, data: result };
        case 'getConfig':
          result = await getTimeConfig();
          return { success: true, data: result };
        case 'addRecord':
          result = await addStudyRecord(data);
          // 🔥 修复：addStudyRecord 在时间范围外返回 {success:false,...}，此处透传给前端；
          //    旧代码无条件 return {success:true} 导致前端始终认为入库成功，计时器持续累计但不写入 DB
          return result.success === true
            ? { success: true, message: '记录添加成功', data: result }
            : { success: false, message: result.message || '记录添加失败' };
        case 'getProgress':
          result = await getStudyProgress(data.userid, data.date);
          return { success: true, data: result };
        case 'getUserStudyRecord':
          result = await getUserStudyRecord(data.userid, data.date);
          return { success: true, data: result };
        case 'searchProgress':
          result = await searchUserProgress(
            data.searchKey || '',
            data.parentAccount || '',
            {
              startDate: data.startDate,
              endDate: data.endDate,
              rangeId: data.rangeId,
              weekStr: data.weekStr,
              weekOffset: data.weekOffset,
              studentAccount: data.studentAccount
            }
          );
          return { success: true, data: result };
        // ===== 任务时间范围管理 =====
        case 'addTimeRange':
          result = await addTaskTimeRange(data);
          return { success: true, data: result };
        case 'getTimeRanges':
          result = await getTaskTimeRanges();
          return { success: true, data: result };
        case 'updateTimeRange':
          result = await updateTaskTimeRange(data.rangeId, data);
          return { success: true, data: result };
        case 'deleteTimeRange':
          result = await deleteTaskTimeRange(data.rangeId);
          return { success: true, data: result };
        // ===== 按周配置管理 =====
        case 'getRangeDetail':
          result = await getRangeDetail(data.rangeId);
          return { success: true, data: result };
        case 'getRangeWeeks':
          result = await getRangeWeeks(data.rangeId);
          return { success: true, data: result };
        case 'getRangeWeekConfig':
          result = await getRangeWeekConfig(data.rangeId, data.weekStr);
          return { success: true, data: result || [] };
        case 'saveRangeWeekConfig':
          result = await saveRangeWeekConfig(data.rangeId, data.weekStr, data.config);
          return { success: true, data: result };
        case 'copyWeekConfigToAll':
          result = await copyWeekConfigToAll(data.rangeId, data.sourceWeekStr, {
            sourceConfig: data.sourceConfig,
            copyMode: data.copyMode,
            sourceWeekday: data.sourceWeekday,
            subjectMode: data.subjectMode
          });
          return { success: true, data: result };
        case 'applyConfigToAll':
          result = await applyConfigToAll(data.rangeId, {
            subjectMode: data.subjectMode,
            values: data.values,
            weekdays: data.weekdays,
            applyMode: data.applyMode,
            subStart: data.subStart,
            subEnd: data.subEnd
          });
          return { success: true, data: result };
        case 'exportStudyData':
          result = await exportStudyData(data);
          return { success: true, data: result };
        default:
          return { success: false, message: '无效的 action' };
      }
    } catch (err) {
      console.error('timeHandler 错误:', err);
      return { success: false, message: err.message };
    }
  }
};
