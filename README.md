# Secure Serverless Application Architecture on Google Cloud Platform

## Project Overview

This project demonstrates the deployment and security of a containerized serverless application on Google Cloud Platform (GCP).

The architecture integrates **Cloud Run, Artifact Registry, an External Application Load Balancer, Cloud Armor WAF, Cloud Logging, Cloud Monitoring, and Terraform** to build a scalable and security-focused cloud environment.

The application runs on Cloud Run with restricted ingress, while an external HTTP load balancer provides the public entry point. Cloud Armor applies request-filtering rules, and Google Cloud's observability services provide logging, metrics, and alerting.

Terraform is used to manage the load-balancing and Cloud Armor infrastructure as code.

## Architecture

![GCP Architecture](architecture/architecture.png)

### Request Flow

```text
Internet Users
      |
      v
External HTTP Application Load Balancer
      |
      v
Cloud Armor WAF
      |
      v
Backend Service
      |
      v
Serverless Network Endpoint Group (NEG)
      |
      v
Cloud Run (secure-app)
      |
      v
Containerized Application
```

**Supporting services:**

- Artifact Registry — stores the application container image.
- Cloud Logging — collects application and load-balancer logs.
- Cloud Monitoring — provides request metrics, latency charts, and alerting.
- Terraform — manages the load balancer, serverless NEG, and Cloud Armor resources.

## Technologies Used

| Category | Technologies |
|---|---|
| Cloud Platform | Google Cloud Platform |
| Serverless Compute | Google Cloud Run |
| Container Registry | Google Artifact Registry |
| Networking | External Application Load Balancer, Serverless NEG |
| Security | Google Cloud Armor WAF, IAM, Cloud Run Ingress Controls |
| Infrastructure as Code | Terraform |
| Logging | Google Cloud Logging |
| Monitoring | Google Cloud Monitoring |
| Command Line | Google Cloud CLI, Cloud Shell |

---

# Implementation Workflow

## Step 1: Configure the Google Cloud Project

Created a GCP project and configured Cloud Shell for infrastructure deployment.

**Project ID:** `secure-serverless-portfolio`

```bash
gcloud config set project secure-serverless-portfolio
```

Verified that billing was enabled for the project.

Enabled the required Google Cloud APIs for the application and supporting infrastructure.

```bash
gcloud services enable run.googleapis.com
gcloud services enable artifactregistry.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable logging.googleapis.com
```

## Step 2: Containerized Application and Artifact Registry

The application was packaged as a container image and stored in Google Artifact Registry.

**Artifact Registry repository:** `secure-app-repo`

**Container image:**

```text
us-central1-docker.pkg.dev/secure-serverless-portfolio/secure-app-repo/secure-app:v1
```

Artifact Registry provides a managed location for storing the container image used by Cloud Run.

## Step 3: Deploy the Application on Cloud Run

Deployed the container image to Google Cloud Run.

**Deployment configuration:**

| Setting | Configuration |
|---|---|
| Service | secure-app |
| Region | us-central1 |
| Container Port | 8080 |
| Memory | 512 MiB |
| CPU | 1 vCPU |
| Minimum Instances | 0 |
| Maximum Instances | 3 |
| Ingress | Internal and Cloud Load Balancing |

The ingress setting restricts direct public access to the Cloud Run service and allows requests through supported internal paths and Cloud Load Balancing.

Verified the deployed service using:

```bash
gcloud run services describe secure-app \
  --region=us-central1
```

## Step 4: Configure Terraform

Terraform was used to provision and manage the load balancer and security resources.

Created the following Terraform configuration files:

```text
terraform/
├── main.tf
├── provider.tf
└── variables.tf
```

### variables.tf

Defined reusable variables for the Google Cloud project and region.

```hcl
variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

variable "region" {
  description = "The GCP Region"
  type        = string
  default     = "us-central1"
}
```

### provider.tf

Configured the Google Cloud Terraform provider.

```hcl
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
```

The Terraform configuration manages six infrastructure resources.

## Step 5: Create the Cloud Armor WAF Policy

Created a Cloud Armor security policy named `secure-app-waf`.

The policy contains two rules:

1. Deny requests containing `BadBot` in the User-Agent header.
2. Allow other requests through the default rule.

**Terraform configuration:**

```hcl
resource "google_compute_security_policy" "waf_policy" {
  name = "secure-app-waf"

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
```

The custom rule demonstrates application-layer request filtering. It is intended as a WAF demonstration rather than comprehensive bot protection.

## Step 6: Configure the Serverless Network Endpoint Group

Created a serverless Network Endpoint Group (NEG) to connect the load balancer backend to Cloud Run.

**Resource name:** `secure-app-neg`

```hcl
resource "google_compute_region_network_endpoint_group" "serverless_neg" {
  name                  = "secure-app-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = "secure-app"
  }
}
```

The serverless NEG acts as the connection between the load balancer backend and the Cloud Run service.

## Step 7: Configure the Load Balancer Backend

Created the backend service and connected it to the serverless NEG.

**Backend service:** `secure-app-backend`

Attached the Cloud Armor WAF policy and enabled backend request logging.

```hcl
resource "google_compute_backend_service" "backend" {
  name     = "secure-app-backend"
  protocol = "HTTP"

  backend {
    group = google_compute_region_network_endpoint_group.serverless_neg.id
  }

  security_policy = google_compute_security_policy.waf_policy.id

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}
```

**Configuration details:**

- Serverless NEG as the backend.
- Cloud Armor security policy attached.
- Backend request logging enabled.
- Logging sample rate configured to 100%.

## Step 8: Configure the External Application Load Balancer

Configured a URL map, HTTP target proxy, and global forwarding rule.

### URL Map

```hcl
resource "google_compute_url_map" "url_map" {
  name            = "secure-app-url-map"
  default_service = google_compute_backend_service.backend.id
}
```

### HTTP Target Proxy

```hcl
resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "secure-app-http-proxy"
  url_map = google_compute_url_map.url_map.id
}
```

### Global Forwarding Rule

```hcl
resource "google_compute_global_forwarding_rule" "frontend" {
  name       = "secure-app-frontend"
  target     = google_compute_target_http_proxy.http_proxy.id
  port_range = "80"
}
```

### Load Balancer IP Output

```hcl
output "load_balancer_ip" {
  value = google_compute_global_forwarding_rule.frontend.ip_address
}
```

The forwarding rule exposes the application through the external HTTP load balancer on port 80.

The observed frontend IP during implementation was:

```text
136.82.172.80
```

This address is a deployment-specific value and may change if the frontend resource is recreated.

## Step 9: Verify Load Balancer and Security Resources

Verified the created infrastructure using Google Cloud CLI.

**Forwarding rule:**

```bash
gcloud compute forwarding-rules list --global
```

**Backend service:**

```bash
gcloud compute backend-services list --global
```

**Serverless NEG:**

```bash
gcloud compute network-endpoint-groups list \
  --regions=us-central1
```

**Cloud Armor policy:**

```bash
gcloud compute security-policies list
```

**Backend logging and security policy attachment:**

```bash
gcloud compute backend-services describe secure-app-backend \
  --global \
  --format="yaml(name,securityPolicy,backends,logConfig)"
```

The resource inspection confirmed the backend service, serverless NEG, attached Cloud Armor policy, and enabled backend request logging.

## Step 10: Test Application Access and WAF Filtering

Used `curl` to test the load balancer endpoint and the Cloud Armor User-Agent filtering rule.

### Normal HTTP Request

```bash
curl -sS -o /dev/null \
  -w "HTTP status: %{http_code}\n" \
  http://136.82.172.80/
```

### Request with Blocked User-Agent

```bash
curl -sS -A "BadBot" -o /dev/null \
  -w "HTTP status: %{http_code}\n" \
  http://136.82.172.80/
```

**Expected behavior:**

| Request | Expected Response |
|---|---|
| Normal request | Application response, typically HTTP 200 for a valid route |
| BadBot User-Agent | HTTP 403 Forbidden |

The Cloud Armor policy is configured to deny matching requests. Actual HTTP responses should be confirmed from the terminal test results.

## Step 11: Configure Cloud Logging and Monitoring

Enabled Cloud Logging and Cloud Monitoring APIs to support observability.

### Cloud Logging

Used Cloud Run service logs to inspect incoming requests and application responses.

```bash
gcloud run services logs read secure-app \
  --region=us-central1 \
  --limit=30
```

Observed successful HTTP 200 responses as well as HTTP 404 and 405 responses for other requested paths or methods.

### Cloud Monitoring Dashboard

Created a Cloud Monitoring dashboard with three charts:

1. **Cloud Run Request Count** — tracks incoming requests to `secure-app`.
2. **Cloud Run Request Latency** — tracks request latency for the service.
3. **Load Balancer Backend Request Count** — displays the backend request count metric.

The Cloud Run charts were filtered to the `secure-app` service. The load balancer chart used the available backend request metric without a verified backend-specific filter.

### Alerting Policy

Created and enabled an alerting policy.

| Setting | Value |
|---|---|
| Alert Name | Secure App - High Request Rate Alert |
| Condition | Cloud Run High Request Rate |
| Metric | Cloud Run Request Count |
| Threshold | Above 1 request/second |
| Retest Window | 5 minutes |
| Status | Enabled |

The threshold was selected to demonstrate request-rate alerting.

## Step 12: Validate the Terraform Infrastructure

Verified the Terraform installation and checked the managed infrastructure.

### Terraform Version

```bash
terraform version
```

**Version used:** Terraform v1.7.5

### Inspect Terraform State

```bash
terraform state list
```

The state contained the following six resources:

```text
google_compute_backend_service.backend
google_compute_global_forwarding_rule.frontend
google_compute_region_network_endpoint_group.serverless_neg
google_compute_security_policy.waf_policy
google_compute_target_http_proxy.http_proxy
google_compute_url_map.url_map
```

### Validate Configuration

```bash
terraform validate
```

**Result:**

```text
Success! The configuration is valid.
```

### Review Infrastructure Plan

```bash
terraform plan
```

The reviewed Terraform plan reported:

```text
No changes. Your infrastructure matches the configuration.
```

This confirmed that the tracked infrastructure matched the Terraform configuration at the time of validation.

---

## Project Screenshots

Screenshots provide evidence of the deployed services, security configuration, monitoring, and Terraform validation.

| Component | Screenshot |
|---|---|
| Cloud Run Service | `screenshots/01-cloud-run-service.png` |
| Cloud Logging and Monitoring APIs | `screenshots/04-monitoring-logging-apis.png` |
| Load Balancer and Cloud Armor Resources | `screenshots/05-load-balancer-and-cloud-armor-resources.png` |
| Backend Logging Configuration | `screenshots/06-backend-service-logging.png` |
| Cloud Armor WAF Rules | `screenshots/07-cloud-armor-waf-rules.png` |
| URL Map and Logging | `screenshots/08-url-map-and-logging.png` |
| Normal HTTP Request Test | `screenshots/09-normal-request.png` |
| Cloud Armor BadBot Test | `screenshots/10-badbot-blocked.png` |
| Cloud Monitoring Dashboard | `screenshots/11-cloud-monitoring-dashboard.png` |
| Monitoring Alert Policy | `screenshots/12-monitoring-alert-policy.png` |
| Terraform State | `screenshots/13-terraform-version-and-state.png` |
| Terraform Validation and Plan | `screenshots/14-terraform-validate-and-plan.png` |


---

## Repository Structure

```text
secure-serverless-portfolio/
│
├── README.md
│
├── architecture/
│   └── architecture.png
│
├── terraform/
│   ├── main.tf
│   ├── provider.tf
│   ├── variables.tf
│   └── terraform.tfvars.example
│
└── screenshots/
    └── Project verification screenshots
```

The Terraform configuration references an existing Cloud Run service. The Cloud Run deployment, container image, monitoring dashboard, and alert policy are not created by the six Terraform resources shown in this repository.

## Key Learnings

Through this project, I gained practical experience with:

- Deploying and configuring a containerized application using Google Cloud Run.
- Restricting Cloud Run ingress and routing traffic through an external Application Load Balancer.
- Connecting Cloud Run to a load balancer through a serverless NEG.
- Creating and attaching Cloud Armor WAF security policies.
- Managing GCP networking and security resources using Terraform.
- Enabling request logging and analyzing Cloud Run service logs.
- Creating Cloud Monitoring dashboards and alerting policies.
- Validating Terraform configurations and reviewing infrastructure state.

## Conclusion

This project demonstrates the integration of serverless computing, cloud networking, application-layer security, infrastructure as code, and observability on Google Cloud Platform.

By combining Cloud Run, an external Application Load Balancer, Cloud Armor, Terraform, Cloud Logging, and Cloud Monitoring, the project provides hands-on experience with the configuration and verification of a security-focused serverless architecture.
