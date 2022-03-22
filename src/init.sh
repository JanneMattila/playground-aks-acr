#!/usr/bin/env bash

cat >/etc/motd <<EOF
Azure ACR demo app

GitHub: https://github.com/JanneMattila/playground-aks-acr
EOF

cat /etc/motd

# Run the main application
$@
