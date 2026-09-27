/**
 * 慢查询监控工具
 * 
 * 功能：启用MongoDB慢查询日志，帮助识别需要优化的查询
 * 使用：node enable_slow_query_log.js
 */

const { MongoClient } = require('mongodb');

const MONGO_URL = 'mongodb://localhost:27017';
const DB_NAME = 'zdxt';

/**
 * 启用慢查询日志
 */
async function enableSlowQueryLog() {
  let client;
  
  try {
    console.log('🔍 启用MongoDB慢查询日志...\n');
    
    client = new MongoClient(MONGO_URL);
    await client.connect();
    
    const adminDb = client.db('admin');
    
    // 设置慢查询阈值为100ms
    const result = await adminDb.command({
      setParameter: 1,
      slowOpThresholdMs: 100
    });
    
    console.log('✅ 慢查询阈值已设置为 100ms');
    console.log('   所有执行时间超过100ms的查询都会被记录\n');
    
    // 查看当前配置
    const config = await adminDb.command({ getParameter: 1, slowOpThresholdMs: 1 });
    console.log('📊 当前配置:');
    console.log(`   慢查询阈值: ${config.slowOpThresholdMs}ms\n`);
    
    console.log('💡 提示:');
    console.log('  1. 慢查询日志位置: MongoDB安装目录/logs/mongod.log');
    console.log('  2. 可以通过以下命令查看慢查询:');
    console.log('     grep "slow query" /var/log/mongodb/mongod.log');
    console.log('  3. 建议定期分析慢查询日志，优化相关索引\n');
    
  } catch (err) {
    console.error('❌ 启用失败:', err.message);
  } finally {
    if (client) {
      await client.close();
    }
  }
}

enableSlowQueryLog();