#!/bin/zsh
# One-time: makes a local "Melcolm Local Signing" certificate so every build keeps the same
# identity and macOS stops asking for Accessibility / Bluetooth after each update.
set -e
NAME="Melcolm Local Signing"
security find-identity -p codesigning | grep -q "$NAME" && { echo "Already exists"; exit 0; }
T=$(mktemp -d)
cat > $T/c.cnf <<CNF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
basicConstraints=critical,CA:false
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout $T/k.pem -out $T/c.pem -config $T/c.cnf
openssl pkcs12 -export -legacy -inkey $T/k.pem -in $T/c.pem -out $T/c.p12 -passout pass:melcolm 2>/dev/null \
  || openssl pkcs12 -export -inkey $T/k.pem -in $T/c.pem -out $T/c.p12 -passout pass:melcolm
security import $T/c.p12 -k ~/Library/Keychains/login.keychain-db -P melcolm -T /usr/bin/codesign
rm -rf $T
echo "Created $NAME"
