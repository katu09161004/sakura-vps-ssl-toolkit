# さくらVPS irohaboard SSL化手順書

## 概要

Let's Encrypt（無料SSL証明書）とCertbotを使用して、irohaboardをSSL化します。

---

## 前提条件

- [x] 独自ドメインを取得済み
- [ ] ドメインのDNS設定がサーバーのIPアドレスに向いている
- [ ] サーバーにSSH接続可能
- [ ] root権限またはsudo権限がある

---

## 手順

### 1. サーバーにSSH接続

```bash
ssh ユーザー名@サーバーのIPアドレス
# または
ssh ユーザー名@ドメイン名
```

---

### 2. OSバージョンの確認

```bash
cat /etc/os-release
```

以下、**CentOS/Rocky Linux/AlmaLinux** と **Ubuntu/Debian** の両方の手順を記載します。

---

### 3. Certbot（Let's Encryptクライアント）のインストール

#### CentOS 7 の場合

```bash
# EPELリポジトリを有効化
sudo yum install -y epel-release

# Certbotとapacheプラグインをインストール
sudo yum install -y certbot python2-certbot-apache
```

#### CentOS 8 / Rocky Linux / AlmaLinux の場合

```bash
# EPELリポジトリを有効化
sudo dnf install -y epel-release

# Certbotとapacheプラグインをインストール
sudo dnf install -y certbot python3-certbot-apache
```

#### Ubuntu / Debian の場合

```bash
# パッケージを更新
sudo apt update

# Certbotとapacheプラグインをインストール
sudo apt install -y certbot python3-certbot-apache
```

---

### 4. ファイアウォールの確認・設定

#### firewalld（CentOS系）の場合

```bash
# 現在の設定を確認
sudo firewall-cmd --list-all

# HTTP(80)とHTTPS(443)を許可
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https

# 設定を反映
sudo firewall-cmd --reload
```

#### ufw（Ubuntu）の場合

```bash
# 現在の設定を確認
sudo ufw status

# HTTP(80)とHTTPS(443)を許可
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

#### さくらVPSのコントロールパネル

さくらVPSの管理画面でパケットフィルターを使用している場合は、そちらでも443番ポートを開放してください。

1. さくらVPSコントロールパネルにログイン
2. 対象サーバーを選択
3. 「パケットフィルター」→「パケットフィルター設定」
4. 「Web」または「カスタム」で443/TCPを許可

---

### 5. 現在のApache設定を確認

```bash
# Apacheの設定ファイルを確認
cat /etc/httpd/conf/httpd.conf | grep -i servername
# または
cat /etc/apache2/sites-available/000-default.conf | grep -i servername

# ドメインが設定されているか確認
# ServerName がドメイン名になっている必要があります
```

ドメインが設定されていない場合は設定します：

```bash
# CentOS系の場合
sudo vi /etc/httpd/conf/httpd.conf

# Ubuntu系の場合
sudo vi /etc/apache2/sites-available/000-default.conf
```

以下を追加または修正：
```apache
ServerName your-domain.jp
```

---

### 6. SSL証明書の取得と設定（自動）

**Certbotが自動でApacheの設定も行ってくれます：**

```bash
sudo certbot --apache -d your-domain.jp
```

実行すると以下の質問が表示されます：

1. **メールアドレスの入力** → 証明書の期限切れ通知用
2. **利用規約に同意** → `Y` を入力
3. **メールアドレスの共有** → `N` でOK
4. **HTTPからHTTPSへのリダイレクト** → `2`（リダイレクトする）を推奨

```
Please choose whether or not to redirect HTTP traffic to HTTPS, removing HTTP access.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
1: No redirect - Make no further changes to the webserver configuration.
2: Redirect - Make all requests redirect to secure HTTPS access.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Select the appropriate number [1-2] then [enter]: 2
```

成功すると以下のメッセージが表示されます：
```
Congratulations! You have successfully enabled https://your-domain.jp
```

---

### 7. Apacheを再起動

```bash
# CentOS系
sudo systemctl restart httpd

# Ubuntu系
sudo systemctl restart apache2
```

---

### 8. SSL化の確認

ブラウザで以下にアクセスして確認：

```
https://your-domain.jp
```

- 鍵マーク🔒が表示されればSSL化成功
- irohaboardが正常に表示されることを確認

---

### 9. 証明書の自動更新設定

Let's Encryptの証明書は**90日で期限切れ**になります。自動更新を設定しましょう。

#### 更新テスト

```bash
sudo certbot renew --dry-run
```

「Congratulations, all renewals succeeded」と表示されればOK。

#### 自動更新のcron設定

Certbotは自動でcronまたはsystemd timerを設定しますが、念のため確認：

```bash
# cronを確認
cat /etc/cron.d/certbot

# または systemd timerを確認
sudo systemctl list-timers | grep certbot
```

設定されていない場合は手動で追加：

```bash
sudo crontab -e
```

以下を追加（毎日午前3時に更新チェック）：
```cron
0 3 * * * /usr/bin/certbot renew --quiet
```

---

## トラブルシューティング

### エラー: ドメインの認証に失敗する

```
Challenge failed for domain your-domain.jp
```

**原因と対処：**
- DNSの設定が反映されていない → `nslookup your-domain.jp` で確認、反映まで待つ
- 80番ポートが開いていない → ファイアウォール設定を確認
- Apacheが起動していない → `sudo systemctl status httpd` で確認

---

### エラー: mod_ssl がインストールされていない

```bash
# CentOS系
sudo yum install -y mod_ssl

# Ubuntu系
sudo a2enmod ssl
sudo systemctl restart apache2
```

---

### irohaboardで混在コンテンツ警告が出る

SSL化後、画像やCSSが`http://`で読み込まれていると警告が出ます。

#### irohaboardの設定変更

`app/Config/core.php` または管理画面でベースURLを変更：

```php
// httpをhttpsに変更
Configure::write('App.fullBaseUrl', 'https://your-domain.jp');
```

または `.htaccess` で強制的にHTTPSに書き換え：

```apache
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
</IfModule>
```

---

### データベース接続エラー

SSL化そのものはDBに影響しませんが、もしエラーが出る場合は：

```bash
# Apacheのエラーログを確認
sudo tail -f /var/log/httpd/error_log
# または
sudo tail -f /var/log/apache2/error.log
```

---

## 確認チェックリスト

- [ ] `https://your-domain.jp` にアクセスできる
- [ ] ブラウザに鍵マーク🔒が表示される
- [ ] irohaboardにログインできる
- [ ] 画像やCSSが正常に表示される（混在コンテンツ警告がない）
- [ ] `http://your-domain.jp` にアクセスすると自動でHTTPSにリダイレクトされる
- [ ] `sudo certbot renew --dry-run` が成功する

---

## SSL証明書の確認コマンド

```bash
# 証明書の有効期限を確認
sudo certbot certificates

# 出力例：
# Certificate Name: your-domain.jp
# Expiry Date: 2025-03-27 (VALID: 89 days)
```

---

## 参考：手動でApacheのSSL設定をする場合

Certbotの自動設定がうまくいかない場合の手動設定：

```bash
# SSL設定ファイルを編集（CentOS系）
sudo vi /etc/httpd/conf.d/ssl.conf
```

```apache
<VirtualHost *:443>
    ServerName your-domain.jp
    DocumentRoot /var/www/html/irohaboard

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/your-domain.jp/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/your-domain.jp/privkey.pem

    <Directory /var/www/html/irohaboard>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
```

---

## お問い合わせ

作業中に問題が発生した場合は、医療情報部までご連絡ください。

- 内線：XXXX
- メール：xxxxx@example.hospital.jp

---

*作成日：2024年12月*
