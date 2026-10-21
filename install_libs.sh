set -euo pipefail

# We build curl + openssl from source due to https://github.com/Unidata/netcdf4-python/issues/1179
# yum -y curl-devel

# perl is needed for openssl
yum -y install wget zlib-devel perl-IPC-Cmd bzip2-devel

build_openssl() {
    wget "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" --output-document="openssl-${OPENSSL_VERSION}.tar.gz"
    mkdir openssl
    tar zxf "openssl-${OPENSSL_VERSION}.tar.gz" --strip-components=1 --directory openssl

    pushd openssl
      ./config shared -fPIC shared --prefix=${BUILD_PREFIX} --libdir=lib
      make -j$(nproc)
      make install_sw install_ssldirs
    popd
}

build_curl() {
    flags="--prefix=${BUILD_PREFIX} --disable-ldap --with-openssl=${BUILD_PREFIX} --without-zstd --without-libpsl"
    wget "https://curl.haxx.se/download/curl-${CURL_VERSION}.tar.gz" --output-document="curl-${CURL_VERSION}.tar.gz"
    mkdir curl
    tar zxf curl-${CURL_VERSION}.tar.gz --strip-components=1 --directory curl
    pushd curl
      ./configure ${flags}
      make -j$(nproc)
      make install
    popd
}

build_libaec(){
    wget "https://github.com/Deutsches-Klimarechenzentrum/libaec/releases/download/v${AEC_VERSION}/libaec-${AEC_VERSION}.tar.gz" --output-document="libaec-${AEC_VERSION}.tar.gz"
    mkdir libaec
    tar zxf libaec-${AEC_VERSION}.tar.gz --strip-components=1 --directory libaec

    pushd libaec
      mkdir build
      cmake -S . -B build \
            -D CMAKE_BUILD_TYPE=Release \
            -D CMAKE_INSTALL_PREFIX="${BUILD_PREFIX}" \
            -D CMAKE_INSTALL_LIBDIR=lib \
            -D CMAKE_INSTALL_INCLUDEDIR=include \
            -D BUILD_STATIC_LIBS=OFF \
            -D BUILD_TESTING=OFF
      make -C build -j "$(nproc)"
      make -C build install
    popd
}

build_zstd(){
    wget "https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz" --output-document="zstd-${ZSTD_VERSION}.tar.gz"
    mkdir zstd
    tar zxf "zstd-${ZSTD_VERSION}.tar.gz" --strip-components=1 --directory zstd

    pushd zstd
      make install PREFIX=${BUILD_PREFIX}
    popd
}

build_blosc() {
    wget "https://github.com/Blosc/c-blosc/archive/refs/tags/v$BLOSC_VERSION.tar.gz" --output-document="c-blosc-$BLOSC_VERSION.tar.gz"
    mkdir c-blosc
    tar zxf "c-blosc-$BLOSC_VERSION.tar.gz" --strip-components=1 --directory c-blosc


    pushd c-blosc
      mkdir build && cd build
      #  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 to bypass incompatibility with cmake v4
      # until https://github.com/Blosc/c-blosc/issues/394 is closed.
      cmake -D CMAKE_BUILD_TYPE="Release" \
            -D CMAKE_INSTALL_PREFIX="${BUILD_PREFIX}" \
            -D CMAKE_INSTALL_LIBDIR=lib \
            -D CMAKE_INSTALL_INCLUDEDIR=include \
            -D CMAKE_POLICY_VERSION_MINIMUM=3.5 \
            -D PREFER_EXTERNAL_ZSTD=ON \
            -D CMAKE_POSITION_INDEPENDENT_CODE=1 \
            -D BUILD_STATIC=0 \
            -D BUILD_SHARED=1 \
            -D BUILD_TESTS=1 \
            -D BUILD_BENCHMARKS=0 \
            -D DEACTIVATE_SNAPPY=0 \
            -D PREFER_EXTERNAL_LZ4=ON \
            -D PREFER_EXTERNAL_ZLIB=ON \
            ..

      make -j$(nproc)
      make install
    popd
}

build_hdf5() {
    # This seems to be needed to find libsz.so.2
    ldconfig

    wget "https://github.com/HDFGroup/hdf5/archive/refs/tags/${HDF5_VERSION}.tar.gz" --output-document="${HDF5_VERSION}.tar.gz"
    mkdir hdf5
    tar zxf "${HDF5_VERSION}.tar.gz" --strip-components=1 --directory hdf5

    pushd hdf5
      mkdir build
      cmake -S . -B build \
            -D CMAKE_BUILD_TYPE=Release \
            -D CMAKE_INSTALL_PREFIX="${BUILD_PREFIX}" \
            -D CMAKE_INSTALL_LIBDIR=lib \
            -D BUILD_TESTING=OFF \
            -D BUILD_STATIC_LIBS=OFF \
            -D HDF5_BUILD_EXAMPLES=OFF \
            -D HDF5_BUILD_TOOLS=OFF \
            -D HDF5_BUILD_UTILS=OFF \
            -D HDF5_ALLOW_EXTERNAL_SUPPORT:STRING=NO \
            -D HDF5_ENABLE_ZLIB_SUPPORT=ON \
            -D HDF5_ENABLE_SZIP_SUPPORT=ON \
            -D H5_DEFAULT_PLUGINDIR="${BUILD_PREFIX}/lib/hdf5/plugin" \

      make -C build -j "$(nproc)"
      make -C build install
    popd

    # Needed by h5ls to find libhdf5.so.310
    ldconfig
}

build_netcdf() {
    wget "https://github.com/Unidata/netcdf-c/archive/refs/tags/v${NETCDF_VERSION}.tar.gz" --output-document="v${NETCDF_VERSION}.tar.gz"
    mkdir netcdf
    tar zxf "v${NETCDF_VERSION}.tar.gz" --strip-components=1 --directory netcdf

      cmake netcdf -B netcdf-build \
          -D CMAKE_BUILD_TYPE=Release \
          -D ENABLE_NETCDF4=on \
          -D NETCDF_ENABLE_HDF5=on \
          -D CMAKE_INSTALL_LIBDIR=lib \
          -D NETCDF_ENABLE_DAP=on \
          -D NETCDF_ENABLE_TESTS=off \
          -D BUILD_SHARED_LIBS=on \
          -D NETCDF_PLUGIN_INSTALL=ON \
          -D NETCDF_WITH_PLUGIN_DIR="${BUILD_PREFIX}/lib/hdf5/plugin"

      cmake --build netcdf-build \
            --target install
}

clean_up(){
  # Clean up to reduce the size of the Docker image.
  rm -rf hdf5/ \
         libaec/ \
         c-blosc/ \
         zstd/ \
         netcdf/ \
         *.tar.gz
  # Can't execute this with our own curl in the path.
  # yum -y erase wget zlib-devel perl-IPC-Cmd
}

pushd /tmp
build_openssl
build_curl
build_libaec
build_zstd
build_blosc
build_hdf5
build_netcdf
clean_up
popd
