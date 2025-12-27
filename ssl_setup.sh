#!/bin/bash

#===============================================================================
# さくらVPS irohaboard SSL化スクリプト
#
# 使用方法:
#   chmod +x ssl_setup.sh
#   sudo ./ssl_setup.sh
#
# 注意: 必ずroot権限またはsudo権限で実行してください
#===============================================================================

set -e  # エラー時に停止

#-------------------------------------------------------------------------------
# 色の定義
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# 関数定義
#-------------------------------------------------------------------------------

# メッセージ表示関数
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

# 確認プロンプト
confirm() {
    read -p "$1 [y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# OSの検出
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="CentOS"
        VER=$(cat /etc/redhat-release | sed 's/.*release \([0-9]*\).*/\1/')
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi
}

# Webサーバーの検出
detect_webserver() {
    if systemctl is-active --quiet httpd 2>/dev/null; then
        WEBSERVER="httpd"
        WEBSERVER_NAME="Apache (httpd)"
    elif systemctl is-active --quiet apache2 2>/dev/null; then
        WEBSERVER="apache2"
        WEBSERVER_NAME="Apache (apache2)"
    elif systemctl is-active --quiet nginx 2>/dev/null; then
        WEBSERVER="nginx"
        WEBSERVER_NAME="Nginx"
    else
        WEBSERVER="unknown"
        WEBSERVER_NAME="不明"
    fi
}

# パッケージマネージャーの検出
detect_package_manager() {
    if command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    elif command -v apt &> /dev/null; then
        PKG_MANAGER="apt"
    else
        PKG_MANAGER="unknown"
    fi
}

#-------------------------------------------------------------------------------
# メイン処理
#-------------------------------------------------------------------------------

print_header "さくらVPS SSL化スクリプト"

# root権限チェック
if [ "$EUID" -ne 0 ]; then
    print_error "このスクリプトはroot権限で実行してください"
    echo "使用方法: sudo ./ssl_setup.sh"
    exit 1
fi

print_success "root権限で実行中"

#-------------------------------------------------------------------------------
# Step 0: バックアップの実行
#-------------------------------------------------------------------------------
print_header "Step 0: バックアップの確認"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_SCRIPT="${SCRIPT_DIR}/backup_server.sh"
BACKUP_BASE_DIR="/root/ssl_backup"

echo "SSL化作業の前に、サーバーのバックアップを取得することを強く推奨します。"
echo ""

# 既存のバックアップを確認
if [ -d "$BACKUP_BASE_DIR" ] && [ -L "${BACKUP_BASE_DIR}/latest" ]; then
    LATEST_BACKUP=$(readlink -f "${BACKUP_BASE_DIR}/latest")
    BACKUP_DATE=$(basename "$LATEST_BACKUP")
    print_info "最新のバックアップ: $BACKUP_DATE"
    echo ""

    if confirm "既存のバックアップを使用しますか？（Nで新規バックアップ作成）"; then
        print_success "既存のバックアップを使用します: $LATEST_BACKUP"
        BACKUP_COMPLETED=true
    else
        BACKUP_COMPLETED=false
    fi
else
    print_warning "バックアップが見つかりません"
    BACKUP_COMPLETED=false
fi

# 新規バックアップの実行
if [ "$BACKUP_COMPLETED" != "true" ]; then
    if [ -f "$BACKUP_SCRIPT" ]; then
        if confirm "今すぐバックアップを実行しますか？"; then
            print_info "バックアップスクリプトを実行します..."
            echo ""
            bash "$BACKUP_SCRIPT"
            BACKUP_RESULT=$?

            if [ $BACKUP_RESULT -eq 0 ]; then
                print_success "バックアップ完了"
                BACKUP_COMPLETED=true
            else
                print_error "バックアップに失敗しました"
                if ! confirm "バックアップなしで続行しますか？（非推奨）"; then
                    echo "中止しました。バックアップの問題を解決してから再実行してください。"
                    exit 1
                fi
            fi
        else
            print_warning "バックアップをスキップしました"
            if ! confirm "バックアップなしで続行しますか？（非推奨）"; then
                echo "中止しました"
                exit 0
            fi
        fi
    else
        print_warning "バックアップスクリプトが見つかりません: $BACKUP_SCRIPT"
        echo ""
        echo "バックアップスクリプトを同じディレクトリに配置してください。"
        echo "または、手動でバックアップを取得してください。"
        echo ""
        if ! confirm "バックアップなしで続行しますか？（非推奨）"; then
            echo "中止しました"
            exit 0
        fi
    fi
fi

echo ""
print_info "問題が発生した場合は、以下のコマンドで復元できます："
echo "  sudo ./restore_server.sh"
echo ""

#-------------------------------------------------------------------------------
# Step 1: 環境確認
#-------------------------------------------------------------------------------
print_header "Step 1: 環境確認"

# OS検出
detect_os
print_info "OS: $OS $VER"

# パッケージマネージャー検出
detect_package_manager
print_info "パッケージマネージャー: $PKG_MANAGER"

# Webサーバー検出
detect_webserver
print_info "Webサーバー: $WEBSERVER_NAME"

if [ "$WEBSERVER" = "unknown" ]; then
    print_warning "Webサーバーが検出できませんでした"
    echo "Apache または Nginx が起動しているか確認してください"
    if ! confirm "続行しますか？"; then
        exit 1
    fi
fi

if [ "$WEBSERVER" = "nginx" ]; then
    print_error "このスクリプトはApache用です。Nginx用のスクリプトは別途必要です。"
    exit 1
fi

#-------------------------------------------------------------------------------
# Step 2: ドメイン名の入力
#-------------------------------------------------------------------------------
print_header "Step 2: ドメイン名の設定"

echo "SSL化するドメイン名を入力してください"
echo "例: training.example.jp"
echo ""
read -p "ドメイン名: " DOMAIN

if [ -z "$DOMAIN" ]; then
    print_error "ドメイン名が入力されていません"
    exit 1
fi

# ドメイン形式の簡易チェック
if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
    print_warning "ドメイン形式が正しくない可能性があります: $DOMAIN"
    if ! confirm "このドメインで続行しますか？"; then
        exit 1
    fi
fi

print_success "ドメイン: $DOMAIN"

# DNS確認
print_info "DNSの確認中..."
if command -v nslookup &> /dev/null; then
    DNS_RESULT=$(nslookup "$DOMAIN" 2>/dev/null | grep -A1 "Name:" | tail -1 || echo "")
    if [ -n "$DNS_RESULT" ]; then
        print_success "DNS解決: $DNS_RESULT"
    else
        print_warning "DNSの解決に失敗しました。DNSが正しく設定されているか確認してください"
        if ! confirm "続行しますか？"; then
            exit 1
        fi
    fi
elif command -v host &> /dev/null; then
    if host "$DOMAIN" &> /dev/null; then
        print_success "DNS解決: OK"
    else
        print_warning "DNSの解決に失敗しました"
        if ! confirm "続行しますか？"; then
            exit 1
        fi
    fi
fi

#-------------------------------------------------------------------------------
# Step 3: メールアドレスの入力
#-------------------------------------------------------------------------------
print_header "Step 3: 連絡先メールアドレス"

echo "Let's Encryptからの通知を受け取るメールアドレスを入力してください"
echo "（証明書の期限切れ警告などが届きます）"
echo ""
read -p "メールアドレス: " EMAIL

if [ -z "$EMAIL" ]; then
    print_error "メールアドレスが入力されていません"
    exit 1
fi

print_success "メールアドレス: $EMAIL"

#-------------------------------------------------------------------------------
# Step 4: 設定確認
#-------------------------------------------------------------------------------
print_header "Step 4: 設定確認"

echo "以下の設定でSSL化を行います："
echo ""
echo "  OS:              $OS $VER"
echo "  Webサーバー:     $WEBSERVER_NAME"
echo "  ドメイン:        $DOMAIN"
echo "  メールアドレス:  $EMAIL"
echo ""

if ! confirm "この設定で続行しますか？"; then
    echo "キャンセルしました"
    exit 0
fi

#-------------------------------------------------------------------------------
# Step 5: 必要なパッケージのインストール
#-------------------------------------------------------------------------------
print_header "Step 5: Certbotのインストール"

# Certbotがインストール済みか確認
if command -v certbot &> /dev/null; then
    print_success "Certbotは既にインストールされています"
    certbot --version
else
    print_info "Certbotをインストールします..."

    case "$PKG_MANAGER" in
        dnf)
            dnf install -y epel-release
            dnf install -y certbot python3-certbot-apache
            ;;
        yum)
            yum install -y epel-release
            yum install -y certbot python2-certbot-apache || yum install -y certbot python3-certbot-apache
            ;;
        apt)
            apt update
            apt install -y certbot python3-certbot-apache
            ;;
        *)
            print_error "サポートされていないパッケージマネージャーです"
            exit 1
            ;;
    esac

    if command -v certbot &> /dev/null; then
        print_success "Certbotのインストール完了"
    else
        print_error "Certbotのインストールに失敗しました"
        exit 1
    fi
fi

#-------------------------------------------------------------------------------
# Step 6: mod_ssl のインストール確認（Apache用）
#-------------------------------------------------------------------------------
print_header "Step 6: mod_sslの確認"

if [ "$PKG_MANAGER" = "apt" ]; then
    # Ubuntu/Debian
    if ! apache2ctl -M 2>/dev/null | grep -q ssl_module; then
        print_info "mod_sslを有効化します..."
        a2enmod ssl
        print_success "mod_ssl有効化完了"
    else
        print_success "mod_sslは既に有効です"
    fi
else
    # CentOS/RHEL系
    if ! httpd -M 2>/dev/null | grep -q ssl_module; then
        print_info "mod_sslをインストールします..."
        $PKG_MANAGER install -y mod_ssl
        print_success "mod_sslインストール完了"
    else
        print_success "mod_sslは既にインストールされています"
    fi
fi

#-------------------------------------------------------------------------------
# Step 7: ファイアウォール設定
#-------------------------------------------------------------------------------
print_header "Step 7: ファイアウォール設定"

# firewalld の確認
if systemctl is-active --quiet firewalld 2>/dev/null; then
    print_info "firewalldが動作しています"

    # HTTPS許可確認
    if firewall-cmd --list-services | grep -q https; then
        print_success "HTTPSは既に許可されています"
    else
        print_info "HTTPSを許可します..."
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --reload
        print_success "ファイアウォール設定完了"
    fi

# ufw の確認
elif command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    print_info "ufwが動作しています"

    if ufw status | grep -q "443"; then
        print_success "443ポートは既に許可されています"
    else
        print_info "443ポートを許可します..."
        ufw allow 80/tcp
        ufw allow 443/tcp
        print_success "ファイアウォール設定完了"
    fi
else
    print_warning "ファイアウォールが検出されませんでした"
    print_info "さくらVPSのパケットフィルターで443ポートが許可されているか確認してください"
fi

#-------------------------------------------------------------------------------
# Step 8: SSL証明書の取得
#-------------------------------------------------------------------------------
print_header "Step 8: SSL証明書の取得"

echo ""
print_warning "これからLet's Encryptに接続して証明書を取得します"
print_warning "ドメインの認証のため、外部からサーバーへのアクセスが行われます"
echo ""

if ! confirm "証明書の取得を開始しますか？"; then
    echo "キャンセルしました"
    exit 0
fi

# Apache用のCertbot実行
print_info "Certbotを実行中..."

if [ "$WEBSERVER" = "httpd" ] || [ "$WEBSERVER" = "apache2" ]; then
    certbot --apache \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --domains "$DOMAIN" \
        --redirect

    CERTBOT_RESULT=$?
else
    print_error "サポートされていないWebサーバーです"
    exit 1
fi

if [ $CERTBOT_RESULT -eq 0 ]; then
    print_success "SSL証明書の取得・設定が完了しました！"
else
    print_error "SSL証明書の取得に失敗しました"
    echo ""
    echo "考えられる原因："
    echo "  - ドメインのDNSがこのサーバーに向いていない"
    echo "  - 80番ポートがブロックされている"
    echo "  - さくらVPSのパケットフィルターで制限されている"
    echo ""
    echo "ログを確認してください: /var/log/letsencrypt/letsencrypt.log"
    exit 1
fi

#-------------------------------------------------------------------------------
# Step 9: Webサーバー再起動
#-------------------------------------------------------------------------------
print_header "Step 9: Webサーバー再起動"

print_info "$WEBSERVER_NAME を再起動します..."

if [ "$WEBSERVER" = "httpd" ]; then
    systemctl restart httpd
elif [ "$WEBSERVER" = "apache2" ]; then
    systemctl restart apache2
fi

if systemctl is-active --quiet "$WEBSERVER"; then
    print_success "$WEBSERVER_NAME の再起動完了"
else
    print_error "$WEBSERVER_NAME の起動に失敗しました"
    echo "ログを確認してください"
    exit 1
fi

#-------------------------------------------------------------------------------
# Step 10: 自動更新の確認
#-------------------------------------------------------------------------------
print_header "Step 10: 自動更新の確認"

print_info "証明書の自動更新をテストします..."

certbot renew --dry-run

if [ $? -eq 0 ]; then
    print_success "自動更新のテスト成功"
else
    print_warning "自動更新のテストに問題がありました"
    print_info "手動で 'certbot renew' を定期実行する設定が必要かもしれません"
fi

#-------------------------------------------------------------------------------
# 完了
#-------------------------------------------------------------------------------
print_header "SSL化完了！"

echo ""
print_success "SSL証明書の設定が完了しました"
echo ""
echo "確認事項："
echo "  1. ブラウザで https://$DOMAIN にアクセス"
echo "  2. 鍵マーク🔒が表示されることを確認"
echo "  3. irohaboardが正常に動作することを確認"
echo ""
echo "証明書の情報："
certbot certificates 2>/dev/null | grep -A3 "Certificate Name: $DOMAIN" || echo "  certbot certificates コマンドで確認できます"
echo ""
print_info "証明書は90日で期限切れになりますが、自動更新が設定されています"
echo ""

#-------------------------------------------------------------------------------
# 追加設定の案内
#-------------------------------------------------------------------------------
print_header "追加設定（必要に応じて）"

echo "irohaboardで混在コンテンツ警告が出る場合は、"
echo "以下のファイルでベースURLをhttpsに変更してください："
echo ""
echo "  app/Config/core.php"
echo "  Configure::write('App.fullBaseUrl', 'https://$DOMAIN');"
echo ""

print_success "スクリプト完了"
