#!/usr/bin/env bash

# --- 1. CONFIGURATION ---
DEBUG="false" 
V_ADDR='YOUR_VAULT_ADDRESS_HERE'
V_TOKEN='YOUR_VAULT_TOKEN_HERE'
V_NAMESPACE='YOUR_VAULT_NAMESPACE_HERE'
V_MOUNT='kv'

V1_BASE_PATH='YOUR_SOURCE_BASE_PATH_HERE'
V2_BASE_PATH='YOUR_TARGET_BASE_PATH_HERE'

OVERWRITE_EXISTING="false"
DEFAULT_RAW="vault_backup_raw.json"
DEFAULT_NEW="vault_backup_new.json"

# --- Password requirements ---
PASS_LEN=24
INCLUDE_SYMBOLS="true"

# --- 2. HELPERS ---
log() { echo -e "$(date +'%H:%M:%S') [INFO] $1"; }
debug() { [[ "$DEBUG" == "true" ]] && echo -e "$(date +'%H:%M:%S') \033[0;33m[DEBUG]\033[0m $1"; }
error() { echo -e "$(date +'%H:%M:%S') \033[0;31m[ERROR]\033[0m $1"; }

generate_password() {
    if [[ "$INCLUDE_SYMBOLS" == "true" ]]; then
        LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*_+=' < /dev/urandom | head -c "$PASS_LEN"
    else
        LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$PASS_LEN"
    fi
}

# --- 3. MODE: EXPORT ---
do_export() {
    local target_file=${2:-$DEFAULT_RAW}
    log "--- EXPORTING SOURCE TO $target_file ---"
    echo "[]" > "$target_file"
    
    walk_path() {
        local sub=$1
        local list_path=$(echo "${V1_BASE_PATH}/${sub}" | sed 's#//#/#g')
        local list_url="${V_ADDR}/v1/${V_MOUNT}/metadata/${list_path%/}/?list=true"

        local resp_file=$(mktemp)
        local http_code=$(curl -k -s -H "X-Vault-Token: ${V_TOKEN}" \
            -H "X-Vault-Namespace: ${V_NAMESPACE}" \
            -o "$resp_file" -w "%{http_code}" "$list_url")

        local keys=$(jq -r '.data.keys[]?' "$resp_file" 2>/dev/null)

        if [[ -z "$keys" ]]; then
            local data_url="${V_ADDR}/v1/${V_MOUNT}/data/${list_path%/}"
            local data_resp=$(curl -k -s -H "X-Vault-Token: ${V_TOKEN}" \
                -H "X-Vault-Namespace: ${V_NAMESPACE}" "$data_url")
            local secret_data=$(echo "$data_resp" | jq -c '.data.data' 2>/dev/null)

            if [[ "$secret_data" != "null" && -n "$secret_data" ]]; then
                # Handle root-level leaf nodes vs nested paths
                local display_path=${sub:-$(basename "$V1_BASE_PATH")}
                log "  [DUMP] Found secret data at: $display_path"
                local tmp=$(mktemp)
                jq --arg p "$display_path" --argjson d "$secret_data" '. += [{"path": $p, "data": $d}]' "$target_file" > "$tmp" && mv "$tmp" "$target_file"
            fi
            rm -f "$resp_file"
            return
        fi

        echo "$keys" | while read -r k; do walk_path "${sub}${k}"; done
        rm -f "$resp_file"
    }
    walk_path ""
    log "Export complete. Found $(jq '. | length' "$target_file") entries."
}

# --- 4. MODE: PREPARE (Structure-Based Rotation) ---
do_prepare() {
    local input_file=${2:-$DEFAULT_RAW}
    local output_file=${3:-$DEFAULT_NEW}
    
    log "--- PREPARING: $input_file -> $output_file ---"
    if [[ ! -f "$input_file" ]]; then error "Input file $input_file not found."; exit 1; fi

    cp "$input_file" "$output_file"
    local count=$(jq '. | length' "$output_file")
    
    for (( i=0; i<count; i++ )); do
        local path=$(jq -r ".[$i].path" "$output_file")
        
        # Get ALL keys in the 'data' object for structural rotation
        local keys=$(jq -r ".[$i].data | keys[]" "$output_file")
        
        for k in $keys; do
            local new_v=$(generate_password)
            local tmp=$(mktemp)
            
            # Use --arg instead of --argkey for maximum compatibility. 
            # We reference the bash index [$i] directly inside the jq filter.
            if jq --arg k "$k" --arg v "$new_v" ".[$i].data[\$k] = \$v" "$output_file" > "$tmp"; then
                mv "$tmp" "$output_file"
                debug "    [REPLACE] $path -> Key: '$k' (Value updated)"
            else
                error "    [FAILED] Failed to update key '$k' in '$path' with jq"
                rm -f "$tmp"
            fi
        done
        log "  [PROCESSED] $path"
    done
    log "Preparation complete. New JSON generated at $output_file"
}

# --- 5. MODE: IMPORT ---
do_import() {
    local input_file=${2:-$DEFAULT_NEW}
    # ... previous initialization ...

    while read -r item; do
        local rel_path=$(echo "$item" | jq -r '.path')
        local payload=$(echo "$item" | jq -c '{data: .data}')
        
        # Construct the final destination path
        local base_name=$(basename "$V1_BASE_PATH")
        local final_path="${V2_BASE_PATH}"
        [[ "$rel_path" != "$base_name" ]] && final_path="${V2_BASE_PATH}/${rel_path%/}"

        if [[ "$OVERWRITE_EXISTING" == "false" ]]; then
            # Check METADATA endpoint instead of DATA to find "soft-deleted" or existing paths
            local metadata_url="${V_ADDR}/v1/${V_MOUNT}/metadata/${final_path}"
            local check_code=$(curl -k -s -o /dev/null -w "%{http_code}" \
                -H "X-Vault-Token: ${V_TOKEN}" -H "X-Vault-Namespace: ${V_NAMESPACE}" "$metadata_url")
            
            if [[ "$check_code" == "200" ]]; then
                log "  [SKIP] $rel_path (Path already exists in Vault metadata)"
                ((skipped++)); continue
            fi
        fi

        # Proceed with WRITE to the DATA endpoint
        local dest_url="${V_ADDR}/v1/${V_MOUNT}/data/${final_path}"
        local status=$(curl -k -s -o /dev/null -w "%{http_code}" -X POST \
            -H "X-Vault-Token: ${V_TOKEN}" -H "X-Vault-Namespace: ${V_NAMESPACE}" \
            -d "$payload" "$dest_url")
            
        # ... status handling ...
    done < <(jq -c '.[]' "$input_file")
}

# --- 6. EXECUTION HANDLER ---
case "$1" in
    export)  do_export "$@" ;;
    prepare) do_prepare "$@" ;;
    import)  do_import "$@" ;;
    *) echo "Usage: $0 {export|prepare|import}"; exit 1 ;;
esac