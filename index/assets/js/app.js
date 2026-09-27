/* ==========================================================================
   智答星途 · 官网交互
   - 站点：Bento / swipe / 功能矩阵 / 三端 / 技术 / 联动演示
   - 模拟器：双实例（桌面右侧手机 + 移动全屏抽屉）
   ========================================================================== */
(function () {
  'use strict';

  var D = window.ZDXT;
  var NAV_TABS = ['考试', '学习', '通知', '我的'];

  function $(sel, root) { return (root || document).querySelector(sel); }
  function $$(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }

  /* ==================== 图标 ==================== */
  var ICO = {
    sparkle: '<path d="M12 3l1.6 4.6L18 9.2l-4.4 1.6L12 15.4l-1.6-4.6L6 9.2l4.4-1.6Z"/><path d="M18.5 15.5l.7 2 2 .7-2 .7-.7 2-.7-2-2-.7 2-.7Z"/>',
    pen: '<path d="M15.2 4.6 19.4 8.8 8.6 19.6 4 20.8l1.2-4.6Z"/><path d="m13.4 6.4 4.2 4.2"/>',
    card: '<rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="M8 9.4h8M8 13.2h5"/>',
    cast: '<path d="M3 5.5h18v11H3z"/><path d="M8 20.5h8"/><path d="M12 16.5v4"/>',
    chart: '<path d="M5 20V11M11 20V6M17 20v-6"/><path d="M3.5 20h17"/>',
    sheet: '<path d="M14 3H7.5A2.5 2.5 0 0 0 5 5.5v13A2.5 2.5 0 0 0 7.5 21h9a2.5 2.5 0 0 0 2.5-2.5V8Z"/><path d="M14 3v5h5"/><path d="M12.7 11.3 10 15.6h3.2l-.8 4 3.1-4.8h-3.1Z"/>',
    bell: '<path d="M18 16.2V11a6 6 0 1 0-12 0v5.2L4.6 18h14.8Z"/><path d="M10 21h4"/>',
    box: '<path d="M3.5 7.5 12 3.4l8.5 4.1v9L12 20.6 3.5 16.5Z"/><path d="M3.5 7.5 12 11.6l8.5-4.1M12 11.6v9"/>'
  };
  function svg(k) {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" ' +
      'stroke-linecap="round" stroke-linejoin="round">' + (ICO[k] || '') + '</svg>';
  }

  function chip(txt, kind) { return '<span class="al-chip al-chip--' + (kind || 'blue') + '">' + txt + '</span>'; }

  /* ==================== 站点：Bento（桌面） ==================== */
  function renderBento() {
    var el = $('#bento');
    if (!el) return;
    el.innerHTML = D.caps.map(function (c) {
      return '<article class="bcard bcard--' + c.size + ' bcard--' + c.accent + '" data-glow>' +
        '<div class="bcard__ico">' + svg(c.ico) + '</div>' +
        '<h3>' + c.title + '</h3>' +
        '<p>' + c.desc + '</p>' +
        (c.points ? '<ul class="bcard__pts">' + c.points.map(function (p) { return '<li>' + p + '</li>'; }).join('') + '</ul>' : '') +
        '<div class="bcard__tags">' + c.tags.map(function (t) { return '<span>' + t + '</span>'; }).join('') + '</div>' +
        '</article>';
    }).join('');

    // 光标跟随光泽
    $$('[data-glow]', el).forEach(function (card) {
      card.addEventListener('mousemove', function (e) {
        var r = card.getBoundingClientRect();
        card.style.setProperty('--mx', (e.clientX - r.left) + 'px');
        card.style.setProperty('--my', (e.clientY - r.top) + 'px');
      });
    });
  }

  /* ==================== 站点：swipe（移动） ==================== */
  function renderSwipe() {
    var el = $('#swipe');
    var dots = $('#swipeDots');
    if (!el) return;
    el.innerHTML = D.caps.map(function (c) {
      return '<article class="scard">' +
        '<div class="bcard__ico bcard--' + c.accent + '" style="background:rgba(255,255,255,.08);border-color:var(--line)">' + svg(c.ico) + '</div>' +
        '<h3>' + c.title + '</h3>' +
        '<p style="margin-top:8px">' + c.desc + '</p>' +
        (c.points ? '<ul class="bcard__pts">' + c.points.map(function (p) { return '<li>' + p + '</li>'; }).join('') + '</ul>' : '') +
        '<div class="bcard__tags">' + c.tags.map(function (t) { return '<span>' + t + '</span>'; }).join('') + '</div>' +
        '</article>';
    }).join('');
    if (dots) dots.innerHTML = D.caps.map(function (_, i) {
      return '<i' + (i === 0 ? ' class="on"' : '') + '></i>';
    }).join('');

    var cards = $$('.scard', el);
    var dotEls = $$('i', dots);
    var cur = 0;
    function mark(i) {
      cur = i;
      cards.forEach(function (c, n) { c.classList.toggle('is-cur', n === i); });
      dotEls.forEach(function (d, n) { d.classList.toggle('on', n === i); });
    }
    mark(0);
    var tick;
    el.addEventListener('scroll', function () {
      clearTimeout(tick);
      tick = setTimeout(function () {
        if (!cards.length) return;
        var mid = el.scrollLeft + el.clientWidth / 18;
        var best = 0, bd = Infinity;
        cards.forEach(function (c, n) {
          var d = Math.abs(c.offsetLeft - mid);
          if (d < bd) { bd = d; best = n; }
        });
        if (best !== cur) mark(best);
      }, 70);
    }, { passive: true });
  }

  /* ==================== 站点：功能矩阵 ==================== */
  var mxRole = 'admin';

  function renderMatrixSeg() {
    var el = $('#matrixSeg');
    el.innerHTML = D.matrix.map(function (m) {
      return '<button data-role="' + m.role + '"' + (m.role === mxRole ? ' class="is-on"' : '') + '>' +
        m.name + '<em style="font-style:normal;opacity:.55;font-size:11px;margin-left:5px">' + m.who + '</em></button>';
    }).join('');
    el.addEventListener('click', function (e) {
      var b = e.target.closest('button[data-role]');
      if (!b) return;
      mxRole = b.dataset.role;
      $$('button', el).forEach(function (x) { x.classList.toggle('is-on', x === b); });
      renderMatrixBody();
    });
  }

  function curRole() {
    for (var i = 0; i < D.matrix.length; i++) if (D.matrix[i].role === mxRole) return D.matrix[i];
    return D.matrix[0];
  }

  function renderMatrixBody() {
    var m = curRole();

    /* 桌面：多列清单 */
    $('#mxDesk').innerHTML =
      '<div class="mx-g" style="grid-column:1/-1;background:linear-gradient(135deg,rgba(24,144,255,.08),rgba(124,92,255,.06));border-color:rgba(24,144,255,.24)">' +
        '<div class="mx-g__top" style="border-bottom:0">' +
          '<span class="mx-g__n" style="width:auto;padding:0 10px;height:26px">' + m.who + '</span>' +
          '<h3 style="font-size:19px">' + m.name + ' · ' + m.groups.length + ' 大项 / ' +
            m.groups.reduce(function (a, g) { return a + g.items.length; }, 0) + ' 个功能点</h3>' +
        '</div>' +
        '<p style="font-size:13.5px;line-height:1.85;color:var(--ink-2)">' + m.desc + '</p>' +
      '</div>' +
      m.groups.map(function (g, i) {
        return '<div class="mx-g">' +
          '<div class="mx-g__top">' +
            '<span class="mx-g__n">' + (i + 1) + '</span>' +
            '<h3>' + g.t + '<em style="font-style:normal;font-size:11px;color:var(--ink-3);margin-left:6px">' + g.items.length + ' 项</em></h3>' +
          '</div>' +
          '<ul>' + g.items.map(function (t) { return '<li>' + t + '</li>'; }).join('') + '</ul>' +
        '</div>';
      }).join('');

    /* 移动：手风琴 */
    $('#mxMob').innerHTML = m.groups.map(function (g, i) {
      return '<div class="acc' + (i === 0 ? ' is-open' : '') + '">' +
        '<button class="acc__btn" data-acc>' +
          '<span class="acc__n">' + (i + 1) + '</span>' +
          '<span class="acc__t">' + g.t + '</span>' +
          '<span class="acc__c">' + g.items.length + '</span>' +
          '<span class="acc__a">▾</span>' +
        '</button>' +
        '<div class="acc__panel"><div><ul>' +
          g.items.map(function (t) { return '<li>' + t + '</li>'; }).join('') +
        '</ul></div></div>' +
      '</div>';
    }).join('');

    $$('#mxMob [data-acc]').forEach(function (b) {
      b.addEventListener('click', function () {
        var acc = b.parentNode;
        var open = acc.classList.contains('is-open');
        $$('#mxMob .acc').forEach(function (a) { a.classList.remove('is-open'); });
        if (!open) acc.classList.add('is-open');
      });
    });
  }

  /* ==================== 站点：三端协同 ==================== */
  function renderRoles() {
    var av = { admin: '管', student: '学', parent: '家' };
    $('#rolesGrid').innerHTML = D.roles.map(function (r) {
      return '<article class="rcard rcard--' + r.role + '">' +
        '<div class="rcard__top">' +
          '<div class="rcard__av">' + av[r.role] + '</div>' +
          '<div><h3>' + r.name + '</h3><div class="rcard__who">' + r.who + '</div></div>' +
        '</div>' +
        '<p class="rcard__lead">' + r.lead + '</p>' +
        '<div class="rcard__kw">' + r.kw.map(function (k) { return '<span>' + k + '</span>'; }).join('') + '</div>' +
      '</article>';
    }).join('');
  }

  /* ==================== 站点：技术架构 ==================== */
  function renderTech() {
    $('#techGrid').innerHTML = D.tech.map(function (t) {
      return '<div class="titem">' +
        '<span class="titem__n">' + t.n + '</span>' +
        '<b>' + t.k + '</b>' +
        '<p>' + t.d + '</p>' +
        '<div class="titem__tags">' + t.tags.map(function (x) { return '<span>' + x + '</span>'; }).join('') + '</div>' +
      '</div>';
    }).join('');
  }

  /* ============================================================
     模拟器 —— 工厂函数（支持多实例）
     ============================================================ */
  var SUBS = ['detail', 'publish', 'explain', 'export', 'sign', 'stusign', 'settings', 'users', 'browser'];

  function createSim(cfg) {
    var P = cfg.prefix;                       // id 前缀，避免多实例冲突
    var host = cfg.host;                      // 挂载容器 #screens
    var statusEl = $('#' + P + 'statusbar');
    var homeEl = $('#' + P + 'homebar');

    var st = {
      view: 'login',
      role: 'student',
      subjectLabel: '语文',
      tab: 0,
      loggedIn: false,
      exam: { idx: 0, ans: {}, done: false, left: 0, timer: null },
      ai: { booted:false, busy:false, mode:'text' },
      detail: { role: 'student', ans: 0 },
      publish: { mode: 'ai', stage: 0 },
      explain: { i: 0, show: { ans: false, exp: false, sta: false } },
      exp: { stage: 0 },
      sgn: { way: 'qr', running: false, subject: '数学', title: '', code: '8315', countdown: 60 },
      usr: { filter: 'all' },
      astudy: { mainTab: 0, activeTab: 0, week: 0 },
      anotice: { tab: 1, sub: 1, ntype: 'system' },
      pexam: { sel: 0 },
      pstudy: { sel: 0 },
      brow: { tab: 0, loading: false, dl: null },
      ssg: { tab: 0, subject: '数学' },
      set: { sub: 0, showPwd: false }
    };

    /* ---------- 通用零件 ---------- */
    function head(role, title, sub) {
      var ini = role === 'admin' ? '李' : role === 'parent' ? '王' : '张';
      return '<div class="al-h1"><div><h5>' + title + '</h5>' +
        (sub ? '<div class="al-sub2">' + sub + '</div>' : '') + '</div>' +
        '<div class="al-avatar">' + ini + '</div></div>';
    }
    function notice(kind, cls, title, time, body) {
      return '<div class="al-notice"><div class="al-notice__top">' + chip(kind, cls) +
        '<b>' + title + '</b><time>' + time + '</time></div><p>' + body + '</p></div>';
    }
    function item(ico, title, sub, act, arg, idx) {
      return '<div class="al-item" data-act="' + (act || 'todo') + '"' +
        (arg ? ' data-arg="' + arg + '"' : '') +
        (idx != null ? ' data-idx="' + idx + '"' : '') + ' data-label="' + title + '">' +
        '<div class="al-item__ico">' + ico + '</div>' +
        '<div class="al-item__tx"><b>' + title + '</b>' + (sub ? '<span>' + sub + '</span>' : '') + '</div>' +
        '<div class="al-item__arrow">›</div></div>';
    }
    function ring(pct, big, small) {
      var C = 2 * Math.PI * 38;
      return '<div class="al-ring"><svg width="92" height="92" viewBox="0 0 92 92">' +
        '<circle cx="46" cy="46" r="38" fill="none" stroke="rgba(24,144,255,.14)" stroke-width="9"/>' +
        '<circle cx="46" cy="46" r="38" fill="none" stroke="#1890FF" stroke-width="9" stroke-linecap="round" ' +
        'stroke-dasharray="' + C.toFixed(1) + '" stroke-dashoffset="' + (C * (1 - pct / 100)).toFixed(1) + '"/>' +
        '</svg><div class="val"><b>' + big + '</b><span>' + small + '</span></div></div>';
    }
    function bars(arr, h) {
      return '<div class="al-bars"' + (h ? ' style="height:' + h + 'px"' : '') + '>' +
        arr.map(function (v) {
          var dim = typeof v === 'string' && v.indexOf('dim') === 0;
          var n = dim ? v.replace('dim', '') : v;
          return '<i class="' + (dim ? 'dim' : '') + '" style="height:' + n + '%"></i>';
        }).join('') + '</div>';
    }
    /* 饼图：segs = [[占比, 颜色, 文案], ...] */
    function pie(segs, size) {
      var total = segs.reduce(function (a, s) { return a + s[0]; }, 0) || 1;
      var acc = 0;
      var stops = segs.map(function (s) {
        var from = acc / total * 100;
        acc += s[0];
        return s[1] + ' ' + from.toFixed(2) + '% ' + (acc / total * 100).toFixed(2) + '%';
      }).join(', ');
      return '<div class="al-pie-wrap">' +
        '<div class="al-pie" style="width:' + size + 'px;height:' + size + 'px;background:conic-gradient(' + stops + ')"></div>' +
        '<div class="al-pie__lg">' + segs.map(function (s) {
          return '<span><i style="background:' + s[1] + '"></i>' + s[2] + '</span>';
        }).join('') + '</div></div>';
    }

    /* ---------- 管理端·学习管理 三个子模块 ---------- */
    var ASTUDY_SUBJECTS = ['语文', '数学', '英语', '其他'];
    var ASTUDY_WEEK = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    var ASTUDY_WEEKS = [
      { lb: '第 1 周', dt: '09-01 ~ 09-07' },
      { lb: '第 2 周', dt: '09-08 ~ 09-14' },
      { lb: '第 3 周', dt: '09-15 ~ 09-21' },
      { lb: '第 4 周', dt: '09-22 ~ 09-28' },
      { lb: '第 5 周', dt: '09-29 ~ 10-05' }
    ];
    function adminStudyBody() {
      var mt = st.astudy.mainTab;
      if (mt === 0) {
        /* 学习要求配置：任务时间范围（标题 + 新增）→ 周配置（周选择）→ 周日期编辑器 */
        return '<div class="al-rowline">' +
            '<b class="al-rowline__t">任务时间范围</b>' +
            '<button class="al-chipbtn" data-act="todo" data-label="新增时间范围">＋ 新增</button>' +
          '</div>' +
          '<div class="al-card" style="padding:12px 14px;margin-bottom:6px;display:flex;align-items:center;gap:8px">' +
            '<div style="flex:1;min-width:0">' +
              '<div style="font-size:14px;font-weight:700;color:#0B2545">2025 秋季学期</div>' +
              '<div style="font-size:11.5px;color:#8A9AAB;margin-top:4px">2025-09-01 ~ 2026-01-15</div>' +
            '</div>' +
            '<button class="al-iconbtn" data-act="todo" data-label="编辑时间范围">✎</button>' +
            '<button class="al-iconbtn al-iconbtn--danger" data-act="todo" data-label="删除时间范围">🗑</button>' +
          '</div>' +
          '<div class="al-rowline" style="margin-top:16px"><b class="al-rowline__t">周配置</b></div>' +
          '<div class="al-tabs" style="margin-bottom:4px">' +
            ASTUDY_WEEKS.map(function (w, i) {
              return '<button class="al-tab' + (st.astudy.week === i ? ' is-on' : '') + '" data-act="astudy-week" data-idx="' + i + '">' + w.lb + '</button>';
            }).join('') +
          '</div>' +
          '<div style="font-size:11.5px;color:#8A9AAB;margin:4px 3px 8px">周日期：' + ASTUDY_WEEKS[st.astudy.week].lb + ' (' + ASTUDY_WEEKS[st.astudy.week].dt + ')</div>' +
          '<div class="al-card" style="padding:12px">' +
            '<div class="al-weekcfg">' +
              ASTUDY_WEEK.map(function (d) {
                return '<div class="al-wkrow"><span class="al-wkrow__d">' + d + '</span>' +
                  ASTUDY_SUBJECTS.map(function (s) {
                    return '<div class="al-wkcell"><span>' + s + '</span><b>0 分</b></div>';
                  }).join('') +
                '</div>';
              }).join('') +
            '</div>' +
            '<div style="display:flex;gap:8px;margin-top:12px">' +
              '<button class="al-btn" style="flex:1" data-act="todo" data-label="高级应用">高级应用</button>' +
              '<button class="al-btn al-btn--primary" style="flex:1" data-act="todo" data-label="保存配置">保存配置</button>' +
            '</div>' +
          '</div>';
      }
      if (mt === 1) {
        /* 科目视频管理：四科切换 + 视频上传 + 列表 */
        return '<div class="al-tabs" style="margin-bottom:12px">' +
          ASTUDY_SUBJECTS.map(function (t, i) {
            return '<button class="al-tab' + (st.astudy.activeTab === i ? ' is-on' : '') + '" data-act="astudy-subj" data-idx="' + i + '">' + t + '</button>';
          }).join('') +
        '</div>' +
        '<div class="al-card" style="padding:16px;margin-bottom:12px">' +
          '<div style="font-size:16px;font-weight:700;color:#0B2545;margin-bottom:12px">📹 视频上传</div>' +
          '<div style="display:flex;gap:12px">' +
            '<button class="al-btn al-btn--primary" style="flex:1" data-act="todo" data-label="上传本地视频">上传本地视频</button>' +
            '<button class="al-btn" style="flex:1;background:#52C41A;color:#fff;border:0" data-act="todo" data-label="上传在线视频">上传在线视频</button>' +
          '</div>' +
        '</div>' +
        '<div class="al-group-title">视频列表 · ' + ASTUDY_SUBJECTS[st.astudy.activeTab] + '</div>' +
        ['二次函数的图象与性质', '一元二次方程的解法', '函数与方程的相互转化'].map(function (n) {
          return '<div class="al-card" style="padding:12px 14px;display:flex;align-items:center;gap:12px;margin-bottom:10px">' +
            '<div class="al-video__thumb" style="width:42px;height:42px;font-size:15px">▶</div>' +
            '<div style="flex:1;min-width:0"><div style="font-size:13.5px;font-weight:600;color:#17324B">'+n+'</div>' +
            '<div style="font-size:11px;color:#8A9AAB;margin-top:3px">时长 24 分钟 · 已学 18 分钟</div></div>' +
            chip('已完成', 'green') +
          '</div>';
        }).join('');
      }
      /* mt === 2 用户学习进度：搜索栏 + 用户卡片（含各科进度） */
      return '<div class="al-card" style="padding:9px 12px;margin-bottom:12px;display:flex;align-items:center;gap:8px">' +
          '<span style="font-size:14px;color:#8A9AAB">🔍</span>' +
          '<span style="font-size:13px;color:#8A9AAB">输入用户/手机号搜索</span>' +
        '</div>' +
        [['张明','138****2018',[38,41,36,29]], ['李华','139****6688',[41,36,32,27]]].map(function (u) {
          return '<div class="al-card" style="padding:12px 14px;margin-bottom:12px">' +
            '<div style="font-size:13.5px;font-weight:700;color:#0B2545;margin-bottom:4px">' + u[0] + ' | ' + u[1] + '</div>' +
            ASTUDY_SUBJECTS.map(function (s, i) {
              var now = u[2][i], target = 45;
              var pct = Math.min(100, Math.round(now / target * 100));
              var col = pct >= 100 ? '#52C41A' : (pct >= 70 ? '#1890FF' : '#FAAD14');
              return '<div style="margin-top:9px">' +
                '<div style="display:flex;align-items:center;font-size:12px">' +
                  '<span style="color:#17324B;font-weight:600">' + s + '</span>' +
                  '<span style="margin-left:auto;color:#8A9AAB;font-size:11px">已学 ' + now + ' 分钟 / 要求 ' + target + ' 分钟</span>' +
                  '<b style="margin-left:8px;font-weight:700;color:' + col + '">' + pct + '%</b>' +
                '</div>' +
                '<div class="al-prog" style="margin-top:5px"><i style="width:' + pct + '%;background:' + col + '"></i></div>' +
              '</div>';
            }).join('') +
          '</div>';
        }).join('');
    }

    /* ---------- 管理端·通知 两个子页（发布通知 / 记录反馈） ---------- */
    function adminNoticeBody() {
      var an = st.anotice;
      var head = '<div class="al-tabs" style="margin-bottom:14px">' +
        '<button class="al-tab' + (an.tab === 1 ? ' is-on' : '') + '" data-act="anotice-tab" data-idx="1">发布通知</button>' +
        '<button class="al-tab' + (an.tab === 2 ? ' is-on' : '') + '" data-act="anotice-tab" data-idx="2">记录反馈</button>' +
      '</div>';
      if (an.tab === 1) {
        /* 发布通知：类型选择 + 插入媒体 + 内容输入 + 发送 */
        return head +
          '<div class="al-card" style="padding:14px">' +
            '<div style="display:flex;gap:10px;margin-bottom:12px">' +
              '<button class="al-segbtn' + (an.ntype === 'system' ? ' is-on' : '') + '" data-act="anotice-ntype" data-arg="system">系统通知</button>' +
              '<button class="al-segbtn' + (an.ntype === 'dept' ? ' is-on' : '') + '" data-act="anotice-ntype" data-arg="dept">学习通知</button>' +
            '</div>' +
            '<div style="display:flex;gap:12px;margin-bottom:14px">' +
              '<button class="al-btn" style="flex:1" data-act="todo" data-label="插入图片">📷 插入图片</button>' +
              '<button class="al-btn" style="flex:1" data-act="todo" data-label="插入视频">🎬 插入视频</button>' +
            '</div>' +
            '<div class="al-ta">请输入通知内容，支持换行。点击插入图片/视频按钮，会在光标处添加标记</div>' +
            '<div style="text-align:right;font-size:11.5px;color:#8A9AAB;margin:8px 2px 12px">已输入：0 字</div>' +
            '<button class="al-btn al-btn--primary" style="width:100%" data-act="todo" data-label="发送通知">发送通知</button>' +
          '</div>';
      }
      /* 记录反馈：通知记录 / 反馈处理 */
      var sub = an.sub;
      var subbar = '<div class="al-tabs" style="margin-bottom:12px">' +
        '<button class="al-tab' + (sub === 1 ? ' is-on' : '') + '" data-act="anotice-sub" data-idx="1">通知记录</button>' +
        '<button class="al-tab' + (sub === 2 ? ' is-on' : '') + '" data-act="anotice-sub" data-idx="2">反馈处理</button>' +
      '</div>';
      if (sub === 1) {
        return head + subbar +
          '<div class="al-group-title">系统通知</div>' +
          notice('系统', 'grey', '新版本 V1.5.9 已发布', '09-25', '本次更新优化了通知到达率与视频播放稳定性，建议全员升级。') +
          '<div class="al-group-title">学习通知</div>' +
          notice('学习', 'blue', '本周学习任务已更新', '09:15', '本周数学新增 3 个视频任务，完成后学习时长将同步到教师端。');
      }
      return head + subbar +
        [['张明', '关于视频播放卡顿的反馈', '待处理'],
         ['李华', '希望增加错题本功能', '已回复'],
         ['王芳', '期中测评时间能否调整', '待处理']].map(function (r) {
          return '<div class="al-card" style="padding:12px 14px;margin-bottom:10px">' +
            '<div style="display:flex;align-items:center;gap:8px">' +
              '<b style="font-size:13px;color:#0B2545">' + r[0] + '</b>' +
              chip(r[2], r[2] === '待处理' ? 'orange' : 'green') +
            '</div>' +
            '<div style="font-size:12.5px;color:#4A5A6B;margin-top:6px">' + r[1] + '</div>' +
            '<button class="al-btn" style="margin-top:10px" data-act="todo" data-label="处理反馈">去处理</button>' +
          '</div>';
        }).join('');
    }

    /* ---------- 四个 Tab ---------- */
    var TABS = {};
    /* 工具：纯标题（与真机一致的白色标题，无头像） */
    function pttl(txt, sub, small) {
      return '<div class="al-pttl' + (small ? ' al-pttl--sm' : '') + '">' + txt +
        (sub ? '<span>' + sub + '</span>' : '') + '</div>';
    }
    function examCard(o) {
      var map = { open: ['答题已开放', 'green'], no: ['未开始', 'grey'], end: ['已结束', 'red'] };
      var b = map[o.status] || ['—', 'grey'];
      /* 默认按钮（学生端）；管理端可传 label / act / arg / primary / disabled 覆盖 */
      var label = o.label, act = o.act, arg = o.arg, primary = o.primary, disabled = o.disabled;
      if (label == null) {
        if (o.status === 'open') { label = '开始答题'; act = 'start-exam'; primary = true; }
        else if (o.status === 'no') { label = '尚未开放'; disabled = true; }
        else if (o.status === 'end') { label = '试卷详情'; act = 'open-sub'; arg = 'detail'; }
        else { label = '—'; disabled = true; }
      }
      var btn = disabled
        ? '<button class="al-btn" disabled>' + label + '</button>'
        : '<button class="al-btn' + (primary ? ' al-btn--primary' : '') + '" data-act="' + (act || 'todo') + '"' +
            (arg ? ' data-arg="' + arg + '"' : '') + ' data-label="' + label + '">' + label + '</button>';
      return '<div class="al-excard">' +
        '<div class="al-excard__top"><span class="al-excard__name">' + o.name + '</span>' + chip(b[0], b[1]) + '</div>' +
        '<div class="al-excard__row"><span>科目：' + o.subject + '</span><span class="o">类型：' + o.type + '</span></div>' +
        '<div class="al-excard__act">' +
          '<div class="al-excard__tm"><span>开始：' + o.start + '</span><span>结束：' + o.end + '</span><span>' + o.timing + '</span></div>' +
          btn +
        '</div>' +
      '</div>';
    }
    function sec(label, items) {
      return '<div class="al-sec"><div class="al-sec__lab">' + label + '</div>' +
        '<div class="al-sec__grid">' + items.map(function (it) {
          var act = it.act || 'todo';
          var arg = it.arg ? ' data-arg="' + it.arg + '"' : '';
          return '<button class="al-seccard" data-act="' + act + '"' + arg + ' data-label="' + it.lb + '">' +
            '<span class="al-seccard__ic">' + it.ic + '</span><span class="al-seccard__lb">' + it.lb + '</span></button>';
        }).join('') + '</div></div>';
    }
    function noticeSec(title, unread, items) {
      return '<div class="al-notsec"><div class="al-notsec__h"><b>' + title + '</b>' +
        (unread ? '<span class="al-notsec__badge">' + unread + '</span>' : '') + '</div>' +
        items.map(function (it) {
          return '<div class="al-noti">' +
            (it.u ? '<span class="al-noti__dot"></span>' : '<span class="al-noti__sp"></span>') +
            '<div class="al-noti__tx"><div>' + it.t + '</div><time>' + it.time + '</time></div>' +
            '<button class="al-noti__btn" data-act="todo" data-label="通知详情">查看详情</button></div>';
        }).join('') + '</div>';
    }


    TABS.student = [
      function () {
        return pttl('试卷中心') +
          examCard({ status: 'open', name: '八年级数学 · 期中测评', subject: '数学', type: '正式考试', start: '09-27 14:00', end: '09-27 15:30', timing: '总计时：90 分钟' }) +
          examCard({ status: 'no', name: '英语听力专项训练', subject: '英语', type: '专项训练', start: '09-29 09:00', end: '09-29 09:30', timing: '每题计时' }) +
          examCard({ status: 'end', name: '物理 · 力学单元小测', subject: '物理', type: '单元小测', start: '09-20 10:00', end: '09-20 10:45', timing: '总计时：45 分钟' });
      },
      function () {
        /* 真机：固定层为「学习中心 + 课程资源」标题行 → 四等分科目标签条 → 进度卡；下方为可滚动视频卡列表 */
        var subj = ['语文', '数学', '英语', '其他'];
        var videos = ['二次函数的图象与性质', '一元二次方程的解法', '函数与方程的相互转化'];
        return '<div class="al-titlerow">' +
            '<div class="al-pttl">学习中心</div>' +
            '<button class="al-resbtn" data-act="open-sub" data-arg="browser"><span class="al-resbtn__ic">📖</span>课程资源</button>' +
          '</div>' +
          '<div class="al-subjbar">' +
            subj.map(function (t) { return '<button class="al-subj' + (st.subjectLabel === t ? ' is-on' : '') + '" data-act="stu-subj" data-sub="' + t + '">' + t + '</button>'; }).join('') +
          '</div>' +
          '<div class="al-card" style="padding:14px;margin-bottom:11px">' +
            '<div style="font-size:14px;font-weight:600;color:rgba(0,0,0,.87);margin-bottom:8px">今日 ' + st.subjectLabel + ' 学习进度</div>' +
            '<div style="display:flex;justify-content:space-between;font-size:12px;color:rgba(0,0,0,.54);margin-bottom:6px"><span>要求：30 分钟</span><span>已学：20.4 分钟</span></div>' +
            '<div class="al-prog"><i style="width:68%;background:#2196F3"></i></div>' +
            '<div style="font-size:12px;color:rgba(0,0,0,.54);margin-top:6px">完成度：68.0%</div>' +
          '</div>' +
          videos.map(function (n) {
            return '<div class="al-vidcard" data-act="todo" data-label="视频播放">' +
              '<span class="al-vidcard__ic">🎬</span>' +
              '<span class="al-vidcard__nm">' + n + '</span>' +
              '<span class="al-vidcard__ar">⌄</span>' +
            '</div>';
          }).join('');
      },
      function () {
        return '<div class="al-pttl-row">' +
            '<div class="al-pttl al-pttl--sm">通知中心</div>' +
            '<button class="al-notfb" data-act="todo" data-label="意见反馈">反馈</button>' +
          '</div>' +
          '<div class="al-notcard">' +
            noticeSec('系统通知', '2', [
              { t: '期中测评安排', time: '14:02', u: true },
              { t: '新版本 V1.5.9 已发布', time: '09-25', u: false }
            ]) +
            '<div class="al-notdiv"></div>' +
            noticeSec('学习通知', '1', [
              { t: '本周学习任务已更新', time: '09:15', u: true }
            ]) +
          '</div>';
      },
      function () {
        return sec('工具', [
            { ic: '📝', lb: '签到', act: 'open-sub', arg: 'stusign' },
            { ic: '📱', lb: '考试登录' }
          ]) +
          sec('常规', [
            { ic: '⚙️', lb: '设置', act: 'open-sub', arg: 'settings' },
            { ic: '🔄', lb: '检查更新' },
            { ic: '🌐', lb: '官网' },
            { ic: '🚪', lb: '退出登录' }
          ]);
      }
    ];
    TABS.admin = [
      function () {
        return '<div class="al-quick">' +
            '<button data-act="open-sub" data-arg="publish"><span class="ic">✎</span><span class="lb">出题管理</span></button>' +
            '<button data-act="todo" data-label="测试管理"><span class="ic">🧪</span><span class="lb">测试管理</span></button>' +
            '<button data-act="todo" data-label="试卷管理"><span class="ic">🗂</span><span class="lb">试卷管理</span></button>' +
            '<button data-act="todo" data-label="试卷统计"><span class="ic">📊</span><span class="lb">试卷统计</span></button>' +
          '</div>' +
          '<div class="al-group-title">已发布试卷</div>' +
          examCard({ status: 'open', name: '八年级数学 · 期中测评', subject: '数学', type: '正式考试', start: '09-27 14:00', end: '09-27 15:30', timing: '总计时：90 分钟' }) +
          examCard({ status: 'no', name: '英语听力专项训练', subject: '英语', type: '专项训练', start: '09-29 09:00', end: '09-29 09:30', timing: '每题计时', label: '未开始', disabled: true }) +
          examCard({ status: 'end', name: '物理 · 力学单元小测', subject: '物理', type: '单元小测', start: '09-20 10:00', end: '09-20 10:45', timing: '总计时：45 分钟', label: '试卷详情', act: 'open-sub', arg: 'detail' });
      },
      function () {
        return '<div class="al-tabs" style="margin-bottom:12px">' +
            ['学习要求配置', '科目视频管理', '用户学习进度'].map(function (t, i) {
              return '<button class="al-tab' + (st.astudy.mainTab === i ? ' is-on' : '') + '" data-act="astudy-tab" data-idx="' + i + '">' + t + '</button>';
            }).join('') +
          '</div>' +
          adminStudyBody();
      },
      function () {
        return adminNoticeBody();
      },
      function () {
        return sec('管理', [
            { ic: '📚', lb: '课程资源', act: 'open-sub', arg: 'browser' },
            { ic: '👥', lb: '用户管理', act: 'open-sub', arg: 'users' },
            { ic: '🛠', lb: '更新管理' },
            { ic: '🖼', lb: '设置背景' },
            { ic: '✅', lb: '签到管理', act: 'open-sub', arg: 'sign' },
            { ic: '📤', lb: '数据导出', act: 'open-sub', arg: 'export' },
            { ic: '📺', lb: '投屏讲解', act: 'open-sub', arg: 'explain' }
          ]) +
          sec('常规', [
            { ic: '🔄', lb: '检查更新' },
            { ic: '🌐', lb: '官网' },
            { ic: '🚪', lb: '退出登录' }
          ]);
      }
    ];
    TABS.parent = [
      function () {
        var PEX = [['20260118', '张明'], ['20260129', '李华']];
        var sel = st.pexam.sel;
        return pttl('试卷详情中心') +
          '<div class="al-stusel">' +
            PEX.map(function (s, i) {
              return '<button class="al-stuchip' + (i === sel ? ' is-on' : '') + '" data-act="pexam-stu" data-idx="' + i + '">' + s[0] + ' (' + s[1] + ')</button>';
            }).join('') +
          '</div>' +
          '<div class="al-group-title">' + PEX[sel][1] + ' 的试卷</div>' +
          [
            ['八年级数学 · 期中测评', '09-27 15:30', '86'],
            ['物理 · 力学单元小测', '09-20 11:30', '92'],
            ['英语听力专项训练', '09-29 09:40', '78']
          ].map(function (e) {
            return '<div class="al-card" style="padding:14px;margin-bottom:10px">' +
              '<div style="font-size:14px;font-weight:700;color:#0B2545">' + e[0] + '</div>' +
              '<div style="font-size:11.5px;color:#8A9AAB;margin-top:7px">提交：' + e[1] + '  |  得分：' + e[2] + '</div>' +
              '<button class="al-btn al-btn--primary" style="width:100%;margin-top:12px" data-act="open-sub" data-arg="detail">查看</button>' +
            '</div>';
          }).join('');
      },
      function () {
        var PST = [['20260118', '张明'], ['20260129', '李华']];
        var sel = st.pstudy.sel;
        var WD = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
        var data = [
          { mins: [30, 42, 50, 36], inRange: true },
          { mins: [20, 38, 40, 28], inRange: true },
          { mins: [30, 40, 44, 30], inRange: true },
          { mins: [28, 36, 30, 24], inRange: true },
          { mins: [18, 30, 26, 20], inRange: true },
          { mins: [0, 0, 0, 0], inRange: false },
          { mins: [0, 0, 0, 0], inRange: false }
        ];
        var targets = [30, 40, 40, 30];
        var subj = ['语文', '数学', '英语', '其他'];
        return pttl('学习记录中心') +
          '<div class="al-stusel">' +
            PST.map(function (s, i) {
              return '<button class="al-stuchip' + (i === sel ? ' is-on' : '') + '" data-act="pstudy-stu" data-idx="' + i + '">' + s[0] + ' (' + s[1] + ')</button>';
            }).join('') +
          '</div>' +
          '<div class="al-card" style="padding:14px;margin-bottom:12px">' +
            '<div class="al-2col">' +
              '<div class="al-selbox"><span>任务范围</span><b>2025 秋季学期 ▾</b></div>' +
              '<div class="al-selbox"><span>选择周</span><b>第 1 周 ▾</b></div>' +
            '</div>' +
          '</div>' +
          '<div class="al-group-title">' + PST[sel][1] + ' · 周一至周日</div>' +
          WD.map(function (d, i) {
            var dd = data[i];
            return '<div class="al-card" style="padding:12px 14px;margin-bottom:10px">' +
              '<div style="display:flex;align-items:center;gap:9px">' +
                '<b style="font-size:13px;color:#0B2545;width:30px">' + d + '</b>' +
                (dd.inRange
                  ? '<span class="al-daybox">在范围内</span>'
                  : '<span class="al-daybox al-daybox--off">未开始</span>') +
              '</div>' +
              '<div style="margin-top:9px;display:grid;gap:6px">' +
                subj.map(function (s, k) {
                  var mins = dd.mins[k];
                  var target = targets[k];
                  var pct = target > 0 ? Math.min(100, Math.round(mins / target * 100)) : 0;
                  var color = pct >= 100 ? '#52C41A' : (pct >= 50 ? '#FAAD14' : '#1890FF');
                  return '<div class="al-prog"><span>' + s + '</span><i><em style="width:' + pct + '%;background:' + color + '"></em></i></div>' +
                    '<div style="font-size:10.5px;color:#7C8FA3;margin:-2px 0 2px 34px">要求：' + target + ' 分钟 · 已学：' + mins + ' 分钟</div>';
                }).join('') +
              '</div>' +
            '</div>';
          }).join('');
      },
      function () {
        return '<div class="al-pttl-row">' +
            '<div class="al-pttl al-pttl--sm">通知中心</div>' +
            '<button class="al-notfb" data-act="todo" data-label="意见反馈">反馈</button>' +
          '</div>' +
          '<div class="al-notcard">' +
            noticeSec('系统通知', '2', [
              { t: '期中测评安排', time: '14:02', u: true },
              { t: '新版本 V1.5.9 已发布', time: '09-25', u: false }
            ]) +
            '<div class="al-notdiv"></div>' +
            noticeSec('学习通知', '1', [
              { t: '本周学习任务已更新', time: '09:15', u: true }
            ]) +
          '</div>';
      },
      function () {
        return '<div class="al-seccenter">' +
            '<button class="al-seccard" data-act="open-sub" data-arg="settings" data-label="设置"><span class="al-seccard__ic">⚙️</span><span class="al-seccard__lb">设置</span></button>' +
            '<button class="al-seccard" data-act="todo" data-label="检查更新"><span class="al-seccard__ic">🔄</span><span class="al-seccard__lb">检查更新</span></button>' +
            '<button class="al-seccard" data-act="todo" data-label="官网"><span class="al-seccard__ic">🌐</span><span class="al-seccard__lb">官网</span></button>' +
            '<button class="al-seccard" data-act="todo" data-label="退出登录"><span class="al-seccard__ic">🚪</span><span class="al-seccard__lb">退出登录</span></button>' +
          '</div>';
      }
    ];
    /* ---------- 二级页 ---------- */
    function subBar(title, sub, right) {
      return '<div class="al-sub__bar">' +
        '<button class="al-ai__back" data-act="back-app">‹</button>' +
        '<div class="al-sub__ttl"><b>' + title + '</b>' + (sub ? '<span>' + sub + '</span>' : '') + '</div>' +
        (right ? '<span class="al-sub__right">' + right + '</span>' : '') +
      '</div>';
    }

    var SUB = {
      /* 答卷详情 */
      detail: function () {
        /* 真机：题型分区（图标 + 题型名 + 分区得分）→ 逐题（第N题 · 得分 · 问AI）→ 选项着色 → 我的/标准答案灰框 → 解析 */
        var SEC = [
          {
            t: '单选题', ic: '📝', score: 4, total: 4,
            qs: [{
              no: 1, score: 4, total: 4,
              stem: '一元二次方程 x² − 5x + 6 = 0 的两个根是（　）',
              opts: ['2 和 3', '−2 和 −3', '1 和 6', '−1 和 −6'],
              mine: 'A. 2 和 3', std: 'A. 2 和 3',
              exp: '因式分解得 (x−2)(x−3)=0，两根为 2 和 3。'
            }]
          },
          {
            t: '填空题', ic: '✏️', score: 3, total: 4,
            qs: [{
              no: 2, score: 3, total: 4,
              stem: '物体所受重力 G = mg，其中 g 取 9.8 N/kg，则质量为 2 kg 的物体所受重力为 ____ N。',
              opts: [],
              mine: '20', std: '19.6',
              exp: 'G = mg = 2 × 9.8 = 19.6 N，注意保留有效数字。'
            }]
          }
        ];
        return '<div class="al-sub">' + subBar('答卷详情', '物理 · 力学单元小测', '86 / 100') +
          '<div class="al-sub__body">' +
            SEC.map(function (sec) {
              return '<div class="al-sechead"><span class="ic">' + sec.ic + '</span><b>' + sec.t + '</b>' +
                  '<span class="al-pill al-pill--orange">得分：' + sec.score + ' / ' + sec.total + '</span></div>' +
                sec.qs.map(function (qq) {
                  return '<div class="al-dq">' +
                    '<div class="al-dq__hd">' +
                      '<span class="al-pill al-pill--blue">第' + qq.no + '题</span>' +
                      '<span class="al-pill al-pill--orange">得分：' + qq.score + ' / ' + qq.total + '</span>' +
                      '<button class="al-askai" data-act="ask-ai">🤖 问AI</button>' +
                    '</div>' +
                    '<div class="al-dq__stem">' + qq.stem + '</div>' +
                    (qq.opts.length ? '<div class="al-dq__opts">' + qq.opts.map(function (o, i) {
                      var k = String.fromCharCode(65 + i);
                      var cls = (qq.std.charAt(0) === k) ? 'is-right' : (qq.mine.charAt(0) === k ? 'is-mine' : '');
                      return '<div class="al-optview ' + cls + '"><span class="k">' + k + '.</span><span>' + o + '</span></div>';
                    }).join('') + '</div>' : '') +
                    '<div class="al-ansbox"><div>我的答案：' + qq.mine + '</div><div>标准答案：' + qq.std + '</div></div>' +
                    '<div class="al-dq__exp">📖 解析：' + qq.exp + '</div>' +
                  '</div>';
                }).join('');
            }).join('') +
          '</div></div>';
      },

      /* 出题发布 */
      publish: function () {
        var m = st.publish;
        return '<div class="al-sub">' + subBar('出题发布', m.mode === 'ai' ? 'AI 出题' : '导入出题') +
          '<div class="al-sub__body">' +
            '<div class="al-tabs" style="margin-bottom:12px">' +
              '<button class="al-tab' + (m.mode === 'ai' ? ' is-on' : '') + '" data-act="pub-mode" data-mode="ai">AI 出题</button>' +
              '<button class="al-tab' + (m.mode === 'import' ? ' is-on' : '') + '" data-act="pub-mode" data-mode="import">导入出题</button>' +
            '</div>' +

            '<div class="al-card">' +
              '<div class="al-row"><span>科目</span><b>数学 ›</b></div>' +
              '<div class="al-row"><span>试卷名称</span><b>八年级数学期中测评</b></div>' +
              (m.mode === 'ai'
                ? '<div class="al-row"><span>出题范围</span><b>二次函数 · 一元二次方程</b></div>'
                : '<div class="al-row"><span>粘贴内容</span><b>已输入 1240 字符</b></div>') +
              '<div class="al-row"><span>考试类型</span><b>强制</b></div>' +
              '<div class="al-row"><span>开始时间</span><b>09-27 14:00</b></div>' +
              '<div class="al-row"><span>结束时间</span><b>09-27 15:30</b></div>' +
              '<div class="al-row"><span>计时方式</span><b>总计时 90 分钟</b></div>' +
            '</div>' +

            '<div class="al-card">' +
              '<div style="font-size:12.5px;font-weight:700;color:#0B2545;margin-bottom:9px">题型设置</div>' +
              '<table class="al-table"><tr><th>题型</th><th>题数</th><th>每题分</th><th>每题时间</th></tr>' +
                '<tr><td>单选题</td><td>5</td><td>4</td><td>—</td></tr>' +
                '<tr><td>多选题</td><td>3</td><td>8</td><td>—</td></tr>' +
                '<tr><td>填空题</td><td>4</td><td>5</td><td>—</td></tr>' +
                '<tr><td>简答题</td><td>2</td><td>15</td><td>—</td></tr>' +
              '</table>' +
              '<div style="font-size:10.5px;color:#8A9AAB;margin-top:8px">卷面总分 100 分 · 共 14 题</div>' +
            '</div>' +

            (m.stage === 0
              ? '<button class="al-btn al-btn--primary" style="width:100%" data-act="pub-gen">' +
                  (m.mode === 'ai' ? '✨ 生成试卷' : '📋 解析导入') + '</button>'
              : m.stage === 1
                ? '<div class="al-card" style="text-align:center;padding:20px 12px">' +
                    '<div class="al-spin"></div>' +
                    '<div style="font-size:12px;color:#56708A;margin-top:10px">' +
                      (m.mode === 'ai' ? 'AI 正在出题中…' : '正在解析题目…') + '</div>' +
                    '<div style="font-size:10.5px;color:#8A9AAB;margin-top:3px">已接收 1,820 字符</div>' +
                  '</div>'
                : '<div class="al-card">' +
                    '<div style="display:flex;align-items:center;gap:8px;margin-bottom:10px">' +
                      chip('预览', 'green') + '<b style="font-size:12.5px;color:#0B2545">八年级数学期中测评</b></div>' +
                    '<div style="font-size:11.5px;color:#56708A;line-height:1.8;margin-bottom:10px">' +
                      '单选题 (5 题) · 多选题 (3 题) · 填空题 (4 题) · 简答题 (2 题)</div>' +
                    '<div style="padding:10px 12px;border-radius:9px;background:rgba(24,144,255,.06);font-size:11.5px;color:#17324B;line-height:1.75">' +
                      '1. 抛物线 <span class="formula">y = x² − 4x + 3</span> 的顶点坐标是（　）<br>' +
                      '参考答案：(2, −1)</div>' +
                    '<div style="display:flex;gap:8px;margin-top:12px">' +
                      '<button class="al-btn" style="flex:1" data-act="pub-reset">重新生成</button>' +
                      '<button class="al-btn al-btn--primary" style="flex:1" data-act="pub-pub">发布试卷</button>' +
                    '</div>' +
                  '</div>') +
          '</div></div>';
      },

      /* 投屏讲解 */
      explain: function () {
        var e = st.explain;
        var QS = [
          { t: '单选题', s: '一元二次方程 x² − 5x + 6 = 0 的两个根是（　）', o: ['2 和 3', '−2 和 −3', '1 和 6', '−1 和 −6'], a: 'A', ex: '因式分解得 (x−2)(x−3)=0，两根为 2 和 3。' },
          { t: '单选题', s: '抛物线', f: 'y = x² − 4x + 3', o: ['(2, −1)', '(−2, 1)', '(2, 1)', '(−2, −1)'], a: 'A', ex: '配方得 y=(x−2)²−1，顶点为 (2, −1)。' },
          { t: '填空题', s: '若 x + 2y = 8，且 x = 2，则 y = ____', o: [], a: '3', ex: '代入得 2 + 2y = 8，解得 y = 3。' }
        ];
        var q = QS[e.i];
        return '<div class="al-sub">' + subBar('讲解中心', '八年级数学 · 期中测评', '第 ' + (e.i + 1) + '/' + QS.length) +
          '<div class="al-sub__body">' +
            '<div class="al-card" style="margin-bottom:11px">' +
              '<div style="display:flex;align-items:center;gap:7px;margin-bottom:9px">' +
                chip(q.t, 'blue') + chip('4 分', 'grey') + chip('第 ' + (e.i + 1) + ' 题', 'violet') + '</div>' +
              '<div style="font-size:13.5px;color:#17324B;line-height:1.8">' + q.s +
                (q.f ? '<span class="formula">' + q.f + '</span>' : '') + '</div>' +
              (q.o.length ? '<div style="display:grid;gap:6px;margin-top:11px">' +
                q.o.map(function (o, i) {
                  var hot = e.show.ans && String.fromCharCode(65 + i) === q.a;
                  return '<div class="al-optview ' + (hot ? 'is-right' : '') + '"><span class="k">' +
                    String.fromCharCode(65 + i) + '</span><span>' + o + '</span></div>';
                }).join('') + '</div>' : '') +
              '<div class="al-answer' + (e.show.ans ? ' is-on' : '') + '">答案：' + q.a +
                (q.o.length && q.o[q.a.charCodeAt(0) - 65] ? '．' + q.o[q.a.charCodeAt(0) - 65] : '') + '</div>' +
              '<div class="al-analysis' + (e.show.exp ? ' is-on' : '') + '">解析：' + q.ex + '</div>' +
              (e.show.sta
                ? '<div class="al-stats"><div class="s ok">答对 <b>28</b></div><div class="s no">答错 <b>4</b></div><div class="s"><b>87.5%</b> 正确率</div></div>'
                : '') +
            '</div>' +
            '<div class="al-note">手机遥控大屏：切题、显隐答案与解析、查看答对答错名单。</div>' +
          '</div>' +
          '<div class="al-sub__foot">' +
            '<button class="al-btn" data-act="exp-prev"' + (e.i === 0 ? ' disabled' : '') + '>上一题</button>' +
            '<button class="al-btn' + (e.show.ans ? ' al-btn--primary' : '') + '" data-act="exp-toggle" data-k="ans">答案</button>' +
            '<button class="al-btn' + (e.show.exp ? ' al-btn--primary' : '') + '" data-act="exp-toggle" data-k="exp">解析</button>' +
            '<button class="al-btn' + (e.show.sta ? ' al-btn--primary' : '') + '" data-act="exp-toggle" data-k="sta">统计</button>' +
            '<button class="al-btn" data-act="exp-next"' + (e.i === QS.length - 1 ? ' disabled' : '') + '>下一题</button>' +
          '</div></div>';
      },

      /* 数据导出 */
      export: function () {
        var e = st.exp;
        return '<div class="al-sub">' + subBar('数据导出', '考试数据 / 学习数据') +
          '<div class="al-sub__body">' +
            '<div class="al-tabs"><button class="al-tab is-on" data-act="filter">导出全部数据</button>' +
              '<button class="al-tab" data-act="filter">单独导出</button></div>' +
            '<div class="al-card">' +
              '<div class="al-row"><span>时间范围</span><b>09-01 ~ 09-27</b></div>' +
              '<div class="al-row"><span>试卷选择</span><b>全部试卷</b></div>' +
              '<div class="al-row"><span>学生筛选</span><b>全部学生</b></div>' +
              '<button class="al-btn" style="width:100%;margin-top:12px;color:#1890FF" data-act="todo" data-label="数据诊断">🔍 数据诊断</button>' +
              (e.stage === 0
                ? '<button class="al-btn al-btn--primary" style="width:100%;margin-top:10px" data-act="exp-run">开始导出</button>'
                : e.stage === 1
                  ? '<div style="text-align:center;padding:16px 0"><div class="al-spin"></div>' +
                    '<div style="font-size:12px;color:#56708A;margin-top:10px">正在导出…</div></div>'
                  : '<div class="al-exported">✅ 导出成功</div>' +
                    '<div class="al-row" style="border:0;padding:0 0 4px"><span>文件名</span>' +
                      '<b style="color:#1890FF">考试成绩_0927.xlsx</b></div>' +
                    '<div style="font-size:11.5px;color:#8A9AAB;margin:2px 0 10px">Excel 工作表：考试成绩 · 答题记录 · 学习记录</div>' +
                    '<button class="al-btn al-btn--primary" style="width:100%" data-act="todo" data-label="下载 Excel">下载 Excel</button>' +
                    '<div class="al-chartttl">考试数据统计</div>' +
                    '<div style="font-size:11.5px;font-weight:700;color:#0B2545;margin-bottom:7px">各科平均分</div>' +
                    bars([46, 88, 62, 30], 54) +
                    '<div class="al-bars-lab"><span>语文</span><span>数学</span><span>英语</span><span>物理</span></div>' +
                    '<div style="font-size:11.5px;font-weight:700;color:#0B2545;margin:16px 0 8px">分数段分布</div>' +
                    pie([[8, '#FF7A45', '0–59'], [52, '#1890FF', '60–79'], [31, '#52C41A', '80–89'], [9, '#722ED1', '90–100']], 84) +
                    '<div class="al-chartttl">学习数据统计</div>' +
                    '<div style="font-size:11.5px;font-weight:700;color:#0B2545;margin-bottom:8px">科目时长占比</div>' +
                    pie([[32, '#1890FF', '语文'], [38, '#52C41A', '数学'], [21, '#FAAD14', '英语'], [9, '#8C8C8C', '其他']], 84) +
                    '<div style="font-size:11.5px;font-weight:700;color:#0B2545;margin:16px 0 8px">学生学习时长排行</div>' +
                    [['张明', 268], ['李华', 231], ['王芳', 188], ['赵磊', 142]].map(function (r) {
                      return '<div class="al-rank"><span>' + r[0] + '</span>' +
                        '<i style="width:' + Math.round(r[1] / 268 * 100) + '%"></i><b>' + r[1] + ' 分</b></div>';
                    }).join('') +
                    '<button class="al-btn" style="width:100%;margin-top:16px" data-act="exp-reset">重新配置</button>') +
            '</div>' +
            '<div class="al-note">导出前可先跑「数据诊断」，确认记录数无误再出表。</div>' +
          '</div></div>';
      },

      /* 签到 */
      sign: function () {
        var g = st.sgn;
        var SUBJ = ['语文', '数学', '英语', '其他'];

        /* ---- 未开始：签到配置面板（真机 _buildSignPanel） ---- */
        if (!g.running) {
          return '<div class="al-sub">' + subBar('签到点名') +
            '<div class="al-sub__body">' +
              '<div class="al-group-title">签到方式</div>' +
              '<div class="al-tabs" style="margin-bottom:14px">' +
                '<button class="al-tab' + (g.way === 'qr' ? ' is-on' : '') + '" data-act="sgn-way" data-way="qr">二维码</button>' +
                '<button class="al-tab' + (g.way === 'code' ? ' is-on' : '') + '" data-act="sgn-way" data-way="code">4 位口令</button>' +
              '</div>' +
              '<div class="al-group-title">科目</div>' +
              '<div class="al-tabs" style="margin-bottom:14px">' +
                SUBJ.map(function (s) {
                  return '<button class="al-tab' + (g.subject === s ? ' is-on' : '') + '" data-act="sgn-subject" data-sub="' + s + '">' + s + '</button>';
                }).join('') +
              '</div>' +
              '<div class="al-field">标题（选填）</div>' +
              '<div class="al-field">' + (g.way === 'code' ? '4 位口令' : '扫描二维码即签到') + '</div>' +
              '<div class="al-field">倒计时（秒）</div>' +
              '<div class="al-note">大屏出码 / 报口令后，学生端在「签到」里输入即完成，出勤率实时回传。</div>' +
              '<button class="al-btn al-btn--warn" style="width:100%;margin-top:12px;padding:14px" data-act="sgn-start">▶ 开始签到</button>' +
            '</div></div>';
        }

        var w = g.way;
        return '<div class="al-sub">' + subBar('签到点名 · 进行中', g.subject) +
          '<div class="al-sub__body">' +
            '<div class="al-card" style="text-align:center;padding:20px 12px">' +
              (w === 'qr'
                ? '<div class="al-qr"></div><div style="font-size:12px;color:#56708A;margin-top:11px">请用 App 扫描大屏二维码</div>'
                : '<div style="font-size:38px;font-weight:900;letter-spacing:.28em;color:#1890FF">' + g.code.split('').join(' ') + '</div>' +
                  '<div style="font-size:12px;color:#56708A;margin-top:8px">在 App 中输入以上 4 位口令</div>') +
              '<div class="al-count">倒计时：<b>' + g.countdown + '</b> 秒</div>' +
              '<div style="height:5px;border-radius:99px;background:#EDF2F8;overflow:hidden;margin-top:8px">' +
                '<i style="display:block;height:100%;width:70%;border-radius:99px;background:linear-gradient(90deg,#52C41A,#95DE64)"></i></div>' +
            '</div>' +
            '<div class="al-grid2">' +
              '<div class="al-metric" style="margin:0"><div class="k">已签</div><div class="v" style="color:#52C41A">42</div></div>' +
              '<div class="al-metric" style="margin:0"><div class="k">未签</div><div class="v" style="color:#FF4D4F">4</div></div>' +
            '</div>' +
            '<div class="al-card">' +
              '<div style="font-size:12px;font-weight:700;color:#0B2545;margin-bottom:8px">未签到 (4)</div>' +
              '<div style="display:flex;flex-wrap:wrap;gap:6px">' +
                ['20260118 张明', '20260129 李华', '20260207 王芳', '20260211 赵磊'].map(function (s) {
                  return '<span class="al-chip al-chip--red">' + s + '</span>';
                }).join('') +
              '</div>' +
            '</div>' +
            '<div style="display:flex;gap:10px;margin-top:14px">' +
              '<button class="al-btn" style="flex:1" data-act="sgn-end">结束签到</button>' +
              '<button class="al-btn" style="flex:1" data-act="todo" data-label="签到历史">签到历史</button>' +
            '</div>' +
          '</div></div>';
      },

      /* 学生端·签到（现场签到 / 记录查询） */
      stusign: function () {
        var g = st.ssg;
        var head = '<div class="al-tabs" style="margin-bottom:14px">' +
            '<button class="al-tab' + (g.tab === 0 ? ' is-on' : '') + '" data-act="ssg-tab" data-idx="0">现场签到</button>' +
            '<button class="al-tab' + (g.tab === 1 ? ' is-on' : '') + '" data-act="ssg-tab" data-idx="1">记录查询</button>' +
          '</div>';

        if (g.tab === 0) {
          return '<div class="al-sub">' + subBar('签到') +
            '<div class="al-sub__body">' + head +
              '<div style="display:flex;gap:10px">' +
                '<button class="al-btn al-btn--primary" style="flex:1;padding:14px 0" data-act="todo" data-label="扫码签到">扫码签到</button>' +
                '<button class="al-btn" style="flex:1;padding:14px 0" data-act="todo" data-label="口令签到">口令签到</button>' +
              '</div>' +
              '<div class="al-field" style="margin-top:14px">输入4位口令</div>' +
              '<div class="al-note">大屏出码或老师报出口令后，在这里扫码 / 输入口令即可完成签到，出勤率实时同步到教师端。</div>' +
            '</div></div>';
        }

        var SUBJ = ['语文', '数学', '英语', '其他'];
        var ROWS = [
          ['课堂签到', '2026-09-26 14:02', true],
          ['课堂签到', '2026-09-24 10:15', true],
          ['单元测验签到', '2026-09-22 09:00', false],
          ['课堂签到', '2026-09-19 14:05', true]
        ];
        return '<div class="al-sub">' + subBar('签到') +
          '<div class="al-sub__body">' + head +
            '<div class="al-tabs" style="margin-bottom:12px">' +
              SUBJ.map(function (s) {
                return '<button class="al-tab' + (g.subject === s ? ' is-on' : '') + '" data-act="ssg-sub" data-sub="' + s + '">' + s + '</button>';
              }).join('') +
            '</div>' +
            '<div class="al-statbar">' +
              '<span><i>总次数</i><b style="color:#1890FF">4</b></span>' +
              '<span><i>出勤</i><b style="color:#52C41A">3</b></span>' +
              '<span><i>缺勤</i><b style="color:#FA8C16">1</b></span>' +
            '</div>' +
            '<div class="al-card" style="padding:2px 14px">' +
              ROWS.map(function (r) {
                return '<div class="al-srow">' +
                  '<span class="al-srow__dot' + (r[2] ? ' is-on' : '') + '">' + (r[2] ? '✓' : '') + '</span>' +
                  '<span class="al-srow__tx"><b>' + r[0] + '</b><i>' + r[1] + '</i></span>' +
                  '<span class="al-srow__tag' + (r[2] ? ' is-on' : '') + '">' + (r[2] ? '已签到' : '缺勤') + '</span>' +
                '</div>';
              }).join('') +
            '</div>' +
          '</div></div>';
      },

      /* 设置（账户信息 / 修改密码 / 用户声明） */
      settings: function () {
        var g = st.set;

        if (g.sub === 0) {
          return '<div class="al-sub">' + subBar('设置') +
            '<div class="al-sub__body">' +
              '<div class="al-card" style="padding:4px 14px">' +
                item('👤', '账户信息', '查看账号、密码与绑定邮箱', 'set-go', null, 1) +
                item('🔒', '修改密码', '原密码 + 新密码 + 确认', 'set-go', null, 2) +
                item('📄', '用户声明', '使用前请完整阅读', 'set-go', null, 3) +
              '</div>' +
            '</div></div>';
        }

        if (g.sub === 1) {
          return '<div class="al-sub">' + subBar('账户信息') +
            '<div class="al-sub__body">' +
              '<div class="al-card">' +
                '<div class="al-row"><span>账号</span><b>20260118</b></div>' +
                '<div class="al-row"><span>密码</span><b style="display:flex;align-items:center;gap:8px">' +
                  (g.showPwd ? 'zx2026_918' : '******') +
                  '<button class="al-eye" data-act="set-pwd">' + (g.showPwd ? '🙈' : '👁') + '</button></b></div>' +
                '<div class="al-row"><span>邮箱</span><b>未绑定</b></div>' +
              '</div>' +
              '<div class="al-note">绑定邮箱后可用于自主找回密码；未绑定则只能走申诉找回。</div>' +
              '<div style="display:flex;gap:10px;margin-top:12px">' +
                '<button class="al-btn al-btn--primary" style="flex:1" data-act="todo" data-label="绑定邮箱">绑定邮箱</button>' +
                '<button class="al-btn" style="flex:1" data-act="set-go" data-idx="0">确定</button>' +
              '</div>' +
            '</div></div>';
        }

        if (g.sub === 2) {
          return '<div class="al-sub">' + subBar('修改密码') +
            '<div class="al-sub__body">' +
              '<div class="al-field">原密码</div>' +
              '<div class="al-field">新密码</div>' +
              '<div class="al-field">确认新密码</div>' +
              '<div class="al-note">新密码需 6 位以上；修改成功后需重新登录。</div>' +
              '<div style="display:flex;gap:10px;margin-top:12px">' +
                '<button class="al-btn al-btn--primary" style="flex:1" data-act="todo" data-label="提交修改">提交修改</button>' +
                '<button class="al-btn" style="flex:1" data-act="set-go" data-idx="0">取消</button>' +
              '</div>' +
            '</div></div>';
        }

        return '<div class="al-sub">' + subBar('用户声明') +
          '<div class="al-sub__body">' +
            '<div class="al-card" style="font-size:12.5px;line-height:1.95;color:#37506B">' +
              '<b style="color:#0B2545">智答星途 · 用户声明</b><br><br>' +
              '1. 本平台是面向教育场景的移动端综合服务平台，分管理员、学生、家长三类角色，权限与功能独立区分，' +
              '核心涵盖考试管理、视频学习、AI 助手、课堂签到、学情统计、消息通知、意见反馈等服务。<br><br>' +
              '2. 平台支持三端角色切换登录，各角色对应专属使用权限，AI 助手、账号管理、版本更新、VaultBox 资源宝库等功能为全用户通用服务。<br><br>' +
              '3. 所有用户需合法合规使用个人账号，妥善保管账号、密码及绑定邮箱，对账号下所有操作承担全部责任。' +
              '首次登录后请立即前往个人中心修改初始密码。' +
            '</div>' +
            '<div class="al-note">首次安装会强制展示，需停留满 10 秒并滑至最底才能确认；确认后不再重复弹出。</div>' +
            '<button class="al-btn al-btn--primary" style="width:100%;margin-top:12px" data-act="set-go" data-idx="0">我已阅读并同意</button>' +
          '</div></div>';
      },

      /* 用户管理 */
      users: function () {
        var f = st.usr.filter;
        var US = [
          ['20260118', 'student', '张明', '正常'],
          ['20260129', 'student', '李华', '待处理'],
          ['20260207', 'student', '王芳', '正常'],
          ['李老师01', 'admin', '八年级组', '正常'],
          ['王女士88', 'parent', '张明家长', '正常']
        ];
        var F = { admin: '管理员', student: '学生', parent: '家长' };
        var C = { admin: 'orange', student: 'blue', parent: 'green' };
        var list = US.filter(function (u) { return f === 'all' || u[1] === f; });
        return '<div class="al-sub">' + subBar('用户管理', list.length + ' 个账号') +
          '<div class="al-sub__body">' +
            '<div class="al-tabs">' +
              '<button class="al-tab' + (f === 'all' ? ' is-on' : '') + '" data-act="usr-f" data-f="all">全部</button>' +
              '<button class="al-tab' + (f === 'admin' ? ' is-on' : '') + '" data-act="usr-f" data-f="admin">管理员</button>' +
              '<button class="al-tab' + (f === 'student' ? ' is-on' : '') + '" data-act="usr-f" data-f="student">学生</button>' +
              '<button class="al-tab' + (f === 'parent' ? ' is-on' : '') + '" data-act="usr-f" data-f="parent">家长</button>' +
            '</div>' +
            (list.length ? list.map(function (u) {
              return '<div class="al-card" style="padding:12px 14px">' +
                '<div style="display:flex;align-items:center;gap:8px">' +
                  '<b style="font-size:13px;color:#0B2545">' + u[0] + '</b>' +
                  chip(F[u[1]], C[u[1]]) +
                  '<span style="margin-left:auto;font-size:10.5px;color:' +
                    (u[3] === '正常' ? '#52C41A' : '#FF4D4F') + '">' + u[3] + '</span>' +
                '</div>' +
                '<div style="display:flex;align-items:center;gap:8px;margin-top:9px">' +
                  '<span style="font-size:11px;color:#8A9AAB;flex:1">备注：' + u[2] + '</span>' +
                  '<button class="al-btn" style="padding:5px 11px;font-size:11px" data-act="todo" data-label="编辑用户">' +
                    (u[3] === '待处理' ? '重置' : '编辑') + '</button>' +
                  '<button class="al-btn" style="padding:5px 11px;font-size:11px;color:#FF4D4F" data-act="todo" data-label="删除用户">删除</button>' +
                '</div>' +
              '</div>';
            }).join('') : '<div class="al-empty">暂无该角色账号</div>') +
            '<div class="al-note">申诉状态为「待处理」的账号自动排在最前，支持一键重置密码。</div>' +
          '</div></div>';
      },

      /* VaultBox 资源宝库（内置浏览器：课程资源站 + 夸克搜索） */
      browser: function () {
        var b = st.brow;
        var BT = ['课程资源', '夸克搜索'];
        var bar = '<div class="al-bwbar">' +
            '<button class="al-bwbar__back" data-act="back-app" title="退出浏览器">←</button>' +
            BT.map(function (t, i) {
              return '<button class="al-bwbar__tab' + (b.tab === i ? ' is-on' : '') + '" data-act="brow-tab" data-idx="' + i + '">' + t + '</button>';
            }).join('') +
            '<button class="al-bwbar__rf" data-act="brow-reload" title="刷新">⟳</button>' +
          '</div>';

        var view;
        if (b.tab === 0) {
          view =
            '<div class="al-web">' +
              '<div class="al-web__hd">📚 课程资源共享站</div>' +
              '<div class="al-web__url">http://cydc.dpdns.org</div>' +
              '<div class="al-web__sec">最新上传</div>' +
              [['八年级数学 · 二次函数专题.pdf', 'PDF · 2.4 MB'],
               ['语文古诗文背诵音频合集.zip', 'ZIP · 18.6 MB'],
               ['英语听力训练 Unit 3-5.mp3', 'MP3 · 9.2 MB'],
               ['物理力学实验视频.mp4', 'MP4 · 62.1 MB']].map(function (f) {
                return '<div class="al-webfile" data-act="brow-dl" data-name="' + f[0] + '">' +
                  '<span class="al-webfile__ic">' + f[0].slice(-3).toLowerCase().replace(/[^a-z]/g, '') + '</span>' +
                  '<span class="al-webfile__tx"><b>' + f[0] + '</b><i>' + f[1] + '</i></span>' +
                  '<span class="al-webfile__go">下载</span>' +
                '</div>';
              }).join('') +
              '<div class="al-web__note">页面内的下载链接会被自动识别并归档到相册 / 文件管理器，外部跳转不会溢出到系统浏览器。</div>' +
            '</div>';
        } else {
          view =
            '<div class="al-web">' +
              '<div class="al-web__hd">🔍 夸克搜索</div>' +
              '<div class="al-web__search"><span>二次函数 顶点坐标 讲解</span><b>搜索</b></div>' +
              '<div class="al-web__sec">搜索结果</div>' +
              [['二次函数的顶点式与一般式互化', '把 y = ax² + bx + c 化为 y = a(x − h)² + k，顶点即 (h, k)…'],
               ['一元二次方程三种解法对比', '直接开平方 / 因式分解 / 公式法，各自适用的题型…'],
               ['期中测评真题 · 函数与方程', '本校 2024 学年八年级上学期期中真题与答案解析…']].map(function (r) {
                return '<div class="al-webres"><b>' + r[0] + '</b><span>' + r[1] + '</span></div>';
              }).join('') +
            '</div>';
        }

        return '<div class="al-bw">' + bar +
          (b.dl ? '<div class="al-bwdl"><i class="al-bwdl__spin"></i>正在下载 ' + b.dl + '</div>' : '') +
          '<div class="al-bw__view">' + view +
            (b.loading
              ? '<div class="al-bw__load"><i class="al-bw__spinner"></i><span>加载中...</span></div>'
              : '') +
          '</div>' +
          (b.loading ? '<div class="al-bw__line"><i></i></div>' : '') +
        '</div>';
      }
    };

    /* ---------- AI 预设 ---------- */
    var AI_REPLIES = [
      {
        keys: ['二次函数', '抛物线', '顶点'],
        html: '二次函数的一般式是 <span class="formula">y = ax² + bx + c　(a ≠ 0)</span>' +
          '它的图象是一条抛物线，开口方向由 <b>a</b> 决定：a &gt; 0 开口向上，a &lt; 0 开口向下。<br><br>' +
          '顶点坐标可直接套公式：<span class="formula">(−b/2a, (4ac − b²)/4a)</span>' +
          '对称轴是直线 <span class="kbd">x = −b/2a</span>。把顶点式与一般式互相转化，画图就不会出错。'
      },
      {
        keys: ['图片', '画', '生成图', '来张图'],
        html: '正在为你生成图片……', image: true
      },
      {
        keys: ['因式分解', '方程', '解法'],
        html: '解一元二次方程通常有三条路，按优先级试：<br><br>' +
          '① <b>直接开平方法</b> —— 形如 <span class="formula">x² = p</span><br>' +
          '② <b>因式分解法</b> —— 最省事，凑 <span class="kbd">(x−m)(x−n)=0</span><br>' +
          '③ <b>公式法</b> —— 万能兜底 <span class="formula">x = (−b ± √(b²−4ac)) / 2a</span>' +
          '先算判别式 Δ = b²−4ac：Δ &gt; 0 两个不等实根，Δ = 0 两个相等实根，Δ &lt; 0 无实根。'
      }
    ];
    var WELCOME = '你好！我是智答星途专属AI助手，您有任何学习问题都可以问我哦！';

    /* ---------- 构建 ---------- */
    function build() {
      host.innerHTML =
        '<div class="view" data-view="login"><div class="al-login" data-node="loginBody"></div></div>' +

        '<div class="view" data-view="app"><div class="al-app">' +
          '<div class="al-app__deco"></div>' +
          '<div class="al-body" data-node="body"></div>' +
          '<nav class="al-nav">' +
            '<button class="al-nav__ai" data-act="open-ai">AI</button>' +
            '<div class="al-nav__card"><div class="al-nav__slider" data-node="slider"></div>' +
              '<div class="al-nav__tabs">' +
                NAV_TABS.map(function (t, i) {
                  return '<button class="al-nav__tab" data-act="switch-tab" data-tab="' + i + '">' + t + '</button>';
                }).join('') +
              '</div>' +
            '</div>' +
          '</nav>' +
        '</div></div>' +

        '<div class="view" data-view="ai"><div class="al-ai">' +
          '<div class="al-ai__bar">' +
            '<button class="al-ai__back" data-act="back-app">←</button>' +
            '<div class="al-ai__title">AI 助手</div>' +
            '<button class="al-ai__menu" data-act="todo" data-label="清空记录 / 关于助手">☰</button>' +
          '</div>' +
          '<div class="al-chat" data-node="chat"></div>' +
          '<div class="al-suggest">' +
            '<button data-act="suggest" data-q="什么是二次函数？">什么是二次函数？</button>' +
            '<button data-act="suggest" data-q="帮我生成一张图片">生成一张图片</button>' +
            '<button data-act="suggest" data-q="一元二次方程怎么解？">方程怎么解？</button>' +
          '</div>' +
          '<div class="al-ai__modes">' +
          '<button class="al-ai__mode is-on" data-act="ai-mode" data-mode="text">文本生成</button>' +
          '<button class="al-ai__mode" data-act="ai-mode" data-mode="image">图片生成</button>' +
        '</div>' +
        '<div class="al-ai__cfg" data-node="aiCfg" style="display:none">' +
          '<button class="al-ai__cfgbtn is-on" data-act="ai-cfg" data-k="quality" data-v="standard">标准</button>' +
          '<button class="al-ai__cfgbtn" data-act="ai-cfg" data-k="quality" data-v="hd">高清</button>' +
          '<span class="al-ai__cfgsz">尺寸 1024×1024</span>' +
        '</div>' +
        '<div class="al-ai__input">' +
            '<input type="text" data-node="input" placeholder="输入问题..." autocomplete="off">' +
            '<button class="al-ai__send" data-act="send" aria-label="发送">➤</button>' +
          '</div>' +
        '</div></div>' +

        '<div class="view" data-view="exam"><div class="al-exam">' +
          '<div class="al-exam__bar">' +
            '<div class="al-exam__row">' +
              '<button class="al-ai__back" data-act="back-app">‹</button>' +
              '<b>数学</b>' +
              '<span class="al-timer" data-node="timer">考试 15:00</span>' +
            '</div>' +
            '<div class="al-exam__paper">八年级数学 · 期中测评</div>' +
          '</div>' +
          '<div class="al-exam__body" data-node="examBody"></div>' +
          '<div class="al-exam__foot" data-node="examFoot"></div>' +
        '</div></div>' +

        SUBS.map(function (s) {
          return '<div class="view" data-view="' + s + '">' + SUB[s]() + '</div>';
        }).join('') +

        '<div class="al-toast" data-node="toast"></div>';

      renderLogin();
      renderBody();
      renderExam();
      syncView();
    }

    function node(n) { return host.querySelector('[data-node="' + n + '"]'); }

    function renderLogin() {
      var roles = [['admin', '管理端'], ['student', '学生端'], ['parent', '家长端']];
      node('loginBody').innerHTML =
        '<div class="al-login__brand"><h4>智答星途</h4><p>智能问答 · 星途相伴</p></div>' +
        '<div class="al-roles">' + roles.map(function (r) {
          return '<button class="al-role' + (st.role === r[0] ? ' is-on' : '') +
            '" data-act="pick-role" data-role="' + r[0] + '">' + r[1] + '</button>';
        }).join('') + '</div>' +
        '<div class="al-field"><span>👤</span><input type="text" data-node="acc" placeholder="请输入账号" autocomplete="off"></div>' +
        '<div class="al-field"><span>🔒</span><input type="password" data-node="pwd" placeholder="请输入密码" autocomplete="off">' +
          '<span class="al-eye" data-act="eye">👁</span></div>' +
        '<div class="al-msg" data-node="msg"></div>' +
        '<button class="al-submit" data-node="loginBtn" data-act="login">🚀 登录</button>' +
        '<div class="al-links">' +
          '<button data-act="todo" data-label="忘记密码">🔐 忘记密码</button>' +
          '<button data-act="todo" data-label="申诉查询">📋 申诉查询</button>' +
        '</div>';
    }

    function renderBody() {
      node('body').innerHTML = TABS[st.role][st.tab]();
      node('body').scrollTop = 0;
      $$('.al-nav__tab', host).forEach(function (b, i) { b.classList.toggle('is-on', i === st.tab); });
      node('slider').style.left = (1.5 + 25 * st.tab) + '%';
    }

    function syncView() {
      $$('.view', host).forEach(function (v) { v.classList.toggle('is-on', v.dataset.view === st.view); });
      var dark = (st.view === 'login');
      statusEl.className = 'statusbar ' + (dark ? 'sb-light' : 'sb-dark');
      homeEl.className = 'homebar' + (dark ? ' on-dark' : '');
    }
    function go(v) { st.view = v; syncView(); }

    /* ---------- AI ---------- */
    function pushMsg(role, html) {
      var chat = node('chat');
      var w = document.createElement('div');
      w.className = 'al-msg' + (role === 'me' ? ' al-msg--me' : '');
      w.innerHTML = '<div class="al-msg__av">' + (role === 'me' ? '我' : 'AI') + '</div><div class="al-bubble"></div>';
      chat.appendChild(w);
      var b = w.querySelector('.al-bubble');
      if (html !== undefined) b.innerHTML = html;
      chat.scrollTop = chat.scrollHeight;
      return b;
    }
    function typeInto(c, html, speed, done) {
      var tmp = document.createElement('div');
      tmp.innerHTML = html;
      var nodes = Array.prototype.slice.call(tmp.childNodes), ni = 0;
      var chat = node('chat');
      c.innerHTML = '';
      (function next() {
        if (ni >= nodes.length) { done && done(); return; }
        var n = nodes[ni++];
        if (n.nodeType === 3) {
          var t = n.textContent, ci = 0;
          (function tick() {
            if (ci >= t.length) { next(); return; }
            c.appendChild(document.createTextNode(t.charAt(ci++)));
            chat.scrollTop = chat.scrollHeight;
            setTimeout(tick, speed);
          })();
        } else {
          c.appendChild(n.cloneNode(true));
          chat.scrollTop = chat.scrollHeight;
          setTimeout(next, speed * 4);
        }
      })();
    }
    function replyFor(q) {
      var low = q.toLowerCase();
      for (var i = 0; i < AI_REPLIES.length; i++) {
        for (var k = 0; k < AI_REPLIES[i].keys.length; k++) {
          if (low.indexOf(AI_REPLIES[i].keys[k]) >= 0) return AI_REPLIES[i];
        }
      }
      return null;
    }
    function send(text, silent) {
      if (st.ai.busy) return;
      var q = (text || '').trim();
      if (!q) return;
      st.ai.busy = true;
      if (!st.ai.booted) { st.ai.booted = true; pushMsg('ai', WELCOME); }
      if (!silent) pushMsg('me', esc(q));
      var b = pushMsg('ai', '<span class="al-typing"><i></i><i></i><i></i></span>');
      var r = replyFor(q);
      if (st.ai.mode === 'image') { r = { keys: [], html: '正在为你生成图片……', image: true }; }
      setTimeout(function () {
        if (r && r.image) {
          typeInto(b, '正在为你生成图片……', 26, function () {
            var box = document.createElement('div');
            box.className = 'al-genimg';
            box.innerHTML = '<b>星途 · 光轨</b><span>CogView · 1024 × 1024 · 高清</span>';
            b.appendChild(box);
            node('chat').scrollTop = node('chat').scrollHeight;
            st.ai.busy = false;
          });
        } else {
          typeInto(b, (r && r.html) || ('收到，我来看看「' + esc(q) + '」。<br><br>' +
            '建议先圈出<b>已知条件</b>和<b>所求量</b>，再判断它属于哪一类模型 —— ' +
            '方程先试因式分解，函数先画草图定位关键点。<br><br>' +
            '需要的话，我可以把完整步骤一步步写给你。'), 17, function () { st.ai.busy = false; });
        }
      }, 400);
    }

    /* ---------- 答题 ---------- */
    var EXAM = {
      qs: [
        { s: '一元二次方程 x² − 5x + 6 = 0 的两个根是（　）', f: null, o: ['2 和 3', '−2 和 −3', '1 和 6', '−1 和 −6'], a: 0 },
        { s: '已知一次函数 y = 2x + 1，当 x = 3 时，y 的值为（　）', f: null, o: ['5', '6', '7', '8'], a: 2 },
        { s: '下列图形中，既是轴对称又是中心对称的是（　）', f: null, o: ['等边三角形', '平行四边形', '正方形', '等腰梯形'], a: 2 },
        { s: '抛物线', f: 'y = x² − 4x + 3', o: ['(2, −1)', '(−2, 1)', '(2, 1)', '(−2, −1)'], a: 0 },
        { s: '若 a &gt; b，则下列不等式一定成立的是（　）', f: null, o: ['a − 2 &lt; b − 2', '−3a &gt; −3b', 'a/4 &gt; b/4', 'a² &gt; b²'], a: 2 }
      ]
    };

    function renderExam() {
      var body = node('examBody'), foot = node('examFoot');
      if (!body) return;
      var E = st.exam;

      var i = E.idx, q = EXAM.qs[i];
      body.innerHTML =
        '<div class="al-q">' +
          '<div class="al-q__meta"><span>第 ' + (i + 1) + ' 题 / 共 ' + EXAM.qs.length + ' 题</span>' +
            '<span class="al-q__score">20 分</span></div>' +
          '<div class="al-q__type">单选题</div>' +
          '<div class="al-q__txt">' + q.s + (q.f ? '<span class="formula">' + q.f + '</span>' : '') + '</div>' +
          '<div class="al-opts">' + q.o.map(function (o, oi) {
            return '<button class="al-opt' + (E.ans[i] === oi ? ' is-on' : '') + '" data-act="pick" data-opt="' + oi + '">' +
              '<span class="k">' + String.fromCharCode(65 + oi) + '</span><span>' + o + '</span></button>';
          }).join('') + '</div>' +
        '</div>';

      foot.innerHTML =
        (i > 0 ? '<button class="al-btn" data-act="prev">上一题</button>' : '') +
        (i < EXAM.qs.length - 1 ? '<button class="al-btn al-btn--primary" data-act="next">下一题</button>' : '') +
        '<button class="al-btn al-btn--danger" data-act="submit">交卷</button>';
    }

    function tick() {
      var el = node('timer');
      if (!el) return;
      var E = st.exam;
      if (E.left <= 0) {
        /* 真机：总计时归零 → 自动交卷（不弹成绩页） */
        clearInterval(E.timer);
        E.idx = 0; E.ans = {};
        go('app');
        toast('交卷成功');
        return;
      }
      var m = Math.floor(E.left / 60), s = E.left % 60;
      el.textContent = '考试 ' + (m < 10 ? '0' : '') + m + ':' + (s < 10 ? '0' : '') + s;
      E.left--;
    }
    function startExam() {
      var E = st.exam;
      E.idx = 0; E.ans = {}; E.done = false; E.left = 15 * 60;
      renderExam(); go('exam'); tick();
      clearInterval(E.timer);
      E.timer = setInterval(tick, 1000);
    }

    /* ---------- 二级页重绘 ---------- */
    function rerenderSub() {
      var v = host.querySelector('.view[data-view="' + st.view + '"]');
      if (v && SUBS.indexOf(st.view) >= 0) v.innerHTML = SUB[st.view]();
    }

    /* ---------- toast ---------- */
    var tt = null;
    function toast(m) {
      var el = node('toast');
      if (!el) return;
      el.textContent = m;
      el.classList.add('is-on');
      clearTimeout(tt);
      tt = setTimeout(function () { el.classList.remove('is-on'); }, 1700);
    }

    /* ---------- 事件 ---------- */
    host.addEventListener('click', function (e) {
      var t = e.target.closest('[data-act]');
      if (!t) return;
      var act = t.dataset.act;
      var arg = t.dataset.arg;
      var A = [];

      if (act === 'pick-role') {
        st.role = t.dataset.role; st.tab = 0;
        renderLogin(); renderBody();
        cfg.onRole && cfg.onRole(st.role);
        return;
      }
      if (act === 'eye') {
        var p = node('pwd');
        if (p) p.type = p.type === 'password' ? 'text' : 'password';
        return;
      }
      if (act === 'login') {
        var msg = node('msg'), btn = node('loginBtn');
        if (!(node('acc') && node('acc').value.trim())) { msg.textContent = '请填写完整账号密码'; return; }
        msg.textContent = '正在登录...';
        btn.classList.add('is-busy'); btn.textContent = '登录中…';
        setTimeout(function () {
          st.loggedIn = true; st.tab = 0;
          renderBody(); go('app');
          toast('登录成功 · 已进入' + { admin: '管理端', student: '学生端', parent: '家长端' }[st.role]);
        }, 720);
        return;
      }

      if (act === 'switch-tab') { st.tab = parseInt(t.dataset.tab, 10); renderBody(); return; }
      if (act === 'astudy-tab') { st.astudy.mainTab = parseInt(t.dataset.idx, 10); if (st.astudy.mainTab === 1) st.astudy.activeTab = 0; renderBody(); return; }
      if (act === 'astudy-subj') { st.astudy.activeTab = parseInt(t.dataset.idx, 10); renderBody(); return; }
      if (act === 'astudy-week') { st.astudy.week = parseInt(t.dataset.idx, 10); renderBody(); return; }
      if (act === 'anotice-tab') { st.anotice.tab = parseInt(t.dataset.idx, 10); renderBody(); return; }
      if (act === 'anotice-sub') { st.anotice.sub = parseInt(t.dataset.idx, 10); renderBody(); return; }
      if (act === 'anotice-ntype') { st.anotice.ntype = t.dataset.arg; renderBody(); return; }
      if (act === 'pexam-stu') { st.pexam.sel = parseInt(t.dataset.idx, 10); renderBody(); return; }
      if (act === 'pstudy-stu') { st.pstudy.sel = parseInt(t.dataset.idx, 10); renderBody(); return; }
      if (act === 'open-ai') {
        if (!st.ai.booted) { st.ai.booted = true; }
        go('ai');
        if (!node('chat').children.length) pushMsg('ai', WELCOME);
        return;
      }
      if (act === 'back-app') { go('app'); return; }
      if (act === 'open-sub') {
        if (SUBS.indexOf(arg) < 0) return;
        if (arg === 'browser') { st.brow.tab = 0; st.brow.dl = null; st.brow.loading = false; }
        if (arg === 'sign') { st.sgn.running = false; }
        if (arg === 'stusign') { st.ssg.tab = 0; }
        if (arg === 'settings') { st.set.sub = 0; st.set.showPwd = false; }
        st.view = arg; rerenderSub(); syncView();
        return;
      }

      /* VaultBox 内置浏览器 */
      if (act === 'brow-tab') {
        st.brow.tab = parseInt(t.dataset.idx, 10);
        rerenderSub();
        return;
      }
      if (act === 'brow-reload') {
        st.brow.loading = true; rerenderSub();
        setTimeout(function () {
          st.brow.loading = false;
          if (st.view === 'browser') rerenderSub();
        }, 900);
        return;
      }
      if (act === 'brow-dl') {
        var nm = t.dataset.name || '资源文件';
        st.brow.dl = nm; rerenderSub();
        setTimeout(function () {
          st.brow.dl = null;
          if (st.view === 'browser') rerenderSub();
          toast('已保存到相册 / 文件管理器');
        }, 1700);
        return;
      }

      if (act === 'filter') {
        A = Array.prototype.slice.call(t.parentNode.querySelectorAll('.al-tab'));
        A.forEach(function (b) { b.classList.remove('is-on'); });
        t.classList.add('is-on');
        return;
      }

      /* AI */
      if (act === 'suggest') {
        var sq = t.dataset.q || '';
        if (sq.indexOf('图') >= 0) {
          st.ai.mode = 'image';
          $$('.al-ai__mode', host).forEach(function (b) { b.classList.toggle('is-on', b.dataset.mode === 'image'); });
          var cfgx = node('aiCfg'); if (cfgx) cfgx.style.display = 'flex';
        }
        send(sq); return;
      }
      if (act === 'send') {
        var inp = node('input');
        A = inp ? inp.value : '';
        send(A);
        if (inp) inp.value = '';
        return;
      }
      if (act === 'ask-ai') {
        go('ai');
        if (!node('chat').children.length) pushMsg('ai', WELCOME);
        setTimeout(function () {
          send('请详细解答：一元二次方程 x² − 5x + 6 = 0 的两个根是什么，并写出完整步骤', true);
        }, 420);
        toast('已把这道题发给 AI');
        return;
      }

      /* 答题 */
      if (act === 'stu-subj') {
        st.subjectLabel = t.dataset.sub;
        A = t.parentNode.querySelectorAll('.al-subj');
        A.forEach(function (b) { b.classList.remove('is-on'); });
        t.classList.add('is-on');
        renderBody();
        return;
      }
      if (act === 'ai-mode') {
        st.ai.mode = t.dataset.mode;
        $$('.al-ai__mode', host).forEach(function (b) { b.classList.toggle('is-on', b === t); });
        var ac = node('aiCfg'); if (ac) ac.style.display = st.ai.mode === 'image' ? 'flex' : 'none';
        /* 真机：切换模式仅改变输入框提示语，不弹提示 */
        var ai = node('input');
        if (ai) ai.placeholder = st.ai.mode === 'image' ? '描述想要生成的图片...' : '输入问题...';
        return;
      }
      if (act === 'ai-cfg') {
        var cbs = t.parentNode.querySelectorAll('.al-ai__cfgbtn');
        cbs.forEach(function (b) { b.classList.remove('is-on'); });
        t.classList.add('is-on');
        toast('清晰度：' + (t.dataset.v === 'hd' ? '高清' : '标准'));
        return;
      }
      if (act === 'start-exam') { toast('正在进入考场…'); setTimeout(startExam, 400); return; }
      if (act === 'pick') { st.exam.ans[st.exam.idx] = parseInt(t.dataset.opt, 10); renderExam(); return; }
      if (act === 'prev') { if (st.exam.idx > 0) { st.exam.idx--; renderExam(); } return; }
      if (act === 'next') { if (st.exam.idx < EXAM.qs.length - 1) { st.exam.idx++; renderExam(); } return; }
      if (act === 'submit') {
        /* 真机：交卷 → Toast「交卷成功」→ 返回试卷列表（不展示成绩页） */
        clearInterval(st.exam.timer);
        st.exam.done = false; st.exam.idx = 0; st.exam.ans = {};
        go('app');
        toast('交卷成功');
        return;
      }

      /* 出题发布 */
      if (act === 'pub-mode') { st.publish.mode = t.dataset.mode; st.publish.stage = 0; rerenderSub(); return; }
      if (act === 'pub-gen') {
        st.publish.stage = 1; rerenderSub();
        setTimeout(function () { if (st.view === 'publish') { st.publish.stage = 2; rerenderSub(); } }, 1900);
        return;
      }
      if (act === 'pub-reset') { st.publish.stage = 0; rerenderSub(); return; }
      if (act === 'pub-pub') { toast('试卷发布成功'); setTimeout(function () { go('app'); }, 800); return; }

      /* 讲解 */
      if (act === 'exp-prev') { if (st.explain.i > 0) { st.explain.i--; rerenderSub(); } return; }
      if (act === 'exp-next') { if (st.explain.i < 2) { st.explain.i++; rerenderSub(); } else toast('已是最后一题'); return; }
      if (act === 'exp-toggle') {
        st.explain.show[t.dataset.k] = !st.explain.show[t.dataset.k];
        rerenderSub();
        toast('已' + (st.explain.show[t.dataset.k] ? '显示' : '隐藏') +
          { ans: '答案', exp: '解析', sta: '统计' }[t.dataset.k]);
        return;
      }

      /* 导出 */
      if (act === 'exp-run') {
        st.exp.stage = 1; rerenderSub();
        setTimeout(function () { if (st.view === 'export') { st.exp.stage = 2; rerenderSub(); } }, 1700);
        return;
      }
      if (act === 'exp-reset') { st.exp.stage = 0; rerenderSub(); return; }

      /* 签到 / 用户 */
      if (act === 'sgn-way') { st.sgn.way = t.dataset.way; rerenderSub(); return; }
      if (act === 'sgn-subject') { st.sgn.subject = t.dataset.sub; rerenderSub(); return; }
      if (act === 'sgn-start') { st.sgn.running = true; rerenderSub(); toast('签到已开始'); return; }
      if (act === 'sgn-end') { st.sgn.running = false; rerenderSub(); toast('已结束签到'); return; }
      if (act === 'usr-f') { st.usr.filter = t.dataset.f; rerenderSub(); return; }
      if (act === 'ssg-tab') { st.ssg.tab = parseInt(t.dataset.idx, 10); rerenderSub(); return; }
      if (act === 'ssg-sub') { st.ssg.subject = t.dataset.sub; rerenderSub(); return; }
      if (act === 'set-go') { st.set.sub = parseInt(t.dataset.idx, 10); rerenderSub(); return; }
      if (act === 'set-pwd') { st.set.showPwd = !st.set.showPwd; rerenderSub(); return; }

      if (act === 'todo') { toast('演示原型：' + (t.dataset.label || '该功能') + ' 在客户端中可正常使用'); }
    });

    host.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && e.target === node('input')) {
        e.preventDefault();
        send(e.target.value);
        e.target.value = '';
      }
      if (e.key === 'Enter' && e.target === node('acc')) {
        var b = node('loginBtn'); if (b) b.click();
      }
    });

    host.addEventListener('focusin', function (e) {
      var f = e.target.closest('.al-field'); if (f) f.classList.add('is-focus');
    });
    host.addEventListener('focusout', function (e) {
      var f = e.target.closest('.al-field'); if (f) f.classList.remove('is-focus');
    });

    build();

    /* 对外 API */
    return {
      setRole: function (r) {
        st.role = r; st.tab = 0;
        renderLogin(); renderBody();
        if (st.loggedIn) { go('app'); toast('已切换为' + { admin: '管理端', student: '学生端', parent: '家长端' }[r]); }
        else { go('login'); toast('已选择' + { admin: '管理端', student: '学生端', parent: '家长端' }[r] + '，点登录进入'); }
      },
      getRole: function () { return st.role; },
      jump: function (spec) {
        if (!st.loggedIn) {
          st.loggedIn = true;
          renderBody();
        }
        if (spec.role && st.role !== spec.role) {
          st.role = spec.role; st.tab = 0;
          renderLogin(); renderBody();
        }
        if (spec.tab !== undefined) { st.tab = spec.tab; renderBody(); }
        if (spec.sub) {
          if (spec.sub === 'browser') { st.brow.tab = 0; st.brow.dl = null; st.brow.loading = false; }
          if (spec.sub === 'sign') { st.sgn.running = false; }
          if (spec.sub === 'stusign') { st.ssg.tab = 0; }
          if (spec.sub === 'settings') { st.set.sub = 0; st.set.showPwd = false; }
          st.view = spec.sub; rerenderSub(); syncView(); return;
        }
        if (spec.view === 'ai') {
          go('ai');
          if (!node('chat').children.length) pushMsg('ai', WELCOME);
          return;
        }
        if (spec.view === 'exam') { startExam(); return; }
        go('app');
      }
    };
  }

  /* ============================================================
     演示面板（桌面右侧 + 移动全屏侧栏）
     ============================================================ */
  var PANEL = {
    admin: {
      title: '管理端 · 老师的一块工作台',
      desc: '出题、组卷、发布、批阅、讲解、导出 —— 点条目，手机就会跳到对应界面。',
      list: [
        ['出题管理', 'AI 出题或粘贴整卷导入，题型分数一次配齐', { role: 'admin', tab: 0, sub: 'publish' }],
        ['测试管理', '回到试卷列表并重新拉取最新试卷状态', { role: 'admin', tab: 0 }],
        ['试卷管理', '全部试卷、查看题目、设时间改分值', { role: 'admin', tab: 0 }],
        ['试卷统计', '逐学生 / 试卷 / 题型 / 单题四级下钻', { role: 'admin', tab: 0 }],
        ['学习管理', '任务时间范围、周计划与视频资源', { role: 'admin', tab: 1 }],
        ['通知发布', '系统 / 学习通知，图文视频混排', { role: 'admin', tab: 2 }],
        ['投屏讲解', 'WebSocket 遥控大屏，切题、显隐答案与统计', { role: 'admin', tab: 3, sub: 'explain' }],
        ['数据导出', '多维筛选导出 Excel，附四张统计图', { role: 'admin', tab: 3, sub: 'export' }],
        ['签到点名', '二维码或口令，实时出勤率', { role: 'admin', tab: 3, sub: 'sign' }],
        ['用户管理', '三角色建号，申诉待处理置顶', { role: 'admin', tab: 3, sub: 'users' }],
        ['资源宝库', '内置浏览器：课程资源站 + 夸克搜索', { role: 'admin', tab: 3, sub: 'browser' }]
      ]
    },
    student: {
      title: '学生端 · 一个学生的一天',
      desc: '试卷、AI、课程、签到全在一部手机里 —— 点条目，手机会跟着跳。',
      list: [
        ['试卷中心', '未开始 / 答题已开放 / 已结束三色状态', { role: 'student', tab: 0 }],
        ['在线作答', '四大题型、总计时 / 每题计时、如实交卷', { role: 'student', tab: 0, view: 'exam' }],
        ['答卷详情', '逐题看解析，不会的题一键问 AI', { role: 'student', tab: 0, sub: 'detail' }],
        ['AI 智能答疑', '流式回答带公式，还能直接生成图片', { role: 'student', view: 'ai' }],
        ['学习中心', '四科切换、内联播放 + 时长上报', { role: 'student', tab: 1 }],
        ['资源宝库', '课程资源站 / 夸克搜索双标签浏览器', { role: 'student', tab: 1, sub: 'browser' }],
        ['通知中心', '系统通知 / 学习通知两个分区', { role: 'student', tab: 2 }],
        ['签到', '现场扫码或口令，按科目查记录', { role: 'student', tab: 3, sub: 'stusign' }],
        ['设置', '账户信息、修改密码、用户声明', { role: 'student', tab: 3, sub: 'settings' }]
      ]
    },
    parent: {
      title: '家长端 · 看得见的成长',
      desc: '绑定孩子后，成绩明细、学习时长与在校通知都在一处 —— 点条目看界面。',
      list: [
        ['试卷详情中心', '按孩子切换，查看历次得分与答卷', { role: 'parent', tab: 0 }],
        ['答卷明细', '逐题我的答案、标准答案与解析', { role: 'parent', tab: 0, sub: 'detail' }],
        ['学习记录', '范围 + 周次两层筛选，每天各科进度', { role: 'parent', tab: 1 }],
        ['AI 助手', '与学生端完全一致的 AI 能力', { role: 'parent', view: 'ai' }],
        ['通知中心', '系统通知 / 学习通知两个分区', { role: 'parent', tab: 2 }],
        ['设置与多孩绑定', '一个账号可绑多个孩子，随时解绑', { role: 'parent', tab: 3, sub: 'settings' }]
      ]
    }
  };

  function renderDemoPanel(hostEl, sim) {
    var role = sim.getRole();
    var p = PANEL[role];
    hostEl.innerHTML =
      '<div class="dpanel__seg">' +
        ['student', 'admin', 'parent'].map(function (r) {
          return '<button data-role="' + r + '"' + (r === role ? ' class="is-on"' : '') + '>' +
            { student: '学生端', admin: '管理端', parent: '家长端' }[r] + '</button>';
        }).join('') +
      '</div>' +
      '<h3 class="dpanel__title">' + p.title + '</h3>' +
      '<p class="dpanel__desc">' + p.desc + '</p>' +
      '<div class="dp-list">' + p.list.map(function (it, i) {
        return '<button class="dp-item" data-i="' + i + '">' +
          '<span class="dp-item__n">' + (i + 1) + '</span>' +
          '<span class="dp-item__tx"><b>' + it[0] + '</b><span>' + it[1] + '</span></span>' +
          '<span class="dp-item__go">›</span></button>';
      }).join('') + '</div>' +
      '<p class="demo__tip">手机里的 <b>AI 圆钮</b>、底部四个 Tab、每个按钮都可以点。AI 支持直接输入问题，试卷支持真作答。</p>';

    $$('.dpanel__seg button', hostEl).forEach(function (b) {
      b.addEventListener('click', function () {
        $$('.dpanel__seg button', hostEl).forEach(function (x) { x.classList.remove('is-on'); });
        b.classList.add('is-on');
        sim.setRole(b.dataset.role);
        renderDemoPanel(hostEl, sim);
      });
    });

    $$('.dp-item', hostEl).forEach(function (b) {
      b.addEventListener('click', function () {
        var it = p.list[parseInt(b.dataset.i, 10)];
        $$('.dp-item', hostEl).forEach(function (x) { x.classList.remove('is-on'); });
        b.classList.add('is-on');
        sim.jump(it[2]);
      });
    });
  }

  var MOBILE = function () { return window.matchMedia('(max-width: 980px)').matches; };

  /* ============================================================
     站点交互
     ============================================================ */
  function bindSite() {
    /* 导航吸顶 + 高亮 */
    var nav = $('#nav');
    if (nav) {
      var onScroll = function () { nav.classList.toggle('is-stuck', window.scrollY > 18); };
      window.addEventListener('scroll', onScroll, { passive: true });
      onScroll();
    }

    /* 桌面导航活动指示 */
    var links = $('#navLinks');
    var ink = $('#navInk');
    var secs = ['caps', 'matrix', 'roles', 'demo', 'tech', 'disclaimer'];
    if (links && ink) {
      function moveInk(a) {
        if (!a) { ink.classList.remove('on'); return; }
        ink.classList.add('on');
        ink.style.left = a.offsetLeft + 'px';
        ink.style.width = a.offsetWidth + 'px';
      }
      links.addEventListener('mouseleave', function () {
        var act = links.querySelector('a.is-on');
        moveInk(act);
      });
      $$('a', links).forEach(function (a) {
        a.addEventListener('mouseenter', function () { moveInk(a); });
      });
      window.addEventListener('scroll', function () {
        var cur = null;
        secs.forEach(function (id) {
          var el = document.getElementById(id);
          if (!el) return;
          var top = el.getBoundingClientRect().top;
          if (top < 200) cur = id;
        });
        $$('a', links).forEach(function (a) {
          var on = cur && a.getAttribute('href') === '#' + cur;
          a.classList.toggle('is-on', !!on);
        });
        if (window.scrollY < 300) moveInk(null);
        else moveInk(links.querySelector('a.is-on'));
      }, { passive: true });
    }

    /* 汉堡菜单 */
    var burger = $('#burger');
    if (burger && links) {
      burger.addEventListener('click', function () {
        var open = links.classList.toggle('is-open');
        burger.classList.toggle('is-x', open);
      });
      links.addEventListener('click', function (e) {
        if (e.target.tagName === 'A') {
          links.classList.remove('is-open');
          burger.classList.remove('is-x');
        }
      });
    }

    /* 移动底部 Tab */
    var mtab = $('#mtab'), mtabInk = $('#mtabInk'), mtop = $('#mtop');
    if (mtab) {
      function moveTabInk(b) {
        if (!b || !mtabInk) return;
        /* 圆卡按「图标位」居中：只算圆心，尺寸交给 CSS（--d: 40px） */
        var ic = b.querySelector('i') || b;
        var rb = mtab.getBoundingClientRect();
        var ri = ic.getBoundingClientRect();
        var d = mtabInk.offsetWidth || 40;
        var x = (ri.left - rb.left) - mtab.clientLeft + (ri.width - d) / 2;
        var y = (ri.top - rb.top) - mtab.clientTop + (ri.height - d) / 2;
        mtabInk.style.transform = 'translate(' + x.toFixed(2) + 'px,' + y.toFixed(2) + 'px)';
      }
      function setTab(id) {
        $$('.mtab__b', mtab).forEach(function (b) {
          b.classList.toggle('is-on', b.dataset.to === id);
          if (b.dataset.to === id) moveTabInk(b);
        });
        var names = { caps: '核心能力', matrix: '功能总览', roles: '三端协同', demo: '在线体验', tech: '技术架构', download: '下载 App' };
        var sec = $('#mtopSec');
        if (sec) sec.textContent = names[id] || '智答星途';
      }
      setTab('caps');
      moveTabInk(mtab.querySelector('.mtab__b.is-on'));

      /* 滚动状态 */
      var lastY = 0;
      var tabTimer = null;
      var tabJumping = false;   /* 点击悬浮栏跳转中：底栏保持常驻，不参与"下滑收起" */
      var jumpTimer = null;
      function showTab() { mtab.classList.remove('hide'); }
      function endJump() {
        clearTimeout(jumpTimer);
        jumpTimer = setTimeout(function () { tabJumping = false; }, 180);
      }
      function bottomY() {
        return Math.max(
          document.documentElement.scrollHeight,
          document.body ? document.body.scrollHeight : 0
        ) - window.innerHeight;
      }

      $$('.mtab__b', mtab).forEach(function (b) {
        b.addEventListener('click', function () {
          var el = document.getElementById(b.dataset.to);
          if (!el) return;
          var top = Math.max(0, el.offsetTop - 72);
          tabJumping = true;      /* 标记为程序化跳转 */
          lastY = top;            /* 预置基准，避免跳转首帧被判成下滑 */
          showTab();
          clearTimeout(tabTimer);
          window.scrollTo({ top: top, behavior: 'smooth' });
          endJump();              /* 无 scroll 事件时也能自动解除标记 */
        });
      });

      window.addEventListener('scroll', function () {
        var y = window.scrollY;
        var ids = ['caps', 'matrix', 'roles', 'demo', 'tech', 'download'];
        var cur = 'caps';
        ids.forEach(function (id) {
          var el = document.getElementById(id);
          if (el && el.getBoundingClientRect().top < 240) cur = id;
        });
        var b = mtab.querySelector('.mtab__b[data-to="' + cur + '"]');
        if (b && !b.classList.contains('is-on')) setTab(cur);

        var down = y > lastY + 6;
        var up = y < lastY - 6;

        if (tabJumping) {
          /* 点击跳转引发的滚动：只保证显示，绝不出手收起 */
          showTab();
          endJump();
        } else if (y >= bottomY() - 4) {
          /* 已滑到底：底栏常驻，不再收起（否则末尾残余滚动会让它卡在隐藏态） */
          showTab();
        } else if (y > 500 && (down || up)) {
          /* 手动滚动（上划 / 下划均生效）：底栏暂时收起，滚动停下后自动滑回 */
          mtab.classList.add('hide');
        }

        /* 顶条维持原有手感：往下滚收起、往上滚恢复 */
        if (!tabJumping) {
          if (down && y > 500) { if (mtop) mtop.classList.add('hide'); }
          else if (up) { if (mtop) mtop.classList.remove('hide'); }
        }
        lastY = y;

        /* 底栏常驻：滚动停止后自动滑回（顶条维持原有收起逻辑） */
        clearTimeout(tabTimer);
        tabTimer = setTimeout(showTab, 260);
      }, { passive: true });

      /* 松手 / 惯性结束：底栏立即滑回，避免移动端停在隐藏态 */
      function settleTab() {
        clearTimeout(tabTimer);
        tabTimer = setTimeout(showTab, 120);
      }
      window.addEventListener('touchend', settleTab, { passive: true });
      window.addEventListener('touchcancel', settleTab, { passive: true });
      if ('onscrollend' in window) {
        window.addEventListener('scrollend', function () {
          clearTimeout(tabTimer);
          showTab();
          clearTimeout(jumpTimer);
          tabJumping = false;     /* 跳转滚动结束，解除标记 */
        }, { passive: true });
      }
      /* 视口变化后圆卡要重新对位（横竖屏切换、地址栏收起等） */
      window.addEventListener('resize', function () {
        moveTabInk(mtab.querySelector('.mtab__b.is-on'));
      }, { passive: true });
      window.addEventListener('orientationchange', function () {
        setTimeout(function () { moveTabInk(mtab.querySelector('.mtab__b.is-on')); }, 220);
      }, { passive: true });
    }

    /* 全屏体验抽屉
       - 无顶部黑条，手机画面直达屏幕顶部
       - 打开时压入一条 history：手机返回键 / 浏览器返回 = 退出体验，而不是离开本站
       - 右上角悬浮 ✕ 走同一条关闭路径（先退栈，由 popstate 统一收尾） */
    var fs = $('#fsdemo'), fsBtn = $('#demoMob'), fsSide = $('#fsSide');
    var FS_STATE = 'fsdemo';
    var fsBase = location.pathname + location.search;

    function fsIsOn() { return !!fs && fs.classList.contains('is-on'); }

    function fsShow() {
      if (fsIsOn()) return;
      fs.classList.add('is-on');
      fs.setAttribute('aria-hidden', 'false');
      document.body.style.overflow = 'hidden';
      var body = fs.querySelector('.fsdemo__body');
      if (body) body.scrollTop = 0;
    }

    function fsHide() {
      if (!fsIsOn()) return;
      fs.classList.remove('is-on');
      fs.setAttribute('aria-hidden', 'true');
      document.body.style.overflow = '';
    }

    function fsOpen() {
      if (fsIsOn()) return;
      fsShow();
      try {
        history.pushState({ zdxt: FS_STATE }, '', fsBase + '#experience');
      } catch (err) { /* 个别内联框架禁用 history，忽略 */ }
    }

    function fsClose() {
      if (!fsIsOn()) return;
      if (history.state && history.state.zdxt === FS_STATE) {
        history.back();          /* popstate 里统一隐藏，避免二次关闭 */
      } else {
        fsHide();
        if (location.hash === '#experience') history.replaceState(null, '', fsBase);
      }
    }

    /* 关闭状态兜底：URL 不带 #experience 时即时校验（刷新/直达） */
    if (fs && location.hash === '#experience' && !(history.state && history.state.zdxt === FS_STATE)) {
      history.replaceState(null, '', fsBase);
    }

    if (fsBtn) {
      fsBtn.innerHTML =
        '<div class="dmob">' +
          '<div class="dmob__tx"><b>完整 App 界面，点开就能玩</b>' +
            '<span>AI 答疑 · 在线作答 · 投屏讲解 · 数据导出 · 签到点名 · 用户管理</span></div>' +
          '<button class="btn btn--lg" id="dmobBtn">▶ 打开全屏体验</button>' +
          '<p class="dmob__tip">进入后可以切换三端角色，点功能清单让手机跳到对应界面；退出按手机返回键或右上角 ✕。</p>' +
        '</div>';
      $('#dmobBtn').addEventListener('click', fsOpen);
    }
    if (fs) {
      var closeBtn = $('#fsClose');
      if (closeBtn) closeBtn.addEventListener('click', fsClose);

      window.addEventListener('popstate', function () {
        /* 回退到「非体验态」时收起抽屉 */
        if (fsIsOn() && !(history.state && history.state.zdxt === FS_STATE)) fsHide();
      });

      /* Esc 兜底（桌面窗口收窄场景） */
      document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && fsIsOn()) fsClose();
      });
    }
    return fsSide;
  }

  /* ============================================================
     iPad 考试版介绍页 —— hash 路由 #ipad
     ============================================================ */
  function initIpadPage() {
    var page = $('#ipadPage');
    if (!page) return;
    var body = $('#ipadBody');
    var BASE = location.pathname + location.search;

    function isOn() { return location.hash === '#ipad'; }

    function sync() {
      var on = isOn();
      page.classList.toggle('is-on', on);
      page.setAttribute('aria-hidden', on ? 'false' : 'true');
      document.body.style.overflow = on ? 'hidden' : '';
      if (on && body) body.scrollTop = 0;
    }

    function close() {
      if (location.hash === '#ipad') {
        history.replaceState(null, '', BASE);
        sync();
      }
    }

    window.addEventListener('hashchange', sync);

    /* 页内链接：返回类关闭页面，其余锚点在容器内平滑滚动（不改 hash，否则会被当成路由） */
    page.addEventListener('click', function (e) {
      var a = e.target.closest ? e.target.closest('a[href^="#"]') : null;
      if (!a) return;
      var h = a.getAttribute('href');
      if (h === '#' || h === '#ipadBack' || h === '#top') { e.preventDefault(); close(); return; }
      var target = document.getElementById(h.slice(1));
      if (!target) { e.preventDefault(); return; }
      e.preventDefault();
      if (body) body.scrollTo({ top: Math.max(0, target.offsetTop - 14), behavior: 'smooth' });
    });

    /* Esc 关闭 */
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && isOn()) close();
    });

    sync();
  }

  /* ============================================================
     启动
     ============================================================ */
  function init() {
    renderBento();
    renderSwipe();
    renderMatrixSeg();
    renderMatrixBody();
    renderRoles();
    renderTech();

    /* iPad 考试版介绍页路由 */
    initIpadPage();

    /* 桌面模拟器 */
    var deskSim = createSim({
      prefix: 'd',
      host: $('#dscreens'),
      onRole: function () { renderDemoPanel($('#demoPanel'), deskSim); }
    });
    bindSite();
    renderDemoPanel($('#demoPanel'), deskSim);

    /* 移动全屏模拟器 */
    var fsSim = createSim({
      prefix: 'f',
      host: $('#fscreens'),
      onRole: function () { renderDemoPanel($('#fsSide'), fsSim); }
    });
    renderDemoPanel($('#fsSide'), fsSim);

    /* 时钟（两台手机） */
    function tickClock() {
      var d = new Date();
      var s = d.getHours() + ':' + (d.getMinutes() < 10 ? '0' : '') + d.getMinutes();
      var a = $('#dclock'), b = $('#fclock');
      if (a) a.textContent = s;
      if (b) b.textContent = s;
    }
    tickClock(); setInterval(tickClock, 20000);

    /* 滚动进入动画 */
    if ('IntersectionObserver' in window) {
      var io = new IntersectionObserver(function (es) {
        es.forEach(function (en) {
          if (en.isIntersecting) { en.target.classList.add('in'); io.unobserve(en.target); }
        });
      }, { threshold: 0.1, rootMargin: '0px 0px -40px' });
      $$('.reveal').forEach(function (el, i) {
        el.style.transitionDelay = (i % 6) * 60 + 'ms';
        io.observe(el);
      });
    } else {
      $$('.reveal').forEach(function (el) { el.classList.add('in'); });
    }

    /* ============================================================
       点击反馈 · 线性光
       系统默认的方形 tap 高亮已在 CSS 里全局关掉——它不跟随圆角，
       压在胶囊/圆角按钮上很突兀。这里改用自己的覆盖层：
       按被点元素的实测矩形 + 圆角裁形，扫一道斜向线性光。
       ============================================================ */
    var fxLayer = document.createElement('div');
    fxLayer.className = 'tapglow';
    fxLayer.setAttribute('aria-hidden', 'true');
    document.body.appendChild(fxLayer);

    var FX_SEL = [
      'button', 'a[href]', '[role="button"]', 'summary',
      '.btn', '.mtab__b', '.mtop__dl', '.acc__btn', '.tab', '.chip',
      '.al-btn', '.al-item', '.al-video', '.al-nav__ai', '.al-submit', '.al-opt',
      '.al-resbtn', '.al-vidcard', '.al-seccard', '.al-stuchip', '.al-chipbtn',
      '.al-iconbtn', '.al-webfile', '.al-quick button', '.al-links button',
      '.al-suggest button', '.al-ai__send', '.al-ai__back', '.al-ai__menu'
    ].join(',');

    var fxTimer = null;

    function fxRadius(el) {
      var raw = getComputedStyle(el).borderTopLeftRadius || '0px';
      if (raw.indexOf('%') > -1) return 0;
      return parseFloat(raw) || 0;
    }

    function fireFx(el) {
      if (!el || el.disabled) return;
      var r = el.getBoundingClientRect();
      if (r.width < 14 || r.height < 14) return;
      /* 整屏级容器（浮层、抽屉）不参与，否则光会扫过整个屏幕 */
      if (r.width > window.innerWidth - 8 && r.height > window.innerHeight * 0.5) return;
      if (r.bottom < 0 || r.top > window.innerHeight) return;

      var vw = window.innerWidth, vh = window.innerHeight;
      var rad = Math.min(fxRadius(el), r.width / 2, r.height / 2);

      fxLayer.style.clipPath =
        'inset(' + Math.max(0, r.top).toFixed(1) + 'px ' +
                  Math.max(0, vw - r.right).toFixed(1) + 'px ' +
                  Math.max(0, vh - r.bottom).toFixed(1) + 'px ' +
                  Math.max(0, r.left).toFixed(1) + 'px ' +
        'round ' + rad.toFixed(1) + 'px)';

      var band = Math.max(64, Math.min(r.width * 0.78, 240));
      fxLayer.style.setProperty('--fx-band', band.toFixed(1) + 'px');
      fxLayer.style.setProperty('--fx-x0', (r.left - band * 1.08).toFixed(1) + 'px');
      fxLayer.style.setProperty('--fx-x1', (r.right + band * 0.16).toFixed(1) + 'px');

      fxLayer.classList.remove('is-run');
      void fxLayer.offsetWidth;        /* 强制重排，连点也能重放动画 */
      fxLayer.classList.add('is-run');

      /* 收尾时长跟着实际动画走（改 CSS 时长 / 关动画偏好都不会脱节） */
      var dur = 0.58;
      try {
        var raw = (getComputedStyle(fxLayer, '::after').animationDuration || '').split(',')[0].trim();
        var v = parseFloat(raw);
        if (v > 0) dur = /ms$/.test(raw) ? v / 1000 : v;
      } catch (err) { /* 取不到就用默认值 */ }
      clearTimeout(fxTimer);
      fxTimer = setTimeout(function () { fxLayer.classList.remove('is-run'); }, dur * 1000 + 80);
    }

    document.addEventListener('pointerdown', function (e) {
      /* 只接管手指 / 手写笔，桌面鼠标保持原有 hover + :active 手感 */
      if (e.pointerType === 'mouse') return;
      if (e.button > 0) return;
      var t = e.target;
      var el = t && t.closest ? t.closest(FX_SEL) : null;
      if (el) fireFx(el);
    }, true);
  }

  /* ---------------------------------------------------------------
     顶栏实际高度 → --nav-h
     首屏内容用这个变量避让固定顶栏。但顶栏实际高度会随「刘海安全区 /
     系统字号 / 文字是否换行 / 浏览器工具栏」变化，硬编码 56px 会与实际
     渲染脱节 —— 表现就是顶栏"变高"把首屏内容压住。
     用 ResizeObserver 盯住顶栏实测高度并回写，任何环境下都严格对齐。
  --------------------------------------------------------------- */
  function syncNavHeight() {
    var mtop = document.getElementById('mtop');
    if (!mtop) return;
    var root = document.documentElement;

    function sync() {
      /* 桌面端顶栏 display:none，还原 CSS 里的默认值 */
      if (getComputedStyle(mtop).display === 'none') {
        root.style.removeProperty('--nav-h');
        return;
      }
      var h = Math.round(mtop.getBoundingClientRect().height);
      if (h > 0) root.style.setProperty('--nav-h', h + 'px');
    }

    if (window.ResizeObserver) {
      /* ⚠️ 必须持有 observer 引用：写成 new ResizeObserver(sync).observe(x)
         时对象无人引用，可能被 GC 回收，回调静默失效（顶栏变高了但变量不更新）。 */
      var ro = new ResizeObserver(sync);
      ro.observe(mtop);
      window.__zdxtNavRO = ro;
    }
    window.addEventListener('resize', sync, { passive: true });
    window.addEventListener('orientationchange', sync, { passive: true });
    window.addEventListener('load', sync);
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(sync);
    sync();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
    document.addEventListener('DOMContentLoaded', syncNavHeight);
  } else {
    init();
    syncNavHeight();
  }
})();
