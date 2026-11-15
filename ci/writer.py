#!/usr/bin/python3
# Hold a POSIX lock on a file over NFS and keep writing with fsync,
# logging every error with a timestamp.  usage: writer.py <file> <secs>
import fcntl, os, sys, time
path, secs = sys.argv[1], float(sys.argv[2])
fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o644)
fcntl.lockf(fd, fcntl.LOCK_EX)
print("%.1f locked" % time.time(), flush=True)
end = time.time() + secs
n = errs = 0
while time.time() < end:
    try:
        os.write(fd, b"x" * 512)
        os.fsync(fd)
        n += 1
    except OSError as e:
        errs += 1
        if errs <= 5 or errs % 20 == 0:
            print("%.1f ERR %s" % (time.time(), e), flush=True)
    time.sleep(0.5)
try:
    fcntl.lockf(fd, fcntl.LOCK_UN)
    print("%.1f unlock ok" % time.time())
except OSError as e:
    print("%.1f unlock ERR %s" % (time.time(), e))
print("writes=%d errors=%d" % (n, errs))
