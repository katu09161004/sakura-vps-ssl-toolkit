#!/bin/bash

#===============================================================================
# サーバー復元スクリプト
#
# SSL化作業後に問題が発生した場合、バックアップから復元します
#
# 使用方法:
#   sudo ./restore_server.sh [バックアップディレクトリ]
#
# 例:
#   sudo ./restore_server.sh /root/ssl_backup/20241228_143000
#   sudo ./restore_server.sh /root/ssl_backup/latest
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

print_header "サーバー復元スクリプト"

# root権限チェック
if [ "$EUID" -ne 0 ]; then
    print_error "このスクリプトはroot権限で実行してください"
    echo "使用方法: sudo ./restore_server.sh [バックアップディレクトリ]"
    exit 1
fi

print_success "root権限で実行中"

#-------------------------------------------------------------------------------
# バックアップディレクトリの確認
#-------------------------------------------------------------------------------
BACKUP_DIR="$1"

if [ -z "$BACKUP_DIR" ]; then
    # 引数がない場合、バックアップ一覧を表示
    BACKUP_BASE_DIR="/root/ssl_backup"

    if [ ! -d "$BACKUP_BASE_DIR" ]; then
        print_error "バックアップが見つかりません: $BACKUP_BASE_DIR"
        exit 1
    fi

    print_header "利用可能なバックアップ"

    echo "番号  日時                 サイズ"
    echo "----------------------------------------"

    BACKUPS=()
    i=1
    for dir in $(ls -dt ${BACKUP_BASE_DIR}/2* 2>/dev/null); do
        if [ -d "$dir" ]; then
            SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
            DATE=$(basename "$dir")
            echo "$i)    $DATE    $SIZE"
            BACKUPS+=("$dir")
            ((i++))
        fi
    done

    if [ ${#BACKUPS[@]} -eq 0 ]; then
        print_error "バックアップが見つかりません"
        exit 1
    fi

    echo "----------------------------------------"
    echo ""
    read -p "復元するバックアップの番号を入力してください: " BACKUP_NUM

    if [[ ! "$BACKUP_NUM" =~ ^[0-9]+$ ]] || [ "$BACKUP_NUM" -lt 1 ] || [ "$BACKUP_NUM" -gt ${#BACKUPS[@]} ]; then
        print_error "無効な番号です"
        exit 1
    fi

    BACKUP_DIR="${BACKUPS[$((BACKUP_NUM-1))]}"
fi

# シンボリックリンクの解決
if [ -L "$BACKUP_DIR" ]; then
    BACKUP_DIR=$(readlink -f "$BACKUP_DIR")
fi

if [ ! -d "$BACKUP_DIR" ]; then
    print_error "バックアップディレクトリが見つかりません: $BACKUP_DIR"
    exit 1
fi

print_success "バックアップディレクトリ: $BACKUP_DIR"

# バックアップ情報表示
if [ -f "${BACKUP_DIR}/backup_info.txt" ]; then
    echo ""
    cat "${BACKUP_DIR}/backup_info.txt"
    echo ""
fi

#-------------------------------------------------------------------------------
# 復元内容の選択
#-------------------------------------------------------------------------------
print_header "復元内容の選択"

echo "復元する項目を選択してください:"
echo ""
echo "1) すべて復元（Apache + irohaboard + データベース）"
echo "2) Apache設定のみ復元"
echo "3) irohaboardファイルのみ復元"
echo "4) データベースのみ復元"
echo "5) 個別に選択"
echo "0) キャンセル"
echo ""
read -p "選択 [1-5, 0]: " RESTORE_CHOICE

case "$RESTORE_CHOICE" in
    1) RESTORE_APACHE=true; RESTORE_IROHA=true; RESTORE_DB=true ;;
    2) RESTORE_APACHE=true; RESTORE_IROHA=false; RESTORE_DB=false ;;
    3) RESTORE_APACHE=false; RESTORE_IROHA=true; RESTORE_DB=false ;;
    4) RESTORE_APACHE=false; RESTORE_IROHA=false; RESTORE_DB=true ;;
    5)
        RESTORE_APACHE=false
        RESTORE_IROHA=false
        RESTORE_DB=false
        confirm "Apache設定を復元しますか？" && RESTORE_APACHE=true
        confirm "irohaboardファイルを復元しますか？" && RESTORE_IROHA=true
        confirm "データベースを復元しますか？" && RESTORE_DB=true
        ;;
    0)
        echo "キャンセルしました"
        exit 0
        ;;
    *)
        print_error "無効な選択です"
        exit 1
        ;;
esac

#-------------------------------------------------------------------------------
# 復元内容の確認
#-------------------------------------------------------------------------------
print_header "復元内容の確認"

echo "以下の項目を復元します:"
echo ""
$RESTORE_APACHE && echo "  ✓ Apache設定"
$RESTORE_IROHA && echo "  ✓ irohaboardファイル"
$RESTORE_DB && echo "  ✓ データベース"
echo ""

print_warning "復元を実行すると、現在の設定が上書きされます"
print_warning "この操作は元に戻せません"
echo ""

if ! confirm "復元を実行しますか？"; then
    echo "キャンセルしました"
    exit 0
fi

#-------------------------------------------------------------------------------
# Webサーバー停止
#-------------------------------------------------------------------------------
print_header "Webサーバー停止"

if systemctl is-active --quiet httpd 2>/dev/null; then
    WEBSERVER="httpd"
elif systemctl is-active --quiet apache2 2>/dev/null; then
    WEBSERVER="apache2"
else
    WEBSERVER=""
fi

if [ -n "$WEBSERVER" ]; then
    print_info "$WEBSERVER を停止します..."
    systemctl stop "$WEBSERVER"
    print_success "$WEBSERVER 停止完了"
else
    print_warning "Webサーバーが検出できませんでした"
fi

#-------------------------------------------------------------------------------
# Apache設定の復元
#-------------------------------------------------------------------------------
if $RESTORE_APACHE; then
    print_header "Apache設定の復元"

    APACHE_BACKUP="${BACKUP_DIR}/apache"

    if [ ! -d "$APACHE_BACKUP" ]; then
        print_warning "Apacheバックアップが見つかりません: $APACHE_BACKUP"
    else
        # CentOS/RHEL系
        if [ -d "${APACHE_BACKUP}/httpd" ]; then
            print_info "/etc/httpd を復元中..."

            # 現在の設定をバックアップ（念のため）
            if [ -d /etc/httpd ]; then
                mv /etc/httpd /etc/httpd.before_restore.$(date +%Y%m%d%H%M%S)
            fi

            cp -rp "${APACHE_BACKUP}/httpd" /etc/
            print_success "/etc/httpd 復元完了"
        fi

        # Ubuntu/Debian系
        if [ -d "${APACHE_BACKUP}/apache2" ]; then
            print_info "/etc/apache2 を復元中..."

            if [ -d /etc/apache2 ]; then
                mv /etc/apache2 /etc/apache2.before_restore.$(date +%Y%m%d%H%M%S)
            fi

            cp -rp "${APACHE_BACKUP}/apache2" /etc/
            print_success "/etc/apache2 復元完了"
        fi

        # Let's Encrypt設定
        if [ -d "${APACHE_BACKUP}/letsencrypt" ]; then
            print_info "/etc/letsencrypt を復元中..."

            if [ -d /etc/letsencrypt ]; then
                mv /etc/letsencrypt /etc/letsencrypt.before_restore.$(date +%Y%m%d%H%M%S)
            fi

            cp -rp "${APACHE_BACKUP}/letsencrypt" /etc/
            print_success "/etc/letsencrypt 復元完了"
        fi
    fi
fi

#-------------------------------------------------------------------------------
# irohaboardファイルの復元
#-------------------------------------------------------------------------------
if $RESTORE_IROHA; then
    print_header "irohaboardファイルの復元"

    IROHA_BACKUP="${BACKUP_DIR}/irohaboard"
    IROHA_ARCHIVE="${IROHA_BACKUP}/irohaboard_files.tar.gz"

    if [ ! -f "$IROHA_ARCHIVE" ]; then
        print_warning "irohaboardバックアップが見つかりません: $IROHA_ARCHIVE"
    else
        # 元のパスを取得
        if [ -f "${IROHA_BACKUP}/original_path.txt" ]; then
            ORIGINAL_PATH=$(cat "${IROHA_BACKUP}/original_path.txt")
            PARENT_DIR=$(dirname "$ORIGINAL_PATH")
            DIR_NAME=$(basename "$ORIGINAL_PATH")

            print_info "復元先: $ORIGINAL_PATH"

            # 現在のディレクトリをバックアップ
            if [ -d "$ORIGINAL_PATH" ]; then
                print_info "現在のディレクトリを退避..."
                mv "$ORIGINAL_PATH" "${ORIGINAL_PATH}.before_restore.$(date +%Y%m%d%H%M%S)"
            fi

            # 復元
            print_info "ファイルを展開中..."
            tar -xzf "$IROHA_ARCHIVE" -C "$PARENT_DIR"

            print_success "irohaboard復元完了: $ORIGINAL_PATH"
        else
            print_warning "元のパス情報が見つかりません"
            read -p "復元先ディレクトリを入力してください: " RESTORE_PATH

            if [ -n "$RESTORE_PATH" ]; then
                PARENT_DIR=$(dirname "$RESTORE_PATH")
                mkdir -p "$PARENT_DIR"
                tar -xzf "$IROHA_ARCHIVE" -C "$PARENT_DIR"
                print_success "irohaboard復元完了"
            fi
        fi
    fi
fi

#-------------------------------------------------------------------------------
# データベースの復元
#-------------------------------------------------------------------------------
if $RESTORE_DB; then
    print_header "データベースの復元"

    DB_BACKUP="${BACKUP_DIR}/database"

    # SQLファイルを探す
    SQL_FILE=$(ls ${DB_BACKUP}/*.sql.gz 2>/dev/null | head -1 || echo "")

    if [ -z "$SQL_FILE" ]; then
        SQL_FILE=$(ls ${DB_BACKUP}/*.sql 2>/dev/null | head -1 || echo "")
    fi

    if [ -z "$SQL_FILE" ]; then
        print_warning "データベースバックアップが見つかりません"
    else
        print_info "SQLファイル: $SQL_FILE"

        # DB情報を読み取る
        if [ -f "${DB_BACKUP}/db_info.txt" ]; then
            DB_NAME=$(grep "データベース名:" "${DB_BACKUP}/db_info.txt" | cut -d: -f2 | tr -d ' ')
            DB_USER=$(grep "ユーザー名:" "${DB_BACKUP}/db_info.txt" | cut -d: -f2 | tr -d ' ')
            DB_HOST=$(grep "ホスト:" "${DB_BACKUP}/db_info.txt" | cut -d: -f2 | tr -d ' ')

            echo ""
            echo "データベース情報:"
            echo "  データベース名: $DB_NAME"
            echo "  ユーザー名: $DB_USER"
            echo "  ホスト: $DB_HOST"
            echo ""
        else
            read -p "データベース名: " DB_NAME
            read -p "ユーザー名: " DB_USER
            DB_HOST="localhost"
        fi

        read -sp "データベースパスワード: " DB_PASS
        echo ""

        print_warning "既存のデータベース '$DB_NAME' は上書きされます"

        if confirm "データベースを復元しますか？"; then
            print_info "データベースを復元中..."

            # 圧縮されている場合は解凍して復元
            if [[ "$SQL_FILE" == *.gz ]]; then
                gunzip -c "$SQL_FILE" | mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME"
            else
                mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$SQL_FILE"
            fi

            if [ $? -eq 0 ]; then
                print_success "データベース復元完了"
            else
                print_error "データベース復元に失敗しました"
            fi
        fi
    fi
fi

#-------------------------------------------------------------------------------
# Webサーバー起動
#-------------------------------------------------------------------------------
print_header "Webサーバー起動"

if [ -n "$WEBSERVER" ]; then
    print_info "$WEBSERVER を起動します..."
    systemctl start "$WEBSERVER"

    if systemctl is-active --quiet "$WEBSERVER"; then
        print_success "$WEBSERVER 起動完了"
    else
        print_error "$WEBSERVER の起動に失敗しました"
        echo "ログを確認してください:"
        echo "  journalctl -u $WEBSERVER -n 50"
    fi
fi

#-------------------------------------------------------------------------------
# 完了
#-------------------------------------------------------------------------------
print_header "復元完了"

echo ""
print_success "復元が完了しました"
echo ""
echo "確認事項:"
echo "  1. Webサイトにアクセスして動作確認"
echo "  2. irohaboardにログインできるか確認"
echo "  3. エラーログの確認"
echo ""

if [ -n "$WEBSERVER" ]; then
    echo "エラーログの確認:"
    if [ "$WEBSERVER" = "httpd" ]; then
        echo "  tail -f /var/log/httpd/error_log"
    else
        echo "  tail -f /var/log/apache2/error.log"
    fi
fi

echo ""
print_success "復元スクリプト完了"
