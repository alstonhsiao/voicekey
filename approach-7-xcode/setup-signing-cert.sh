#!/usr/bin/env bash
# 一次性：建立 self-signed code-signing 憑證，讓 WhisperVoice 用穩定 identity 簽章。
#
# 為什麼要這個：
#   ad-hoc 簽章（codesign -s -）每次 rebuild 都產生新的 cdhash，macOS「輔助使用」
#   授權綁的是 path+cdhash，於是每次重編都會掉授權。改用固定的 self-signed 憑證後，
#   TCC 綁的是憑證 identity，rebuild 換 cdhash 也不會失效——只需授權一次。
#
# 用法：bash setup-signing-cert.sh
#   過程中可能會跳出要你輸入「登入密碼」（給 keychain 設定 codesign 存取權用）。
#   跑完一次即可，之後 build.sh 會自動用這張憑證。
set -euo pipefail

CERT_CN="WhisperVoice Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 強制用 macOS 內建 LibreSSL。Homebrew OpenSSL 3.x 產生的 .p12 用新版 MAC 演算法，
# macOS `security import` 會回 "MAC verification failed"。LibreSSL 產的是相容格式。
OPENSSL=/usr/bin/openssl

# 先清除所有同名舊憑證，避免 keychain 堆積導致 codesign 回 "ambiguous"。
# 必須用 SHA-1 逐一刪：當有多張同名時，`delete-certificate -c name` 會拒絕（ambiguous）。
removed=0
while true; do
  sha=$(security find-certificate -a -c "$CERT_CN" -Z "$KEYCHAIN" 2>/dev/null \
        | awk '/SHA-1 hash:/ {print $3; exit}')
  [ -z "$sha" ] && break
  security delete-certificate -Z "$sha" "$KEYCHAIN" >/dev/null 2>&1 || break
  removed=$((removed + 1))
done
[ "$removed" -gt 0 ] && echo "🧹 已移除 ${removed} 張舊的同名憑證。"

echo "🔧 產生 self-signed code-signing 憑證…"

cat > "$TMP/cert.conf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no
[ dn ]
CN = $CERT_CN
[ v3 ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP/wv.key" -out "$TMP/wv.crt" \
  -days 3650 -config "$TMP/cert.conf" 2>/dev/null

# macOS security 不接受「空密碼」的 p12（會回 MAC verification failed），
# 所以給一個臨時密碼；它只用於 p12→keychain 的傳輸，匯入後即無作用。
P12PW="whispervoice-temp"
"$OPENSSL" pkcs12 -export \
  -inkey "$TMP/wv.key" -in "$TMP/wv.crt" \
  -out "$TMP/wv.p12" -name "$CERT_CN" -passout pass:"$P12PW" 2>/dev/null

echo "🔧 匯入 login keychain…"
security import "$TMP/wv.p12" -k "$KEYCHAIN" -P "$P12PW" \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "🔧 設定 codesign 可存取私鑰（可能要求輸入登入密碼）…"
# 讓 codesign 不必每次跳 GUI 對話框就能用私鑰簽章。
if ! security set-key-partition-list \
      -S apple-tool:,apple: -s -k "" "$KEYCHAIN" >/dev/null 2>&1; then
  read -rsp "   請輸入登入密碼（keychain）: " PW; echo
  security set-key-partition-list \
    -S apple-tool:,apple: -s -k "$PW" "$KEYCHAIN" >/dev/null
fi

echo ""
echo "✅ 完成。憑證 ${CERT_CN} 已就緒。"
echo "   接著重新 build: bash build.sh"
echo "   首次啟動 App 後到輔助使用授權一次，之後 rebuild 都不會再掉授權。"
