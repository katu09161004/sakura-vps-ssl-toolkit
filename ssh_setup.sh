#!/bin/bash

#===============================================================================
# SSH公開鍵認証 設定スクリプト
#
# パスワード認証から公開鍵認証への切り替えを自動化します
#
# 使用方法:
#   chmod +x ssh_setup.sh
#   sudo ./ssh_setup.sh
#
# 注意:
#   - 事前にローカルPCで鍵ペアを生成し、公開鍵を登録しておくこと
#   - 公開鍵認証でログインできることを確認してから実行すること
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# 色の定義
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#-------------------------------------------------------------------------------
# 関数定義
#-------------------------------------------------------------------------------
print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

confirm() {
    read -p "$1 [y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

#-------------------------------------------------------------------------------
# メイン処理
#-------------------------------------------------------------------------------

print_header "SSH公開鍵認証 設定スクリプト"

# root権限チェック
if [ "$EUID" -ne 0 ]; then
    print_error "このスクリプトはroot権限で実行してください"
    echo "使用方法: sudo ./ssh_setup.sh"
    exit 1
fi

print_success "root権限で実行中"

#-------------------------------------------------------------------------------
# Step 1: 事前確認
#-------------------------------------------------------------------------------
print_header "Step 1: 事前確認"

echo "このスクリプトを実行する前に、以下を確認してください："
echo ""
echo "  1. ローカルPCで鍵ペア（秘密鍵・公開鍵）を生成済み"
echo "  2. 公開鍵をサーバーの ~/.ssh/authorized_keys に登録済み"
echo "  3. 公開鍵認証でSSHログインできることを確認済み"
echo ""
print_warning "公開鍵認証が動作しない状態でパスワード認証を無効化すると"
print_warning "サーバーにログインできなくなります！"
echo ""

if ! confirm "上記をすべて確認しましたか？"; then
    echo ""
    echo "まず以下の手順を実行してください："
    echo ""
    echo "【ローカルPCで鍵生成】"
    echo "  ssh-keygen -t ed25519 -C \"your-email@example.com\""
    echo ""
    echo "【公開鍵をサーバーに登録】"
    echo "  ssh-copy-id -i ~/.ssh/id_ed25519.pub ユーザー名@サーバーIP"
    echo ""
    echo "【公開鍵認証でログインを確認】"
    echo "  ssh ユーザー名@サーバーIP"
    echo ""
    exit 0
fi

#-------------------------------------------------------------------------------
# Step 2: 現在のSSH設定を確認
#-------------------------------------------------------------------------------
print_header "Step 2: 現在のSSH設定を確認"

SSHD_CONFIG="/etc/ssh/sshd_config"

if [ ! -f "$SSHD_CONFIG" ]; then
    print_error "sshd_configが見つかりません: $SSHD_CONFIG"
    exit 1
fi

print_info "現在の設定:"
echo ""
grep -E "^(PasswordAuthentication|PubkeyAuthentication|PermitRootLogin|ChallengeResponseAuthentication)" "$SSHD_CONFIG" 2>/dev/null || echo "  (明示的な設定なし - デフォルト値が使用されています)"
echo ""

# authorized_keysの確認
CURRENT_USER=$(logname 2>/dev/null || echo "$SUDO_USER")
AUTH_KEYS="/home/${CURRENT_USER}/.ssh/authorized_keys"

if [ -f "$AUTH_KEYS" ]; then
    KEY_COUNT=$(wc -l < "$AUTH_KEYS")
    print_success "authorized_keys: $KEY_COUNT 個の公開鍵が登録されています"
else
    print_warning "authorized_keys が見つかりません: $AUTH_KEYS"
    print_warning "公開鍵が登録されていない可能性があります"

    if ! confirm "続行しますか？（非推奨）"; then
        exit 1
    fi
fi

#-------------------------------------------------------------------------------
# Step 3: 設定のバックアップ
#-------------------------------------------------------------------------------
print_header "Step 3: 設定のバックアップ"

BACKUP_FILE="${SSHD_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
cp -p "$SSHD_CONFIG" "$BACKUP_FILE"
print_success "バックアップ作成: $BACKUP_FILE"

#-------------------------------------------------------------------------------
# Step 4: 変更内容の確認
#-------------------------------------------------------------------------------
print_header "Step 4: 変更内容の確認"

echo "以下の設定を変更します："
echo ""
echo "  PasswordAuthentication no        # パスワード認証を無効化"
echo "  ChallengeResponseAuthentication no  # チャレンジレスポンス認証を無効化"
echo "  PubkeyAuthentication yes         # 公開鍵認証を有効化"
echo "  PermitEmptyPasswords no          # 空パスワードを禁止"
echo ""

# rootログインについて確認
if grep -q "^PermitRootLogin yes" "$SSHD_CONFIG"; then
    print_warning "現在rootログインが許可されています"
    if confirm "rootログインも無効化しますか？（推奨）"; then
        DISABLE_ROOT_LOGIN=true
        echo "  PermitRootLogin no               # rootログインを禁止"
    else
        DISABLE_ROOT_LOGIN=false
    fi
else
    DISABLE_ROOT_LOGIN=false
fi

echo ""

if ! confirm "この設定で続行しますか？"; then
    echo "キャンセルしました"
    exit 0
fi

#-------------------------------------------------------------------------------
# Step 5: sshd_configを変更
#-------------------------------------------------------------------------------
print_header "Step 5: sshd_configを変更"

# PasswordAuthentication
if grep -q "^PasswordAuthentication" "$SSHD_CONFIG"; then
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
elif grep -q "^#PasswordAuthentication" "$SSHD_CONFIG"; then
    sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
else
    echo "PasswordAuthentication no" >> "$SSHD_CONFIG"
fi
print_success "PasswordAuthentication no"

# ChallengeResponseAuthentication
if grep -q "^ChallengeResponseAuthentication" "$SSHD_CONFIG"; then
    sed -i 's/^ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$SSHD_CONFIG"
elif grep -q "^#ChallengeResponseAuthentication" "$SSHD_CONFIG"; then
    sed -i 's/^#ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$SSHD_CONFIG"
else
    echo "ChallengeResponseAuthentication no" >> "$SSHD_CONFIG"
fi
print_success "ChallengeResponseAuthentication no"

# PubkeyAuthentication
if grep -q "^PubkeyAuthentication" "$SSHD_CONFIG"; then
    sed -i 's/^PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
elif grep -q "^#PubkeyAuthentication" "$SSHD_CONFIG"; then
    sed -i 's/^#PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
else
    echo "PubkeyAuthentication yes" >> "$SSHD_CONFIG"
fi
print_success "PubkeyAuthentication yes"

# PermitEmptyPasswords
if grep -q "^PermitEmptyPasswords" "$SSHD_CONFIG"; then
    sed -i 's/^PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$SSHD_CONFIG"
elif grep -q "^#PermitEmptyPasswords" "$SSHD_CONFIG"; then
    sed -i 's/^#PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$SSHD_CONFIG"
else
    echo "PermitEmptyPasswords no" >> "$SSHD_CONFIG"
fi
print_success "PermitEmptyPasswords no"

# PermitRootLogin（オプション）
if [ "$DISABLE_ROOT_LOGIN" = true ]; then
    if grep -q "^PermitRootLogin" "$SSHD_CONFIG"; then
        sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
    elif grep -q "^#PermitRootLogin" "$SSHD_CONFIG"; then
        sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
    else
        echo "PermitRootLogin no" >> "$SSHD_CONFIG"
    fi
    print_success "PermitRootLogin no"
fi

#-------------------------------------------------------------------------------
# Step 6: 設定ファイルの文法チェック
#-------------------------------------------------------------------------------
print_header "Step 6: 設定ファイルの文法チェック"

if sshd -t 2>&1; then
    print_success "設定ファイルの文法チェック: OK"
else
    print_error "設定ファイルにエラーがあります"
    echo ""
    echo "バックアップから復元します..."
    cp -p "$BACKUP_FILE" "$SSHD_CONFIG"
    print_success "復元完了: $BACKUP_FILE"
    exit 1
fi

#-------------------------------------------------------------------------------
# Step 7: SSHサービスの再起動
#-------------------------------------------------------------------------------
print_header "Step 7: SSHサービスの再起動"

print_warning "現在のSSHセッションは維持されます"
print_warning "必ず別のターミナルで接続確認を行ってください"
echo ""

if ! confirm "SSHサービスを再起動しますか？"; then
    echo "キャンセルしました"
    echo "手動で再起動してください: sudo systemctl restart sshd"
    exit 0
fi

# SSHサービスの再起動
if systemctl is-active --quiet sshd 2>/dev/null; then
    systemctl restart sshd
    SSH_SERVICE="sshd"
elif systemctl is-active --quiet ssh 2>/dev/null; then
    systemctl restart ssh
    SSH_SERVICE="ssh"
else
    print_error "SSHサービスが見つかりません"
    exit 1
fi

if systemctl is-active --quiet "$SSH_SERVICE"; then
    print_success "SSHサービス ($SSH_SERVICE) の再起動完了"
else
    print_error "SSHサービスの起動に失敗しました"
    echo "バックアップから復元します..."
    cp -p "$BACKUP_FILE" "$SSHD_CONFIG"
    systemctl restart "$SSH_SERVICE"
    exit 1
fi

#-------------------------------------------------------------------------------
# Step 8: 完了
#-------------------------------------------------------------------------------
print_header "設定完了"

echo ""
print_success "SSH公開鍵認証の設定が完了しました"
echo ""
echo "変更後の設定:"
echo ""
grep -E "^(PasswordAuthentication|PubkeyAuthentication|PermitRootLogin|ChallengeResponseAuthentication|PermitEmptyPasswords)" "$SSHD_CONFIG"
echo ""

print_warning "重要: 必ず別のターミナルで接続確認を行ってください"
echo ""
echo "確認コマンド（新しいターミナルで実行）："
echo ""
echo "  # 公開鍵認証でログイン"
echo "  ssh ユーザー名@サーバーIP"
echo ""
echo "  # パスワード認証が無効か確認"
echo "  ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no ユーザー名@サーバーIP"
echo "  # → 'Permission denied (publickey).' と表示されれば成功"
echo ""

print_info "バックアップファイル: $BACKUP_FILE"
echo ""
echo "問題が発生した場合は、VNCコンソールからログインして"
echo "バックアップから復元してください："
echo ""
echo "  sudo cp $BACKUP_FILE $SSHD_CONFIG"
echo "  sudo systemctl restart $SSH_SERVICE"
echo ""

print_success "スクリプト完了"
