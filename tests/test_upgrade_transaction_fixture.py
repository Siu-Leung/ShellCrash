#!/usr/bin/env python3
"""Fast, hermetic upgrade transaction regression. No host stop/init is executed."""
import os
import pathlib
import shutil
import subprocess
import tarfile
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIB = ROOT / 'scripts/libs/set_config.sh'
START = ROOT / 'scripts/start.sh'


def put(path, data, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data)
    path.chmod(mode)


def run(env, script):
    return subprocess.run(['sh', '-c', script], env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=8)


def require(ok, name, detail=''):
    if not ok:
        raise AssertionError('%s: %s' % (name, detail))
    print('PASS', name)


def setup(base, name, running=True):
    d = base / name
    i, t, b, p = [d / x for x in ('inst', 'tmp', 'bin', 'pkg')]
    for x in (i / 'configs', t, b, p):
        x.mkdir(parents=True, exist_ok=True)
    put(d / 'state', '1' if running else '0')
    put(i / 'version', 'old\n')
    put(i / 'configs/ShellCrash.cfg', 'firewall_area=4\nold=yes\n')
    put(i / 'start.sh', '''#!/bin/sh
printf 'old %s\\n' "$1" >> "$LAB/events"
case "$1" in
 stop) [ "$KILL_STOP" = 1 ] && { printf 0 > "$LAB/state"; kill -KILL "$PPID"; }; [ "$STOP_FAIL" = 1 ] && exit 1; printf 0 > "$LAB/state";;
 start) [ "$OLD_FAIL" = 1 ] && exit 1; printf 1 > "$LAB/state";;
esac
exit 0
''', 0o755)
    put(i / 'menu.sh', '#!/bin/sh\n# old\n')
    put(i / 'init.sh', '#!/bin/sh\n# old\n')
    put(i / 'libs/get_config.sh', '#!/bin/sh\n# old\n')
    put(p / 'start.sh', '''#!/bin/sh
printf 'new %s\\n' "$1" >> "$LAB/events"
case "$1" in
 stop) [ "$NEW_STOP_FAIL" = 1 ] && exit 1; printf 0 > "$LAB/state";;
 start) [ "$NEW_FAIL" = 1 ] && exit 1; [ "$NO_PROCESS" = 1 ] || printf 1 > "$LAB/state";;
esac
exit 0
''', 0o755)
    put(p / 'init.sh', '''#!/bin/sh
printf 'new init\\n' >> "$LAB/events"
case "$MODE" in
 fail|created) echo changed >> "$CRASHDIR/configs/ShellCrash.cfg";;
 term) kill -TERM "$PPID"; exit 1;;
esac
[ "$MODE" = created ] && echo generated > "$CRASHDIR/configs/command.env"
case "$MODE" in fail|created) exit 1;; esac
exit 0
''', 0o755)
    put(p / 'menu.sh', '#!/bin/sh\n# new\n')
    put(p / 'libs/get_config.sh', '#!/bin/sh\n# new\n')
    put(p / 'version', 'new\n')
    a = d / 'upgrade.tar.gz'
    with tarfile.open(a, 'w:gz') as f:
        for item in sorted(p.iterdir()):
            f.add(item, arcname=item.name)
    put(b / 'pidof', '#!/bin/sh\n[ "$(cat "$LAB/state")" = 1 ] && echo 999999\nexit 0\n', 0o755)
    put(b / 'rc-status', '#!/bin/sh\nexit 1\n', 0o755)
    env = dict(os.environ, CRASHDIR=str(i), TMPDIR=str(t), LAB=str(d), LIB=str(LIB), PKG=str(a),
               PATH=str(b) + ':/usr/bin:/bin', _SC_UPG_ACTIVE='', MODE='', STOP_FAIL='', KILL_STOP='',
               OLD_FAIL='', NEW_FAIL='', NEW_STOP_FAIL='', NO_PROCESS='')
    return d, i, t, b, a, env


def upgrade(env):
    return run(env, '. "$LIB"; apply_script_upgrade "$PKG"')


def transaction_cases(base):
    for name, flags, expected, state, failed in [
        ('success', {}, 0, '1', False),
        ('stopped', {'RUNNING': False}, 0, '0', False),
        ('stop_fail', {'STOP_FAIL': '1'}, 1, '1', False),
        ('init_fail', {'MODE': 'fail'}, 1, '1', False),
        ('created', {'MODE': 'created'}, 1, '1', False),
        ('start_fail', {'NEW_FAIL': '1'}, 1, '1', False),
        ('false_success', {'NO_PROCESS': '1'}, 1, '1', False),
        ('restart_fail', {'NEW_FAIL': '1', 'OLD_FAIL': '1'}, 1, '0', True),
        ('new_stop_fail', {'NEW_FAIL': '1', 'NEW_STOP_FAIL': '1'}, 1, '0', True),
        ('term', {'MODE': 'term'}, 143, '1', False),
    ]:
        running = flags.pop('RUNNING', True)
        d, i, t, b, a, e = setup(base, name, running)
        e.update(flags)
        r = upgrade(e)
        version = (i / 'version').read_text().strip()
        expected_version = 'new' if expected == 0 or name == 'new_stop_fail' else 'old'
        require(r.returncode == expected and version == expected_version and
                (d / 'state').read_text() == state and
                (i / '.upg_txn/rollback_failed').exists() == failed and
                not (i / 'configs/command.env').exists(), name, r.stdout)
        if expected != 0 and name != 'new_stop_fail':
            require((i / 'configs/ShellCrash.cfg').read_text() == 'firewall_area=4\nold=yes\n', name + ' config')


def archive_safety_cases(base):
    d, i, t, b, a, e = setup(base, 'symlink-parent', False)
    outside = d / 'outside'
    outside.mkdir()
    shutil.rmtree(i / 'libs')
    (i / 'libs').symlink_to(outside, target_is_directory=True)
    r = upgrade(e)
    require(r.returncode != 0 and not (outside / 'get_config.sh').exists(), 'parent symlink rejected before stop', r.stdout)
    d, i, t, b, a, e = setup(base, 'txn-in-package', False)
    with tarfile.open(a, 'w:gz') as f:
        for item in sorted((d / 'pkg').iterdir()):
            f.add(item, arcname=item.name)
        marker = d / 'marker'
        marker.write_text('fake')
        f.add(marker, arcname='.upg_txn/pending')
    r = upgrade(e)
    require(r.returncode != 0 and not (d / 'events').exists(), 'archive cannot overwrite transaction', r.stdout)


def recovery_cases(base):
    d, i, t, b, a, e = setup(base, 'kill')
    e['KILL_STOP'] = '1'
    r = upgrade(e)
    require(r.returncode < 0 and (i / '.upg_txn/pending').is_file() and (d / 'state').read_text() == '0', 'SIGKILL pending before stop')
    e['KILL_STOP'] = ''
    r = run(e, '. "$LIB"; recover_interrupted_upgrade')
    require(r.returncode == 0 and (d / 'state').read_text() == '1' and not (i / '.upg_txn').exists(), 'SIGKILL recovery', r.stdout)
    d, i, t, b, a, e = setup(base, 'mode', False)
    x = i / '.upg_txn'
    put(x / 'bak/example', 'old\n', 0o755)
    put(i / 'example', 'new\n', 0o644)
    put(x / 'was_running', '0\n')
    put(x / 'pending', '999999999\n')
    put(x / 'newlist', 'example\n')
    r = run(e, '. "$LIB"; recover_interrupted_upgrade')
    require(r.returncode == 0 and (i / 'example').read_text() == 'old\n' and (i / 'example').stat().st_mode & 0o777 == 0o755, 'legacy recovery mode', r.stdout)
    d, i, t, b, a, e = setup(base, 'external-reject', False)
    x = i / '.upg_txn'
    put(x / 'was_running', '0\n')
    put(x / 'pending', '999999999\n')
    put(x / 'external/path', str(d / 'outside'))
    put(x / 'external/absent', '')
    put(d / 'outside', 'preserve')
    r = run(e, '. "$LIB"; recover_interrupted_upgrade')
    require(r.returncode != 0 and (d / 'outside').read_text() == 'preserve' and (x / 'rollback_failed').exists(), 'external allowlist rejects arbitrary paths', r.stdout)
    d, i, t, b, a, e = setup(base, 'blocked', False)
    put(i / '.upg_txn/bak/sentinel', 'keep')
    r = upgrade(e)
    require(r.returncode != 0 and (i / '.upg_txn/bak/sentinel').read_text() == 'keep', 'pre-pending directory preserved')
    put(i / '.upg_txn/rollback_failed', '1')
    r = upgrade(e)
    require(r.returncode != 0 and (i / '.upg_txn/bak/sentinel').read_text() == 'keep', 'rollback_failed preserved')
    (i / '.upg_txn/rollback_failed').unlink()
    r = run(e, '. "$LIB"; echo $$ > "$CRASHDIR/.upg_txn/pending"; apply_script_upgrade "$PKG"')
    require(r.returncode != 0 and (i / '.upg_txn/bak/sentinel').exists(), 'live owner blocks')


def external_cases(base):
    # Exact same shell implementation, with hard-coded host paths redirected into the sandbox.
    for mode in ('existed', 'absent', 'unsafe'):
        d, i, t, b, a, e = setup(base, 'external-' + mode, False)
        systemd = d / 'systemd'
        systemd.mkdir()
        unit = systemd / 'shellcrash.service'
        libcopy = d / 'set_config.sh'
        libcopy.write_text(LIB.read_text().replace('/etc/systemd/system/shellcrash.service', str(unit)))
        e['LIB'] = str(libcopy)
        put(b / 'systemctl', '#!/bin/sh\necho "$*" >> "$LAB/reload"\nexit 0\n', 0o755)
        x = i / '.upg_txn'
        put(x / 'was_running', '0\n')
        put(x / 'pending', '999999999\n')
        put(x / 'external/path', str(unit))
        put(x / 'external/systemd', '')
        put(x / ('external/absent' if mode == 'absent' else 'external/existed'), '')
        if mode == 'existed':
            put(x / 'external/backup', 'old unit', 0o755)
            put(unit, 'new unit', 0o644)
        elif mode == 'absent':
            put(unit, 'new unit')
        else:
            put(x / 'external/backup', 'old unit')
            put(d / 'outside', 'outside')
            unit.symlink_to(d / 'outside')
        r = run(e, '. "$LIB"; recover_interrupted_upgrade')
        if mode == 'unsafe':
            require(r.returncode != 0 and (d / 'outside').read_text() == 'outside' and (x / 'rollback_failed').exists(), 'external symlink rejected', r.stdout)
        else:
            ok = (not unit.exists()) if mode == 'absent' else unit.read_text() == 'old unit' and unit.stat().st_mode & 0o777 == 0o755
            require(r.returncode == 0 and ok and (d / 'reload').read_text().strip() == 'daemon-reload', 'external ' + mode + ' restored', r.stdout)


def concurrent_case(base):
    d, i, t, b, a, e = setup(base, 'concurrent', False)
    put(b / 'tar', '''#!/bin/sh
if [ "$BLOCK_TAR" = 1 ]; then
 : > "$LAB/ready"
 while [ ! -e "$LAB/release" ]; do /bin/sleep 0.02; done
fi
exec /bin/tar "$@"
''', 0o755)
    first = subprocess.Popen(['sh', '-c', '. "$LIB"; apply_script_upgrade "$PKG"'],
                             env=dict(e, BLOCK_TAR='1'), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(100):
            if (d / 'ready').exists():
                break
            time.sleep(.02)
        require((d / 'ready').exists(), 'concurrency barrier')
        put(i / '.upg_txn/bak/sentinel', 'keep')
        r = upgrade(e)
        require(r.returncode != 0 and (i / '.upg_txn/bak/sentinel').read_text() == 'keep', 'concurrent pre-pending protection', r.stdout)
        (d / 'release').touch()
        require(first.wait(timeout=8) == 0, 'first transaction survives competitor')
    finally:
        if first.poll() is None:
            first.kill()
            first.wait()


def readiness_cases(base):
    d, i, t, b, a, e = setup(base, 'readiness', False)
    r = run(e, '. "$LIB"; _upg_check_service_ready')
    require(r.returncode != 0, 'missing core cannot succeed')
    put(i / 'configs/ShellCrash.cfg', 'firewall_area=5\ntable=100\nbypass_host=192.0.2.1\n')
    put(b / 'ip', '#!/bin/sh\n[ "$(cat "$LAB/state")" = 1 ] && echo "default via 192.0.2.1 dev eth0"\nexit 0\n', 0o755)
    r = run(e, '. "$LIB"; _upg_check_service_ready')
    require(r.returncode != 0, 'gateway missing route rejected')
    (d / 'state').write_text('1')
    r = run(e, '. "$LIB"; _upg_check_service_ready')
    require(r.returncode == 0, 'gateway route no-process behavior')
    r = upgrade(e)
    require(r.returncode == 0 and (d / 'state').read_text() == '1' and 'new start' in (d / 'events').read_text(), 'active gateway preserved through upgrade', r.stdout)
    put(i / 'configs/ShellCrash.cfg', 'firewall_area=4\n')
    (d / 'state').write_text('1')
    (t / 'CrashCore').write_bytes(b'\x7fELFtest')
    put(b / 'od', '#!/bin/sh\nexit 127\n', 0o755)
    put(b / 'curl', '#!/bin/sh\necho call >> "$LAB/calls"\nexit 1\n', 0o755)
    put(b / 'sleep', '#!/bin/sh\nexit 0\n', 0o755)
    r = run(e, '. "$LIB"; _upg_check_service_ready')
    require(r.returncode != 0 and len((d / 'calls').read_text().splitlines()) == 8, 'ELF controller failure without od')


def stop_cases(base):
    for platform in ('systemd', 'openrc', 'procd'):
        d, i, t, b, a, e = setup(base, 'stop-' + platform, False)
        # Copy and redirect only absolute procd path in the fixture, never the host.
        text = START.read_text().replace('/etc/rc.common', '"$LAB/rc.common"').replace('/etc/init.d/shellcrash', '"$LAB/procd"')
        put(i / 'start.sh', text, 0o755)
        for name, body in {
            'set_cron.sh': 'croncheck() { return 0; }\ncronupdate() { return 0; }\n',
            'get_config.sh': 'crondir="$LAB/missing"\n', 'set_config.sh': '', 'check_cmd.sh': '',
            'check_autostart.sh': '', 'compare.sh': '', 'logger.sh': '',
            'web_save.sh': 'web_save() { :; }\n',
        }.items():
            put(i / 'libs' / name, body)
        put(i / 'menus/bot_tg_service.sh', 'bot_tg_stop() { :; }\n')
        for name in ('logger', 'killall'):
            put(b / name, '#!/bin/sh\nexit 0\n', 0o755)
        put(b / 'crontab', '#!/bin/sh\nexit 1\n', 0o755)
        for name in ('systemctl', 'rc-service'):
            put(b / name, '#!/bin/sh\necho "$*" >> "$LAB/called"\nexit 1\n', 0o755)
        put(d / 'procd', '#!/bin/sh\necho "$*" >> "$LAB/called"\nexit 1\n', 0o755)
        put(b / 'rc-status', '#!/bin/sh\nexit %s\n' % ('0' if platform == 'openrc' else '1'), 0o755)
        put(b / 'grep', '''#!/bin/sh
case "$*" in
 *systemd*/proc/1/comm*) [ "$PLATFORM" = systemd ]; exit $?;;
 *procd*/proc/1/comm*) [ "$PLATFORM" = procd ]; exit $?;;
 *s6*/proc/1/comm*) exit 1;;
esac
exec /bin/grep "$@"
''', 0o755)
        if platform == 'procd':
            put(d / 'rc.common', '')
        put(t / 'CrashCore', 'preserve')
        r = run(dict(e, PLATFORM=platform), '"$CRASHDIR/start.sh" stop')
        require(r.returncode != 0 and (d / 'called').exists() and (t / 'CrashCore').exists(), platform + ' stop failure propagated without deleting core', r.stdout)


with tempfile.TemporaryDirectory(prefix='sc-upgrade-test-') as temp:
    base = pathlib.Path(temp)
    transaction_cases(base)
    archive_safety_cases(base)
    recovery_cases(base)
    external_cases(base)
    concurrent_case(base)
    readiness_cases(base)
    stop_cases(base)
print('test_upgrade_transaction: all passed')
