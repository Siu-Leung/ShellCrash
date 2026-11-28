#!/usr/bin/env python3
"""Loopback-only integration harness. Never logs authentication material."""
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import urllib.parse

REPO = Path(__file__).resolve().parent.parent
AUDIT = Path(os.environ.get('PANEL_OPENWRT_AUDIT') or '/nonexistent')
SELECTORS = '{"proxies":{"Group A":{"type":"Selector","all":["Default","选择"],"now":"选择","name":"Group A","tail":0}}}'
SECRET = 'test-secret-do-not-log'

class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *args):
        pass
    def handle_request(self):
        length = int(self.headers.get('Content-Length', '0'))
        body = self.rfile.read(length)
        expected = self.server.expected
        auth = self.headers.get('Authorization', '')
        auth_valid = auth == ('Bearer ' + expected) if expected else auth in ('', 'Bearer ')
        self.server.requests.append((self.command, self.path, body, auth_valid,
                                     self.headers.get('Content-Type', '')))
        status = self.server.status if auth_valid else 401
        payload = SELECTORS.encode() if self.command == 'GET' and status == 200 else b''
        self.send_response(status)
        if status == 302:
            self.send_header('Location', 'http://127.0.0.2:1/must-not-follow')
        if self.server.mode == 'chunked' and payload:
            self.send_header('Transfer-Encoding', 'chunked')
        else:
            self.send_header('Content-Length', str(len(payload) + (10 if self.server.mode == 'truncated' else 0)))
        self.send_header('Connection', 'close')
        self.end_headers()
        if payload:
            if self.server.mode == 'chunked':
                self.wfile.write(('%x\r\n' % len(payload)).encode() + payload + b'\r\n0\r\n\r\n')
            else:
                self.wfile.write(payload)
    do_GET = do_PUT = do_PATCH = handle_request

def wrapper(path, command):
    path.write_text('#!/bin/sh\n' + command + ' "$@"\n')
    path.chmod(0o755)

def run_suite(name, shell, path, env, fixture, supports_secret, supports_put=True, supports_get=True):
    server = Server(('127.0.0.1', 0), Handler)
    server.requests = []
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]
    env = dict(env, PATH=str(path), CRASHDIR=str(fixture), TMPDIR=str(fixture / 'tmp'),
               db_port=str(port), http_proxy='http://127.0.0.1:1',
               HTTP_PROXY='http://127.0.0.1:1', ALL_PROXY='http://127.0.0.1:1')
    save = str(REPO / 'scripts/libs/web_save.sh')
    restore = str(REPO / 'scripts/libs/web_restore.sh')
    test_count = 0
    def call(code, secret='', status=200, mode='normal'):
        nonlocal test_count
        server.expected, server.status, server.mode = secret, status, mode
        server.requests.clear()
        actual_env = dict(env, secret=secret)
        result = subprocess.run([str(shell), '-c', '. "$1"; . "$2"; ' + code,
                                 'panel-test', save, restore], env=actual_env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8)
        assert SECRET.encode() not in result.stdout + result.stderr, name + ': secret leaked'
        test_count += 1
        return result, list(server.requests)
    def require(condition, what):
        if not condition:
            raise AssertionError(name + ': ' + what)
    try:
        r, req = call('get_save "http://127.0.0.1:$db_port/proxies"')
        can_get = supports_get
        require((r.returncode == 0 and r.stdout.decode().strip() == SELECTORS and
                 len(req) == 1 and req[0][0:2] == ('GET', '/proxies')) if can_get
                else (r.returncode != 0 and not req), 'GET no secret')
        r, req = call('get_save "http://127.0.0.1:$db_port/proxies"', SECRET)
        require((r.returncode == 0 and len(req) == 1 and req[0][3]) if supports_secret
                else (r.returncode != 0 and not req), 'GET Bearer capability')
        r, req = call('get_save "http://127.0.0.1:$db_port/proxies"', status=401)
        require(r.returncode != 0 and (len(req) == 1 if can_get else not req), 'GET HTTP 401')
        r, req = call('get_save "http://127.0.0.1:$db_port/proxies"', status=500)
        require(r.returncode != 0 and (len(req) == 1 if can_get else not req), 'GET HTTP 500')
        code = 'put_save "http://127.0.0.1:$db_port/proxies/Group%20A" \'{"name":"选择"}\''
        r, req = call(code, status=204)
        if supports_put:
            require(r.returncode == 0 and len(req) == 1 and req[0][0] == 'PUT' and
                    req[0][1] == '/proxies/Group%20A' and
                    json.loads(req[0][2]) == {'name': '选择'} and
                    req[0][4].startswith('application/json'), 'PUT 204 and UTF-8 body')
        else:
            require(r.returncode != 0 and not req, 'unsupported PUT must fail')
        r, req = call(code, SECRET, 204)
        require((r.returncode == 0 and len(req) == 1 and req[0][3]) if supports_secret and supports_put
                else (r.returncode != 0 and not req), 'PUT Bearer capability')
        for status in (302, 401, 404, 500):
            r, req = call(code, status=status)
            require(r.returncode != 0 and (len(req) == 1 if supports_put else not req),
                    'PUT HTTP ' + str(status))
        r, req = call('put_save "http://127.0.0.1:$db_port/configs" \'{}\' PATCH', status=204)
        require((r.returncode == 0 and len(req) == 1 and req[0][0] == 'PATCH') if supports_put
                else (r.returncode != 0 and not req), 'custom PATCH')
        (fixture / 'configs/web_save').write_text('Old,unchanged\n')
        r, req = call('ckcmd(){ command -v "$1" >/dev/null; }; web_save')
        require((r.returncode == 0 and (fixture / 'configs/web_save').read_text() == 'Group A,选择\n')
                if can_get else (r.returncode != 0 and (fixture / 'configs/web_save').read_text() == 'Old,unchanged\n'),
                'web_save actual selection')
        if not can_get:
            (fixture / 'configs/web_save').write_text('Group A,选择\n')
        r, req = call('ckcmd(){ command -v "$1" >/dev/null; }; web_save', status=500)
        require(r.returncode != 0 and (fixture / 'configs/web_save').read_text() == 'Group A,选择\n',
                'failed save preserves file')
        r, req = call('web_restore', status=204)
        require((r.returncode == 0 and len(req) == 1 and req[0][0:2] ==
                 ('PUT', '/proxies/Group%20A') and json.loads(req[0][2]) == {'name': '选择'})
                if supports_put else (r.returncode != 0 and not req), 'web_restore')
        (fixture / 'configs/web_save').write_text('Group A,选择\nGroup B,other\n')
        r, req = call('web_restore', status=500)
        require(r.returncode != 0 and (len(req) == 2 if supports_put else not req),
                'web_restore reports failure and continues')
        (fixture / 'configs/web_save').write_text('')
        r, req = call('web_restore')
        require(r.returncode == 0 and not req, 'empty restore')
        r, req = call('put_save "http://localhost:$db_port/proxies/x" \'{}\'', SECRET, 204)
        require(r.returncode != 0 and not req, 'rejects non-127 address')
        if name == 'curl':
            curl_home = fixture / 'curl-home'
            curl_home.mkdir(exist_ok=True)
            (curl_home / '.curlrc').write_text('location\n')
            env['CURL_HOME'] = str(curl_home)
            env['HOME'] = str(curl_home)
            r, req = call('get_save "http://127.0.0.1:$db_port/proxies"', SECRET, 302)
            require(r.returncode != 0 and len(req) == 1, 'curl -q ignores .curlrc location on GET 302')
            r, req = call(code, SECRET, 302)
            require(r.returncode != 0 and len(req) == 1, 'curl -q ignores .curlrc location on PUT 302')
        if name.startswith('OpenWrt') and supports_put:
            get = 'get_save "http://127.0.0.1:$db_port/proxies"'
            r, req = call(get, SECRET, mode='chunked')
            require(r.returncode == 0 and r.stdout.decode().strip() == SELECTORS,
                    'authenticated chunked GET')
            r, req = call(get, SECRET, mode='truncated')
            require(r.returncode != 0 and not r.stdout, 'truncated GET fails closed')
            r, req = call(code, SECRET, 204, mode='truncated')
            require(r.returncode != 0, 'truncated PUT fails closed')
            r, req = call('put_save "http://localhost:$db_port/proxies/x" \'{}\'', SECRET, 204)
            require(r.returncode != 0 and not req, 'fallback rejects non-127 address')
            r, req = call(get, 'unsafe\r\nInjected: yes')
            require(r.returncode != 0 and not req, 'header injection rejected')
        print('PASS', name, test_count, 'cases')
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

def main():
    with tempfile.TemporaryDirectory(prefix='panel-uclient-test-') as tmp:
        tmp = Path(tmp)
        fixture = tmp / 'crash'
        (fixture / 'libs').mkdir(parents=True)
        (fixture / 'configs').mkdir()
        (fixture / 'tmp').mkdir()
        for source in ('compare.sh', 'panel_http.sh', 'panel_response.uc'):
            shutil.copy(REPO / 'scripts/libs' / source, fixture / 'libs' / source)
        host = os.environ.copy()
        sh = shutil.which('sh')
        busybox = shutil.which('busybox')
        for client in ('curl', 'gnu', 'busybox'):
            binary = shutil.which('curl' if client == 'curl' else 'wget' if client == 'gnu' else 'busybox')
            if not binary or not busybox:
                print('SKIP', client, '(binary missing)')
                continue
            if client == 'gnu' and 'GNU Wget' not in subprocess.run([binary, '--version'], capture_output=True, text=True).stdout:
                print('SKIP gnu (not GNU wget)')
                continue
            if client == 'busybox':
                bb_probe = subprocess.run([busybox, 'wget', '--help'], capture_output=True)
                if b'applet not found' in bb_probe.stdout + bb_probe.stderr:
                    print('SKIP busybox (wget applet missing)')
                    continue
            path = tmp / client
            path.mkdir()
            for cmd in ('grep', 'sed', 'awk', 'rm', 'mv', 'wc', 'cat', 'cmp', 'mktemp'):
                resolved = shutil.which(cmd)
                wrapper(path / cmd, resolved if resolved else busybox + ' ' + cmd)
            wrapper(path / 'busybox', busybox)
            if client == 'curl':
                wrapper(path / 'curl', binary)
            else:
                wrapper(path / 'wget', binary + (' wget' if client == 'busybox' else ''))
            # Use the real firmware ucode for the BusyBox wget fallback when available.
            root = AUDIT / 'ow235'
            ucode = root / 'usr/bin/ucode'
            if ucode.exists():
                lib = str(root / 'lib') + ':' + str(root / 'usr/lib')
                wrapper(path / 'ucode', 'LD_LIBRARY_PATH=' + lib + ' exec ' + str(ucode) + ' -L ' + str(root / 'usr/lib/ucode'))
            probe = subprocess.run([str(path / 'wget'), '--help'], capture_output=True) if client != 'curl' else None
            options = probe.stdout + probe.stderr if probe is not None else b''
            native_get = client == 'curl' or b'--header' in options
            native_put = client == 'curl' or all(flag in options for flag in (b'--method', b'--body-data', b'--header', b'--max-redirect'))
            run_suite(client, sh, path, host, fixture, native_get or ucode.exists(),
                      native_put or ucode.exists(), native_get or ucode.exists())
        for version in ('227', '235'):
            root = AUDIT / ('ow' + version)
            uclient = root / 'bin/uclient-fetch'
            owbox = root / 'bin/busybox'
            ucode = root / 'usr/bin/ucode'
            if not all(p.exists() for p in (uclient, owbox, ucode)):
                print('SKIP OpenWrt', version, '(firmware userland unavailable)')
                continue
            path = tmp / ('ow' + version)
            path.mkdir()
            lib = str(root / 'lib') + ':' + str(root / 'usr/lib')
            prefix = 'LD_LIBRARY_PATH=' + lib + ' exec '
            for cmd in ('grep', 'sed', 'awk', 'rm', 'mv', 'wc', 'cat', 'cmp', 'mktemp'):
                wrapper(path / cmd, prefix + str(owbox) + ' ' + cmd)
            wrapper(path / 'busybox', prefix + str(owbox))
            wrapper(path / 'wget', prefix + str(uclient))
            wrapper(path / 'ucode', prefix + str(ucode) + ' -L ' + str(root / 'usr/lib/ucode'))
            ash = path / 'ash'
            wrapper(ash, prefix + str(owbox) + ' ash')
            run_suite('OpenWrt ' + version + ' uclient-fetch', ash, path, host, fixture, True)
            (path / 'ucode').unlink()
            run_suite('OpenWrt ' + version + ' without ucode', ash, path, host, fixture, False, False, False)

if __name__ == '__main__':
    main()
