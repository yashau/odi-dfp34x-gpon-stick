#!/bin/sh
# SSH to the stick with the legacy algorithms its dropbear offers.
#
#   tools/stick-ssh.sh                      interactive shell
#   tools/stick-ssh.sh 'diag gpon get onu-state'
#   tools/stick-ssh.sh 'cat > /var/config/rc.local' < stick/rc.local
#
# STICK (default 10.0.2.1) and STICK_USER (default admin) override the target.
# The password is prompted for; set SSH_ASKPASS to a program that prints it for
# unattended use. The stick allows only one SSH session at a time.

STICK=${STICK:-10.0.2.1}
STICK_USER=${STICK_USER:-admin}

if [ $# -gt 0 ]; then TTY=-T; else TTY=-t; fi

exec ssh $TTY \
	-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	-o ConnectTimeout=8 \
	-o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive \
	-o KexAlgorithms=+diffie-hellman-group1-sha1,diffie-hellman-group14-sha1 \
	-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa \
	-o Ciphers=+aes128-cbc,3des-cbc,aes256-cbc -o MACs=+hmac-sha1 \
	"$STICK_USER@$STICK" "$@"
