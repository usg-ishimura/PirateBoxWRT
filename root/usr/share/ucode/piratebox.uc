// PirateBox: libreria condivisa dagli script CGI (ucode, incluso in OpenWrt >= 22.03)
'use strict';

import * as fs from 'fs';

const RESERVE = 2 * 1024 * 1024; // spazio libero da non consumare mai
const MAX_JSON = 16384;
const DANGEROUS = { html: 1, htm: 1, xhtml: 1, shtml: 1, svg: 1, xml: 1, xsl: 1, xslt: 1, js: 1, mjs: 1 };
const REASONS = {
	'200': 'OK', '400': 'Bad Request', '403': 'Forbidden', '404': 'Not Found',
	'405': 'Method Not Allowed', '413': 'Payload Too Large', '507': 'Insufficient Storage'
};

let cfg;

function q(s) {
	return "'" + replace(s, "'", "'\\''") + "'";
}

function exists(p) {
	return fs.stat(p) != null;
}

/* ------------------------------------------------------------ config */

function config() {
	if (cfg)
		return cfg;

	cfg = { path: '/srv/piratebox', max_upload_mb: '512' };

	let txt = fs.readfile('/etc/config/piratebox');
	for (let line in split(txt ? txt : '', '\n')) {
		let m = match(line, /^[ \t]*option[ \t]+([A-Za-z0-9_]+)[ \t]+'(.*)'[ \t]*$/);
		if (m && m[2] != '')
			cfg[m[1]] = m[2];
	}

	let mb = int(cfg.max_upload_mb);
	cfg.max_bytes = (mb > 0 ? mb : 512) * 1048576;
	return cfg;
}

function path(sub) {
	let p = config().path;
	return sub ? p + '/' + sub : p;
}

function mkdir(p) {
	system(['mkdir', '-p', p]);
}

/* Voci visibili di una cartella, dalla piu' recente: [{name, size, mtime, dir}] */
function list(dir) {
	let out = [];
	for (let n in (fs.lsdir(dir) || [])) {
		if (substr(n, 0, 1) == '.')
			continue;
		let st = fs.stat(dir + '/' + n);
		if (st)
			push(out, { name: n, size: st.size, mtime: st.mtime, dir: st.type == 'directory' });
	}
	return sort(out, (a, b) => b.mtime - a.mtime);
}

function free_bytes(p) {
	let h = fs.popen('df -k ' + q(p) + ' 2>/dev/null', 'r');
	if (!h)
		return null;
	let out = h.read('all');
	h.close();
	let m = match(out, /[ \t]+[0-9]+[ \t]+[0-9]+[ \t]+([0-9]+)[ \t]+[0-9]+%/);
	return m ? int(m[1]) * 1024 : null;
}

function upload_limit() {
	let lim = config().max_bytes;
	let free = free_bytes(path());
	if (free != null && free - RESERVE < lim)
		lim = free - RESERVE;
	return lim > 0 ? lim : 0;
}

function rand(n) {
	let f = fs.open('/dev/urandom', 'r');
	let s = f ? f.read(n) : '';
	if (f)
		f.close();
	let out = '';
	for (let i = 0; i < n; i++)
		out += sprintf('%02x', i < length(s) ? ord(s, i) : (time() * 31 + i * 7919) % 256);
	return out;
}

/* ------------------------------------------------------------ JSON / HTTP */

function encode(v) {
	return sprintf('%J', v);
}

function decode(s) {
	try {
		return json(s);
	}
	catch (e) {
		return null;
	}
}

function send(status, body) {
	print('Status: ', status, ' ', REASONS[sprintf('%d', status)] || 'Error', '\r\n',
		'Content-Type: application/json; charset=utf-8\r\n',
		'Cache-Control: no-store\r\n',
		'X-Content-Type-Options: nosniff\r\n\r\n', body);
	exit(0);
}

function reply(v) {
	send(200, encode(v));
}

function fail(status, msg) {
	send(status, encode({ error: msg }));
}

function method() {
	return getenv('REQUEST_METHOD') || 'GET';
}

function urldecode(s) {
	s = replace(s, '+', ' ');
	return replace(s, /%([0-9a-fA-F]{2})/g, (m, h) => chr(hex(h)));
}

function query() {
	let t = {};
	for (let kv in split(getenv('QUERY_STRING') || '', '&')) {
		let i = index(kv, '=');
		let k = i < 0 ? kv : substr(kv, 0, i);
		if (k != '')
			t[urldecode(k)] = i < 0 ? '' : urldecode(substr(kv, i + 1));
	}
	return t;
}

function content_length() {
	let n = int(getenv('CONTENT_LENGTH') || 0);
	return n > 0 ? n : 0;
}

/* Corpo JSON di una POST, come oggetto */
function input() {
	let len = content_length();
	if (len <= 0 || len > MAX_JSON)
		fail(413, 'Invalid or oversized request');
	let d = decode(fs.stdin.read(len));
	if (type(d) != 'object')
		fail(400, 'Invalid JSON');
	return d;
}

/* ------------------------------------------------------------ input utente */

function ucut(s, max) {
	let n = 0;
	for (let i = 0; i < length(s); i++) {
		let c = ord(s, i);
		if (c < 0x80 || c >= 0xC0) {
			n++;
			if (n > max)
				return substr(s, 0, i);
		}
	}
	return s;
}

function clean(s, max, multiline) {
	if (type(s) != 'string')
		return '';

	let out = '';
	for (let i = 0; i < length(s); i++) {
		let c = ord(s, i);
		if (c == 13) {
			c = 10;
			if (ord(s, i + 1) == 10)
				i++;
		}
		if (c == 10 || c == 9)
			out += multiline ? chr(c) : ' ';
		else if (c < 32 || c == 127)
			out += multiline ? '' : ' ';
		else
			out += substr(s, i, 1);
	}
	return trim(ucut(out, max));
}

/* Timestamp dichiarato dal client (il router spesso non ha un orologio valido) */
function stamp(t) {
	if ((type(t) == 'int' || type(t) == 'double') && t > 1e9 && t < 4e9)
		return int(t);
	return time();
}

/* Nome file sicuro; i formati eseguibili dal browser diventano .txt (niente XSS da upload) */
function filename(raw) {
	let n = '';
	raw = type(raw) == 'string' ? raw : '';
	for (let i = 0; i < length(raw); i++) {
		let c = ord(raw, i);
		n += (c < 32 || c == 127 || index('/\\:*?"<>|', substr(raw, i, 1)) >= 0) ? '_' : substr(raw, i, 1);
	}
	n = rtrim(ltrim(n, '. \t'), ' \t');

	if (length(n) > 150) {
		n = substr(n, 0, 150);
		let k = length(n) - 1;
		while (k > 0 && (ord(n, k) & 0xC0) == 0x80)
			k--;
		let lead = ord(n, k);
		let need = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1;
		if (length(n) - k < need)
			n = substr(n, 0, k);
	}

	if (n == '')
		n = 'file';

	let m = match(n, /\.([^.]+)$/);
	if (m && DANGEROUS[lc(m[1])])
		n += '.txt';
	return n;
}

function unique(dir, n) {
	if (!exists(dir + '/' + n))
		return n;
	let m = match(n, /^(.+)(\.[^.]*)$/);
	let base = m ? m[1] : n;
	let ext = m ? m[2] : '';
	let i = 1;
	while (exists(dir + '/' + base + '-' + i + ext))
		i++;
	return base + '-' + i + ext;
}

export {
	exists, config, path, mkdir, list, free_bytes, upload_limit, rand,
	encode, decode, send, reply, fail, method, urldecode, query,
	content_length, input, clean, stamp, filename, unique
};
