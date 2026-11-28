// Parse the loopback HTTP/1.x reply without leaking headers or body on error.
// BusyBox nc is bounded by ucode system() in panel_http.sh.
import { stdin } from 'fs';

let raw = stdin.read('all');
if (raw == null) exit(1);
let end = index(raw, '\r\n\r\n');
if (end < 0) exit(1);
let lines = split(substr(raw, 0, end), '\r\n');
if (!match(lines[0], /^HTTP\/1\.[01] 2[0-9][0-9]( |$)/)) exit(1);
let content_length = null;
let encoding = null;
for (let i = 1; i < length(lines); i++) {
    let colon = index(lines[i], ':');
    if (colon < 1) exit(1);
    let key = lc(substr(lines[i], 0, colon));
    let value = trim(substr(lines[i], colon + 1));
    if (key == 'content-length') {
        if (content_length != null || !match(value, /^[0-9]+$/)) exit(1);
        content_length = int(value);
    }
    if (key == 'transfer-encoding') {
        if (encoding != null) exit(1);
        encoding = lc(value);
    }
}
let body = substr(raw, end + 4);
if (encoding != null) {
    if (encoding != 'chunked' || content_length != null) exit(1);
    let out = '';
    while (true) {
        let line_end = index(body, '\r\n');
        if (line_end < 0) exit(1);
        let size_line = substr(body, 0, line_end);
        let ext = index(size_line, ';');
        let size = ext < 0 ? size_line : substr(size_line, 0, ext);
        if (!match(size, /^[0-9a-fA-F]+$/) || length(size) > 8) exit(1);
        let n = 0;
        size = lc(size);
        for (let j = 0; j < length(size); j++)
            n = n * 16 + index('0123456789abcdef', substr(size, j, 1));
        body = substr(body, line_end + 2);
        if (n == 0) {
            // Allow trailers only if they are terminated by a blank CRLF line.
            if (substr(body, 0, 2) != '\r\n' && index(body, '\r\n\r\n') < 0) exit(1);
            body = out;
            break;
        }
        if (length(body) < n + 2 || substr(body, n, 2) != '\r\n') exit(1);
        out += substr(body, 0, n);
        body = substr(body, n + 2);
    }
}
else if (content_length != null && length(body) != content_length) exit(1);
if (ARGV[0] == 'GET') print(body);
