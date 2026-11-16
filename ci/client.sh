#!/bin/sh
# Runs inside netns "cli".  `ip netns exec` gives each invocation its
# own mount namespace, so the mount, the writer and the relock must all
# happen in this one process tree or the writer ends up on local disk.
# usage: client.sh <vers> <name> <secs>
set -u
v=$1 name=$2 secs=$3
timeout 60 mount -t nfs -o vers=$v,timeo=50 10.9.0.1:/srv/export /mnt/c || { echo MOUNT FAILED; exit 1; }
grep ' /mnt/c ' /proc/mounts
f=/mnt/c/$name.dat; rm -f $f
timeout $((secs + 120)) /root/writer.py $f $secs; echo "writer exit $?"
echo "-- extra lock attempt after failover"
timeout 60 python3 -c "import fcntl,os;fd=os.open('$f',os.O_RDWR);fcntl.lockf(fd,fcntl.LOCK_EX|fcntl.LOCK_NB);print('relock ok')" 2>&1
umount -f /mnt/c || umount -l /mnt/c
