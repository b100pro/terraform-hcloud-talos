# Piraeus/LINSTOR Storage for Talos
# Requires siderolabs/drbd extension in the Talos image
# See: https://piraeus.io/docs/stable/how-to/talos/

locals {
  piraeus_namespace = "piraeus-datastore"
}

# Create namespace first with privileged pod security
resource "kubectl_manifest" "piraeus_namespace" {
  count = var.deploy_piraeus && var.control_plane_count > 0 ? 1 : 0

  yaml_body = <<-EOF
    apiVersion: v1
    kind: Namespace
    metadata:
      name: ${local.piraeus_namespace}
      labels:
        pod-security.kubernetes.io/enforce: privileged
        pod-security.kubernetes.io/audit: privileged
        pod-security.kubernetes.io/warn: privileged
  EOF

  server_side_apply = true
  apply_only        = true

  depends_on = [data.http.talos_health]
}

# Fetch Piraeus Operator manifests from GitHub releases
data "http" "piraeus_operator_manifests" {
  count = var.deploy_piraeus ? 1 : 0
  url   = "https://github.com/piraeusdatastore/piraeus-operator/releases/download/${var.piraeus_operator_version}/manifest.yaml"

  retry {
    attempts     = 3
    min_delay_ms = 1000
    max_delay_ms = 3000
  }
}

data "kubectl_file_documents" "piraeus_operator" {
  count   = var.deploy_piraeus ? 1 : 0
  content = data.http.piraeus_operator_manifests[0].response_body
}

resource "kubectl_manifest" "piraeus_operator" {
  for_each          = var.deploy_piraeus && var.control_plane_count > 0 ? data.kubectl_file_documents.piraeus_operator[0].manifests : {}
  yaml_body         = each.value
  server_side_apply = true
  apply_only        = true

  depends_on = [
    data.http.talos_health,
    kubectl_manifest.piraeus_namespace
  ]
}

# LinstorCluster resource
resource "kubectl_manifest" "linstor_cluster" {
  count = var.deploy_piraeus && var.control_plane_count > 0 ? 1 : 0

  yaml_body = <<-EOF
    apiVersion: piraeus.io/v1
    kind: LinstorCluster
    metadata:
      name: linstorcluster
    spec: {}
  EOF

  depends_on = [kubectl_manifest.piraeus_operator]
}

# LinstorSatelliteConfiguration for Talos (removes systemd dependencies)
resource "kubectl_manifest" "linstor_satellite_config_talos" {
  count = var.deploy_piraeus && var.control_plane_count > 0 ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "piraeus.io/v1"
    kind       = "LinstorSatelliteConfiguration"
    metadata = {
      name = "talos-loader-override"
    }
    spec = {
      podTemplate = {
        spec = {
          initContainers = [
            {
              name     = "drbd-shutdown-guard"
              "$patch" = "delete"
            },
            {
              name     = "drbd-module-loader"
              "$patch" = "delete"
            }
          ]
          volumes = [
            {
              name     = "run-systemd-system"
              "$patch" = "delete"
            },
            {
              name     = "run-drbd-shutdown-guard"
              "$patch" = "delete"
            },
            {
              name     = "systemd-bus-socket"
              "$patch" = "delete"
            },
            {
              name     = "lib-modules"
              "$patch" = "delete"
            },
            {
              name     = "usr-src"
              "$patch" = "delete"
            },
            {
              name = "etc-lvm-backup"
              hostPath = {
                path = "/var/etc/lvm/backup"
                type = "DirectoryOrCreate"
              }
            },
            {
              name = "etc-lvm-archive"
              hostPath = {
                path = "/var/etc/lvm/archive"
                type = "DirectoryOrCreate"
              }
            }
          ]
        }
      }
      storagePools = var.piraeus_storage_pools
    }
  })

  depends_on = [kubectl_manifest.linstor_cluster]
}

# StorageClasses for Piraeus
resource "kubectl_manifest" "piraeus_storage_classes" {
  for_each = var.deploy_piraeus && var.control_plane_count > 0 ? { for sc in var.piraeus_storage_classes : sc.name => sc } : {}

  yaml_body = yamlencode({
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = each.value.name
      annotations = lookup(each.value, "is_default", false) ? {
        "storageclass.kubernetes.io/is-default-class" = "true"
      } : {}
    }
    provisioner          = "linstor.csi.linbit.com"
    reclaimPolicy        = lookup(each.value, "reclaim_policy", "Delete")
    allowVolumeExpansion = lookup(each.value, "allow_volume_expansion", true)
    volumeBindingMode    = lookup(each.value, "volume_binding_mode", "WaitForFirstConsumer")
    parameters = merge(
      {
        "csi.storage.k8s.io/fstype"                      = lookup(each.value, "fs_type", "xfs")
        "linstor.csi.linbit.com/storagePool"             = lookup(each.value, "storage_pool", "pool1")
        "linstor.csi.linbit.com/allowRemoteVolumeAccess" = tostring(lookup(each.value, "allow_remote_volume_access", false))
      },
      lookup(each.value, "placement_count", null) != null ? {
        "linstor.csi.linbit.com/placementCount" = tostring(each.value.placement_count)
      } : {},
      lookup(each.value, "layer_list", null) != null ? {
        "linstor.csi.linbit.com/layerList" = each.value.layer_list
      } : {}
    )
  })

  depends_on = [kubectl_manifest.linstor_satellite_config_talos]
}
