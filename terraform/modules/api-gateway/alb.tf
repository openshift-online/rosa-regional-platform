# =============================================================================
# Internal Application Load Balancer
#
# This ALB is created by Terraform and remains empty until ArgoCD deploys
# a TargetGroupBinding that registers pod IPs into the target group.
#
# Flow: API Gateway -> VPC Link -> ALB -> Target Group -> Pods
# =============================================================================

# -----------------------------------------------------------------------------
# Application Load Balancer
# -----------------------------------------------------------------------------

resource "aws_lb" "frontend" {
  name               = "${var.resource_name_base}-api"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.private_subnet_ids

  tags = {
    Name = "${var.resource_name_base}-api"
  }
}

# -----------------------------------------------------------------------------
# Target Group
#
# Uses IP target type for TargetGroupBinding compatibility.
# EKS Auto Mode will register pod IPs when the TargetGroupBinding resource
# is created in Kubernetes.
#
# IMPORTANT: The eks:eks-cluster-name tag is REQUIRED for EKS Auto Mode.
# The AmazonEKSLoadBalancingPolicy has a condition that only allows
# RegisterTargets on target groups tagged with the cluster name.
# -----------------------------------------------------------------------------

resource "aws_lb_target_group" "frontend" {
  name_prefix = substr("${var.resource_name_base}-api-", 0, 6)
  port        = var.target_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Required for TargetGroupBinding

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    matcher             = "200"
  }

  tags = {
    Name                   = "${var.resource_name_base}-api"
    "eks:eks-cluster-name" = var.cluster_name
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Listener
# -----------------------------------------------------------------------------

resource "aws_lb_listener" "frontend" {
  load_balancer_arn = aws_lb.frontend.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}
