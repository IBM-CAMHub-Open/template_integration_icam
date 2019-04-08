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

# Check if a command exists
command_exists() {
  type "$1" &> /dev/null;
}

IPMGetValue() {
    [ ! -f "${2}" ] && return 1
    _properties_entry=$(grep "${1}" "${2}" 2>/dev/null | cut -f2 -d= | sed s'/^ //' | sed s'/ $//')
    # Did not find the entry so return with error code.
    [ -z "${_properties_entry}" ] && return 1
    echo "${_properties_entry}"

    return 0
}

GetAgentProductCode() {
    _agent_properties="${TEMP_DIR}/${SOURCE_SUBDIR}"/.apm/inst/${1}-agent/agent.properties
    _product_code=$(IPMGetValue "^SMAI_PC" "${_agent_properties}") || return 1
    _ipmo_agents=$(echo "${_product_code}" | tr '[:upper:]' '[:lower:]')
    echo "${_ipmo_agents}"

    return 0
}

ConfigureAgentBinaries() {
    set -e
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
            curl -O ${CONFIG_BUNDLE}
        else
            curl -u ${SOURCE_CREDENTIALS} -O ${CONFIG_BUNDLE}
        fi
        bundle=${CONFIG_BUNDLE##*/}
        tar xvf ${bundle}
        if [ -f linux_unix_configpack.tar ]; then
            echo "Configuring agent binaries for ICAM server..."
            tar xvf linux_unix_configpack.tar
            sh ./pre_config.sh -s ${unconfiguredDir} -d ${configuredDir} -e env.properties
        else
            echo "Configuration bundle does not exist; Exiting"
            exit 1
        fi

        # Cleanup
        mv ${configuredDir}/${INSTALLER} ${TEMP_DIR}
        rm -rf ${apmWorkDir}
    fi
}

InstallAgent() {
    set -e
    agentName=$1
    silentTxt=APP_MGMT_silent_install.txt.tmp

    echo "Preparing silent install file for ${agentName} agent..."
    cd ${TEMP_DIR}/${SOURCE_SUBDIR}
    cp APP_MGMT_silent_install.txt ${silentTxt}

    echo "" >> ${silentTxt}
    echo "License_Agreement=\"I agree to use the software only in accordance with the installed license.\"" >> ${silentTxt}
    echo "AGENT_HOME=$INSTALL_DIR" >> ${silentTxt}
    echo "INSTALL_AGENT=${agentName}" >> ${silentTxt}

    echo "Installing ${agentName} agent..."
    export IGNORE_PRECHECK_WARNING=1
    ./installAPMAgents.sh -p ${silentTxt}

    echo "Verifying installation of ${agentName} agent..."
    agentCode=$(GetAgentProductCode ${agentName})
    agentInstalled=`$INSTALL_DIR/bin/cinfo -d | grep \"${agentCode}\"  | wc -l` 
    if [ "${agentInstalled}" = "0" ]; then
        echo "Unable to install ${agentName} agent; exiting."
        exit 1
    fi
    echo "Agent '${agentName}' successfully installed."
}

GenerateServerInfo() {
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

    if [ ! -z "${icamServerJson}" ]; then
        printf "\n\n\n"
        echo "ICAM_SERVER_INFO=${icamServerJson}"
        printf "\n"
    fi
}


TEMP_DIR=/tmp

# Check Parameters

if [ "$#" -lt 4 ]; then
    echo "Usage: $0 icam_config_location icam_agent_location icam_source_credentials icam_agent_source_subdir icam_agent_installation_dir icam_agent_name" >&2
    exit 1
fi

# Assign Parameters
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
    --icam_agent_source_subdir=*)
    SOURCE_SUBDIR="${i#*=}"
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
    *)
    # unknown option
    ;;
esac
done

INSTALLER=${SOURCE##*/}

AGENTS="$@"

# Download APM Installer
cd $TEMP_DIR
if [[ -z "$SOURCE_CREDENTIALS" ]]; then
    curl -O $SOURCE
else
    curl -u$SOURCE_CREDENTIALS -O $SOURCE
fi

if [ ! -z "${CONFIG_BUNDLE}" ]; then
    # Configure bundle specified; Agent source binary presumed to be unconfigued
    ConfigureAgentBinaries

    # Return to original work directory
    cd ${TEMP_DIR}
fi

# Extract configured agent installer bundle
tar xvf $INSTALLER


# Install Pre-requisites

# Identify the platform and version using Python
if command_exists python; then
  PLATFORM=`python -c "import platform;print(platform.platform())" | rev | cut -d '-' -f3 | rev | tr -d '".' | tr '[:upper:]' '[:lower:]'`
  PLATFORM_VERSION=`python -c "import platform;print(platform.platform())" | rev | cut -d '-' -f2 | rev`
else
  if command_exists python3; then
    PLATFORM=`python3 -c "import platform;print(platform.platform())" | rev | cut -d '-' -f3 | rev | tr -d '".' | tr '[:upper:]' '[:lower:]'`
    PLATFORM_VERSION=`python3 -c "import platform;print(platform.platform())" | rev | cut -d '-' -f2 | rev`
  fi
fi
# Check if the executing platform is supported
if [[ $PLATFORM == *"ubuntu"* ]] || [[ $PLATFORM == *"redhat"* ]] || [[ $PLATFORM == *"rhel"* ]] || [[ $PLATFORM == *"centos"* ]]; then
  echo "[*] Platform identified as: $PLATFORM $PLATFORM_VERSION"
else
  echo "[ERROR] Platform $PLATFORM not supported"
  exit 1
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
    echo "[ERROR] There was an error obtaining the latest packages"
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


# Install Agent(s)
agentNames=$(echo $AGENT_NAME | tr '[,:;]' ' ')
for agentName in ${agentNames}
do
    InstallAgent ${agentName}
done


# Generate ICAM server info from agent configuration details
GenerateServerInfo


# Cleanup
rm $TEMP_DIR/$INSTALLER
rm -Rf $TEMP_DIR/$SOURCE_SUBDIR
