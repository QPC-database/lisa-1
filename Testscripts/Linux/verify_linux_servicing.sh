#!/bin/bash
########################################################################
#
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
#
# Description:
# Test suite to verify the package upgrade & rollback feature in Mariner
#
########################################################################

PACKAGE_LIST="package_list.txt"
PACKAGE_UPGRADE_SUMMARY="package_upgrade_summary.log"

pkg_exception_list=(
    "kernel-hyperv"
    "kernel-signed"
)

# Function to generate the summary report for all installed & upgraded pkgs
function LogUpdateSummary() {
    local packagename=${1}
    local operation=${2}
    echo "$operation .. ${packagename}" >>  ${PACKAGE_UPGRADE_SUMMARY}
    return 0
}

function is_pkg_exempted() {
    local pkgname=${1}
    for pkg in "${pkg_exception_list[@]}";do
        [[ "${pkgname}" =~ "${pkg}" ]] && return 1
    done
    return 0
}

# Function to install all dependencies for servicing tests
function InstallDependencies() {
    local dpackage="diffutils"
    install_package ${dpackage}
    if ! rpm -q --quiet ${dpackage};then
      return ${FAIL_ID}
    fi

    # Update  mariner-release package to capture update release version
    local updatelog=$(dnf update mariner-release -y)
    LogMsg "InstallDependencies: mariner release update log: $updatelog"

    return 0
}

# Function to get the update package repository list
function GetUpdateRepolist() {
    local repolist=$(dnf repolist | awk 'NR!=1 {print $1}' | grep update)
    echo $repolist
}

# Function to get the list of package marked for upgrade
function GetUpdatePackageList() {
    tmp_file=".pkglist"
    [[ -f ${PACKAGE_LIST} ]] && rm -f ${PACKAGE_LIST}
    [[ -f ${tmp_file} ]] && rm -f ${tmp_file}

    local update_repolist="${1}"
    [[ -z $update_repolist ]] && return ${SKIP_ID}

    for repo in ${update_repolist};do
        LogMsg "INFO: Checking repo ${repo}..."
        local pkg_list=$(dnf list -y | grep -w ${repo} | awk '{ printf("%s,%s ", $1, $2) }')
        LogMsg "INFO: GetUpdatePackageList: ${pkg_list}"
        echo ${pkg_list} >> ${tmp_file}
    done

    cat ${tmp_file} | uniq > ${PACKAGE_LIST}
    rm -f ${tmp_file}

    return 0
}

function GetPackageVersion() {
    local pkgname="${1}"
    # There could a case of multiple version
    # Extract the most latest version.
    local version=$(rpm -q --qf "%{VERSION}-%{RELEASE}\n" ${pkgname} | tail -1 | tr -d '\n')
    echo ${version}
}

# Helper function to check the package upgrade status
function CheckPackageUpdateStatus() {
    local pkgname=${1}
    local expected_version=${2}

    current_version=$(GetPackageVersion ${pkgname})
    LogMsg "INFO: ${pkgname} - ${current_version} - ${expected_version}"
    [[ ${current_version} != ${expected_version} ]] && return ${FAIL_ID}

    return 0
}

# Function to test specific package upgrade scenario
function TestSpecificPackageUpgrade() {
    local ret=${SKIP_ID}
    local pkgnames=${1}

    LogMsg "INFO: Upgrading package ${1}"
    
    # Iterate over the package list and upgrade
    for pkgname in ${pkgnames//,/ };do
        if ! rpm -q --quiet ${pkgname};then
            LogMsg "INFO: TestSpecificPackageUpgrade: Specified package not installed"
        else
            local oldversion=$(GetPackageVersion ${pkgname})
            dnf update ${pkgname} -y
            local newversion=$(GetPackageVersion ${pkgname})
            LogMsg "INFO: TestSpecificPackageUpgrade:: ${pkgname} oldversion: ${oldversion} newversion: ${newversion}"
            [[ ${oldversion} == ${newversion} ]]  && {
                for pkg in $(cat ${PACKAGE_LIST});do
                    local upkgname=$(echo $pkg | cut -d, -f1)
                    if [[ $pkg == ${upkgname} ]];then
                        LogErr "ERR: ${pkgname} was marked for upgrade ($pkg) but no upgrade"
                        ret=${FAIL_ID}
                        break
                    fi
                done
            }
        fi
    done

    return $ret
}

# Function to check transaction history
function CheckTransactionHistory() {
    local ret=0
    [[ -z ${1} ]] && return ${FAIL_ID}
    local output=$(dnf history | tail -n +3 | head -1 | grep ${1}); ret=$?
    LogMsg "ERR: CheckTransactionHistory: ret: $ret output: ${output}"
    [[ $ret -ne 0 ]] && return ${FAIL_ID}

    return 0
}

# Function to test package installation from updates
function TestAllUpdatePackages() {
    LogMsg "INFO: Test ALL Update Packages..."
    local ret=2

    for pkg in $(cat ${PACKAGE_LIST});do
        local pkgname=$(echo $pkg | cut -d, -f1)
        local newversion=$(echo $pkg | cut -d, -f2)
        pkgname=$(echo $pkgname | sed s/.$(uname -m)//g)
        LogMsg "INFO: SKIP_DEBUG(${SKIP_DEBUG}) pkgname(${pkgname})"
        # Check wheather to skip debug packages
        [[ ! -z ${SKIP_DEBUG} &&  ${SKIP_DEBUG} == "Yes" ]] && {
            [[ ${pkgname} =~ "debuginfo" ]] && {
                LogMsg "INFO: TestAllUpdatePackages Skipping - ${pkgname}"
                continue
            }
        }
        is_pkg_exempted "${pkgname}"
        [[ $? -eq 1 ]] && {
            LogMsg "INFO: TestAllUpdatePackages Skipping - ${pkgname}"
            continue
        }

        LogMsg "INFO: TestAllUpdatePackages:: Checking ${pkgname} ${newversion}"
        ret=1
        if rpm -q --quiet ${pkgname};then
            local oldversion=$(GetPackageVersion ${pkgname})
            LogMsg "${pkgname} - ${oldversion}"
            LogMsg "INFO: TestAllUpdatePackages:: Upgrading ${pkgname} ${oldversion} - ${newversion}"
            dnf update ${pkgname} -y
            CheckPackageUpdateStatus "${pkgname}" "${newversion}"
            [[ $? -ne 0 ]] && {
                LogErr "ERR: TestAllUpdatePackages:: Failed to update ${pkgname}"
                break
            } || {
                ret=0
                LogUpdateSummary "${pkgname}-${newversion}" "Updated"
            }
        else
            local logs=$(dnf install ${pkgname} -y)
            LogMsg "Installing ${pkgname} : ${logs}"
            local nversion=$(GetPackageVersion ${pkgname})
            [[ ${nversion} != ${newversion} ]] && {
                LogErr "ERR: TestAllUpdatePackages:: Failed to install the latest package"
                break
            } || {
              ret=0
              LogUpdateSummary "${pkgname}-${nversion}" "Installed"
            }
        fi
        if [[ ! -z ${CHECK_HISTORY} && ${CHECK_HISTORY} == "Yes" ]];then
            CheckTransactionHistory ${pkgname}; ret=$?
            [[ ${ret} -ne 0 ]] && {
                LogErr "Package transaction not recorded for ${pkgname}"
                ret=1
                break
            }
        fi
    done
    
    return $ret
}

# Function to test package upgrade in a controlled order
function TestPackageUpgrade() {
    LogMsg "INFO: Test Package Upgrade"
    local ret=2
    
    for pkg in $(cat ${PACKAGE_LIST});do
        local pkgname=$(echo $pkg | cut -d, -f1)
        local newversion=$(echo $pkg | cut -d, -f2)
        pkgname=$(echo $pkgname | sed s/.$(uname -m)//g)
        LogMsg "INFO: TestPackageUpgrade:: Checking ${pkgname} ${newversion}"
        if rpm -q --quiet ${pkgname};then
            local cversion=$(GetPackageVersion ${pkgname})
            LogMsg "${pkgname} - ${cversion}"
            [[ ${cversion} == ${newversion} ]] && continue
            ret=1
            LogMsg "INFO: TestPackageUpgrade:: Upgrading ${pkgname} ${cversion} - ${newversion}"
            dnf update ${pkgname} -y
            CheckPackageUpdateStatus "${pkgname}" "${newversion}"
            if [[ $? -ne 0 ]];then
                LogErr "ERR: TestPackageUpgrade:: Failed to update"
                break
            else
                ret=0
            fi
        fi
    done
    
    return $ret
}

# Function to test rollback of upgraded packages
function TestPackageUpgradeRollback() {
    LogMsg "INFO: Test Package Upgrade Rollback"

    PKG_LIST_BUPDATE=".ins_list"
    PKG_LIST_AUPDATE=".ins_list_after_update"
    PKG_LIST_AROLLBACK=".ins_list_after_rollback"

    # Capture installed package list before update
    rpm -qa | sort > ${PKG_LIST_BUPDATE}

    # Perform package upgrade
    local updatelogs=$(dnf update -y)
    LogMsg "INFO: DNF Upgrade Log: ${updatelogs}"

    # Capture the installed package list snapshot after update
    rpm -qa | sort > ${PKG_LIST_AUPDATE}

    # No updates available, skip the test
    if diff -q ${PKG_LIST_BUPDATE} ${PKG_LIST_AUPDATE} > /dev/null;then
        LogMsg "INFO: TestPackageUpgradeRollback:: No updates available"
        return ${SKIP_ID}
    fi
    
    # Rollback last update
    local history=$(dnf history undo last -y)
    LogMsg "INFO: TestPackageUpgradeRollback:: Update history: ${history}"

    # Capture installed package list snapshot after rollback
    rpm -qa | sort > ${PKG_LIST_AROLLBACK}

    # Check rollback was successful.
    # This should match with the package list before update
    if ! diff -q ${PKG_LIST_BUPDATE} ${PKG_LIST_AROLLBACK} > /dev/null;then
        LogMsg "$(diff ${PKG_LIST_BUPDATE} ${PKG_LIST_AROLLBACK})"
        LogMsg "INFO: Rollback unsuccessful"
        return ${FAIL_ID}
    fi

    rm -f ${PKG_LIST_AUPDATE} ${PKG_LIST_AROLLBACK} ${PKG_LIST_BUPDATE}

    return 0
}

# Function to test package upgrade scenario using yum/dnf update
function TestPackagesUpgrade() {
    LogMsg "INFO: Test Packages Upgrade"
    local pkglist=""
    
    # Iterate over the entire package list available for update
    for pkg in $(cat ${PACKAGE_LIST});do
        local pkgname=$(echo $pkg | cut -d, -f1)
        local newversion=$(echo $pkg | cut -d, -f2)
        local pkgname=$(echo $pkgname | sed s/.$(uname -m)//g)
        # If the package is installed and is older version then store in ${pkglist}
        rpm -q --quiet ${pkgname} && {
            local oversion=$(GetPackageVersion ${pkgname})
            [[ ${oversion} != ${newversion} ]] && pkglist="$pkglist $pkg"
        }
    done
    
    # If no packages are available for update then skip
    [[ -z ${pkglist} ]] && {
        LogMsg "INFO: No packages marked for update"
        return ${SKIP_ID}
    }

    LogMsg "INFO: Packages marked for update: ${pkglist}"
    # Perform dnf update for all packages
    dnf update -y
    # Iterate over the installed package version to check the installation status
    for pkg in ${pkglist};do
        local pkgname=$(echo $pkg | cut -d, -f1)
        local nversion=$(echo $pkg | cut -d, -f2)
        local iversion=$(GetPackageVersion ${pkgname})
        if [[ ${iversion} != ${nversion} ]];then
            LogMsg "INFO: ${pkgname} version mismatch ${iversion} ${nversion}"
            return ${FAIL_ID}
        else
            LogMsg "INFO: ${pkgname} version match ${iversion} ${nversion}"
        fi
    done

    return 0
}

# Function to test kernel package upgrade
# Kernel package upgrade test works in 2 phases
# Phase 1: 
#     1. Detect kernel upgrade
#     2. Upgrade kernel
#     3. Reboot system
# Phase 2:
#     1. Detect bootup after kernel upgrade
#     2. Verify kernel upgrade is proper
function TestKernelUpgrade() {
    local test_status=${FAIL_ID}
    KERNEL_VERSION_FILE="${HOME}/kernel_version.txt"
    file_indicator="${HOME}/lisa_kupgrade_test"

    # Check for confirming that system booted with expected
    # kernel version after reboot
    if [[ -f ${file_indicator} ]]; then
        LogMsg "INFO: TestKernelUpgrade:: Verify Kernel package upgrade"
        #rm -f ${file_indicator}
        if [[ -f ${KERNEL_VERSION_FILE} ]];then
            local cversion=$(cat ${KERNEL_VERSION_FILE} | grep "current_version" | cut -d: -f2)
            local eversion=$(cat ${KERNEL_VERSION_FILE} | grep "expected_version" | cut -d: -f2)
            LogMsg "INFO: Versions [Previous: ${cversion} Expected: ${eversion} Current: $(uname -r)]"
            [[ ${eversion} == $(uname -r) ]] && test_status=0
        fi

        #rm -f ${KERNEL_VERSION_FILE}
        return ${test_status}
    fi

    LogMsg "TestKernelUpgrade:: Kernel package upgrade"

    # Check kernel package update is available
    # In Mariner two variants of kernel package is supported
    local kernel_pkg_name="kernel"
    if ! rpm -q kernel > /dev/null ;then
        if rpm -q kernel-hyperv > /dev/null ;then
            kernel_pkg_name="kernel-hyperv"
        else
            kernel_pkg_name=""
        fi
    fi

    [[ -z ${kernel_pkg_name} ]] && {
        LogErr "INFO: TestKernelUpgrade: Unable to detect kernel package"
        return ${FAIL_ID}
    }

    local current_kversion=$(uname -r)
    LogMsg "INFO: TestKernelUpgrade: kernel version before update: ${current_kversion}"
    
    TestSpecificPackageUpgrade ${kernel_pkg_name}; test_status=$?
    if [[ ${test_status} -eq 0 ]];then
        local expected_kversion=$(GetPackageVersion ${kernel_pkg_name})
        touch ${file_indicator}
        echo "current_version:${current_kversion}" > ${KERNEL_VERSION_FILE}
        echo "expected_version:${expected_kversion}" > ${KERNEL_VERSION_FILE}
    fi

    return ${test_status}
}

# Function to test the reinstallation of packages
function TestPackageReinstall() {
    local cmdret=0

    # Get the list of installed packages
    pkgs=$(rpm -qa --qf "%{NAME} ")
    [[ -z ${pkgs} ]] && {
        LogErr "ERR: TestPackageReinstall: Failed to get the installed package list"
        return ${FAIL_ID}
    }

    for pkg in ${pkgs};do
        local bversion=$(GetPackageVersion ${pkg})
        dnf reinstall $pkg -y
        local nversion=$(GetPackageVersion ${pkg}); cmdret=$?
        [[ ${cmdret} -ne 0 && ${bversion} != ${nversion} ]] && {
            LogErr "ERR: TestPackageReinstall: re-install ${pkg} failed"
            return ${FAIL_ID}
        }
        if [[ ! -z ${CHECK_HISTORY} && ${CHECK_HISTORY} == "Yes" ]];then
            CheckTransactionHistory ${pkg}; cmdret=$?
            [[ ${cmdret} -ne 0 ]] && {
                LogErr "Package transaction not recorded for ${pkg}"
                return ${FAIL_ID}
            }
        fi
    done

    return 0
}

# Function to perform sanity check for servicing commands
function TestSanityCheck() {
    local status=0
    LogMsg "INFO: TestSanityCheck: check output of (dnf check-update)"
    output=$(dnf check-update); status=$?
    [[ ${status} -ne 0 ]] && {
        LogErr "ERR: TestSanityCheck: dnf check-update failed (${status})"
        return ${FAIL_ID}
    }

    LogMsg "INFO: TestSanityCheck: check output of (dnf info)"
    # bash package is hardcoded as this is the basic package
    # required for running this test
    local count=$(dnf info bash | grep Name | wc -l)
    [[ ${count} -ne 1 ]] && {
        LogErr "ERR: TestSanityCheck: dnf info bash failed count($count)"
        LogErr "ERR: $(dnf info bash)"
        return ${FAIL_ID}
    }

    LogMsg "INFO: TestSanityCheck: check output of (dnf info)"
    # bash package is hardcoded as this is the basic package
    # required for running this test
    local count=$(tdnf info bash | grep Name | wc -l)
    [[ ${count} -ne 1 ]] && {
        LogErr "ERR: TestSanityCheck: tdnf info bash failed count(${count})"
        LogErr "ERR: $(dnf info bash)"
        return ${FAIL_ID}
    }

    return 0
}

#######################################################################
#
# Main script body
#
#######################################################################

# Source containers_utils.sh
. containers_utils.sh || {
    echo "ERROR: unable to source containers_utils.sh"
    echo "TestAborted" > state.txt
    exit 0
}

UtilsInit
GetDistro

[[ ! ${DISTRO_NAME} == "mariner" ]] && HandleSkip "INFO: Test not supported in ${DISTRO_NAME}"

. constants.sh || {
    LogMsg "INFO: No constants.sh found"
}

test_status=0
[[ -f ${PACKAGE_UPGRADE_SUMMARY} ]] && rm -f ${PACKAGE_UPGRADE_SUMMARY}

InstallDependencies; test_status=$?
HandleTestResults ${test_status} "InstallDependencies"

REPOLIST=$(GetUpdateRepolist)
LogMsg "INFO: SERVICING ${REPOLIST}"
[[ -z $REPOLIST ]] && test_status=1
HandleTestResults ${test_status} "Failed to get the repo list"

LogMsg "INFO: REPO LIST: ${REPOLIST}"
GetUpdatePackageList "${REPOLIST}"

case "$SERVICING_TEST_NAME" in
    PACKAGE_UPGRADE_TEST)
        TestPackageUpgrade; test_status=$?
        ;;
    
    SPECIFIC_PACKAGE_UPGRADE_TEST)
        if [[ ! -z ${UPGRADE_PACKAGE_NAME} ]];then
            TestSpecificPackageUpgrade ${UPGRADE_PACKAGE_NAME}; test_status=$?
        else
            LogErr "ERR: PACKAGE to be upgraded not specified"
            test_status=1
        fi
        ;;

    PACKAGE_UPGRADE_ROLLBACK_TEST)
        TestPackageUpgradeRollback; test_status=$?
        ;;
    
    PACKAGES_UPGRADE_TEST)
        TestPackagesUpgrade; test_status=$?
        ;;

    ALL_PACKAGES_UPDATE_TEST)
        TestAllUpdatePackages; test_status=$?
        ;;

    ALL_NON_DEBUG_PACKAGE_UPDATE_TEST)
        SKIP_DEBUG="Yes"
        TestAllUpdatePackages; test_status=$?
        ;;

    KERNEL_PACKAGES_UPGRADE_TEST)
        TestKernelUpgrade; test_status=$?
        ;;

    SERVICING_SANITY_TEST)
        TestSanityCheck; test_status=$?
        ;;

    PACKAGES_REINSTALL_TEST)
        CHECK_HISTORY="Yes"
        TestPackageReinstall; test_status=$?
        ;;

    TRANSACTION_HISTORY_UPDATE_TEST)
        CHECK_HISTORY="Yes"
        SKIP_DEBUG="Yes"
        TestAllUpdatePackages; test_status=$?
        ;;

    *)
        SERVICING_TEST_NAME="PACKAGE_UPGRADE_TEST"
        LogMsg "INFO: Running Default Test (PACKAGE_UPGRADE_TEST)"
        TestPackageUpgrade; test_status=$?
esac
LogMsg "INFO: ${SERVICING_TEST_NAME} returned : ${test_status}"
HandleTestResults ${test_status} "${SERVICING_TEST_NAME}"

SetTestStateCompleted
exit 0
