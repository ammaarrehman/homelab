# Homelab

A growing set of self-hosted networking and infrastructure projects, built and documented as I learn. Most of this runs on a Raspberry Pi 5, with cloud work to come. Each project has its own folder with a full writeup, the steps I took, the concepts behind it, and screenshots.

## Projects

### [Home Network DNS Filtering and Recursive Resolution](dns-filtering/)
AdGuard Home for DNS filtering, with Unbound behind it doing recursive resolution straight from the root servers and validating DNSSEC locally. Private DNS with no public resolver in the middle.
**Raspberry Pi, Linux, AdGuard Home, Unbound, DNS, DNSSEC**

### [Self-Hosted Uptime Monitoring](uptime-monitoring/)
Uptime Kuma running in Docker, monitoring the services from the DNS project plus the Pi and general connectivity, with a status dashboard and uptime history.
**Docker, Containers, Monitoring, Linux**

## Roadmap

- Remote access with Tailscale, then a self-hosted WireGuard setup
- A Grafana and Prometheus monitoring stack
- Infrastructure as Code on AWS with Terraform

## About

Built by Ammaar Rehman. Information Systems student working toward IT and cybersecurity roles, building this homelab project by project to get hands-on with Linux, networking, and self-hosted infrastructure.
