# Karmada vs Azure Fleet Manager - Evaluation Summary

## TL;DR

We evaluated Karmada as an alternative to Azure Fleet Manager. While Karmada works technically, **supporting both platforms doubles our development and operational effort**. Azure Fleet Manager is recommended for Azure-focused deployments.

---

## Key Findings

### Development Effort - The Real Problem

**Supporting Karmada means maintaining TWO deployment systems:**

| Artifact | Azure Fleet Manager | Karmada | Impact |
|----------|---------------------|---------|--------|
| Deployment manifest | `ClusterResourcePlacement` | `PropagationPolicy` | **Different YAML schemas** |
| Namespace propagation | Automatic | `ClusterPropagationPolicy` required | Extra manifest |
| Override per-cluster | `ClusterResourceOverride` | `OverridePolicy` | Different API |
| Documentation | Azure Docs | Karmada Docs | **Two doc sets to maintain** |
| CI/CD pipelines | Fleet-specific | Karmada-specific | **Duplicate pipelines** |
| Testing | Fleet test matrix | Karmada test matrix | **Double testing effort** |

**Developer impact:**
- Every feature change requires updating **two template systems**
- Bug fixes must be validated on **both platforms**
- Documentation must cover **both workflows**
- Team must be trained on **both APIs**

### Operational Complexity

| Concern | Karmada | Fleet Manager |
|---------|---------|---------------|
| **Control plane management** | You deploy, upgrade, patch, monitor, backup | Fully managed by Microsoft |
| **HA setup** | Manual configuration required | Built-in |
| **Disaster recovery** | You design and implement | Azure handles it |
| **Upgrades** | Manual, requires planning and testing | Automatic, zero downtime |
| **Troubleshooting** | Community Slack/GitHub, no SLA | Microsoft Support with SLA |
| **On-call burden** | Your team owns Karmada issues | Microsoft owns infrastructure |
| **Security patching** | Your responsibility | Microsoft handles it |

### Integration Gaps

| Integration | Karmada | Fleet Manager |
|-------------|---------|---------------|
| Azure Portal | No visibility | Full dashboard |
| Azure RBAC | Manual mapping | Native integration |
| Azure Policy | Separate tooling | Built-in compliance |
| Azure Monitor | DIY (Prometheus/Grafana) | Native metrics & logs |
| Azure AD | Manual configuration | Seamless SSO |

### Karmada Pros (Limited Use Cases)

- Multi-cloud support (AKS + EKS + GKE in single control plane)
- Works with on-premises Kubernetes
- No Azure-specific dependencies

---

## Recommendation

### **Azure Fleet Manager is recommended** because:

1. **Single template system** - One deployment workflow to maintain
2. **Zero operational overhead** - Managed service, no infrastructure to run
3. **Native Azure integration** - Portal, RBAC, Policy, Monitor work out-of-box
4. **Enterprise support** - Microsoft SLA, not community Slack
5. **Familiar patterns** - Team already knows Azure

### When would Karmada make sense?

Only if:
- Multi-cloud is a **hard requirement** (must span AWS + Azure + GCP)
- On-premises clusters must be managed alongside cloud
- Dedicated platform team exists to manage Karmada infrastructure

---

## Key Trade-off

| Factor | Karmada | Fleet Manager |
|--------|---------|---------------|
| **Dev effort** | Maintain separate templates | Single template system |
| **Ops effort** | Self-managed control plane | Zero - managed service |
| **Learning curve** | New concepts for team | Familiar Azure patterns |
| **Support** | Community only | Microsoft enterprise |

> **Bottom line**: Supporting Karmada alongside Fleet Manager doubles our maintenance burden for a capability (multi-cloud) we don't currently need.

---

## Related Documents

- **Technical Comparison**: [KARMADA-VS-FLEET-MANAGER-REPORT.md](KARMADA-VS-FLEET-MANAGER-REPORT.md)
- **Karmada Setup Guide** (for reference): [COMPLETE-SETUP-GUIDE.md](COMPLETE-SETUP-GUIDE.md)
