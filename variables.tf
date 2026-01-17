# General
variable "hcloud_token" {
  type        = string
  description = "The Hetzner Cloud API token."
  sensitive   = true
}

variable "cluster_name" {
  type        = string
  description = "The name of the cluster."
}

variable "cluster_domain" {
  type        = string
  default     = "cluster.local"
  description = "The domain name of the cluster."
}

variable "cluster_prefix" {
  type        = bool
  default     = false
  description = "Prefix Hetzner Cloud resources with the cluster name."
}

variable "node_prefix" {
  type        = string
  default     = null
  description = <<-EOF
    Prefix for node names. If not set, uses cluster_name.
    Nodes are named: <prefix>c1, <prefix>c2 (control planes) and <prefix>w1, <prefix>w2 (workers).
    Example: node_prefix="tm" -> tmc1, tmc2, tmw1, tmw2
    Example: node_prefix=null, cluster_name="tmain" -> tmainc1, tmainc2, tmainw1, tmainw2
  EOF
}

variable "cluster_api_host" {
  type        = string
  description = <<EOF
    Optional. A stable DNS hostname for the public Kubernetes API endpoint (e.g., `kube.mydomain.com`).
    If set, you MUST configure a DNS A record for this hostname pointing to your desired public entrypoint (e.g., Floating IP, Load Balancer IP).
    This hostname will be embedded in the cluster's certificates (SANs).
    If not set, the generated kubeconfig/talosconfig will use an IP address based on `output_mode_config_cluster_endpoint`.
    Internal cluster communication often uses `kube.[cluster_domain]`, which is handled automatically via /etc/hosts if `enable_alias_ip = true`.
  EOF
  default     = null
}

variable "export_configs" {
  type        = bool
  default     = true
  description = "Automatically write kubeconfig and talosconfig files to the current directory after apply."
}

variable "location" {
  type        = string
  description = <<EOF
    The Hetzner Cloud location where the cluster will be created.
    Possible values: fsn1, nbg1, hel1, ash, hil
  EOF
  validation {
    condition     = contains(["fsn1", "nbg1", "hel1", "ash", "hil"], var.location)
    error_message = "Invalid location. Must be one of: fsn1, nbg1, hel1, ash, hil"
  }
}

variable "output_mode_config_cluster_endpoint" {
  type    = string
  default = "public_ip"
  validation {
    condition     = contains(["public_ip", "private_ip", "cluster_endpoint"], var.output_mode_config_cluster_endpoint)
    error_message = "Invalid output mode for kube and talos config endpoint."
  }
  description = <<EOF
    Configure which endpoint address is written into the generated `talosconfig` and `kubeconfig` files.
    - `public_ip`: Use the public IP of the first control plane (or the Floating IP if enabled).
    - `private_ip`: Use the private IP of the first control plane (or the private Alias IP if enabled). Useful if accessing only via VPN/private network.
    - `cluster_endpoint`: Use the hostname defined in `cluster_api_host`. Requires `cluster_api_host` to be set.
  EOF
}

# Firewall
variable "firewall_id" {
  type        = string
  default     = null
  description = <<EOF
    ID of an existing Hetzner Cloud firewall to use instead of creating one.
    When set, the module will not create a firewall and will use this ID instead.
    This is useful to avoid chicken-and-egg issues when your IP changes:
    manage the firewall externally and pass its ID here.
  EOF
}

variable "firewall_use_current_ip" {
  type        = bool
  default     = false
  description = <<EOF
    If true, the current IP address will be used as the source for the firewall rules.
    ATTENTION: to determine the current IP, requests to public services are made:
    - IPv4 address is always fetched from https://ipv4.icanhazip.com
    - IPv6 address is only fetched from https://ipv6.icanhazip.com if enable_ipv6 = true
  EOF
}

variable "extra_firewall_rules" {
  type        = list(any)
  default     = []
  description = "Additional firewall rules to apply to the cluster."
}

variable "firewall_kube_api_source" {
  type        = list(string)
  default     = null
  description = <<EOF
    Source networks that have Kube API access to the servers.
    If null (default), the all traffic is blocked.
    If set, this overrides the firewall_use_current_ip setting.
  EOF
}

variable "firewall_talos_api_source" {
  type        = list(string)
  default     = null
  description = <<EOF
    Source networks that have Talos API access to the servers.
    If null (default), the all traffic is blocked.
    If set, this overrides the firewall_use_current_ip setting.
  EOF
}

# Network
variable "enable_floating_ip" {
  type        = bool
  default     = false
  description = "If true, a floating IP will be created and assigned to the control plane nodes."
}

variable "enable_alias_ip" {
  type        = bool
  default     = true
  description = <<EOF
    If true, a private alias IP (defaulting to the .100 address within `node_ipv4_cidr`) will be configured on the control plane nodes.
    This enables a stable internal IP for the Kubernetes API server, reachable via `kube.[cluster_domain]`.
    The module automatically configures `/etc/hosts` on nodes to resolve `kube.[cluster_domain]` to this alias IP.
  EOF
}

variable "floating_ip" {
  type = object({
    id = number,
  })
  default     = null
  description = <<EOF
    The Floating IP (ID) to use for the control plane nodes.
    If null (default), a new floating IP will be created.
    (using object because of https://github.com/hashicorp/terraform/issues/26755)
  EOF
}

variable "enable_ipv6" {
  type        = bool
  default     = false
  description = <<EOF
    If true, the servers will have an IPv6 address.
    IPv4/IPv6 dual-stack is actually not supported, it keeps being an IPv4 single stack. PRs welcome!
  EOF
}

variable "enable_kube_span" {
  type        = bool
  default     = false
  description = "If true, the KubeSpan Feature (with \"Kubernetes registry\" mode) will be enabled."
}

variable "network_ipv4_cidr" {
  description = "The main network cidr that all subnets will be created upon."
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_ipv4_cidr" {
  description = "Node CIDR, used for the nodes (control plane and worker nodes) in the cluster."
  type        = string
  default     = "10.0.1.0/24"
}

variable "pod_ipv4_cidr" {
  description = "Pod CIDR, used for the pods in the cluster."
  type        = string
  default     = "10.0.16.0/20"
}

variable "service_ipv4_cidr" {
  description = "Service CIDR, used for the services in the cluster."
  type        = string
  default     = "10.0.8.0/21"
}

# Server
variable "talos_version" {
  type        = string
  description = "The version of talos features to use in generated machine configurations."
}

variable "ssh_public_key" {
  description = <<EOF
    The public key to be set in the servers. This key is used by Hetzner Cloud for initial server provisioning
    and for accessing the server in rescue mode. While Talos itself does not use this key for cluster operations,
    providing one prevents Hetzner from sending login credentials via email.
    If you don't set it, a dummy key will be generated and used.
  EOF
  type        = string
  default     = null
  sensitive   = true
}

variable "control_plane_count" {
  type        = number
  description = <<EOF
    The number of control plane nodes to create.
    Must be an odd number. Maximum 5.
  EOF
  validation {
    // 0 is required for debugging (create configs etc. without servers)
    condition     = var.control_plane_count == 0 || (var.control_plane_count % 2 == 1 && var.control_plane_count <= 5)
    error_message = "The number of control plane nodes must be an odd number."
  }
}

variable "control_plane_server_type" {
  type        = string
  description = <<EOF
    The server type to use for the control plane nodes.
    Possible values: cpx11, cpx12, cpx21, cpx22, cpx31, cpx32, cpx41, cpx42, cpx51, cpx52, cpx62,
    cax11, cax21, cax31, cax41, ccx13, ccx23, ccx33, ccx43, ccx53, ccx63,
    cx22, cx23, cx32, cx33, cx42, cx43, cx52, cx53
  EOF
  validation {
    condition = contains([
      "cpx11", "cpx12", "cpx21", "cpx22", "cpx31", "cpx32", "cpx41", "cpx42", "cpx51", "cpx52", "cpx62",
      "cax11", "cax21", "cax31", "cax41",
      "ccx13", "ccx23", "ccx33", "ccx43", "ccx53", "ccx63",
      "cx22", "cx23", "cx32", "cx33", "cx42", "cx43", "cx52", "cx53"
    ], var.control_plane_server_type)
    error_message = "Invalid control plane server type."
  }
}


variable "control_plane_allow_schedule" {
  type        = bool
  default     = false
  description = <<EOF
    If true, control plane nodes will be schedulable (i.e., can run workloads).
    If false (default), control plane nodes will be tainted to prevent scheduling of regular workloads.
    Note: If you set worker_count to 0, control plane nodes will automatically be schedulable regardless of this setting.
  EOF
}


variable "worker_count" {
  type        = number
  default     = 0
  description = "DEPRECATED: Use worker_nodes instead. The number of worker nodes to create. Maximum 99."
  validation {
    condition     = var.worker_count <= 99
    error_message = "The number of worker nodes must be less than 100."
  }
}

variable "worker_server_type" {
  type        = string
  default     = "cpx11"
  description = <<EOF
    DEPRECATED: Use worker_nodes instead. The server type to use for the worker nodes.
    Possible values: cpx11, cpx12, cpx21, cpx22, cpx31, cpx32, cpx41, cpx42, cpx51, cpx52, cpx62,
    cax11, cax21, cax31, cax41, ccx13, ccx23, ccx33, ccx43, ccx53, ccx63,
    cx22, cx23, cx32, cx33, cx42, cx43, cx52, cx53
  EOF
  validation {
    condition = contains([
      "cpx11", "cpx12", "cpx21", "cpx22", "cpx31", "cpx32", "cpx41", "cpx42", "cpx51", "cpx52", "cpx62",
      "cax11", "cax21", "cax31", "cax41",
      "ccx13", "ccx23", "ccx33", "ccx43", "ccx53", "ccx63",
      "cx22", "cx23", "cx32", "cx33", "cx42", "cx43", "cx52", "cx53"
    ], var.worker_server_type)
    error_message = "Invalid worker server type."
  }
}

variable "worker_nodes" {
  type = list(object({
    type   = string
    labels = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default     = []
  description = <<EOF
    List of worker node configurations. Each object defines a group of worker nodes with the same configuration.
    - type: Server type (cpx11, cpx12, cpx21, cpx22, cpx31, cpx32, cpx41, cpx42, cpx51, cpx52, cpx62, cax11, cax21, cax31, cax41, ccx13, ccx23, ccx33, ccx43, ccx53, ccx63, cx22, cx23, cx32, cx33, cx42, cx43, cx52, cx53)
    - count: Number of nodes of this type
    - labels: Map of Kubernetes labels to apply to these nodes (default: {})
    - taints: List of Kubernetes taints to apply to these nodes (default: [])

    Example:
    worker_nodes = [
      {
        type  = "cx22"
      },
      {
        type   = "cax22"
        labels = {
          "node.kubernetes.io/arch" = "arm64"
        }
        taints = [
          {
            key    = "workload-type"
            value  = "gpu"
            effect = "NoSchedule"
          }
        ]
      }
    ]
  EOF
  validation {
    condition = alltrue([
      for node in var.worker_nodes : contains([
        "cpx11", "cpx12", "cpx21", "cpx22", "cpx31", "cpx32", "cpx41", "cpx42", "cpx51", "cpx52", "cpx62",
        "cax11", "cax21", "cax31", "cax41",
        "ccx13", "ccx23", "ccx33", "ccx43", "ccx53", "ccx63",
        "cx22", "cx23", "cx32", "cx33", "cx42", "cx43", "cx52", "cx53"
      ], node.type)
    ])
    error_message = "Invalid worker server type in worker_nodes."
  }
  validation {
    condition     = length(var.worker_nodes) <= 99
    error_message = "Total number of worker nodes must be less than 100."
  }
}

variable "disable_x86" {
  type        = bool
  default     = false
  description = "If true, x86 images will not be used."
}

variable "disable_arm" {
  type        = bool
  default     = false
  description = "If true, arm images will not be used."
}

# Talos
variable "kubelet_extra_args" {
  type        = map(string)
  default     = {}
  description = "Additional arguments to pass to kubelet."
}

variable "kube_api_extra_args" {
  type        = map(string)
  default     = {}
  description = "Additional arguments to pass to the kube-apiserver."
}

variable "kubernetes_version" {
  type        = string
  default     = "1.30.3"
  description = <<EOF
    The Kubernetes version to use. If not set, the latest version supported by Talos is used: https://www.talos.dev/v1.7/introduction/support-matrix/
    Needs to be compatible with the `cilium_version`: https://docs.cilium.io/en/stable/network/kubernetes/compatibility/
  EOF
}

variable "sysctls_extra_args" {
  type        = map(string)
  default     = {}
  description = "Additional sysctls to set."
}

variable "kernel_modules_to_load" {
  type = list(object({
    name       = string
    parameters = optional(list(string))
  }))
  default     = null
  description = "List of kernel modules to load."
}

variable "talos_control_plane_extra_config_patches" {
  type        = list(string)
  default     = []
  description = "List of additional YAML configuration patches to apply to the Talos machine configuration for control plane nodes."
}

variable "talos_worker_extra_config_patches" {
  type        = list(string)
  default     = []
  description = "List of additional YAML configuration patches to apply to the Talos machine configuration for worker nodes."
}


variable "tailscale" {
  type = object({
    enabled            = optional(bool)
    auth_key           = optional(string)
    login_server       = optional(string)           # For Headscale: e.g., "http://hs.example.com:8080"
    routes             = optional(list(string), []) # Subnet routes to advertise, e.g., ["10.0.16.0/20"]
    api_key            = optional(string, "")       # Headscale API key for cleanup (headscale apikeys create)
    user               = optional(string, "")       # Headscale user/namespace
    cleanup_on_destroy = optional(bool, true)       # Auto-remove nodes from Headscale on destroy
  })
  default = {
    enabled            = false
    auth_key           = ""
    login_server       = ""
    routes             = []
    api_key            = ""
    user               = ""
    cleanup_on_destroy = true
  }
  sensitive   = true
  description = <<-EOF
    Tailscale/Headscale configuration.
    - enabled: Enable Tailscale on nodes
    - auth_key: Pre-auth key for nodes to join (headscale preauthkeys create)
    - login_server: Headscale URL (e.g., "http://hs.example.com:8080")
    - routes: Subnet routes to advertise (e.g., ["10.0.16.0/20"])
    - api_key: Headscale admin API key for cleanup (headscale apikeys create)
    - user: Headscale user/namespace where nodes are registered
    - cleanup_on_destroy: Auto-remove nodes from Headscale on terraform destroy (default: true)
  EOF
  validation {
    condition     = var.tailscale.enabled == false || (var.tailscale.enabled == true && var.tailscale.auth_key != "")
    error_message = "If tailscale is enabled, an auth_key must be provided."
  }
  validation {
    condition = (
      var.tailscale.api_key == "" ||
      (var.tailscale.api_key != "" && var.tailscale.user != "" && var.tailscale.login_server != "")
    )
    error_message = "If tailscale.api_key is set, user and login_server must also be provided."
  }
}

variable "cloudflared" {
  type = object({
    enabled = optional(bool)
    token   = optional(string) # Cloudflare Tunnel token (from cloudflared tunnel create)
  })
  default = {
    enabled = false
    token   = ""
  }
  description = "Cloudflare Tunnel (cloudflared) configuration. Provide the tunnel token to enable."
  sensitive   = true
  validation {
    condition     = var.cloudflared.enabled == false || (var.cloudflared.enabled == true && var.cloudflared.token != "")
    error_message = "If cloudflared is enabled, a token must be provided."
  }
}

variable "registries" {
  type = object({
    mirrors = optional(map(object({
      endpoints    = list(string)
      overridePath = optional(bool)
    })))
    config = optional(map(object({
      auth = object({
        username      = optional(string)
        password      = optional(string)
        auth          = optional(string)
        identityToken = optional(string)
      })
    })))
  })
  default     = null
  description = <<EOF
    List of registry mirrors to use.
    Example:
    ```
    registries = {
      mirrors = {
        "docker.io" = {
          endpoints = [
            "http://localhost:5000",
            "https://docker.io"
          ]
        }
      }
    }
    ```
    https://www.talos.dev/v1.6/reference/configuration/v1alpha1/config/#Config.machine.registries
  EOF
}

# Deployments
variable "cilium_version" {
  type        = string
  default     = "1.16.2"
  description = <<EOF
    The version of Cilium to deploy. If not set, the `1.16.0` version will be used.
    Needs to be compatible with the `kubernetes_version`: https://docs.cilium.io/en/stable/network/kubernetes/compatibility/
  EOF
}

variable "cilium_values" {
  type        = list(string)
  default     = null
  description = <<EOF
    The values.yaml file to use for the Cilium Helm chart.
    If null (default), the default values will be used.
    Otherwise, the provided values will be used.
    Example:
    ```
    cilium_values  = [templatefile("cilium/values.yaml", {})]
    ```
  EOF
}

variable "cilium_enable_encryption" {
  type        = bool
  default     = false
  description = "Enable transparent network encryption."
}

variable "cilium_enable_service_monitors" {
  type        = bool
  default     = false
  description = <<EOF
    If true, the service monitors for Prometheus will be enabled.
    Service Monitor requires monitoring.coreos.com/v1 CRDs.
    You can use the deploy_prometheus_operator_crds variable to deploy them.
  EOF
}

variable "deploy_prometheus_operator_crds" {
  type        = bool
  default     = false
  description = "If true, the Prometheus Operator CRDs will be deployed."
}

# Piraeus/LINSTOR Storage
variable "deploy_piraeus" {
  type        = bool
  default     = false
  description = "If true, Piraeus/LINSTOR storage will be deployed. Requires siderolabs/drbd extension in Talos image."
}

variable "piraeus_operator_version" {
  type        = string
  default     = "v2.10.3"
  description = "The version of the Piraeus Operator to deploy (git ref for kustomize)."
}

variable "piraeus_storage_pools" {
  type = list(object({
    name = string
    fileThinPool = optional(object({
      directory = string
    }))
    lvmThinPool = optional(object({
      volumeGroup = string
      thinPool    = string
    }))
    lvmPool = optional(object({
      volumeGroup = string
    }))
    zfsPool = optional(object({
      zPool = optional(string)
    }))
    zfsThinPool = optional(object({
      zPool = optional(string)
      source = optional(object({
        hostDevices = optional(list(string))
      }))
    }))
  }))
  default = [
    {
      name = "pool1"
      fileThinPool = {
        directory = "/var/lib/piraeus/pool1"
      }
    }
  ]
  description = "Storage pools configuration for LINSTOR satellites. Defaults to file-based thin pool."
}

variable "piraeus_storage_classes" {
  type = list(object({
    name                       = string
    is_default                 = optional(bool, false)
    reclaim_policy             = optional(string, "Delete")
    allow_volume_expansion     = optional(bool, true)
    volume_binding_mode        = optional(string, "WaitForFirstConsumer")
    fs_type                    = optional(string, "xfs")
    storage_pool               = optional(string, "pool1")
    placement_count            = optional(number)
    allow_remote_volume_access = optional(bool, false)
    layer_list                 = optional(string) # e.g., "STORAGE" to bypass DRBD, or "DRBD,STORAGE" for replication
  }))
  default = [
    {
      name            = "piraeus"
      storage_pool    = "pool1"
      placement_count = 3
      is_default      = true
    },
    {
      name            = "piraeus-retain"
      storage_pool    = "pool1"
      placement_count = 3
      reclaim_policy  = "Retain"
    },
    {
      name            = "piraeus-local"
      storage_pool    = "pool1"
      placement_count = 1
      layer_list      = "STORAGE"
    },
    {
      name            = "piraeus-local-retain"
      storage_pool    = "pool1"
      placement_count = 1
      layer_list      = "STORAGE"
      reclaim_policy  = "Retain"
    }
  ]
  description = "Storage classes to create for Piraeus/LINSTOR. Defaults to ZFS-backed storage."
}

variable "hcloud_ccm_version" {
  type        = string
  default     = null
  description = "The version of the Hetzner Cloud Controller Manager to deploy. If not set, the latest version will be used."
}

variable "disable_talos_coredns" {
  type        = bool
  default     = false
  description = "If true, the CoreDNS delivered by Talos will not be deployed."
}

variable "extraManifests" {
  type        = list(string)
  default     = null
  description = "Additional manifests URL applied during Talos bootstrap."
}
