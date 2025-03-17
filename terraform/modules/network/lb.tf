resource "aws_lb" "kubernetes" {
  name                = "kubernetes"
  internal            = false
  load_balancer_type  = "network"
  subnets             = [aws_subnet.kubernetes.id]
}

resource "aws_lb_target_group" "kubernetes" {
  name            = "kubernetes"
  target_type     = "ip"
  port            = 6443
  protocol        = "TCP"
  vpc_id          = aws_vpc.kubernetes-the-hard-way.id

  health_check {
    protocol  = "TCP"
    port      = "6443"
    interval  = 30
    timeout   = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group_attachment" "kubernetes" {
  count               = 3
  target_group_arn    = aws_lb_target_group.kubernetes.arn
  target_id           = "10.0.1.1${count.index}"
}
  
resource "aws_lb_listener" "kubernetes" {
  load_balancer_arn = aws_lb.kubernetes.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type              = "forward"
    target_group_arn  = aws_lb_target_group.kubernetes.arn
  }
}
