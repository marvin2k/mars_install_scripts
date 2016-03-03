##############################
# helper functions
##############################

function printBold {
  if $MSYS
    then
      echo -ne "\033[32;1m"
      echo -n "$@"
      echo -e "\033[0m"
      echo
    else
      echo -ne "\033[32;1m"
      echo -n "$@"
      echo -e "\033[0m"
  fi
}

function printErr {
  if $MSYS
    then
      echo -e "\033[31;1m"
      echo -n "Error: $@"
      echo -e "\033[0m"
      echo
    else
      echo -e "\033[31;1m"
      echo "Error: $@"
      echo -e "\033[0m"
  fi
}

function forAllPackagesDo {
    handledPackages=""
    action=$1
    setScriptDir
    if [[ ! -f ${MARS_SCRIPT_DIR}/${PACKAGE_FILE} ]]; then
        p="${last_clean}_path"
        if [[ x${!p} = x ]]; then
            printErr "No ${PACKAGE_FILE} found"
            return 1
        else
            handlePackage ${action} ${PACKAGE_FILE}
            return 0
        fi
    fi
#    for package in $(cat ${MARS_SCRIPT_DIR}/${PACKAGE_FILE}); do
    while read package; do
        handlePackage ${action} ${package}
    if [[ x${MARS_SCRIPT_ERROR} != x && ${MARS_SCRIPT_ERROR} != 0 ]]; then
        # clear script error
        MARS_SCRIPT_ERROR=0
        return 1;
    fi
    done < ${MARS_SCRIPT_DIR}/${PACKAGE_FILE}
#    done
}


function handlePackage {
    action=$1
    package=$2

    # remove leading and trailing whitespaces
    read -rd '' package <<< "${package}"
    # remove everything after comment character (#)
    package=${package/\#*/}
    if [[ x${package} = x ]]; then
        continue
    fi
    # replace dash (-) by underscore (_) for function call
    # leave unchanged for generic version
    package_clean=${package//-/_}
    p="${package_clean}_path"

    p_folder="${package_clean}_folder"
    if [[ x${!p_folder} = x ]]; then
        p_folder=${package}
    else
        p_folder=${!p_folder}
    fi

    p_fetch="${package_clean}_fetch_path"
    if [[ x${!p_fetch} = x ]]; then
        p_fetch=${!p}/${package}
    else
        p_fetch=${!p_fetch}
    fi
    p_read="${package_clean}_read_address"

    p_write="${package_clean}_write_address"
    if [[ x${!p_write} = x ]]; then
        p_write=${p_read}
    fi

    p_cmake_options="${package_clean}_cmake_options"

    if type -t ${action}_${package_clean##*/} | grep -q 'function'; then
        ${action}_${package_clean##*/} ${!p}
    else
        if [[ x${!p} = x ]]; then
            if [ ${action} = "fetch" ] || [ ${action} = "update" ] || [ ${action} = "diff" ]; then
                handle="y"
                IFS=' '
                set -f
                for line in ${handledPackages}; do
                    if [[ ${line} == "simulation/mars" ]]; then
                        handle="n"
                        break
                    fi
                done
                set +f
                unset IFS

                if [[ ${handle} = "y" ]]; then
                    ${action}_package "mars" "simulation/mars" "https://github.com/rock-simulation/mars.git" "https://github.com/rock-simulation/mars.git"
                    handledPackages+="simulation/mars"
                    handledPackages+=" "
                fi
            else
                ${action}_package ${package} "simulation" ${p_folder}
            fi
        else
            if [ ${action} = "fetch" ] || [ ${action} = "update" ] || [ ${action} = "diff" ]; then
                handle="y"
                IFS=' '
                set -f
                for line in ${handledPackages}; do
                    if [[ ${line} == ${p_fetch} ]]; then
                        handle="n"
                        break
                    fi
                done
                set +f
                unset IFS

                if [[ ${handle} = "y" ]]; then
                    ${action}_package ${package} ${p_fetch} "${!p_read}" "${!p_write}"
                    handledPackages+=${p_fetch}
                    handledPackages+=" "
                fi
            else
                ${action}_package ${package} ${!p} ${p_folder} ${!p_cmake_options}
            fi
        fi
    fi
    if [[ x${MARS_SCRIPT_ERROR} != x && ${MARS_SCRIPT_ERROR} != 0 ]]; then
        printErr "There was an Error. Please check the above output for more information"
        return 1;
    fi
}


#############################
# environment functions
#############################

function setScriptDir {
    if [[ x"${MARS_SCRIPT_DIR}" == "x" ]]; then
        MARS_SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
    fi
    export MARS_SCRIPT_DIR=${MARS_SCRIPT_DIR}
}


function setupConfig {
    configFile=${MARS_SCRIPT_DIR}/config.txt
    devDir=${MARS_SCRIPT_DIR%/*}
    if [[ "${MARS_SCRIPT_DIR%/*}" == *"bootstrap"* ]]; then
        devDir=${MARS_SCRIPT_DIR%/*/*}
    fi

    if [[ x${MARS_DEV_ROOT} == x ]]; then
        if [[ ! -a ${configFile} ]]; then
            echo "You must set a root directory where all repositories will be checked out and all packages will be installed"
            echo "On Windows you should use the mingw path and not the windows path and avoid trailing slashes (e.g. /c/dev/mars-git)"
            echo -n "Enter root directory or nothing for \"$devDir\": "
            read MARS_DEV_ROOT
            if [[ x${MARS_DEV_ROOT} = x ]]; then
                MARS_DEV_ROOT=${devDir}
            else
                # expand ~ by using eval
                eval MARS_DEV_ROOT=${MARS_DEV_ROOT}
            fi
            echo "MARS_DEV_ROOT=\"${MARS_DEV_ROOT}\"" > ${configFile}
            echo "You can specify the number of CORES you want to use when compiling packages."
            echo -n "Enter number of CORES: "
            read CORES || return 1
            pattern='^[1-9][0-9]*$'
            if ! [[ ${CORES} =~ ${pattern} ]]; then
                printBold "error parsing number of CORES using default (6)"
                CORES=6
            fi
            echo "CORES=${CORES}" >> ${configFile}
            echo -n "Enter build type (debug|release) : "
            read BUILD_TYPE || return 1
            pattern='debug|release'
            if ! [[ ${BUILD_TYPE} =~ ${pattern} ]]; then
                printBold "error parsing built type. Using default (debug)"
                BUILD_TYPE=debug
            fi
            echo "BUILD_TYPE=${BUILD_TYPE}" >> ${configFile}
        else
            source ${configFile}
        fi
    fi
    mkdir -p ${MARS_DEV_ROOT}
}


function setup_env {
    pushd . > /dev/null 2>&1
    platform='unknown'

    # detect if we are in msys
    if [ "${WINDIR}" = "" ]; then
        MSYS=false
        unamestr=`uname`
        if [[ "${unamestr}" == 'Linux' ]]; then
        platform='linux'
        elif [[ "${unamestr}" == 'Darwin' ]]; then
        platform='darwin'
        fi
    else
        MSYS=true
        platform='windows'
    fi

    export MSYS=${MSYS}

    setupConfig
    setScriptDir
    prefix=${MARS_DEV_ROOT}/install
    prefix_bin=${prefix}/bin
    prefix_lib=${prefix}/lib
    prefix_pkg=${prefix}/lib/pkgconfig
    prefix_config=${prefix}/configuration

    if [ x`which python` != x ]; then
        python_version=`python -c 'import sys; print(".".join(map(str, sys.version_info[:2])))'`
        prefix_dist_packages=${prefix}/lib/python${python_version}/dist-packages
        prefix_site_packages=${prefix}/lib/python${python_version}/site-packages
    fi

    mkdir -p ${prefix_bin}
    cd ${MARS_DEV_ROOT}

    if [ x`which cmake_debug` = "x" ]; then

        echo "#! /bin/sh" > env.sh
        echo "" >> env.sh
  
        echo "export MARS_SCRIPT_DIR=\"${MARS_SCRIPT_DIR}\"" >> env.sh
        echo "export PATH=\"$""PATH:${prefix_bin}\"" >> env.sh
        
        if [ "${platform}" = "darwin" ]; then
            echo "export DYLD_LIBRARY_PATH=\"${prefix_lib}\":$""DYLD_LIBRARY_PATH" >> env.sh
        else
            echo "export LD_LIBRARY_PATH=\"${prefix_lib}\":$""LD_LIBRARY_PATH" >> env.sh
        fi

        echo "export ROCK_CONFIGURATION_PATH=\"${prefix_config}\"" >> env.sh

        if [ x`which python` != x ]; then
            echo "" >> env.sh
            echo "export PYTHONPATH=$""PYTHONPATH:\"${prefix_dist_packages}\":\"${prefix_site_packages}\"" >> env.sh
        fi

        echo "" >> env.sh
        echo "if [ x$""{PKG_CONFIG_PATH} = "x" ]; then" >> env.sh
        echo "  export PKG_CONFIG_PATH=\"${prefix_pkg}\"" >> env.sh
        echo "else" >> env.sh
        echo "  export PKG_CONFIG_PATH=\"${prefix_pkg}\":\"$""PKG_CONFIG_PATH"\" >> env.sh
        echo "fi" >> env.sh
        echo "" >> env.sh
        echo "alias mars_bootstrap='bash ${MARS_SCRIPT_DIR}/mars.sh bootstrap'" >> env.sh
        echo "alias mars_install='bash ${MARS_SCRIPT_DIR}/mars.sh install'" >> env.sh
        echo "alias mars_rebuild='bash ${MARS_SCRIPT_DIR}/mars.sh rebuild'" >> env.sh
        echo "alias mars_build='bash ${MARS_SCRIPT_DIR}/mars.sh'" >> env.sh
        echo "alias mars_diff='bash ${MARS_SCRIPT_DIR}/mars.sh diff'" >> env.sh
        echo ". ${MARS_SCRIPT_DIR}/auto_complete.sh" >> env.sh

        cd ${prefix}/bin
        if $MSYS; then
            echo "#!/bin/bash" > cmake_debug
            echo "cmake .. -DCMAKE_EXPORT_COMPILE_COMMANDS:BOOL=ON -DCMAKE_INSTALL_PREFIX=$prefix -DCMAKE_BUILD_TYPE=DEBUG  -G \"MSYS Makefiles\" \$@" >> cmake_debug
            echo "#!/bin/bash" > cmake_release
            echo "cmake .. -DCMAKE_EXPORT_COMPILE_COMMANDS:BOOL=ON -DCMAKE_INSTALL_PREFIX=$prefix -DCMAKE_BUILD_TYPE=RELEASE  -G \"MSYS Makefiles\" \$@" >> cmake_release
        else
            echo "cmake .. -DCMAKE_EXPORT_COMPILE_COMMANDS:BOOL=ON -DCMAKE_INSTALL_PREFIX=$prefix -DCMAKE_BUILD_TYPE=DEBUG \$@" > cmake_debug
            echo "cmake .. -DCMAKE_EXPORT_COMPILE_COMMANDS:BOOL=ON -DCMAKE_INSTALL_PREFIX=$prefix -DCMAKE_BUILD_TYPE=RELEASE \$@" > cmake_release
        fi
        chmod +x cmake_debug
        chmod +x cmake_release
        cd ${MARS_DEV_ROOT}

        source env.sh
    else
        if [ ! `which cmake_debug` = "${prefix_bin}/cmake_debug" ]; then
            printErr "error for cmake_debug path; check environment variables or open a new shell"
            MARS_SCRIPT_ERROR=1
            return 1
        fi
    fi
    popd > /dev/null 2>&1
}


# =========================================================
# function copied from https://gist.github.com/8665367.git
# ========================================================

function parse_yaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_-]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p" $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         sub("-", "_", vname[0])
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

##############################
# fetch functions
##############################

# ======================
# generic fetch function
# ======================

function fetch_package {
    package=$1
    path=$2
    push_addr=$3
    read_addr=$4
    setupConfig
    printBold "fetching ${path} ..."
    pushd . > /dev/null 2>&1
    if [ -d ${MARS_DEV_ROOT}/${path} ]; then
        if [ -d ${MARS_DEV_ROOT}/${path}/.git ]; then
            printBold "${package} seems to already exist. updating..."
            cd ${MARS_DEV_ROOT}/${path}
            git pull | egrep "Already up-to-date|Fast-forward" || MARS_SCRIPT_ERROR=1;
        else
            printBold "${package} exists but doesn't seem to be a git repo!"
            #MARS_SCRIPT_ERROR=1;
        fi
    else
        printBold "cloning ${package}"
        path=${MARS_DEV_ROOT}/${path}
        #${path%/*}
        mkdir -p ${path}
        cd ${path}
        if ${PUSH}; then
            CLONE_ADDR=${push_addr}
            #"git@git.hb.dfki.de:mars/${package##*/}.git"
        else
            CLONE_ADDR=${read_addr}
            #"git://git.hb.dfki.de/mars/${package##*/}.git"
        fi
        CLONE_ERROR=0
        git clone ${CLONE_ADDR} . || CLONE_ERROR=1;
        if [[ ${CLONE_ERROR} != 0 ]]; then
            printErr "Error: Could not clone package from \"${CLONE_ADDR}\"!"
            MARS_SCRIPT_ERROR=1;
        fi
    fi
    popd > /dev/null 2>&1
    if [[ ${MARS_SCRIPT_ERROR} != 0 ]]; then
        return 1;
    else
        printBold "... done fetching ${path}."
    fi
    return 0;
}


# ======================
# yaml fetch function
# ======================

function fetch_yaml_cpp() {
    setupConfig
    printBold "fetching yaml-cpp ..."
    pushd . > /dev/null 2>&1
    mkdir -p ${MARS_DEV_ROOT}/external
    cd ${MARS_DEV_ROOT}/external
    if [ ! -e "yaml-cpp-0.3.0.tar.gz" ]; then
        wget http://yaml-cpp.googlecode.com/files/yaml-cpp-0.3.0.tar.gz
        if [ -d "yaml-cpp" ]; then 
            uninstall_package "external/yaml-cpp"
            rm -rf yaml-cpp
        fi
    fi
    if [ ! -d "yaml-cpp" ]; then 
        tar -xzvf yaml-cpp-0.3.0.tar.gz
        #mv yaml-cpp-0.3.0 yaml-cpp
    fi
    cd ..
    popd > /dev/null 2>&1
    printBold "... done fetching yaml-cpp."
}


# ======================
# eigen fetch function
# ======================

function fetch_eigen() {
    setupConfig
    printBold "fetching eigen3 ..."
    pushd . > /dev/null 2>&1
    mkdir -p ${MARS_DEV_ROOT}/external
    cd ${MARS_DEV_ROOT}/external
    if [ ! -e "3.2.4.tar.gz" ]; then
        wget --no-check-certificate http://bitbucket.org/eigen/eigen/get/3.2.4.tar.gz
        if [ -d "eigen3" ]; then 
            uninstall_package "external/eigen3"
            rm -rf eigen3
        fi
    fi

    if [ ! -d "eigen3" ]; then 
        tar -xzvf 3.2.4.tar.gz
        mv eigen-eigen-10219c95fe65 eigen3
    fi
    cd ..
    popd > /dev/null 2>&1
    printBold "... done fetching eigen3."
}


# ======================
# ode fetch function
# ======================

function fetch_ode_mars() {
    setupConfig
    printBold "fetching ode ..."
    pushd . > /dev/null 2>&1
    mkdir -p ${MARS_DEV_ROOT}/external
    cd ${MARS_DEV_ROOT}/external
    if [ ! -e "ode-0.12.tar.gz" ]; then
        wget http://sourceforge.net/projects/opende/files/ODE/0.12/ode-0.12.tar.gz
        if [ -d "ode_mars" ]; then 
            uninstall_package "external/ode_mars"
            rm -rf ode_mars
        fi
    fi

    if [ ! -d "ode_mars" ]; then 
        tar -xzvf ode-0.12.tar.gz
        mv ode-0.12 ode_mars
    fi
    cd ..
    popd > /dev/null 2>&1
    printBold "... done fetching ode."
}


# ======================
# minizip fetch function
# ======================

function fetch_minizip() {
    setupConfig
    printBold "fetching minizip ..."
    pushd . > /dev/null 2>&1
    mkdir -p ${MARS_DEV_ROOT}/external
    cd ${MARS_DEV_ROOT}/external
    if [ ! -e "unzip11.zip" ]; then
        wget http://www.winimage.com/zLibDll/unzip101e.zip
        if [ -d "minizip" ]; then 
            uninstall_package "external/minizip"
            rm -rf minizip
        fi
    fi

    if [ ! -d "minizip" ]; then 
        unzip unzip101e.zip -d minizip
    fi
    cd ..
    popd > /dev/null 2>&1
    printBold "... done fetching minizip."
}

# ======================
# opencv fetch function
# ======================

function fetch_opencv() {
    setupConfig
    pushd . > /dev/null 2>&1
    printBold "fetching opencv ..."
    mkdir -p ${MARS_DEV_ROOT}/external
    cd ${MARS_DEV_ROOT}/external
    if $MSYS; then
        if [ ! -e "opencv-2.3.0.zip" ]; then
            #wget http://sourceforge.net/projects/opencvlibrary/files/opencv-win/2.3/OpenCV-2.3.0-win-src.zip
            wget --no-check-certificate --output-document=opencv-2.3.0.zip https://github.com/Itseez/opencv/archive/2.3.0.zip
        fi
        if [ ! -d "opencv-2.3.0.zip" ]; then 
            unzip opencv-2.3.0.zip
        fi
    #wget http://sourceforge.net/projects/opencvlibrary/files/opencv-unix/2.3.1/OpenCV-2.3.1a.tar.bz2/download
    #tar -xjvf OpenCV-2.3.1a.tar.bz2
    fi
    cd ..
    popd > /dev/null 2>&1
    printBold "... done fetching opencv."
}

# ====================
# catch fetch function
# ====================

function fetch_catch() {
    setupConfig
    pushd . > /dev/null 2>&1
    printBold "fetching catch ..."
    mkdir -p ${MARS_DEV_ROOT}/external
    cd ${MARS_DEV_ROOT}/external
    if $MSYS; then
        if [ ! -e "catch.hpp" ]; then
            wget --no-check-certificate https://raw.githubusercontent.com/philsquared/Catch/master/single_include/catch.hpp
        fi
    fi
    cd ..
    popd > /dev/null 2>&1
    printBold "... done fetching catch."
}

#############################
# update functions
#############################

function update_package {
    packages=$1;
    path=$2;
    folder=$3;
    setupConfig
    printBold "updating ${path} ..."
    pushd . > /dev/null 2>&1
    cd ${MARS_DEV_ROOT}/${path} || MARS_SCRIPT_ERROR=1
    if [[ x${MARS_SCRIPT_ERROR} == x1 ]]; then
        popd > /dev/null 2>&1
        return 1
    fi
    git pull
    popd > /dev/null 2>&1
    printBold "... done updateing ${path}."
};

function update_yaml_cpp {
    # yaml is not under revision control
    return 0
}

function update_eigen {
    # eigen is not under revision control
    return 0
}

function update_opencv {
    # opencv is not under revision control
    return 0
}

function update_ode_mars {
    # ode is not under revision control
    return 0
}

function update_minizip {
    # minizip is not under revision control
    return 0
}

function update_catch {
    # catch is not under revision control
    return 0
}

    
#############################
# patch functions
#############################

function patch_package {
    package=$1
    path=${MARS_DEV_ROOT}/$2
    folder=$3
    echo ${path}
    echo ${MARS_SCRIPT_DIR}/patches/${package##*/}.patch
    setScriptDir
    setupConfig
    if [[ -f ${MARS_SCRIPT_DIR}/patches/${package##*/}.patch ]]; then
        printBold "patching ${package} ..."
        patch -N -p0 -d ${path} -i ${MARS_SCRIPT_DIR}/patches/${package##*/}.patch
        printBold "... done patching ${package}."
    fi
}


function patch_minizip {
    printBold "patching external/minizip ..."
    setScriptDir
    setupConfig
    patch -N -p0 -d ${MARS_DEV_ROOT}/external -i ${MARS_SCRIPT_DIR}/patches/minizip.patch
    # patch was submitted upstream and confirmed via email to 
    # Gilles Vollant <info@winimage.com> on 22. Oct. 2012
    patch -N -p0 -d ${MARS_DEV_ROOT}/external -i ${MARS_SCRIPT_DIR}/patches/minizip_unzip.patch
    printBold "... done patching external/minizip."
}

function patch_opencv {
    printBold "patching external/OpenCV-2.3.0 ..."
    setScriptDir
    setupConfig
    patch -N -p0 -d ${MARS_DEV_ROOT}/external -i ${MARS_SCRIPT_DIR}/patches/OpenCV-2.3.0.patch
    printBold "... done patching external/OpenCV-2.3.0"
}

function patch_eigen {
    patch_package eigen3 external
}

function patch_ode_mars {
    printBold "patching external/ode_mars version 0.12 ..."
    setScriptDir
    setupConfig
    # patch was accepted upstream (http://sf.net/p/opende/patches/180) and
    # applied to Rev. 1913 (http://sf.net/p/opende/code/1913) and should be
    # in the next release
    patch -N -p0 -d ${MARS_DEV_ROOT}/external/ode_mars -i ${MARS_SCRIPT_DIR}/patches/ode-0.12-va_end.patch
    patch -N -p0 -d ${MARS_DEV_ROOT}/external/ode_mars -i ${MARS_SCRIPT_DIR}/patches/ode-0.12-lambda.patch
    patch -N -p0 -d ${MARS_DEV_ROOT}/external/ode_mars -i ${MARS_SCRIPT_DIR}/patches/ode-0.12-export_joint_internals.patch
    # patch was submitted upstream (http://sf.net/p/opende/patches/187)
    patch -N -p0 -d ${MARS_DEV_ROOT}/external/ode_mars -i ${MARS_SCRIPT_DIR}/patches/ode-0.12-abort.patch
    printBold "... done patching external/ode_mars version 0.12."
}


##############################
# install functions
##############################

# =========================
# generic install function
# =========================

function install_package {
    packages=$1;
    path=$2;
    folder=$3;
    cmake_options=$4;
    echo
    printBold "building "${package}" ..."
    echo
    pushd . > /dev/null 2>&1
    manifest=${MARS_DEV_ROOT}/${path}/${folder}/manifest.xml
    if grep -qs "no_install" ${manifest}; then
        printBold "... skip install of ${category}/${package}"
    else
        mkdir -p ${MARS_DEV_ROOT}/${path}/${folder}/build
        cd ${MARS_DEV_ROOT}/${path}/${folder}/build
        if [[ ${BUILD_TYPE} == "release" ]]; then
            cmake_release ${cmake_options}
        else
            cmake_debug ${cmake_options}
        fi
        make install -j${CORES} || MARS_SCRIPT_ERROR=1
        popd > /dev/null 2>&1
        if [[ x${MARS_SCRIPT_ERROR} == "x1" ]]; then
            return 1
        fi
        echo
        printBold "... done building ${category}/${package}."
    fi
}

# =========================
# install rock/base-types
# =========================

function install_base_types {
    path=$1;
    echo
    printBold "building "${package}" ..."
    echo
    pushd . > /dev/null 2>&1
    mkdir -p ${MARS_DEV_ROOT}/${path}/base-types/build
    cd ${MARS_DEV_ROOT}/${path}/base-types/build
    if [[ ${BUILD_TYPE} == "release" ]]; then
        cmake_release -DINSTALL_BOOST_IF_REQUIRED=1
    else
        cmake_debug -DINSTALL_BOOST_IF_REQUIRED=1
    fi
    make install -j${CORES} || MARS_SCRIPT_ERROR=1
    popd > /dev/null 2>&1
    if [[ x${MARS_SCRIPT_ERROR} == "x1" ]]; then
        return 1
    fi
    echo
    printBold "... done building ${category}/${package}."
}

# =========================
# ode install function
# =========================

function install_ode_mars {
    if [ ! -e ${MARS_DEV_ROOT}"/install/lib/pkgconfig/ode.pc" ]; then
      echo
      printBold "building external/ode_mars..."
      echo
      pushd . > /dev/null 2>&1
      cd ${MARS_DEV_ROOT}/external/ode_mars
      export CFLAGS=-fPIC
      export CXXFLAGS=-fPIC
      # --enable-release
      ./configure CPPFLAGS="-DdNODEBUG" CXXFLAGS="-O2 -ffast-math -fPIC" CFLAGS="-O2 -ffast-math -fPIC" --enable-double-precision --prefix=$prefix --with-drawstuff=none --disable-demos
      if [ "${platform}" = "linux" ]; then
        if [ x`which libtool` != x ]; then
          mv libtool libtool_old
          ln -s `which libtool` libtool
        fi
      fi
      make install -j${CORES} || MARS_SCRIPT_ERROR=1
      popd > /dev/null 2>&1

      if [[ x${MARS_SCRIPT_ERROR} == "x1" ]]; then
          return 1
      fi
      echo
      printBold "... done building external/ode."
    fi
}


# =========================
# opencv install function
# =========================

function install_opencv {
  if [ ! -e ${MARS_DEV_ROOT}"/install/lib/pkgconfig/opencv.pc" ]; then
    echo
    printBold "building external/OpenCV-2.3.0 ..."
    echo
    pushd . > /dev/null 2>&1
    cd ${MARS_DEV_ROOT}/external/OpenCV-2.3.0
    mkdir -p build; cd build;
    # disable python support for OpenCV
    if [[ ${BUILD_TYPE} == "release" ]]; then
      cmake_release "-DBUILD_NEW_PYTHON_SUPPORT=OFF -DWITH_CUDA=OFF";
    else
      # always build release on windows
      if ${MSYS}; then
        cmake_release "-DBUILD_NEW_PYTHON_SUPPORT=OFF -DWITH_CUDA=OFF";
      else
         cmake_debug "-DBUILD_NEW_PYTHON_SUPPORT=OFF -DWITH_CUDA=OFF";
      fi
    fi
    # on MSYS opencv chokes on build with many CORES
    if ${MSYS}; then
        make install -j1 || MARS_SCRIPT_ERROR=1
    else
        make install -j${CORES} || MARS_SCRIPT_ERROR=1
    fi
    popd > /dev/null 2>&1
    if [[ x${MARS_SCRIPT_ERROR} == "x1" ]]; then
        return 1
    fi
    echo
    printBold "... done building external/OpenCV-2.3.0"
  fi
}


# =========================
# eigen install function
# =========================

function install_eigen {
  if [ ! -e ${MARS_DEV_ROOT}"/install/lib/pkgconfig/eigen3.pc" ]; then
    echo
    printBold "building external/eigen3 ..."
    echo
    pushd . > /dev/null 2>&1
    cd ${MARS_DEV_ROOT}/external/eigen3
    mkdir -p build; cd build;
    if [[ ${BUILD_TYPE} == "release" ]]; then
        cmake_release
    else
        cmake_debug
    fi
    make install -j${CORES} || MARS_SCRIPT_ERROR=1
    if [[ x${MARS_SCRIPT_ERROR} == "x1" ]]; then
        popd > /dev/null 2>&1
        return 1
    fi
    cp eigen3.pc ${MARS_DEV_ROOT}/install/lib/pkgconfig/
    popd > /dev/null 2>&1
    echo
    printBold "... done building external/eigen3"
  fi
}


# ======================
# catch install function
# ======================

function install_catch {
  if [ ! -e ${MARS_DEV_ROOT}"/install/include/catch.hpp" ]; then
    pushd . > /dev/null 2>&1
    cp ${MARS_DEV_ROOT}/external/catch.hpp ${MARS_DEV_ROOT}/install/include/catch.hpp 
    echo "Name: catch
Description: A modern, C++-native, header-only, framework for unit-tests, TDD and BDD
Version: dev
Cflags: -I${MARS_DEV_ROOT}/install/include" >> ${MARS_DEV_ROOT}/install/lib/pkgconfig/catch.pc
  fi
}






##############################
# cleanup functions
##############################

function clean_package {
    package=$1
    path=$2
    folder=$3
    setupConfig
    printBold "cleaning "${package}"..."
    pushd . > /dev/null 2>&1
    cd ${MARS_DEV_ROOT}/${path}/${folder}
    rm -rf build
    popd > /dev/null 2>&1
    printBold "...cleaning "${package}" done!"
}


function clean_eigen {
    setupConfig
    printBold "cleaning external/eigen3..."
    pushd . > /dev/null 2>&1
    cd ${MARS_DEV_ROOT}/external/eigen3
    rm -rf build
    popd > /dev/null 2>&1
    printBold "...cleaning external/eigen3 done!"
}


function clean_opencv {
    setupConfig
    printBold "cleaning external/OpenCV-2.3.0..."
    pushd . > /dev/null 2>&1
    cd ${MARS_DEV_ROOT}/external/OpenCV-2.3.0
    rm -rf build
    popd > /dev/null 2>&1
    printBold "...cleaning external/OpenCV-2.3.0 done!"
}


function uninstall_package {
    package=$1
    path=$2
    setupConfig
    printBold "uninstalling ${package}..."
    pushd . > /dev/null 2>&1
    if [[ ! -d ${MARS_DEV_ROOT}/${path}/${package}/build ]]; then
        printErr "Cannot uninstall ${package} because the build directory is missing!"
        MARS_SCRIPT_ERROR=1
        return 1
    else
        cd ${MARS_DEV_ROOT}/${path}/${package}/build
        if [[ -f install_manifest.txt ]]; then
            if $MSYS; then
                dos2unix install_manifest.txt
            fi
            xargs rm < install_manifest.txt
        else
            printErr "Cannot uninstall ${package} because the install_manifest.txt is missing!"
            MARS_SCRIPT_ERROR=1
        fi
    fi
    popd > /dev/null 2>&1
    if [[ x${MARS_SCRIPT_ERROR} != x && ${MARS_SCRIPT_ERROR} != 0 ]]; then
        return 1
    else
        printBold "...uninstalling ${package} done!"
    fi
}


# ======================
# generic diff function
# ======================

function diff_package() {
    packages=$1;
    path=$2;
    folder=$3;
    printBold "diff "${path}" ..."
    pushd . > /dev/null 2>&1
    cd ${MARS_DEV_ROOT}/${path} || MARS_SCRIPT_ERROR=1
    if [[ x${MARS_SCRIPT_ERROR} == x1 ]]; then
        popd > /dev/null 2>&1
        return 1
    fi
    git diff
    popd > /dev/null 2>&1
}

function diff_eigen() {
    return 0
}

function diff_yaml_cpp() {
    return 0
}

function diff_ode_mars() {
    return 0
}

function diff_minizip() {
    return 0
}

function diff_opencv() {
    return 0
}
