#!/bin/bash

. /app/includes.sh

function clear_dir() {
    rm -rf "${BACKUP_DIR}"
}

function backup_init() {
    NOW="$(date +"${BACKUP_FILE_DATE_FORMAT}")"
    # backup vaultwarden database file (sqlite)
    BACKUP_FILE_DB_SQLITE="${BACKUP_DIR}/db.${NOW}.sqlite3"
    # backup vaultwarden database file (postgresql)
    BACKUP_FILE_DB_POSTGRESQL="${BACKUP_DIR}/db.${NOW}.dump"
    # backup vaultwarden database file (mysql)
    BACKUP_FILE_DB_MYSQL="${BACKUP_DIR}/db.${NOW}.sql"
    # backup vaultwarden config file
    BACKUP_FILE_CONFIG="${BACKUP_DIR}/config.${NOW}.json"
    # backup vaultwarden rsakey files
    BACKUP_FILE_RSAKEY="${BACKUP_DIR}/rsakey.${NOW}"
    BACKUP_FILE_RSAKEY_TAR="${BACKUP_FILE_RSAKEY}.tar"
    # backup vaultwarden attachments directory
    BACKUP_FILE_ATTACHMENTS="${BACKUP_DIR}/attachments.${NOW}"
    BACKUP_FILE_ATTACHMENTS_TAR="${BACKUP_FILE_ATTACHMENTS}.tar"
    # backup vaultwarden sends directory
    BACKUP_FILE_SENDS="${BACKUP_DIR}/sends.${NOW}"
    BACKUP_FILE_SENDS_TAR="${BACKUP_FILE_SENDS}.tar"
    # backup zip file
    BACKUP_FILE_ZIP="${BACKUP_DIR}/backup.${NOW}.${ZIP_TYPE}"
}

function backup_db_sqlite() {
    color blue "backup vaultwarden sqlite database"

    if [[ -f "${DATA_DB}" ]]; then
        sqlite3 "${DATA_DB}" ".backup '${BACKUP_FILE_DB_SQLITE}'"
    else
        color yellow "not found vaultwarden sqlite database, skipping"
    fi
}

function backup_db_postgresql() {
    color blue "backup vaultwarden postgresql database"

    pg_dump -Fc -h "${PG_HOST}" -p "${PG_PORT}" -d "${PG_DBNAME}" -U "${PG_USERNAME}" -f "${BACKUP_FILE_DB_POSTGRESQL}"
    if [[ $? != 0 ]]; then
        color red "backup vaultwarden postgresql database failed"

        send_notification "failure" "Backup failed at $(date +"%Y-%m-%d %H:%M:%S %Z"). Reason: Backup postgresql database failed."

        exit 1
    fi
}

function backup_db_mysql() {
    color blue "backup vaultwarden mysql database"

    local EXTRA_OPTIONS=()
    if [[ -n "${MYSQL_SSL}" ]]; then
        EXTRA_OPTIONS+=("--ssl=\"${MYSQL_SSL}\"")
    fi
    if [[ -n "${MYSQL_SSL_VERIFY_SERVER_CERT}" ]]; then
        EXTRA_OPTIONS+=("--ssl-verify-server-cert=\"${MYSQL_SSL_VERIFY_SERVER_CERT}\"")
    fi
    if [[ -n "${MYSQL_SSL_CA}" ]]; then
        EXTRA_OPTIONS+=("--ssl-ca=\"${MYSQL_SSL_CA}\"")
    fi
    if [[ -n "${MYSQL_SSL_CERT}" ]]; then
        EXTRA_OPTIONS+=("--ssl-cert=\"${MYSQL_SSL_CERT}\"")
    fi
    if [[ -n "${MYSQL_SSL_KEY}" ]]; then
        EXTRA_OPTIONS+=("--ssl-key=\"${MYSQL_SSL_KEY}\"")
    fi

    eval "mariadb-dump -h \"${MYSQL_HOST}\" -P \"${MYSQL_PORT}\" -u \"${MYSQL_USERNAME}\" -p\"${MYSQL_PASSWORD}\" ${EXTRA_OPTIONS[@]} \"${MYSQL_DATABASE}\" > \"${BACKUP_FILE_DB_MYSQL}\""
    if [[ $? != 0 ]]; then
        color red "backup vaultwarden mysql database failed"

        send_notification "failure" "Backup failed at $(date +"%Y-%m-%d %H:%M:%S %Z"). Reason: Backup mysql database failed."

        exit 1
    fi
}

function backup_config() {
    color blue "backup vaultwarden config"

    if [[ -f "${DATA_CONFIG}" ]]; then
        cp -pf "${DATA_CONFIG}" "${BACKUP_FILE_CONFIG}"
    else
        color yellow "not found vaultwarden config, skipping"
    fi
}

function backup_rsakey() {
    color blue "backup vaultwarden rsakey"

    local FIND_RSAKEY=$(find "${DATA_RSAKEY_DIRNAME}" -name "${DATA_RSAKEY_BASENAME}*" | xargs -I {} basename {})
    local FIND_RSAKEY_COUNT=$(echo "${FIND_RSAKEY}" | wc -l)

    if [[ "${FIND_RSAKEY_COUNT}" -gt 0 ]]; then
        if [[ "${RESTIC_ENABLE}" == "TRUE" ]]; then
            mkdir -p "${BACKUP_FILE_RSAKEY}"

            echo "${FIND_RSAKEY}" | xargs -I {} cp -p "${DATA_RSAKEY_DIRNAME}/{}" "${BACKUP_FILE_RSAKEY}"

            color blue "display rsakey file list"

            find "${BACKUP_FILE_RSAKEY}"
        else
            echo "${FIND_RSAKEY}" | tar -c -C "${DATA_RSAKEY_DIRNAME}" -f "${BACKUP_FILE_RSAKEY_TAR}" -T -

            color blue "display rsakey tar file list"

            tar -tf "${BACKUP_FILE_RSAKEY}"
        fi
    else
        color yellow "not found vaultwarden rsakey, skipping"
    fi
}

function backup_attachments() {
    color blue "backup vaultwarden attachments"

    if [[ -d "${DATA_ATTACHMENTS}" ]]; then
        if [[ "${RESTIC_ENABLE}" == "TRUE" ]]; then
            mkdir -p "${BACKUP_FILE_ATTACHMENTS}"

            cp -rpf "${DATA_ATTACHMENTS}" "${BACKUP_FILE_ATTACHMENTS}"

            color blue "display attachments file list"

            find "${BACKUP_FILE_ATTACHMENTS}"
        else
            tar -c -C "${DATA_ATTACHMENTS_DIRNAME}" -f "${BACKUP_FILE_ATTACHMENTS_TAR}" "${DATA_ATTACHMENTS_BASENAME}"

            color blue "display attachments tar file list"

            tar -tf "${BACKUP_FILE_ATTACHMENTS}"
        fi
    else
        color yellow "not found vaultwarden attachments directory, skipping"
    fi
}

function backup_sends() {
    color blue "backup vaultwarden sends"

    if [[ -d "${DATA_SENDS}" ]]; then
        if [[ "${RESTIC_ENABLE}" == "TRUE" ]]; then
            mkdir -p "${BACKUP_FILE_SENDS}"

            cp -rpf "${DATA_SENDS}" "${BACKUP_FILE_SENDS}"

            color blue "display sends file list"

            find "${BACKUP_FILE_SENDS}"
        else
            tar -c -C "${DATA_SENDS_DIRNAME}" -f "${BACKUP_FILE_SENDS_TAR}" "${DATA_SENDS_BASENAME}"

            color blue "display sends tar file list"

            tar -tf "${BACKUP_FILE_SENDS}"
        fi
    else
        color yellow "not found vaultwarden sends directory, skipping"
    fi
}

function backup() {
    mkdir -p "${BACKUP_DIR}"

    case "${DB_TYPE}" in
        SQLITE)     backup_db_sqlite ;;
        POSTGRESQL) backup_db_postgresql ;;
        MYSQL)      backup_db_mysql ;;
    esac

    backup_config
    backup_rsakey
    backup_attachments
    backup_sends

    ls -lah "${BACKUP_DIR}"
}

function backup_package() {
    if [[ "${ZIP_ENABLE}" == "TRUE" && "${RESTIC_ENABLE}" == "FALSE" ]]; then
        color blue "package backup file"

        UPLOAD_FILE="${BACKUP_FILE_ZIP}"

        if [[ "${ZIP_TYPE}" == "zip" ]]; then
            7z a -tzip -mx=9 -p"${ZIP_PASSWORD}" "${BACKUP_FILE_ZIP}" "${BACKUP_DIR}"/*
        else
            7z a -t7z -m0=lzma2 -mx=9 -mfb=64 -md=32m -ms=on -mhe=on -p"${ZIP_PASSWORD}" "${BACKUP_FILE_ZIP}" "${BACKUP_DIR}"/*
        fi

        ls -lah "${BACKUP_DIR}"

        color blue "display backup ${ZIP_TYPE} file list"

        7z l -p"${ZIP_PASSWORD}" "${BACKUP_FILE_ZIP}"
    else
        color yellow "skip package backup files"

        UPLOAD_FILE="${BACKUP_DIR}"
    fi
}

function upload() {
    # upload file not exist
    if [[ ! -e "${UPLOAD_FILE}" ]]; then
        color red "upload file not found"

        send_notification "failure" "File upload failed at $(date +"%Y-%m-%d %H:%M:%S %Z"). Reason: Upload file not found."

        exit 1
    fi

    # upload
    local HAS_ERROR="FALSE"

    for RCLONE_REMOTE_X in "${RCLONE_REMOTE_LIST[@]}"
    do
        color blue "upload backup file to storage system $(color yellow "[${RCLONE_REMOTE_X}]")"

        if [[ "${RESTIC_ENABLE}" == "TRUE" ]]; then
            local RESTIC_COMMAND_X="${RESTIC_COMMAND} -r \"rclone:${RCLONE_REMOTE_X}\""

            # check if repo already initialized
            eval "${RESTIC_COMMAND_X} cat config"
            local RESTIC_EXIT_CODE=$?

            if [[ $RESTIC_EXIT_CODE == 10 ]]; then
                # init repo if not exist
                eval "${RESTIC_COMMAND_X} init"
                RESTIC_EXIT_CODE=$?

                if [[ $RESTIC_EXIT_CODE != 0 ]]; then
                    color red "restic repository initializing failed"

                    HAS_ERROR=TRUE
                else 
                    # override exit code 10 from "cat config" command
                    RESTIC_EXIT_CODE=0
                fi
            elif [[ $RESTIC_EXIT_CODE != 0 ]]; then
                color red "restic repository probe failed"

                HAS_ERROR="TRUE"
            fi

            if [[ $RESTIC_EXIT_CODE == 0 ]]; then
                # do the backup
                eval "${RESTIC_COMMAND_X} --host \"${RESTIC_HOST}\" backup \"${UPLOAD_FILE}\""
                if [[ $? != 0 ]]; then
                    color red "upload failed"

                    HAS_ERROR="TRUE"
                fi
            fi
        else
            rclone ${RCLONE_GLOBAL_FLAG} copy "${UPLOAD_FILE}" "${RCLONE_REMOTE_X}"
            if [[ $? != 0 ]]; then
                color red "upload failed"

                HAS_ERROR="TRUE"
            fi
        fi
    done

    if [[ "${HAS_ERROR}" == "TRUE" ]]; then
        send_notification "failure" "File upload failed at $(date +"%Y-%m-%d %H:%M:%S %Z")."

        exit 1
    fi
}

function clear_history() {
    if [[ "${BACKUP_KEEP_DAYS}" -gt 0 ]]; then
        for RCLONE_REMOTE_X in "${RCLONE_REMOTE_LIST[@]}"
        do
            color blue "delete ${BACKUP_KEEP_DAYS} days ago backup files $(color yellow "[${RCLONE_REMOTE_X}]")"

            if [[ "${RESTIC_ENABLE}" == "TRUE" ]]; then
                local RESTIC_COMMAND_X="${RESTIC_COMMAND} -r \"rclone:${RCLONE_REMOTE_X}\""
                
                eval "${RESTIC_COMMAND_X} forget --prune --keep-within \"${BACKUP_KEEP_DAYS}d\""
                if [[ $? != 0 ]]; then
                    color red "removing old snapshots failed"
                else
                    eval "${RESTIC_COMMAND_X} check"
                    if [[ $? != 0 ]]; then
                        color red "checking repository failed"
                    fi
                fi
            else
                mapfile -t RCLONE_DELETE_LIST < <(rclone ${RCLONE_GLOBAL_FLAG} lsf "${RCLONE_REMOTE_X}" --min-age "${BACKUP_KEEP_DAYS}d")

                for RCLONE_DELETE_FILE in "${RCLONE_DELETE_LIST[@]}"
                do
                    color yellow "deleting \"${RCLONE_DELETE_FILE}\""

                    rclone ${RCLONE_GLOBAL_FLAG} delete "${RCLONE_REMOTE_X}/${RCLONE_DELETE_FILE}"
                    if [[ $? != 0 ]]; then
                        color red "delete \"${RCLONE_DELETE_FILE}\" failed"
                    fi
                done
            fi
        done
    fi
}

color blue "running the backup program at $(date +"%Y-%m-%d %H:%M:%S %Z")"

init_env

send_notification "start" "Start backup at $(date +"%Y-%m-%d %H:%M:%S %Z")"

check_rclone_connection any

clear_dir
backup_init
backup
backup_package
upload
clear_dir
clear_history

send_notification "success" "The file was successfully uploaded at $(date +"%Y-%m-%d %H:%M:%S %Z")."

color none ""
