#!/bin/bash

# ===============================
# GLOBALS
# ===============================
MODEL=""
MODELS=()
KSU_OPTION="n"
RECOVERY_OPTION="n"
DTB_OPTION="n"
CLEAN_BUILD=false
EXCLUDE_MODELS=()
ARGS_PROVIDED=false
TESTBUILD=false

# ===============================
# MODEL METADATA
# ===============================
declare -A MODEL_HUMAN=(
    [x1slte]="Galaxy S20"
    [x1s]="Galaxy S20 5G"
    [y2slte]="Galaxy S20+ (LTE)"
    [y2s]="Galaxy S20+ 5G"
    [z3s]="Galaxy S20 Ultra"
    [c1slte]="Galaxy N20 (LTE)"
    [c1s]="Galaxy N20"
    [c2slte]="Galaxy N20 Ultra lte"
    [c2s]="Galaxy N20 Ultra 5G"
    [r8s]="Galaxy S20 FE"
)

declare -A MODEL_ZIP_LABEL=(
    [x1slte]="s20"
    [x1s]="s20-5g"
    [y2slte]="s20-plus-lte"
    [y2s]="s20-plus-5g"
    [z3s]="s20-Ultra"
    [c1slte]="N20-lte"
    [c1s]="N20"
    [c2slte]="N20-Ultra-lte"
    [c2s]="N20-Ultra-5g"
    [r8s]="s20-FE"
)

declare -A MODEL_BOARD=(
    [x1slte]=SRPSJ28B018KU
    [x1s]=SRPSI19A018KU
    [y2slte]=SRPSJ28A018KU
    [y2s]=SRPSG12A018KU
    [z3s]=SRPSI19B018KU
    [c1slte]=SRPTC30B009KU
    [c1s]=SRPTB27D009KU
    [c2slte]=SRPTC30A009KU
    [c2s]=SRPTB27C009KU
    [r8s]=SRPTF26B014KU
)

ALL_DEVICES=(x1slte x1s y2slte y2s z3s c1slte c1s c2slte c2s r8s)

# ===============================
# ABORT
# ===============================
abort() {
    popd > /dev/null 2>&1
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║          ❌  COMPILATION FAILED  ❌              ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    exit 1
}

# ===============================
# USAGE
# ===============================
print_usage() {
    cat << EOF
Usage: $(basename "$0") [options]
Options:
    -m, --model [value]     Specify model code(s), comma-separated (e.g. x1s,y2s)
    -k, --ksu [y/N]         Include KernelSU (default: n)
    -r, --recovery [y/N]    Compile kernel for an Android Recovery (default: n)
    -d, --dtbs [y/N]        Compile only DTBs (default: n)
    -e, --exclude [model]   Exclude a model from batch build (repeatable)
    -c, --clean             Clean output before building
    -h, --help              Show this help message

    If no options are provided, an interactive prompt will guide you.
EOF
}

# ===============================
# CCACHE
# ===============================
setup_ccache() {
    if ! command -v ccache >/dev/null 2>&1; then
        echo "  ⚠  ccache not installed → skipping"
        return
    fi

    echo "  🚀 Enabling ccache..."

    export USE_CCACHE=1
    export CCACHE_COMPRESS=1
    export CCACHE_DIR="$HOME/.ccache"

    if [ ! -f "$CCACHE_DIR/.size_set" ]; then
        ccache -M 50G
        mkdir -p "$CCACHE_DIR"
        touch "$CCACHE_DIR/.size_set"
    fi
}

# ===============================
# FANCY BANNERS
# ===============================
print_build_start() {
    local model="$1"
    local human="${MODEL_HUMAN[$model]:-$model}"
    local idx="$2"
    local total="$3"

    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    printf "│  🔨  BUILD [%d/%d]  %-42s│\n" "$idx" "$total" ""
    printf "│       Model  : %-45s│\n" "$human"
    printf "│       Code   : %-45s│\n" "$model"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
}

print_build_success() {
    local model="$1"
    local zipname="$2"
    local elapsed="$3"
    local human="${MODEL_HUMAN[$model]:-$model}"

    echo ""
    echo "┌─────────────────────────────────────────────────────────────────────────────────┐"
    printf "│  ✅  BUILD COMPLETE %-60s│\n" ""
    printf "│       Device  : %-64s│\n" "$human"
    printf "│       Output  : %-64s│\n" "$zipname"
    printf "│       Time    : %-64s│\n" "${elapsed}s"
    echo "└─────────────────────────────────────────────────────────────────────────────────┘"
    echo ""
}

print_all_done() {
    local total="$1"
    local failed="$2"
    local elapsed="$3"

    echo ""
    echo "╔═════════════════════════════════════════════════════════════╗"
    if [[ "$failed" -eq 0 ]]; then
        printf "║  🎉  ALL DONE — %d/%d device(s) built successfully           %-1s║\n" "$total" "$total" ""
    else
        printf "║  ⚠️   DONE — %d/%d device(s) built, %d failed                %-1s║\n" $((total - failed)) "$total" "$failed" ""
    fi
    printf "║       Total time : %-41s║\n" "${elapsed}s"
    echo "╚═════════════════════════════════════════════════════════════╝"
    echo ""
}

# ===============================
# ARGS
# ===============================
if [[ $# -gt 0 ]]; then
    ARGS_PROVIDED=true
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model|-m)
            IFS=',' read -ra MODELS <<< "$2"; shift 2 ;;
        --ksu|-k)
            KSU_OPTION="$2"; shift 2 ;;
        --recovery|-r)
            RECOVERY_OPTION="$2"; shift 2 ;;
        --dtbs|-d)
            DTB_OPTION="$2"; shift 2 ;;
        --exclude|-e)
            EXCLUDE_MODELS+=("$2"); shift 2 ;;
        --clean|-c)
            CLEAN_BUILD=true; shift ;;
        --help|-h)
            print_usage; exit 0 ;;
        *)
            print_usage; exit 1 ;;
    esac
done

# ===============================
# INTERACTIVE PROMPT
# (only when no flags were passed)
# ===============================
prompt_options() {
    echo ""
    echo "╔═════════════════════════════════════════════════════════════╗"
    echo "║              Kernel Build Configuration                     ║"
    echo "╚═════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Available models:"
    echo "  ┌────┬──────────────┬────────────────────────────────┐"
    echo "  │  # │  Codename    │  Device                        │"
    echo "  ├────┼──────────────┼────────────────────────────────┤"
    echo "  │  0 │  ALL         │  Batch build all devices       │"
    echo "  ├────┼──────────────┼────────────────────────────────┤"
    echo "  │  1 │  x1slte      │  Galaxy S20 (LTE)    	       │"
    echo "  │  2 │  x1s         │  Galaxy S20  5G     	       │"
    echo "  │  3 │  y2slte      │  Galaxy S20+ (LTE)             │"
    echo "  │  4 │  y2s         │  Galaxy S20+ 5G                │"
    echo "  │  5 │  z3s         │  Galaxy S20 Ultra              │"
    echo "  │  6 │  c1slte      │  Galaxy N20 (LTE)              │"
    echo "  │  7 │  c1s         │  Galaxy N20 5G                 │"
    echo "  │  8 │  c2slte      │  Galaxy N20 Ultra (LTE)        │"
    echo "  │  9 │  c2s         │  Galaxy N20 Ultra 5G           │"
    echo "  │ 10 │  r8s         │  Galaxy S20 FE                 │"
    echo "  └────┴──────────────┴────────────────────────────────┘"
    echo ""
    echo "  💡 You can select multiple models: e.g.  1 3 5   or   1-4   or   0 for all"
    echo ""
    read -p "  Select model(s): " MODEL_INPUT

    MODELS=()

    for token in $MODEL_INPUT; do
        if [[ "$token" == *-* ]]; then
            start="${token%-*}"
            end="${token#*-}"
            for ((i=start; i<=end; i++)); do
                [[ "$i" -eq 0 ]] && MODELS=("${ALL_DEVICES[@]}") && break 2
                MODELS+=("$i")
            done
        else
            [[ "$token" -eq 0 ]] && MODELS=("${ALL_DEVICES[@]}") && break
            MODELS+=("$token")
        fi
    done

    # Test build prompt
    read -p "  Test build? (y/N): " TESTBUILD_INPUT
    [[ "${TESTBUILD_INPUT:-n}" == "y" ]] && TESTBUILD=true || TESTBUILD=false

    # Resolve numbers to codenames
    RESOLVED=()
    for m in "${MODELS[@]}"; do
        case "$m" in
            1)  RESOLVED+=(x1slte) ;;
            2)  RESOLVED+=(x1s) ;;
            3)  RESOLVED+=(y2slte) ;;
            4)  RESOLVED+=(y2s) ;;
            5)  RESOLVED+=(z3s) ;;
            6)  RESOLVED+=(c1slte) ;;
            7)  RESOLVED+=(c1s) ;;
            8)  RESOLVED+=(c2slte) ;;
            9)  RESOLVED+=(c2s) ;;
            10) RESOLVED+=(r8s) ;;
            x1slte|x1s|y2slte|y2s|z3s|c1slte|c1s|c2slte|c2s|r8s)
                RESOLVED+=("$m") ;;
            *)
                echo "  ⚠  Unknown selection: $m — skipping"
                ;;
        esac
    done
    MODELS=("${RESOLVED[@]}")

    if [[ ${#MODELS[@]} -eq 0 ]]; then
        echo "  No valid models selected. Exiting."
        exit 1
    fi

    echo ""
    read -p "  Include KernelSU? (y/N): " KSU_INPUT
    KSU_OPTION="${KSU_INPUT:-n}"

    echo ""
    read -p "  Build for Recovery? (y/N): " RECOVERY_INPUT
    RECOVERY_OPTION="${RECOVERY_INPUT:-n}"

    echo ""
    read -p "  Build DTBs only? (y/N): " DTB_INPUT
    DTB_OPTION="${DTB_INPUT:-n}"

    echo ""
    read -p "  Clean build? Wipes out/ before building (y/N): " CLEAN_INPUT
    [[ "${CLEAN_INPUT:-n}" == "y" ]] && CLEAN_BUILD=true

    echo ""
    echo "  ┌─────────────────────────────────────────────┐"
    echo "  │  Configuration Summary                      │"
    echo "  ├─────────────────────────────────────────────┤"
    printf "  │  Model(s)  : %-31s│\n" "${MODELS[*]}"
    printf "  │  KernelSU  : %-31s│\n" "$KSU_OPTION"
    printf "  │  Recovery  : %-31s│\n" "$RECOVERY_OPTION"
    printf "  │  DTBs only : %-31s│\n" "$DTB_OPTION"
    printf "  │  Clean     : %-31s│\n" "$CLEAN_BUILD"
    echo "  └─────────────────────────────────────────────┘"
    echo ""
    read -p "  Proceed? (Y/n): " CONFIRM
    [[ "${CONFIRM:-y}" == "n" ]] && echo "  Aborted." && exit 0
    echo ""
}

if [[ "$ARGS_PROVIDED" == false ]]; then
    prompt_options
fi

# ===============================
# BUILD FUNCTION
# ===============================
build_device() {

local MODEL="$1"
local KSU_OPTION="$2"
local RECOVERY_OPTION="$3"
local DTB_OPTION="$4"
local BUILD_IDX="$5"
local BUILD_TOTAL="$6"

local BUILD_START_TIME=$SECONDS

print_build_start "$MODEL" "$BUILD_IDX" "$BUILD_TOTAL"

pushd "$(dirname "$0")" > /dev/null || abort
CORES=$(nproc --all)

# ===============================
# TOOLCHAIN
# ===============================
CLANG_DIR=$PWD/toolchain/clang_14
PATH=$CLANG_DIR/bin:$PATH

if [ ! -f "$CLANG_DIR/bin/clang-14" ]; then
    echo "  -----------------------------------------------"
    echo "  Toolchain not found! Downloading..."
    echo "  -----------------------------------------------"
    rm -rf $CLANG_DIR
    mkdir -p $CLANG_DIR
    pushd $CLANG_DIR > /dev/null
    curl -LJOk https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/tags/android-13.0.0_r13/clang-r450784d.tar.gz
    tar xf android-13.0.0_r13-clang-r450784d.tar.gz
    rm android-13.0.0_r13-clang-r450784d.tar.gz
    echo "  Cleaning up..."
    popd > /dev/null
fi

setup_ccache

# ===============================
# MAKE ARGS (ccache if available)
# ===============================
if command -v ccache >/dev/null 2>&1; then
    MAKE_ARGS=(
        LLVM=1
        LLVM_IAS=1
        ARCH=arm64
        O=out/$MODEL
        CC="ccache clang"
        CXX="ccache clang++"
    )
else
    MAKE_ARGS=(
        LLVM=1
        LLVM_IAS=1
        ARCH=arm64
        O=out/$MODEL
    )
fi

# ===============================
# BOARD
# ===============================
BOARD="${MODEL_BOARD[$MODEL]}"
if [[ -z "$BOARD" ]]; then
    echo "  Unknown model: $MODEL"
    print_usage
    exit 1
fi

# ===============================
# KSU + RECOVERY + DTB CONFIG
# ===============================
KSU=""
RECOVERY=""
DTBS=""

if [[ "$RECOVERY_OPTION" == "y" ]]; then
    RECOVERY="recovery.config"
    KSU_OPTION="n"
fi

if [[ "$KSU_OPTION" == "y" ]]; then
    KSU="ksu.config"
fi

if [[ "$DTB_OPTION" == "y" ]]; then
    DTBS="y"
fi

# ===============================
# CLEAN
# ===============================
[[ "$CLEAN_BUILD" == true ]] && rm -rf out/$MODEL build/out/$MODEL
mkdir -p build/out/$MODEL/zip/files
mkdir -p build/out/$MODEL/zip/META-INF/com/google/android

# ===============================
# DEFCONFIG
# ===============================
echo "  ┌──────────────────────────────────────────────────┐"
printf "  │  Defconfig  : %-35s│\n" "exynos9830_defconfig + $MODEL.config"
printf "  │  KernelSU   : %-35s│\n" "$( [[ -n "$KSU" ]] && echo 'Yes' || echo 'No' )"
printf "  │  Recovery   : %-35s│\n" "$( [[ -n "$RECOVERY" ]] && echo 'Yes' || echo 'No' )"
printf "  │  DTBs only  : %-35s│\n" "$( [[ -n "$DTBS" ]] && echo 'Yes' || echo 'No' )"
echo "  └──────────────────────────────────────────────────┘"
echo ""

make "${MAKE_ARGS[@]}" -j$CORES exynos9830_defconfig "$MODEL.config" $KSU $RECOVERY || abort

# ===============================
# BUILD KERNEL / DTBs
# ===============================
if [[ -n "$DTBS" ]]; then
    echo "  Building DTBs..."
    echo "  -----------------------------------------------"
    make "${MAKE_ARGS[@]}" -j$CORES dtbs || abort
else
    echo "  Building kernel..."
    echo "  -----------------------------------------------"
    make "${MAKE_ARGS[@]}" -j$CORES || abort
    
    rm -rf build/out/$MODEL
    mkdir -p build/out/$MODEL
    cp out/$MODEL/arch/arm64/boot/Image build/out/$MODEL || abort
fi

# ===============================
# DTB / DTBO
# ===============================
echo "  -----------------------------------------------"
echo "  Building common exynos9830 DTB..."
./toolchain/mkdtimg cfg_create build/out/$MODEL/dtb.img \
    build/dtconfigs/exynos9830.cfg \
    -d out/$MODEL/arch/arm64/boot/dts/exynos || abort

echo "  Building DTBO for $MODEL..."
./toolchain/mkdtimg cfg_create build/out/$MODEL/dtbo.img \
    build/dtconfigs/$MODEL.cfg \
    -d out/$MODEL/arch/arm64/boot/dts/samsung || abort
echo "  -----------------------------------------------"

# ===============================
# RAMDISK + BOOT.IMG
# ===============================
if [[ -z "$RECOVERY" && -z "$DTBS" ]]; then

    KERNEL_PATH=build/out/$MODEL/Image
    RAMDISK=build/out/$MODEL/ramdisk.cpio.gz

    if [ ! -f "$RAMDISK" ]; then
        echo "  Building RAMDisk..."
        echo "  -----------------------------------------------"
        pushd build/ramdisk > /dev/null || abort
        find . ! -name . | LC_ALL=C sort | cpio -o -H newc -R root:root | gzip > ../out/$MODEL/ramdisk.cpio.gz || abort
        popd > /dev/null
        echo "  -----------------------------------------------"
    fi

    echo "  Creating boot image..."
    echo "  -----------------------------------------------"
    ./toolchain/mkbootimg \
        --base 0x10000000 \
        --board $BOARD \
        --cmdline "androidboot.hardware=exynos990 loop.max_part=7" \
        --dtb build/out/$MODEL/dtb.img \
        --dtb_offset 0x00000000 \
        --hashtype sha1 \
        --header_version 2 \
        --kernel $KERNEL_PATH \
        --kernel_offset 0x00008000 \
        --os_patch_level 2025-08 \
        --os_version 15.0.0 \
        --pagesize 2048 \
        --ramdisk $RAMDISK \
        --ramdisk_offset 0x01000000 \
        --second_offset 0xF0000000 \
        --tags_offset 0x00000100 \
        --output build/out/$MODEL/boot.img || abort

fi

# ===============================
# ZIP PACKAGING
# ===============================
if [[ -z "$DTBS" ]]; then
    echo "  Building zip..."
    echo "  -----------------------------------------------"

    ZIP_DIR=build/out/$MODEL/zip
    rm -rf "$ZIP_DIR"
    mkdir -p "$ZIP_DIR/files"
    mkdir -p "$ZIP_DIR/META-INF/com/google/android"

    if [[ -z "$RECOVERY" ]]; then
        cp build/out/$MODEL/boot.img "$ZIP_DIR/files/" || abort
    fi

    cp build/out/$MODEL/dtbo.img "$ZIP_DIR/files/" || abort
    cp build/update-binary "$ZIP_DIR/META-INF/com/google/android/" 2>/dev/null
    cp build/updater-script "$ZIP_DIR/META-INF/com/google/android/" 2>/dev/null

    # ===============================
    # ZIP NAME
    # Format: <zip_label>_<codename>_<localversion>_<KSU|NON-KSU>.zip
    # Example: s20-ultra_x1s_extreme-v1_KSU_16-04-2026--14-30-00.zip
    # ===============================
    version=$(grep -o 'CONFIG_LOCALVERSION="[^"]*"' arch/arm64/configs/exynos9830_defconfig | cut -d '"' -f 2)
    version="${version#-}"

    ZIP_LABEL="${MODEL_ZIP_LABEL[$MODEL]:-$MODEL}"

    if [[ "$KSU_OPTION" == "y" ]]; then
        SUFFIX="KSU"
    else
        SUFFIX="NON-KSU"
    fi

    if [[ "$TESTBUILD" == true ]]; then
        NAME="${ZIP_LABEL}_${MODEL}_TESTBUILD_${version}_${SUFFIX}.zip"
    else
        NAME="${ZIP_LABEL}_${MODEL}_${version}_${SUFFIX}.zip"
    fi

    pushd "$ZIP_DIR" > /dev/null || abort
    zip -r -qq "../$NAME" . || abort
    popd > /dev/null
fi

local ELAPSED=$(( SECONDS - BUILD_START_TIME ))
print_build_success "$MODEL" "${NAME:-DTBs only}" "$ELAPSED"

popd > /dev/null || abort
}

# ===============================
# MAIN LOOP
# ===============================

# If no models selected via args, resolve single --model or batch all
if [[ ${#MODELS[@]} -eq 0 && -z "$MODEL" ]]; then
    MODELS=("${ALL_DEVICES[@]}")
elif [[ ${#MODELS[@]} -eq 0 && -n "$MODEL" ]]; then
    IFS=',' read -ra MODELS <<< "$MODEL"
fi

# Apply exclude list
FINAL_MODELS=()
for DEVICE in "${MODELS[@]}"; do
    SKIP=false
    for EXCLUDED in "${EXCLUDE_MODELS[@]}"; do
        [[ "$DEVICE" == "$EXCLUDED" ]] && SKIP=true && break
    done
    [[ "$SKIP" == true ]] && echo "  ⏭  Skipping $DEVICE (excluded)" && continue
    FINAL_MODELS+=("$DEVICE")
done

TOTAL=${#FINAL_MODELS[@]}
FAILED=0
OVERALL_START=$SECONDS

if [[ $TOTAL -eq 0 ]]; then
    echo "  No models to build. Exiting."
    exit 1
fi

for i in "${!FINAL_MODELS[@]}"; do
    IDX=$(( i + 1 ))
    DEVICE="${FINAL_MODELS[$i]}"
    build_device "$DEVICE" "$KSU_OPTION" "$RECOVERY_OPTION" "$DTB_OPTION" "$IDX" "$TOTAL" || {
        FAILED=$(( FAILED + 1 ))
        echo "  ❌ Failed to build $DEVICE — continuing with next..."
        sleep 1
    }
    [[ $IDX -lt $TOTAL ]] && sleep 2
done

OVERALL_ELAPSED=$(( SECONDS - OVERALL_START ))
print_all_done "$TOTAL" "$FAILED" "$OVERALL_ELAPSED"

[[ $FAILED -gt 0 ]] && exit 1 || exit 0
