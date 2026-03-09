#!/bin/bash

errorMsg=""
dependencies=("git" "xz" "curl" "unzip")

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
LIGHT_GREEN='\033[1;32m'
LIGHT_CYAN='\033[1;36m'
LIGHT_RED='\033[1;31m'
LIGHT_YELLOW='\033[1;33m'
LIGHT_MAGENTA='\033[1;35m'

LANGUAGE="en"
TRANSLATIONS_URL="https://raw.githubusercontent.com/Syslogine/fivem-server-manager/main/translations.json"
TRANSLATIONS_FILE="$(pwd)/translations_cache.json"

if [ ! -f "$TRANSLATIONS_FILE" ]; then
    echo "Downloading translations..."
    curl -s "$TRANSLATIONS_URL" -o "$TRANSLATIONS_FILE"
    echo "Translations downloaded."
else
    echo "Translations file found."
fi

get_translation() {
    local key="$1"
    if [ ! -f "$TRANSLATIONS_FILE" ]; then
        echo "Error: Translations file not found."
        return
    fi
    if [ -z "$LANGUAGE" ]; then
        echo "Error: Language is not set."
        return
    fi
    local translation=$(jq -r ".[\"$LANGUAGE\"].\"$key\"" "$TRANSLATIONS_FILE")
    if [ "$translation" == "null" ]; then
        echo "Error: Translation for key '$key' not found."
    else
        echo "$translation"
    fi
}

install_dependency() {
    local dependency="$1"
    while true; do
        echo "$(get_translation "attempting_to_install") $dependency..."
        if sudo apt-get update && sudo apt-get install -y "$dependency"; then
            echo "$dependency $(get_translation "installed_successfully")"
            break
        else
            echo "$(get_translation "failed_to_install") $dependency."
            read -p "$(get_translation "do_you_want_to_retry_skip_exit") " choice
            case $choice in
                r|R) echo "$(get_translation "retrying")" ;;
                s|S) echo "$(get_translation "skipping_installation")"
                     return 0 ;;
                e|E) echo "$(get_translation "exiting_script")"
                     exit 1 ;;
                *) echo "$(get_translation "invalid_choice")" ;;
            esac
        fi
    done
}

for dependency in "${dependencies[@]}"; do
    if ! command -v "$dependency" &>/dev/null; then
        errorMsg="${errorMsg}$(get_translation "dependency_not_installed" "$dependency")\n"
        install_dependency "$dependency"
    fi
done

if [ ! -z "$errorMsg" ]; then
    printf "$errorMsg"
fi

create_screen_session() {
    if ! screen -ls | grep -q "FiveM"; then
        screen -S FiveM -dm bash
    fi
}

start_server() {
    echo -e "${YELLOW}$(get_translation "fetching_list_of_servers")${NC}"
    script_dir="$(dirname "$(realpath "$0")")"
    available_servers=()
    for dir in "$script_dir"/*/; do
        if [ -f "${dir}run.sh" ]; then
            available_servers+=("$dir")
        fi
    done
    if [ ${#available_servers[@]} -eq 0 ]; then
        echo "$(get_translation "no_servers_found")"
        return 1
    fi
    echo "$(get_translation "available_servers")"
    for ((i=0; i<${#available_servers[@]}; i++)); do
        server_name=$(basename "${available_servers[$i]}")
        echo "$((i+1)). $server_name"
    done
    read -p "$(get_translation "enter_server_number") " server_choice
    if ! [[ "$server_choice" =~ ^[0-9]+$ ]] || [ "$server_choice" -lt 1 ] || [ "$server_choice" -gt ${#available_servers[@]} ]; then
        echo "$(get_translation "invalid_choice0")"
        return 1
    fi
    selected_server="${available_servers[$((server_choice-1))]}"
    server_name=$(basename "${selected_server}")
    screen_name="$server_name"
    echo "$(get_translation "select_start_method")"
    echo "$(get_translation "standard_start")"
    echo "$(get_translation "start_with_config")"
    read -p "$(get_translation "option_1_2") " start_option
    case "$start_option" in
        2) start_cmd="./run.sh +exec server.cfg"
            if grep -qE '^\s*sv_licenseKey\s+changeme\s*$' "${selected_server}/server.cfg"; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') - $(get_translation "warning_sv_licenseKey_not_set")" >> "${selected_server}server.log"
            fi
           ;;
        *) start_cmd="./run.sh"
           ;;
    esac
    echo "$(get_translation "starting_server") $server_name"
    screen -dmS "$screen_name" bash -c "cd '$selected_server' && $start_cmd"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $(get_translation "server_started" "$server_name" "$start_cmd")" >> "${selected_server}server.log"
    echo "$(get_translation "server_start_event_logged" "$server_name")"
}

stop_server() {
    local script_dir="$(dirname "$(realpath "$0")")"
    local available_servers=()
    for dir in "$script_dir"/*/; do
        if [ -f "${dir}run.sh" ]; then
            available_servers+=("$dir")
        fi
    done
    if [ ${#available_servers[@]} -eq 0 ]; then
        echo "$(get_translation "no_servers_found_to_stop")"
        return 1
    fi
    echo "$(get_translation "available_servers_to_stop")"
    for ((i=0; i<${#available_servers[@]}; i++)); do
        local server_name=$(basename "${available_servers[$i]}")
        echo "$((i+1)). $server_name"
    done
    read -p "$(get_translation "enter_server_number_to_stop") " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#available_servers[@]} ]; then
        echo "$(get_translation "invalid_choice_operation_cancelled")"
        return 1
    fi
    if [ "$choice" -eq 0 ]; then
        echo "$(get_translation "operation_cancelled_by_user")"
        return 0
    fi
    local selected_server_path="${available_servers[$((choice-1))]}"
    local selected_server_name=$(basename "$selected_server_path")
    if screen -S "$selected_server_name" -X quit; then
        echo "$(get_translation "server_stopped_successfully" "$selected_server_name")"
        local log_path="${selected_server_path}server.log"
        if [[ -f "$log_path" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - $(get_translation "server_stop_event_logged" "$selected_server_name")" >> "$log_path"
        else
            echo "$(get_translation "failed_to_log_stop_event" "$log_path")"
        fi
    else
        echo "$(get_translation "failed_to_stop_server" "$selected_server_name")"
    fi
}

monitor_server() {
    script_dir="$(dirname "$(realpath "$0")")"
    available_servers=()
    for dir in "$script_dir"/*/; do
        if [ -f "${dir}run.sh" ]; then
            available_servers+=("$dir")
        fi
    done
    if [ ${#available_servers[@]} -eq 0 ]; then
        echo "$(get_translation "no_servers_found_to_monitor")"
        return 1
    fi
    echo "$(get_translation "available_servers_to_monitor")"
    for ((i=0; i<${#available_servers[@]}; i++)); do
        server_name=$(basename "${available_servers[$i]}")
        if [[ $server_name != "fivemanager.sh" ]]; then
            echo "$((i+1)). $server_name"
        fi
    done
    read -p "$(get_translation "enter_server_number_to_monitor") " server_choice
    if ! [[ "$server_choice" =~ ^[0-9]+$ ]] || [ "$server_choice" -lt 1 ] || [ "$server_choice" -gt ${#available_servers[@]} ]; then
        echo "$(get_translation "invalid_choice_monitor")"
        return 1
    fi
    selected_server="${available_servers[$((server_choice-1))]}"
    server_name=$(basename "${selected_server%/}")
    screen_name="$server_name"
    echo "$(get_translation "now_monitoring" "$server_name")"
    read -p "$(get_translation "press_any_key_to_continue")" -n 1 -s
    screen -r "$screen_name"
    echo "$(get_translation "successfully_detached" "$server_name")"
}

create_server() {
    read -p "$(get_translation "enter_server_name") " server_name
    server_dir="$(pwd)"
    server_path="$server_dir/$server_name"
    if [ -d "$server_path" ]; then
        echo "$(get_translation "error_server_directory_exists" "$server_name")"
        return
    fi
    echo "$(get_translation "creating_directory" "$server_path")"
    mkdir -p "$server_path" && cd "$server_path" || { echo "$(get_translation "failed_create_access_directory" "$server_path")"; exit 1; }
    echo "$(get_translation "cloning_cfx_server_data")"
    git clone https://github.com/citizenfx/cfx-server-data.git . && rm -rf .git || { echo "$(get_translation "failed_clone_cfx_server_data")"; exit 1; }
    local base_url="https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/"
    echo "$(get_translation "fetching_latest_build_url")"
    local build_url=$(curl -s "${base_url}" | grep -o 'href="[^"]\+fx.tar.xz"' | head -1 | cut -d '"' -f 2)
    if [ -z "$build_url" ]; then
        echo "$(get_translation "failed_obtain_build_url")"
        exit 1
    fi
    local full_url="${base_url}${build_url}"
    full_url="${full_url/.\//}"
    echo "$(get_translation "downloading_fivem_build" "$full_url")"
    download_result=$(curl -o "fx.tar.xz" "$full_url" 2>&1)
    if [ $? -ne 0 ]; then
        echo "$(get_translation "download_failed")"
        exit 1
    else
        echo "$(get_translation "download_successful")"
    fi
    echo "$(get_translation "extracting_server_build")"
    if tar -xvf "fx.tar.xz" -C "$server_path"; then
        echo "$(get_translation "extraction_successful")"
        rm "fx.tar.xz"
        echo "$(get_translation "removed_fx_tar_xz_archive")"
    else
        echo "$(get_translation "failed_extract_server_build")"
        exit 1
    fi
    echo "$(get_translation "creating_populating_server_cfg")"
    touch "$server_path/server.log" || { echo "$(get_translation "failed_create_server_log")"; exit 1; }
    if curl -o "$server_path/server.cfg" "https://syslogine.cloud/docs/games/gta_v/pixxy/config.cfg"; then
        echo "$(get_translation "server_cfg_downloaded_populated")"
    else
        echo "$(get_translation "failed_download_server_cfg")"
        exit 1
    fi
}

update_script() {
    local script_name=$(basename "$0")
    local temp_script="temp_updated_$script_name"
    local backup_script="${script_name}.backup"
    local script_url="https://raw.githubusercontent.com/Syslogine/fivem-server-manager/main/$script_name"
    echo "$(get_translation "checking_for_updates")"
    if curl -sSf "$script_url" -o "$temp_script"; then
        if cmp -s "$temp_script" "$0"; then
            echo "$(get_translation "no_new_updates")"
            rm -f "$temp_script"
            return 0
        else
            echo "$(get_translation "update_available")"
        fi
        echo "$(get_translation "backing_up_current_script" "$backup_script")"
        if cp -f "$0" "$backup_script"; then
            echo "$(get_translation "backup_created_successfully")"
        else
            echo "$(get_translation "failed_create_backup")"
            rm -f "$temp_script"
            return 1
        fi
        echo "$(get_translation "validating_downloaded_script")"
        if grep -q "#!/bin/bash" "$temp_script"; then
            echo "$(get_translation "validation_successful")"
            echo "$(get_translation "updating_script")"
            if mv -f "$temp_script" "$0"; then
                echo "$(get_translation "update_successful")"
                chmod +x "$0"
                exec "$0"
            else
                echo "$(get_translation "failed_update_script")"
                if cp -f "$backup_script" "$0"; then
                    echo "$(get_translation "restore_successful")"
                else
                    echo "$(get_translation "critical_error_restore_failed" "$backup_script")"
                fi
            fi
        else
            echo "$(get_translation "validation_failed_update_aborted")"
            rm -f "$temp_script"
        fi
    else
        echo "$(get_translation "failed_download_updated_script")"
    fi
}

debug_server() {
    echo "$(get_translation "select_server_to_debug")"
    script_dir="$(dirname "$(realpath "$0")")"
    available_servers=()
    for dir in "$script_dir"/*/; do
        if [ -f "${dir}run.sh" ]; then
            available_servers+=("$dir")
        fi
    done
    if [ ${#available_servers[@]} -eq 0 ]; then
        echo "$(get_translation "no_servers_found_to_debug")"
        return 1
    fi
    for ((i=0; i<${#available_servers[@]}; i++)); do
        server_name=$(basename "${available_servers[$i]}")
        echo "$((i+1)). $server_name"
    done
    read -p "$(get_translation "enter_server_number_to_debug") " server_choice
    if ! [[ "$server_choice" =~ ^[0-9]+$ ]] || [ "$server_choice" -lt 1 ] || [ "$server_choice" -gt ${#available_servers[@]} ]; then
        echo "$(get_translation "invalid_choice_debug")"
        return 1
    fi
    selected_server="${available_servers[$((server_choice-1))]}"
    server_name=$(basename "${selected_server}")
    echo "$(get_translation "debugging_server" "$server_name")"
    if screen -list | grep -q "fivem_server_$server_name"; then
        echo "$(get_translation "server_currently_running")"
    else
        echo "$(get_translation "server_not_running")"
    fi
    local log_file="${selected_server}server.log"
    if [ -f "$log_file" ]; then
        echo "$(get_translation "last_lines_server_log")"
        tail -n 10 "$log_file"
    else
        echo "$(get_translation "server_log_file_not_found")"
        read -p "$(get_translation "create_log_file_prompt") " create_choice
        if [[ $create_choice =~ ^[Yy]$ ]]; then
            touch "$log_file" && echo "$(get_translation "log_file_created" "$log_file")" || echo "$(get_translation "failed_create_log_file")"
        else
            echo "$(get_translation "not_creating_log_file")"
        fi
    fi
}

update_txAdmin() {
    echo "$(get_translation "fetching_txadmin_release_info")"
    available_servers=()
    script_dir="$(dirname "$(realpath "$0")")"
    for server_dir in "$script_dir"/*; do
        if [ -d "$server_dir" ] && [ -f "$server_dir/run.sh" ]; then
            available_servers+=("$server_dir")
        fi
    done
    if [ ${#available_servers[@]} -eq 0 ]; then
        echo "$(get_translation "no_servers_found_txadmin")"
        return 1
    fi
    echo "$(get_translation "available_servers_for_txadmin_update")"
    for i in "${!available_servers[@]}"; do
        echo "$((i+1)). $(basename "${available_servers[$i]}")"
    done
    read -p "$(get_translation "enter_number_for_txadmin_update") " server_choice
    if ! [[ "$server_choice" =~ ^[0-9]+$ ]] || [ "$server_choice" -lt 1 ] || [ "$server_choice" -gt ${#available_servers[@]} ]; then
        echo "$(get_translation "invalid_choice_txadmin_update")"
        return 1
    fi
    selected_server="${available_servers[$((server_choice-1))]}"
    txAdmin_dir="${selected_server}/alpine/opt/cfx-server/citizen/system_resources/monitor"
    release_info=$(curl -s https://api.github.com/repos/tabarra/txAdmin/releases/latest)
    download_url=$(echo "$release_info" | jq -r '.assets[] | select(.name == "monitor.zip") | .browser_download_url')
    if [ -z "$download_url" ]; then
        echo "$(get_translation "failed_find_monitor_zip")"
        return 1
    fi
    echo "$(get_translation "downloading_monitor_zip" "$download_url")"
    curl -L "$download_url" -o monitor.zip
    if ! command -v unzip &> /dev/null; then
        echo "$(get_translation "unzip_required")"
        return 1
    fi
    temp_dir=$(mktemp -d)
    echo "$(get_translation "extracting_monitor_zip")"
    unzip monitor.zip -d "$temp_dir"
    rm monitor.zip
    echo "$(get_translation "updating_txadmin_monitor" "$txAdmin_dir")"
    rm -rf "$txAdmin_dir/*"
    mkdir -p "$txAdmin_dir/"
    mv "$temp_dir"/* "$txAdmin_dir/"
    rm -rf "$temp_dir"
    echo "$(get_translation "txadmin_update_complete")"
}

delete_server() {
    script_dir="$(dirname "$(realpath "$0")")"
    available_servers=()
    echo "$(get_translation "available_servers_to_delete")"
    for dir in "$script_dir"/*/; do
        if [ -d "$dir" ]; then
            server_name=$(basename "$dir")
            available_servers+=("$server_name")
            echo "${#available_servers[@]}. $server_name"
        fi
    done
    if [ ${#available_servers[@]} -eq 0 ]; then
        echo "$(get_translation "no_servers_found_to_delete")"
        return 1
    fi
    read -p "$(get_translation "enter_number_to_delete") " server_choice
    if [ "$server_choice" -eq 0 ]; then
        echo "$(get_translation "deletion_cancelled")"
        return 0
    fi
    if ! [[ "$server_choice" =~ ^[0-9]+$ ]] || [ "$server_choice" -lt 1 ] || [ "$server_choice" -gt ${#available_servers[@]} ]; then
        echo "$(get_translation "invalid_choice_delete")"
        return 1
    fi
    selected_server="${available_servers[$((server_choice-1))]}"
    read -p "$(get_translation "confirm_deletion" "$selected_server") " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        rm -rf "$script_dir/$selected_server"
        echo "$(get_translation "server_deleted" "$selected_server")"
    else
        echo "$(get_translation "deletion_cancelled")"
    fi
}

monitor_server_performance() {
    printf "\033c"
    echo -e "${YELLOW}$(get_translation "gathering_system_performance")${NC}\n"
    echo -e "${YELLOW}$(get_translation "cpu_information")${NC}"
    CPU_MODEL=$(lscpu | grep "Model name" | awk -F: '{print $2}' | sed -e 's/^[[:space:]]*//')
    CPU_CORES=$(nproc)
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
    echo -e "${GREEN}$(get_translation "model"):${NC} $CPU_MODEL"
    echo -e "${GREEN}$(get_translation "core_count"):${NC} $CPU_CORES"
    echo -e "${GREEN}$(get_translation "usage"):${NC} $CPU_USAGE\n"
    echo -e "${YELLOW}$(get_translation "memory")${NC}"
    TOTAL_RAM_MB=$(grep MemTotal /proc/meminfo | awk '{print $2 / 1024 " MB"}')
    MEM_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')
    SWAP_USAGE=$(free -m | awk 'NR==3{printf "%.2f%%", $3*100/$2 }')
    echo -e "${GREEN}$(get_translation "total_ram"):${NC} $TOTAL_RAM_MB"
    echo -e "${GREEN}$(get_translation "usage"):${NC} $MEM_USAGE"
    echo -e "${GREEN}$(get_translation "swap_usage"):${NC} $SWAP_USAGE\n"
    echo -e "${YELLOW}$(get_translation "disk")${NC}"
    DISK_USAGE=$(df -h | awk '$NF=="/"{printf "%s of total disk space used", $5}')
    echo -e "${GREEN}$(get_translation "disk_usage"):${NC} $DISK_USAGE\n"
    echo -e "${YELLOW}$(get_translation "network")${NC}"
    LOAD_AVERAGE=$(awk '{printf "%s, %s, %s", $1, $2, $3}' /proc/loadavg 2>/dev/null)
    ACTIVE_INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    LOCAL_IP=$(ip -4 addr show "$ACTIVE_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    PUBLIC_IP=$(curl -s https://ipv4.icanhazip.com)
    ACTIVE_CONNS=$(ss -tun | grep -vc "State")
    echo -e "${GREEN}$(get_translation "load_average"):${NC} $LOAD_AVERAGE"
    echo -e "${GREEN}$(get_translation "local_ipv4"):${NC} $LOCAL_IP"
    echo -e "${GREEN}$(get_translation "public_ipv4"):${NC} $PUBLIC_IP"
    echo -e "${GREEN}$(get_translation "active_connections"):${NC} $ACTIVE_CONNS\n"
    echo -e "${YELLOW}$(get_translation "services")${NC}"
    check_process_status() {
        local process_name=$1
        if pgrep "$process_name" > /dev/null; then
            echo "$(get_translation "running")"
        else
            echo "$(get_translation "not_running")"
        fi
    }
    MYSQL_RUNNING=$(check_process_status "mysql")
    MARIADB_RUNNING=$(check_process_status "mariadbd")
    NGINX_RUNNING=$(check_process_status "nginx")
    REDIS_RUNNING=$(check_process_status "redis-server")
    echo -e "${GREEN}$(get_translation "mysql")${NC} $MYSQL_RUNNING"
    echo -e "${GREEN}$(get_translation "mariadb")${NC} $MARIADB_RUNNING"
    echo -e "${GREEN}$(get_translation "nginx")${NC} $NGINX_RUNNING"
    echo -e "${GREEN}$(get_translation "redis")${NC} $REDIS_RUNNING\n"
    echo -e "${YELLOW}$(get_translation "users_security")${NC}"
    USER_SESSIONS=$(who | wc -l)
    SSH_USERS=$(getent passwd | grep /home | wc -l)
    PENDING_UPGRADES=$(apt list --upgradable 2>/dev/null | wc -l)
    echo -e "${GREEN}$(get_translation "active_sessions"):${NC} $USER_SESSIONS"
    echo -e "${GREEN}$(get_translation "ssh_users"):${NC} $SSH_USERS"
    echo -e "${GREEN}$(get_translation "pending_upgrades"):${NC} $PENDING_UPGRADES\n"
    echo -e "${YELLOW}$(get_translation "system")${NC}"
    UPTIME=$(uptime -p)
    echo -e "${GREEN}$(get_translation "uptime"):${NC} $UPTIME"
}

perform_automated_backup() {
    echo -e "${YELLOW}$(get_translation "initiating_automated_backup")${NC}"
    local script_dir="$(dirname "$(realpath "$0")")"
    local backup_dir="${script_dir}/backup"
    mkdir -p "$backup_dir"
    echo "$(get_translation "available_servers_for_backup")"
    local available_servers=()
    local i=0
    for dir in "$script_dir"/*/; do
        if [ -d "$dir" ] && [ -f "${dir}run.sh" ]; then
            local server_name=$(basename "$dir")
            available_servers+=("$server_name")
            ((i++))
            echo "$i. $server_name"
        fi
    done
    if [ ${#available_servers[@]} -eq 0 ]; then
        echo -e "${RED}$(get_translation "no_servers_found_to_backup")${NC}"
        return
    fi
    read -p "$(get_translation "enter_number_of_server_to_backup") " server_choice
    if [[ "$server_choice" == "0" ]]; then
        echo "$(get_translation "backup_operation_cancelled")"
        return
    fi
    if ! [[ "$server_choice" =~ ^[0-9]+$ ]] || [ "$server_choice" -lt 1 ] || [ "$server_choice" -gt ${#available_servers[@]} ]; then
        echo -e "${RED}$(get_translation "invalid_selection_try_again")${NC}"
        return
    fi
    local target="${available_servers[$server_choice-1]}"
    local target_dir="${script_dir}/${target}"
    local backup_filename="server_backup_${target}_$(date +%Y%m%d_%H%M%S)"
    read -p "$(get_translation "do_you_want_to_backup_database_for" "${target}") (y/n): " backup_db
    if [[ "$backup_db" =~ ^[Yy]$ ]]; then
        local server_cfg="${target_dir}/server.cfg"
        if [ -f "$server_cfg" ]; then
            local db_info=$(grep 'set mysql_connection_string' "$server_cfg" | cut -d '"' -f 2)
            local username=$(echo $db_info | cut -d ':' -f 2 | cut -d '/' -f 3)
            local password=$(echo $db_info | cut -d '@' -f 1 | cut -d ':' -f 3)
            local db=$(echo $db_info | cut -d '/' -f 4 | cut -d '?' -f 1)
            local host=$(echo $db_info | cut -d '@' -f 2 | cut -d '/' -f 1)
            local db_backup_filename="${backup_filename}_db.sql"
            echo "$(get_translation "performing_database_backup")"
            mysqldump -u "$username" -p"$password" -h "$host" "$db" > "${target_dir}/${db_backup_filename}"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}$(get_translation "database_backup_completed_successfully" "${target}", "${db_backup_filename}")${NC}"
            else
                echo -e "${RED}$(get_translation "database_backup_failed" "${target}")${NC}"
                return 1
            fi
        else
            echo "$(get_translation "server_config_not_found_skipping_db_backup")"
        fi
    fi
    backup_filename="${backup_filename}.tar.gz"
    tar -czf "${backup_dir}/${backup_filename}" -C "$script_dir" "$target" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}$(get_translation "file_backup_completed_successfully" "${target}", "${backup_filename}")${NC}"
    else
        echo -e "${RED}$(get_translation "file_backup_failed" "${target}")${NC}"
        return 1
    fi
    [[ "$backup_db" =~ ^[Yy]$ ]] && rm -f "${target_dir}/${db_backup_filename}"
    local keep_last_n=5
    echo "$(get_translation "cleaning_up_old_backups" "${keep_last_n}")"
    find "$backup_dir" -type f -name 'server_backup_*' | sort -r | tail -n +$((keep_last_n + 1)) | xargs rm -f
}

handle_invalid_choice() {
    echo "$(get_translation "invalid_choice_please_try_again" "$1")"
}

manage_security() {
    echo -e "${YELLOW}$(get_translation "security_enhancements_menu")${NC}"
    echo "$(get_translation "configure_firewall")"
    echo "$(get_translation "harden_ssh")"
    echo "$(get_translation "perform_system_updates")"
    echo "$(get_translation "setup_fail2ban")"
    echo "$(get_translation "perform_security_audit")"
    read -p "$(get_translation "select_option")" security_action

    case $security_action in
        1) configure_firewall ;;
        2) harden_ssh ;;
        3) perform_updates ;;
        4) setup_fail2ban ;;
        5) perform_security_audit ;;
        *) echo -e "${RED}$(get_translation "invalid_option_selected")${NC}" ;;
    esac
}

configure_firewall() {
    echo -e "${YELLOW}$(get_translation "initiating_firewall_configuration")${NC}"
    available_servers=()
    script_dir="$(dirname "$(realpath "$0")")"
    echo "$(get_translation "searching_for_servers" "${script_dir}")"
    for server_dir in "$script_dir"/*; do
        if [ -d "$server_dir" ] && [ -f "$server_dir/run.sh" ]; then
            server_name=$(basename "$server_dir")
            available_servers+=("$server_name")
        fi
    done
    if [ ${#available_servers[@]} -eq 0 ]; then
        echo -e "${RED}$(get_translation "no_servers_found")${NC}"
        return 1
    fi
    echo "$(get_translation "available_servers_for_firewall")"
    for i in "${!available_servers[@]}"; do
        echo "$((i+1)). ${available_servers[$i]}"
    done
    read -p "$(get_translation "select_server_for_firewall")" server_choice
    let server_choice-=1
    if [[ $server_choice -lt 0 || $server_choice -ge ${#available_servers[@]} ]]; then
        echo -e "${RED}$(get_translation "invalid_selection")${NC}"
        return 1
    fi
    server_cfg="${script_dir}/${available_servers[$server_choice]}/server.cfg"
    if [ -f "$server_cfg" ]; then
        tcp_port=$(grep "endpoint_add_tcp" "$server_cfg" | cut -d '"' -f 2 | cut -d ':' -f 2)
        udp_port=$(grep "endpoint_add_udp" "$server_cfg" | cut -d '"' -f 2 | cut -d ':' -f 2)
        if [[ -z $tcp_port || -z $udp_port ]]; then
            echo -e "${RED}$(get_translation "could_not_extract_ports")${NC}"
            return 1
        fi
        echo "$(get_translation "configuring_ufw")"
        sudo ufw allow 22/tcp
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        sudo ufw allow $tcp_port/tcp
        sudo ufw allow $udp_port/udp
        read -p "$(get_translation "do_you_want_to_allow_txadmin") " allow_txadmin
        if [[ $allow_txadmin =~ ^[Yy]$ ]]; then
            sudo ufw allow 40120/tcp
            echo -e "${GREEN}$(get_translation "txadmin_port_opened")${NC}"
        fi
        if sudo ufw status | grep -q "inactive"; then
            sudo ufw --force enable
            echo -e "${GREEN}$(get_translation "firewall_enabled_configured" "${available_servers[$server_choice]}")${NC}"
        else
            sudo ufw reload
            echo -e "${GREEN}$(get_translation "firewall_rules_reloaded" "${available_servers[$server_choice]}")${NC}"
        fi
        echo -e "${GREEN}$(get_translation "firewall_rules_configured_successfully" "${available_servers[$server_choice]}")${NC}"
    else
        echo -e "${RED}$(get_translation "server_cfg_not_found")${NC}"
        return 1
    fi
}

harden_ssh() {
    echo -e "${YELLOW}$(get_translation "hardening_ssh_configuration")${NC}"
    local user=$(whoami)
    user_home=$(eval echo ~${user})
    if [ -f "${user_home}/.ssh/authorized_keys" ]; then
        echo -e "${GREEN}$(get_translation "ssh_keys_setup_detected" "${user}")${NC}"
        ssh_config_file="/etc/ssh/sshd_config"
        sudo cp $ssh_config_file "${ssh_config_file}.bak"
        sudo sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' $ssh_config_file
        read -p "$(get_translation "disable_password_authentication")" disable_pass_auth
        if [[ $disable_pass_auth == [Yy] ]]; then
            sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' $ssh_config_file
            sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' $ssh_config_file
            echo -e "${GREEN}$(get_translation "password_authentication_disabled")${NC}"
        else
            echo -e "${YELLOW}$(get_translation "keeping_password_authentication_enabled")${NC}"
        fi
        sudo systemctl reload sshd
    else
        echo -e "${RED}$(get_translation "no_ssh_keys_setup_detected" "${user}")${NC}"
    fi
}

perform_updates() {
    echo -e "${YELLOW}$(get_translation "updating_server_software")${NC}"
    if sudo apt-get update; then
        echo -e "${GREEN}$(get_translation "package_lists_updated")${NC}"
    else
        echo -e "${RED}$(get_translation "failed_to_update_package_lists")${NC}"
        return 1
    fi
    if sudo apt-get upgrade -y; then
        echo -e "${GREEN}$(get_translation "packages_upgraded")${NC}"
    else
        echo -e "${RED}$(get_translation "failed_to_upgrade_packages")${NC}"
        return 1
    fi
    read -p "$(get_translation "remove_obsolete_packages")" cleanup_choice
    if [[ $cleanup_choice == [Yy] ]]; then
        sudo apt-get autoremove -y && sudo apt-get autoclean -y
        echo -e "${GREEN}$(get_translation "system_cleaned_up")${NC}"
    fi
    if [ -f /var/run/reboot-required ]; then
        echo -e "${YELLOW}$(get_translation "reboot_required")${NC}"
        read -p "$(get_translation "reboot_now")" reboot_choice
        if [[ $reboot_choice == [Yy] ]]; then
            echo -e "${YELLOW}$(get_translation "rebooting_now")${NC}"
            sudo reboot
        else
            echo -e "${YELLOW}$(get_translation "remember_to_reboot")${NC}"
        fi
    else
        echo -e "${GREEN}$(get_translation "system_updated_no_reboot")${NC}"
    fi
}

setup_fail2ban() {
    echo -e "${YELLOW}$(get_translation "checking_fail2ban_installation")${NC}"
    if command -v fail2ban-client &> /dev/null; then
        echo -e "${GREEN}$(get_translation "fail2ban_already_installed")${NC}"
    else
        echo -e "${YELLOW}$(get_translation "installing_fail2ban")${NC}"
        if sudo apt-get install fail2ban -y; then
            echo -e "${GREEN}$(get_translation "fail2ban_installed_success")${NC}"
        else
            echo -e "${RED}$(get_translation "fail2ban_install_failed")${NC}"
            return 1
        fi
    fi
    echo -e "${YELLOW}$(get_translation "enabling_starting_fail2ban")${NC}"
    if sudo systemctl enable fail2ban && sudo systemctl start fail2ban; then
        echo -e "${GREEN}$(get_translation "fail2ban_enabled_started")${NC}"
    else
        echo -e "${RED}$(get_translation "fail2ban_enable_start_failed")${NC}"
        return 1
    fi
    echo -e "${YELLOW}$(get_translation "verifying_fail2ban_status")${NC}"
    if sudo systemctl is-active --quiet fail2ban; then
        echo -e "${GREEN}$(get_translation "fail2ban_running")${NC}"
    else
        echo -e "${RED}$(get_translation "fail2ban_not_running")${NC}"
        return 1
    fi
    read -p "$(get_translation "apply_custom_fail2ban_config")" apply_custom_config
    if [[ "$apply_custom_config" =~ ^[Yy]$ ]]; then
        read -p "$(get_translation "enter_full_path_custom_config")" custom_config_path
        if [ -f "$custom_config_path" ]; then
            custom_config_dir="/etc/fail2ban"
            sudo cp "$custom_config_path" "$custom_config_dir"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}$(get_translation "custom_fail2ban_config_applied")${NC}"
                sudo systemctl reload fail2ban
            else
                echo -e "${RED}$(get_translation "fail2ban_custom_config_failed")${NC}"
                return 1
            fi
        else
            echo -e "${RED}$(get_translation "config_file_not_exist")${NC}"
        fi
    fi
}

perform_security_audit() {
    echo -e "${YELLOW}$(get_translation "checking_lynis_installation")${NC}"
    if command -v lynis &> /dev/null; then
        echo -e "${GREEN}$(get_translation "lynis_already_installed")${NC}"
    else
        echo -e "${YELLOW}$(get_translation "installing_lynis")${NC}"
        if sudo apt-get install lynis -y; then
            echo -e "${GREEN}$(get_translation "lynis_installed_successfully")${NC}"
        else
            echo -e "${RED}$(get_translation "failed_to_install_lynis")${NC}"
            return 1
        fi
    fi
    echo -e "${YELLOW}$(get_translation "performing_security_audit_with_lynis")${NC}"
    read -p "$(get_translation "full_system_or_custom_audit")" audit_choice
    case $audit_choice in
        [cC]* )
            read -p "$(get_translation "enter_lynis_audit_options")" custom_options
            audit_command="sudo lynis $custom_options"
            ;;
        * )
            audit_command="sudo lynis audit system"
            ;;
    esac
    if $audit_command; then
        echo -e "${GREEN}$(get_translation "lynis_audit_completed_successfully")${NC}"
    else
        echo -e "${RED}$(get_translation "lynis_audit_issue")${NC}"
        return 1
    fi
    read -p "$(get_translation "save_audit_report_to_file")" save_report
    if [[ "$save_report" =~ ^[Yy]$ ]]; then
        report_file="/var/log/lynis-$(date +%Y%m%d-%H%M%S).log"
        if $audit_command > "$report_file" 2>&1; then
            echo -e "${GREEN}$(get_translation "lynis_audit_report_saved" "${report_file}")${NC}"
        else
            echo -e "${RED}$(get_translation "failed_to_save_lynis_audit_report")${NC}"
            return 1
        fi
    fi
}

change_language() {
    read -p "$(get_translation "choose_language") " selected_language
    export LANGUAGE="$selected_language"
    echo "$(get_translation "language_set_to" "$selected_language")"
    sleep 2
}

update_server() {
    echo -e "${YELLOW}$(get_translation "select_server_to_update")${NC}"
    script_dir="$(dirname "$(realpath "$0")")"
    available_servers=()
    for dir in "$script_dir"/*/; do
        if [ -f "${dir}run.sh" ]; then
            available_servers+=("$dir")
        fi
    done
    
    if [ ${#available_servers[@]} -eq 0 ]; then
        echo "$(get_translation "no_servers_found_to_update")"
        return 1
    fi
    
    for ((i=0; i<${#available_servers[@]}; i++)); do
        server_name=$(basename "${available_servers[$i]}")
        echo "$((i+1)). $server_name"
    done
    
    read -p "$(get_translation "enter_server_number_to_update") " server_choice
    if ! [[ "$server_choice" =~ ^[0-9]+$ ]] || [ "$server_choice" -lt 1 ] || [ "$server_choice" -gt ${#available_servers[@]} ]; then
        echo "$(get_translation "invalid_choice_update")"
        return 1
    fi
    
    selected_server="${available_servers[$((server_choice-1))]}"
    server_name=$(basename "${selected_server}")
    
    echo "$(get_translation "select_version_type")"
    echo "1. $(get_translation "latest_version")"
    echo "2. $(get_translation "recommended_version")"
    read -p "$(get_translation "enter_version_choice") " version_choice
    
    case "$version_choice" in
        1)
            echo "$(get_translation "fetching_latest_version")"
            api_url="https://changelogs-live.fivem.net/api/changelog/versions/linux/server"
            version_info=$(curl -s "$api_url")
            if [ $? -eq 0 ]; then
                build_url=$(echo "$version_info" | jq -r '.latest_download')
            else
                echo "$(get_translation "failed_to_fetch_version_info")"
                return 1
            fi
            ;;
        2)
            echo "$(get_translation "fetching_recommended_version")"
            api_url="https://changelogs-live.fivem.net/api/changelog/versions/linux/server"
            version_info=$(curl -s "$api_url")
            if [ $? -eq 0 ]; then
                build_url=$(echo "$version_info" | jq -r '.recommended_download')
            else
                echo "$(get_translation "failed_to_fetch_version_info")"
                return 1
            fi
            ;;
        *)
            echo "$(get_translation "invalid_version_choice")"
            return 1
            ;;
    esac
    
    if [ -z "$build_url" ] || [ "$build_url" = "null" ]; then
        echo "$(get_translation "failed_obtain_build_url")"
        return 1
    fi
    
    echo "$(get_translation "downloading_new_version")"
    cd "$selected_server"
    
    if [ -f "fx.tar.xz" ]; then
        rm fx.tar.xz
    fi
    
    echo "Downloading from: $build_url"
    if curl -L -o "fx.tar.xz" "$build_url"; then
        echo "$(get_translation "download_successful")"
        
        echo "$(get_translation "backing_up_current_version")"
        timestamp=$(date +%Y%m%d_%H%M%S)
        mkdir -p "backups"
        if [ -d "alpine" ]; then
            tar -czf "backups/server_backup_${timestamp}.tar.gz" alpine
            echo "$(get_translation "backup_created")"
            
            echo "$(get_translation "removing_old_version")"
            rm -rf alpine
            
            echo "$(get_translation "extracting_new_version")"
            if tar -xf fx.tar.xz; then
                echo "$(get_translation "update_completed_successfully")"
                rm fx.tar.xz
            else
                echo "$(get_translation "extraction_failed")"
                echo "$(get_translation "restoring_backup")"
                tar -xzf "backups/server_backup_${timestamp}.tar.gz"
                return 1
            fi
        else
            echo "$(get_translation "no_existing_installation")"
            echo "$(get_translation "performing_fresh_install")"
            if tar -xf fx.tar.xz; then
                echo "$(get_translation "installation_completed_successfully")"
                rm fx.tar.xz
            else
                echo "$(get_translation "installation_failed")"
                return 1
            fi
        fi
    else
        echo "$(get_translation "download_failed")"
        return 1
    fi
}

display_menu() {

    printf "\033c"
    
    printf "${LIGHT_YELLOW}========================================${NC}\n"
    printf "${LIGHT_CYAN}${BOLD}    $(get_translation "menu_header")    ${NC}\n"
    printf "${LIGHT_YELLOW}========================================${NC}\n\n"

    # Server Management Section
    printf "${LIGHT_GREEN}$(get_translation "server_management")${NC}\n"
    printf "${CYAN}1. ${NC} %-30s${NC} - %s\n" "$(get_translation "create_new_server")" "$(get_translation "create_new_server_desc")"
    printf "${CYAN}2. ${NC} %-30s${NC} - %s\n" "$(get_translation "start_server")" "$(get_translation "start_server_desc")"
    printf "${CYAN}3. ${NC} %-30s${NC} - %s\n" "$(get_translation "stop_server")" "$(get_translation "stop_server_desc")"
    printf "${CYAN}4. ${NC} %-30s${NC} - %s\n" "$(get_translation "monitor_server_console")" "$(get_translation "monitor_server_console_desc")"
    printf "${CYAN}5. ${NC} %-30s${NC} - %s\n" "$(get_translation "backup_server")" "$(get_translation "backup_server_desc")"
    printf "${CYAN}6. ${NC} %-30s${NC} - %s\n" "$(get_translation "debug_server")" "$(get_translation "debug_server_desc")"
    printf "${CYAN}7. ${NC} %-30s${NC} - %s\n\n" "$(get_translation "delete_server")" "$(get_translation "delete_server_desc")"

    # Server Utilities Section
    printf "${LIGHT_GREEN}$(get_translation "server_utilities")${NC}\n"
    printf "${CYAN}8. ${NC} %-30s${NC} - %s\n" "$(get_translation "update_txadmin")" "$(get_translation "update_txadmin_desc")"
    printf "${CYAN}9. ${NC} %-30s${NC} - %s\n" "$(get_translation "server_performance_monitoring")" "$(get_translation "server_performance_monitoring_desc")"
    printf "${CYAN}10.${NC} %-30s${NC} - %s\n\n" "$(get_translation "security_enhancements")" "$(get_translation "security_enhancements_desc")"

    # General Options Section
    printf "${LIGHT_GREEN}$(get_translation "general_options")${NC}\n"
    printf "${CYAN}11.${NC} %-30s${NC} - %s\n" "$(get_translation "change_language_option")" "$(get_translation "change_language_option_desc")"
    printf "${CYAN}12.${NC} %-30s${NC} - %s\n" "$(get_translation "update_script")" "$(get_translation "update_script_desc")"
    printf "${CYAN}13.${NC} %-30s${NC} - %s\n" "$(get_translation "update_server")" "$(get_translation "update_server_desc")"
    printf "${CYAN}0. ${NC} %-30s${NC} - %s\n\n" "$(get_translation "exit")" "$(get_translation "exit_desc")"

    # Footer
    printf "${LIGHT_YELLOW}========================================${NC}\n"
}

while true; do
    display_menu
    read -p "$(echo -e $(get_translation "enter_your_choice")${NC} )" choice
    case $choice in
        1) create_server ;;
        2) start_server ;;
        3) stop_server ;;
        4) monitor_server ;;
        5) perform_automated_backup ;;
        6) debug_server ;;
        7) delete_server ;;
        8) update_txAdmin ;;
        9) monitor_server_performance ;;
        10) manage_security ;;
        11) change_language ;;
        12) update_script ;;
        13) update_server ;;
        0 | exit | stop | quit) echo -e "${RED}$(get_translation "exiting_script")${NC}"; exit 0 ;;
        *) echo -e "${RED}$(get_translation "invalid_choice1")${NC}" ;;
    esac
    read -p "$(echo -e ${YELLOW}$(get_translation "press_enter_to_continue")${NC})"
done

