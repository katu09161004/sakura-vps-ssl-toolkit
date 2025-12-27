#!/bin/bash

#===============================================================================
# サーバーバックアップスクリプト
#
# SSL化作業前に実行し、Apache設定・irohaboard・データベースをバックアップします
#
# 使用方法:
#   chmod +x backup_server.sh
#   sudo ./backup_server.sh
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# 設定
#-------------------------------------------------------------------------------
BACKUP_BASE_DIR="/root/ssl_backup"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="${BACKUP_BASE_DIR}/${TIMESTAMP}"

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

# バックアップサイズを人間が読める形式で表示
human_readable_size() {
    local size=$1
    if [ $size -ge 1073741824 ]; then
        echo "$(echo "scale=2; $size/1073741824" | bc) GB"
    elif [ $size -ge 1048576 ]; then
        echo "$(echo "scale=2; $size/1048576" | bc) MB"
    elif [ $size -ge 1024 ]; then
        echo "$(echo "scale=2; $size/1024" | bc) KB"
    else
        echo "$size bytes"
    fi
}

#-------------------------------------------------------------------------------
# メイン処理
#-------------------------------------------------------------------------------

print_header "サーバーバックアップスクリプト"

# root権限チェック
if [ "$EUID" -ne 0 ]; then
    print_error "このスクリプトはroot権限で実行してください"
    echo "使用方法: sudo ./backup_server.sh"
    exit 1
fi

print_success "root権限で実行中"

#-------------------------------------------------------------------------------
# Step 1: バックアップディレクトリ作成
#-------------------------------------------------------------------------------
print_header "Step 1: バックアップディレクトリ作成"

mkdir -p "$BACKUP_DIR"
print_success "バックアップディレクトリ: $BACKUP_DIR"

# バックアップ情報ファイル作成
cat > "${BACKUP_DIR}/backup_info.txt" << EOF
========================================
バックアップ情報
========================================
作成日時: $(date)
ホスト名: $(hostname)
OS: $(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | cut -d'"' -f2 || uname -a)
カーネル: $(uname -r)
========================================
EOF

print_success "バックアップ情報ファイル作成完了"

#-------------------------------------------------------------------------------
# Step 2: Apache設定のバックアップ
#-------------------------------------------------------------------------------
print_header "Step 2: Apache設定のバックアップ"

APACHE_BACKUP_DIR="${BACKUP_DIR}/apache"
mkdir -p "$APACHE_BACKUP_DIR"

# CentOS/RHEL系
if [ -d /etc/httpd ]; then
    print_info "/etc/httpd をバックアップ中..."
    cp -rp /etc/httpd "$APACHE_BACKUP_DIR/"
    print_success "Apache設定 (/etc/httpd) バックアップ完了"
fi

# Ubuntu/Debian系
if [ -d /etc/apache2 ]; then
    print_info "/etc/apache2 をバックアップ中..."
    cp -rp /etc/apache2 "$APACHE_BACKUP_DIR/"
    print_success "Apache設定 (/etc/apache2) バックアップ完了"
fi

# SSL関連設定（存在する場合）
if [ -d /etc/letsencrypt ]; then
    print_info "/etc/letsencrypt をバックアップ中..."
    cp -rp /etc/letsencrypt "$APACHE_BACKUP_DIR/"
    print_success "Let's Encrypt設定バックアップ完了"
fi

if [ -d /etc/ssl ]; then
    print_info "/etc/ssl をバックアップ中..."
    cp -rp /etc/ssl "$APACHE_BACKUP_DIR/"
    print_success "SSL証明書ディレクトリバックアップ完了"
fi

#-------------------------------------------------------------------------------
# Step 3: irohaboardのバックアップ
#-------------------------------------------------------------------------------
print_header "Step 3: irohaboardのバックアップ"

IROHA_BACKUP_DIR="${BACKUP_DIR}/irohaboard"
mkdir -p "$IROHA_BACKUP_DIR"

# irohaboardの一般的なインストール場所を検索
IROHA_PATHS=(
    "/var/www/html/irohaboard"
    "/var/www/irohaboard"
    "/var/www/html"
    "/home/*/public_html/irohaboard"
    "/home/*/www/irohaboard"
)

IROHA_FOUND=""
for path in "${IROHA_PATHS[@]}"; do
    # ワイルドカード展開
    for expanded_path in $path; do
        if [ -d "$expanded_path" ] && [ -f "$expanded_path/index.php" ]; then
            IROHA_FOUND="$expanded_path"
            break 2
        fi
    done
done

if [ -n "$IROHA_FOUND" ]; then
    print_info "irohaboardを検出: $IROHA_FOUND"
    print_info "バックアップ中...（時間がかかる場合があります）"

    # tarで圧縮バックアップ
    tar -czf "${IROHA_BACKUP_DIR}/irohaboard_files.tar.gz" -C "$(dirname "$IROHA_FOUND")" "$(basename "$IROHA_FOUND")"

    print_success "irohaboardファイルバックアップ完了"

    # パスを記録
    echo "$IROHA_FOUND" > "${IROHA_BACKUP_DIR}/original_path.txt"
else
    print_warning "irohaboardのインストール場所が見つかりませんでした"
    echo ""
    read -p "irohaboardのパスを入力してください（スキップする場合は空Enter）: " CUSTOM_IROHA_PATH

    if [ -n "$CUSTOM_IROHA_PATH" ] && [ -d "$CUSTOM_IROHA_PATH" ]; then
        print_info "$CUSTOM_IROHA_PATH をバックアップ中..."
        tar -czf "${IROHA_BACKUP_DIR}/irohaboard_files.tar.gz" -C "$(dirname "$CUSTOM_IROHA_PATH")" "$(basename "$CUSTOM_IROHA_PATH")"
        echo "$CUSTOM_IROHA_PATH" > "${IROHA_BACKUP_DIR}/original_path.txt"
        print_success "irohaboardファイルバックアップ完了"
        IROHA_FOUND="$CUSTOM_IROHA_PATH"
    else
        print_warning "irohaboardのバックアップをスキップしました"
    fi
fi

#-------------------------------------------------------------------------------
# Step 4: データベースのバックアップ
#-------------------------------------------------------------------------------
print_header "Step 4: データベースのバックアップ"

DB_BACKUP_DIR="${BACKUP_DIR}/database"
mkdir -p "$DB_BACKUP_DIR"

# MySQLの設定ファイルからDB情報を取得を試みる
DB_NAME=""
DB_USER=""
DB_PASS=""
DB_HOST="localhost"

# irohaboardのdatabase.phpから設定を読み取る
if [ -n "$IROHA_FOUND" ]; then
    DB_CONFIG_FILE="${IROHA_FOUND}/app/Config/database.php"

    if [ -f "$DB_CONFIG_FILE" ]; then
        print_info "データベース設定ファイルを検出: $DB_CONFIG_FILE"

        # 設定ファイルからDB情報を抽出（簡易パース）
        DB_NAME=$(grep -oP "'database'\s*=>\s*'\K[^']+" "$DB_CONFIG_FILE" 2>/dev/null | head -1 || echo "")
        DB_USER=$(grep -oP "'login'\s*=>\s*'\K[^']+" "$DB_CONFIG_FILE" 2>/dev/null | head -1 || echo "")
        DB_PASS=$(grep -oP "'password'\s*=>\s*'\K[^']+" "$DB_CONFIG_FILE" 2>/dev/null | head -1 || echo "")
        DB_HOST=$(grep -oP "'host'\s*=>\s*'\K[^']+" "$DB_CONFIG_FILE" 2>/dev/null | head -1 || echo "localhost")
    fi
fi

# DB情報が取得できなかった場合は手動入力
if [ -z "$DB_NAME" ]; then
    print_warning "データベース設定を自動検出できませんでした"
    echo ""
    echo "MySQLデータベースのバックアップを行います"
    echo "（スキップする場合は空Enterを押してください）"
    echo ""

    read -p "データベース名: " DB_NAME

    if [ -n "$DB_NAME" ]; then
        read -p "データベースユーザー名: " DB_USER
        read -sp "データベースパスワード: " DB_PASS
        echo ""
        read -p "データベースホスト [localhost]: " DB_HOST
        DB_HOST=${DB_HOST:-localhost}
    fi
fi

# データベースバックアップ実行
if [ -n "$DB_NAME" ] && [ -n "$DB_USER" ]; then
    print_info "データベース '$DB_NAME' をバックアップ中..."

    # mysqldumpでバックアップ
    if command -v mysqldump &> /dev/null; then
        if mysqldump -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "${DB_BACKUP_DIR}/${DB_NAME}.sql" 2>/dev/null; then
            # パスワードを含まない接続情報を保存
            cat > "${DB_BACKUP_DIR}/db_info.txt" << EOF
データベース名: $DB_NAME
ユーザー名: $DB_USER
ホスト: $DB_HOST
バックアップファイル: ${DB_NAME}.sql
EOF
            print_success "データベースバックアップ完了"

            # SQLファイルを圧縮
            gzip "${DB_BACKUP_DIR}/${DB_NAME}.sql"
            print_success "バックアップファイルを圧縮しました"
        else
            print_error "データベースバックアップに失敗しました"
            print_info "認証情報を確認してください"
        fi
    else
        print_error "mysqldumpコマンドが見つかりません"
    fi
else
    print_warning "データベースのバックアップをスキップしました"
fi

#-------------------------------------------------------------------------------
# Step 5: システム設定のバックアップ
#-------------------------------------------------------------------------------
print_header "Step 5: システム設定のバックアップ"

SYSTEM_BACKUP_DIR="${BACKUP_DIR}/system"
mkdir -p "$SYSTEM_BACKUP_DIR"

# ファイアウォール設定
if command -v firewall-cmd &> /dev/null; then
    print_info "firewalld設定をバックアップ中..."
    firewall-cmd --list-all > "${SYSTEM_BACKUP_DIR}/firewalld_config.txt" 2>/dev/null || true
    if [ -d /etc/firewalld ]; then
        cp -rp /etc/firewalld "${SYSTEM_BACKUP_DIR}/"
    fi
    print_success "firewalld設定バックアップ完了"
fi

if command -v ufw &> /dev/null; then
    print_info "ufw設定をバックアップ中..."
    ufw status verbose > "${SYSTEM_BACKUP_DIR}/ufw_status.txt" 2>/dev/null || true
    if [ -d /etc/ufw ]; then
        cp -rp /etc/ufw "${SYSTEM_BACKUP_DIR}/"
    fi
    print_success "ufw設定バックアップ完了"
fi

# hostsファイル
if [ -f /etc/hosts ]; then
    cp -p /etc/hosts "${SYSTEM_BACKUP_DIR}/"
    print_success "/etc/hosts バックアップ完了"
fi

# crontab
crontab -l > "${SYSTEM_BACKUP_DIR}/crontab_root.txt" 2>/dev/null || true
print_success "crontab バックアップ完了"

# 現在のサービス状態
systemctl list-units --type=service --state=running > "${SYSTEM_BACKUP_DIR}/running_services.txt" 2>/dev/null || true
print_success "サービス状態バックアップ完了"

#-------------------------------------------------------------------------------
# Step 6: バックアップの検証と完了
#-------------------------------------------------------------------------------
print_header "Step 6: バックアップ完了"

# バックアップサイズ計算
BACKUP_SIZE=$(du -sb "$BACKUP_DIR" | cut -f1)
BACKUP_SIZE_HUMAN=$(human_readable_size $BACKUP_SIZE)

# バックアップ内容一覧
echo ""
echo "バックアップ内容:"
echo "----------------------------------------"
ls -la "$BACKUP_DIR"
echo "----------------------------------------"
echo ""

# バックアップサマリー作成
cat >> "${BACKUP_DIR}/backup_info.txt" << EOF

バックアップ内容:
----------------------------------------
$(ls -la "$BACKUP_DIR")
----------------------------------------

バックアップサイズ: $BACKUP_SIZE_HUMAN

復元コマンド:
  sudo ./restore_server.sh $BACKUP_DIR

EOF

print_success "バックアップが完了しました！"
echo ""
echo "バックアップ場所: $BACKUP_DIR"
echo "バックアップサイズ: $BACKUP_SIZE_HUMAN"
echo ""

# 復元スクリプトのパスを表示
echo "復元する場合は以下のコマンドを実行してください:"
echo ""
echo "  sudo ./restore_server.sh $BACKUP_DIR"
echo ""

# シンボリックリンクで最新バックアップを示す
ln -sfn "$BACKUP_DIR" "${BACKUP_BASE_DIR}/latest"
print_info "最新バックアップへのリンク: ${BACKUP_BASE_DIR}/latest"

#-------------------------------------------------------------------------------
# バックアップ一覧表示
#-------------------------------------------------------------------------------
print_header "既存のバックアップ一覧"

echo "バックアップディレクトリ: $BACKUP_BASE_DIR"
echo ""

if [ -d "$BACKUP_BASE_DIR" ]; then
    ls -lt "$BACKUP_BASE_DIR" | grep -v "^total" | grep -v "latest" | head -10
fi

echo ""
print_success "バックアップスクリプト完了"
