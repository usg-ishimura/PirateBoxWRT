(function () {
  'use strict';

  var $ = function (s) { return document.querySelector(s); };
  var root = document.documentElement;
  var store = {
    get: function (k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
    set: function (k, v) { try { localStorage.setItem(k, v); } catch (e) {} }
  };

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  function api(name, opt) {
    return fetch('/cgi-bin/' + name, opt).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (d) {
        if (!r.ok) throw new Error(d.error || ('Error ' + r.status));
        return d;
      });
    });
  }

  function post(name, data) {
    data.t = Math.floor(Date.now() / 1000);
    data.n = nick();
    return api(name, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
  }

  function nick() { return $('#nick').value.trim(); }

  function fmt(b) {
    if (b < 1024) return b + ' B';
    if (b < 1048576) return (b / 1024).toFixed(1) + ' KB';
    if (b < 1073741824) return (b / 1048576).toFixed(1) + ' MB';
    return (b / 1073741824).toFixed(2) + ' GB';
  }

  var noteTimer;
  function note(msg, isErr) {
    var n = $('#note');
    n.textContent = msg;
    n.className = isErr ? 'err' : '';
    n.hidden = false;
    clearTimeout(noteTimer);
    noteTimer = setTimeout(function () { n.hidden = true; }, 5000);
  }
  function fail(e) { note(e.message || 'Network error', true); }

  /* tema */
  $('#theme').onclick = function () {
    var t = root.dataset.theme === 'dark' ? 'light' : 'dark';
    root.dataset.theme = t;
    store.set('pb-theme', t);
  };

  /* nome */
  $('#nick').value = store.get('pb-nick') || '';
  $('#nick').onchange = function () { store.set('pb-nick', nick()); };

  /* file */
  var limit = 0;

  var KINDS = {
    image: 'jpg jpeg png gif webp bmp avif',
    video: 'mp4 m4v webm ogv mov',
    audio: 'mp3 ogg oga opus wav m4a aac flac',
    pdf: 'pdf',
    text: 'txt md log json csv'
  };

  function kindOf(name) {
    var m = /\.([^.]+)$/.exec(name);
    if (!m) return null;
    var ext = m[1].toLowerCase();
    for (var k in KINDS) if (KINDS[k].split(' ').indexOf(ext) >= 0) return k;
    return null;
  }

  function preview(f, kind) {
    var url = '/files/' + encodeURIComponent(f.name);
    var stream = '/cgi-bin/get?name=' + encodeURIComponent(f.name);
    var body = $('#m-body');
    var m = null;
    body.textContent = '';
    $('#m-title').textContent = f.name;
    $('#m-dl').href = url;
    $('#m-dl').setAttribute('download', f.name);

    if (kind === 'image') { m = el('img'); m.src = url; m.alt = f.name; }
    else if (kind === 'video') { m = el('video'); m.controls = true; m.playsInline = true; m.src = stream; }
    else if (kind === 'audio') { m = el('audio'); m.controls = true; m.src = stream; }
    else if (kind === 'pdf') { m = el('iframe'); m.src = url; m.title = f.name; }
    else if (f.size > 524288) body.appendChild(el('p', 'muted', 'File too large to preview.'));
    else {
      m = el('pre', null, 'Loading...');
      fetch(url).then(function (r) { return r.text(); })
        .then(function (t) { m.textContent = t; })
        .catch(function () { m.textContent = 'Unable to load the file.'; });
    }
    if (m) body.appendChild(m);
    if (kind === 'video' || kind === 'audio') {
      var p = m.play();
      if (p && p.catch) p.catch(function () {});
    }

    $('#modal').hidden = false;
    document.body.classList.add('lock');
    $('#m-close').focus();
  }

  function closeModal() {
    var body = $('#m-body');
    var v = body.querySelector('video, audio');
    if (v) { v.pause(); v.removeAttribute('src'); v.load(); }
    body.textContent = '';
    $('#modal').hidden = true;
    document.body.classList.remove('lock');
  }

  $('#m-close').onclick = closeModal;
  $('#modal').onclick = function (e) { if (e.target === this) closeModal(); };
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !$('#modal').hidden) closeModal();
  });

  function loadFiles() {
    api('files').then(function (d) {
      limit = d.limit;
      $('#limit').textContent = 'Maximum size per file: ' + fmt(d.limit);
      var ul = $('#files');
      ul.textContent = '';
      if (!d.files.length) ul.appendChild(el('li', null, 'No files shared yet.'));
      d.files.forEach(function (f) {
        var li = el('li');
        var a = el('a', null, f.name);
        a.href = '/files/' + encodeURIComponent(f.name);
        a.setAttribute('download', f.name);
        var kind = kindOf(f.name);
        if (kind) a.onclick = function (e) { e.preventDefault(); preview(f, kind); };
        li.appendChild(a);
        var label = kind ? (kind === 'video' || kind === 'audio' ? 'Play' : 'View') + ' \u00b7 ' : '';
        li.appendChild(el('small', null, label + fmt(f.size)));
        ul.appendChild(li);
      });
    }).catch(fail);
  }

  function uploadOne(file, done) {
    if (file.size > limit) {
      note(file.name + ': too large (max ' + fmt(limit) + ')', true);
      return done();
    }
    var x = new XMLHttpRequest();
    x.open('POST', '/cgi-bin/upload?name=' + encodeURIComponent(file.name));
    x.upload.onprogress = function (e) {
      if (e.lengthComputable) $('#bar').value = e.loaded * 100 / e.total;
    };
    x.onload = function () {
      var d = {};
      try { d = JSON.parse(x.responseText); } catch (e) {}
      if (x.status === 200) note('Uploaded: ' + d.name);
      else note(file.name + ': ' + (d.error || 'error ' + x.status), true);
      done();
    };
    x.onerror = function () { note(file.name + ': network error', true); done(); };
    x.send(file);
  }

  $('#file').onchange = function () {
    var q = Array.prototype.slice.call(this.files);
    var input = this;
    $('#bar').hidden = false;
    (function next() {
      var f = q.shift();
      if (!f) {
        $('#bar').hidden = true;
        input.value = '';
        return loadFiles();
      }
      $('#bar').value = 0;
      uploadOne(f, next);
    })();
  };

  /* forum */
  function when(t) { return new Date(t * 1000).toLocaleString([], { dateStyle: 'short', timeStyle: 'short' }); }

  function loadThreads() {
    $('#f-list').hidden = false;
    $('#f-thread').hidden = true;
    api('forum').then(function (d) {
      var ul = $('#threads');
      ul.textContent = '';
      if (!d.threads.length) ul.appendChild(el('li', null, 'No threads yet.'));
      d.threads.forEach(function (t) {
        var li = el('li');
        var a = el('a', null, t.title);
        a.href = '#forum/' + t.id;
        li.appendChild(a);
        li.appendChild(el('small', null, t.n + ' \u00b7 ' + t.replies));
        ul.appendChild(li);
      });
    }).catch(fail);
  }

  var thread = null;

  function openThread(id) {
    thread = id;
    $('#f-list').hidden = true;
    $('#f-thread').hidden = false;
    api('forum?thread=' + encodeURIComponent(id)).then(function (d) {
      var box = $('#posts');
      box.textContent = '';
      d.posts.forEach(function (p, i) {
        if (i === 0) $('#th-title').textContent = p.title;
        var div = el('div', 'post');
        var head = el('div');
        head.appendChild(el('b', null, p.n));
        head.appendChild(el('small', null, when(p.t)));
        div.appendChild(head);
        div.appendChild(el('div', null, p.m));
        box.appendChild(div);
      });
    }).catch(function (e) { fail(e); location.hash = '#forum'; });
  }

  $('#f-new').onsubmit = function (e) {
    e.preventDefault();
    var f = this;
    post('forum', { title: f.title.value, m: f.m.value }).then(function (d) {
      f.reset();
      location.hash = '#forum/' + d.id;
    }).catch(fail);
  };

  $('#f-reply').onsubmit = function (e) {
    e.preventDefault();
    var f = this;
    post('forum', { thread: thread, m: f.m.value }).then(function () {
      f.reset();
      openThread(thread);
    }).catch(fail);
  };

  /* chat */
  var chat = { pos: -1, seen: {}, busy: false };

  function addMsg(m) {
    if (chat.seen[m.id]) return;
    chat.seen[m.id] = 1;
    var d = el('div', 'msg');
    var head = el('div');
    head.appendChild(el('b', null, m.n));
    head.appendChild(el('small', null, new Date(m.t * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })));
    d.appendChild(head);
    d.appendChild(el('div', null, m.m));
    $('#log').appendChild(d);
  }

  function pollChat() {
    if (document.hidden || chat.busy) return;
    chat.busy = true;
    api('chat?since=' + chat.pos).then(function (d) {
      var log = $('#log');
      var stick = chat.pos < 0 || log.scrollTop + log.clientHeight >= log.scrollHeight - 40;
      chat.pos = d.pos;
      d.msgs.forEach(addMsg);
      if (stick) log.scrollTop = log.scrollHeight;
    }).catch(function () {}).then(function () { chat.busy = false; });
  }

  $('#c-form').onsubmit = function (e) {
    e.preventDefault();
    var f = this;
    post('chat', { m: f.m.value }).then(function () {
      f.reset();
      pollChat();
    }).catch(fail);
  };

  /* routing */
  var views = ['files', 'forum', 'chat'];
  var timer = null;

  function route() {
    closeModal();
    var p = (location.hash || '#files').slice(1).split('/');
    var v = views.indexOf(p[0]) < 0 ? 'files' : p[0];
    views.forEach(function (n) {
      $('#v-' + n).hidden = n !== v;
      $('#t-' + n).classList.toggle('on', n === v);
    });
    clearInterval(timer);
    timer = null;
    if (v === 'files') loadFiles();
    else if (v === 'forum') { if (p[1]) openThread(p[1]); else loadThreads(); }
    else {
      chat.pos = -1;
      chat.seen = {};
      $('#log').textContent = '';
      pollChat();
      timer = setInterval(pollChat, 3000);
    }
  }

  window.addEventListener('hashchange', route);
  route();
})();
