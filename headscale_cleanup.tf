# headscale_cleanup.tf
# Automatic Headscale node cleanup on cluster destruction
#
# When enabled, this resource removes nodes from Headscale before Terraform
# destroys the servers. This prevents orphaned node entries in Headscale.
#
# Requirements:
# - curl and jq must be installed on the machine running Terraform
# - Network access to Headscale API from Terraform execution environment

locals {
  # Only enable cleanup if tailscale is enabled and API key is configured
  # Use nonsensitive() for the boolean check since we're not exposing actual sensitive values
  headscale_cleanup_enabled = nonsensitive(
    var.tailscale.enabled &&
    var.tailscale.api_key != "" &&
    var.tailscale.cleanup_on_destroy
  )

  # Build list of all node names that will be registered with Headscale
  # Talos nodes register with their hostname, which matches the server name
  all_node_names = concat(
    [for cp in local.control_planes : cp.name],
    [for w in local.workers : w.name]
  )
}

# Cleanup resource for each node
# Uses null_resource to avoid modifying existing server resources
resource "null_resource" "headscale_cleanup" {
  for_each = local.headscale_cleanup_enabled ? toset(local.all_node_names) : toset([])

  # Triggers store values needed at destroy time
  # Note: destroy-time provisioners can only reference self.triggers
  # Use nonsensitive() since triggers are stored in state anyway
  triggers = {
    node_name      = each.value
    headscale_url  = nonsensitive(var.tailscale.login_server)
    headscale_key  = nonsensitive(var.tailscale.api_key)
    headscale_user = nonsensitive(var.tailscale.user)
  }

  # Destroy-time provisioner runs BEFORE dependent resources are destroyed
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOF
      #!/bin/bash
      set -e

      NODE_NAME="${self.triggers.node_name}"
      HEADSCALE_URL="${self.triggers.headscale_url}"
      HEADSCALE_KEY="${self.triggers.headscale_key}"
      HEADSCALE_USER="${self.triggers.headscale_user}"

      echo "Cleaning up Headscale node: $NODE_NAME"

      # Query nodes - filter by user if specified, otherwise query all
      if [ -n "$HEADSCALE_USER" ]; then
        NODES_JSON=$(curl -sf \
          -H "Authorization: Bearer $HEADSCALE_KEY" \
          "$HEADSCALE_URL/api/v1/node?user=$HEADSCALE_USER" \
          2>/dev/null || echo '{"nodes":[]}')
      else
        NODES_JSON=$(curl -sf \
          -H "Authorization: Bearer $HEADSCALE_KEY" \
          "$HEADSCALE_URL/api/v1/node" \
          2>/dev/null || echo '{"nodes":[]}')
      fi

      # Find node ID by hostname/given_name
      NODE_ID=$(echo "$NODES_JSON" | jq -r \
        --arg name "$NODE_NAME" \
        '.nodes[] | select(.givenName == $name or .name == $name) | .id' \
        2>/dev/null | head -1)

      if [ -n "$NODE_ID" ] && [ "$NODE_ID" != "null" ]; then
        echo "Found node $NODE_NAME with ID $NODE_ID, deleting..."

        HTTP_STATUS=$(curl -sf -o /dev/null -w "%%{http_code}" \
          -X DELETE \
          -H "Authorization: Bearer $HEADSCALE_KEY" \
          "$HEADSCALE_URL/api/v1/node/$NODE_ID" \
          2>/dev/null || echo "000")

        case "$HTTP_STATUS" in
          200|204)
            echo "Successfully deleted node $NODE_NAME from Headscale"
            ;;
          404)
            echo "Node $NODE_NAME already deleted from Headscale"
            ;;
          *)
            echo "Warning: Failed to delete node $NODE_NAME (HTTP $HTTP_STATUS)"
            # Don't fail the destroy - node might be manually removed
            ;;
        esac
      else
        echo "Node $NODE_NAME not found in Headscale (may already be deleted)"
      fi
    EOF

    interpreter = ["bash", "-c"]
  }

  # Ensure cleanup runs before servers are destroyed
  depends_on = [
    hcloud_server.control_planes,
    hcloud_server.workers,
  ]
}
