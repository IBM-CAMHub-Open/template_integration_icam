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

uninstallAgent() {
    agentName=$1
    agentScript=${INSTALL_DIR}/bin/${agentName}-agent.sh
    status=0

    if [ -x "${agentScript}" ]; then
        echo "Uninstalling ${agentName} agent..."
        ${agentScript} uninstall

        echo "Verifying removal of ${agentName} agent..."
        if [ ! -f "${agentScript}" ]; then
            for code in `cat ${INSTALL_DIR}/config/agentscripts.properties | grep ${agentName}-agent.sh | cut -f1 -d'|'`
            do
                echo "Verifying agent product code ${code} has been unregistered..."
                agentRegistered=$(${INSTALL_DIR}/bin/cinfo -d | grep \"${code}\" | wc -l)
                if [ "${agentRegistered}" != "0" ]; then
                    echo "Agent product code ${code} is still registered; Agent may not be fully uninstalled"
                    status=1
                fi
            done
        else
            echo "Agent script ${agentScript} has not been removed; Agent may not be fully uninstalled"
            status=1
        fi

        if [ ${status} -eq 0 ]; then
            echo "${agentName} agent has been uninstalled"
        fi
    else
        echo "Script for ${agentName} agent does not exist; skipping..."
    fi
    return $status
}

identifySeparateAgents() {
    for scriptName in `cat ${INSTALL_DIR}/config/agentscripts.properties | cut -f2 -d'|' | sort -u`
    do
        agentName=$(echo ${scriptName} | cut -f1 -d'-')
        if [ -x "${INSTALL_DIR}/bin/${scriptName}" ]; then
            if [[ ${separateAgents} ]]; then
                separateAgents="${separateAgents}, ${agentName}"
            else
                separateAgents="${agentName}"
            fi
        fi
    done
    echo ${separateAgents}
}

# Perform tasks necessary for installing the agent(s)
performTasks() {
    # Uninstall specified agent(s)
    agentNames=$(echo $AGENT_NAME | tr '[,:;]' ' ')
    for agentName in ${agentNames}
    do
        uninstallAgent ${agentName}
        if [ $? -ne 0 ]; then
            logFailure "Unable to fully uninstall agent ${agentName}"
        fi
    done

    # Determine if additional agents have been installed separately
    additionalAgents=$(identifySeparateAgents)
    if [ -z "${additionalAgents}" ]; then
        if [ -x "${INSTALL_DIR}/bin/smai-agent.sh" ]; then
            echo "No additional agents have been installed separately; removing all agent artifacts..."
            ${INSTALL_DIR}/bin/smai-agent.sh uninstall_all force
        fi
    else
        echo "Additional agent(s) (${additionalAgents}) have been installed separately"
    fi
}


# Check Parameters
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 icam_agent_installation_dir icam_agent_name" >&2
    exit 1
fi

# Assign Parameters
for i in "$@"
do
    case $i in
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


# Perform uninstalltion(s)
performTasks 2>&1 | tee ${LOG_FILE}
exitStatus=$?
if [ $exitStatus -ne 0 ]; then
    echo "Uninstall did not complete successfully; Exit code ${exitStatus}"
fi
exit $exitStatus