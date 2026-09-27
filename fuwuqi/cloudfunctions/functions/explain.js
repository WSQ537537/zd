/**
 * 讲解功能后端业务逻辑
 * 职责：试卷数据读取、指令转发（手机 HTTP → 大屏 WebSocket）
 */

const { ObjectId } = require('mongodb');
const WebSocket = require('ws');
const { dbPool, Logger } = require('../utils');
const { SERVER_HOST } = require('../config'); // ✅ 公网地址统一配置
const colName = 'exam';
const recordColName = 'examrecord';

// ==================== 会话状态 ====================
let currentSession = null;
let pendingScreenWs = null;

function getSession() { return currentSession; }
function setSession(data) { currentSession = data; }
function removeSession() { currentSession = null; }
function getPendingScreenWs() { return pendingScreenWs; }
function setPendingScreenWs(ws) { pendingScreenWs = ws; }
function clearPendingScreenWs(ws) { if (pendingScreenWs === ws) pendingScreenWs = null; }

// ==================== HTML 大屏页面模板 ====================
function getExplainHtml() {
  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>智答星途 · 讲解</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css" crossorigin="anonymous">
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js" crossorigin="anonymous" onload="renderAll()"><\/script>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{
  font-family:'PingFang SC','Microsoft YaHei',sans-serif;
  background:linear-gradient(135deg,#0f0c29,#302b63,#24243e);
  color:#fff;min-height:100vh;overflow-x:hidden;
}

/* ===== 暂无讲解 ===== */
.no-state{
  display:flex;flex-direction:column;align-items:center;justify-content:center;
  height:100vh;gap:20px;
}
.no-state .icon{font-size:80px;opacity:.4}
.no-state .text{font-size:26px;opacity:.5;letter-spacing:4px}
.no-state .sub{font-size:14px;opacity:.3}
.wait-dot{
  width:10px;height:10px;border-radius:50%;
  background:rgba(102,126,234,.6);animation:bounce 1.2s infinite;margin-top:24px;
}
.wait-dot:nth-child(2){animation-delay:.2s;background:rgba(118,75,162,.6)}
.wait-dot:nth-child(3){animation-delay:.4s;background:rgba(165,180,252,.6)}
@keyframes bounce{0%,80%,100%{transform:translateY(0)}40%{transform:translateY(-12px)}}

/* ===== 讲解进行中 ===== */
.live-container{
  display:none;flex-direction:column;min-height:100vh;
  padding:24px 40px 40px;animation:fadeIn .4s ease;
}
@keyframes fadeIn{from{opacity:0;transform:translateY(12px)}to{opacity:1;transform:translateY(0)}}
@keyframes slideUp{from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:translateY(0)}}

.header{
  display:flex;align-items:center;justify-content:space-between;
  padding-bottom:16px;border-bottom:1px solid rgba(255,255,255,.08);margin-bottom:20px;
}
.header-left{display:flex;align-items:center;gap:16px}
.header .badge{
  display:flex;align-items:center;gap:6px;
  background:rgba(102,126,234,.18);border:1px solid rgba(102,126,234,.4);
  border-radius:20px;padding:5px 14px;font-size:13px;color:#a5b4fc;font-weight:600;
}
.live-dot{width:8px;height:8px;border-radius:50%;background:#34d399;animation:pulse 1.5s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
.header .exam-name{font-size:18px;font-weight:700;color:rgba(255,255,255,.9)}
.q-counter{font-size:14px;color:rgba(255,255,255,.4)}

/* ===== 左3右2分栏 ===== */
.main{flex:1;display:grid;grid-template-columns:3fr 2fr;gap:20px;align-items:start}

/* ===== 题目卡片 ===== */
.question-card{
  background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.08);
  border-radius:20px;padding:28px 32px;animation:slideUp .35s ease;
}
.q-header{display:flex;align-items:center;gap:10px;margin-bottom:18px;flex-wrap:wrap}
.q-num{
  background:linear-gradient(135deg,#667eea,#764ba2);
  border-radius:12px;padding:6px 16px;font-size:14px;font-weight:700;
}
.q-type-tag{
  background:rgba(102,126,234,.18);border:1px solid rgba(102,126,234,.35);
  border-radius:8px;padding:4px 12px;font-size:12px;color:#a5b4fc;
}
.q-score{
  background:rgba(251,191,36,.12);border:1px solid rgba(251,191,36,.28);
  border-radius:8px;padding:4px 12px;font-size:12px;color:#fbbf24;
}
.q-title{font-size:22px;line-height:1.7;font-weight:500;white-space:pre-wrap;word-break:break-word}
.q-image{margin-top:20px;text-align:center}
.q-image img{max-width:100%;max-height:400px;border-radius:14px;object-fit:contain;background:rgba(255,255,255,.04)}
.options-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:24px}
.option-item{
  background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.1);
  border-radius:14px;padding:16px 20px;font-size:16px;line-height:1.5;
  display:flex;align-items:flex-start;gap:12px;
}
.opt-label{
  flex-shrink:0;width:32px;height:32px;border-radius:8px;
  background:rgba(102,126,234,.22);border:1px solid rgba(102,126,234,.4);
  display:flex;align-items:center;justify-content:center;
  font-weight:700;font-size:14px;color:#a5b4fc;
}

/* ===== 右栏 ===== */
.side-panel{display:flex;flex-direction:column;gap:16px}
.answer-block{padding:24px 28px;border-radius:16px;animation:slideUp .3s ease}
.answer-block.answer{background:rgba(52,211,153,.08);border:1px solid rgba(52,211,153,.25)}
.answer-block.analysis{background:rgba(96,165,250,.08);border:1px solid rgba(96,165,250,.25)}
.block-label{font-size:16px;font-weight:700;margin-bottom:10px;letter-spacing:1px}
.answer .block-label{color:#34d399}
.analysis .block-label{color:#60a5fa}
.block-content{font-size:20px;line-height:1.8}
.answer .block-content{color:#6ee7b7;font-weight:600}
.analysis .block-content{color:#93c5fd}

/* ===== 统计区块 ===== */
.stats-block{
  background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.08);
  border-radius:16px;padding:22px 26px;animation:slideUp .3s ease;
}
.stats-tabs{display:flex;gap:10px;margin-bottom:16px}
.stat-tab{
  padding:10px 22px;border-radius:10px;font-size:15px;font-weight:600;
  cursor:pointer;transition:all .2s;border:1px solid transparent;
}
.stat-tab.correct{background:rgba(52,211,153,.12);color:#34d399;border-color:rgba(52,211,153,.25)}
.stat-tab.wrong{background:rgba(239,68,68,.1);color:#fca5a5;border-color:rgba(239,68,68,.2)}
.stat-tab.active-correct{background:rgba(52,211,153,.22);border-color:#34d399}
.stat-tab.active-wrong{background:rgba(239,68,68,.18);border-color:#ef4444}
.user-list{max-height:300px;overflow-y:auto}
.user-item{
  display:flex;align-items:center;justify-content:space-between;
  padding:12px 16px;border-radius:10px;margin-bottom:8px;background:rgba(255,255,255,.04);
}
.user-name{font-size:16px;color:rgba(255,255,255,.85)}
.user-answer{font-size:14px;color:rgba(255,255,255,.5)}
.stats-empty{text-align:center;padding:24px;color:rgba(255,255,255,.25);font-size:15px}

/* ===== 答错原始答案区块（统计下方） ===== */
.wrong-answer-block{
  padding:22px 28px;border-radius:16px;
  background:rgba(239,68,68,.07);border:1px solid rgba(239,68,68,.22);
  animation:slideUp .3s ease;
}
.wa-header{display:flex;align-items:center;gap:10px;margin-bottom:12px}
.wa-dot{width:10px;height:10px;border-radius:50%;background:#ef4444;animation:pulse 1.2s infinite}
.wa-label{font-size:16px;font-weight:700;color:#fca5a5;letter-spacing:1px}
.wa-account{font-size:16px;color:rgba(255,255,255,.85);margin-left:auto}
.wa-content{font-size:20px;line-height:1.8;color:#fecaca}
.wa-dismiss{margin-top:12px;text-align:right}
.wa-dismiss button{
  background:none;border:1px solid rgba(255,255,255,.15);
  color:rgba(255,255,255,.5);padding:8px 20px;border-radius:8px;
  cursor:pointer;font-size:15px;transition:all .2s;
}
.wa-dismiss button:hover{border-color:rgba(255,255,255,.35);color:rgba(255,255,255,.8)}

::-webkit-scrollbar{width:4px}
::-webkit-scrollbar-track{background:transparent}
::-webkit-scrollbar-thumb{background:rgba(255,255,255,.15);border-radius:2px}

@media(max-width:900px){
  .live-container{padding:20px 24px}
  .main{grid-template-columns:1fr}
  .options-grid{grid-template-columns:1fr}
  .q-title{font-size:19px}
}
</style>
</head>
<body>

<div class="no-state" id="noState">
  <div class="icon">📺</div>
  <div class="text">暂无讲解</div>
  <div class="sub">请等待管理员开始讲解</div>
  <div style="display:flex;gap:8px;margin-top:24px">
    <div class="wait-dot"></div><div class="wait-dot"></div><div class="wait-dot"></div>
  </div>
</div>

<div class="live-container" id="liveContainer">
  <div class="header">
    <div class="header-left">
      <div class="badge"><div class="live-dot"></div>讲解中</div>
      <div class="exam-name" id="headerTitle">-</div>
    </div>
    <div class="q-counter" id="qCounter">第 1 题</div>
  </div>

  <div class="main" id="mainArea">
    <div class="question-card" id="questionCard">
      <div class="q-header">
        <span class="q-num" id="qNum">第 1 题</span>
        <span class="q-type-tag" id="qTypeTag">单选题</span>
        <span class="q-score" id="qScoreTag">10分</span>
      </div>
      <div class="q-title" id="qTitle">-</div>
      <div class="q-image" id="qImage"></div>
      <div class="options-grid" id="optionsGrid"></div>
    </div>

    <div class="side-panel">
      <div class="answer-block answer" id="answerBlock" style="display:none">
        <div class="block-label">参考答案</div>
        <div class="block-content" id="answerContent">-</div>
      </div>
      <div class="answer-block analysis" id="analysisBlock" style="display:none">
        <div class="block-label">题目解析</div>
        <div class="block-content" id="analysisContent">-</div>
      </div>
      <div class="stats-block" id="statsBlock" style="display:none">
        <div class="stats-tabs">
          <div class="stat-tab correct active-correct" id="tabCorrect" onclick="switchTab('correct')">答对 (<span id="correctCount">0</span>)</div>
          <div class="stat-tab wrong" id="tabWrong" onclick="switchTab('wrong')">答错 (<span id="wrongCount">0</span>)</div>
        </div>
        <div class="user-list" id="statsList"></div>
      </div>
      <div class="wrong-answer-block" id="wrongAnswerBlock" style="display:none">
        <div class="wa-header">
          <div class="wa-dot"></div>
          <div class="wa-label">学生原始作答</div>
          <div class="wa-account" id="waAccount">-</div>
        </div>
        <div class="wa-content" id="waContent">-</div>
        <div class="wa-dismiss"><button onclick="dismissWrongAnswer()">收起</button></div>
      </div>
    </div>
  </div>
</div>

<script>
var currentExamId = null;
var currentQuestionIndex = 0;
var correctUsers = [];
var wrongUsers = [];
var activeTab = 'correct';
var lastRenderedIndex = -1;

var wsUrl = (location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/explain-ws';
var ws = new WebSocket(wsUrl);
var reconnectAttempts = 0;      // 指数退避计数
var MAX_RECONNECT_DELAY = 30000; // 重连间隔上限 30s

function connectWs() {
  // 先关闭旧连接（若存在且未关闭），避免多个 socket 并存
  var old = ws;
  ws = new WebSocket(wsUrl);
  ws.onopen = function() {
    console.log('[大屏] WS 已连接');
    reconnectAttempts = 0;
    ws.send(JSON.stringify({ type: 'screen_join' }));
  };
  ws.onmessage = function(e) {
    try {
      var msg = JSON.parse(e.data);
      handleMsg(msg);
    } catch(ex) {
      console.error('[大屏] 消息处理异常:', ex);
    }
  };
  ws.onclose = function() {
    // 只处理"当前"连接关闭，忽略旧连接的滞后 onclose
    if (old !== ws) return;
    console.log('[大屏] WS 断开，自动重连（不刷新页面）');
    // 指数退避：5s, 10s, 20s ... 上限 30s；无限重试，永不停止
    var delay = Math.min(5000 * Math.pow(2, reconnectAttempts), MAX_RECONNECT_DELAY);
    reconnectAttempts++;
    setTimeout(function() { connectWs(); }, delay);
  };
  ws.onerror = function() {
    // 连接错误统一交给 onclose 处理
  };
}

ws.onopen = function() {
  console.log('[大屏] WS 已连接');
  reconnectAttempts = 0;
  ws.send(JSON.stringify({ type: 'screen_join' }));
};
ws.onmessage = function(e) {
  try {
    var msg = JSON.parse(e.data);
    handleMsg(msg);
  } catch(ex) {
    console.error('[大屏] 消息处理异常:', ex);
  }
};
ws.onclose = function() {
  // 首次连接断开：指数退避无限重连。每次重连都会重新 send screen_join，
  // 服务端会把大屏暂存到 pendingScreenWs；老师重新 startExplaining 会立即补发 start，
  // 因此即使曾掉线，重新发起讲解后大屏也能恢复显示。
  console.log('[大屏] WS 断开，自动重连（不刷新页面）');
  var delay = Math.min(5000 * Math.pow(2, reconnectAttempts), MAX_RECONNECT_DELAY);
  reconnectAttempts++;
  setTimeout(function() { connectWs(); }, delay);
};

var typeMap = {single:'单选题',multi:'多选题',fill:'填空题',short:'简答题'};
function typeLabel(t) { return typeMap[t] || t || ''; }

function handleMsg(msg) {
  lastMsg = msg;
  try {
    switch(msg.type) {
      case 'connected':
        console.log('[大屏] 已关联讲解:', msg.examId);
        break;
      case 'start': onStart(msg); break;
      case 'question': onQuestion(msg); break;
      case 'show-answer': showAnswer(msg); break;
      case 'hide-answer': hideAnswer(); break;
      case 'show-analysis': showAnalysis(msg); break;
      case 'hide-analysis': hideAnalysis(); break;
      case 'show-stats': showStats(msg); break;
      case 'hide-stats': hideStats(); break;
      case 'switch-tab': onSwitchTab(msg); break;
      case 'next': onQuestion(msg); break;
      case 'prev': onQuestion(msg); break;
      case 'jump': onQuestion(msg); break;
      case 'reset': onReset(); break;
      case 'end': onEnd(); break;
      case 'wrong-answer': showWrongAnswer(msg); break;
      case 'hide-wrong-answer': dismissWrongAnswer(); break;
      case 'ping': ws.send(JSON.stringify({type:'pong'})); break;
    }
  } catch(ex) {
    console.error('[大屏] handleMsg异常:', ex, 'msg.type:', msg.type);
  }
}

function onStart(msg) {
  currentExamId = msg.examId;
  currentQuestionIndex = msg.questionIndex || 0;
  document.getElementById('noState').style.display = 'none';
  document.getElementById('liveContainer').style.display = 'flex';
  document.getElementById('headerTitle').textContent = msg.examName || '讲解中';
  hideAnswer(); hideAnalysis(); hideStats(); dismissWrongAnswer();
  lastRenderedIndex = -1;
  renderQuestion(msg);
}

function onQuestion(msg) {
  currentQuestionIndex = msg.questionIndex;
  hideAnswer(); hideAnalysis(); hideStats(); dismissWrongAnswer();
  var q = msg.question;
  if (!q) return;
  var isSameQuestion = (lastRenderedIndex === msg.questionIndex);
  lastRenderedIndex = msg.questionIndex;
  var card = document.getElementById('questionCard');
  if (!isSameQuestion) {
    card.style.transition = 'none';
    card.style.opacity = '0';
    card.style.transform = 'translateY(20px)';
    renderQuestion(msg);
    requestAnimationFrame(function() {
      card.style.transition = 'opacity .3s ease, transform .3s ease';
      card.style.opacity = '1';
      card.style.transform = 'translateY(0)';
    });
  } else {
    renderQuestion(msg);
  }
}

function renderQuestion(msg) {
  var q = msg.question;
  if (!q) return;
  document.getElementById('qNum').textContent = '第 ' + (q.index + 1) + ' 题';
  document.getElementById('qTitle').innerHTML = renderMath(q.title || '');
  document.getElementById('headerTitle').textContent = msg.examName || document.getElementById('headerTitle').textContent;
  document.getElementById('qCounter').textContent = '第 ' + (q.index + 1) + ' 题 / 共 ' + msg.totalQuestions + ' 题';
  document.getElementById('qTypeTag').textContent = typeLabel(q.type);
  document.getElementById('qScoreTag').textContent = (q.score || 0) + '分';

  var imgEl = document.getElementById('qImage');
  if (q.imgUrl) {
    var imgSrc = q.imgUrl.indexOf('http') === 0 ? q.imgUrl : ${JSON.stringify(SERVER_HOST)} + q.imgUrl;
    imgEl.innerHTML = '<img src="' + imgSrc + '" style="max-width:100%;max-height:400px;border-radius:14px" onerror="onImgError(this)">';
  } else {
    imgEl.innerHTML = '';
  }

  var grid = document.getElementById('optionsGrid');
  var labels = ['A','B','C','D','E','F'];
  var opts = q.options || [];
  var html = '';
  for (var i = 0; i < opts.length; i++) {
    html += '<div class="option-item"><span class="opt-label">' + (labels[i]||'') + '</span><span>' + renderMath(opts[i]) + '</span></div>';
  }
  grid.innerHTML = html;
}

function showAnswer(msg) {
  var answer = msg.answer || (msg.question && msg.question.standardAnswer) || (msg.question && msg.question.answer) || '';
  document.getElementById('answerContent').innerHTML = renderMath(answer);
  document.getElementById('answerBlock').style.display = 'block';
}
function hideAnswer() { document.getElementById('answerBlock').style.display = 'none'; }

function showAnalysis(msg) {
  var analysis = msg.analysis || (msg.question && msg.question.analysis) || '';
  document.getElementById('analysisContent').innerHTML = renderMath(analysis);
  document.getElementById('analysisBlock').style.display = 'block';
}
function hideAnalysis() { document.getElementById('analysisBlock').style.display = 'none'; }

function showStats(msg) {
  correctUsers = msg.correctUsers || [];
  wrongUsers = msg.wrongUsers || [];
  document.getElementById('correctCount').textContent = correctUsers.length;
  document.getElementById('wrongCount').textContent = wrongUsers.length;
  document.getElementById('statsBlock').style.display = 'block';
  activeTab = 'correct';
  document.getElementById('tabCorrect').className = 'stat-tab correct active-correct';
  document.getElementById('tabWrong').className = 'stat-tab wrong';
  renderStats();
}
function hideStats() { document.getElementById('statsBlock').style.display = 'none'; }

function onSwitchTab(msg) {
  var tab = msg.tab || 'correct';
  activeTab = tab;
  document.getElementById('tabCorrect').className = 'stat-tab correct' + (tab==='correct'?' active-correct':'');
  document.getElementById('tabWrong').className = 'stat-tab wrong' + (tab==='wrong'?' active-wrong':'');
  renderStats();
}

function switchTab(tab) {
  activeTab = tab;
  document.getElementById('tabCorrect').className = 'stat-tab correct' + (tab==='correct'?' active-correct':'');
  document.getElementById('tabWrong').className = 'stat-tab wrong' + (tab==='wrong'?' active-wrong':'');
  renderStats();
}

function renderStats() {
  var list = document.getElementById('statsList');
  var users = activeTab === 'correct' ? correctUsers : wrongUsers;
  if (!users || users.length === 0) {
    list.innerHTML = '<div class="stats-empty">暂无数据</div>';
    return;
  }
  var html = '';
  for (var i = 0; i < users.length; i++) {
    var u = users[i];
    var name = escapeHtml(u.account||'');
    if (u.remark) name += ' (' + escapeHtml(u.remark) + ')';
    html += '<div class="user-item"><span class="user-name">' + name + '</span></div>';
  }
  list.innerHTML = html;
}

function onReset() {
  currentQuestionIndex = 0;
  hideAnswer(); hideAnalysis(); hideStats(); dismissWrongAnswer();
  lastRenderedIndex = -1;
  document.getElementById('noState').style.display = 'flex';
  document.getElementById('liveContainer').style.display = 'none';
}

function onEnd() {
  currentExamId = null;
  currentQuestionIndex = 0;
  hideAnswer(); hideAnalysis(); hideStats(); dismissWrongAnswer();
  lastRenderedIndex = -1;
  document.getElementById('noState').style.display = 'flex';
  document.getElementById('liveContainer').style.display = 'none';
}

function showWrongAnswer(msg) {
  document.getElementById('waAccount').textContent = msg.account || '';
  document.getElementById('waContent').innerHTML = renderMath(msg.userAnswer || '');
  document.getElementById('wrongAnswerBlock').style.display = 'block';
  document.getElementById('wrongAnswerBlock').scrollIntoView({ behavior: 'smooth', block: 'center' });
}
function dismissWrongAnswer() {
  document.getElementById('wrongAnswerBlock').style.display = 'none';
}

// 公式渲染缓存，避免重复解析相同公式
var mathCache = Object.create(null);

function renderMath(text) {
  if (!text) return '';
  var str = String(text);
  // 纯文本无公式，直接返回（注意：本文件是模板字符串，'\\' 输出为 \'，需用 '\\\\' 才能在浏览器中得到 '\\')
  if (str.indexOf('$') === -1 && str.indexOf('\\\\') === -1) return escapeHtml(str);
  if (typeof katex === 'undefined') return escapeHtml(str);
  // 缓存命中直接返回
  if (mathCache[str]) return mathCache[str];
  var result = '';
  var regex = /\\$\\$([\\s\\S]*?)\\$\\$|\\$([^$]+?)\\$/g;
  var lastIndex = 0;
  var match;
  while ((match = regex.exec(str)) !== null) {
    if (match.index > lastIndex) {
      result += escapeHtml(str.slice(lastIndex, match.index));
    }
    var formula = match[1] !== undefined ? match[1] : match[2];
    if (formula) {
      try {
        result += katex.renderToString(formula, { throwOnError: false, displayMode: false });
      } catch (e) {
        result += escapeHtml(match[0]);
      }
    }
    lastIndex = regex.lastIndex;
  }
  if (lastIndex < str.length) {
    result += escapeHtml(str.slice(lastIndex));
  }
  mathCache[str] = result;
  return result;
}

var lastMsg = null;
function renderAll() {
  if (lastMsg) handleMsg(lastMsg);
}

function escapeHtml(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

function onImgError(img) {
  img.onerror = null;
  img.parentElement.textContent = '图片加载失败';
}
<\/script>
</body>
</html>`;
}

// ==================== HTTP 请求处理器 ====================
async function explainHandler(params) {
  const action = params.action;
  if (!action) return { success: false, msg: '缺少 action' };

  const examCollection = dbPool.getCollection(colName);
  const recordCollection = dbPool.getCollection(recordColName);

  if (action === 'startExplaining') {
    if (!params.examId) return { success: false, msg: '缺少 examId' };
    const exam = await examCollection.findOne({ _id: new ObjectId(params.examId) });
    if (!exam) return { success: false, msg: '试卷不存在' };

    Logger.info('EXPLAIN_WS', `startExplaining 开始, examId=${params.examId}, 当前session=${!!getSession()}`);

    const questions = exam.questions || [];
    const firstQ = questions[0] || {};
    const questionData = {
      index: 0, type: firstQ.type || '', title: firstQ.title || '',
      score: firstQ.score || 0, imgUrl: firstQ.imgUrl || null,
      options: firstQ.options || [],
      standardAnswer: firstQ.standardAnswer || firstQ.answer || '',
      analysis: firstQ.analysis || '',
    };

    const allQuestions = (exam.questions || []).map((q, i) => ({
      index: i, type: q.type || '', title: q.title || '',
      score: q.score || 0, imgUrl: q.imgUrl || null,
      options: q.options || [],
      standardAnswer: q.standardAnswer || q.answer || '',
      analysis: q.analysis || '',
    }));

    let screenWs = null;
    const psw = getPendingScreenWs();
    // 🔥 同时检查 socket.writable，防止 readyState===OPEN 但实际半开的陈旧连接被当作有效
    if (psw && psw.readyState === WebSocket.OPEN && psw._socket?.writable !== false) {
      screenWs = psw;
    } else if (psw) {
      // 连接已死，清理掉，避免阻塞下一次 screen_join
      Logger.info('EXPLAIN_WS', '🧹 pendingScreenWs 为陈旧连接，已清理');
      clearPendingScreenWs(psw);
    }
    setSession({ examId: params.examId, examName: exam.examName, screenWs, questions: allQuestions, currentQuestion: questionData, currentQuestionIndex: 0, totalQuestions: questions.length });
    const session = getSession();
    Logger.info('EXPLAIN_WS', `session 已创建, examId=${session.examId}, screenWs=${!!session.screenWs}, adminWs=${!!session.adminWs}`);
    const screenOnline = !!(session.screenWs && session.screenWs.readyState === WebSocket.OPEN);

    if (screenOnline) {
      session.screenWs.send(JSON.stringify({
        type: 'start', examId: params.examId, examName: exam.examName,
        questionIndex: 0, totalQuestions: questions.length, question: questionData,
      }));
      Logger.info('EXPLAIN_WS', `已推送 start 到大屏, examId=${params.examId}`);
    } else {
      Logger.warn('EXPLAIN_WS', `大屏未连接，无法推送 start, examId=${params.examId}`);
    }
    return { success: true, data: { examName: exam.examName, questionCount: questions.length, screenOnline } };
  }

  if (action === 'endExplaining') {
    const session = getSession();
    if (session && session.screenWs && session.screenWs.readyState === WebSocket.OPEN) {
      session.screenWs.send(JSON.stringify({ type: 'end' }));
    }
    removeSession();
    return { success: true, msg: '讲解已结束' };
  }

  if (action === 'getExamQuestions') {
    if (!params.examId) return { success: false, msg: '缺少 examId' };
    const exam = await examCollection.findOne({ _id: new ObjectId(params.examId) });
    if (!exam) return { success: false, msg: '试卷不存在' };
    const questions = (exam.questions || []).map((q, i) => ({
      index: i, type: q.type || '',
      title: (q.title || '').replace(/\*\*/g, '').substring(0, 60),
      score: q.score || 0,
    }));
    return { success: true, data: { examId: exam._id.toString(), examName: exam.examName || '', questions } };
  }

  if (action === 'getQuestionDetail') {
    if (!params.examId) return { success: false, msg: '缺少 examId' };
    if (params.questionIndex === undefined) return { success: false, msg: '缺少 questionIndex' };
    const idx = parseInt(params.questionIndex);
    const exam = await examCollection.findOne({ _id: new ObjectId(params.examId) });
    if (!exam) return { success: false, msg: '试卷不存在' };
    const q = (exam.questions || [])[idx];
    if (!q) return { success: false, msg: '题目不存在' };
    return { success: true, data: {
      index: idx, type: q.type || '', title: q.title || '',
      score: q.score || 0, imgUrl: q.imgUrl || null, options: q.options || [],
      standardAnswer: q.standardAnswer || q.answer || '', analysis: q.analysis || '',
    }};
  }

  if (action === 'getQuestionStats') {
    if (!params.examId) return { success: false, msg: '缺少 examId' };
    if (params.questionIndex === undefined) return { success: false, msg: '缺少 questionIndex' };
    const idx = parseInt(params.questionIndex);
    const records = await recordCollection.find({ examId: params.examId }).toArray();
    const correctUsers = [];
    const wrongUsers = [];
    for (const rec of records) {
      const qs = Array.isArray(rec.questions) ? rec.questions : [];
      const q = qs[idx];
      if (!q) continue;
      const user = { account: rec.account, remark: rec.remark || '', userAnswer: q.userAnswer || '' };
      if (q.userScore > 0) correctUsers.push(user);
      else wrongUsers.push(user);
    }
    return { success: true, data: { correctUsers, wrongUsers, total: records.length, correctCount: correctUsers.length, wrongCount: wrongUsers.length } };
  }

  if (action === 'getExplainStatus') {
    const session = getSession();
    if (session) {
      return { success: true, data: {
        active: true, examId: session.examId, examName: session.examName,
        currentQuestionIndex: session.currentQuestionIndex ?? 0,
        totalQuestions: session.totalQuestions ?? 0,
        screenOnline: !!(session.screenWs && session.screenWs.readyState === WebSocket.OPEN),
      }};
    }
    return { success: true, data: { active: false, screenOnline: false } };
  }

  return { success: false, msg: '无效的 action: ' + action };
}

module.exports = { explainHandler, getExplainHtml, getSession, setSession, removeSession, getPendingScreenWs, setPendingScreenWs, clearPendingScreenWs };
