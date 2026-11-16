# nfs-scope-failover

Does an NFSv4.1/4.2 client holding a POSIX lock lose it (EIO) across a
server restart when the server scope changes, and does keeping the scope
the same avoid it?  On RHEL-family kernels nfsd copies the nodename of
the process that starts it into the server scope, so the scope is set
by the UTS namespace `rpc.nfsd` runs in.

`ci/test.sh` runs inside an AlmaLinux 8, 9 and 10 cloud image booted
under KVM on the runner.  The server runs in the VM's host network
namespace, the client in a separate namespace over a veth.  Each case
stops nfsd and starts it again with either a different nodename (nodeA
then nodeB) or the same one (nfs-ha twice), using `unshare -u` plus
`hostname` before `rpc.nfsd`, and with `rpc.nfsd -S` where nfs-utils
has it.

## Result (run 43896939490, 2026-11-17)

With a different nodename (nodeA, then nodeB) the client skips lock
reclaim and the writer's fd returns EIO for the rest of the run, on
AlmaLinux 8, 9 and 10, NFSv4.1 and 4.2.  The client logs
"Lock reclaim failed!" on 8 and "lost 1 locks" on 9 and 10.  With the
same nodename, or `rpc.nfsd -S` on 10 (nfs-utils 2.8.3; 8 and 9 do
not have it), the open is reclaimed with CLAIM_PREVIOUS and the writer
sees no errors.  On 8 the lock is reclaimed with LOCK; on 9 and 10 the
reclaimed open carries a write delegation and the lock stays local.
