# =================================================================
# Licensed Materials - Property of IBM
# 5737-E67
# @ Copyright IBM Corporation 2016, 2017 All Rights Reserved
# US Government Users Restricted Rights - Use, duplication or disclosure
# restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================

##############################################################
# Script package to install the APM Agents
##############################################################


resource "null_resource" "InstallScript" {
  connection {
    type = "ssh"
    host = "${var.ip_address}"
    user = "${var.user}"
    password =  "${var.password}"
    private_key = "${length(var.private_key) > 0 ? base64decode(var.private_key) : ""}"
    bastion_host        = "${var.bastion_host}"
    bastion_user        = "${var.bastion_user}"
    bastion_private_key = "${length(var.bastion_private_key) > 0 ? base64decode(var.bastion_private_key) : var.bastion_private_key}"
    bastion_port        = "${var.bastion_port}"
    bastion_host_key    = "${var.bastion_host_key}"
    bastion_password    = "${var.bastion_password}"          
  }
  
  provisioner "file" {
    source      = "${path.module}/scripts/install_icam_agent_linux.sh"
    destination = "/tmp/install_icam_agent_linux.sh"
  }
  
  provisioner "remote-exec" {
    inline = [
      "/bin/bash /tmp/install_icam_agent_linux.sh --icam_config_location=${var.icam_config_location} --icam_agent_location=${var.icam_agent_location} --icam_source_credentials=${var.icam_source_credentials} --icam_agent_installation_dir=${var.icam_agent_installation_dir} --icam_agent_name=${var.icam_agent_name} --log_file=/tmp/install_icam_agent_linux.log"
    ]
  }
}

resource "camc_scriptpackage" "FetchServerInfo" {
  depends_on = ["null_resource.InstallScript"]
  
  program = ["svrInfo=$(grep ICAM_SERVER_INFO /tmp/install_icam_agent_linux.log | cut -f2 -d'=');", "if [ -z \"$${svrInfo}\" ]; then echo '{}'; else echo $svrInfo; fi"]
  remote_host = "${var.ip_address}"
  remote_user = "${var.user}"
  remote_password = "${var.password}"
  remote_key = "${var.private_key}"
  bastion_host = "${var.bastion_host}"
  bastion_user = "${var.bastion_user}"
  bastion_password = "${var.bastion_password}"
  bastion_private_key = "${var.bastion_private_key}"  
  bastion_port = "${var.bastion_port}"    
  on_create = true
}

resource "null_resource" "DestroyScript" {
  connection {
    type = "ssh"
    host = "${var.ip_address}"
    user = "${var.user}"
    password =  "${var.password}"
    private_key = "${length(var.private_key) > 0 ? base64decode(var.private_key) : ""}"
    bastion_host        = "${var.bastion_host}"
    bastion_user        = "${var.bastion_user}"
    bastion_private_key = "${length(var.bastion_private_key) > 0 ? base64decode(var.bastion_private_key) : var.bastion_private_key}"
    bastion_port        = "${var.bastion_port}"
    bastion_host_key    = "${var.bastion_host_key}"
    bastion_password    = "${var.bastion_password}"          
  }
  
  provisioner "file" {
    when = "destroy"  
    source      = "${path.module}/scripts/uninstall_icam_agent_linux.sh"
    destination = "/tmp/uninstall_icam_agent_linux.sh"
  }
  
  provisioner "remote-exec" {
    when = "destroy"  
    inline = [
      "/bin/bash /tmp/uninstall_icam_agent_linux.sh --icam_agent_installation_dir=${var.icam_agent_installation_dir} --icam_agent_name=${var.icam_agent_name} --log_file=/tmp/uninstall_icam_agent_linux.log"
    ]
  }
}
