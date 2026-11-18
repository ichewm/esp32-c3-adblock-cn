#!/usr/bin/env python3
"""Live on-device audit: prove each firmware feature works, black-box, end-to-end.

Every feature shipped since cn-2.0 has an externally observable behaviour.
This script asserts each one against the RUNNING device — no version-string
trust: the board's fw string is additionally cross-checked against the
repo's FW_VER (catches "code ahead of the board" drift).

Usage:  python3 tools/audit_device.py [device-ip | c3adblock.local]
Exit:   0 all PASS / 1 any FAIL (each check prints its evidence)

Checks:
  A  version parity     board fw == repo FW_VER
  B  sinkhole           ad domain          -> 0.0.0.0
  C  forwarding         normal domain      -> real answer (not 0.0.0.0 / self)
  D  DoH in use         dohok counter advances on a forwarded query
  E  graveyard DNS      telemetry domain   -> the DEVICE's own IP
  E2 graveyard HTTP     foreign Host on :80 -> 204 No Content
  E3 own-host safety    our own host 404s stay 404 (no hijack)
  F  allowlist round    addallow -> forwarded; delallow -> graveyard again
  G  auth enforcement   mutating endpoint without credentials -> 401/403
  H  fog scheduler      high rate briefly -> counter advances; restores OFF
  I  heap sanity        free heap > 50KB
"""
import base64
import json
import re
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).parent.parent
results = []


def check(name, ok, evidence):
    results.append(ok)
    print(f"  {'PASS' if ok else 'FAIL'}  {name:20s} {evidence}")


def dig(ip, domain):
    r = subprocess.run(['dig', '+short', '+tries=1', '+time=4', f'@{ip}', domain, 'A'],
                       capture_output=True, text=True, timeout=10)
    return (r.stdout.split('\n')[0] or '').strip()


def stats(ip):
    return json.load(urllib.request.urlopen(f'http://{ip}/stats.json', timeout=8))


def api(ip, path, auth=True):
    sec = (ROOT / 'src' / 'secrets.h').read_text()
    user = re.search(r'WEB_USER\s*=\s*"([^"]*)"', sec).group(1)
    pw = re.search(r'WEB_PASS\s*=\s*"([^"]*)"', sec).group(1)
    hdr = {'X-Requested-With': 'c3-adblock'}
    if auth:
        hdr['Authorization'] = 'Basic ' + base64.b64encode(f'{user}:{pw}'.encode()).decode()
    req = urllib.request.Request(f'http://{ip}/{path}', headers=hdr)
    return urllib.request.urlopen(req, timeout=10).read().decode()


def http_code(ip, path, host=None):
    req = urllib.request.Request(f'http://{ip}{path}', headers={'Host': host} if host else {})
    try:
        r = urllib.request.urlopen(req, timeout=6)
        return r.status
    except urllib.error.HTTPError as e:
        return e.code


def main():
    ip = sys.argv[1] if len(sys.argv) > 1 else 'c3adblock.local'
    ip = socket.gethostbyname(ip) if not ip[0].isdigit() else ip
    dev_ip = ip
    print(f'auditing device {ip} at {time.strftime("%F %T")}\n')

    s = stats(ip)
    repo_fw = re.search(r'FW_VER = "([^"]+)"', (ROOT / 'src' / 'main.cpp').read_text()).group(1)
    check('A version parity', s.get('fw') == repo_fw, f'board={s.get("fw")} repo={repo_fw}')

    a = dig(ip, 'doubleclick.net')
    check('B sinkhole', a == '0.0.0.0', f'doubleclick.net -> {a}')

    a = dig(ip, 'baidu.com')
    check('C forwarding', a not in ('0.0.0.0', '', dev_ip), f'baidu.com -> {a}')

    before = stats(ip)['dohok']
    dig(ip, 'qq.com')
    time.sleep(1)
    after = stats(ip)['dohok']
    check('D DoH in use', s['doh'].startswith('ok') and after > before,
          f'doh={s["doh"].split("(")[0]} dohok {before}->{after}')

    a = dig(ip, 'alog.umeng.com')
    check('E graveyard DNS', a == dev_ip, f'alog.umeng.com -> {a} (device ip)')

    c = http_code(ip, '/sdk/upload?data=x', host='alog.umeng.com')
    check('E2 graveyard HTTP', c == 204, f'foreign-Host GET -> HTTP {c}')

    c = http_code(ip, '/definitely-not-a-route')
    check('E3 own-host safety', c == 404, f'own host 404 -> HTTP {c}')

    target = 'alog.umeng.com'
    already = target in stats(ip).get('allow', [])
    if not already:
        api(ip, f'addallow?d={target}')
    try:
        a = dig(ip, target)
        check('F allowlist fwd', a not in (dev_ip, '0.0.0.0', ''), f'allowlisted -> {a} (forwarded)')
    finally:
        if not already:
            api(ip, f'delallow?d={target}')
    a = dig(ip, target)
    check('F2 allowlist revert', a == dev_ip, f'delallow -> {a} (graveyard again)')

    try:
        urllib.request.urlopen(f'http://{ip}/addallow?d=evil.example', timeout=6)
        code = 200
    except urllib.error.HTTPError as e:
        code = e.code
    check('G auth enforced', code in (401, 403), f'no-cred POST /addallow -> HTTP {code}')

    api(ip, 'setnoise?on=1&rate=20000')
    n0 = stats(ip)['noise']
    time.sleep(16)
    n1 = stats(ip)['noise']
    api(ip, 'setnoise?on=0&rate=1000')
    check('H fog scheduler', n1 > n0, f'20000/day: noise {n0}->{n1} in 16s (restored OFF)')

    check('I heap sanity', s['heap'] > 50 * 1024, f'free heap {s["heap"]//1024}KB')

    ok = all(results)
    print(f'\n{"ALL PASS" if ok else "AUDIT FAILED"} — {sum(results)}/{len(results)} checks')
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
