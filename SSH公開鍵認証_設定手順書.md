# SSH公開鍵認証 設定手順書

## 概要

パスワード認証から公開鍵認証に切り替えることで、SSHのセキュリティを強化します。

### パスワード認証 vs 公開鍵認証

| 項目 | パスワード認証 | 公開鍵認証 |
|------|--------------|-----------|
| セキュリティ | 弱い（総当たり攻撃に脆弱） | 強い（秘密鍵がないとログイン不可） |
| 利便性 | 毎回パスワード入力 | パスフレーズ or 入力なしでログイン可能 |
| 管理 | パスワード漏洩リスク | 秘密鍵の厳重管理が必要 |

---

## 前提条件

- サーバーにSSHでログインできる（現在のパスワード認証で）
- ローカルPC（Mac/Windows/Linux）で作業可能

---

## 手順概要

```
1. ローカルPCで鍵ペア（秘密鍵・公開鍵）を生成
2. 公開鍵をサーバーに登録
3. 公開鍵認証でログインできることを確認
4. パスワード認証を無効化
5. 設定の確認
```

---

## 1. 鍵ペアの生成（ローカルPC）

### Mac / Linux の場合

```bash
# Ed25519形式で鍵を生成（推奨）
ssh-keygen -t ed25519 -C "your-email@example.com"

# または RSA 4096bit で生成
ssh-keygen -t rsa -b 4096 -C "your-email@example.com"
```

**対話プロンプト：**

```
Generating public/private ed25519 key pair.
Enter file in which to save the key (/Users/username/.ssh/id_ed25519):
# → Enterで既定の場所に保存（またはパスを指定）

Enter passphrase (empty for no passphrase):
# → パスフレーズを入力（推奨）または空Enter

Enter same passphrase again:
# → 同じパスフレーズを再入力
```

**生成されるファイル：**

| ファイル | 説明 | 扱い |
|---------|------|------|
| `~/.ssh/id_ed25519` | 秘密鍵 | **絶対に漏洩させない** |
| `~/.ssh/id_ed25519.pub` | 公開鍵 | サーバーに登録する |

### Windows（PowerShell）の場合

```powershell
# OpenSSHがインストールされていることを確認
ssh-keygen -t ed25519 -C "your-email@example.com"
```

**生成先：** `C:\Users\ユーザー名\.ssh\`

### Windows（Git Bash）の場合

```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
```

---

## 2. 公開鍵をサーバーに登録

### 方法A: ssh-copy-id を使用（推奨）

```bash
# Mac / Linux
ssh-copy-id -i ~/.ssh/id_ed25519.pub ユーザー名@サーバーIP

# パスワードを聞かれるので入力
```

成功すると以下のメッセージが表示されます：
```
Number of key(s) added: 1
Now try logging into the machine, with: "ssh 'ユーザー名@サーバーIP'"
```

### 方法B: 手動で登録

**ローカルPCで公開鍵の内容を表示：**
```bash
cat ~/.ssh/id_ed25519.pub
```

出力例：
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... your-email@example.com
```

**サーバーにSSH接続（パスワード認証）：**
```bash
ssh ユーザー名@サーバーIP
```

**サーバー側で公開鍵を登録：**
```bash
# .sshディレクトリを作成（なければ）
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# authorized_keysファイルに公開鍵を追加
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... your-email@example.com" >> ~/.ssh/authorized_keys

# パーミッションを設定
chmod 600 ~/.ssh/authorized_keys
```

---

## 3. 公開鍵認証でログインを確認

**新しいターミナルを開いて確認：**
```bash
ssh ユーザー名@サーバーIP
```

- パスフレーズを設定した場合 → パスフレーズを入力
- パスフレーズなしの場合 → そのままログイン

**パスワードを聞かれずにログインできれば成功です。**

> **重要：** この時点ではまだパスワード認証を無効化しないでください。
> 公開鍵認証が確実に動作することを確認してから次に進みます。

---

## 4. パスワード認証を無効化（サーバー側）

### 4.1 現在の設定をバックアップ

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d)
```

### 4.2 sshd_configを編集

```bash
sudo vi /etc/ssh/sshd_config
```

**以下の設定を変更：**

```bash
# パスワード認証を無効化
PasswordAuthentication no

# チャレンジレスポンス認証を無効化
ChallengeResponseAuthentication no

# 公開鍵認証を有効化（通常はデフォルトでyes）
PubkeyAuthentication yes

# rootログインを禁止（推奨）
PermitRootLogin no

# 空パスワードを禁止
PermitEmptyPasswords no
```

**viでの編集方法：**
1. `/PasswordAuthentication` で検索
2. `i` で編集モードに入る
3. `yes` を `no` に変更
4. `Esc` で編集モード終了
5. `:wq` で保存して終了

### 4.3 設定ファイルの文法チェック

```bash
sudo sshd -t
```

エラーが表示されなければOK。

### 4.4 SSHサービスを再起動

```bash
# CentOS / Rocky Linux / AlmaLinux
sudo systemctl restart sshd

# Ubuntu / Debian
sudo systemctl restart ssh
```

---

## 5. 設定の確認

### 5.1 別のターミナルで公開鍵認証を確認

**重要：現在のSSHセッションは閉じないでください。**

新しいターミナルで：
```bash
ssh ユーザー名@サーバーIP
```

公開鍵認証でログインできることを確認。

### 5.2 パスワード認証が無効になっているか確認

```bash
# -o オプションでパスワード認証を試みる
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no ユーザー名@サーバーIP
```

以下のようなメッセージが出れば成功：
```
Permission denied (publickey).
```

---

## トラブルシューティング

### 公開鍵認証でログインできない

**1. パーミッションを確認：**
```bash
# サーバー側
ls -la ~/.ssh/
# 期待値：
# drwx------ .ssh
# -rw------- authorized_keys
```

**修正：**
```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

**2. authorized_keysの内容を確認：**
```bash
cat ~/.ssh/authorized_keys
```
公開鍵が正しく登録されているか確認。

**3. SELinuxが原因の場合（CentOS/RHEL）：**
```bash
restorecon -Rv ~/.ssh
```

**4. sshdログを確認：**
```bash
sudo tail -f /var/log/secure      # CentOS/RHEL
sudo tail -f /var/log/auth.log    # Ubuntu/Debian
```

---

### ロックアウトされた場合

パスワード認証を無効化した後に公開鍵でログインできなくなった場合：

**さくらVPSの場合：**
1. さくらVPSコントロールパネルにログイン
2. 対象サーバーを選択
3. 「コンソール」→「VNCコンソール」を開く
4. サーバーに直接ログイン
5. sshd_configを修正してパスワード認証を再度有効化

```bash
sudo vi /etc/ssh/sshd_config
# PasswordAuthentication yes に戻す
sudo systemctl restart sshd
```

---

## 複数PCからアクセスする場合

各PCで鍵ペアを生成し、公開鍵をサーバーの `authorized_keys` に追加します。

```bash
# サーバー側で複数の公開鍵を登録
cat >> ~/.ssh/authorized_keys << 'EOF'
ssh-ed25519 AAAAC3... PC1の公開鍵
ssh-ed25519 AAAAC3... PC2の公開鍵
ssh-ed25519 AAAAC3... PC3の公開鍵
EOF
```

---

## SSH接続の簡略化（~/.ssh/config）

**ローカルPCで設定：**

```bash
vi ~/.ssh/config
```

```
Host myserver
    HostName サーバーIPまたはドメイン
    User ユーザー名
    IdentityFile ~/.ssh/id_ed25519
    Port 22
```

**パーミッション設定：**
```bash
chmod 600 ~/.ssh/config
```

**使用方法：**
```bash
# 長いコマンドの代わりに
ssh myserver
```

---

## セキュリティ強化（追加設定）

### SSHポート番号の変更

```bash
sudo vi /etc/ssh/sshd_config
```

```
Port 10022  # 任意のポート番号（1024〜65535）
```

**ファイアウォール設定も変更：**
```bash
# CentOS/RHEL
sudo firewall-cmd --permanent --add-port=10022/tcp
sudo firewall-cmd --permanent --remove-service=ssh
sudo firewall-cmd --reload

# Ubuntu
sudo ufw allow 10022/tcp
sudo ufw delete allow ssh
```

**さくらVPSのパケットフィルターも変更を忘れずに。**

### ログイン試行回数の制限

```bash
# sshd_config
MaxAuthTries 3
```

### 接続元IPの制限

```bash
# /etc/hosts.allow
sshd: 192.168.1.0/24  # 許可するIPまたはネットワーク

# /etc/hosts.deny
sshd: ALL  # その他は拒否
```

---

## 確認チェックリスト

- [ ] ローカルPCで鍵ペアを生成した
- [ ] 公開鍵をサーバーに登録した
- [ ] 公開鍵認証でSSHログインできる
- [ ] パスワード認証を無効化した
- [ ] パスワードでのログインが拒否される
- [ ] 秘密鍵を安全な場所に保管した
- [ ] （任意）SSHポート番号を変更した

---

## 参考：鍵の種類

| 種類 | 説明 | 推奨度 |
|------|------|-------|
| Ed25519 | 最新・高速・セキュア | ★★★ 推奨 |
| RSA (4096bit) | 広く互換性あり | ★★ 従来環境向け |
| ECDSA | 楕円曲線暗号 | ★ 一部環境で問題あり |
| DSA | 古い形式 | × 非推奨 |

---

## お問い合わせ

作業中に問題が発生した場合は、医療情報部までご連絡ください。

- 内線：XXXX
- メール：xxxxx@example.hospital.jp

---

*作成日：2024年12月*
