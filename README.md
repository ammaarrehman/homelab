# Homelab

A growing set of self-hosted networking and infrastructure projects, built and documented as I learn. Most of this runs on a Raspberry Pi 5, plus a cloud project built with Terraform. Each project has its own folder with a full writeup, the steps I took, the concepts behind it, and screenshots.

## Projects

### [Home Network DNS Filtering and Recursive Resolution](dns-filtering/)
AdGuard Home for DNS filtering, with Unbound behind it doing recursive resolution straight from the root servers and validating DNSSEC locally. Private DNS with no public resolver in the middle.
**Raspberry Pi, Linux, AdGuard Home, Unbound, DNS, DNSSEC**

### [Self-Hosted Uptime Monitoring](uptime-monitoring/)
Uptime Kuma running in Docker, monitoring the services from the DNS project plus the Pi and general connectivity, with a status dashboard and uptime history.
**Docker, Containers, Monitoring, Linux**

### [Remote Access with Tailscale](remote-access/)
Secure remote access to the Pi and its services from any network, with no ports opened on the router. Built on Tailscale's mesh VPN, which uses WireGuard underneath and NAT traversal instead of port forwarding.
**Tailscale, VPN, WireGuard, Networking, Remote Administration**

### [Metrics Monitoring with Prometheus and Grafana](monitoring-stack/)
A Docker Compose stack: Prometheus scrapes host and container metrics, Grafana visualizes them. Where uptime monitoring shows whether a service is up, this shows how the Pi and its containers are performing over time.
**Docker Compose, Prometheus, Grafana, Observability, Metrics**

### [Static Site on AWS with Terraform](terraform-aws-static-site/)
A static site provisioned entirely with Terraform: a private S3 bucket served over HTTPS through CloudFront with Origin Access Control. Infrastructure as Code, deployed and destroyed with one command, inside the AWS free tier.
**Terraform, AWS, S3, CloudFront, Infrastructure as Code**

### [Homelab Dashboard with Homepage](homepage/)
A single config-driven dashboard for the whole homelab, running in Docker. Live service status, quick links, and Pi system stats on one page. Becomes the rack touchscreen's display in kiosk mode.
**Docker, Homepage, YAML, Self-Hosting**

## Roadmap

- High availability DNS across two Raspberry Pis
- A self-hosted WireGuard setup (PiVPN) to compare against Tailscale
- Alertmanager on top of the Prometheus stack for notifications

## About

Built by Ammaar Rehman. Information Systems student working toward IT and cybersecurity roles, building this homelab project by project to get hands-on with Linux, networking, cloud, and self-hosted infrastructure.
