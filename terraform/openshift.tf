resource "random_string" "ocp_admin_password" {
  length  = 32
  special = true
}
data "template_file" "inventory" {
  template = "${file("${path.module}/templates/ocp-inventory.tmpl")}"
  vars = {
    ocp_admin                = "${var.ocp_vm_admin_user}",
    ocp_admin_password       = "${random_string.ocp_admin_password.result}",
    ocp_cluster_prefix       = "${var.ocp_cluster_prefix}",
    ocp_master_count         = "${var.ocp_master_count}",
    ocp_infra_count          = "${var.ocp_infra_count}",
    ocp_node_count           = "${var.ocp_node_count}",
    ocp_dns_zone_name        = "${var.ocp_dns_zone_name}",
    ocpvnet_name             = "${var.ocpvnet_name}",
    resource_group_name      = "${data.azurerm_resource_group.ocp.name}",
    location                 = "${var.location}",
    oreg_auth_user           = "${var.ocp_oreg_user}",
    oreg_auth_password       = "${var.ocp_oreg_password}",
    rh_activation_key        = "${var.rh_activation_key}",
    rh_org                   = "${var.rh_org}",
    rh_pool_id               = "${var.rh_pool_id}",
    rh_infra_pool_id         = "${var.rh_infra_pool_id}",
    osm_host_subnet_length   = "${var.ocp_osm_host_subnet_length}",
    openshift_portal_net     = "${var.ocp_openshift_portal_net}",
    osm_cluster_network_cidr = "${var.ocp_osm_cluster_network_cidr}",
    openshift_docker_options = "${var.ocp_openshift_docker_options}",
  }
}

data "template_file" "ansiblecfg" {
  template = "${file("${path.module}/templates/ansible.cfg.tmpl")}"
  vars = {
    ocp_vm_admin_name   = "${var.ocp_vm_admin_user}",
  }
}

resource "null_resource" "inventory" {
  depends_on = [azurerm_virtual_machine.bastion]
  triggers = {
    template = "${data.template_file.inventory.rendered}"
  }
  provisioner "file" {
    content = "${data.template_file.inventory.rendered}"
    destination = "/home/${var.ocp_vm_admin_user}/inventory"
    connection {
      type        = "ssh"
      host        = "${azurerm_public_ip.bastion.ip_address}"
      user        = "${var.ocp_vm_admin_user}"
      private_key = "${file("${path.module}/../certs/bastion")}"
    }
  }
}
resource "null_resource" "ansiblecfg" {
  depends_on = [azurerm_virtual_machine.bastion]
  triggers = {
    template = "${data.template_file.ansiblecfg.rendered}"
  }
  provisioner "file" {
    content = "${data.template_file.ansiblecfg.rendered}"
    destination = "/home/${var.ocp_vm_admin_user}/.ansible.cfg"
    connection {
      type        = "ssh"
      host        = "${azurerm_public_ip.bastion.ip_address}"
      user        = "${var.ocp_vm_admin_user}"
      private_key = "${file("${path.module}/../certs/bastion")}"
    }
  }
}

locals {
  ansible_playbook_prefix = "ansible-playbook -e openshift_cloudprovider_azure_client_id=\"${azuread_application.azure_app.application_id}\" -e openshift_cloudprovider_azure_client_secret=\"${azuread_service_principal_password.azure_app.value}\" -e openshift_cloudprovider_azure_tenant_id=\"${data.azurerm_client_config.current.tenant_id}\" -e openshift_cloudprovider_azure_subscription_id=\"${data.azurerm_client_config.current.subscription_id}\""
}

resource "null_resource" "openshift-prepare" {
  depends_on = [null_resource.inventory, null_resource.ansiblecfg, azurerm_virtual_machine.master, azurerm_virtual_machine.infra, azurerm_virtual_machine.node]

  provisioner "remote-exec" {
    inline = [
      # runs all prereqs + patches
      "${local.ansible_playbook_prefix} /home/${var.ocp_vm_admin_user}/ansible/playbooks/init_hosts.yaml",
#      "${local.ansible_playbook_prefix} /usr/share/ansible/openshift-ansible/playbooks/deploy_cluster.yml",
    ]

    connection {
      type        = "ssh"
      host        = "${azurerm_public_ip.bastion.ip_address}"
      user        = "${var.ocp_vm_admin_user}"
      private_key = "${file("${path.module}/../certs/bastion")}"
    }
  }
}