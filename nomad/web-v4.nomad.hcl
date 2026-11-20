job "web" {
  datacenters = ["dc1"]
  type        = "service"

  group "apache" {
    count = 3

    network {
      port "http" {
        to = 80
      }
    }

    service {
      name     = "web"
      port     = "http"
      provider = "nomad"
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
