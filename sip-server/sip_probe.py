"""
SIP probe: OPTIONS -> REGISTER (401 -> auth -> 200 OK)
Usage: python sip_probe.py <host> <username> <password>
"""
import socket, sys, uuid, hashlib, re

host     = sys.argv[1]
user     = sys.argv[2] if len(sys.argv) > 2 else "alice"
password = sys.argv[3] if len(sys.argv) > 3 else "alicepass"
port     = 5060

def md5(s): return hashlib.md5(s.encode()).hexdigest()

def send_recv(sock, msg):
    print("\n--- SENT ---")
    print(msg)
    sock.sendall(msg.encode())
    data = b""
    sock.settimeout(5)
    try:
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            data += chunk
            if b"\r\n\r\n" in data:
                break
    except socket.timeout:
        pass
    resp = data.decode(errors="replace")
    print("--- RECEIVED ---")
    print(resp)
    return resp

def make_via(branch):
    return f"SIP/2.0/TCP {host}:5060;branch=z9hG4bK{branch}"

def make_headers(method, uri, cseq_n, tag, call_id, branch, extra=""):
    return (
        f"{method} {uri} SIP/2.0\r\n"
        f"Via: {make_via(branch)}\r\n"
        f"From: <sip:{user}@{host}>;tag={tag}\r\n"
        f"To: <sip:{user}@{host}>\r\n"
        f"Call-ID: {call_id}\r\n"
        f"CSeq: {cseq_n} {method}\r\n"
        f"Contact: <sip:{user}@127.0.0.1:5060;transport=tcp>\r\n"
        f"Max-Forwards: 70\r\n"
        f"User-Agent: sip-probe/1.0\r\n"
        f"{extra}"
        f"Content-Length: 0\r\n\r\n"
    )

def digest_auth(realm, nonce, method, uri):
    ha1 = md5(f"{user}:{realm}:{password}")
    ha2 = md5(f"{method}:{uri}")
    resp = md5(f"{ha1}:{nonce}:{ha2}")
    return (
        f'Authorization: Digest username="{user}", realm="{realm}", '
        f'nonce="{nonce}", uri="{uri}", response="{resp}", algorithm=MD5\r\n'
    )

print(f"\n{'='*60}")
print(f"SIP probe => {host}:{port}  user={user}")
print(f"{'='*60}")

with socket.create_connection((host, port), timeout=5) as s:

    # ── Step 1: OPTIONS (no auth required) ────────────────────────
    print("\n[1] OPTIONS — basic connectivity")
    tag    = uuid.uuid4().hex[:8]
    cid    = uuid.uuid4().hex
    branch = uuid.uuid4().hex[:8]
    uri    = f"sip:{host}"
    opts   = (
        f"OPTIONS {uri} SIP/2.0\r\n"
        f"Via: {make_via(branch)}\r\n"
        f"From: <sip:probe@{host}>;tag={tag}\r\n"
        f"To: <sip:{host}>\r\n"
        f"Call-ID: {cid}\r\n"
        f"CSeq: 1 OPTIONS\r\n"
        f"Max-Forwards: 70\r\n"
        f"Content-Length: 0\r\n\r\n"
    )
    r1 = send_recv(s, opts)
    status1 = r1.splitlines()[0] if r1 else "(no response)"
    print(f"\n=> OPTIONS result: {status1}")

    # ── Step 2: REGISTER (expect 401) ─────────────────────────────
    print("\n[2] REGISTER — expect 401 Unauthorized (auth challenge)")
    tag    = uuid.uuid4().hex[:8]
    cid    = uuid.uuid4().hex
    branch = uuid.uuid4().hex[:8]
    uri    = f"sip:{host}"
    r2 = send_recv(s, make_headers("REGISTER", uri, 1, tag, cid, branch,
                                   "Expires: 3600\r\n"))
    status2 = r2.splitlines()[0] if r2 else "(no response)"
    print(f"\n=> REGISTER (no auth) result: {status2}")

    # ── Step 3: REGISTER with digest auth (expect 200 OK) ─────────
    print("\n[3] REGISTER — with digest credentials, expect 200 OK")
    realm_m = re.search(r'realm="([^"]+)"', r2)
    nonce_m = re.search(r'nonce="([^"]+)"', r2)

    if not realm_m or not nonce_m:
        print("ERROR: could not parse realm/nonce from 401 — cannot continue")
        sys.exit(1)

    realm  = realm_m.group(1)
    nonce  = nonce_m.group(1)
    branch = uuid.uuid4().hex[:8]
    auth   = digest_auth(realm, nonce, "REGISTER", uri)
    r3 = send_recv(s, make_headers("REGISTER", uri, 2, tag, cid, branch,
                                   f"Expires: 3600\r\n{auth}"))
    status3 = r3.splitlines()[0] if r3 else "(no response)"
    print(f"\n=> REGISTER (with auth) result: {status3}")

print(f"\n{'='*60}")
print("SUMMARY")
print(f"  OPTIONS : {status1}")
print(f"  REGISTER (no auth) : {status2}")
print(f"  REGISTER (with auth): {status3}")
print(f"{'='*60}\n")
