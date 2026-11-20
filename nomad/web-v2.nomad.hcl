job "web" {
  datacenters = ["dc1"]
  type        = "service"

  group "apache" {
    count = 3

    task "httpd" {
      driver = "docker"

      config {
        image = "httpd:2.4"
      }
    }
  }
}
