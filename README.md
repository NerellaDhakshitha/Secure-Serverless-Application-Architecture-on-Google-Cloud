# Secure Serverless Application Architecture on Google Cloud Platform

### Cloud Run | Terraform | Cloud Armor WAF | Load Balancing | Cloud Monitoring

## 1. Project Overview

This project demonstrates the implementation of a **secure, scalable, containerized serverless application architecture on Google Cloud Platform (GCP)**.

The application is hosted on **Google Cloud Run**, with an **External Application Load Balancer** providing the public entry point. **Cloud Armor WAF** is attached to the load balancer backend to filter incoming requests.

**Terraform** is used to manage the networking and security infrastructure, while **Cloud Logging and Cloud Monitoring** provide request visibility, performance metrics, and alerting.

### Project Objectives

- Deploy a containerized application using Google Cloud Run.
- Configure restricted Cloud Run ingress.
- Route external HTTP requests through an Application Load Balancer.
- Implement Cloud Armor WAF request filtering.
- Provision and manage networking and security resources using Terraform.
- Enable request logging and performance monitoring.
- Configure an alerting policy for high request rates.
- Validate infrastructure configuration and Terraform state.

---

## 2. Architecture Diagram

![Secure Serverless GCP Architecture](architecture/architecture.png)

### Application Request Flow

```text
Internet Users
      |
      v
External HTTP Application Load Balancer
      |
      v
Backend Service + Cloud Armor WAF
      |
      v
Serverless Network Endpoint Group
      |
      v
Google Cloud Run
      |
      v
Containerized Application
```

**Supporting Components**

- **Artifact Registry:** Stores the container image deployed to Cloud Run.
- **Cloud Logging:** Collects Cloud Run and load balancer request logs.
- **Cloud Monitoring:** Displays request metrics, latency, and alerting information.
- **Terraform:** Manages the load balancer, serverless NEG, and Cloud Armor resources.

---

## 3. Technologies Used

| Category | Technologies |
|---|---|
| Cloud Platform | Google Cloud Platform |
| Serverless Compute | Google Cloud Run |
| Container Registry | Google Artifact Registry |
| Networking | External Application Load Balancer, Serverless NEG |
| Security | Google Cloud Armor WAF, Cloud Run Ingress Controls |
| Infrastructure as Code | Terraform |
| Logging | Google Cloud Logging |
| Monitoring | Google Cloud Monitoring |
| CLI | Google Cloud CLI, Google Cloud Shell |

---

# 4. Implementation Workflow

## Step 1: Configure Google Cloud Project

Created a Google Cloud project and configured the active project in Cloud Shell.

**Project ID:** `secure-serverless-portfolio`

```bash
gcloud config set project secure-serverless-portfolio
```

Verified that billing was enabled.

Enabled the required Google Cloud APIs:

```bash
gcloud services enable run.googleapis.com
gcloud services enable artifactregistry.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable logging.googleapis.com
gcloud services enable monitoring.googleapis.com
```

These services provide the foundation for application hosting, networking, security, logging, and monitoring.

---

## Step 2: Container Image and Artifact Registry

The application container image was stored in Google Artifact Registry.

**Repository:** `secure-app-repo`

**Image:**

```text
us-central1-docker.pkg.dev/secure-serverless-portfolio/secure-app-repo/secure-app:v1
```

Artifact Registry provides managed storage for container images used by Cloud Run.

---

## Step 3: Deploy the Application to Cloud Run

Deployed the containerized application using Google Cloud Run.

### Cloud Run Configuration

| Property | Configuration |
|---|---|
| Service Name | secure-app |
| Region | us-central1 |
| Container Port | 8080 |
| Memory | 512 MiB |
| CPU | 1 vCPU |
| Minimum Instances | 0 |
| Maximum Instances | 3 |
| Ingress | Internal and Cloud Load Balancing |

The ingress configuration restricts direct public access and permits supported requests through Cloud Load Balancing.

### Verify Cloud Run Deployment

```bash
gcloud run services describe secure-app \
  --region=us-central1
```

### Cloud Run Deployment Screenshot

![Cloud Run Deployment](screenshots/01-cloud-run-service.png)

---

## Step 4: Configure Infrastructure as Code Using Terraform

Terraform was used to manage the load balancer and Cloud Armor infrastructure.

### Terraform Configuration Files

```text
terraform/
├── main.tf
├── provider.tf
└── variables.tf
```

### variables.tf

Defines reusable project and region variables.

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

Configures the Google Cloud Terraform provider.

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

Terraform manages six resources in this project:

1. Cloud Armor security policy.
2. Serverless Network Endpoint Group.
3. Backend service.
4. URL map.
5. HTTP target proxy.
6. Global forwarding rule.

---

## Step 5: Implement Cloud Armor WAF Security

Created a Cloud Armor security policy named `secure-app-waf`.

The policy contains a custom rule that blocks requests when the User-Agent header contains `BadBot`.

All other requests are permitted by the default allow rule.

### Terraform Configuration

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

### Cloud Armor Security Rules

![Cloud Armor WAF Rules](screenshots/07-cloud-armor-waf-rules.png)

This rule demonstrates application-layer request filtering. It is a demonstration rule rather than comprehensive bot protection.

---

## Step 6: Create a Serverless Network Endpoint Group

Created a serverless Network Endpoint Group (NEG) to connect the load balancer backend to the Cloud Run service.

**NEG Name:** `secure-app-neg`

### Terraform Configuration

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

The serverless NEG provides the integration between the load balancer backend and Cloud Run.

---

## Step 7: Configure the Load Balancer Backend Service

Created a backend service named `secure-app-backend`.

The backend service connects to the serverless NEG, attaches the Cloud Armor WAF policy, and enables request logging.

### Terraform Configuration

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

### Verify Backend Configuration

```bash
gcloud compute backend-services describe secure-app-backend \
  --global \
  --format="yaml(name,securityPolicy,backends,logConfig)"
```

The backend inspection confirmed the serverless NEG, attached Cloud Armor policy, and enabled request logging.

### Backend Service and Logging Screenshot

![Backend Logging Configuration](screenshots/06-backend-service-logging.png)

---

## Step 8: Configure the External Application Load Balancer

Configured an external HTTP Application Load Balancer using a URL map, HTTP target proxy, and global forwarding rule.

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

### Output the Public IP Address

```hcl
output "load_balancer_ip" {
  value = google_compute_global_forwarding_rule.frontend.ip_address
}
```

The observed frontend IP during implementation was `136.82.172.80`.

The load balancer uses HTTP on port 80.

### Verify Load Balancer Resources

```bash
gcloud compute forwarding-rules list --global

gcloud compute backend-services list --global

gcloud compute network-endpoint-groups list \
  --regions=us-central1

gcloud compute security-policies list
```

### Load Balancer and Cloud Armor Resources

![Load Balancer Resources](screenshots/05-load-balancer-and-cloud-armor-resources.png)

### URL Map Verification

![URL Map Configuration](screenshots/08-url-map-and-logging.png)

---

## Step 9: Test HTTP Requests and Cloud Armor Filtering

Used `curl` to test requests through the load balancer frontend.

### Test 1: Normal HTTP Request

```bash
curl -sS -o /dev/null \
  -w "HTTP status: %{http_code}\n" \
  http://136.82.172.80/
```

**Expected result:** The application responds successfully for a valid route, typically with HTTP 200.

### Normal Request Screenshot

![Normal HTTP Request](screenshots/09-normal-request.png)

### Test 2: Blocked User-Agent Request

```bash
curl -sS -A "BadBot" -o /dev/null \
  -w "HTTP status: %{http_code}\n" \
  http://136.82.172.80/
```

**Expected result:** HTTP 403 Forbidden when the Cloud Armor rule matches.

### Cloud Armor WAF Test Screenshot

![Cloud Armor Blocked Request](screenshots/10-badbot-blocked.png)

### Security Testing Summary

| Test | Expected Behavior |
|---|---|
| Normal request | Application response for a valid route |
| BadBot User-Agent | HTTP 403 Forbidden |

The actual HTTP status codes should be verified from the terminal outputs before treating these expected results as confirmed outcomes.

---

## Step 10: Enable Cloud Logging

Enabled Cloud Logging to inspect application requests and responses.

### Enable Logging API

```bash
gcloud services enable logging.googleapis.com
```

### Read Cloud Run Logs

```bash
gcloud run services logs read secure-app \
  --region=us-central1 \
  --limit=30
```

The Cloud Run logs included successful HTTP 200 requests and HTTP 404/405 responses for other paths or methods.

Backend request logging was also enabled with a sample rate of 1.0.

### Logging and Monitoring APIs

![Logging and Monitoring APIs](screenshots/04-monitoring-logging-apis.png)

---

## Step 11: Create Cloud Monitoring Dashboard

Created a Cloud Monitoring dashboard to visualize application traffic and performance.

### Dashboard Metrics

**1. Cloud Run Request Count**

Tracks the number of requests received by the Cloud Run service.

Filter:

```text
service_name = secure-app
```

**2. Cloud Run Request Latency**

Tracks request latency for the Cloud Run service.

Filter:

```text
service_name = secure-app
```

**3. Load Balancer Backend Request Count**

Displays the available load balancer backend request count metric. The chart was not confirmed to have a backend-specific filter.

### Cloud Monitoring Dashboard Screenshot

![Cloud Monitoring Dashboard](screenshots/11-cloud-monitoring-dashboard.png)

---

## Step 12: Configure Cloud Monitoring Alerting

Created an alerting policy to monitor high request rates.

### Alert Configuration

| Property | Value |
|---|---|
| Alert Name | Secure App - High Request Rate Alert |
| Condition | Cloud Run High Request Rate |
| Metric | Cloud Run Request Count |
| Threshold | Above 1 request/second |
| Retest Window | 5 minutes |
| Status | Enabled |

The threshold was configured for demonstrating alerting functionality.

### Alerting Policy Screenshot

![Cloud Monitoring Alert](screenshots/12-monitoring-alert-policy.png)

---

## Step 13: Validate Terraform Infrastructure

Validated the Terraform configuration and reviewed the managed infrastructure.

### Check Terraform Version

```bash
terraform version
```

**Terraform version used:** 1.7.5

### Inspect Terraform State

```bash
terraform state list
```

The state contained six managed resources:

```text
google_compute_backend_service.backend
google_compute_global_forwarding_rule.frontend
google_compute_region_network_endpoint_group.serverless_neg
google_compute_security_policy.waf_policy
google_compute_target_http_proxy.http_proxy
google_compute_url_map.url_map
```

### Terraform State Screenshot

![Terraform State](screenshots/13-terraform-version-and-state.png)

### Validate Terraform Configuration

```bash
terraform validate
```

**Observed result:**

```text
Success! The configuration is valid.
```

### Review Terraform Plan

```bash
terraform plan
```

**Observed result:**

```text
No changes. Your infrastructure matches the configuration.
```

This confirmed that the tracked infrastructure matched the Terraform configuration at the time of the plan.

### Terraform Validation and Plan Screenshot

![Terraform Validation and Plan](screenshots/14-terraform-validate-and-plan.png)

---

## 5. Repository Structure

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
│   └── variables.tf
│
└── screenshots/
    ├── 01-cloud-run-service.png
    ├── 04-monitoring-logging-apis.png
    ├── 05-load-balancer-and-cloud-armor-resources.png
    ├── 06-backend-service-logging.png
    ├── 07-cloud-armor-waf-rules.png
    ├── 08-url-map-and-logging.png
    ├── 09-normal-request.png
    ├── 10-badbot-blocked.png
    ├── 11-cloud-monitoring-dashboard.png
    ├── 12-monitoring-alert-policy.png
    ├── 13-terraform-version-and-state.png
    └── 14-terraform-validate-and-plan.png
```

**Note:** The Terraform configuration manages the load balancer, serverless NEG, and Cloud Armor resources. It references an existing Cloud Run service. The container image, Cloud Run service, monitoring dashboard, and alert policy are not provisioned by the six Terraform resources shown.

Terraform state files, local provider directories, and credentials should not be committed to the public repository.

---

## 6. Key Learnings

This project provided practical experience in:

- Deploying containerized applications on Google Cloud Run.
- Configuring restricted ingress for serverless applications.
- Implementing external HTTP load balancing with serverless backends.
- Creating Cloud Armor WAF rules for application-layer request filtering.
- Managing networking and security infrastructure with Terraform.
- Enabling backend request logging and inspecting Cloud Run logs.
- Building Cloud Monitoring dashboards for request count and latency.
- Configuring Cloud Monitoring alerting policies.
- Validating Terraform configuration and infrastructure state.

---

## 7. Conclusion

This project demonstrates a security-focused serverless application architecture on Google Cloud Platform.

It combines **Cloud Run, Artifact Registry, External Application Load Balancing, Cloud Armor WAF, Terraform, Cloud Logging, and Cloud Monitoring** to demonstrate serverless deployment, infrastructure automation, application-layer request filtering, and observability.

The project strengthened my practical understanding of Google Cloud infrastructure, networking, security, and infrastructure as code.
