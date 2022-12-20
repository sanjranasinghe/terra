resource "aws_instance" "web" {
  ami           = "ami-0aa51c59d00ba919b"
  instance_type = "t3a.medium"
  key_name      = "sanjaya"

  tags = {
    Name = "test"
  }

  connection {
     type        = "ssh"
     user        = "admin"
     private_key = file("${path.module}/sanjaya.pem")
     host        = aws_instance.web.private_ip
   }

  provisioner "file" {
    source      = ""
    destination = "/home/admin/id_rsa"
   }
 user_data = file("nginx_name/${var.nginx_name}.sh")

}
