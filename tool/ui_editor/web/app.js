'use strict';

/* ————————————————————————————————————————————————
 * GRKU UI 编辑器前端
 * 组件面板与属性检查器完全由 /api/palette 驱动——服务端新增组件无需改本文件。
 * ———————————————————————————————————————————————— */

const TOKEN = new URLSearchParams(location.search).get('token') || '';
const DRAFT_KEY = 'uiEditor.doc.v1';

const state = {
  catalog: new Map(),
  order: [],
  doc: null,
  selectedId: 0,
  nextId: 1,
  name: 'MyWidget',
};

const $ = (id) => document.getElementById(id);

/* ————— 工具 ————— */

function uid() { return state.nextId++; }

function defaultProps(spec) {
  const props = {};
  for (const p of spec.props) {
    if (p.defaultValue !== null && p.defaultValue !== undefined) {
      props[p.name] = p.defaultValue;
    }
  }
  return props;
}

function createNode(type) {
  const spec = state.catalog.get(type);
  if (!spec) throw new Error('未知组件：' + type);
  return { id: uid(), type, props: defaultProps(spec), children: [] };
}

function findNode(id, node = state.doc, parent = null, index = -1) {
  if (!node) return null;
  if (node.id === id) return { node, parent, index };
  for (let i = 0; i < node.children.length; i++) {
    const hit = findNode(id, node.children[i], node, i);
    if (hit) return hit;
  }
  return null;
}

function containsNode(node, id) {
  if (!node) return false;
  if (node.id === id) return true;
  return node.children.some((c) => containsNode(c, id));
}

function specOf(node) {
  return state.catalog.get(node.type) || { type: node.type, children: 'none', props: [] };
}

function setStatus(text, kind) {
  const el = $('status');
  el.textContent = text || '';
  el.className = 'status' + (kind ? ' ' + kind : '');
}

/* ————— 启动 ————— */

async function boot() {
  try {
    const res = await fetch('/api/palette', {
      headers: { 'X-Editor-Token': TOKEN },
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || res.statusText);
    for (const spec of data) state.catalog.set(spec.type, spec);
    state.order = data.map((s) => s.type);
  } catch (err) {
    setStatus('无法加载组件目录：' + err.message, 'err');
    return;
  }

  if (!restoreDraft()) {
    newDocument(false);
  } else {
    $('className').value = state.name;
  }

  renderPalette('');
  renderAll();
  refreshPreview();
  bindGlobal();
  setStatus('就绪', 'ok');
}

function newDocument(confirmFirst = true) {
  if (confirmFirst && !confirm('新建会清空当前画布，确定继续？')) return;
  state.nextId = 1;
  const root = createNode('Column');
  const text = createNode('Text');
  root.children.push(text);
  state.doc = root;
  state.selectedId = root.id;
  state.name = $('className').value.trim() || 'MyWidget';
  commit();
}

function bindGlobal() {
  $('className').addEventListener('input', () => {
    state.name = $('className').value.trim() || 'MyWidget';
    saveDraft();
  });
  $('btnSave').addEventListener('click', save);
  $('btnNew').addEventListener('click', () => newDocument(true));
  $('paletteSearch').addEventListener('input', (e) => renderPalette(e.target.value));
  document.addEventListener('keydown', onKeyDown);
}

function onKeyDown(e) {
  const tag = (document.activeElement || {}).tagName || '';
  const editing = tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT';
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') {
    e.preventDefault();
    save();
    return;
  }
  if (editing) return;
  if (e.key === 'Delete' || e.key === 'Backspace') {
    e.preventDefault();
    removeNode(state.selectedId);
  } else if (e.key === 'Escape') {
    select(null);
  }
}

/* ————— 组件面板 ————— */

function renderPalette(filter) {
  const host = $('paletteList');
  host.textContent = '';
  const needle = (filter || '').trim().toLowerCase();
  const byCategory = new Map();
  for (const type of state.order) {
    const spec = state.catalog.get(type);
    if (needle && !type.toLowerCase().includes(needle)) continue;
    if (!byCategory.has(spec.category)) byCategory.set(spec.category, []);
    byCategory.get(spec.category).push(spec);
  }
  if (byCategory.size === 0) {
    const empty = document.createElement('div');
    empty.className = 'muted';
    empty.textContent = '没有匹配的组件';
    host.appendChild(empty);
    return;
  }
  for (const [category, specs] of byCategory) {
    const head = document.createElement('div');
    head.className = 'cat';
    head.textContent = category;
    host.appendChild(head);
    for (const spec of specs) {
      const item = document.createElement('div');
      item.className = 'pal-item';
      item.textContent = spec.type;
      item.draggable = true;
      item.addEventListener('dragstart', (e) => {
        e.dataTransfer.setData('application/x-ui-type', spec.type);
        e.dataTransfer.effectAllowed = 'copy';
      });
      host.appendChild(item);
    }
  }
}

/* ————— 画布 ————— */

function renderAll() {
  renderCanvas();
  renderInspector();
}

function renderCanvas() {
  const host = $('canvas');
  const keep = host.scrollTop;
  host.textContent = '';
  if (state.doc) host.appendChild(renderNode(state.doc));
  host.scrollTop = keep;
  renderBreadcrumb();
}

function renderNode(node) {
  const spec = specOf(node);
  const wrap = document.createElement('div');
  wrap.className = 'node' + (node.id === state.selectedId ? ' sel' : '');
  wrap.dataset.id = String(node.id);
  wrap.addEventListener('click', (e) => {
    e.stopPropagation();
    select(node.id);
  });

  // 头部：类型标签（可拖拽移动）+ 删除
  const head = document.createElement('div');
  head.className = 'node-head';
  const tag = document.createElement('span');
  tag.className = 'node-tag';
  tag.textContent = node.type;
  head.appendChild(tag);
  if (node.id !== state.doc.id) {
    const del = document.createElement('button');
    del.type = 'button';
    del.className = 'mini';
    del.textContent = '删除';
    del.addEventListener('click', (e) => {
      e.stopPropagation();
      removeNode(node.id);
    });
    head.appendChild(del);
  }
  head.draggable = true;
  head.addEventListener('dragstart', (e) => {
    e.stopPropagation();
    e.dataTransfer.setData('application/x-ui-node', String(node.id));
    e.dataTransfer.effectAllowed = 'move';
  });
  wrap.appendChild(head);

  const body = document.createElement('div');
  body.className = 'node-body';
  styleBody(body, node, spec);
  wrap.appendChild(body);

  if (spec.children === 'multi') {
    if (node.children.length === 0) {
      body.appendChild(makeSlot(node, 0, true));
    } else {
      for (let i = 0; i <= node.children.length; i++) {
        body.appendChild(makeSlot(node, i, false));
        if (i < node.children.length) body.appendChild(renderNode(node.children[i]));
      }
    }
  } else if (spec.children === 'single') {
    // 单子节点容器满员后不再显示插槽，避免拖入第二个子节点生成非法树。
    if (node.children.length === 0) {
      body.appendChild(makeSlot(node, 0, true));
    } else {
      body.appendChild(renderNode(node.children[0]));
    }
  } else {
    body.appendChild(renderLeaf(node, spec));
  }
  return wrap;
}

function styleBody(body, node, spec) {
  const p = node.props || {};
  const type = node.type;
  if (type === 'Column') {
    body.style.display = 'flex';
    body.style.flexDirection = 'column';
    body.style.gap = '6px';
    body.style.alignItems = alignValue(p.crossAxisAlignment);
    body.style.justifyContent = justifyValue(p.mainAxisAlignment);
  } else if (type === 'Row') {
    body.style.display = 'flex';
    body.style.flexDirection = 'row';
    body.style.gap = '6px';
    body.style.alignItems = alignValue(p.crossAxisAlignment);
    body.style.justifyContent = justifyValue(p.mainAxisAlignment);
  } else if (type === 'Container') {
    if (p.padding != null) body.style.padding = p.padding + 'px';
    if (p.width != null) body.style.width = p.width + 'px';
    if (p.height != null) body.style.height = p.height + 'px';
    if (p.color) body.style.background = p.color;
    if (p.radius != null) body.style.borderRadius = p.radius + 'px';
  } else if (type === 'Padding') {
    body.style.padding = (p.padding != null ? p.padding : 12) + 'px';
  } else if (type === 'Center') {
    body.style.display = 'flex';
    body.style.alignItems = 'center';
    body.style.justifyContent = 'center';
    body.style.minHeight = '40px';
  } else if (type === 'SizedBox') {
    body.style.width = (p.width != null ? p.width : 24) + 'px';
    body.style.height = (p.height != null ? p.height : 24) + 'px';
  } else if (type === 'Card') {
    body.classList.add('pv-card');
  }
}

function alignValue(v) {
  switch (v) {
    case 'start': return 'flex-start';
    case 'end': return 'flex-end';
    case 'center': return 'center';
    case 'stretch': return 'stretch';
    case 'baseline': return 'baseline';
    default: return 'center';
  }
}

function justifyValue(v) {
  switch (v) {
    case 'center': return 'center';
    case 'end': return 'flex-end';
    case 'spaceBetween': return 'space-between';
    case 'spaceAround': return 'space-around';
    case 'spaceEvenly': return 'space-evenly';
    default: return 'flex-start';
  }
}

function renderLeaf(node, spec) {
  const p = node.props || {};
  const type = node.type;
  let el;

  if (type === 'Text') {
    el = document.createElement('span');
    el.className = 'pv-text';
    el.textContent = p.data != null ? String(p.data) : 'Text';
    if (p.fontSize != null) el.style.fontSize = p.fontSize + 'px';
    if (p.color) el.style.color = p.color;
    if (p.bold) el.style.fontWeight = '700';
  } else if (type === 'Icon') {
    el = document.createElement('span');
    el.className = 'pv-icon';
    el.textContent = '◈ ' + (p.icon || 'add');
    if (p.size != null) el.style.fontSize = p.size + 'px';
    if (p.color) el.style.color = p.color;
  } else if (type === 'Divider') {
    el = document.createElement('hr');
    el.style.border = 'none';
    el.style.borderTop = '1px solid var(--border)';
    el.style.width = '100%';
    if (p.height != null) el.style.margin = p.height / 2 + 'px 0';
  } else if (type === 'ElevatedButton') {
    el = document.createElement('span');
    el.className = 'pv-button';
    el.textContent = p.label != null ? String(p.label) : '按钮';
    if (p.enabled === false) el.style.opacity = '.5';
  } else if (type === 'IconButton') {
    el = document.createElement('span');
    el.className = 'pv-icon';
    el.textContent = '◈ ' + (p.icon || 'add');
    if (p.enabled === false) el.style.opacity = '.5';
  } else if (type === 'TextField') {
    el = document.createElement('div');
    el.className = 'pv-input';
    el.textContent = p.hint || p.label || '输入框';
  } else if (type === 'Checkbox') {
    el = document.createElement('label');
    el.className = 'pv-checkbox';
    const box = document.createElement('input');
    box.type = 'checkbox';
    box.checked = !!p.value;
    box.disabled = true;
    el.appendChild(box);
    el.appendChild(document.createTextNode('复选'));
  } else if (type.startsWith('Image.')) {
    el = document.createElement('div');
    el.className = 'pv-image';
    el.textContent = '🖼 ' + (p.src || p.name || p.path || '');
    if (p.width != null) el.style.width = p.width + 'px';
    if (p.height != null) el.style.height = p.height + 'px';
  } else {
    el = document.createElement('span');
    el.className = 'muted';
    el.textContent = '<' + type + '>';
  }
  return el;
}

function makeSlot(parent, index, empty) {
  const slot = document.createElement('div');
  slot.className = 'slot' + (empty ? ' empty-slot' : '');
  if (empty) slot.textContent = '拖组件到这里';
  slot.addEventListener('dragover', (e) => {
    e.preventDefault();
    e.stopPropagation();
    slot.classList.add('hover');
  });
  slot.addEventListener('dragleave', () => slot.classList.remove('hover'));
  slot.addEventListener('drop', (e) => {
    e.preventDefault();
    e.stopPropagation();
    slot.classList.remove('hover');
    handleDrop(e, parent, index);
  });
  return slot;
}

function handleDrop(e, parent, index) {
  const type = e.dataTransfer.getData('application/x-ui-type');
  const nodeId = e.dataTransfer.getData('application/x-ui-node');

  if (type) {
    const node = createNode(type);
    parent.children.splice(index, 0, node);
    state.selectedId = node.id;
    commit();
    return;
  }
  if (!nodeId) return;

  const id = Number(nodeId);
  const found = findNode(id);
  if (!found || !found.parent) return;
  if (containsNode(found.node, parent.id)) return; // 不能拖进自己的子树

  let target = index;
  if (found.parent === parent && found.index < index) target -= 1;
  found.parent.children.splice(found.index, 1);
  parent.children.splice(target, 0, found.node);
  state.selectedId = id;
  commit();
}

function select(id) {
  state.selectedId = id;
  const keep = $('canvas').scrollTop;
  renderCanvas();
  $('canvas').scrollTop = keep;
  renderInspector();
  saveDraft();
}

function removeNode(id) {
  if (!id || id === state.doc.id) return;
  const found = findNode(id);
  if (!found || !found.parent) return;
  found.parent.children.splice(found.index, 1);
  if (state.selectedId === id) state.selectedId = state.doc.id;
  commit();
}

function renderBreadcrumb() {
  const host = $('breadcrumb');
  host.textContent = '';
  const path = [];
  (function walk(node) {
    path.push(node);
    if (node.id === state.selectedId) return true;
    return node.children.some(walk) ? true : (path.pop(), false);
  })(state.doc);
  path.forEach((node, i) => {
    if (i > 0) host.appendChild(document.createTextNode(' › '));
    const span = document.createElement('span');
    span.className = 'crumb';
    span.textContent = node.type;
    span.addEventListener('click', () => select(node.id));
    host.appendChild(span);
  });
}

/* ————— 属性检查器 ————— */

function renderInspector() {
  const host = $('inspectorBody');
  host.textContent = '';
  const found = findNode(state.selectedId);
  if (!found) {
    const hint = document.createElement('div');
    hint.className = 'muted';
    hint.textContent = '未选中节点';
    host.appendChild(hint);
    return;
  }
  const node = found.node;
  const spec = specOf(node);
  if (spec.props.length === 0) {
    const hint = document.createElement('div');
    hint.className = 'muted';
    hint.textContent = node.type + ' 没有可配置属性';
    host.appendChild(hint);
    return;
  }
  for (const prop of spec.props) {
    host.appendChild(propControl(node, prop));
  }
}

function propControl(node, prop) {
  const wrap = document.createElement('div');
  wrap.className = 'prop';
  const set = Object.prototype.hasOwnProperty.call(node.props, prop.name);
  const value = set ? node.props[prop.name] : prop.defaultValue;

  const label = document.createElement('label');
  label.textContent = prop.label || prop.name;
  wrap.appendChild(label);

  if (prop.nullable && !set) {
    const row = document.createElement('div');
    row.className = 'unset-row';
    const hint = document.createElement('span');
    hint.className = 'muted';
    hint.textContent = '（未设置）';
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'mini';
    btn.textContent = '设置';
    btn.addEventListener('click', () => {
      node.props[prop.name] = fallbackValue(prop);
      commit();
    });
    row.appendChild(hint);
    row.appendChild(btn);
    wrap.appendChild(row);
    return wrap;
  }

  const control = controlFor(prop, value, (v) => {
    node.props[prop.name] = v;
    commit();
  });
  wrap.appendChild(control);

  if (prop.nullable) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'mini';
    btn.textContent = '取消设置';
    btn.style.marginTop = '4px';
    btn.addEventListener('click', () => {
      delete node.props[prop.name];
      commit();
    });
    wrap.appendChild(btn);
  }
  return wrap;
}

function fallbackValue(prop) {
  switch (prop.type) {
    case 'color': return '#3B82F6';
    case 'double':
    case 'int': return 0;
    case 'edgeInsets': return 12;
    case 'borderRadius': return 12;
    case 'bool': return true;
    case 'enumValue': return prop.values[0] || '';
    case 'icon':
    case 'iconWidget': return prop.values[0] || 'add';
    default: return '';
  }
}

function controlFor(prop, value, onChange) {
  const type = prop.type;
  if (type === 'bool' || type === 'fontWeight') {
    const row = document.createElement('div');
    row.className = 'row';
    const input = document.createElement('input');
    input.type = 'checkbox';
    input.checked = !!value;
    input.addEventListener('change', () => onChange(input.checked));
    row.appendChild(input);
    const text = document.createElement('span');
    text.className = 'muted';
    text.textContent = input.checked ? 'true' : 'false';
    input.addEventListener('change', () => { text.textContent = input.checked ? 'true' : 'false'; });
    row.appendChild(text);
    return row;
  }

  if (type === 'enumValue' || type === 'icon' || type === 'iconWidget') {
    const select = document.createElement('select');
    for (const option of prop.values) {
      const opt = document.createElement('option');
      opt.value = option;
      opt.textContent = option;
      select.appendChild(opt);
    }
    select.value = value != null ? String(value) : '';
    select.addEventListener('change', () => onChange(select.value));
    return select;
  }

  if (type === 'color') {
    const row = document.createElement('div');
    row.className = 'row';
    const picker = document.createElement('input');
    picker.type = 'color';
    picker.value = normalizeHex(value);
    const text = document.createElement('input');
    text.type = 'text';
    text.value = value != null ? String(value) : '';
    text.placeholder = '#RRGGBB';
    picker.addEventListener('input', () => { text.value = picker.value.toUpperCase(); onChange(picker.value.toUpperCase()); });
    text.addEventListener('change', () => { picker.value = normalizeHex(text.value); onChange(text.value.trim()); });
    row.appendChild(picker);
    row.appendChild(text);
    return row;
  }

  if (type === 'double' || type === 'int' || type === 'edgeInsets' || type === 'borderRadius') {
    const input = document.createElement('input');
    input.type = 'number';
    input.step = type === 'int' ? '1' : '1';
    input.value = value != null ? value : '';
    input.addEventListener('change', () => {
      const n = Number(input.value);
      onChange(Number.isFinite(n) ? n : 0);
    });
    return input;
  }

  if (type === 'multilineString') {
    const area = document.createElement('textarea');
    area.value = value != null ? String(value) : '';
    area.addEventListener('change', () => onChange(area.value));
    return area;
  }

  const input = document.createElement('input');
  input.type = 'text';
  input.value = value != null ? String(value) : '';
  input.addEventListener('change', () => onChange(input.value));
  return input;
}

function normalizeHex(v) {
  if (typeof v !== 'string') return '#3b82f6';
  const s = v.trim().replace('#', '');
  if (/^[0-9a-fA-F]{6}$/.test(s)) return '#' + s.toLowerCase();
  if (/^[0-9a-fA-F]{8}$/.test(s)) return '#' + s.slice(2).toLowerCase();
  return '#3b82f6';
}

/* ————— 代码预览 ————— */

let previewTimer = null;

function schedulePreview() {
  clearTimeout(previewTimer);
  previewTimer = setTimeout(refreshPreview, 300);
}

async function refreshPreview() {
  const codeEl = $('code');
  try {
    const res = await fetch('/api/preview', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Editor-Token': TOKEN },
      body: JSON.stringify({ tree: state.doc }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || res.statusText);
    codeEl.textContent = data.code;
  } catch (err) {
    codeEl.textContent = '// 预览失败：' + err.message;
  }
}

/* ————— 保存 ————— */

async function save() {
  const name = ($('className').value || '').trim();
  if (!name) { setStatus('请填写类名', 'err'); return; }
  try {
    let res = await postSave(name, false);
    if (res.status === 409) {
      if (!confirm(name + '.dart 已存在，确定覆盖？')) return;
      res = await postSave(name, true);
    }
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || res.statusText);
    $('code').textContent = data.code;
    setStatus('已保存 → ' + data.path, 'ok');
    saveDraft();
  } catch (err) {
    setStatus('保存失败：' + err.message, 'err');
  }
}

function postSave(name, overwrite) {
  return fetch('/api/save', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Editor-Token': TOKEN },
    body: JSON.stringify({ name, tree: state.doc, overwrite }),
  });
}

/* ————— 草稿（localStorage） ————— */

function commit() {
  saveDraft();
  renderAll();
  schedulePreview();
}

function saveDraft() {
  try {
    localStorage.setItem(DRAFT_KEY, JSON.stringify({
      name: state.name,
      doc: state.doc,
      nextId: state.nextId,
      selectedId: state.selectedId,
    }));
  } catch (_) {
    /* 忽略隐私模式下的写入失败 */
  }
}

function restoreDraft() {
  let raw = null;
  try { raw = localStorage.getItem(DRAFT_KEY); } catch (_) { return false; }
  if (!raw) return false;
  try {
    const data = JSON.parse(raw);
    if (!data || !data.doc || !data.doc.type) return false;
    state.doc = data.doc;
    state.nextId = data.nextId || 1000;
    state.selectedId = data.selectedId || data.doc.id;
    state.name = data.name || 'MyWidget';
    $('className').value = state.name;
    return true;
  } catch (_) {
    return false;
  }
}

boot();
