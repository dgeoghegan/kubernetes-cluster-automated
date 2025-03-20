resource "aws_lb" "lb" {
  count               = var.cloud_type == "aws" ? 1 : 0
  name                = "${var.network_name}-${var.cluster_index}"
  internal            = true
  load_balancer_type  = "network"
  subnets             = aws_subnet.subnet[*].id

  tags = {
    Name = "${var.network_name}-cluster-${var.cluster_index}"
  }

  lifecycle {
    precondition {
      condition     = length("${var.network_name}-${var.cluster_index}") <= 32
      error_message = "Error: Load balancer name '${var.network_name}-${var.cluster_index}' would exceed 32-char limit for AWS ELBs."
    }
  }
}

resource "aws_lb_target_group" "lb_target_group" {
  count           = var.cloud_type == "aws" ? 1 : 0
  name            = "${var.network_name}-cluster-${var.cluster_index}"
  target_type     = "ip"
  port            = 6443
  protocol        = "TCP"
  vpc_id          = aws_vpc.vpc[0].id

  health_check {
    protocol  = "TCP"
    port      = "6443"
    interval  = 30
    timeout   = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.network_name}-cluster-${var.cluster_index}"
  }
}

resource "aws_lb_target_group_attachment" "lb_target_group_attachment" {
  count            = 3
#  count            = var.cloud_type == "aws" ? length(aws_instance.kubernetes_controller) : 0
  target_group_arn = aws_lb_target_group.lb_target_group[0].arn
  target_id        = "10.0.1.1${count.index}"
#  target_id        = aws_instance.kubernetes_controller[count.index].private_ip
}
  
resource "aws_lb_listener" "lb_listener" {
  count             = var.cloud_type == "aws" ? 1 : 0
  load_balancer_arn = aws_lb.lb[0].arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type              = "forward"
    target_group_arn  = aws_lb_target_group.lb_target_group[0].arn
  }

  tags = {
    Name = "${var.network_name}-cluster-${var.cluster_index}"
  }
}
