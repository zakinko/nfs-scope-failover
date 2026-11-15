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
