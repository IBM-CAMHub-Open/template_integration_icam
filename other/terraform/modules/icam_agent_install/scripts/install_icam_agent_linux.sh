#!/bin/bash
# =================================================================
# Copyright 2017 IBM Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# =================================================================

set -o pipefail

# Log the given message upon failure and exit
logFailure() {
    message=$1
    echo -e "\n\n\n"
    echo "ERROR: ${message}"
    echo -e "\n"
    exit 1
}

# Check if a command exists
commandExists() {
  type "$1" &> /dev/null;
}

# Remove work files
cleanup() {
    if [ -f "${TEMP_DIR}/${INSTALLER}" ]; then
        rm -f  ${TEMP_DIR}/${INSTALLER}
    fi
    if [ ! -z "${SOURCE_SUBDIR}" ]; then
        if [ -d "${TEMP_DIR}/${SOURCE_SUBDIR}" ]; then
            rm -rf ${TEMP_DIR}/${SOURCE_SUBDIR}
        fi
    fi
}

# Download bundle containing the agents and their installer
downloadAgentBundle() {
    echo "Downloading agent source bundle..."
    cd ${TEMP_DIR}
    if [[ -z "$SOURCE_CREDENTIALS" ]]; then
        curl -f -O $SOURCE
    else
        curl -f -u $SOURCE_CREDENTIALS -O $SOURCE
    fi
    return $?
}

# Configure the downloaded agent bundle, if necessary
configureAgentBundle() {
    exitStatus=0
    if [ ! -z "${CONFIG_BUNDLE}" ]; then
        # Configure bundle specified; Agent source binary presumed to be unconfigured
        configureAgentBinaries
        exitStatus=$?
    
        # Return to original work directory
        cd ${TEMP_DIR}
    fi
    return $exitStatus
}

# Configure agent binaries for specific ICAM server, as indicated within the given configuration bundle
configureAgentBinaries() {
    exitStatus=0
    echo "Downloading agent configuration bundle..."
    apmWorkDir="${TEMP_DIR}/apm"
    configuredDir="${apmWorkDir}/configuredAgents"
    unconfiguredDir="${apmWorkDir}/unconfiguredAgents"
    if [ -f "${TEMP_DIR}/${INSTALLER}" ]; then
        # Move installer to unconfigured directory
        mkdir -p ${configuredDir}
        mkdir -p ${unconfiguredDir}
        mv ${TEMP_DIR}/${INSTALLER} ${unconfiguredDir}

        # Download and extract configure bundle
        mkdir -p ${apmWorkDir}/configBundle
        cd ${apmWorkDir}/configBundle
        if [[ -z "${SOURCE_CREDENTIALS}" ]]; then
            curl -f -O ${CONFIG_BUNDLE}
        else
            curl -f -u ${SOURCE_CREDENTIALS} -O ${CONFIG_BUNDLE}
        fi
        if [ $? -ne 0 ]; then
            exitStatus=$?
            logFailure "Unable to download configuration bundle: ${CONFIG_BUNDLE}"
        fi
        
        bundle=${CONFIG_BUNDLE##*/}
        tar xf ${bundle}
        if [ -f linux_unix_configpack.tar ]; then
            echo "Configuring agent binaries for ICAM server..."
            tar xf linux_unix_configpack.tar
            sh ./pre_config.sh -s ${unconfiguredDir} -d ${configuredDir} -e env.properties
        else
            logFailure "Configuration pack does not exist; Exiting"
            exitStatus=$?
        fi

        # Cleanup
        mv ${configuredDir}/${INSTALLER} ${TEMP_DIR}
        rm -rf ${apmWorkDir}
    else
        logFailure "Installer bundle (${TEMP_DIR}/${INSTALLER}) does not exist"
        exitStatus=$?
    fi
    
    return $exitStatus
}

    
# Extract configured agent source bundle
extractAgentInstaller() {
    exitStatus=0
    if [ -f "${TEMP_DIR}/${INSTALLER}" ]; then
        # Determine root directory within agent source bundle
        SOURCE_SUBDIR=$(tar -tzf ${TEMP_DIR}/${INSTALLER} | head -1 | cut -f1 -d'/')
        
        # Extract configured agent installer bundle
        cd ${TEMP_DIR}
        tar xf ${INSTALLER}
        exitStatus=$?
    else
        logFailure "Installer bundle (${TEMP_DIR}/${INSTALLER}) does not exist"
        exitStatus=$?
    fi
    return $exitStatus
}

# Install prerequisite packages required by agents
installPrerequisites() {
    exitStatus=0
    
    # Identify the platform and version using Python
    if commandExists python; then
        PLATFORM=`python -c "import platform;print(platform.platform())" | rev | cut -d '-' -f3 | rev | tr -d '".' | tr '[:upper:]' '[:lower:]'`
        PLATFORM_VERSION=`python -c "import platform;print(platform.platform())" | rev | cut -d '-' -f2 | rev`
    else
        if commandExists python3; then
            PLATFORM=`python3 -c "import platform;print(platform.platform())" | rev | cut -d '-' -f3 | rev | tr -d '".' | tr '[:upper:]' '[:lower:]'`
            PLATFORM_VERSION=`python3 -c "import platform;print(platform.platform())" | rev | cut -d '-' -f2 | rev`
        fi
    fi
    # Check if the executing platform is supported
    if [[ $PLATFORM == *"ubuntu"* ]] || [[ $PLATFORM == *"redhat"* ]] || [[ $PLATFORM == *"rhel"* ]] || [[ $PLATFORM == *"centos"* ]]; then
        echo "[*] Platform identified as: $PLATFORM $PLATFORM_VERSION"
    else
        logFailure "Platform $PLATFORM not supported"
        exitStatus=$?
    fi
    # Change the string 'redhat' to 'rhel'
    if [[ $PLATFORM == *"redhat"* ]]; then
        PLATFORM="rhel"
    fi
    
    if [[ $PLATFORM == *"ubuntu"* ]]; then
        PACKAGE_MANAGER=apt-get
        until sudo apt-get update; do
            echo "Sleeping 2 sec while waiting for apt-get update to finish ..."
            sleep 2
        done
    else
        PACKAGE_MANAGER=yum
        if { sudo -n yum -y update 2>&1 || echo E: update failed; } | grep -q '^[W]:'; then
            logFailure "Unable to obtain the latest packages"
            exitStatus=$?
        fi
    fi
    
    PACKAGES="bc"
    for PACKAGE in $PACKAGES
    do
        echo "Installing $PACKAGE"
        until sudo $PACKAGE_MANAGER install -y $PACKAGE; do
            echo "Sleeping 2 sec while waiting for $PACKAGE_MANAGER install to finish ..."
            sleep 2
        done   
    done
    return $exitStatus
}

# Get product code entry associated with the agent
ipmGetValue() {
    [ ! -f "${2}" ] && return 1
    _properties_entry=$(grep "${1}" "${2}" 2>/dev/null | cut -f2 -d= | sed s'/^ //' | sed s'/ $//')
    # Did not find the entry so return with error code.
    [ -z "${_properties_entry}" ] && return 1
    echo "${_properties_entry}"

    return 0
}

# Get product code for the agent
getAgentProductCode() {
    _agent_properties="${TEMP_DIR}/${SOURCE_SUBDIR}"/.apm/inst/${1}-agent/agent.properties
    _product_code=$(ipmGetValue "^SMAI_PC" "${_agent_properties}") || return 1
    _ipmo_agents=$(echo "${_product_code}" | tr '[:upper:]' '[:lower:]')
    echo "${_ipmo_agents}"

    return 0
}

# Generate JSON map detailing information about the ICAM server
generateServerInfo() {
    # Using details from the configured agent binaries, build JSON map of info pertaining to the ICAM server
    icamServerJson=""
    envFile="${TEMP_DIR}/${SOURCE_SUBDIR}/.apm_config/agent_global.environment"
    if [ -f "${envFile}" ]; then
        asfRequest=$(grep IRA_ASF_SERVER_URL ${envFile} | cut -f2 -d'=')
        serverName=$(echo ${asfRequest} | awk -F'//' '{print $NF}' | cut -f1 -d':')
        serverPort=$(echo ${asfRequest} | awk -F':'  '{print $NF}' | cut -f1 -d'/')
        tenantId=$(grep IRA_API_TENANT_ID ${envFile} | cut -f2 -d'=')
        
        icamServerJson="{ \"server\": \"${serverName}\", \"port\": \"${serverPort}\", \"tenant\": \"${tenantId}\" }"
    fi

    echo -e "\n\n\n"
    if [ ! -z "${icamServerJson}" ]; then
        echo "ICAM_SERVER_INFO=${icamServerJson}"
    else
        echo "ICAM_SERVER_INFO="{ \"info": \"unknown\" }"
    fi
    echo -e "\n"
}

# Install the specified agent
installAgent() {
    exitStatus=0
    agentName=$1
    silentTxt=APP_MGMT_silent_install.txt.tmp

    echo "Preparing silent install file for ${agentName} agent..."
    if [ -d "${TEMP_DIR}/${SOURCE_SUBDIR}" ]; then
        cd ${TEMP_DIR}/${SOURCE_SUBDIR}
        
        cp *silent_install.txt ${silentTxt}
        echo "" >> ${silentTxt}
        echo "License_Agreement=\"I agree to use the software only in accordance with the installed license.\"" >> ${silentTxt}
        echo "AGENT_HOME=$INSTALL_DIR" >> ${silentTxt}
        echo "INSTALL_AGENT=${agentName}" >> ${silentTxt}

        echo "Installing ${agentName} agent..."
        export IGNORE_PRECHECK_WARNING=1
        ./installAPMAgents.sh -p ${silentTxt}
        if [ $? -ne 0 ]; then
            exitStatus=$?
            logFailure "Failure during installation of agent ${agentName}"
        fi

        echo "Verifying installation of ${agentName} agent..."
        agentCode=$(getAgentProductCode ${agentName})
        agentInstalled=`$INSTALL_DIR/bin/cinfo -d | grep \"${agentCode}\"  | wc -l` 
        if [ "${agentInstalled}" = "0" ]; then
            logFailure "Failed to install ${agentName} agent; exiting."
            exitStatus=$?
        else
            echo "Agent '${agentName}' successfully installed."
        fi
    else
        logFailure "Agent source subdirectory ${SOURCE_SUBDIR} does not exist"
        exitStatus=$?
    fi
    
    return $exitStatus
}

# Perform tasks necessary for installing the agent(s)
performTasks() {
    # Prepare for agent installation
    cleanup
    downloadAgentBundle
    if [ $? -ne 0 ]; then
        logFailure "Unable to download agent source bundle: ${SOURCE}"
        exit $?
    fi
    configureAgentBundle
    if [ $? -ne 0 ]; then
        logFailure "Unable to configure agent source bundle"
        exit $?
    fi
    extractAgentInstaller
    if [ $? -ne 0 ]; then
        logFailure "Unable to extract configured agent source bundle"
        exit $?
    fi
    installPrerequisites
    if [ $? -ne 0 ]; then
        logFailure "Unable to install required prerequisite packages"
        exit $?
    fi

    # Generate ICAM server info from agent configuration details
    generateServerInfo

    # Install agent(s)
    agentNames=$(echo $AGENT_NAME | tr '[,:;]' ' ')
    for agentName in ${agentNames}
    do
        installAgent ${agentName}
        if [ $? -ne 0 ]; then
            logFailure "Unable to install agent ${agentName}"
            exit $?
        fi
    done

    # Remove work files
    cleanup
}


# Check parameters
if [ "$#" -lt 4 ]; then
    echo "Usage: $0 [icam_config_location] icam_agent_location icam_source_credentials icam_agent_installation_dir icam_agent_name log_file" >&2
    exit 1
fi

# Assign parameters
for i in "$@"
do
    case $i in
        --icam_config_location=*)
        CONFIG_BUNDLE="${i#*=}"
        shift # past argument=value
        ;;
        --icam_agent_location=*)
        SOURCE="${i#*=}"
        shift # past argument=value
        ;;
        --icam_source_credentials=*)
        SOURCE_CREDENTIALS="${i#*=}"
        shift # past argument=value
        ;;
        --icam_agent_installation_dir=*)
        INSTALL_DIR="${i#*=}"
        shift # past argument=value
        ;;
        --icam_agent_name=*)
        AGENT_NAME="${i#*=}"
        shift # past argument with no value
        ;;
        --log_file=*)
        LOG_FILE="${i#*=}"
        shift # past argument with no value
        ;;
        *)
        # unknown option
        ;;
    esac
done

TEMP_DIR=/tmp
INSTALLER=${SOURCE##*/}
AGENTS="$@"
SOURCE_SUBDIR=""

# Perform installation(s)
performTasks 2>&1 | tee ${LOG_FILE}
exitStatus=$?
if [ $exitStatus -ne 0 ]; then
    echo "Installation did not complete successfully; Exit code ${exitStatus}"
fi
exit $exitStatus


