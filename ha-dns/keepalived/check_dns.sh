#!/bin/bash
# Healthy only if the local AdGuard answers DNS on port 53.
# We query a junk name and ignore the answer - we only care that
# AdGuard responded at all. dig exits 0 on any response (including
# NXDOMAIN) and non-zero on timeout, which is the signal keepalived
# uses to lower this node's priority and move the VIP away.
dig +short +tries=1 +time=2 @127.0.0.1 health.check.local A > /dev/null 2>&1
exit $?
