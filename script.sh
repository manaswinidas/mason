#!/usr/bin/env bash

BOOST_VERSION1="1.58.0"
BOOST_VERSION2="1_58_0"
BOOST_LIBRARY="regex"
BOOST_ARCH="x86"

if [[ $(uname -s) == 'Darwin' ]]; then
  BOOST_TOOLSET="darwin"
else
  BOOST_TOOLSET="gcc"
fi

MASON_NAME=boost_liball
MASON_VERSION=1.58.0
# this boost package has multiple libraries to we
# reference this empty file as a placeholder for all of them
MASON_LIB_FILE=lib/libboost_placeholder.txt

. ${MASON_DIR:-~/.mason}/mason.sh

function mason_load_source {
    mason_download \
        http://sourceforge.net/projects/boost/files/boost/1.58.0.beta.1/boost_1_58_0_b1.tar.bz2/download \
        c5091923813e319340d86cb52d94de96b21ed701

    export MASON_BUILD_PATH=${MASON_ROOT}/.build/boost_${BOOST_VERSION2}

    mason_extract_tar_bz2

    MASON_BUILD_PATH=${MASON_ROOT}/.build/boost_1_58_0_b1

}

function gen_config() {
  echo "using $1 : : $(which $2)" > user-config.jam
  if [[ "${AR:-false}" != false ]] || [[ "${RANLIB:-false}" != false ]]; then
      echo ' : ' >> user-config.jam
      if [[ "${AR:-false}" != false ]]; then
          echo "<archiver>${AR} " >> user-config.jam
      fi
      if [[ "${RANLIB:-false}" != false ]]; then
          echo "<ranlib>${RANLIB} " >> user-config.jam
      fi
  fi
  echo ' ;' >> user-config.jam
}

function mason_prepare_compile {
    ${MASON_DIR:-~/.mason}/mason install icu 54.1
    MASON_ICU=$(${MASON_DIR:-~/.mason}/mason prefix icu 54.1)
    BOOST_LDFLAGS="-L${MASON_ICU}/lib -licuuc -licui18n -licudata"
}

function write_python_config() {
# usage:
# write_python_config <user-config.jam> <version> <base> <variant>
PYTHON_VERSION=$2
# note: apple pythons need '/System'
PYTHON_BASE=$3
# note: python 3 uses 'm'
PYTHON_VARIANT=$4
if [[ ${UNAME} == 'Darwin' ]]; then
    echo "
      using python
           : ${PYTHON_VERSION} # version
           : ${PYTHON_BASE}/Library/Frameworks/Python.framework/Versions/${PYTHON_VERSION}/bin/python${PYTHON_VERSION}${PYTHON_VARIANT} # cmd-or-prefix
           : ${PYTHON_BASE}/Library/Frameworks/Python.framework/Versions/${PYTHON_VERSION}/include/python${PYTHON_VERSION}${PYTHON_VARIANT} # includes
           : ${PYTHON_BASE}/Library/Frameworks/Python.framework/Versions/${PYTHON_VERSION}/lib/python${PYTHON_VERSION}/config${PYTHON_VARIANT} # a lib actually symlink
           : <toolset>${BOOST_TOOLSET} # condition
           ;
    " >> $1
else
  if [[ ${UNAME} == 'FreeBSD' ]]; then
      echo "
        using python
             : ${PYTHON_VERSION} # version
             : /usr/local/bin/python${PYTHON_VERSION}${PYTHON_VARIANT} # cmd-or-prefix
             : /usr/local/include/python${PYTHON_VERSION} # includes
             : /usr/local/lib/python${PYTHON_VERSION}/config${PYTHON_VARIANT}
             : <toolset>${BOOST_TOOLSET} # condition
             ;
      " >> $1
  else
      echo "
        using python
             : ${PYTHON_VERSION} # version
             : /usr/bin/python${PYTHON_VERSION}${PYTHON_VARIANT} # cmd-or-prefix
             : /usr/include/python${PYTHON_VERSION} # includes
             : /usr/lib/python${PYTHON_VERSION}/config${PYTHON_VARIANT}
             : <toolset>${BOOST_TOOLSET} # condition
             ;
      " >> $1
  fi
fi
}

function mason_compile {
    if [[ -f ../../../patch.diff ]]; then
      patch -N -p0 < ../../../patch.diff
    else
      # patch to workaround crashes in python.input
      # https://github.com/mapnik/mapnik/issues/1968
      mason_step "Loading patch 'https://github.com/mapbox/mason/blob/${MASON_SLUG}/patch.diff'..."
      curl --retry 3 -s -f -# -L \
        https://raw.githubusercontent.com/mapbox/mason/${MASON_SLUG}/patch.diff \
        -O || (mason_error "Could not find patch for ${MASON_SLUG}" && exit 1)
      patch -N -p0 < ./patch.diff
    fi
    gen_config ${BOOST_TOOLSET} g++
    perl -i -p -e "s/\-march=i386/\-m64/g;" ./tools/build/v2/tools/gcc.jam
    write_python_config user-config.jam "2.7" "/System" ""
    if [[ ! -f ./b2 ]] ; then
        ./bootstrap.sh
    fi
    ./b2 \
        --with-regex \
        --with-system \
        --with-thread \
        --with-filesystem \
        --with-program_options \
        --with-python \
        --prefix=${MASON_PREFIX} \
        -j${MASON_CONCURRENCY} \
        -sHAVE_ICU=1 -sICU_PATH=${MASON_ICU} \
        linkflags="${BOOST_LDFLAGS}" \
        -d0 \
        --ignore-site-config --user-config=user-config.jam \
        architecture="${BOOST_ARCH}" \
        address-model=64 \
        toolset="${BOOST_TOOLSET}" \
        link=static \
        variant=release \
        install

        mkdir -p ${MASON_PREFIX}/lib/
        touch ${MASON_PREFIX}/lib/libboost_placeholder.txt
}

function mason_ldflags {
    echo "-lboost_regex -lboost_system -lboost_thread -lboost_filesystem -lboost_program_options -lboost_python"
}

function mason_clean {
    make clean
}

mason_run "$@"
