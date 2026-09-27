const { MongoClient } = require('mongodb');
const crypto = require('crypto');

const MONGO_URL = 'mongodb://localhost:27017';
const DB_NAME = 'zdxt';
const COL = 'sign_in';

let currentSign = null;
let timer = null;
let clientGlobal = null;
let qrUpdateCounter = 0;  // 二维码更新计数器（每10秒更新一次）

async function handler(params) {
  if (!clientGlobal) {
    clientGlobal = new MongoClient(MONGO_URL);
    await clientGlobal.connect();
  }
  const db = clientGlobal.db(DB_NAME);
  const col = db.collection(COL);
  const userCol = db.collection('user');

  try {
    switch (params.action) {
      case 'create': {
        const type = params.type;
        const code = params.code || '';
        const totalTime = Number(params.time) || 60;
        const subject = params.subject || '语文';
        const title = params.title || '';

        const allStudents = await userCol.find({ type: 2 }).project({
          account: 1, name: 1, remark: 1
        }).toArray();

        const allStudentNames = allStudents.map(s => {
          const acc = s.account || '';
          const rem = s.remark || '';
          return rem ? `${acc}(${rem})` : acc;
        });

        currentSign = {
          running: true,
          locked: false,
          closed: false,           // 新增字段：是否已关闭（完全清空）
          subject,
          title,
          type,
          code,
          qrcode: crypto.randomUUID(),
          startTime: Date.now(),
          totalTime,
          leftTime: totalTime,
          allStudents: allStudentNames,
          signedList: [],
          signedAccounts: [],
          unsignedList: [...allStudentNames],
          createTime: new Date()
        };

        await col.insertOne({ ...currentSign });
        startTimer();
        return { success: true, message: '已发起签到' };
      }

      case 'status': {
        if (!currentSign) {
          return { success: true, data: { running: false, closed: true } };
        }
        return { success: true, data: currentSign };
      }

      case 'stop': {
        if (currentSign) {
          currentSign.running = false;
          currentSign.locked = true;
        }
        stopTimer();

        if (currentSign) {
          await col.updateOne(
            { createTime: currentSign.createTime },
            { $set: currentSign }
          );
        }
        return { success: true };
      }

      case 'close': {
        // 新增：彻底关闭签到（清空大屏）
        if (currentSign) {
          currentSign.closed = true;
          await col.updateOne(
            { createTime: currentSign.createTime },
            { $set: { closed: true } }
          );
        }
        return { success: true };
      }

      case 'scan': {
        const account = params.account;
        const qrcode = params.qrcode;

        if (!currentSign || !currentSign.running || currentSign.locked) {
          return { success: false, message: '已结束' };
        }
        if (currentSign.qrcode !== qrcode) return { success: false, message: '二维码已过期，请重新扫描！' };
        return await doSign(account, userCol, col);
      }

      case 'code': {
        const account = params.account;
        const code = params.code;

        if (!currentSign || !currentSign.running || currentSign.locked) {
          return { success: false, message: '已结束' };
        }
        if (currentSign.code !== code) return { success: false, message: '口令错误' };
        return await doSign(account, userCol, col);
      }

      case 'history': {
        const list = await col.find().sort({ createTime: -1 }).toArray();
        const fixedList = list.map(item => {
          let timeStr = "暂无时间";
          try {
            timeStr = new Date(item.createTime).toLocaleString();
          } catch (e) {}
          return {
            ...item,
            formatTime: timeStr
          };
        });
        return { success: true, data: fixedList };
      }

      case 'clearHistory': {
        const subjects = params.subjects || [];
        if (subjects.length > 0) {
          await col.deleteMany({ subject: { $in: subjects } });
        } else {
          await col.deleteMany({});
        }
        return { success: true, message: '清除成功' };
      }

      default:
        return { success: false, message: '不存在action' };
    }
  } catch (e) {
    console.error(e);
    return { success: false, message: '服务异常' };
  }
}

async function doSign(account, userCol, col) {
  if (!currentSign || currentSign.locked) return { success: false, message: '已结束' };
  if (currentSign.signedAccounts.includes(account)) {
    return { success: true, message: '已签到' };
  }

  const user = await userCol.findOne({ account });
  const acc = user?.account || account;
  const rem = user?.remark || '';
  const showName = rem ? `${acc}(${rem})` : acc;

  currentSign.signedAccounts.push(account);
  currentSign.signedList.push(showName);

  const idx = currentSign.unsignedList.indexOf(showName);
  if (idx > -1) currentSign.unsignedList.splice(idx, 1);

  await col.updateOne(
    { createTime: currentSign.createTime },
    { $set: currentSign }
  );

  return { success: true, message: '签到成功' };
}

function startTimer() {
  stopTimer();
  qrUpdateCounter = 0;
  timer = setInterval(() => {
    if (!currentSign) { stopTimer(); return; }
    if (currentSign.running && currentSign.leftTime > 0) {
      currentSign.leftTime--;
      qrUpdateCounter++;
      // 每10秒更新二维码（仅二维码模式，非阻塞写库）
      if (qrUpdateCounter >= 15 && currentSign.type !== 'code') {
        qrUpdateCounter = 0;
        currentSign.qrcode = crypto.randomUUID();
        // fire-and-forget：不await，避免阻塞定时器和签到请求
        if (clientGlobal) {
          const db = clientGlobal.db(DB_NAME);
          const col = db.collection(COL);
          col.updateOne(
            { createTime: currentSign.createTime },
            { $set: { qrcode: currentSign.qrcode } }
          ).catch(e => console.error('二维码更新失败', e));
        }
      }
    }
    if (currentSign.leftTime <= 0 && currentSign.running) {
      currentSign.running = false;
      currentSign.locked = true;
      stopTimer();
    }
  }, 1000);
}

function stopTimer() {
  if (timer) clearInterval(timer);
  timer = null;
}

function getBigScreenHtml() {
  return `
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>签到大屏</title>
  <style>
  :root{
    --gold-1:#FFE9A8; --gold-2:#FFC247; --gold-3:#FF9D2F;
    --green:#34d399; --red:#fb7185;
    --glass:rgba(255,255,255,0.055);
    --glass-brd:rgba(255,255,255,0.12);
    --ink:#f5f7ff;
  }
  *{margin:0;padding:0;box-sizing:border-box;font-family:"Microsoft YaHei","PingFang SC","Noto Sans SC",sans-serif}
  html,body{height:100%}
  body{
    color:var(--ink);height:100vh;overflow:hidden;position:relative;
    background:
      radial-gradient(1100px 620px at 12% -8%, rgba(99,102,241,0.28), transparent 60%),
      radial-gradient(1000px 560px at 108% 18%, rgba(236,72,153,0.20), transparent 55%),
      radial-gradient(900px 520px at 50% 120%, rgba(45,212,191,0.14), transparent 60%),
      linear-gradient(160deg,#070b18 0%, #0b1228 46%, #15123a 100%);
  }
  body::before{
    content:"";position:fixed;inset:0;pointer-events:none;z-index:0;
    background:
      radial-gradient(420px 420px at 20% 75%, rgba(255,193,71,0.10), transparent 70%),
      radial-gradient(380px 380px at 85% 60%, rgba(168,85,247,0.10), transparent 70%);
    animation:drift 18s ease-in-out infinite alternate;
  }
  @keyframes drift{from{transform:translate3d(0,0,0)}to{transform:translate3d(30px,-20px,0)}}

  .topbar{position:relative;z-index:2;display:flex;align-items:center;justify-content:space-between;padding:22px 40px}
  .brand{display:flex;align-items:center;gap:12px;font-size:24px;font-weight:700;letter-spacing:1px}
  .brand .logo{
    width:42px;height:42px;border-radius:12px;display:grid;place-items:center;font-size:22px;
    background:linear-gradient(135deg,var(--gold-1),var(--gold-3));color:#3a2a00;
    box-shadow:0 8px 22px rgba(255,170,40,0.35);
  }
  .brand small{display:block;font-size:12px;font-weight:400;color:rgba(255,255,255,0.45);letter-spacing:3px}
  .live{font-size:15px;color:rgba(255,255,255,0.6);display:flex;align-items:center;gap:9px}
  .live .pulse{width:10px;height:10px;border-radius:50%;background:var(--green);animation:beat 2s infinite}

  .wrap{position:relative;z-index:1;display:flex;width:100%;height:calc(100vh - 88px);padding:0 40px 30px;gap:28px}
  .left{
    width:42%;display:flex;flex-direction:column;align-items:center;justify-content:center;
    background:var(--glass);border:1px solid var(--glass-brd);border-radius:30px;padding:46px;
    backdrop-filter:blur(18px);box-shadow:0 30px 70px rgba(0,0,0,0.40), inset 0 1px 0 rgba(255,255,255,0.08);
    position:relative;overflow:hidden;animation:rise .55s ease both;
  }
  .left::after{content:"";position:absolute;top:-40%;left:-10%;width:60%;height:120%;
    background:linear-gradient(180deg,rgba(255,200,80,0.10),transparent);filter:blur(20px)}

  .empty{font-size:60px;font-weight:800;color:rgba(255,255,255,0.82);text-align:center;line-height:1.3;
    display:flex;flex-direction:column;align-items:center;gap:18px}
  .empty .ico{font-size:86px;animation:beat 2.4s infinite}
  @keyframes beat{0%{box-shadow:0 0 0 0 rgba(52,211,153,0.55);opacity:1}70%{box-shadow:0 0 0 14px rgba(52,211,153,0);opacity:.6}100%{box-shadow:0 0 0 0 rgba(52,211,153,0);opacity:1}}

  .subject-title{
    font-size:58px;font-weight:800;line-height:1.14;text-align:center;margin-bottom:10px;
    background:linear-gradient(135deg,var(--gold-1),var(--gold-2) 55%,var(--gold-3));
    -webkit-background-clip:text;background-clip:text;color:transparent;
    text-shadow:0 6px 40px rgba(255,180,60,0.22);
  }
  .title-text{font-size:32px;color:rgba(255,255,255,0.78);margin-bottom:28px;font-weight:500;text-align:center}

  .display-box{
    width:420px;height:420px;max-width:82%;flex:0 0 auto;background:#fff;border-radius:28px;
    display:flex;align-items:center;justify-content:center;color:#1f2937;
    font-size:84px;font-weight:800;letter-spacing:6px;font-variant-numeric:tabular-nums;padding:12px;
    box-shadow:0 40px 90px rgba(0,0,0,0.50), 0 0 0 6px rgba(255,255,255,0.06), 0 0 0 12px rgba(255,200,80,0.22);
  }
  .display-box canvas{width:380px!important;height:380px!important;border-radius:14px}

  .time{
    margin-top:28px;font-size:27px;font-weight:700;color:var(--gold-1);
    background:rgba(255,200,80,0.12);border:1px solid rgba(255,200,80,0.28);
    padding:12px 30px;border-radius:999px;box-shadow:0 10px 26px rgba(0,0,0,0.30);
    display:flex;align-items:center;gap:10px;
  }
  .time::before{content:"⏱";font-size:24px}

  .right{width:58%;display:flex;flex-direction:column;gap:28px;min-height:0}
  .box{
    flex:1;min-height:0;background:var(--glass);border:1px solid var(--glass-brd);border-radius:30px;
    padding:28px 34px;backdrop-filter:blur(18px);box-shadow:0 30px 70px rgba(0,0,0,0.40), inset 0 1px 0 rgba(255,255,255,0.08);
    display:flex;flex-direction:column;animation:rise .55s ease both;
  }
  .box h2{font-size:36px;font-weight:800;margin-bottom:18px;display:flex;align-items:center;gap:12px}
  .box h2::after{content:"";flex:1;height:2px;border-radius:2px;background:linear-gradient(90deg,rgba(255,255,255,0.18),transparent)}
  .green{color:var(--green)}
  .red{color:var(--red)}

  .names{flex:1;overflow-y:auto;display:flex;flex-wrap:wrap;align-content:flex-start;gap:12px;padding-right:6px}
  .names::-webkit-scrollbar{width:8px}
  .names::-webkit-scrollbar-thumb{background:rgba(255,255,255,0.18);border-radius:8px}
  .tag{
    background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.12);
    padding:12px 18px;border-radius:14px;font-size:24px;line-height:1;color:#eef1ff;
    transition:transform .18s ease, background .18s ease;
  }
  .tag:hover{transform:translateY(-3px);background:rgba(255,255,255,0.14)}
  @keyframes rise{from{opacity:0;transform:translateY(18px)}to{opacity:1;transform:translateY(0)}}

  .btn-group{position:fixed;bottom:36px;right:40px;z-index:5;display:flex;gap:18px}
  .end-btn,.close-btn{border:none;border-radius:16px;font-size:22px;font-weight:700;cursor:pointer;padding:18px 38px;color:#fff;
    transition:transform .15s ease, filter .15s ease, box-shadow .15s ease}
  .end-btn{background:linear-gradient(135deg,#FFB020,#FF7A00);box-shadow:0 14px 34px rgba(255,122,0,0.42)}
  .close-btn{background:linear-gradient(135deg,#FF5C7A,#E11D48);box-shadow:0 14px 34px rgba(225,29,72,0.42)}
  .end-btn:hover,.close-btn:hover{transform:translateY(-3px);filter:brightness(1.06)}
  .end-btn:active,.close-btn:active{transform:translateY(0) scale(.98)}

  @media (max-height:780px){
    .subject-title{font-size:46px}.title-text{font-size:26px}
    .display-box{width:340px;height:340px}.display-box canvas{width:300px!important;height:300px!important}
    .empty{font-size:50px}.empty .ico{font-size:64px}
    .box h2{font-size:30px;margin-bottom:14px}.tag{font-size:20px;padding:10px 14px}
    .time{font-size:22px;margin-top:18px}.topbar{padding:16px 30px}
  }
  </style>
</head>
<body>

<header class="topbar">
  <div class="brand">
    <span class="logo">📚</span>
    <div>智慧课堂 · 签到大屏<small>SMART CLASS SIGN-IN</small></div>
  </div>
  <div class="live"><span class="pulse"></span> 实时同步中</div>
</header>

<div class="wrap">
  <section class="left">
    <div class="empty" id="emptyTip">
      <span class="ico">📡</span>
      <span>暂无签到</span>
    </div>
    <div class="subject-title" id="subjectTitle"></div>
    <div class="title-text" id="titleText"></div>
    <div class="display-box" id="displayBox"></div>
    <div class="time" id="time"></div>
  </section>

  <section class="right">
    <div class="box">
      <h2 class="green">✅ 已签到</h2>
      <div class="names" id="signed"></div>
    </div>
    <div class="box">
      <h2 class="red">❌ 未签到</h2>
      <div class="names" id="unsigned"></div>
    </div>
  </section>
</div>

<div class="btn-group">
  <button class="end-btn" id="endBtn">结束签到</button>
  <button class="close-btn" id="closeBtn">关闭大屏</button>
</div>

<script src="https://cdn.jsdelivr.net/npm/qrcode@1.5.1/build/qrcode.min.js"></script>
<script>
// ======================== 全局变量 ========================
let isEndedManually = false;   // 本页面是否手动点击了"结束"
let endedData = null;          // 手动结束时保存的 { subject, title, signedList, unsignedList }
let pollTimer = null;          // 无签到/已关闭时的1秒轮询定时器
let localLeftTime = 0;         // 本地倒计时剩余秒数
let localTimer = null;         // 本地倒计时定时器（1秒）
let rosterTimer = null;        // 名单刷新定时器（3秒）
let syncTimer = null;          // 校准+二维码刷新定时器（10秒）
let currentQrcode = '';        // 当前二维码值（用于比对是否变化）
let isPollingMode = true;      // 当前是否为轮询模式（无签到/已关闭）

// ======================== 定时器管理 ========================
function stopAllOptimizedTimers() {
  if (localTimer) { clearInterval(localTimer); localTimer = null; }
  if (rosterTimer) { clearInterval(rosterTimer); rosterTimer = null; }
  if (syncTimer) { clearInterval(syncTimer); syncTimer = null; }
}
function stopPollTimer() {
  if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
}
function startPollTimer() {
  stopPollTimer();
  stopAllOptimizedTimers();
  isPollingMode = true;
  pollTimer = setInterval(load, 1000);
}

// ======================== 本地倒计时（1秒） ========================
function startLocalCountdown() {
  if (localTimer) clearInterval(localTimer);
  localTimer = setInterval(function() {
    if (localLeftTime <= 0) {
      clearInterval(localTimer);
      localTimer = null;
      document.getElementById('time').style.display = 'none';
      document.getElementById('displayBox').style.display = 'none';
      document.getElementById('endBtn').style.display = 'none';
      stopAllOptimizedTimers();
      syncOnce();
      return;
    }
    localLeftTime--;
    document.getElementById('time').innerText = '剩余：' + localLeftTime + ' 秒';
  }, 1000);
}

// ======================== 统一数据同步（2秒） ========================
// 合并名单刷新和二维码同步为单一轮询，几乎实时
function startRosterTimer() {
  if (rosterTimer) clearInterval(rosterTimer);
  rosterTimer = setInterval(syncOnce, 2000);
}

function startSyncTimer() {
  // 已由 rosterTimer 统一处理，不再单独启动
}

function syncOnce() {
  fetch('/api/sign', { method: 'POST', body: JSON.stringify({ action: 'status' }) })
    .then(res => res.json())
    .then(res => {
      if (!res.success || !res.data) {
        switchToPollMode();
        return;
      }
      var d = res.data;
      if (d.closed === true) {
        switchToPollMode();
        showEmpty();
        return;
      }
      if (d.running !== true) {
        switchToPollMode();
        if (isEndedManually && endedData) {
          showEndedView(endedData);
        } else {
          showEndedView(d);
        }
        return;
      }
      // 校准本地倒计时（偏差>2秒才修正）
      var serverLeft = parseInt(d.leftTime) || 0;
      if (serverLeft >= 0 && Math.abs(serverLeft - localLeftTime) > 2) {
        localLeftTime = serverLeft;
        document.getElementById('time').innerText = '剩余：' + localLeftTime + ' 秒';
      }
      // 刷新二维码（仅二维码模式，值变化时才重绘）
      if (d.type !== 'code' && d.qrcode && d.qrcode !== currentQrcode) {
        currentQrcode = d.qrcode;
        var box = document.getElementById('displayBox');
        if (box && box.style.display !== 'none') {
          var canvas = box.querySelector('canvas');
          if (canvas) QRCode.toCanvas(canvas, currentQrcode, { width: 380 });
        }
      }
      // 刷新签到名单
      document.getElementById('signed').innerHTML = (d.signedList || []).map(x => '<span class="tag">' + x + '</span>').join('');
      document.getElementById('unsigned').innerHTML = (d.unsignedList || []).map(x => '<span class="tag">' + x + '</span>').join('');
    })
    .catch(err => console.error('同步失败', err));
}

// ======================== 切换回轮询模式 ========================
function switchToPollMode() {
  stopAllOptimizedTimers();
  isPollingMode = true;
  localLeftTime = 0;
  currentQrcode = '';
  startPollTimer();
}

// ======================== UI 辅助函数 ========================
function showEmpty() {
  document.getElementById('emptyTip').style.display = 'block';
  document.getElementById('subjectTitle').innerText = '';
  document.getElementById('titleText').innerText = '';
  document.getElementById('displayBox').style.display = 'none';
  document.getElementById('time').style.display = 'none';
  document.getElementById('signed').innerHTML = '';
  document.getElementById('unsigned').innerHTML = '';
  document.getElementById('endBtn').style.display = 'none';
}

// 显示“已结束”视图：保留标题和统计，隐藏二维码/口令/时间
function showEndedView(data) {
  document.getElementById('emptyTip').style.display = 'none';
  document.getElementById('subjectTitle').innerText = (data.subject || '') + '课堂签到';
  document.getElementById('titleText').innerText = data.title || '';
  document.getElementById('displayBox').style.display = 'none';
  document.getElementById('time').style.display = 'none';
  document.getElementById('endBtn').style.display = 'none';
  document.getElementById('signed').innerHTML = (data.signedList || []).map(x => '<span class="tag">' + x + '</span>').join('');
  document.getElementById('unsigned').innerHTML = (data.unsignedList || []).map(x => '<span class="tag">' + x + '</span>').join('');
}

// 显示进行中的签到（完整界面）
function showActiveView(data) {
  // 切换到优化模式（停止轮询）
  stopPollTimer();
  isPollingMode = false;

  document.getElementById('emptyTip').style.display = 'none';
  document.getElementById('endBtn').style.display = 'block';
  document.getElementById('time').style.display = 'block';
  document.getElementById('displayBox').style.display = 'flex';

  document.getElementById('subjectTitle').innerText = (data.subject || '') + '课堂签到';
  document.getElementById('titleText').innerText = data.title || '';

  // 初始化本地倒计时
  localLeftTime = parseInt(data.leftTime) || 0;
  document.getElementById('time').innerText = '剩余：' + localLeftTime + ' 秒';

  const box = document.getElementById('displayBox');
  box.innerHTML = '';

  if (data.type === 'code') {
    currentQrcode = '';
    box.innerText = data.code;
  } else {
    currentQrcode = data.qrcode || '';
    const canvas = document.createElement('canvas');
    canvas.width = 380;
    canvas.height = 380;
    box.appendChild(canvas);
    QRCode.toCanvas(canvas, currentQrcode, { width: 380 });
  }

  document.getElementById('signed').innerHTML = (data.signedList || []).map(x => '<span class="tag">' + x + '</span>').join('');
  document.getElementById('unsigned').innerHTML = (data.unsignedList || []).map(x => '<span class="tag">' + x + '</span>').join('');

  // 启动优化定时器
  startLocalCountdown();
  startRosterTimer();
  startSyncTimer();
}

// ======================== 核心加载逻辑（仅轮询模式使用） ========================
function load() {
  // 优化模式下不执行（由各定时器独立处理）
  if (!isPollingMode) return;

  fetch('/api/sign', { method: 'POST', body: JSON.stringify({ action: 'status' }) })
    .then(res => res.json())
    .then(res => {
      if (!res.success || !res.data) {
        showEmpty();
        return;
      }

      const d = res.data;
      const isRunning = d.running === true;
      const isClosed = d.closed === true;

      // 如果已关闭（closed=true），直接显示空
      if (isClosed) {
        showEmpty();
        return;
      }

      if (isRunning) {
        // 签到进行中：切换到优化模式
        isEndedManually = false;
        endedData = null;
        showActiveView(d);
      } else {
        // 签到已结束（running=false 且 closed=false）
        if (isEndedManually && endedData) {
          // 本页面手动结束过，使用保存的数据
          showEndedView(endedData);
        } else {
          // 外部结束（手机端或倒计时）→ 直接显示结束视图，但不保存到 endedData
          showEndedView(d);
        }
      }
    })
    .catch(err => {
      console.error('请求失败', err);
      showEmpty();
    });
}

// ======================== 结束按钮（手动结束） ========================
document.getElementById('endBtn').onclick = () => {
  // 调用后端停止签到（只改 running = false）
  fetch('/api/sign', { method: 'POST', body: JSON.stringify({ action: 'stop' }) })
    .then(() => {
      return fetch('/api/sign', { method: 'POST', body: JSON.stringify({ action: 'status' }) });
    })
    .then(res => res.json())
    .then(res => {
      if (res.success && res.data) {
        const d = res.data;
        endedData = {
          subject: d.subject,
          title: d.title,
          signedList: d.signedList,
          unsignedList: d.unsignedList
        };
        isEndedManually = true;
        // 停止优化定时器，切换回轮询模式
        stopAllOptimizedTimers();
        startPollTimer();
        showEndedView(endedData);
      }
    })
    .catch(err => console.error('结束失败', err));
};

// ======================== 关闭按钮 ========================
document.getElementById('closeBtn').onclick = () => {
  // 调用后端 close 接口，设置 closed = true
  fetch('/api/sign', { method: 'POST', body: JSON.stringify({ action: 'close' }) })
    .then(() => {
      isEndedManually = false;
      endedData = null;
      // 停止优化定时器，切换回轮询模式
      stopAllOptimizedTimers();
      startPollTimer();
      showEmpty();
    })
    .catch(err => console.error('关闭失败', err));
};

// ======================== 页面启动 ========================
window.addEventListener('load', () => {
  load();
  startPollTimer();
});
</script>
</body>
</html>
  `;
}

module.exports = {
  signHandler: handler,
  getBigScreenHtml
};