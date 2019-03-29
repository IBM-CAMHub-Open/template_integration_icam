output "icam_server_url"
{
  value = "${lookup(camc_scriptpackage.FetchServerUrl.result, "stdout")}"
}