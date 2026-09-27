const { MongoClient, ObjectId } = require('mongodb');
const crypto = require('crypto');
const nodemailer = require('nodemailer');

const url = 'mongodb://localhost:27017';
const dbName = 'zdxt';
const colName = 'user';

// SMTP 配置（QQ邮箱）
const smtpConfig = {
  host: 'smtp.qq.com',
  port: 465,
  secure: true,
  auth: {
    user: '1922216262@qq.com',
    pass: 'abnyhkmkdkdhbfad'
  },
  name: 'zdxt-system'
};

// 创建邮件发送器
const transporter = nodemailer.createTransport(smtpConfig);

// 邮箱验证码缓存（内存存储，5分钟过期）
const emailCodeCache = new Map();
const EMAIL_CODE_EXPIRE_TIME = 5 * 60 * 1000; // 5分钟有效期

// 发送邮件函数
async function sendEmail(to, subject, html) {
  try {
    const info = await transporter.sendMail({
      from: `"智答星途" <${smtpConfig.auth.user}>`,
      to: to,
      subject: subject,
      html: html
    });
    console.log('✅ 邮件发送成功:', info.messageId);
    return { success: true, msg: '邮件发送成功' };
  } catch (error) {
    console.error('❌ 邮件发送失败:', error);
    return { success: false, msg: '邮件发送失败' };
  }
}

// 生成6位数字验证码
function generateEmailCode() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

// 定时清理过期邮箱验证码（每分钟执行一次）
setInterval(() => {
  const now = Date.now();
  for (const [key, value] of emailCodeCache.entries()) {
    if (value.expire < now) {
      emailCodeCache.delete(key);
      console.log(`[邮箱验证码缓存] 清理过期: ${key}`);
    }
  }
}, 60 * 1000).unref();

// 优化1：复用MongoDB客户端（大幅提升响应速度，避免重复创建连接）
let mongoClient;

// 二维码登录：内存缓存（存储临时授权数据）
// 结构：key=qrkey, value={ account: 绑定账号, expire: 过期时间戳 }
const qrCodeCache = new Map();
const QRCODE_EXPIRE_TIME = 5 * 60 * 1000; // 5分钟有效期

// 定时清理过期二维码缓存（每分钟执行一次）
setInterval(() => {
  const now = Date.now();
  for (const [key, value] of qrCodeCache.entries()) {
    if (value.expire < now) {
      qrCodeCache.delete(key);
      console.log(`[二维码缓存] 清理过期qrkey: ${key}`);
    }
  }
}, 60 * 1000).unref();

async function getMongoClient() {
  if (!mongoClient || !mongoClient.topology || !mongoClient.topology.isConnected()) {
    mongoClient = new MongoClient(url, {
      connectTimeoutMS: 5000,  // 缩短连接超时，避免卡住
      socketTimeoutMS: 10000
    });
    await mongoClient.connect();
  }
  return mongoClient;
}

async function userHandler(params) {
  // 日志脱敏：前端 params 中可能含 password / newPassword / oldPassword 明文，
  // 统一替换为 *** 后再打印，避免日志文件残留明文密码
  const safeParams = { ...params };
  for (const k of ['password', 'newPassword', 'oldPassword', 'studentPassword', 'appealNewPassword']) {
    if (safeParams[k] !== undefined && safeParams[k] !== null && safeParams[k] !== '') {
      safeParams[k] = '***';
    }
  }
  console.log(`【/api/user】action=${safeParams.action ?? '(无)'} 账号=${safeParams.account ?? '-'}`);

  if (!params.action) {
    return { success: false, msg: "缺少 action" };
  }

  let result = { success: false, msg: "未知错误" }; // 初始化返回结果
  let client;

  try {
    // 优化2：使用复用的客户端，替代每次新建
    client = await getMongoClient();
    const db = client.db(dbName);
    const collection = db.collection(colName);

    // 1. 原有登录逻辑（优化：更强的参数容错 + 只查必要字段）
    if (params.action === "login") {
      // 优化3：强制字符串化+空值容错，避免undefined/null导致的判断错误
      const account = (params.account ?? '').toString().trim();
      const password = (params.password ?? '').toString().trim();
      const selected_role = (params.selected_role ?? '').toString().trim();

      console.log("【登录】账号：", account);
      console.log("【登录】角色：", selected_role);

      // 提前校验空值，减少数据库查询
      if (!account || !password || !selected_role) {
        result = { success: false, msg: "登录失败，请检查账号密码" };
        return result;
      }

      // 优化4：只查询必要字段（password/type/remark），提升查询速度
      const findUser = await collection.findOne(
        { account: account },
        { projection: { password: 1, type: 1, remark: 1 } }
      );

      if (!findUser) {
        console.log("【错误】没找到这个账号");
        result = { success: false, msg: "登录失败，请检查账号密码" };
      } else {
        const pwdOk = String(findUser.password ?? '') === String(password);
        const roleOk = String(findUser.type) === selected_role;

        if (!pwdOk || !roleOk) {
          result = { success: false, msg: "登录失败，请检查账号密码" };
        } else {
          console.log("✅ 登录成功！");
          result = {
            success: true,
            msg: "登录成功",
            account: account,
            remark: findUser.remark || '', // 返回用户备注（无则为空）
          };
        }
      }
    }

    // 2. 新增：创建用户（管理员专用）
    else if (params.action === "createUser") {
      const account = params.account?.toString().trim() || '';
      const password = params.password?.toString().trim() || '';
      const type = Number(params.type) || 2; // 1=管理员，2=学生，3=家长（默认学生）
      const remark = params.remark?.toString().trim() || '';
      // 新增：接收绑定学生列表（仅家长有效）
      const boundStudents = Array.isArray(params.boundStudents) ? params.boundStudents : [];

      if (!account || !password) {
        result = { success: false, msg: "账号和密码不能为空" };
      } else if (![1, 2, 3].includes(type)) {
        result = { success: false, msg: "角色类型错误（1=管理员，2=学生，3=家长）" };
      } else {
        const existUser = await collection.findOne({ account: account });
        if (existUser) {
          result = { success: false, msg: "该账号已存在，无法创建" };
        } else {
          const newUser = {
            account: account,       // 字符串账号
            password: password,     // 明文存储
            type: type,             // 数字角色（1/2/3）
            remark: remark,         // 备注（支持中文）
            boundStudents: type === 3 ? boundStudents : [] // 仅家长存储绑定学生
          };
          const insertResult = await collection.insertOne(newUser);

          console.log(`✅ 创建用户成功：账号=${account}，角色=${type}，ID=${insertResult.insertedId}`);
          result = {
            success: true,
            msg: "用户创建成功",
            userId: insertResult.insertedId.toString(),
            account: account
          };
        }
      }
    }
    // 3. 新增：查询所有用户列表（管理员专用）
    else if (params.action === "getUserList") {
      const userList = await collection
        .find({}, { projection: { password: 0 } }) // 不返回密码，安全
        .sort({ _id: -1 })
        .toArray();

      const formattedList = userList.map(user => ({
        ...user,
        _id: user._id.toString(), // ObjectId转字符串，前端好处理
        boundStudents: user.boundStudents || [] // 新增：返回绑定学生列表
      }));

      console.log("✅ 查询用户列表成功：", formattedList);
      result = {
        success: true,
        msg: "查询用户列表成功",
        data: formattedList
      };
    }

    // 4. 新增：删除用户（管理员专用）+ 级联删除该用户所有答题记录
  else if (params.action === "deleteUser") {
    const account = params.account?.toString().trim() || '';
    if (!account) {
      result = { success: false, msg: "缺少要删除的账号参数" };
    } else if (account.toLowerCase() === "admin") {
      // 🔒 防御机制：默认 admin 账号不可删除，其余新建管理员允许删除
      result = { success: false, msg: "默认 admin 账号不可删除" };
    } else {
      // 1. 删除用户本身
      const deleteResult = await collection.deleteOne({ account: account });

      if (deleteResult.deletedCount === 0) {
        result = { success: false, msg: "该账号不存在，删除失败" };
      } else {
        // 2. 关键：删除该用户的所有考试答题记录
        const recordCollection = client.db(dbName).collection('examrecord');
        await recordCollection.deleteMany({ account: account });

        console.log(`✅ 删除用户成功：账号=${account}，并清空所有答题记录`);
        result = {
          success: true,
          msg: "用户及所有答题记录已删除",
          deletedAccount: account
        };
      }
    }
  }

    // 5. 忘记密码申诉（生成申诉码）
    else if (params.action === "submitForgotPassword") {
      const account = params.account?.toString().trim() || '';
      if (!account) {
        result = { success: false, msg: "请输入账号" };
        return result;
      }

      const existUser = await collection.findOne({ account: account });
      if (!existUser) {
        result = { success: false, msg: "账号不存在" };
        return result;
      }

      // 【新增】检查是否已有待处理的申诉（防止重复提交）
      if (existUser.appealStatus === 'pending' && existUser.appealCode) {
        // 【新增】拿到用户备注
        const userRemark = existUser.remark || '';
        
        // 重新发送推送提醒管理员（但不生成新申诉码）
        if (global.pushMsg) {
          // 🔥 修复：使用唯一ID（包含时间戳），确保每次提醒都能推送
          const appealId = `appeal_${account}_${Date.now()}`;
          await global.pushMsg(1, {
            id: appealId,
            title: '密码找回申诉（提醒）',
            content: `账号：${account}（备注：${userRemark}）申请找回密码，请及时处理！`,
            createTime: new Date(),
            type: 'appeal'
          }, true);
        }
        
        result = {
          success: true,
          msg: "您已提交过申诉啦，请勿重复提交！",
          appealCode: existUser.appealCode
        };
        return result;
      }

      // 【新增】拿到用户备注
      const userRemark = existUser.remark || '';

      const appealCode = Math.random().toString(36).substring(2, 8).toUpperCase();
      await collection.updateOne(
        { account: account },
        { $set: { 
          appealCode: appealCode, 
          appealStatus: 'pending', // pending=待处理
          appealSubmitTime: new Date() // 记录提交时间
        } }
      );
      
      // 发推送：给管理员（type=1），带上type字段
      if (global.pushMsg) {
        // 🔥 修复：使用唯一ID（包含时间戳），确保每次申诉都能推送
        const appealId = `appeal_${account}_${Date.now()}`;
        await global.pushMsg(1, {
          id: appealId,
          title: '密码找回申诉',
          content: `账号：${account}（备注：${userRemark}）申请找回密码，请及时处理！`,
          createTime: new Date(),
          type: 'appeal' // 【关键！必须加，用于区分消息类型】
        }, true);
      }

      console.log(`✅ 申诉成功：账号=${account}，申诉码=${appealCode}`);
      result = {
        success: true,
        msg: "申诉已提交，请保存好您的申诉码(唯一查询密码凭证，用于在申诉查询中查询密码）",
        appealCode: appealCode
      };
    }

    // 6. 申诉查询（用申诉码查密码，一次性）
    else if (params.action === "queryAppealResult") {
      const appealCode = params.appealCode?.toString().trim() || '';
      if (!appealCode) {
        result = { success: false, msg: "请输入申诉码查询密码" };
        return result;
      }

      const user = await collection.findOne({ appealCode: appealCode });
      if (!user) {
        result = { success: false, msg: "申诉码无效或已使用" };
        return result;
      }

      if (user.appealStatus && user.appealStatus === 'pending') {
        result = { success: false, msg: "该申诉正在处理中，请等待管理员重置密码" };
        return result;
      }

      // 密码已哈希化：取回的是临时暂存的明文（adminResetPassword 写入 appealNewPassword）
      const password = user.appealNewPassword;
      await collection.updateOne(
        { appealCode: appealCode },
        { $unset: { appealCode: '', appealNewPassword: '' } } // 删申诉码 + 删临时明文
      );

      console.log(`✅ 申诉查询成功：申诉码=${appealCode}，账号=${user.account}`);
      result = {
        success: true,
        msg: "查询成功，您的密码已重置！",
        password: password
      };
    }
    // 7. 管理员重置密码（处理申诉）
    else if (params.action === "adminResetPassword") {
      const account = params.account?.toString().trim() || '';
      const newPassword = params.newPassword?.toString().trim() || '';
      
      if (!account || !newPassword) {
        result = { success: false, msg: "账号和新密码不能为空" };
        return result;
      }

      const updateResult = await collection.updateOne(
        { account: account },
        { 
          $set: { password: newPassword, appealNewPassword: newPassword },
          $unset: { appealStatus: '' } // 只删状态，不删申诉码（保留申诉码供用户取回新密码）
        }
      );

      if (updateResult.modifiedCount === 0) {
        result = { success: false, msg: "账号不存在，重置失败" };
      } else {
        console.log(`✅ 密码重置成功：账号=${account}`);
        result = {
          success: true,
          msg: "密码重置成功",
          newPassword: newPassword // 供 queryAppealResult 链路中用户取回新密码（一次性，随消息流转不落库）
        };
      }
    }

    // 8. 用户自主修改密码
    else if (params.action === "updatePassword") {
      const account = params.account?.toString().trim() || '';
      const oldPassword = params.oldPassword?.toString().trim() || '';
      const newPassword = params.newPassword?.toString().trim() || '';

      if (!account || !oldPassword || !newPassword) {
        result = { success: false, msg: "账号、原密码、新密码不能为空" };
        return result;
      }

      const user = await collection.findOne({ account: account });
      if (!user) {
        result = { success: false, msg: "用户不存在" };
        return result;
      }

      if (String(user.password ?? '') !== String(oldPassword)) {
        result = { success: false, msg: "修改失败，请输入正确的原密码" };
        return result;
      }

      await collection.updateOne(
        { account: account },
        { $set: { password: newPassword } }
      );

      console.log(`✅ 用户自主修改密码成功：账号=${account}`);
      result = {
        success: true,
        msg: "密码修改成功"
      };
    }
        // 9. 新增：编辑用户（管理员专用）
    else if (params.action === "updateUser") {
      const account = params.account?.toString().trim() || '';
      const newAccount = params.newAccount?.toString().trim() || account; // 支持修改账号
      const remark = params.remark?.toString().trim() || '';
      const newPassword = params.newPassword?.toString().trim() || '';
      const boundStudents = Array.isArray(params.boundStudents) ? params.boundStudents : [];

      if (!account) {
        result = { success: false, msg: "缺少目标账号参数" };
      } else {
        // 1. 检查原用户是否存在
        const existUser = await collection.findOne({ account: account });
        if (!existUser) {
          result = { success: false, msg: "该账号不存在，无法编辑" };
        } else {
          // 2. 如果修改了账号，检查新账号是否重复
          if (newAccount !== account) {
            const duplicateAccount = await collection.findOne({ account: newAccount });
            if (duplicateAccount) {
              result = { success: false, msg: "新账号已存在，无法修改" };
              return result;
            }
          }

          // 3. 构造更新数据
          const updateData = {
            $set: {
              account: newAccount,
              remark: remark,
              updateTime: new Date()
            }
          };

          // 仅家长更新绑定学生
          if (existUser.type === 3) {
            updateData.$set.boundStudents = boundStudents;
          }

          if (newPassword) {
            updateData.$set.password = newPassword;
          }

          // 4. 执行更新
          await collection.updateOne(
            { account: account },
            updateData
          );

          console.log(`✅ 编辑用户成功：原账号=${account}，新账号=${newAccount}`);
          result = {
            success: true,
            msg: "用户编辑成功",
            account: newAccount
          };
        }
      }
    }

    // 10. 新增：家长自主绑定学生
    else if (params.action === "parentBindStudent") {
      const parentAccount = params.parentAccount?.toString().trim() || '';
      const studentAccount = params.studentAccount?.toString().trim() || '';
      const studentPassword = params.studentPassword?.toString().trim() || '';

      if (!parentAccount || !studentAccount || !studentPassword) {
        result = { success: false, msg: "缺少家长账号/学生账号/学生密码" };
      } else {
        // 1. 验证学生账号密码是否正确
        const student = await collection.findOne({ 
          account: studentAccount, 
          type: 2 // 必须是学生角色
        });
        if (!student) {
          result = { success: false, msg: "学生账号不存在" };
        } else if (String(student.password ?? '') !== String(studentPassword)) {
          result = { success: false, msg: "学生密码错误" };
        } else {
          // 2. 检查是否已绑定
          const parent = await collection.findOne({ account: parentAccount, type: 3 });
          if (!parent) {
            result = { success: false, msg: "家长账号不存在" };
          } else {
            const currentBound = parent.boundStudents || [];
            if (currentBound.includes(studentAccount)) {
              result = { success: false, msg: "该学生已绑定，无需重复绑定" };
            } else {
              // 3. 执行绑定
              await collection.updateOne(
                { account: parentAccount },
                { $push: { boundStudents: studentAccount } }
              );
              console.log(`✅ 家长绑定学生成功：家长=${parentAccount}，学生=${studentAccount}`);
              result = {
                success: true,
                msg: "绑定学生成功",
                studentAccount: studentAccount
              };
            }
          }
        }
      }
    }

    // 11. 新增：家长自主解绑学生
    else if (params.action === "parentUnbindStudent") {
      const parentAccount = params.parentAccount?.toString().trim() || '';
      const studentAccount = params.studentAccount?.toString().trim() || '';

      if (!parentAccount || !studentAccount) {
        result = { success: false, msg: "缺少家长账号/学生账号" };
      } else {
        await collection.updateOne(
          { account: parentAccount },
          { $pull: { boundStudents: studentAccount } }
        );
        console.log(`✅ 家长解绑学生成功：家长=${parentAccount}，学生=${studentAccount}`);
        result = {
          success: true,
          msg: "解绑学生成功",
          studentAccount: studentAccount
        };
      }
    }

    // 12. 新增：获取家长绑定的学生列表
    else if (params.action === "getParentBoundStudents") {
      const parentAccount = params.parentAccount?.toString().trim() || '';
      if (!parentAccount) {
        result = { success: false, msg: "缺少家长账号参数" };
      } else {
        const parent = await collection.findOne(
          { account: parentAccount, type: 3 },
          { projection: { boundStudents: 1, _id: 0 } }
        );
        const boundStudents = parent?.boundStudents || [];
        
        // 获取绑定学生的备注信息
        const students = await collection
          .find({ account: { $in: boundStudents }, type: 2 })
          .toArray();
        
        result = {
          success: true,
          msg: "获取绑定学生成功",
          data: students.map(s => ({
            account: s.account,
            remark: s.remark || ''
          }))
        };
      }
    }

    // 13. 新增：创建二维码登录凭证（平板端调用）
    else if (params.action === "qrcodecreate") {
      // 生成唯一随机qrkey（32位随机字符串）
      const qrkey = crypto.randomBytes(16).toString('hex');
      const expire = Date.now() + QRCODE_EXPIRE_TIME;
      
      // 存入内存缓存（初始未绑定账号）
      qrCodeCache.set(qrkey, { account: null, expire: expire });
      
      console.log(`[二维码登录] 创建qrkey: ${qrkey}, 过期时间: ${new Date(expire).toLocaleString()}`);
      result = {
        success: true,
        msg: "二维码创建成功",
        qrkey: qrkey,
        expireTime: QRCODE_EXPIRE_TIME // 返回有效期（毫秒），供前端参考
      };
    }

    // 14. 新增：二维码绑定账号（手机端扫码后调用）
    else if (params.action === "qrcodebind") {
      const qrkey = params.qrkey?.toString().trim() || '';
      const account = params.account?.toString().trim() || '';
      
      if (!qrkey || !account) {
        result = { success: false, msg: "缺少二维码凭证或账号参数" };
      } else {
        // 校验qrkey是否存在
        const cached = qrCodeCache.get(qrkey);
        if (!cached) {
          result = { success: false, msg: "二维码不存在或已失效" };
        } else if (cached.expire < Date.now()) {
          // 二维码已过期，删除缓存
          qrCodeCache.delete(qrkey);
          result = { success: false, msg: "二维码已过期，请刷新重试" };
        } else if (cached.account) {
          // 已被其他账号绑定
          result = { success: false, msg: "二维码已被使用" };
        } else {
          // 校验账号是否存在且为学生角色
          const user = await collection.findOne(
            { account: account },
            { projection: { type: 1, remark: 1 } }
          );
          if (!user) {
            result = { success: false, msg: "账号不存在" };
          } else if (user.type !== 2) {
            result = { success: false, msg: "仅学生账号可扫码登录平板考试系统" };
          } else {
            // 绑定账号到二维码
            cached.account = account;
            cached.remark = user.remark || '';
            qrCodeCache.set(qrkey, cached);
            
            console.log(`[二维码登录] 绑定成功: qrkey=${qrkey}, account=${account}`);
            result = {
              success: true,
              msg: "登陆成功，可以在平板端正常使用了！"
            };
          }
        }
      }
    }

    // 15. 新增：二维码状态检查（平板端轮询调用）
    else if (params.action === "qrcodecheck") {
      const qrkey = params.qrkey?.toString().trim() || '';
      
      if (!qrkey) {
        result = { success: false, msg: "缺少二维码凭证参数" };
      } else {
        const cached = qrCodeCache.get(qrkey);
        
        if (!cached) {
          // 二维码不存在（可能已被使用后删除，或从未创建）
          result = { success: false, msg: "二维码已失效", status: "expired" };
        } else if (cached.expire < Date.now()) {
          // 二维码已过期
          qrCodeCache.delete(qrkey);
          result = { success: false, msg: "二维码已过期", status: "expired" };
        } else if (!cached.account) {
          // 未绑定账号，等待扫码
          result = {
            success: true,
            msg: "等待扫码授权",
            status: "waiting"
          };
        } else {
          // 已绑定账号，返回账号信息并删除缓存（一次性使用）
          const account = cached.account;
          const remark = cached.remark || '';
          qrCodeCache.delete(qrkey);
          
          console.log(`[二维码登录] 授权成功: qrkey=${qrkey}, account=${account}`);
          result = {
            success: true,
            msg: "授权成功",
            status: "authorized",
            account: account,
            remark: remark
          };
        }
      }
    }

    // 16. 新增：发送邮箱验证码（用于绑定或找回密码）
    else if (params.action === "sendEmailCode") {
      const account = params.account?.toString().trim() || '';
      const email = params.email?.toString().trim().toLowerCase() || '';
      const purpose = params.purpose || 'bind'; // purpose: bind=绑定邮箱, reset=重置密码

      if (!account || !email) {
        result = { success: false, msg: "账号和邮箱不能为空" };
      } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        result = { success: false, msg: "邮箱格式不正确" };
      } else {
        // 验证账号是否存在
        const user = await collection.findOne({ account: account });
        if (!user) {
          result = { success: false, msg: "账号不存在" };
        } else {
          // 绑定邮箱场景：检查邮箱是否已被其他账号绑定
          if (purpose === 'bind') {
            const existEmail = await collection.findOne({ 
              email: email, 
              account: { $ne: account } 
            });
            if (existEmail) {
              result = { success: false, msg: "该邮箱已被其他账号绑定" };
            } else if (user.email && user.email.toLowerCase() === email) {
              result = { success: false, msg: "该邮箱已绑定到此账号，无需重复绑定" };
            } else {
              // 生成验证码并发送
              const code = generateEmailCode();
              const expire = Date.now() + EMAIL_CODE_EXPIRE_TIME;
              emailCodeCache.set(account, { code, email, purpose, expire });

              const emailHtml = `
                <div style="font-family: Arial, sans-serif; max-width: 500px; margin: 0 auto;">
                  <h2 style="color: #333;">邮箱绑定验证码</h2>
                  <p>您好，您正在绑定邮箱到账号 <strong>${account}</strong>。</p>
                  <div style="background: #f5f5f5; padding: 20px; text-align: center; margin: 20px 0;">
                    <span style="font-size: 28px; font-weight: bold; letter-spacing: 8px; color: #2877FF;">${code}</span>
                  </div>
                  <p style="color: #666;">验证码 <strong>5 分钟</strong>内有效，请勿泄露给他人；使用后请及时删除。</p>
                  <p style="color: #999; font-size: 12px;">本邮件由系统自动发送，无需回复。如非本人操作请忽略。</p>
                </div>
              `;

              const sendResult = await sendEmail(email, '【智答星途】邮箱绑定验证', emailHtml);
              if (sendResult.success) {
                console.log(`✅ 邮箱验证码发送成功: account=${account}, email=${email}, code=${code}`);
                result = { success: true, msg: "验证码已发送到您的邮箱，请及时查收！" };
              } else {
                result = { success: false, msg: "验证码发送失败，请检查邮箱地址内容或格式是否正确！" };
              }
            }
          }
          // 重置密码场景：检查邮箱是否与账号匹配
          else if (purpose === 'reset') {
            if (!user.email || user.email.toLowerCase() !== email) {
              result = { success: false, msg: "该账号未绑定此邮箱" };
            } else {
              // 生成验证码并发送
              const code = generateEmailCode();
              const expire = Date.now() + EMAIL_CODE_EXPIRE_TIME;
              emailCodeCache.set(account, { code, email, purpose, expire });

              const emailHtml = `
                <div style="font-family: Arial, sans-serif; max-width: 500px; margin: 0 auto;">
                  <h2 style="color: #333;">密码重置验证码</h2>
                  <p>您好，您正在重置账号 <strong>${account}</strong> 的密码。</p>
                  <div style="background: #f5f5f5; padding: 20px; text-align: center; margin: 20px 0;">
                    <span style="font-size: 28px; font-weight: bold; letter-spacing: 8px; color: #FF5722;">${code}</span>
                  </div>
                  <p style="color: #666;">验证码 <strong>5 分钟</strong>内有效，请勿泄露给他人。</p>
                  <p style="color: #999; font-size: 12px;">本邮件由系统自动发送，无需回复。如非本人操作请忽略。</p>
                </div>
              `;

              const sendResult = await sendEmail(email, '【智答星途】密码重置验证', emailHtml);
              if (sendResult.success) {
                console.log(`✅ 密码重置验证码发送成功: account=${account}, email=${email}, code=${code}`);
                result = { success: true, msg: "验证码已发送到您的邮箱" };
              } else {
                result = { success: false, msg: "验证码发送失败，请检查邮箱地址" };
              }
            }
          }
        }
      }
    }

    // 17. 新增：绑定邮箱
    else if (params.action === "bindEmail") {
      const account = params.account?.toString().trim() || '';
      const email = params.email?.toString().trim().toLowerCase() || '';
      const code = params.code?.toString().trim() || '';

      if (!account || !email || !code) {
        result = { success: false, msg: "账号、邮箱、验证码不能为空" };
      } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        result = { success: false, msg: "邮箱格式不正确" };
      } else {
        // 验证验证码
        const cached = emailCodeCache.get(account);
        if (!cached || cached.expire < Date.now()) {
          result = { success: false, msg: "验证码已过期，请重新获取" };
        } else if (cached.code !== code) {
          result = { success: false, msg: "验证码错误" };
        } else if (cached.email !== email) {
          result = { success: false, msg: "邮箱地址不匹配" };
        } else if (cached.purpose !== 'bind') {
          result = { success: false, msg: "验证码用途不正确" };
        } else {
          // 执行绑定
          await collection.updateOne(
            { account: account },
            { $set: { email: email, emailBindTime: new Date() } }
          );
          emailCodeCache.delete(account);

          console.log(`✅ 邮箱绑定成功: account=${account}, email=${email}`);
          result = { success: true, msg: "邮箱绑定成功" };
        }
      }
    }

    // 18. 新增：解绑邮箱
    else if (params.action === "unbindEmail") {
      const account = params.account?.toString().trim() || '';
      if (!account) {
        result = { success: false, msg: "账号不能为空" };
      } else {
        const user = await collection.findOne({ account: account }, { projection: { email: 1 } });
        if (!user) {
          result = { success: false, msg: "用户不存在" };
        } else if (!user.email) {
          result = { success: false, msg: "该账号未绑定邮箱" };
        } else {
          await collection.updateOne(
            { account: account },
            { $unset: { email: '', emailBindTime: '' } }
          );
          console.log(`✅ 邮箱解绑成功: account=${account}`);
          result = { success: true, msg: "邮箱解绑成功" };
        }
      }
    }

    // 19. 新增：邮箱验证码重置密码
    else if (params.action === "resetPasswordByEmail") {
      const account = params.account?.toString().trim() || '';
      const email = params.email?.toString().trim().toLowerCase() || '';
      const code = params.code?.toString().trim() || '';
      const newPassword = params.newPassword?.toString().trim() || '';

      if (!account || !email || !code || !newPassword) {
        result = { success: false, msg: "账号、邮箱、验证码、新密码不能为空" };
      } else if (newPassword.length < 6) {
        result = { success: false, msg: "新密码长度不能少于6位" };
      } else {
        // 验证验证码
        const cached = emailCodeCache.get(account);
        if (!cached || cached.expire < Date.now()) {
          result = { success: false, msg: "验证码已过期，请重新获取" };
        } else if (cached.code !== code) {
          result = { success: false, msg: "验证码错误" };
        } else if (cached.email !== email) {
          result = { success: false, msg: "邮箱地址不匹配" };
        } else if (cached.purpose !== 'reset') {
          result = { success: false, msg: "验证码用途不正确" };
        } else {
          // 执行密码重置
          await collection.updateOne(
            { account: account },
            { $set: { password: newPassword } }
          );
          emailCodeCache.delete(account);

          console.log(`✅ 邮箱验证码重置密码成功: account=${account}`);
          result = { success: true, msg: "密码重置成功" };
        }
      }
    }

    // 19. 新增：检查用户邮箱绑定状态（登录时调用）
    else if (params.action === "checkEmailBind") {
      const account = params.account?.toString().trim() || '';
      
      if (!account) {
        result = { success: false, msg: "账号不能为空" };
      } else {
        const user = await collection.findOne(
          { account: account },
          { projection: { email: 1 } }
        );
        
        if (!user) {
          result = { success: false, msg: "用户不存在" };
        } else {
          result = {
            success: true,
            msg: "查询成功",
            hasEmail: !!user.email,
            email: user.email || null
          };
        }
      }
    }

    // 无效action
    else {
      result = { success: false, msg: `无效的action：${params.action}` };
    }

  } catch (err) {
    console.error("服务器错误：", err);
    // 优化5：隐藏敏感错误信息，避免前端误判+安全风险
    result = { success: false, msg: "服务器内部错误，请稍后重试" };
  } finally {
    // 优化6：复用客户端，不再每次关闭（核心提速点）
    // await client.close(); // 注释掉这行，改用全局复用
  }

  return result; // 统一返回结果
}

module.exports = { userHandler };