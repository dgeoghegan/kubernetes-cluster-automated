
resource "aws_route" "pod_route" {
  count = length(aws_instance.kubernetes_worker)
  route_table_id  = var.route_table_id
  destination_cidr_block  = local.kubernetes_worker_network_info[count.index].worker_pod_cidr
  network_interface_id    = aws_instance.kubernetes_worker[count.index].primary_network_interface_id
}
