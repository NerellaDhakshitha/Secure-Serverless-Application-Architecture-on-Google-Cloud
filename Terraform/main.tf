# 1. THE BOUNCER: Cloud Armor Web Application Firewall
resource "google_compute_security_policy" "waf_policy" {
  name = "secure-app-waf"

  # Rule 1: Kick out anyone pretending to be "BadBot"
  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      expr {
        expression = "request.headers['user-agent'].contains('BadBot')"
      }
    }
    description = "Block BadBot traffic"
  }

  # Rule 2: Allow all other normal customers
  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow"
  }
}

# 2. THE BRIDGE: Connects the Load Balancer to the Magic Kitchen (Cloud Run)
resource "google_compute_region_network_endpoint_group" "serverless_neg" {
  name                  = "secure-app-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region
  cloud_run {
    service = "secure-app"
  }
}

# 3. THE BACKEND: The system that manages the connection and holds the Bouncer
resource "google_compute_backend_service" "backend" {
  name        = "secure-app-backend"
  protocol    = "HTTP"
  
  backend {
    group = google_compute_region_network_endpoint_group.serverless_neg.id
  }
  
  # Attach the Bouncer (WAF) here!
  security_policy = google_compute_security_policy.waf_policy.id

  # TURN ON THE SECURITY CAMERAS (Cloud Logging)
  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# 4. THE TRAFFIC COP: The Load Balancer Frontend (URL Map, Proxy, and IP Rule)
resource "google_compute_url_map" "url_map" {
  name            = "secure-app-url-map"
  default_service = google_compute_backend_service.backend.id
}

resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "secure-app-http-proxy"
  url_map = google_compute_url_map.url_map.id
}

resource "google_compute_global_forwarding_rule" "frontend" {
  name       = "secure-app-frontend"
  target     = google_compute_target_http_proxy.http_proxy.id
  port_range = "80"
}

# 5. OUTPUT: Show us the final public IP address when finished!
output "load_balancer_ip" {
  value = google_compute_global_forwarding_rule.frontend.ip_address
}
