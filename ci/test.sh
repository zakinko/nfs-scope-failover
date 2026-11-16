#!/bin/sh
# Runs inside the VM as root.  Server nfsd in the host netns, client in
# netns "cli" over a veth.  Failover = stop nfsd, restart it with another
# (or the same) UTS nodename, which is what nfsd copies into the server
# scope at start on RHEL kernels.
set -u
cd /root
dnf -q -y install nfs-utils python3 wireshark-cli tcpdump iproute >/dev/null 2>&1 \
  || dnf -y install nfs-utils python3 wireshark-cli tcpdump iproute
echo "== versions"
uname -r; rpm -q nfs-utils kernel | sort -u
echo "== native scope option"
NATIVE=no
# --help output does not list every option; look in the binary
if grep -a -q 'scope' "$(command -v rpc.nfsd)"; then NATIVE=yes; fi
grep -a -o '[a-z]*scope[a-z=]*' "$(command -v rpc.nfsd)" | sort -u
grep -n -i scope /etc/nfs.conf || true
echo "rpc.nfsd -S: $NATIVE"; rpc.nfsd --help 2>&1 | grep -i -- scope || true

# network: host 10.9.0.1 <-> cli 10.9.0.2
ip netns add cli
ip link add vh type veth peer name vc
ip link set vc netns cli
ip addr add 10.9.0.1/24 dev vh; ip link set vh up
ip netns exec cli ip addr add 10.9.0.2/24 dev vc
ip netns exec cli ip link set vc up; ip netns exec cli ip link set lo up

mkdir -p /srv/export /mnt/c
chmod 777 /srv/export
echo '/srv/export 10.9.0.0/24(rw,no_root_squash,sync,fsid=1)' > /etc/exports
systemctl start nfs-server || { journalctl -u nfs-server | tail; }
systemctl is-active nfsdcld 2>/dev/null; ls -la /var/lib/nfs /var/lib/nfs/v4recovery /var/lib/nfs/nfsdcld 2>&1 | head -30
rpc.nfsd 0

start_nfsd() { # $1 = hostname, $2 = native scope or ""
  echo 15 > /proc/fs/nfsd/nfsv4leasetime
  echo 15 > /proc/fs/nfsd/nfsv4gracetime
  if [ -n "$2" ]; then
    rpc.nfsd -S "$2" 8
  else
    unshare -u sh -c "hostname $1; rpc.nfsd 8"
  fi
  exportfs -r
  echo "nfsd started: host=$1 native=$2 threads=$(cat /proc/fs/nfsd/threads) versions=$(cat /proc/fs/nfsd/versions)"
}

runcase() { # name vers hostA hostB nativeA nativeB
  name=$1; v=$2
  echo; echo "########## case $name vers=$v A=$3/$5 B=$4/$6"
  dmesg -C
  timeout 300 tcpdump -q -i vh -s 0 -w /root/$name.pcap port 2049 2>/dev/null &
  tp=$!
  start_nfsd "$3" "$5"
  sleep 1
  ip netns exec cli sh /root/client.sh $v $name 60 > /root/$name.client 2>&1 &
  cp=$!
  # Server A's first LOCK can get NFS4ERR_GRACE (lockd's grace while
  # v3 is enabled); fail over only once the lock is really held.
  i=0
  until grep -q locked /root/$name.client 2>/dev/null; do
    i=$((i+1)); [ $i -lt 150 ] || { echo "writer never got the lock"; break; }; sleep 1
  done
  echo "-- lock held after ${i}s"
  sleep 5
  echo "-- failover at $(date +%s)"
  rpc.nfsd 0; exportfs -f
  sleep 3
  start_nfsd "$4" "$6"
  wait $cp
  cat /root/$name.client
  echo "-- client dmesg"; dmesg | grep -E 'NFS|nfs|grace|reclaim|lock' | tail -40
  rpc.nfsd 0; sleep 1
  kill $tp 2>/dev/null; wait $tp 2>/dev/null
  echo "-- EXCHANGE_ID replies: major id and server scope bytes"
  tshark -r /root/$name.pcap -Y 'nfs.opcode == 42 && rpc.msgtyp == 1' -T fields \
    -e frame.number -e frame.time_relative -e nfs.data 2>&1 | head
  tshark -r /root/$name.pcap -Y 'nfs.opcode == 42 && rpc.msgtyp == 1' -x 2>/dev/null \
    | grep -E -o '  [^ ].{0,16}$' | tr -d '\n' | tr -s '.' ; echo
  echo "-- state ops on the wire (OPEN claim, LOCK reclaim, RECLAIM_COMPLETE, errors)"
  tshark -r /root/$name.pcap -Y 'nfs' -V 2>/dev/null | grep -E \
    -e '^Frame [0-9]+:' -e 'Opcode: (OPEN|LOCK|RECLAIM_COMPLETE|EXCHANGE_ID|CREATE_SESSION) ' \
    -e 'claim_type|reclaim\?|Status: NFS4ERR' | grep -B1 -v '^Frame' | grep -v '^--' | grep -v 'Main Opcode' | paste - - | uniq -c | head -60
}

for v in 4.2 4.1; do
  runcase diff-$v $v nodeA nodeB "" ""
  runcase same-$v $v nfs-ha nfs-ha "" ""
  if [ $NATIVE = yes ]; then
    runcase native-$v $v nodeA nodeB nfs-ha nfs-ha
  fi
done

echo; echo "########## probe: nfsd inside a separate netns"
ip netns add srvA
dmesg -C
ip netns exec srvA rpc.nfsd 8; echo "rpc.nfsd in netns exit $?"
ip netns exec srvA cat /proc/fs/nfsd/threads
ip netns exec srvA rpc.nfsd 0
dmesg | tail -10
