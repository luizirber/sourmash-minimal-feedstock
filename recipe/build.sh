#!/bin/bash -euo

set -ex
set -o xtrace -o nounset -o pipefail -o errexit

# https://github.com/rust-lang/cargo/issues/10583#issuecomment-1129997984
export CARGO_NET_GIT_FETCH_WITH_CLI=true

###################
# Prepare licenses
###################

pushd src/core
# Bundle all downstream library licenses
cargo-bundle-licenses \
    --format yaml \
    --output ${SRC_DIR}/THIRDPARTY.yml
popd

if [[ "$target_platform" == "linux-ppc64le" ]]; then
  # From https://conda-forge.zulipchat.com/#narrow/channel/457337-general/topic/ppc64le.20issues/near/576500347
  # disable -fno-plt, which causes problems with GCC on PPC
  CFLAGS="$(echo $CFLAGS | sed 's/-fno-plt //g')"
  CXXFLAGS="$(echo $CXXFLAGS | sed 's/-fno-plt //g')"
  # From https://github.com/conda-forge/rattler-build-feedstock/blob/504fd2e977d6597d2c83332a3e7f0fce023b1d25/recipe/recipe.yaml#L38-L39
  # Rust 1.90 uses lld by default and has issue linking to conda libraries
  # compiled with newer gcc
  set +u
  RUSTFLAGS="$RUSTFLAGS -C link-arg=-fuse-ld=bfd"
  set -u
fi

####################
# Build shared lib
####################
SOEXT=so
if [ "$(uname)" == "Darwin" ]; then
    SOEXT=dylib
fi

cp include/sourmash.h ${PREFIX}/include/

cargo build --release --features branchwater

cp -a target/${CARGO_BUILD_TARGET}/release/libsourmash.${SOEXT} ${PREFIX}/lib/
cp -a target/${CARGO_BUILD_TARGET}/release/libsourmash.a ${PREFIX}/lib/

mkdir -p ${PREFIX}/lib/pkgconfig
cat > ${PREFIX}/lib/pkgconfig/sourmash.pc <<"EOF"
prefix=/usr/local
exec_prefix=${prefix}
includedir=${prefix}/include
libdir=${exec_prefix}/lib

Name: sourmash
Description: Compute MinHash signatures for nucleotide (DNA/RNA) and protein sequences.
Version: 0.11.0
Cflags: -I${includedir}
Libs: -L${libdir} -lsourmash
EOF

#########################
# Install python package
#########################

# Run the maturin build via pip which works for direct and
# cross-compiled builds.
$PYTHON -m pip install . -vv
