#!/bin/sh
# Copyright (C) Juewuy

_sb_esc() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

[ "$vms_service" = ON ] && {
    transport=""
    [ -n "$vms_ws_path" ] && transport=', "transport": { "type": "ws", "path": "'"$(_sb_esc "$vms_ws_path")"'" }'
    cat >"$TMPDIR"/jsons/vmess-in.json <<EOF
{
  "inbounds": [
    {
      "type": "vmess",
      "tag": "vmess-in",
      "listen": "::",
      "listen_port": $vms_port,
      "users": [
        {
          "uuid": "$(_sb_esc "$vms_uuid")"
        }
      ]$transport
    }
  ]
}
EOF
}

[ "$sss_service" = ON ] && {
    cat >"$TMPDIR"/jsons/ss-in.json <<EOF
{
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": $sss_port,
      "method": "$(_sb_esc "$sss_cipher")",
      "password": "$(_sb_esc "$sss_pwd")"
    }
  ]
}
EOF
}
