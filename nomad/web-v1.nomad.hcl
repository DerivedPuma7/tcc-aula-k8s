job "web" {
  datacenters = ["dc1"]
  type        = "service"

  group "apache" {
    count = 1

    task "httpd" {
      driver = "docker"

      config {
        image = "httpd:2.4"
      }
    }
  }
}
