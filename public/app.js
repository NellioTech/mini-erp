// 前端只負責「依 SQL 回傳的定義畫畫面」與「斷線重傳」，所有檢核、編號、計算都在 SQL Server。
const $ = (s, el = document) => el.querySelector(s);
const app = $('#app');
const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const uuid = () => crypto.randomUUID ? crypto.randomUUID()
  : '10000000-1000-4000-8000-100000000000'.replace(/[018]/g, c => (c ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> c / 4).toString(16));
const today = () => new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 10);

function toast(msg, cls = '') {
  const t = $('#toast'); t.textContent = msg; t.className = cls; t.hidden = false;
  clearTimeout(toast.h); toast.h = setTimeout(() => (t.hidden = true), cls === 'err' ? 6000 : 3000);
}

/* ---------- API ---------- */
async function get(proc, params = {}) {
  const down = () => { throw new Error(`無法連線到後端 API（${window.ERP_API || location.origin}），請確認後端服務已啟動`); };
  const r = await fetch(`${window.ERP_API || ''}/api/${proc}?` + new URLSearchParams(params)).catch(down);
  const j = await r.json().catch(down);
  if (!r.ok) throw new Error(j.error || r.statusText);
  return j;
}
async function post(proc, params) {
  const r = await fetch(`${window.ERP_API || ''}/api/${proc}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(params) });
  const j = await r.json().catch(() => ({ error: '伺服器回應格式錯誤' }));
  if (!r.ok) throw Object.assign(new Error(j.error || r.statusText), { status: r.status });
  return j;
}

/* ---------- 待傳佇列（斷線重傳） ----------
   每筆寫入帶唯一請求編號；SQL 端以 同步請求紀錄 去重，因此重傳絕不會重複入帳。 */
const box = {
  key: 'erp.outbox',
  all() { try { return JSON.parse(localStorage.getItem(this.key)) || []; } catch { return []; } },
  save(a) { try { localStorage.setItem(this.key, JSON.stringify(a)); } catch {} badge(); },
  add(it) { this.save([...this.all(), it]); },
  remove(id) { this.save(this.all().filter(x => x.id !== id)); },
  patch(id, p) { this.save(this.all().map(x => x.id === id ? { ...x, ...p } : x)); },
};
const isReject = e => e.status >= 400 && e.status < 500;   // SQL 拒絕：重傳也沒用

async function submit(proc, params, label) {
  const id = params.請求編號 = uuid();
  box.add({ id, proc, params, label, time: new Date().toLocaleString() });
  try {
    const res = await post(proc, params);
    box.remove(id);
    return res;
  } catch (e) {
    if (isReject(e)) { box.remove(id); throw e; }
    toast('目前離線，已暫存，連線後自動重傳', 'warn');
    return null;
  }
}

let flushing = false;
async function flush() {
  if (flushing || !navigator.onLine) return;
  flushing = true;
  try {
    for (const it of box.all().filter(x => !x.error)) {
      try { await post(it.proc, it.params); box.remove(it.id); toast(`已重傳：${it.label}`, 'ok'); }
      catch (e) { if (isReject(e)) box.patch(it.id, { error: e.message }); else break; }
    }
  } finally { flushing = false; }
}
function badge() {
  const n = box.all().length;
  $('#pending').textContent = n || '';
  document.body.classList.toggle('offline', !navigator.onLine);
  $('#netTxt').textContent = navigator.onLine ? '連線中' : '離線';
}
addEventListener('online', () => { badge(); flush(); });
addEventListener('offline', badge);
setInterval(flush, 15000);

/* ---------- 畫面 ---------- */
const defs = {}, opts = {};
const getDef = async code => defs[code] ||= await get('api_功能定義', { 功能代碼: code });
const getOpts = async t => opts[t] ||= await get('api_選項', { 表名: t }).catch(() => []);
function setHead(title, back) { $('#title').textContent = title === 'Mini ERP' ? '' : title; document.title = title; const b = $('#back'); b.hidden = !back; if (back) b.href = back; }

function pageHead(d, sub) {
  return `<div class="page-head"><div class="crumb"><a href="#/">首頁</a><i>›</i>${esc(d.模組名稱)}<i>›</i>${esc(d.分類)}</div>
    <h2>${esc(d.功能名稱)}${sub ? `<small>${esc(sub)}</small>` : ''}</h2></div>`;
}

async function viewMenu() {
  setHead('Mini ERP');
  const mods = await get('api_功能表');
  app.innerHTML = `<div class="page-head"><h2>主功能表<small>SD 訂單・MM 採購・IM 庫存・PP 生產</small></h2></div>
    <div class="grid">${mods.map(m => `
    <section class="mod" style="--c:var(--${m.模組})">
      <header><span class="badge">${esc(m.模組)}</span><h3>${esc(m.模組名稱.replace(m.模組, ''))}</h3>
        <em>${m.分類清單.reduce((n, c) => n + c.功能.length, 0)} 項功能</em></header>
      ${m.分類清單.map(c => `<div class="grp"><h4>${esc(c.分類)}</h4>${c.功能.map(f =>
        `<a href="#/f/${f.功能代碼}"><span>${esc(f.功能名稱)}</span>${f.類型 === '報表' ? '<small class="tag">報表</small>' : ''}<i>›</i></a>`).join('')}</div>`).join('')}
    </section>`).join('')}</div>`;
}

const fmt = v => typeof v === 'number' ? v.toLocaleString() : typeof v === 'string' && /^\d{4}-\d\d-\d\dT/.test(v) ? v.replace('T', ' ').slice(0, 19) : v;
const cell = (v, f) => `<td class="${f && f.型別 === 'int' ? 'n' : ''}">${esc(fmt(v))}</td>`;
const pkOf = (fields, row) => Object.fromEntries(fields.filter(f => f.主鍵).map(f => [f.欄位名, row[f.欄位名]]));
const table = (cols, rows, cls = '') => rows.length
  ? `<table><thead><tr>${cols.map(c => `<th class="${c.型別 === 'int' ? 'n' : ''}">${esc(c.欄位名)}</th>`).join('')}</tr></thead><tbody>
     ${rows.map((r, i) => `<tr data-i="${i}" class="${cls}">${cols.map(c => cell(r[c.欄位名], c)).join('')}</tr>`).join('')}</tbody></table>
     <div class="foot">共 ${rows.length} 筆</div>`
  : `<div class="empty">沒有資料</div>`;

async function viewList(code) {
  const d = await getDef(code);
  if (d.層級?.length) return viewDrill(code, d);
  setHead(d.功能名稱, '#/');
  const q = sessionStorage.getItem('q.' + code) || '';
  const ps = d.參數欄位 || [];   // 報表函數參數（如 年度），由 SQL 提供
  app.innerHTML = pageHead(d, d.類型 === '報表' ? '報表' : '') + `<div class="toolbar">${ps.map(p => `<label class="param">${esc(p.參數名)}
      <input data-p="${esc(p.參數名)}" type="${p.型別 === 'date' ? 'date' : p.型別 === 'int' ? 'number' : 'text'}"
        value="${p.參數名 === '年度' ? new Date().getFullYear() : ''}"></label>`).join('')}
    <input id="q" type="search" placeholder="搜尋關鍵字…" value="${esc(q)}">
    ${d.類型 === '維護' ? `<button id="add">＋ 新增</button>` : ''}</div><div id="list" class="tbl"></div>`;
  const load = async () => {
    const kw = $('#q').value.trim(); sessionStorage.setItem('q.' + code, kw);
    const 參數 = Object.fromEntries([...app.querySelectorAll('[data-p]')].map(i => [i.dataset.p, i.value || null]));
    const rows = await get('api_查詢', { 功能代碼: code, 關鍵字: kw, ...(ps.length ? { 參數: JSON.stringify(參數) } : {}) });
    const cols = d.主檔欄位;
    $('#list').innerHTML = table(cols, rows, d.類型 === '維護' ? 'link' : '');
    if (d.類型 === '維護') $('#list tbody')?.addEventListener('click', e => {
      const tr = e.target.closest('tr'); if (!tr) return;
      location.hash = `#/f/${code}/edit/${encodeURIComponent(JSON.stringify(pkOf(cols, rows[tr.dataset.i])))}`;
    });
  };
  let t; $('#q').oninput = () => { clearTimeout(t); t = setTimeout(load, 300); };
  app.querySelectorAll('[data-p]').forEach(i => (i.onchange = load));
  if ($('#add')) $('#add').onclick = () => (location.hash = `#/f/${code}/new`);
  await load();
}

/* 多層鑽取：層級與關聯由 SQL 的 報表層級 定義，點選列進入下一層 */
async function viewDrill(code, d) {
  setHead(d.功能名稱, '#/');
  const path = [];   // 每層被點選的列
  const render = async () => {
    const lv = d.層級[path.length];
    const rows = await get('api_鑽取', { 功能代碼: code, 層級: lv.層級, ...(path.length ? { 上層: JSON.stringify(path.at(-1)) } : {}) });
    const hasNext = path.length + 1 < d.層級.length;
    const label = (r, l) => l.欄位.slice(0, 3).map(c => r[c.欄位名]).filter(v => v != null && v !== '').join(' / ');
    app.innerHTML = pageHead(d, `第 ${lv.層級} 層・${lv.標題}`) + `
      <nav class="levels">${d.層級.map((l, i) => `<button class="lv ${i === path.length ? 'on' : ''}" data-l="${i}" ${i > path.length ? 'disabled' : ''}>
        <b>${l.層級}</b>${esc(l.標題)}${i < path.length ? `<small>${esc(label(path[i], l))}</small>` : ''}</button>`).join('<i>›</i>')}</nav>
      ${hasNext ? `<p class="hint">點選資料列可查看下一層「${esc(d.層級[path.length + 1].標題)}」</p>` : ''}
      <div class="tbl">${table(lv.欄位, rows, hasNext ? 'link' : '')}</div>`;
    app.querySelectorAll('.lv[data-l]').forEach(b => (b.onclick = () => { path.length = +b.dataset.l; render(); }));
    if (hasNext) $('.tbl tbody')?.addEventListener('click', e => {
      const tr = e.target.closest('tr'); if (tr) { path.push(rows[tr.dataset.i]); render(); }
    });
  };
  await render();
}

async function input(f, v, { isNew, lockPk, auto, allRo }) {
  const ro = allRo || f.唯讀 || (f.主鍵 && lockPk);
  const attrs = `data-f="${esc(f.欄位名)}" data-t="${f.型別}"${f.唯讀 ? ' data-ro' : ''}`;
  if (ro || auto) return `<input ${attrs} readonly value="${esc(v)}" placeholder="${auto ? '自動編號' : ''}">`;
  if (f.參照表) {
    const o = await getOpts(f.參照表);
    return `<select ${attrs}><option value=""></option>${o.map(x =>
      `<option value="${esc(x.值)}" ${x.值 === v ? 'selected' : ''}>${esc(x.值)}${x.說明 ? ' ' + esc(x.說明) : ''}</option>`).join('')}</select>`;
  }
  if (f.型別 === 'date') return `<input ${attrs} type="date" value="${esc(v ?? (isNew && !f.可空 ? today() : ''))}">`;
  if (f.型別 === 'int') return `<input ${attrs} type="number" inputmode="numeric" value="${esc(v)}">`;
  return `<input ${attrs} maxlength="${f.長度 || ''}" value="${esc(v)}">`;
}
function collect(el) {
  const o = {};
  el.querySelectorAll('[data-f]').forEach(i => {
    if (i.hasAttribute('data-ro')) return;   // SQL 回寫欄位不送出
    const v = i.value.trim();
    o[i.dataset.f] = v === '' ? null : i.dataset.t === 'int' ? Number(v) : v;
  });
  return o;
}

async function viewForm(code, keyJson) {
  const d = await getDef(code);
  const isNew = !keyJson, key = keyJson ? JSON.parse(keyJson) : null;
  setHead(d.功能名稱, `#/f/${code}`);
  const hasDetail = !!d.明細檔;
  const hk = d.主檔欄位.find(f => f.主鍵)?.欄位名;
  let head = {}, lines = [];
  if (!isNew) {
    if (hasDetail) { const r = await get('api_查詢', { 功能代碼: code, 主鍵: key[hk] }); head = r.主檔 || {}; lines = r.明細 || []; }
    else {
      const rows = await get('api_查詢', { 功能代碼: code, 關鍵字: Object.values(key)[0] });
      head = rows.find(r => Object.entries(key).every(([k, v]) => r[k] === v)) || {};
    }
    if (!Object.keys(head).length) { app.innerHTML = `<div class="empty">找不到資料（可能尚未同步）</div>`; return; }
  }
  const auto = isNew && d.單號前綴;
  const dCols = hasDetail ? d.明細欄位.filter(f => f.欄位名 !== hk) : [];
  const roDetail = d.明細唯讀;
  const ref = !roDetail && d.參照;   // 明細參照帶入（SQL 的 明細參照 設定）

  const headHtml = (await Promise.all(d.主檔欄位.map(async f =>
    `<label><span>${esc(f.欄位名)}${!f.可空 && !f.唯讀 ? '<b> *</b>' : ''}</span>${await input(f, head[f.欄位名], { isNew, lockPk: !isNew, auto: auto && f.主鍵 })}</label>`))).join('');
  const rowHtml = async r => `<tr>${(await Promise.all(dCols.map(async f =>
    `<td>${await input(f, r[f.欄位名], { isNew: true, lockPk: true, allRo: roDetail })}</td>`))).join('')}
    ${roDetail ? '' : '<td><button class="icon rm" type="button" title="刪除此列">✕</button></td>'}</tr>`;

  app.innerHTML = pageHead(d, isNew ? '新增' : (hk ? head[hk] : '修改')) + `
    <section class="card"><h3 class="card-t">${hasDetail ? '表頭資料' : '基本資料'}</h3><div class="form" id="head">${headHtml}</div></section>
    ${hasDetail ? `<section class="card"><div class="card-t row"><h3>明細${roDetail ? '<small>依用量清單自動展開</small>' : ''}</h3>
      ${ref ? `<button class="sub" id="pick" type="button">⇲ 從${esc(ref.標題)}帶入</button>` : ''}
      ${roDetail ? '' : '<button class="sub" id="addRow" type="button">＋ 明細</button>'}</div>
      <div class="tbl dt"><table><thead><tr>${dCols.map(f => `<th>${esc(f.欄位名)}</th>`).join('')}${roDetail ? '' : '<th></th>'}</tr></thead>
      <tbody id="rows">${(await Promise.all(lines.map(rowHtml))).join('')}</tbody></table></div></section>` : ''}
    <div class="actions"><button class="sub" onclick="location.hash='#/f/${code}'">返回</button><span></span>
      ${isNew ? '' : '<button class="del" id="del">刪除</button>'}<button id="save">儲存</button></div>`;

  if (hasDetail && !roDetail) {
    $('#addRow').onclick = async () => $('#rows').insertAdjacentHTML('beforeend', await rowHtml({}));
    if (isNew && !ref) $('#addRow').click();
    $('#rows').onclick = e => e.target.classList.contains('rm') && e.target.closest('tr').remove();
  }
  if (ref) $('#pick').onclick = () => pickRef(code, ref, async picked => {
    for (const r of picked) {
      Object.entries(r._表頭 || {}).forEach(([k, v]) => {   // 表頭空白才回填
        const el = $(`#head [data-f="${CSS.escape(k)}"]`); if (el && !el.value) el.value = v ?? '';
      });
      const blank = [...$('#rows').rows].find(tr => [...tr.querySelectorAll('[data-f]')].every(i => i.readOnly || !i.value));
      blank?.remove();
      $('#rows').insertAdjacentHTML('beforeend', await rowHtml(r._帶入));
    }
    toast(`已帶入 ${picked.length} 筆明細，請選擇倉庫並確認數量`, 'ok');
  });
  $('#save').onclick = async () => {
    const 主檔 = collect($('#head'));
    const 明細 = hasDetail && !roDetail ? [...$('#rows').rows].map(tr => collect(tr)) : [];
    try {
      const r = await submit('api_儲存', { 功能代碼: code, 資料: { 主檔, 明細 } }, `${d.功能名稱} ${主檔[hk] || '新單'}`);
      if (!r) return (location.hash = `#/f/${code}`);
      toast(`已儲存 ${r.主鍵 || ''}`, 'ok');
      const next = hasDetail ? `#/f/${code}/edit/${encodeURIComponent(JSON.stringify({ [hk]: r.主鍵 }))}` : `#/f/${code}`;
      if (location.hash === next) route(); else location.hash = next;
    } catch (e) { toast(e.message, 'err'); }
  };
  if ($('#del')) $('#del').onclick = async () => {
    if (!confirm('確定刪除？')) return;
    try {
      const r = await submit('api_刪除', { 功能代碼: code, 主鍵: key }, `刪除 ${d.功能名稱} ${Object.values(key).join('/')}`);
      if (r) toast('已刪除', 'ok');
      location.hash = `#/f/${code}`;
    } catch (e) { toast(e.message, 'err'); }
  };
}

/* 參照瀏覽視窗：來源與欄位對應全由 SQL（api_參照來源）決定，依表頭已填值篩選 */
async function pickRef(code, ref, done) {
  const rows = await get('api_參照來源', { 功能代碼: code, 表頭: JSON.stringify(collect($('#head'))) });
  const cols = ref.欄位;
  const dlg = document.createElement('dialog');
  dlg.className = 'modal';
  dlg.innerHTML = `<header><h3>${esc(ref.標題)}</h3><button class="icon" value="x">✕</button></header>
    <div class="tbl">${rows.length ? `<table><thead><tr><th><input type="checkbox" id="all"></th>${cols.map(c => `<th class="${c.型別 === 'int' ? 'n' : ''}">${esc(c.欄位名)}</th>`).join('')}</tr></thead>
      <tbody>${rows.map((r, i) => `<tr class="link"><td><input type="checkbox" data-i="${i}"></td>${cols.map(c => cell(r[c.欄位名], c)).join('')}</tr>`).join('')}</tbody></table>`
      : '<div class="empty">沒有可帶入的資料（已依表頭條件篩選）</div>'}</div>
    <footer><span id="cnt">已選 0 筆</span><button class="sub" value="x">取消</button><button id="ok" disabled>帶入明細</button></footer>`;
  document.body.append(dlg);
  const boxes = () => [...dlg.querySelectorAll('tbody input')];
  const sync = () => { const n = boxes().filter(b => b.checked).length; dlg.querySelector('#cnt').textContent = `已選 ${n} 筆`; dlg.querySelector('#ok').disabled = !n; };
  dlg.querySelector('tbody')?.addEventListener('click', e => {
    const tr = e.target.closest('tr'); if (!tr) return;
    if (e.target.type !== 'checkbox') { const b = tr.querySelector('input'); b.checked = !b.checked; }
    tr.classList.toggle('sel', tr.querySelector('input').checked); sync();
  });
  dlg.querySelector('#all')?.addEventListener('change', e => { boxes().forEach(b => { b.checked = e.target.checked; b.closest('tr').classList.toggle('sel', b.checked); }); sync(); });
  dlg.querySelectorAll('[value=x]').forEach(b => (b.onclick = () => dlg.close()));
  dlg.querySelector('#ok').onclick = () => { done(boxes().filter(b => b.checked).map(b => rows[b.dataset.i])); dlg.close(); };
  dlg.addEventListener('close', () => dlg.remove());
  dlg.showModal();
}

function viewOutbox() {
  setHead('待傳送', '#/');
  const items = box.all();
  app.innerHTML = `<div class="page-head"><h2>待傳送<small>斷線時暫存的資料，連線後自動重傳</small></h2></div><div class="toolbar"><button id="retry">立即重傳</button></div>${items.length ? `<div class="tbl"><table>
    <thead><tr><th>時間</th><th>內容</th><th>狀態</th><th></th></tr></thead><tbody>${items.map(x => `
    <tr><td>${esc(x.time)}</td><td>${esc(x.label)}</td><td class="${x.error ? 'err' : ''}">${esc(x.error || '等待連線')}</td>
    <td><button class="sub" data-id="${x.id}">移除</button></td></tr>`).join('')}</tbody></table></div>` : '<div class="empty">沒有待傳送的資料</div>'}`;
  $('#retry').onclick = async () => { box.all().forEach(x => x.error && box.patch(x.id, { error: null })); await flush(); viewOutbox(); };
  app.querySelectorAll('[data-id]').forEach(b => (b.onclick = () => { if (confirm('移除後此筆資料不會送出，確定？')) { box.remove(b.dataset.id); viewOutbox(); } }));
}

async function route() {
  const [, a, code, mode, key] = location.hash.split('/');
  try {
    if (a === 'outbox') viewOutbox();
    else if (a === 'f' && mode === 'new') await viewForm(code);
    else if (a === 'f' && mode === 'edit') await viewForm(code, decodeURIComponent(key));
    else if (a === 'f') await viewList(code);
    else await viewMenu();
  } catch (e) { app.innerHTML = `<div class="empty err">${esc(e.message)}</div>`; }
  scrollTo(0, 0);
}
addEventListener('hashchange', route);
if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js');
badge(); route(); flush();
