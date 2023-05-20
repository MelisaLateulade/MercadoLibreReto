provider "aws" {
  region = "us-east-1"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"] 

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "VPC" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "VPC"
  }
}

resource "aws_subnet" "Subnet" {
  vpc_id     = aws_vpc.VPC.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags = {
    Name = "Subnet"
  }
}

resource "aws_internet_gateway" "Gateway" {
  vpc_id = aws_vpc.VPC.id
}

resource "aws_route_table" "RouteTable" {
  vpc_id = aws_vpc.VPC.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.Gateway.id
  }
}

resource "aws_route_table_association" "RouteTable" {
  subnet_id      = aws_subnet.Subnet.id
  route_table_id = aws_route_table.RouteTable.id
}

resource "aws_security_group" "instance" {
  name        = "Meli_instance_and_Redis_SG"
  description = "Security group for the instance"
  vpc_id      = aws_vpc.VPC.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress { 
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.VPC.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "api" {
  name        = "Meli_Instance_SG"
  description = "Security group for the api"
  vpc_id      = aws_vpc.VPC.id

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_launch_configuration" "LaunchConfig" {
  name_prefix          = "Meli_API_Launch_Config" 
  image_id             = data.aws_ami.amazon_linux.id
  instance_type        = "t2.micro"
  security_groups      = [aws_security_group.instance.id, aws_security_group.api.id]

  user_data = <<-EOF
              #!/bin/bash
              echo 'export DATABASE_HOST=${aws_elasticache_cluster.ClusterRedis.cache_nodes[0].address}' >> ~/.bashrc
              echo 'export DNS_LB=${aws_elb.LoadBalancer.dns_name}/' >> ~/.bashrc
              source ~/.bashrc
              sudo yum update -y
              sudo yum install -y python3 git
              sudo amazon-linux-extras install python3.8
              sudo pip3 install flask
              sudo pip3 install redis
              git clone https://github.com/MelisaLateulade/MercadoLibreReto.git /home/ec2-user/meli
              python3 /home/ec2-user/meli/Main.py
              EOF
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "elb" {
  name        = "Meli_LB_SG"
  description = "Security group for the ELB"
  vpc_id      = aws_vpc.VPC.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elb" "LoadBalancer" {
  name               = "Meli-LoadBalancer"
  security_groups    = [aws_security_group.elb.id]
  subnets            = [aws_subnet.Subnet.id]

  listener {
    instance_port     = 5000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:5000/healthcheck"
    interval            = 30
  }
}

resource "aws_autoscaling_group" "asg" {
  launch_configuration = aws_launch_configuration.LaunchConfig.id
  min_size             = 1
  max_size             = 5
  desired_capacity     = 3
  vpc_zone_identifier  = [aws_subnet.Subnet.id]
  load_balancers       = [aws_elb.LoadBalancer.name]

  tag {
    key                 = "Name"
    value               = "API Auto Scaling Group"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale_up"
  autoscaling_group_name = aws_autoscaling_group.asg.id
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "cpu_high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "50"
  alarm_description   = "This metric checks cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale_down"
  autoscaling_group_name = aws_autoscaling_group.asg.id
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "cpu_low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "10"
  alarm_description   = "This metric checks cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }
}

resource "aws_iam_role" "IAMRole" {
  name               = "IAMRole"
  assume_role_policy = data.aws_iam_policy_document.PolicyDocument.json
}

data "aws_iam_policy_document" "PolicyDocument" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["autoscaling.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "PolicyAttach" {
  role       = aws_iam_role.IAMRole.name
  policy_arn = "arn:aws:iam::aws:policy/AutoScalingFullAccess"
}

resource "aws_security_group" "redis" {
  name        = "redis_security_group"
  description = "Security group for Redis"
  vpc_id      = aws_vpc.VPC.id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    security_groups = [aws_security_group.instance.id] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elasticache_subnet_group" "RedisSubnet" {
  name       = "RedisSubnet"
  subnet_ids = [aws_subnet.Subnet.id]

  description = "An RedisSubnet ElastiCache subnet group"
}

resource "aws_elasticache_cluster" "ClusterRedis" {
  cluster_id           = "my-cluster-redis"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis5.0"
  engine_version       = "5.0.6"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.RedisSubnet.name
  security_group_ids   = [aws_security_group.redis.id]
}

output "load_balancer_dns_name" {
  description = "The DNS name of the Load Balancer"
  value       = aws_elb.LoadBalancer.dns_name
}