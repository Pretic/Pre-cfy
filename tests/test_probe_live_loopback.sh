#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source <(sed -n '/^[A-Za-z_][A-Za-z_0-9]*() {/,/^}/p' "$repo/cfy.sh")
d=$(mktemp -d); server_pid=''
trap '[ -z "$server_pid" ] || { kill "$server_pid" 2>/dev/null || :; wait "$server_pid" 2>/dev/null || :; }; rm -rf "$d"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$d/key" -out "$d/cert" -days 1 \
 -subj /CN=localhost -addext subjectAltName=DNS:localhost >/dev/null 2>&1
cat > "$d/server.py" <<'PY'
import base64, hashlib, socket, ssl, sys, threading, time
root=sys.argv[1]
ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain(root+'/cert', root+'/key')
listener=socket.socket(); listener.bind(('127.0.0.1',0)); listener.listen(32)
open(root+'/port','w').write(str(listener.getsockname()[1]))
def serve(sock):
 try:
  with ctx.wrap_socket(sock,server_side=True) as s:
   s.settimeout(3); req=b''
   while b'\r\n\r\n' not in req: req+=s.recv(2048)
   path=req.split()[1].decode(); headers={}
   for line in req.split(b'\r\n')[1:]:
    if b':' in line:
     k,v=line.split(b':',1); headers[k.lower()]=v.strip()
   key=headers.get(b'sec-websocket-key',b'')
   accept=base64.b64encode(hashlib.sha1(key+b'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest())
   if path=='/wrong': accept=b'incorrect'
   if path=='/forbidden':
    s.sendall(b'HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n'); return
   if path=='/stall': time.sleep(10); return
   response=b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+accept+b'\r\n'
   if path!='/incomplete': response+=b'\r\n'
   s.sendall(response)
   if path=='/close': return
   time.sleep(3)
 except (OSError,ssl.SSLError): pass
while True:
 sock,_=listener.accept(); threading.Thread(target=serve,args=(sock,),daemon=True).start()
PY
python3 "$d/server.py" "$d" > "$d/server.log" 2>&1 & server_pid=$!
for _ in {1..100}; do [ ! -s "$d/port" ] || break; sleep 0.02; done
port=$(cat "$d/port")
export CURL_CA_BUNDLE="$d/cert"
CFY_HEALTH_PROBE_ATTEMPTS=1 CFY_HEALTH_MIN_SUCCESS=1 CFY_HEALTH_MAX_TIME=2
CFY_PROBE_RESULT_FILE="$d/reason"
template="vless://00000000-0000-4000-8000-000000000001@localhost:${port}?security=tls&type=ws&host=localhost&sni=localhost&path="
start=$(date +%s%N)
probe_vless_edge_candidate "${template}%2Fhold" 127.0.0.1
end=$(date +%s%N)
new_ms=$(( (end-start)/1000000 ))
[ "$new_ms" -lt 1500 ] || { echo "handshake waited for body/timeout: ${new_ms}ms"; exit 1; }
[[ $(cat "$d/reason") == ok ]]
probe_vless_edge_candidate "${template}%2Fclose" 127.0.0.1
for path in wrong incomplete forbidden; do
 if probe_vless_edge_candidate "${template}%2F${path}" 127.0.0.1; then echo "accepted $path"; exit 1; fi
done
[[ $(cat "$d/reason") == http-403 ]]
# The exact old transport pattern waits for two max-time limits on a healthy socket.
start=$(date +%s%N)
for _ in 1 2; do
 rc=0
 curl -q --noproxy '*' --http1.1 --silent --output /dev/null --max-time 2 \
  --header 'Connection: Upgrade' --header 'Upgrade: websocket' \
  --header 'Sec-WebSocket-Version: 13' --header 'Sec-WebSocket-Key: MDEyMzQ1Njc4OWFiY2RlZg==' \
  "https://localhost:${port}/hold" || rc=$?
 [[ "$rc" == 28 ]]
done
end=$(date +%s%N); old_ms=$(( (end-start)/1000000 ))
printf 'Local TLS/WebSocket hold-open comparison: old=%sms new=%sms\n' "$old_ms" "$new_ms"
# Cancellation must stop only this run's curl workers and never publish results.
sed -n '/^[A-Za-z_][A-Za-z_0-9]*() {/,/^}/p' "$repo/cfy.sh" > "$d/definitions"
cat > "$d/cancel.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
source "$1/definitions"
CFY_HEALTH_PROBE=1 CFY_HEALTH_CONCURRENCY=3 CFY_HEALTH_MAX_TIME=5
ip_list=(127.0.0.1 127.0.0.1 127.0.0.1); isp_list=(test test test)
screen_edge_candidates vless "$2"
echo unexpected-publication > "$1/published"
SH
bash "$d/cancel.sh" "$d" "${template}%2Fstall" > "$d/cancel.log" 2>&1 & child_pid=$!
python3 - "$child_pid" "$d/pids" <<'PY'
import pathlib,sys,time
root=int(sys.argv[1]); found=[]
for _ in range(50):
 rows={}
 for p in pathlib.Path('/proc').glob('[0-9]*/status'):
  try:
   values=dict(line.split(':',1) for line in p.read_text().splitlines() if ':' in line)
   rows[int(p.parent.name)]=(int(values['PPid']),values['Name'].strip())
  except (OSError,KeyError,ValueError): pass
 nodes={root}
 for _ in range(10): nodes.update(pid for pid,(parent,_) in rows.items() if parent in nodes)
 found=[pid for pid in nodes if rows.get(pid,(0,''))[1]=='curl']
 if len(found)==3: break
 time.sleep(.05)
assert len(found)==3,found
pathlib.Path(sys.argv[2]).write_text('\n'.join(map(str,found)))
PY
kill -TERM "$child_pid"
rc=0; wait "$child_pid" || rc=$?
[[ "$rc" == 143 && ! -e "$d/published" ]]
python3 - "$d/pids" <<'PY'
import pathlib,sys,time
pids=pathlib.Path(sys.argv[1]).read_text().splitlines()
for _ in range(30):
 live=[p for p in pids if pathlib.Path('/proc/'+p).exists()]
 if not live: break
 time.sleep(.1)
assert not live,live
PY
echo 'Cancellation reaped all three owned curl workers without publication.'

# Real certificate checking remains enabled, even on a working WebSocket origin.
unset CURL_CA_BUNDLE
if probe_vless_edge_candidate "${template}%2Fhold" 127.0.0.1; then echo 'untrusted certificate accepted'; exit 1; fi
[[ $(cat "$d/reason") == tls ]]
echo 'Real curl: fast success, early close, malformed headers, HTTP errors and TLS checks passed.'
