
locals {
    http_port = 80
    any_port = 0
    any_protocol = "-1"
    tcp_protocol = "tcp"
    all_ips = ["0.0.0.0/0"]
}

resource "aws_security_group" "instance" {
	name = "${var.cluster_name}-instance"

	ingress {
        from_port =  local.http_port
        to_port = local.http_port
        protocol = local.tcp_protocol
        cidr_blocks = local.all_ips 
	}
}

data "aws_vpc" "default" {
    default = true
}


data "aws_subnet_ids" "default" {
    vpc_id = data.aws_vpc.default.id

}

resource "aws_launch_configuration" "example" {
    image_id    = "ami-0283a57753b18025b"
    instance_type = var.instance_type
    key_name = var.keyname
    security_groups = [aws_security_group.instance.id]

    user_data = data.template_file.user_data.rendered

    lifecycle {
        create_before_destroy = true
    }

}

resource "aws_autoscaling_group" "example" {
    launch_configuration = aws_launch_configuration.example.name
    vpc_zone_identifier = data.aws_subnet_ids.default.ids

    target_group_arns = [aws_lb_target_group.asg.arn]
    health_check_type = "ELB"

    min_size = var.min_size
    max_size = var.max_size
    tag {
        key    = "Name"
        value    = "${var.cluster_name}-asg-example"
        propagate_at_launch = true
    }
}

#Create the ALB
resource "aws_lb" "example" {
    name = "${var.cluster_name}-alb"
    load_balancer_type = "application"
    subnets = data.aws_subnet_ids.default.ids
    security_groups = [aws_security_group.alb.id]

}

#listener for this ALB
resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.example.arn
    port = local.http_port
    protocol = "HTTP"

# By default, return a simple 404 page
default_action {
    type = "fixed-response"
    fixed_response {
        content_type = "text/plain"
        message_body = "404: page not found"
        status_code = 404
            }
    }
}

# Target Group
resource "aws_lb_target_group" "asg" {
    name = "${var.cluster_name}-asg"
    port = local.http_port
    protocol = "HTTP"
    vpc_id = data.aws_vpc.default.id

    health_check {
        path    =    "/"
        protocol    =    "HTTP"
        matcher    =    "200"
        interval    =    15
        timeout    =    3
        healthy_threshold    =    2
        unhealthy_threshold    =    2
    }
}


# SG for ALB
resource "aws_security_group" "alb" {
name = "${var.cluster_name}-alb-sg"

}

# Allow inbound HTTP requests by a rule
resource "aws_security_group_rule" "allow_http_inbound" {
    type = "ingress"
    security_group_id = aws_security_group.alb.id
    from_port =  local.http_port
    to_port = local.http_port
    protocol = local.tcp_protocol
    cidr_blocks = local.all_ips
}

# Allow all outbound requests
resource "aws_security_group_rule" "allow_all_outbound" {
    type = "egress"
    security_group_id = aws_security_group.alb.id
    from_port = local.any_port
    to_port = local.any_port
    protocol = local.any_protocol
    cidr_blocks = local.all_ips
    }

# ELB listner rule
resource "aws_lb_listener_rule" "asg" {
    listener_arn = aws_lb_listener.http.arn
    priority = 100

    condition {
    path_pattern {
    values = ["*"]
    }
}

    action {
        type = "forward"
        target_group_arn = aws_lb_target_group.asg.arn
    }
}


data "template_file" "user_data" {
    template = file("${path.module}/user-data.sh")
    vars = {
        html_body = var.html_body
    }
}

