/**
 * 数据库索引优化脚本
 * 
 * 功能：为所有集合添加合适的索引，提升查询性能
 * 使用：node optimize_indexes.js
 * 
 * 注意：此脚本只会创建不存在的索引，不会影响现有数据
 */

const { MongoClient } = require('mongodb');

// 数据库配置
const MONGO_URL = 'mongodb://localhost:27017';
const DB_NAME = 'zdxt';

// 索引配置定义
const INDEX_CONFIGS = {
  // exam 集合（试卷）
  exam: [
    {
      keys: { account: 1, createTime: -1 },
      name: 'idx_exam_account_createTime',
      options: { background: true }
    },
    {
      keys: { subject: 1, status: 1 },
      name: 'idx_exam_subject_status',
      options: { background: true }
    },
    {
      keys: { createTime: -1 },
      name: 'idx_exam_createTime_desc',
      options: { background: true }
    },
    {
      keys: { examId: 1 },
      name: 'idx_exam_examId',
      options: { background: true, unique: false }
    }
  ],

  // examrecord 集合（答题记录）
  examrecord: [
    {
      keys: { account: 1, examId: 1 },
      name: 'idx_examrecord_account_exam',
      options: { background: true, unique: true }
    },
    {
      keys: { account: 1, submitTime: -1 },
      name: 'idx_examrecord_account_submitTime',
      options: { background: true }
    },
    {
      keys: { examId: 1, totalScore: -1 },
      name: 'idx_examrecord_exam_totalScore',
      options: { background: true }
    },
    {
      keys: { submitTime: -1 },
      name: 'idx_examrecord_submitTime_desc',
      options: { background: true }
    }
  ],

  // user 集合（用户）
  user: [
    {
      keys: { account: 1 },
      name: 'idx_user_account',
      options: { background: true, unique: true }
    },
    {
      keys: { type: 1, status: 1 },
      name: 'idx_user_type_status',
      options: { background: true }
    },
    {
      keys: { appealStatus: 1 },
      name: 'idx_user_appealStatus',
      options: { background: true }
    },
    {
      keys: { parentAccount: 1 },
      name: 'idx_user_parentAccount',
      options: { background: true }
    }
  ],

  // video 集合（视频）
  video: [
    {
      keys: { fileName: 1 },
      name: 'idx_video_filename',
      options: { background: true, unique: true }
    },
    {
      keys: { subject: 1, createTime: -1 },
      name: 'idx_video_subject_createTime',
      options: { background: true }
    },
    {
      keys: { createTime: -1 },
      name: 'idx_video_createTime_desc',
      options: { background: true }
    }
  ],

  // text 集合（通知/反馈）
  text: [
    {
      keys: { type: 1, createTime: -1 },
      name: 'idx_text_type_createTime',
      options: { background: true }
    },
    {
      keys: { status: 1, createTime: -1 },
      name: 'idx_text_status_createTime',
      options: { background: true }
    },
    {
      keys: { createTime: -1 },
      name: 'idx_text_createTime_desc',
      options: { background: true }
    }
  ],

  // time 集合（学习时长）
  time: [
    {
      keys: { studentId: 1, date: 1 },
      name: 'idx_time_student_date',
      options: { background: true, unique: true }
    },
    {
      keys: { studentId: 1, totalTime: -1 },
      name: 'idx_time_student_totalTime',
      options: { background: true }
    },
    {
      keys: { date: -1 },
      name: 'idx_time_date_desc',
      options: { background: true }
    }
  ]
};

/**
 * 为单个集合创建索引
 */
async function createIndexesForCollection(db, collectionName, indexes) {
  console.log(`\n📊 处理集合: ${collectionName}`);
  
  const collection = db.collection(collectionName);
  
  for (const indexConfig of indexes) {
    try {
      // 检查索引是否已存在
      const existingIndexes = await collection.indexes();
      const indexExists = existingIndexes.some(idx => idx.name === indexConfig.name);
      
      if (indexExists) {
        console.log(`  ✅ 索引已存在: ${indexConfig.name}`);
        continue;
      }
      
      // 创建索引
      await collection.createIndex(indexConfig.keys, {
        ...indexConfig.options,
        name: indexConfig.name
      });
      
      console.log(`  ✨ 创建索引成功: ${indexConfig.name}`);
      console.log(`     键: ${JSON.stringify(indexConfig.keys)}`);
    } catch (err) {
      console.error(`  ❌ 创建索引失败: ${indexConfig.name}`, err.message);
    }
  }
}

/**
 * 获取集合统计信息
 */
async function getCollectionStats(db, collectionName) {
  const collection = db.collection(collectionName);
  const count = await collection.countDocuments();
  const indexes = await collection.indexes();
  
  return {
    name: collectionName,
    documentCount: count,
    indexCount: indexes.length,
    indexes: indexes.map(idx => ({
      name: idx.name,
      keys: idx.key
    }))
  };
}

/**
 * 主函数
 */
async function main() {
  let client;
  
  try {
    console.log('🚀 开始数据库索引优化...\n');
    console.log(`数据库: ${DB_NAME}`);
    console.log(`地址: ${MONGO_URL}\n`);
    
    // 连接数据库
    client = new MongoClient(MONGO_URL);
    await client.connect();
    console.log('✅ 数据库连接成功\n');
    
    const db = client.db(DB_NAME);
    
    // 为每个集合创建索引
    for (const [collectionName, indexes] of Object.entries(INDEX_CONFIGS)) {
      await createIndexesForCollection(db, collectionName, indexes);
    }
    
    // 输出统计信息
    console.log('\n\n📈 数据库统计信息:');
    console.log('=' .repeat(60));
    
    for (const collectionName of Object.keys(INDEX_CONFIGS)) {
      try {
        const stats = await getCollectionStats(db, collectionName);
        console.log(`\n集合: ${stats.name}`);
        console.log(`  文档数: ${stats.documentCount}`);
        console.log(`  索引数: ${stats.indexCount}`);
        console.log(`  索引列表:`);
        stats.indexes.forEach(idx => {
          console.log(`    - ${idx.name}: ${JSON.stringify(idx.keys)}`);
        });
      } catch (err) {
        console.log(`\n集合: ${collectionName} (获取统计信息失败)`);
      }
    }
    
    console.log('\n' + '='.repeat(60));
    console.log('\n✅ 索引优化完成！\n');
    console.log('💡 提示:');
    console.log('  1. 索引创建是后台操作，不会影响现有业务');
    console.log('  2. 新索引会在下次查询时自动生效');
    console.log('  3. 可以通过 MongoDB Compass 查看索引使用情况');
    console.log('  4. 建议定期监控慢查询日志，进一步优化索引\n');
    
  } catch (err) {
    console.error('\n❌ 索引优化失败:', err.message);
    console.error(err.stack);
    process.exit(1);
  } finally {
    if (client) {
      await client.close();
      console.log('🔒 数据库连接已关闭\n');
    }
  }
}

// 执行
main();