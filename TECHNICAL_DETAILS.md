# 技術詳細ドキュメント

このドキュメントでは、各スクリプトが実行する具体的なコマンドと処理内容を詳細に説明します。

---

## 目次

1. [ssl_setup.sh - SSL化スクリプト](#1-ssl_setupsh---ssl化スクリプト)
2. [backup_server.sh - バックアップスクリプト](#2-backup_serversh---バックアップスクリプト)
3. [restore_server.sh - 復元スクリプト](#3-restore_serversh---復元スクリプト)
4. [ssh_setup.sh - SSH公開鍵認証設定スクリプト](#4-ssh_setupsh---ssh公開鍵認証設定スクリプト)
5. [ファイル構成とパス一覧](#5-ファイル構成とパス一覧)

---

## 1. ssl_setup.sh - SSL化スクリプト

### 1.1 概要

| 項目 | 内容 |
|------|------|
| 実行権限 | root（sudo） |
| 対話形式 | あり（ドメイン名、メールアドレス等を入力） |
| 所要時間 | 約10〜30分 |
| 依存スクリプト | backup_server.sh（同一ディレクトリに配置） |

### 1.2 処理フロー詳細

#### Step 0: バックアップの確認・実行

```bash
# バックアップディレクトリの存在確認
if [ -d "/root/ssl_backup" ] && [ -L "/root/ssl_backup/latest" ]; then
    # 既存バックアップを使用するか確認
fi

# 新規バックアップの実行
bash ./backup_server.sh
```

**処理内容：**
- `/root/ssl_backup/latest` シンボリックリンクの存在確認
- 既存バックアップがあれば使用するか確認
- なければ `backup_server.sh` を自動実行

---

#### Step 1: 環境確認

**OS検出：**
```bash
# OS情報の取得
cat /etc/os-release
# または
cat /etc/redhat-release
```

**パッケージマネージャー検出：**
```bash
# 優先順位: dnf > yum > apt
command -v dnf   # CentOS 8+, Rocky Linux, AlmaLinux
command -v yum   # CentOS 7
command -v apt   # Ubuntu, Debian
```

**Webサーバー検出：**
```bash
# systemctlでサービス状態を確認
systemctl is-active --quiet httpd    # CentOS系
systemctl is-active --quiet apache2  # Ubuntu/Debian系
systemctl is-active --quiet nginx    # Nginx（非対応）
```

---

#### Step 2: ドメイン名の設定

**DNS解決確認：**
```bash
# nslookupで確認
nslookup your-domain.jp

# または hostコマンドで確認
host your-domain.jp
```

**入力値のバリデーション：**
- 正規表現によるドメイン形式チェック
- 空入力のチェック

---

#### Step 3: メールアドレスの入力

Let's Encryptからの通知（証明書期限切れ警告等）を受け取るメールアドレスを入力。

---

#### Step 4: 設定確認

入力された情報を表示し、続行するか確認。

---

#### Step 5: Certbotのインストール

**CentOS 7 の場合：**
```bash
yum install -y epel-release
yum install -y certbot python2-certbot-apache
```

**CentOS 8 / Rocky Linux / AlmaLinux の場合：**
```bash
dnf install -y epel-release
dnf install -y certbot python3-certbot-apache
```

**Ubuntu / Debian の場合：**
```bash
apt update
apt install -y certbot python3-certbot-apache
```

**インストール確認：**
```bash
command -v certbot
certbot --version
```

---

#### Step 6: mod_ssl の確認・インストール

**CentOS/RHEL系：**
```bash
# mod_sslがロードされているか確認
httpd -M 2>/dev/null | grep ssl_module

# インストールされていない場合
yum install -y mod_ssl
# または
dnf install -y mod_ssl
```

**Ubuntu/Debian系：**
```bash
# mod_sslが有効か確認
apache2ctl -M 2>/dev/null | grep ssl_module

# 有効化されていない場合
a2enmod ssl
systemctl restart apache2
```

---

#### Step 7: ファイアウォール設定

**firewalld（CentOS系）の場合：**
```bash
# 現在の設定確認
firewall-cmd --list-services

# HTTP/HTTPSの許可（永続設定）
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https

# 設定の反映
firewall-cmd --reload
```

**ufw（Ubuntu）の場合：**
```bash
# 現在の設定確認
ufw status

# ポートの許可
ufw allow 80/tcp
ufw allow 443/tcp
```

---

#### Step 8: SSL証明書の取得

**Certbotの実行：**
```bash
certbot --apache \
    --non-interactive \
    --agree-tos \
    --email "入力されたメールアドレス" \
    --domains "入力されたドメイン" \
    --redirect
```

**オプションの説明：**

| オプション | 説明 |
|-----------|------|
| `--apache` | Apache用プラグインを使用 |
| `--non-interactive` | 対話なしで実行 |
| `--agree-tos` | 利用規約に同意 |
| `--email` | 通知用メールアドレス |
| `--domains` | SSL化するドメイン |
| `--redirect` | HTTP→HTTPSリダイレクトを設定 |

**証明書の保存先：**
```
/etc/letsencrypt/live/ドメイン名/
├── fullchain.pem   # 証明書チェーン（サーバー証明書 + 中間証明書）
├── privkey.pem     # 秘密鍵
├── cert.pem        # サーバー証明書
└── chain.pem       # 中間証明書
```

**Apacheへの自動設定内容：**
- VirtualHost設定の作成/更新
- SSLEngine on の設定
- 証明書ファイルパスの設定
- HTTPからHTTPSへのリダイレクト設定

---

#### Step 9: Webサーバー再起動

```bash
# CentOS系
systemctl restart httpd

# Ubuntu/Debian系
systemctl restart apache2

# 起動確認
systemctl is-active --quiet httpd
# または
systemctl is-active --quiet apache2
```

---

#### Step 10: 自動更新のテスト

```bash
# 更新のドライラン（実際には更新しない）
certbot renew --dry-run
```

**成功時の出力例：**
```
Congratulations, all simulated renewals succeeded
```

**自動更新の仕組み：**
- Certbotインストール時に自動で設定される
- systemd timer または cron で定期実行

**確認コマンド：**
```bash
# systemd timerの確認
systemctl list-timers | grep certbot

# cronの確認
cat /etc/cron.d/certbot
```

---

## 2. backup_server.sh - バックアップスクリプト

### 2.1 概要

| 項目 | 内容 |
|------|------|
| 実行権限 | root（sudo） |
| バックアップ先 | /root/ssl_backup/YYYYMMDD_HHMMSS/ |
| 圧縮形式 | tar.gz（ファイル）、gzip（SQLダンプ） |

### 2.2 バックアップ対象と実行コマンド

#### バックアップディレクトリの作成

```bash
BACKUP_BASE_DIR="/root/ssl_backup"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="${BACKUP_BASE_DIR}/${TIMESTAMP}"

mkdir -p "$BACKUP_DIR"
```

---

#### Apache設定のバックアップ

**CentOS/RHEL系：**
```bash
# /etc/httpd をコピー（パーミッション保持）
cp -rp /etc/httpd "${BACKUP_DIR}/apache/"
```

**Ubuntu/Debian系：**
```bash
# /etc/apache2 をコピー（パーミッション保持）
cp -rp /etc/apache2 "${BACKUP_DIR}/apache/"
```

**Let's Encrypt設定：**
```bash
# 証明書と設定をコピー
cp -rp /etc/letsencrypt "${BACKUP_DIR}/apache/"
```

**SSL証明書ディレクトリ：**
```bash
cp -rp /etc/ssl "${BACKUP_DIR}/apache/"
```

---

#### irohaboardファイルのバックアップ

**検索パス：**
```bash
IROHA_PATHS=(
    "/var/www/html/irohaboard"
    "/var/www/irohaboard"
    "/var/www/html"
    "/home/*/public_html/irohaboard"
    "/home/*/www/irohaboard"
)
```

**バックアップコマンド：**
```bash
# tar.gz形式で圧縮バックアップ
tar -czf "${BACKUP_DIR}/irohaboard/irohaboard_files.tar.gz" \
    -C "$(dirname "$IROHA_PATH")" \
    "$(basename "$IROHA_PATH")"
```

**オプションの説明：**

| オプション | 説明 |
|-----------|------|
| `-c` | アーカイブを作成 |
| `-z` | gzip圧縮 |
| `-f` | 出力ファイル名を指定 |
| `-C` | 作業ディレクトリを変更 |

---

#### データベースのバックアップ

**DB接続情報の自動取得：**
```bash
# irohaboardの設定ファイルから抽出
DB_CONFIG_FILE="${IROHA_PATH}/app/Config/database.php"

# 正規表現で抽出
DB_NAME=$(grep -oP "'database'\s*=>\s*'\K[^']+" "$DB_CONFIG_FILE")
DB_USER=$(grep -oP "'login'\s*=>\s*'\K[^']+" "$DB_CONFIG_FILE")
DB_PASS=$(grep -oP "'password'\s*=>\s*'\K[^']+" "$DB_CONFIG_FILE")
DB_HOST=$(grep -oP "'host'\s*=>\s*'\K[^']+" "$DB_CONFIG_FILE")
```

**mysqldumpコマンド：**
```bash
mysqldump -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
    > "${BACKUP_DIR}/database/${DB_NAME}.sql"

# gzip圧縮
gzip "${BACKUP_DIR}/database/${DB_NAME}.sql"
```

**出力ファイル：**
- `${DB_NAME}.sql.gz` - 圧縮されたSQLダンプ
- `db_info.txt` - 接続情報（パスワード除く）

---

#### システム設定のバックアップ

**firewalld設定：**
```bash
# 現在の設定を出力
firewall-cmd --list-all > "${BACKUP_DIR}/system/firewalld_config.txt"

# 設定ディレクトリをコピー
cp -rp /etc/firewalld "${BACKUP_DIR}/system/"
```

**ufw設定：**
```bash
ufw status verbose > "${BACKUP_DIR}/system/ufw_status.txt"
cp -rp /etc/ufw "${BACKUP_DIR}/system/"
```

**その他：**
```bash
# hostsファイル
cp -p /etc/hosts "${BACKUP_DIR}/system/"

# root crontab
crontab -l > "${BACKUP_DIR}/system/crontab_root.txt"

# 実行中サービス一覧
systemctl list-units --type=service --state=running \
    > "${BACKUP_DIR}/system/running_services.txt"
```

---

#### 最新バックアップへのリンク

```bash
ln -sfn "$BACKUP_DIR" "${BACKUP_BASE_DIR}/latest"
```

---

### 2.3 バックアップディレクトリ構成

```
/root/ssl_backup/
├── 20241228_143000/
│   ├── backup_info.txt           # バックアップ情報
│   ├── apache/
│   │   ├── httpd/                # Apache設定（CentOS）
│   │   ├── apache2/              # Apache設定（Ubuntu）
│   │   ├── letsencrypt/          # Let's Encrypt設定
│   │   └── ssl/                  # SSL証明書
│   ├── irohaboard/
│   │   ├── irohaboard_files.tar.gz  # ファイル一式
│   │   └── original_path.txt        # 元のパス
│   ├── database/
│   │   ├── dbname.sql.gz         # DBダンプ（圧縮）
│   │   └── db_info.txt           # DB接続情報
│   └── system/
│       ├── firewalld_config.txt  # ファイアウォール設定
│       ├── firewalld/            # firewalld設定ディレクトリ
│       ├── hosts                 # hostsファイル
│       ├── crontab_root.txt      # crontab
│       └── running_services.txt  # サービス一覧
└── latest -> 20241228_143000/    # 最新へのシンボリックリンク
```

---

## 3. restore_server.sh - 復元スクリプト

### 3.1 概要

| 項目 | 内容 |
|------|------|
| 実行権限 | root（sudo） |
| 引数 | バックアップディレクトリ（省略可） |
| 復元オプション | 全部 / Apache / irohaboard / DB / 個別選択 |

### 3.2 処理フロー詳細

#### バックアップの選択

**引数なしの場合：**
```bash
# バックアップ一覧を表示
for dir in $(ls -dt /root/ssl_backup/2* 2>/dev/null); do
    SIZE=$(du -sh "$dir" | cut -f1)
    DATE=$(basename "$dir")
    echo "$i)    $DATE    $SIZE"
done
```

**引数ありの場合：**
```bash
# シンボリックリンクを解決
BACKUP_DIR=$(readlink -f "$1")
```

---

#### 復元項目の選択

```
1) すべて復元（Apache + irohaboard + データベース）
2) Apache設定のみ復元
3) irohaboardファイルのみ復元
4) データベースのみ復元
5) 個別に選択
```

---

#### Webサーバーの停止

```bash
# CentOS系
systemctl stop httpd

# Ubuntu/Debian系
systemctl stop apache2
```

---

#### Apache設定の復元

**現在の設定を退避：**
```bash
# CentOS系
mv /etc/httpd /etc/httpd.before_restore.$(date +%Y%m%d%H%M%S)

# Ubuntu/Debian系
mv /etc/apache2 /etc/apache2.before_restore.$(date +%Y%m%d%H%M%S)
```

**バックアップから復元：**
```bash
# パーミッションを保持してコピー
cp -rp "${BACKUP_DIR}/apache/httpd" /etc/
cp -rp "${BACKUP_DIR}/apache/apache2" /etc/
cp -rp "${BACKUP_DIR}/apache/letsencrypt" /etc/
```

---

#### irohaboardファイルの復元

**元のパスを取得：**
```bash
ORIGINAL_PATH=$(cat "${BACKUP_DIR}/irohaboard/original_path.txt")
```

**現在のディレクトリを退避：**
```bash
mv "$ORIGINAL_PATH" "${ORIGINAL_PATH}.before_restore.$(date +%Y%m%d%H%M%S)"
```

**アーカイブを展開：**
```bash
tar -xzf "${BACKUP_DIR}/irohaboard/irohaboard_files.tar.gz" \
    -C "$(dirname "$ORIGINAL_PATH")"
```

**オプションの説明：**

| オプション | 説明 |
|-----------|------|
| `-x` | アーカイブを展開 |
| `-z` | gzip圧縮を解凍 |
| `-f` | 入力ファイル名を指定 |
| `-C` | 展開先ディレクトリを指定 |

---

#### データベースの復元

**圧縮ファイルの場合：**
```bash
gunzip -c "${BACKUP_DIR}/database/${DB_NAME}.sql.gz" | \
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME"
```

**非圧縮ファイルの場合：**
```bash
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
    < "${BACKUP_DIR}/database/${DB_NAME}.sql"
```

---

#### Webサーバーの起動

```bash
# CentOS系
systemctl start httpd

# Ubuntu/Debian系
systemctl start apache2

# 起動確認
systemctl is-active --quiet httpd
```

---

## 4. ssh_setup.sh - SSH公開鍵認証設定スクリプト

### 4.1 概要

| 項目 | 内容 |
|------|------|
| 実行権限 | root（sudo） |
| 対話形式 | あり（確認プロンプト） |
| 所要時間 | 約5分 |
| 前提条件 | 公開鍵認証でログインできることを事前確認 |

### 4.2 処理フロー詳細

#### Step 1: 事前確認

スクリプト実行前に以下を確認するようユーザーに促します：

1. ローカルPCで鍵ペアを生成済み
2. 公開鍵をサーバーに登録済み
3. 公開鍵認証でログイン可能

#### Step 2: 現在のSSH設定を確認

```bash
# 現在の設定を表示
grep -E "^(PasswordAuthentication|PubkeyAuthentication|PermitRootLogin|ChallengeResponseAuthentication)" /etc/ssh/sshd_config

# authorized_keysの確認
CURRENT_USER=$(logname 2>/dev/null || echo "$SUDO_USER")
AUTH_KEYS="/home/${CURRENT_USER}/.ssh/authorized_keys"
wc -l < "$AUTH_KEYS"  # 登録されている公開鍵の数
```

#### Step 3: 設定のバックアップ

```bash
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_FILE="${SSHD_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"

cp -p "$SSHD_CONFIG" "$BACKUP_FILE"
```

**バックアップファイル例：** `/etc/ssh/sshd_config.backup.20241228_150000`

#### Step 4: 変更内容の確認

ユーザーに変更内容を表示し、確認を求めます。

#### Step 5: sshd_configを変更

**変更する設定項目と実行コマンド：**

```bash
# PasswordAuthentication を no に変更
sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
# または（コメントアウトされている場合）
sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
# または（設定がない場合）
echo "PasswordAuthentication no" >> /etc/ssh/sshd_config

# ChallengeResponseAuthentication を no に変更
sed -i 's/^ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config

# PubkeyAuthentication を yes に変更
sed -i 's/^PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# PermitEmptyPasswords を no に変更
sed -i 's/^PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config

# PermitRootLogin を no に変更（オプション）
sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
```

**変更後の設定値：**

| 設定項目 | 変更後の値 | 説明 |
|---------|-----------|------|
| `PasswordAuthentication` | no | パスワード認証を無効化 |
| `ChallengeResponseAuthentication` | no | チャレンジレスポンス認証を無効化 |
| `PubkeyAuthentication` | yes | 公開鍵認証を有効化 |
| `PermitEmptyPasswords` | no | 空パスワードを禁止 |
| `PermitRootLogin` | no | rootログインを禁止（オプション） |

#### Step 6: 設定ファイルの文法チェック

```bash
sshd -t
```

エラーがある場合はバックアップから復元：
```bash
cp -p "$BACKUP_FILE" /etc/ssh/sshd_config
```

#### Step 7: SSHサービスの再起動

```bash
# CentOS / Rocky Linux / AlmaLinux
systemctl restart sshd

# Ubuntu / Debian
systemctl restart ssh

# 起動確認
systemctl is-active --quiet sshd
# または
systemctl is-active --quiet ssh
```

### 4.3 ローカルPCでの鍵生成コマンド

**Ed25519形式（推奨）：**
```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
```

**RSA 4096bit形式：**
```bash
ssh-keygen -t rsa -b 4096 -C "your-email@example.com"
```

**オプションの説明：**

| オプション | 説明 |
|-----------|------|
| `-t` | 鍵の種類（ed25519, rsa, ecdsa, dsa） |
| `-b` | 鍵のビット長（RSAの場合） |
| `-C` | コメント（識別用） |

**生成されるファイル：**

| ファイル | 説明 |
|---------|------|
| `~/.ssh/id_ed25519` | 秘密鍵（絶対に漏洩させない） |
| `~/.ssh/id_ed25519.pub` | 公開鍵（サーバーに登録） |

### 4.4 公開鍵のサーバー登録コマンド

**ssh-copy-id を使用（推奨）：**
```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub ユーザー名@サーバーIP
```

**手動で登録：**
```bash
# サーバー側で実行
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "公開鍵の内容" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 4.5 必要なパーミッション

| パス | パーミッション | 説明 |
|------|--------------|------|
| `~/.ssh/` | 700 (drwx------) | SSHディレクトリ |
| `~/.ssh/authorized_keys` | 600 (-rw-------) | 公開鍵ファイル |
| `~/.ssh/id_ed25519` | 600 (-rw-------) | 秘密鍵 |
| `~/.ssh/id_ed25519.pub` | 644 (-rw-r--r--) | 公開鍵 |
| `~/.ssh/config` | 600 (-rw-------) | SSH設定ファイル |

### 4.6 設定確認コマンド

**公開鍵認証でログイン：**
```bash
ssh ユーザー名@サーバーIP
```

**パスワード認証が無効か確認：**
```bash
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no ユーザー名@サーバーIP
# → "Permission denied (publickey)." と表示されれば成功
```

**詳細ログでデバッグ：**
```bash
ssh -v ユーザー名@サーバーIP
```

### 4.7 トラブル時の復元

**バックアップから復元：**
```bash
sudo cp /etc/ssh/sshd_config.backup.YYYYMMDD_HHMMSS /etc/ssh/sshd_config
sudo systemctl restart sshd
```

**さくらVPS VNCコンソールからの復元：**
1. さくらVPSコントロールパネルにログイン
2. 対象サーバーを選択
3. 「コンソール」→「VNCコンソール」を開く
4. サーバーに直接ログイン
5. 上記の復元コマンドを実行

---

## 5. ファイル構成とパス一覧

### 5.1 スクリプトが参照・変更するパス

#### システムパス

| パス | 説明 | 操作 |
|------|------|------|
| `/etc/httpd/` | Apache設定（CentOS） | バックアップ/復元 |
| `/etc/apache2/` | Apache設定（Ubuntu） | バックアップ/復元 |
| `/etc/letsencrypt/` | Let's Encrypt証明書・設定 | バックアップ/復元/作成 |
| `/etc/ssl/` | システムSSL証明書 | バックアップ |
| `/etc/firewalld/` | firewalld設定 | バックアップ/変更 |
| `/etc/ufw/` | ufw設定 | バックアップ/変更 |
| `/etc/hosts` | hostsファイル | バックアップ |
| `/etc/cron.d/certbot` | Certbot自動更新cron | 確認 |
| `/etc/ssh/sshd_config` | SSH設定ファイル | バックアップ/変更 |
| `~/.ssh/authorized_keys` | SSH公開鍵 | 確認/登録 |

#### アプリケーションパス

| パス | 説明 | 操作 |
|------|------|------|
| `/var/www/html/irohaboard/` | irohaboard（デフォルト） | バックアップ/復元 |
| `/var/www/html/irohaboard/app/Config/database.php` | DB設定ファイル | 読み取り |
| `/var/www/html/irohaboard/app/Config/core.php` | アプリ設定 | 案内のみ |

#### バックアップパス

| パス | 説明 |
|------|------|
| `/root/ssl_backup/` | バックアップベースディレクトリ |
| `/root/ssl_backup/YYYYMMDD_HHMMSS/` | 各バックアップ |
| `/root/ssl_backup/latest` | 最新バックアップへのシンボリックリンク |

#### ログパス

| パス | 説明 |
|------|------|
| `/var/log/httpd/error_log` | Apacheエラーログ（CentOS） |
| `/var/log/apache2/error.log` | Apacheエラーログ（Ubuntu） |
| `/var/log/letsencrypt/letsencrypt.log` | Certbotログ |

---

### 4.2 インストールされるパッケージ

#### CentOS 7

```bash
epel-release
certbot
python2-certbot-apache
mod_ssl
```

#### CentOS 8 / Rocky Linux / AlmaLinux

```bash
epel-release
certbot
python3-certbot-apache
mod_ssl
```

#### Ubuntu / Debian

```bash
certbot
python3-certbot-apache
```

---

### 4.3 使用する外部コマンド

| コマンド | 用途 | 必須/任意 |
|---------|------|----------|
| `systemctl` | サービス管理 | 必須 |
| `certbot` | SSL証明書取得 | 必須（インストール） |
| `tar` | ファイルアーカイブ | 必須 |
| `gzip` / `gunzip` | 圧縮/解凍 | 必須 |
| `mysqldump` | DBバックアップ | 必須 |
| `mysql` | DB復元 | 必須 |
| `firewall-cmd` | ファイアウォール設定 | CentOS系で必須 |
| `ufw` | ファイアウォール設定 | Ubuntu系で必須 |
| `nslookup` / `host` | DNS確認 | 任意 |
| `grep` | テキスト検索 | 必須 |
| `cp` | ファイルコピー | 必須 |
| `mv` | ファイル移動 | 必須 |
| `ln` | シンボリックリンク作成 | 必須 |

---

## 更新履歴

| 日付 | バージョン | 内容 |
|------|-----------|------|
| 2024-12-28 | 1.0 | 初版作成 |
