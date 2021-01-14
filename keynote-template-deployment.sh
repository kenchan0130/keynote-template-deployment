#!/bin/zsh -e
#######################################
# Deploy a Keynote app template programmatically.
# Arguments:
#   $1: Keynote template URL
#       Remote file e.g.) https://example.com/theme.kth
#       Local file e.g.) file:///tmp/theme.kth
#   $2: Display Name on theme selector
#   $3: Type of specify the local users to be deployed
#       - current
#       - all
#######################################

VERSION='0.1.0'
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

# MARK: Functions

#######################################
# Run arguments as current user.
# Globals:
#   LOCAL_USER
# Arguments:
#   $@: Script to run
#######################################
run_as_user() {
  local uid
  if [[ "$(whoami)" == "${LOCAL_USER}" ]];then
    "$@"
  else
    uid=$(id -u "${LOCAL_USER}")
    launchctl asuser "${uid}" sudo -u "${LOCAL_USER}" "$@"
  fi
}

#######################################
# Output info log with timestamp.
# Arguments:
#   $@: Script to run
# Outputs:
#   Writes a argument with timestamp to stdout
#######################################
print_info_log(){
  local timestamp
  timestamp=$(date +%F\ %T)

  echo "$timestamp [INFO] $1"
}

#######################################
# Output error log with timestamp.
# Arguments:
#   $@: Script to run
# Outputs:
#   Writes a argument with timestamp to stdout
#######################################
print_error_log(){
  local timestamp
  timestamp=$(date +%F\ %T)

  echo "$timestamp [ERROR] $1"
}

# MARK: Main script

# Check for the existence of Keynote application
if [[ ! -e "/Applications/Keynote.app" ]];then
  print_error_log "It seems that the Keynote application is not installed. Please install it and try again."
  exit 1
fi

if [[ "${1}" = "/" ]];then
	# Jamf uses sends '/' as the first argument
  print_info_log "Shifting arguments for Jamf."
  shift 3
fi

if [[ "${1:l}" = "version" ]];then
  echo "${VERSION}"
  exit 0
fi

if [[ ! "${1}" ]];then
  print_error_log "You need to set Keynote template file location."
  exit 1
fi
KEYNOTE_TEMPLATE_FILE_PATH="${1}"

if [[ ! "${2}" ]];then
  print_error_log "You need to set Keynote template display name."
  exit 1
fi
KEYNOTE_TEMPLATE_DISPLAY_NAME="${2}"

if [[ ! "${3:-current}" =~ "^(current|all)$" ]];then
  print_error_log "You need to set type of specify the local users to be deployed. 'current' or 'all'"
  exit 1
fi
DEPLOY_USER_TYPE="${3:-current}"

if [[ "${DEPLOY_USER_TYPE}" == "current" ]];then
  LOCAL_USER_LIST=($(stat -f%Su /dev/console))
else
  LOCAL_USER_LIST=$(dscl . list /Users UniqueID | awk '$2 > 500 && $2 < 999 {print $1}')
fi

# Check for the existence of local users
if [[ "${#LOCAL_USER_LIST}" -eq 0 ]];then
  print_info_log "This device has no local users."
  exit 0
fi

TMP_WORKING_DIRECTORY=$(mktemp -d)
TMP_DOWNLOAD_PATH="${TMP_WORKING_DIRECTORY%/}/$(uuidgen)"
PREVIEW_IMAGE_FILE_NAME="preview.jpg"
TMP_PREVIEW_IMAGE_FILE_PATH="${TMP_WORKING_DIRECTORY%/}/${PREVIEW_IMAGE_FILE_NAME}"
TMP_DOCUMENT_IDENTIFIER_NAME="Metadata/DocumentIdentifier"
TMP_DOCUMENT_IDENTIFIER_FILE_PATH="${TMP_WORKING_DIRECTORY%/}/${TMP_DOCUMENT_IDENTIFIER_NAME}"

print_info_log "Start Keynote template deplyment..."

print_info_log "Download Keynote template from ${KEYNOTE_TEMPLATE_FILE_PATH}..."
curl -fL "${KEYNOTE_TEMPLATE_FILE_PATH}" -o "${TMP_DOWNLOAD_PATH}"

if [[ ! -s "${TMP_DOWNLOAD_PATH}" ]];then
  print_error_log "${KEYNOTE_TEMPLATE_FILE_PATH} is not found or empty."
  exit 1
fi

print_info_log "Extract a Keynote template preview image and identifier..."
unzip -q "${TMP_DOWNLOAD_PATH}" "${PREVIEW_IMAGE_FILE_NAME}" -d "${TMP_WORKING_DIRECTORY}"
unzip -q "${TMP_DOWNLOAD_PATH}" "${TMP_DOCUMENT_IDENTIFIER_NAME}" -d "${TMP_WORKING_DIRECTORY}"

if [[ ! -s "${TMP_PREVIEW_IMAGE_FILE_PATH}" ]] || [[ ! -s "${TMP_DOCUMENT_IDENTIFIER_FILE_PATH}" ]];then
  print_error_log "${KEYNOTE_TEMPLATE_FILE_PATH} may not be Keynote template file."
  exit 1
fi

KEYNOTE_TEMPLATE_ID="CloudKit/$(cat "${TMP_DOCUMENT_IDENTIFIER_FILE_PATH}")"

for LOCAL_USER in "${LOCAL_USER_LIST[@]}";do
  print_info_log "Deploy Keynote template for ${LOCAL_USER}..."

  LOCAL_USER_HOME_DIRECTORY=$(dscl /Local/Default read "/Users/${LOCAL_USER}" NFSHomeDirectory | awk '{print $2}')
  LOCAL_USER_GROUP_NAME=$(stat -f "%Sg" "${LOCAL_USER_HOME_DIRECTORY}")

  KEYNOTE_TEMPLAETE_DIRECTORY="${LOCAL_USER_HOME_DIRECTORY%/}/Library/Containers/com.apple.iWork.Keynote/Data/Library/Application Support/User Templates"
  KEYNOTE_TEMPLAETE_FILE_PATH="${KEYNOTE_TEMPLAETE_DIRECTORY}/${KEYNOTE_TEMPLATE_DISPLAY_NAME}.kth"

  # Deploy Keynote template to User Templates directory of Keynote app
  print_info_log "Deploy template file to ${KEYNOTE_TEMPLAETE_FILE_PATH}..."
  mkdir -p "${KEYNOTE_TEMPLAETE_DIRECTORY}"
  cp "${TMP_DOWNLOAD_PATH}" "${KEYNOTE_TEMPLAETE_FILE_PATH}"
  chown "${LOCAL_USER}:${LOCAL_USER_GROUP_NAME}" "${KEYNOTE_TEMPLAETE_FILE_PATH}"

  KEYNOTE_PREVIEW_IMAGE_NAME=$(uuidgen)
  KEYNOTE_PREVIEW_IMAGE_DIRECTORY="${LOCAL_USER_HOME_DIRECTORY%/}/Library/Containers/com.apple.iWork.Keynote/Data/Library/Application Support/com.apple.iWork.CloudKitStorage/data"
  KEYNOTE_PREVIEW_IMAGE_FILE_PATH="${KEYNOTE_PREVIEW_IMAGE_DIRECTORY%/}/${KEYNOTE_PREVIEW_IMAGE_NAME}"

  # Deploy Keynote template preview image to com.apple.iWork.CloudKitStorage/data directory of Keynote app
  print_info_log "Deploy template preivew image to ${KEYNOTE_PREVIEW_IMAGE_FILE_PATH}..."
  mkdir -p "${KEYNOTE_PREVIEW_IMAGE_DIRECTORY}"
  cp "${TMP_PREVIEW_IMAGE_FILE_PATH}" "${KEYNOTE_PREVIEW_IMAGE_FILE_PATH}"
  chown "${LOCAL_USER}:${LOCAL_USER_GROUP_NAME}" "${KEYNOTE_PREVIEW_IMAGE_FILE_PATH}"

  DB_PATH="${LOCAL_USER_HOME_DIRECTORY%/}/Library/Containers/com.apple.iWork.Keynote/Data/Library/Application Support/com.apple.iWork.CloudKitStorage/com.apple.iWork.TSKCloudKitPrivateZone.db"

  # Delete settings data from the same existing Keynote template
  print_info_log "Delete tempalte file, preview image file and ${KEYNOTE_TEMPLATE_ID} records from TSACloudKitTemplateItem and TSACloudKitTemplateItem_stale table in ${DB_PATH}..."
  run_as_user sqlite3 "${DB_PATH}" "SELECT previewImage FROM TSACloudKitTemplateItem WHERE identifier = '${KEYNOTE_TEMPLATE_ID}'" | xargs -I{} basename {} | xargs -I{} rm -rf "${KEYNOTE_PREVIEW_IMAGE_DIRECTORY%/}/{}"
  run_as_user sqlite3 "${DB_PATH}" "SELECT file FROM TSACloudKitTemplateItem WHERE identifier = '${KEYNOTE_TEMPLATE_ID}'" | xargs -I{} basename {} | xargs -I{} rm -rf "${KEYNOTE_TEMPLAETE_DIRECTORY%/}/{}"
  run_as_user sqlite3 "${DB_PATH}" "DELETE FROM TSACloudKitTemplateItem WHERE identifier = '${KEYNOTE_TEMPLATE_ID}'"
  run_as_user sqlite3 "${DB_PATH}" "DELETE FROM TSACloudKitTemplateItem_stale WHERE identifier = '${KEYNOTE_TEMPLATE_ID}'"

  # Insert settings data of Keynote template
  print_info_log "Insert a ${KEYNOTE_TEMPLATE_ID} record to TSACloudKitTemplateItem and TSACloudKitTemplateItem_stale in ${DB_PATH}..."
  run_as_user sqlite3 "${DB_PATH}" "INSERT INTO TSACloudKitTemplateItem (identifier, needs_first_fetch, displayName, previewImage, TSKCloudKitAssetVersion_previewImage, file, TSKCloudKitAssetVersion_file, originatingDeviceName) VALUES ('${KEYNOTE_TEMPLATE_ID}', 0, '${KEYNOTE_TEMPLATE_DISPLAY_NAME}', '<NSApplicationSupportDirectory>/com.apple.iWork.CloudKitStorage/data/${KEYNOTE_PREVIEW_IMAGE_NAME}', 1, '<NSApplicationSupportDirectory>/User Templates/${KEYNOTE_TEMPLATE_DISPLAY_NAME}.kth', 1, '$(hostname -s)')"
  run_as_user sqlite3 "${DB_PATH}" "INSERT INTO TSACloudKitTemplateItem_stale (identifier, stale, TSKCloudKitAssetVersion_previewImage, TSKCloudKitAssetVersion_file) VALUES ('${KEYNOTE_TEMPLATE_ID}', 0, 1, 1)"

  print_info_log "Successfully deploy ${KEYNOTE_TEMPLATE_DISPLAY_NAME} Keynote template to ${LOCAL_USER}."
done

print_info_log "Clean a temporary directory..."
rm -rf "${TMP_WORKING_DIRECTORY}"

exit 0
