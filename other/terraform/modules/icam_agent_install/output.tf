locals {
  icam_server_info   = "${camc_scriptpackage.FetchServerInfo.result}"
  icam_server_name   = "${lookup(local.icam_server_info, "server", "")}"
  icam_server_port   = "${lookup(local.icam_server_info, "port",   "")}"
  icam_server_tenant = "${lookup(local.icam_server_info, "tenant", "")}"
  
  icam_server_url    = "https://${local.icam_server_name}:${local.icam_server_port}/cemui/resources?subscriptionId=${local.icam_server_tenant}"
}

output "icam_server_url"
{
  value = "${local.icam_server_url}"
}