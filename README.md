# さくらVPS SSL化ツールキット

さくらのVPSで運用しているWebサイト（irohaboard等）をSSL化するためのスクリプト集です。

## 概要

SSL非対応のWebサイトにアクセスする際、ブラウザに警告が表示されてアクセスできないという問題を解決するために作成されました。

このリポジトリには以下が含まれます：

1. **SSL化スクリプト** - Let's Encryptを使用した無料SSL証明書の自動取得・設定
2. **バックアップ/復元スクリプト** - 作業前のバックアップと問題発生時の復元
3. **SSH公開鍵認証設定スクリプト** - パスワード認証から公開鍵認証への切り替え
4. **利用者向けドキュメント** - SSL化完了までの暫定対応として、警告画面の回避方法

## ファイル構成

```
.
├── README.md                           # このファイル
├── REQUIREMENTS.md                     # 要求仕様書
├── TECHNICAL_DETAILS.md                # 技術詳細ドキュメント（実行コマンド詳細）
├── ssl_setup.sh                        # SSL化メインスクリプト
├── backup_server.sh                    # バックアップスクリプト
├── restore_server.sh                   # 復元スクリプト
├── ssh_setup.sh                        # SSH公開鍵認証設定スクリプト
├── SSH公開鍵認証_設定手順書.md           # SSH設定の手動作業手順書
├── さくらVPS_SSL化手順書.md              # SSL化の手動作業手順書
├── 教育研修サイト_アクセス手順書.html     # 利用者向け案内（HTML版）
└── 教育研修サイト_アクセス手順書.md       # 利用者向け案内（Markdown版）
```

## ドキュメント

| ドキュメント | 内容 |
|-------------|------|
| [README.md](README.md) | プロジェクト概要・クイックスタート |
| [REQUIREMENTS.md](REQUIREMENTS.md) | 要求仕様書（機能要求・非機能要求） |
| [TECHNICAL_DETAILS.md](TECHNICAL_DETAILS.md) | **技術詳細（実行コマンド・処理内容）** |
| [さくらVPS_SSL化手順書.md](さくらVPS_SSL化手順書.md) | SSL化の手動作業手順 |
| [SSH公開鍵認証_設定手順書.md](SSH公開鍵認証_設定手順書.md) | SSH設定の手動作業手順 |

## 動作要件

### サーバー側
- さくらのVPS（他のVPSでも動作可能）
- CentOS 7/8, Rocky Linux, AlmaLinux, Ubuntu, Debian
- Apache (httpd または apache2)
- root権限またはsudo権限

### SSL化の前提条件
- 独自ドメインを取得済み
- ドメインのDNSがサーバーのIPアドレスに向いている
- 80番ポート（HTTP）と443番ポート（HTTPS）が開放されている

## クイックスタート

### 1. スクリプトをサーバーに転送

```bash
scp ssl_setup.sh backup_server.sh restore_server.sh user@your-server:~/
```

### 2. サーバーにSSH接続

```bash
ssh user@your-server
```

### 3. 実行権限を付与

```bash
chmod +x ssl_setup.sh backup_server.sh restore_server.sh
```

### 4. SSL化スクリプトを実行

```bash
sudo ./ssl_setup.sh
```

スクリプトが対話形式で以下を実行します：
1. サーバー環境の自動検出
2. バックアップの作成（自動）
3. Certbotのインストール
4. SSL証明書の取得
5. Apacheの設定
6. 自動更新の設定

## スクリプト詳細

### ssl_setup.sh

SSL化のメインスクリプト。実行すると対話形式で必要な情報を入力し、自動でSSL化を行います。

```bash
sudo ./ssl_setup.sh
```

**処理フロー：**
```
Step 0: バックアップ確認・実行
Step 1: 環境確認（OS、Webサーバー検出）
Step 2: ドメイン名入力
Step 3: メールアドレス入力
Step 4: 設定確認
Step 5: Certbotインストール
Step 6: mod_ssl確認
Step 7: ファイアウォール設定
Step 8: SSL証明書取得
Step 9: Webサーバー再起動
Step 10: 自動更新テスト
```

### backup_server.sh

SSL化作業前にサーバーの設定をバックアップします。

```bash
sudo ./backup_server.sh
```

**バックアップ対象：**
- Apache設定（`/etc/httpd` または `/etc/apache2`）
- Let's Encrypt設定（`/etc/letsencrypt`）
- irohaboardファイル一式
- MySQLデータベース
- ファイアウォール設定
- crontab

**バックアップ保存先：** `/root/ssl_backup/YYYYMMDD_HHMMSS/`

### restore_server.sh

問題発生時にバックアップから復元します。

```bash
# バックアップ一覧から選択して復元
sudo ./restore_server.sh

# 特定のバックアップを指定して復元
sudo ./restore_server.sh /root/ssl_backup/20241228_143000

# 最新のバックアップから復元
sudo ./restore_server.sh /root/ssl_backup/latest
```

**復元オプション：**
1. すべて復元（Apache + irohaboard + データベース）
2. Apache設定のみ
3. irohaboardファイルのみ
4. データベースのみ
5. 個別選択

### ssh_setup.sh

SSHのパスワード認証を公開鍵認証に変更するスクリプトです。

```bash
sudo ./ssh_setup.sh
```

**前提条件：**
- ローカルPCで鍵ペア（秘密鍵・公開鍵）を生成済み
- 公開鍵をサーバーの `~/.ssh/authorized_keys` に登録済み
- 公開鍵認証でSSHログインできることを確認済み

**処理内容：**
1. 事前確認（公開鍵登録の確認）
2. 現在のSSH設定確認
3. sshd_configのバックアップ
4. 設定変更（パスワード認証無効化、公開鍵認証有効化）
5. 設定ファイルの文法チェック
6. SSHサービス再起動

**変更される設定：**
```
PasswordAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
PermitRootLogin no  # オプション
```

## 利用者向けドキュメント

SSL化が完了するまでの間、利用者がSSL警告を回避してサイトにアクセスするための手順書です。

### 対応デバイス・ブラウザ

| デバイス | ブラウザ |
|---------|---------|
| Windows PC | Chrome, Edge, Firefox |
| Mac | Safari, Chrome, Firefox |
| iPhone/iPad | Safari, Chrome |
| Android | Chrome, 標準ブラウザ |

### ドキュメントのカスタマイズ

`教育研修サイト_アクセス手順書.html` を編集して以下を変更してください：

- サイトのドメイン名（`example-training.sakura.ne.jp` → 実際のドメイン）
- 問い合わせ先（内線番号、メールアドレス）
- 最終更新日

## トラブルシューティング

### SSL証明書の取得に失敗する

**考えられる原因と対処：**

| 原因 | 対処 |
|------|------|
| DNSが未設定 | `nslookup ドメイン名` で確認、DNS設定を見直す |
| 80番ポートがブロック | ファイアウォール設定を確認 |
| さくらVPSのパケットフィルター | コントロールパネルで80/443を許可 |

### 復元後にサイトが動かない

```bash
# Apacheのエラーログを確認
sudo tail -f /var/log/httpd/error_log
# または
sudo tail -f /var/log/apache2/error.log

# Apacheの設定をテスト
sudo apachectl configtest
```

### 証明書の有効期限を確認

```bash
sudo certbot certificates
```

## 証明書の更新

Let's Encrypt証明書は90日で期限切れになりますが、Certbotが自動更新を設定します。

### 自動更新の確認

```bash
# 更新テスト
sudo certbot renew --dry-run

# cronまたはsystemd timerの確認
sudo systemctl list-timers | grep certbot
```

### 手動更新

```bash
sudo certbot renew
```

## ライセンス

MIT License

## 更新履歴

- 2024-12-29: SSH公開鍵認証設定スクリプト・手順書を追加
- 2024-12-28: 初版作成
