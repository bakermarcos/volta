#!/bin/zsh
set -eu
openssl_bin=/opt/homebrew/opt/openssl@3/bin/openssl
cert_dir="${1:-$HOME/Library/Containers/com.homegame.volta/Data/Library/Application Support/volta/https}"
[[ -x "$openssl_bin" ]] || { print 'Instale o OpenSSL 3 atualizado pelo Homebrew.'; exit 1; }
umask 077
mkdir -p "$cert_dir"
chmod 700 "$cert_dir"
if [[ ! -f "$cert_dir/ca.key" ]]; then
  "$openssl_bin" req -x509 -newkey rsa:3072 -noenc -sha256 -days 3650 -keyout "$cert_dir/ca.key" -out "$cert_dir/ca.pem" -subj '/CN=Volta Wi-Fi Local CA' -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign'
fi
san='DNS:localhost,IP:127.0.0.1'
for interface in en0 en1 en2; do
  local_ip=$(ipconfig getifaddr "$interface" 2>/dev/null || true)
  [[ -z "$local_ip" ]] || san="$san,IP:$local_ip"
done
print "subjectAltName=$san\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth" > "$cert_dir/server.ext"
"$openssl_bin" req -new -newkey rsa:2048 -noenc -keyout "$cert_dir/server.key" -out "$cert_dir/server.csr" -subj '/CN=Volta Local'
"$openssl_bin" x509 -req -in "$cert_dir/server.csr" -CA "$cert_dir/ca.pem" -CAkey "$cert_dir/ca.key" -CAcreateserial -days 365 -sha256 -extfile "$cert_dir/server.ext" -out "$cert_dir/server.pem"
cat "$cert_dir/server.pem" "$cert_dir/ca.pem" > "$cert_dir/chain.pem"
"$openssl_bin" x509 -in "$cert_dir/ca.pem" -outform DER -out "$cert_dir/volta-ca.cer"
"$openssl_bin" x509 -in "$cert_dir/ca.pem" -noout -fingerprint -sha256
print "HTTPS preparado em $cert_dir. Reabra a sala. SAN: $san"
