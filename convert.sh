#!/bin/env bash
# Convert script written by affggh
# https://github.com/affggh

# if some command exit code not equal to 0
# then exit
set -e

# Do not edit this
BINDIR="$(readlink -f "$(dirname $0)/bin")"
TMPDIR="$(readlink -f "$(dirname $0)/tmp")"

. ./settings.conf

# If on windows, pad commands with .exe
if [ "Windows_NT" == "$(uname -s)" ]; then
    EXT=".exe"
else
    EXT=""
fi

# Define commands alias
alias p7z="$BINDIR/7z$EXT"
if [ "Windows_NT" == "$(uname -s)" ]; then
    alias node="$BINDIR/node$EXT"
fi
alias magiskboot="node $BINDIR/magiskboot.js"

if [ "Windows_NT" == "$(uname -s)" ]; then
    alias python="$BINDIR/python-3.13.0-embed-amd64/python.exe"
fi
alias sdat2img="python $BINDIR/sdat2img.py"
alias img2sdat="python $BINDIR/img2sdat" # This is a dir

alias resize2fs="$BINDIR/resize2fs$EXT"
alias brotli="$BINDIR/brotli$EXT"

alias simg2img="$BINDIR/simg2img$EXT"
alias img2simg="$BINDIR/img2simg$EXT"

alias skip_verity="python $BINDIR/skip_verity.py"

# 定义颜色代码
COLOR_RESET='\033[0m'
COLOR_INFO='\033[0;92m'    # 亮绿色
COLOR_WARNING='\033[0;93m' # 亮黄色
COLOR_ERROR='\033[0;91m'   # 亮红色

# 日志函数
log() {
    local level="$1"
    shift
    local timestamp="$(date +"[%H:%M:%S] ")"
    local message="$*"

    case "$level" in
    info)
        echo -e "${COLOR_INFO}${timestamp}[INFO] ${message}${COLOR_RESET}"
        ;;
    warning)
        echo -e "${COLOR_WARNING}${timestamp}[WARNING] ${message}${COLOR_RESET}"
        ;;
    error)
        echo -e "${COLOR_ERROR}${timestamp}[ERROR] ${message}${COLOR_RESET}"
        ;;
    *)
        echo "${timestamp}[UNKNOWN] $message"
        ;;
    esac
}

logi() {
    log info $@
}

logw() {
    log warning $@
}

loge() {
    log error $@
}

abort() {
    loge $@
    exit 1
}

decompress() {
    local SRC="$1"
    local DEST="$2"

    logi "Decompress flashable zip from $SRC -> $DEST ..."

    p7z x -o"$DEST" "$SRC" -y || abort "Failed!"

    logi "Done!"
}

compress() {
    local DIR="$1"
    local OUT="$2"

    local ABS_DIR="$(readlink -f "$DIR")"
    local ABS_OUT="$(readlink -f "$OUT")"

    logi "Repacking flashable zip ..."
    local CURRENT_DIR="$(pwd)"

    cd "$ABS_DIR"
    p7z a -tZIP "$ABS_OUT" "./*"
    cd "$CURRENT_DIR"

    logi "Done!"
    logi "Your flashable zip saved at: $ABS_OUT"
}

convert() {
    local INPUT_ZIP="$1"

    logi "Converting... $INPUT_ZIP to r7plusm/r7splus"

    if [ ! -d "$TMPDIR" ]; then
        mkdir -p "$TMPDIR"
    else
        rm -rf "$TMPDIR"
        mkdir -p "$TMPDIR"
    fi

    decompress "$INPUT_ZIP" "$TMPDIR"

    local FORMAT_DAT_BR=false
    if [ -f "$TMPDIR/system.new.dat.br" ]; then
        logi "Detect brotli compressed system, decompressing..."
        brotli -d "$TMPDIR/system.new.dat.br" || abort "Brotli decompress failed!"
        FORMAT_DAT_BR=true
        logi "Done!"
        rm -f "$TMPDIR/system.new.dat.br"
        logi "Delete old file"
    fi

    local FORMAT_DAT=false
    if [ -f "$TMPDIR/system.new.dat" ]; then
        logi "Detect sdat format system, decompressing..."
        sdat2img "$TMPDIR/system.transfer.list" \
            "$TMPDIR/system.new.dat" \
            "$TMPDIR/system.img" || abort "Sdat2img convert failed!"
        FORMAT_DAT=true
        logi "Done!"
        rm -f "$TMPDIR/system.new.dat"
        logi "Delete old file"
    fi

    if [ -f "$TMPDIR/system.img" ]; then
        logi "Resize system image :$RESIZE_SIZE ..."
        resize2fs -f "$TMPDIR/system.img" $RESIZE_SIZE || abort "Failed!"
        logi "Done!"
    else
        abort "System image not exist, something went wrong!"
    fi

    if [ -f "$TMPDIR/boot.img" ]; then
        logi "Use magiskboot resign boot image with google test key ..."
        magiskboot sign "$TMPDIR/boot.img" || abort "Failed!"
        magiskboot sign "$TMPDIR/boot.img" || abort "Failed!"
        logi "Done!"
    else
        logw "Could not find boot.img to sign, maybe bootloop"
    fi

    if [ "$FORMAT_DAT" == "true" ]; then
        # Force VERSION==4 android 7+
        logi "Convert back system image to dat format ..."
        logi "Use img2sdat version: $SDAT_VERSION ..."
        logi "Convert raw image into sparse image ..."
        img2simg "$TMPDIR/system.img" "$TMPDIR/system_sparse.img"
        rm -f "$TMPDIR/system.img"
        logi "Done!"

        logi "Convert sparse image to sdat ..."
        img2sdat -o "$TMPDIR" -p "system" -v "$SDAT_VERSION" "$TMPDIR/system_sparse.img" || abort "Failed!"
        logi "Done!"
        rm -f "$TMPDIR/system_sparse.img"
    fi

    if [ "$FORMAT_DAT_BR" == "true" ]; then
        logi "Convert back system.new.dat to br compressed format ..."
        logi "Compress level: $BROTLI_COMPRESS_LEVEL"
        brotli -j -q "$BROTLI_COMPRESS_LEVEL" "$TMPDIR/system.new.dat" -o "$TMPDIR/system.new.dat.br" || abort "Failed!"
        logi "Done!"
    fi

    if [ -f "$TMPDIR/META-INF/com/google/android/updater-script" ]; then
        logi "Try replace flash script asset ..."
        skip_verity "$TMPDIR/META-INF/com/google/android/updater-script"
        logw "This may not work, if flash failed, try edit flash script by yourself!"
    fi

    compress "$TMPDIR" "$(echo -e "$INPUT_ZIP" | sed s/\.zip/\_converted\.zip/)"

    logi "Everything seems to be done!"
}

convert $@
