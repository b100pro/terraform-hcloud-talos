output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}

output "kubeconfig" {
  value     = local.kubeconfig
  sensitive = true
}

# Automatically export config files when enabled
resource "local_file" "kubeconfig" {
  count           = var.export_configs ? 1 : 0
  content         = local.kubeconfig
  filename        = "${path.root}/kubeconfig"
  file_permission = "0600"
}

resource "local_file" "talosconfig" {
  count           = var.export_configs ? 1 : 0
  content         = data.talos_client_configuration.this.talos_config
  filename        = "${path.root}/talosconfig"
  file_permission = "0600"
}

# Manage kubeconfig with kubecm
resource "null_resource" "kubecm" {
  count = var.export_configs ? 1 : 0

  triggers = {
    cluster_name    = var.cluster_name
    kubeconfig_path = local_file.kubeconfig[0].filename
  }

  # Add to kubecm on apply
  provisioner "local-exec" {
    command     = "yes | kubecm add -cf ${self.triggers.kubeconfig_path} --context-name ${self.triggers.cluster_name} -s 2>/dev/null || true"
    interpreter = ["bash", "-c"]
  }

  # Remove from kubecm on destroy
  provisioner "local-exec" {
    when        = destroy
    command     = "kubecm delete ${self.triggers.cluster_name} -s 2>/dev/null || true"
    interpreter = ["bash", "-c"]
  }

  depends_on = [local_file.kubeconfig]
}

output "talos_client_configuration" {
  value     = data.talos_client_configuration.this
  sensitive = true
}

output "talos_machine_configurations_control_plane" {
  value     = data.talos_machine_configuration.control_plane
  sensitive = true
}

output "talos_machine_configurations_worker" {
  value     = data.talos_machine_configuration.worker
  sensitive = true
}

output "kubeconfig_data" {
  description = "Structured kubeconfig data to supply to other providers"
  value       = local.kubeconfig_data
  sensitive   = true
}

output "public_ipv4_list" {
  description = "List of public IPv4 addresses of all control plane nodes"
  value       = local.control_plane_public_ipv4_list
}

output "hetzner_network_id" {
  description = "Network ID of the network created at cluster creation"
  value       = hcloud_network.this.id
}

output "firewall_id" {
  description = "ID of the firewall attached to cluster nodes"
  value       = local.firewall_id
}

output "talos_worker_ids" {
  description = "Server IDs of the hetzner talos workers machines"
  value = merge(
    { for id, server in hcloud_server.workers_new : id => server.id },
    { for id, server in hcloud_server.workers : id => server.id }
  )
}

