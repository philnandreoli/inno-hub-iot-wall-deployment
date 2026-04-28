# Threat Model — IoT Control Nexus

## System Overview

The IoT Control Nexus is a web dashboard for monitoring and commanding industrial devices (Beckhoff PLCs, Leuze barcode readers) via MQTT through Azure Event Grid. It consists of:

- **Frontend**: React 18 SPA authenticated via MSAL (Azure Entra ID), served by Nginx
- **Backend**: FastAPI (Python 3.11) API that publishes MQTT commands and reads telemetry from Fabric Eventhouse (Kusto)
- **Infrastructure**: Docker containers on Azure Container Apps, provisioned via bash scripts on Ubuntu hosts with k3s clusters connected to Azure Arc

## STRIDE Threat Analysis

### 1. Spoofing

| Threat | Component | Mitigation | Status |
|--------|-----------|------------|--------|
| Forged JWT tokens | Backend API | RS256 signature verification with Azure AD JWKS | ✅ Implemented |
| MQTT impersonation | Event Grid | OAuth2-JWT auth with Azure Managed Identity | ✅ Implemented |
| Service Principal credential theft | Provisioning scripts | Secrets passed via command-line args (visible in /proc) | ⚠️ Issue #37 |
| Man-in-the-middle on SSH | Deployment scripts | SSH host key checking disabled | ⚠️ Issue #35 |

### 2. Tampering

| Threat | Component | Mitigation | Status |
|--------|-----------|------------|--------|
| MQTT payload injection | Backend → Event Grid | Device name validation (alphanumeric + suffix check), JSON serialization | ✅ Implemented |
| KQL injection | Backend → Eventhouse | Parameterized queries via ClientRequestProperties | ✅ Implemented |
| Docker image tampering | CI/CD | Mutable latest tag allows image replacement | ⚠️ Issue #41 |
| Nginx config injection | Frontend container | BACKEND_URL env var used unsanitized in sed | ⚠️ Issue #39 |

### 3. Repudiation

| Threat | Component | Mitigation | Status |
|--------|-----------|------------|--------|
| Unattributed device commands | Backend API | JWT claims extracted (identity available), MQTT correlation ID | ✅ Implemented |
| Missing audit trail | Backend API | Azure Application Insights + OpenTelemetry configured | ✅ Implemented |
| Anonymous device control | All endpoints | All device command endpoints require JWT auth | ✅ Implemented |

### 4. Information Disclosure

| Threat | Component | Mitigation | Status |
|--------|-----------|------------|--------|
| Token theft via XSS | Frontend | MSAL tokens stored in localStorage | ⚠️ Issue #27 |
| App Insights key in image layers | Docker build | Connection string as build arg | ⚠️ Issue #38 |
| Verbose auth logging | Frontend | MSAL LogLevel.Verbose in all environments | ⚠️ Issue #25 |
| Kubeconfig exposed | k3s VM | /etc/rancher/k3s/k3s.yaml chmod 644 | ⚠️ Issue #42 |
| OpenAPI docs exposed | Backend API | Docs enabled by default in all environments | ⚠️ Issue #23 |

### 5. Denial of Service

| Threat | Component | Mitigation | Status |
|--------|-----------|------------|--------|
| API flooding | Backend API | No rate limiting on command endpoints | ⚠️ Issue #24 |
| MQTT command flooding | Event Grid | QoS 1 + message expiry (60s) limits queue growth | ✅ Partial |
| Telemetry query timeout | Eventhouse | 4-minute server timeout + client retries with backoff | ✅ Implemented |
| Large date range queries | Backend API | 60-day max range + server-side downsampling for >1 day | ✅ Implemented |

### 6. Elevation of Privilege

| Threat | Component | Mitigation | Status |
|--------|-----------|------------|--------|
| Container escape | Docker | Running as root in containers | ⚠️ Issue #28 (Fixed) |
| Missing CORS policy | Backend API | No CORSMiddleware configured | ⚠️ Issue #40 |
| JWT issuer bypass | Backend API | verify_iss: False in PyJWT, manual check after | ⚠️ Issue #29 |
| XSS via Mermaid | Frontend | securityLevel loose + innerHTML | ⚠️ Issue #26 |

## Trust Boundaries

1. **Internet → Nginx**: TLS termination, security headers, CSP
2. **Nginx → Backend**: Internal network (Container Apps), no additional auth
3. **Backend → Event Grid**: TLS 8883 + OAuth2 JWT
4. **Backend → Fabric Eventhouse**: Azure SDK with Managed Identity
5. **Host → VM**: SSH over OT network (private LAN)
6. **CI/CD → Azure**: OIDC workload identity federation

## Security Controls Summary

### Implemented ✅
- Azure Entra ID (MSAL) authentication on frontend
- JWT RS256 token verification on backend with JWKS rotation
- Input validation for device names (regex + suffix), timespan, and date ranges
- Parameterized Kusto queries (no string interpolation of user input)
- TLS for MQTT connections with certificate verification
- Security headers in nginx (X-Frame-Options, X-Content-Type-Options, HSTS, CSP, Referrer-Policy, Permissions-Policy)
- OIDC workload identity in CI/CD (no stored Azure secrets)
- Secrets stored in Azure Key Vault
- .env files in .gitignore

### Missing/Weak ⚠️
- No rate limiting
- No CORS middleware
- Mutable image tags
- SSH host key verification disabled
- Service principal secrets in process arguments
- Kubeconfig world-readable

## Recommendations for Manual Review

1. **Azure Container Apps networking**: Verify the backend is not publicly accessible outside of the nginx proxy
2. **MQTT topic ACLs**: Verify Azure Event Grid namespace topic spaces restrict which clients can publish to which topics
3. **Managed Identity scope**: Verify the DefaultAzureCredential used by backend has minimum required permissions
4. **Key Vault access policies**: Verify only required services have access to deployment secrets
5. **Network segmentation**: Verify OT network (192.168.30.x) is properly isolated from IT network
