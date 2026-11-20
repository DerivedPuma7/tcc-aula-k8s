job "web" {
  datacenters = ["dc1"]
  type        = "service"

  group "apache" {
    count = 3

    network {
      port "http" {
        static = 8080
        to     = 80
      }
    }

    task "httpd" {
      driver = "docker"

      config {
        image = "httpd:2.4"
        ports = ["http"]
      }
    }
  }
}
