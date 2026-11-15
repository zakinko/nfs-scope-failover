#!/bin/sh
# Boot an AlmaLinux GenericCloud image under KVM and wait for ssh.
# usage: boot-vm.sh <release>
set -eu
rel=$1
img=AlmaLinux-$rel-GenericCloud-latest.x86_64.qcow2
curl -fsSL -o base.qcow2 https://repo.almalinux.org/almalinux/$rel/cloud/x86_64/images/$img
qemu-img create -q -f qcow2 -F qcow2 -b base.qcow2 vm.qcow2 20G
ssh-keygen -q -t ed25519 -N '' -f key
cat > user-data <<EOT
#cloud-config
users:
  - name: root
    ssh_authorized_keys: ["$(cat key.pub)"]
disable_root: false
ssh_pwauth: false
EOT
printf 'instance-id: t\nlocal-hostname: almavm\n' > meta-data
cloud-localds seed.img user-data meta-data
sudo chmod 666 /dev/kvm
qemu-system-x86_64 -enable-kvm -cpu host -smp 2 -m 4096 \
  -drive file=vm.qcow2,if=virtio -drive file=seed.img,if=virtio,format=raw \
  -nic user,model=virtio,hostfwd=tcp::2222-:22 \
  -display none -serial file:serial.log -daemonize -pidfile qemu.pid
i=0
while ! ssh -F ci/ssh_config vm true 2>/dev/null; do
  i=$((i+1)); [ $i -lt 60 ] || { tail -50 serial.log; exit 1; }; sleep 5
done
ssh -F ci/ssh_config vm 'cat /etc/os-release | head -2; uname -r'
