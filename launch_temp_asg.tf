#Creating the vpc
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "demo-vpc"
  }
}
#Creating the pub subnets
resource "aws_subnet" "pub_subnets" {
  vpc_id = aws_vpc.vpc.id
  count = 2
  cidr_block = cidrsubnet("10.0.0.0/16", 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "pub-subnet-${count.index + 1}"
  }
}
data "aws_availability_zones" "available" {}
#Creating the rt
resource "aws_route_table" "pub_rt" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}
#Creating the igw
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "demo-igw"
  }
}
#Associating the pub subnets to the pub rt
resource "aws_route_table_association" "associate_1" {
  route_table_id = aws_route_table.pub_rt.id
  subnet_id = aws_subnet.pub_subnets[0].id
}
resource "aws_route_table_association" "associate_2" {
  route_table_id = aws_route_table.pub_rt.id
  subnet_id = aws_subnet.pub_subnets[1].id
}
#Setting the sg
resource "aws_security_group" "launch_sg" {
  name = "demo-launch-temp-sg"
  vpc_id = aws_vpc.vpc.id
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["1.2.3.4/32"] #Demo pub IP
  }
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
#Creating the launch template
resource "aws_launch_template" "template" {
  name = "demo-launch-template"
  image_id = "ami-077d7e91242395d35"
  instance_type = "t3.micro"
  vpc_security_group_ids = [aws_security_group.launch_sg.id]
  key_name = "demo-launch-temp"
  tags = {
    Name = "launch-temp"
    Environment = "Dev"
  }
  user_data = base64encode(
    <<EOF
    #!/bin/bash
    yum update -y
    yum install -y nginx
    systemctl enable nginx
    systemctl start nginx
    echo "Hello from a loser, me!" > /usr/share/nginx/html/index.html
    EOF
  )
  tag_specifications {
    resource_type = "instance"
    tags = {
        Name = "asg-instance"
        Environment = "bs"
    }
  }
}
#Setting the asg
resource "aws_autoscaling_group" "scale" {
  min_size = 2
  max_size = 3
  desired_capacity = 2
  name = "demo-asg"
  health_check_grace_period = 300
  health_check_type = "EC2"
  launch_template {
    id = aws_launch_template.template.id
    version = "$Latest"
  }
  vpc_zone_identifier = [aws_subnet.pub_subnets[0].id, aws_subnet.pub_subnets[1].id ]
}