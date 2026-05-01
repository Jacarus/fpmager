#!/usr/bin/env python3
"""
UDP echo server for fly.io NAT diagnostics.

Root-cause findings:
  - fly.io does NOT auto-assign the dedicated public IPv4 to eth0; the machine
    only has its private IP (172.x) and fly-global-services IP.
  - iptables (nft and legacy) is bypassed by fly.io's Firecracker eth0; all
    netfilter counters stay at zero regardless of traffic.

Solution:
  - Manually add PUBLIC_IP/32 to eth0 (makes it a local address for both
    receive and send).
  - Add a policy routing rule so the kernel can route packets with
    src=PUBLIC_IP.
  - Bind a dedicated send socket to PUBLIC_IP:PORT.  Socket-level binding
    sets the source IP without iptables, so replies leave with the correct
    source address.
  - Receive socket on 0.0.0.0:PORT catches DNAT'd packets from fly.io edge.
"""
import socket, os, struct, subprocess, sys, time, select

PORT = int(os.environ.get('PORT', 24567))
PUB  = os.environ.get('PUBLIC_IP', '')

def sh(*args) -> str:
    r = subprocess.run(args, capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip()
    print(f'  $ {" ".join(args)}' + (f' -> {out}' if out else ''), flush=True)
    return out

def detect_gateway() -> str:
    r = subprocess.run(['ip', 'route', 'show', 'default'], capture_output=True, text=True)
    if 'via' in r.stdout:
        return r.stdout.split('via')[1].strip().split()[0]
    return '172.19.7.161'

def setup_public_ip(pub_ip: str):
    """Add public IP to eth0 and set up source-based routing."""
    gw = detect_gateway()
    print(f'[net] Gateway = {gw}', flush=True)

    # 1. Add public IP to eth0 so it becomes a valid local source address.
    sh('ip', 'addr', 'add', f'{pub_ip}/32', 'dev', 'eth0')

    # 2. Routing table 100: default route with pub_ip as preferred source.
    sh('ip', 'route', 'add', 'default', 'via', gw, 'dev', 'eth0', 'src', pub_ip, 'table', '100')

    # 3. Policy rule: packets from pub_ip use table 100.
    sh('ip', 'rule', 'add', 'from', pub_ip, 'table', '100')

    # 4. Verify.
    sh('ip', '-4', 'addr', 'show', 'dev', 'eth0')
    sh('ip', 'route', 'show', 'table', '100')

def test_outbound_connectivity(pub_ip: str):
    """Test whether outbound UDP+TCP from both private and public IPs works."""
    import urllib.request, struct

    # --- TCP test: see what external IP is used for outbound connections ---
    try:
        with urllib.request.urlopen('https://api.ipify.org', timeout=5) as r:
            seen_ip = r.read().decode()
        print(f'[diag] TCP outbound: external IP seen by internet = {seen_ip}', flush=True)
    except Exception as e:
        print(f'[diag] TCP outbound test failed: {e}', flush=True)

    # --- UDP test: DNS query via private IP (recv_sock approach) ---
    dns_q = b'\xaa\xbb\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x03www\x06google\x03com\x00\x00\x01\x00\x01'
    # Detect global-svc IP for test
    r3 = subprocess.run(['ip', '-4', 'addr', 'show', 'dev', 'eth0'], capture_output=True, text=True)
    glosvcs = None
    for line in r3.stdout.splitlines():
        if 'secondary' in line and 'inet ' in line:
            glosvcs = line.strip().split()[1].split('/')[0]
            break

    test_ips = [('private', '0.0.0.0'), ('public', pub_ip)]
    if glosvcs:
        test_ips.append(('global-svc', glosvcs))

    for label, bind_ip in test_ips:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
            s.settimeout(3.0)
            s.bind((bind_ip, 0))
            s.sendto(dns_q, ('8.8.4.4', 53))
            resp, from_addr = s.recvfrom(512)
            print(f'[diag] UDP {label} ({bind_ip}) → 8.8.4.4:53 WORKS — got {len(resp)}b from {from_addr}', flush=True)
            s.close()
        except socket.timeout:
            print(f'[diag] UDP {label} ({bind_ip}) → 8.8.4.4:53 TIMED OUT (outbound blocked?)', flush=True)
            s.close()
        except Exception as e:
            print(f'[diag] UDP {label} ({bind_ip}) → 8.8.4.4:53 ERROR: {e}', flush=True)
            try: s.close()
            except: pass

def main():
    print(f'[net] PUBLIC_IP = {PUB!r}', flush=True)

    # Receive socket: wildcard — catches fly.io DNAT'd packets (dst = private IP).
    recv_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    recv_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    recv_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    recv_sock.bind(('0.0.0.0', PORT))
    print(f'[echo] recv_sock bound to 0.0.0.0:{PORT}', flush=True)

    send_sock = None
    if PUB:
        setup_public_ip(PUB)
        test_outbound_connectivity(PUB)
        # Detect fly-global-services secondary IP (172.19.x.x secondary on eth0)
        glosvcs_ip = None
        r2 = subprocess.run(['ip', '-4', 'addr', 'show', 'dev', 'eth0'], capture_output=True, text=True)
        for line in r2.stdout.splitlines():
            if 'secondary' in line and 'inet ' in line:
                glosvcs_ip = line.strip().split()[1].split('/')[0]
                break
        print(f'[net] fly-global-services IP = {glosvcs_ip!r}', flush=True)

        # Try bind order: fly-global-services first (native secondary, no ip addr add needed),
        # then public IP, then private (fallback)
        for bind_ip, label in [(glosvcs_ip, 'global-svc'), (PUB, 'public'), ('172.19.7.162', 'private')]:
            if not bind_ip:
                continue
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
                s.bind((bind_ip, PORT))
                send_sock = s
                print(f'[echo] send_sock bound to {bind_ip}:{PORT} (label={label})', flush=True)
                break
            except Exception as e:
                print(f'[echo] send_sock bind {bind_ip}:{PORT} FAILED: {e}', flush=True)

    # Monitor both sockets: packets may arrive on either depending on which IP
    # fly.io's DNAT targets (172.19.7.162 vs 172.19.7.163).
    # Reply from the same socket that received the packet so the source IP is correct.
    all_socks = [s for s in [recv_sock, send_sock] if s is not None]
    print(f'[echo] Monitoring sockets: {[s.getsockname() for s in all_socks]}', flush=True)

    seq = 0
    while True:
        try:
            readable, _, _ = select.select(all_socks, [], [], 60.0)
            if not readable:
                print('[echo] 60s idle', flush=True)
                continue

            for in_sock in readable:
                data, addr = in_sock.recvfrom(4096)
                seq += 1
                msg = data.decode('utf-8', errors='replace').strip()
                src_label = in_sock.getsockname()[0]
                reply = f'PONG src={src_label} seq={seq} echo={msg}'.encode()

                try:
                    in_sock.sendto(reply, addr)
                    print(f'[echo] #{seq} via {in_sock.getsockname()} {addr} -> {reply.decode()!r}', flush=True)
                except Exception as e:
                    print(f'[echo] send error via {in_sock.getsockname()}: {e}', flush=True)

        except Exception as e:
            print(f'[echo] error: {e}', flush=True)
            time.sleep(0.1)

if __name__ == '__main__':
    main()
