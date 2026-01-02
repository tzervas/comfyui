# SSO Authentication Flow - Comprehensive Test Plan

## Environment Configuration

- **Base URL**: `https://homelab.lan:8444`
- **Keycloak Admin Console**: `https://homelab.lan:8444/keycloak/admin/`
- **OAuth2-Proxy Prefix**: `/oauth2`
- **Realm**: `comfyui`
- **Test Users**:
  - `admin@homelab.lan` (admin role)
  - `user1@homelab.lan` (user role)
  - `user2@homelab.lan` (user role)
- **Keycloak Admin**: `kcadmin`

---

## Test Suite Overview

| Test ID | Category | Automation | Priority |
|---------|----------|------------|----------|
| TC-01 | Infrastructure Health | Automated | P0 |
| TC-02 | Keycloak Admin Access | Manual | P0 |
| TC-03 | Unauthenticated Access | Automated | P0 |
| TC-04 | Login Flow - Admin User | Manual | P0 |
| TC-05 | Login Flow - Regular User | Manual | P1 |
| TC-06 | Service Access - Authenticated | Automated | P1 |
| TC-07 | Role-Based Access Control | Manual | P1 |
| TC-08 | Logout Flow | Manual | P1 |
| TC-09 | Session Persistence | Manual | P2 |
| TC-10 | Invalid User Access | Automated | P2 |
| TC-11 | Token Expiration | Manual | P2 |

---

## Test Cases

### TC-01: Infrastructure Health Checks

**Objective**: Verify all SSO components are running and healthy

**Prerequisites**: Stack deployed with `SSO_ENABLED=1` and `KEYCLOAK_ENABLED=1`

**Test Steps**:

#### 1.1 OAuth2-Proxy Health Endpoint
```bash
# Test the ping endpoint (should be accessible without auth)
curl -v http://localhost:4180/oauth2/ping

# Expected: 200 OK with "OK" response
```

**Expected Results**:
- HTTP Status: `200 OK`
- Response Body: `OK`
- No authentication required

**Success Criteria**: ✓ OAuth2-Proxy responds to health checks

---

#### 1.2 Keycloak Health Endpoint (Internal)
```bash
# Check Keycloak container health
docker exec comfyui-homelab-keycloak-1 \
  curl -f http://localhost:9000/health/ready

# Expected: 200 OK with health status
```

**Expected Results**:
- HTTP Status: `200 OK`
- Response indicates Keycloak is ready

**Success Criteria**: ✓ Keycloak is healthy and ready

---

#### 1.3 Nginx Healthz Endpoint
```bash
# Unauthenticated health endpoint
curl -v https://homelab.lan:8444/healthz -k

# Expected: 200 OK
```

**Expected Results**:
- HTTP Status: `200 OK`
- Response Body: `ok`
- No authentication required

**Success Criteria**: ✓ Nginx ingress is responding

---

**Automation**: ✅ **AUTOMATED** - Can be scripted with curl

**Priority**: P0 (Must pass before other tests)

---

### TC-02: Keycloak Admin Console Access

**Objective**: Verify Keycloak admin console is accessible and credentials work

**Prerequisites**: 
- Keycloak admin credentials from `.env.homelab`
- Username: `kcadmin`
- Password: Check `KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD`

**Test Steps**:

#### 2.1 Access Admin Console
```bash
# Check if Keycloak admin console is accessible
curl -v https://homelab.lan:8444/keycloak/admin/ -k

# Expected: 200 OK with HTML login page
```

**Manual Steps**:
1. Open browser to `https://homelab.lan:8444/keycloak/admin/`
2. You should see Keycloak admin login page
3. Enter credentials:
   - Username: `kcadmin`
   - Password: `<from .env.homelab>`
4. Click "Sign In"

**Expected Results**:
- HTTP Status: `200 OK` for initial page load
- Login form displayed
- After login: Redirected to Keycloak admin dashboard
- No SSO auth_request applied (Keycloak has its own auth)

**Success Criteria**: 
- ✓ Admin console accessible
- ✓ Login successful
- ✓ Can view realm configuration
- ✓ See `comfyui` realm listed

---

#### 2.2 Verify Realm Configuration
**Manual Steps**:
1. Navigate to "Realm Settings" in Keycloak admin
2. Verify realm name: `comfyui`
3. Check "Clients" → Verify `comfyui-ingress` client exists
4. Check "Users" → Verify baseline users exist:
   - `admin@homelab.lan`
   - `user1@homelab.lan`
   - `user2@homelab.lan`
5. Check "Roles" → Verify roles exist:
   - `comfyui_admin`
   - `comfyui_user`

**Success Criteria**: 
- ✓ All baseline configuration present
- ✓ Client credentials match `.env.homelab`

---

**Automation**: ❌ **MANUAL** - Requires browser interaction with Keycloak UI

**Priority**: P0 (Required for SSO functionality)

---

### TC-03: Unauthenticated Access to Protected Resources

**Objective**: Verify unauthenticated requests are redirected to SSO login

**Prerequisites**: No existing session cookies

**Test Steps**:

#### 3.1 Root Path Access
```bash
# Attempt to access root without authentication
curl -v -L https://homelab.lan:8444/ -k 2>&1 | grep -E "HTTP|Location:"

# Expected: Redirect to OAuth2-Proxy login flow
```

**Expected Results**:
- Initial HTTP Status: `302 Found`
- `Location` header: `/oauth2/start?rd=https://homelab.lan:8444/`
- Following redirect leads to Keycloak login page

**Success Criteria**: ✓ Unauthenticated access triggers redirect

---

#### 3.2 ComfyUI Access
```bash
# Attempt to access ComfyUI without authentication
curl -v -L https://homelab.lan:8444/comfyui/ -k 2>&1 | grep -E "HTTP|Location:"

# Expected: Redirect to OAuth2-Proxy login flow
```

**Expected Results**:
- Initial HTTP Status: `302 Found`
- `Location` header: `/oauth2/start?rd=https://homelab.lan:8444/comfyui/`

**Success Criteria**: ✓ Protected service triggers redirect

---

#### 3.3 Model Vault Access
```bash
# Attempt to access Model Vault without authentication
curl -v -L https://homelab.lan:8444/model-vault/ -k 2>&1 | grep -E "HTTP|Location:"

# Expected: Redirect to OAuth2-Proxy login flow
```

**Expected Results**:
- Initial HTTP Status: `302 Found`
- Redirect to OAuth2 login flow

**Success Criteria**: ✓ API endpoints also protected

---

#### 3.4 Verify All Protected Endpoints
```bash
# Test multiple endpoints in sequence
for endpoint in "/" "/comfyui/" "/ollama/" "/langchain/" "/langflow/" "/code-executor/" "/model-vault/"; do
  echo "Testing: $endpoint"
  curl -s -o /dev/null -w "%{http_code} - %{redirect_url}\n" \
    https://homelab.lan:8444$endpoint -k
done

# Expected: All return 302 with redirect to /oauth2/start
```

**Expected Results**:
- All endpoints return `302`
- All redirect to `/oauth2/start?rd=<original_url>`

**Success Criteria**: ✓ All services protected by SSO

---

**Automation**: ✅ **AUTOMATED** - Can be fully scripted

**Priority**: P0 (Core security requirement)

---

### TC-04: Login Flow - Admin User

**Objective**: Complete end-to-end login flow with admin user

**Prerequisites**: 
- No existing session
- Admin credentials from `.env.homelab`
- Username: `admin@homelab.lan`
- Password: Check `SSO_ADMIN_PASS`

**Test Steps**:

#### 4.1 Initiate Login
**Manual Steps**:
1. Open browser in incognito/private mode
2. Navigate to `https://homelab.lan:8444/`
3. Accept self-signed certificate warning (if applicable)
4. Verify redirect to Keycloak login page

**Expected Results**:
- URL redirects to `/oauth2/start?rd=...`
- Then redirects to Keycloak: `/keycloak/realms/comfyui/protocol/openid-connect/auth?...`
- Login form displayed with "comfyui" realm branding

---

#### 4.2 Enter Credentials
**Manual Steps**:
1. Enter username: `admin@homelab.lan`
2. Enter password from `.env.homelab` (`SSO_ADMIN_PASS`)
3. Click "Sign In"

**Expected Results**:
- If first login: Redirect to "Update Password" page
- User must set new password
- Then redirect to "Configure OTP" page (TOTP/MFA)

---

#### 4.3 First-Time Setup (If Applicable)
**Manual Steps**:
1. **Update Password**:
   - Enter new password (twice)
   - Submit
2. **Configure TOTP**:
   - Scan QR code with authenticator app (Google Authenticator, Authy, etc.)
   - Enter 6-digit code
   - Submit

**Expected Results**:
- Password updated successfully
- TOTP enrolled successfully
- Redirect to OAuth2-Proxy callback URL

---

#### 4.4 OAuth Callback
**Expected Results**:
- URL redirects to `/oauth2/callback?code=...&state=...`
- OAuth2-Proxy exchanges code for token
- Session cookie set: `_oauth2_proxy`
- Final redirect to original destination: `https://homelab.lan:8444/`

---

#### 4.5 Verify Authenticated Access
**Manual Steps**:
1. Verify you can see the landing page
2. Navigate to `/comfyui/` - should load without redirect
3. Check browser cookies:
   - Cookie name: `_oauth2_proxy`
   - Secure: `true`
   - HttpOnly: `true`
   - SameSite: `Lax`

**Expected Results**:
- All protected resources accessible
- No authentication redirects
- Session cookie present

---

**Automation**: ❌ **MANUAL** - Requires browser interaction, TOTP enrollment

**Priority**: P0 (Critical path for admin access)

---

### TC-05: Login Flow - Regular User

**Objective**: Verify regular users can log in successfully

**Prerequisites**: 
- No existing session
- User credentials from `.env.homelab`
- Test with both:
  - `user1@homelab.lan` / `SSO_USER1_PASS`
  - `user2@homelab.lan` / `SSO_USER2_PASS`

**Test Steps**:

#### 5.1 Login as User1
**Manual Steps**:
1. Open browser in incognito/private mode
2. Navigate to `https://homelab.lan:8444/`
3. Enter credentials for `user1@homelab.lan`
4. Complete password update (first login)
5. Note: Regular users do NOT get TOTP prompt by default

**Expected Results**:
- Password update required on first login
- No TOTP configuration prompt (admin only)
- Successful redirect to original destination
- Session cookie set

**Success Criteria**: 
- ✓ User can log in
- ✓ No MFA prompt for regular users
- ✓ Access to protected resources

---

#### 5.2 Login as User2
**Manual Steps**:
1. Repeat above steps for `user2@homelab.lan`

**Success Criteria**: ✓ Second user can also authenticate

---

**Automation**: ❌ **MANUAL** - Requires browser interaction

**Priority**: P1 (Important for multi-user validation)

---

### TC-06: Service Access After Authentication

**Objective**: Verify authenticated users can access all services

**Prerequisites**: Active session (logged in as any user)

**Test Steps**:

#### 6.1 Access ComfyUI
```bash
# Save cookies from browser session to file
# Then test with curl
curl -v -b cookies.txt https://homelab.lan:8444/comfyui/ -k

# Expected: 200 OK with ComfyUI HTML
```

**Manual Steps**:
1. Navigate to `https://homelab.lan:8444/comfyui/`
2. Verify ComfyUI interface loads
3. Test workflow creation (basic functionality check)

**Expected Results**:
- HTTP Status: `200 OK`
- ComfyUI interface rendered
- No authentication redirect

---

#### 6.2 Access Ollama API
```bash
# With session cookie
curl -v -b cookies.txt https://homelab.lan:8444/ollama/api/tags -k

# Expected: 200 OK with models list
```

**Expected Results**:
- HTTP Status: `200 OK`
- JSON response with available models

---

#### 6.3 Access LangChain
```bash
# With session cookie
curl -v -b cookies.txt https://homelab.lan:8444/langchain/ -k

# Expected: 200 OK
```

**Expected Results**:
- HTTP Status: `200 OK`
- Service accessible

---

#### 6.4 Access LangFlow
**Manual Steps**:
1. Navigate to `https://homelab.lan:8444/langflow/`

**Expected Results**:
- LangFlow UI loads successfully

---

#### 6.5 Access Model Vault
```bash
# With session cookie
curl -v -b cookies.txt https://homelab.lan:8444/model-vault/health -k

# Expected: 200 OK
```

**Expected Results**:
- HTTP Status: `200 OK`

---

#### 6.6 Complete Service Access Matrix
```bash
# Automated test for all services
for endpoint in "/comfyui/" "/ollama/" "/langchain/" "/langflow/" "/code-executor/" "/model-vault/"; do
  echo "Testing: $endpoint"
  status=$(curl -s -b cookies.txt -o /dev/null -w "%{http_code}" \
    https://homelab.lan:8444$endpoint -k)
  echo "  Status: $status"
  if [ "$status" = "200" ] || [ "$status" = "302" ]; then
    echo "  ✓ PASS"
  else
    echo "  ✗ FAIL"
  fi
done
```

**Expected Results**:
- All services return `200 OK` or appropriate success status
- No `401` or `403` errors
- No unexpected redirects

**Success Criteria**: ✓ All services accessible with valid session

---

**Automation**: ⚠️ **SEMI-AUTOMATED** 
- Cookie extraction: Manual (export from browser)
- Service testing: Automated (curl with cookies)

**Priority**: P1 (Validates core functionality)

---

### TC-07: Role-Based Access Control (RBAC)

**Objective**: Verify role-based permissions work correctly

**Note**: This test depends on whether RBAC is implemented at the service level. Currently, OAuth2-Proxy validates authentication but may not enforce granular role-based authorization.

**Prerequisites**: 
- Admin session
- Regular user session

**Test Steps**:

#### 7.1 Check User Claims
**Manual Steps**:
1. Log in as `admin@homelab.lan`
2. Access OAuth2-Proxy userinfo endpoint:
```bash
curl -v -b cookies.txt https://homelab.lan:8444/oauth2/userinfo -k
```

**Expected Results**:
```json
{
  "sub": "...",
  "email": "admin@homelab.lan",
  "email_verified": true,
  "preferred_username": "admin",
  "groups": ["comfyui-admins"],
  "roles": ["comfyui_admin"]
}
```

---

#### 7.2 Verify Admin Role Claims
**Manual Steps**:
1. Check response includes `comfyui_admin` role
2. Check response includes `comfyui-admins` group

**Success Criteria**: ✓ Admin user has admin role/group claims

---

#### 7.3 Verify User Role Claims
**Manual Steps**:
1. Log in as `user1@homelab.lan`
2. Access userinfo endpoint:
```bash
curl -v -b cookies.txt https://homelab.lan:8444/oauth2/userinfo -k
```

**Expected Results**:
```json
{
  "sub": "...",
  "email": "user1@homelab.lan",
  "email_verified": true,
  "preferred_username": "user1",
  "groups": ["comfyui-users"],
  "roles": ["comfyui_user"]
}
```

**Success Criteria**: ✓ Regular user has user role/group claims

---

#### 7.4 Service-Level RBAC (If Implemented)
**Note**: This test requires service-level authorization logic. If not implemented, mark as N/A.

**Manual Steps**:
1. As regular user, attempt to access admin-only features
2. Examples might include:
   - Model Vault admin API
   - System configuration endpoints
   - User management interfaces

**Expected Results**:
- Admin users: Full access
- Regular users: `403 Forbidden` for admin-only resources

**Success Criteria**: ✓ Authorization enforced at service level

---

**Automation**: ⚠️ **SEMI-AUTOMATED**
- Userinfo checks: Automated
- Service-level tests: Manual or N/A

**Priority**: P1 (Important for security model)

---

### TC-08: Logout Flow

**Objective**: Verify users can log out and session is terminated

**Prerequisites**: Active authenticated session

**Test Steps**:

#### 8.1 Initiate Logout
**Manual Steps**:
1. While logged in, navigate to logout URL:
   - `https://homelab.lan:8444/oauth2/sign_out`

**Expected Results**:
- Session cookie cleared
- Redirect to `/oauth2/sign_out` confirmation or login page

---

#### 8.2 Automated Logout Test
```bash
# With active session cookie
curl -v -b cookies.txt -c cookies.txt \
  https://homelab.lan:8444/oauth2/sign_out -k -L

# Check if session cookie was cleared
cat cookies.txt | grep _oauth2_proxy

# Expected: Cookie should be expired or removed
```

**Expected Results**:
- Session cookie removed or set with expiration in the past
- User is logged out

---

#### 8.3 Verify Session Invalidation
**Manual Steps**:
1. After logout, attempt to access protected resource:
   - `https://homelab.lan:8444/comfyui/`

**Expected Results**:
- HTTP Status: `302 Found`
- Redirect to login page
- Cannot access protected resources

```bash
# Test with old cookie after logout
curl -v -b old_cookies.txt https://homelab.lan:8444/comfyui/ -k 2>&1 | grep -E "HTTP|Location:"

# Expected: 302 redirect to /oauth2/start
```

**Success Criteria**: 
- ✓ Logout URL accessible
- ✓ Session terminated
- ✓ Subsequent requests require re-authentication

---

#### 8.4 Keycloak Session Termination (Optional)
**Manual Steps**:
1. After OAuth2-Proxy logout, check if Keycloak session persists
2. Navigate to Keycloak account console:
   - `https://homelab.lan:8444/keycloak/realms/comfyui/account/`
3. Check if still logged in to Keycloak

**Note**: OAuth2-Proxy logout may not trigger Keycloak logout (single logout not configured by default)

**Expected Results**:
- OAuth2-Proxy session: Terminated
- Keycloak session: May persist (expected behavior)

---

**Automation**: ⚠️ **SEMI-AUTOMATED**
- OAuth2-Proxy logout: Automated
- Session verification: Automated
- Keycloak session check: Manual

**Priority**: P1 (Important for security)

---

### TC-09: Session Persistence and Cookie Behavior

**Objective**: Verify session cookies persist correctly and timeout appropriately

**Prerequisites**: Active authenticated session

**Test Steps**:

#### 9.1 Cookie Inspection
**Manual Steps**:
1. Log in successfully
2. Open browser developer tools (F12)
3. Navigate to: Application → Cookies → `https://homelab.lan:8444`
4. Inspect `_oauth2_proxy` cookie

**Expected Cookie Attributes**:
- Name: `_oauth2_proxy`
- Secure: `Yes`
- HttpOnly: `Yes`
- SameSite: `Lax`
- Path: `/`
- Domain: `homelab.lan` or `.homelab.lan`

**Success Criteria**: ✓ Cookie has secure attributes

---

#### 9.2 Session Timeout Test
**Manual Steps**:
1. Log in and note the time
2. Wait for session timeout period (check oauth2-proxy config)
3. Attempt to access protected resource after timeout

**Expected Results**:
- After timeout: Session expires
- User redirected to login
- Must re-authenticate

**Note**: Default timeout is typically 1 hour, may be longer

---

#### 9.3 Cross-Tab Session Sharing
**Manual Steps**:
1. Log in to Tab 1
2. Open Tab 2 to same domain
3. Navigate to protected resource in Tab 2

**Expected Results**:
- Session shared across tabs (same browser)
- Both tabs have access without re-authentication

**Success Criteria**: ✓ Single sign-on works across browser tabs

---

**Automation**: ❌ **MANUAL** - Requires browser behavior observation

**Priority**: P2 (Nice to have, validates cookie behavior)

---

### TC-10: Invalid User Access Attempts

**Objective**: Verify email allowlist is enforced

**Prerequisites**: 
- Allowlist configured: `admin@homelab.lan, user1@homelab.lan, user2@homelab.lan`
- Test user created in Keycloak but NOT in allowlist

**Test Steps**:

#### 10.1 Create Test User in Keycloak
**Manual Steps**:
1. Log in to Keycloak admin console
2. Navigate to Users → Add User
3. Create user: `unauthorized@homelab.lan`
4. Set password for test user

---

#### 10.2 Attempt Login with Non-Allowlisted User
**Manual Steps**:
1. Open browser in incognito mode
2. Navigate to `https://homelab.lan:8444/`
3. Log in with `unauthorized@homelab.lan`

**Expected Results**:
- Keycloak authentication succeeds
- OAuth2-Proxy rejects due to allowlist
- Error page displayed: "403 Permission Denied" or "Email not authorized"
- User cannot access protected resources

---

#### 10.3 Verify Allowlist Enforcement
```bash
# This test cannot be fully automated without browser automation
# But you can verify the allowlist file
cat config/oauth2-proxy/allowed_emails.txt

# Expected:
# admin@homelab.lan
# user1@homelab.lan
# user2@homelab.lan
```

**Success Criteria**: 
- ✓ Non-allowlisted users denied after Keycloak auth
- ✓ Only allowlisted emails can access

---

**Automation**: ❌ **MANUAL** - Requires Keycloak user management and browser testing

**Priority**: P2 (Important for security, but covered by configuration)

---

### TC-11: Token Expiration and Refresh

**Objective**: Verify token refresh works correctly

**Prerequisites**: Active authenticated session

**Test Steps**:

#### 11.1 Inspect Initial Token
**Manual Steps**:
1. Log in successfully
2. Check OAuth2-Proxy session cookie
3. Decode JWT token (if using JWT session store)

**Note**: By default, OAuth2-Proxy uses encrypted cookie sessions, not JWT

---

#### 11.2 Wait for Token Expiration
**Manual Steps**:
1. Note the token expiration time
2. Keep browser tab open past expiration
3. Attempt to access protected resource

**Expected Results**:
- If refresh token valid: Transparent token refresh
- If refresh token expired: Redirect to login

---

#### 11.3 Verify Transparent Refresh
**Manual Steps**:
1. Monitor network tab in browser
2. Look for requests to `/oauth2/auth` during token refresh
3. Verify no user-facing redirect to login page

**Expected Results**:
- Token refreshed automatically
- User remains logged in
- No disruption to user experience

**Success Criteria**: ✓ Tokens refresh without user intervention

---

**Automation**: ❌ **MANUAL** - Requires waiting for token expiration

**Priority**: P2 (Important for UX, but lower priority for initial testing)

---

## Automated Test Script

Save as `tools/test-sso-flow.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# SSO Authentication Flow - Automated Tests
# Run automated subset of the SSO test plan

BASE_URL="${BASE_URL:-https://homelab.lan:8444}"
COOKIE_JAR="./test-sso-cookies.txt"

echo "========================================"
echo "SSO Test Suite - Automated Tests"
echo "Base URL: $BASE_URL"
echo "========================================"
echo ""

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass_count=0
fail_count=0

# Test function
run_test() {
  local test_id="$1"
  local test_name="$2"
  local expected_status="$3"
  local url="$4"
  local extra_args="${5:-}"
  
  echo "Running: $test_id - $test_name"
  
  # Run curl and capture status
  status=$(curl -s -o /dev/null -w "%{http_code}" -k $extra_args "$url")
  
  if [ "$status" = "$expected_status" ]; then
    echo -e "  ${GREEN}✓ PASS${NC} (HTTP $status)"
    ((pass_count++))
  else
    echo -e "  ${RED}✗ FAIL${NC} (Expected: $expected_status, Got: $status)"
    ((fail_count++))
  fi
  echo ""
}

# TC-01.1: OAuth2-Proxy Health
echo "TC-01.1: OAuth2-Proxy Health Endpoint"
docker exec comfyui-homelab-oauth2-proxy-1 \
  wget -q -O - http://localhost:4180/oauth2/ping > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo -e "  ${GREEN}✓ PASS${NC}"
  ((pass_count++))
else
  echo -e "  ${RED}✗ FAIL${NC}"
  ((fail_count++))
fi
echo ""

# TC-01.3: Nginx Healthz
run_test "TC-01.3" "Nginx Healthz Endpoint" "200" "$BASE_URL/healthz"

# TC-03.1: Unauthenticated Root Access
echo "TC-03.1: Unauthenticated Root Access"
redirect=$(curl -s -k -o /dev/null -w "%{redirect_url}" "$BASE_URL/")
if [[ "$redirect" == *"/oauth2/start"* ]]; then
  echo -e "  ${GREEN}✓ PASS${NC} (Redirects to: $redirect)"
  ((pass_count++))
else
  echo -e "  ${RED}✗ FAIL${NC} (Expected redirect to /oauth2/start, got: $redirect)"
  ((fail_count++))
fi
echo ""

# TC-03: All Protected Endpoints
echo "TC-03: Protected Endpoints Redirect Test"
for endpoint in "/comfyui/" "/ollama/" "/langchain/" "/langflow/" "/code-executor/" "/model-vault/"; do
  echo "  Testing: $endpoint"
  status=$(curl -s -o /dev/null -w "%{http_code}" -k "$BASE_URL$endpoint")
  redirect=$(curl -s -k -o /dev/null -w "%{redirect_url}" "$BASE_URL$endpoint")
  
  if [ "$status" = "302" ] && [[ "$redirect" == *"/oauth2/start"* ]]; then
    echo -e "    ${GREEN}✓ PASS${NC} (302 → $redirect)"
    ((pass_count++))
  else
    echo -e "    ${RED}✗ FAIL${NC} (Status: $status, Redirect: $redirect)"
    ((fail_count++))
  fi
done
echo ""

# Summary
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "Passed: ${GREEN}$pass_count${NC}"
echo -e "Failed: ${RED}$fail_count${NC}"
echo "Total:  $((pass_count + fail_count))"
echo ""

if [ $fail_count -eq 0 ]; then
  echo -e "${GREEN}All automated tests passed!${NC}"
  exit 0
else
  echo -e "${RED}Some tests failed.${NC}"
  exit 1
fi
```

**Usage**:
```bash
chmod +x tools/test-sso-flow.sh
./tools/test-sso-flow.sh
```

---

## Manual Test Checklist

Use this checklist for manual browser testing:

### Pre-Flight Checks
- [ ] Stack deployed with SSO profile: `docker compose --profile sso up -d`
- [ ] Keycloak healthy: Check admin console access
- [ ] OAuth2-Proxy healthy: Check ping endpoint
- [ ] SSL certificates trusted or warnings understood

### Authentication Flow
- [ ] **TC-02**: Keycloak admin console accessible with `kcadmin` credentials
- [ ] **TC-04**: Admin user can log in (`admin@homelab.lan`)
  - [ ] Password update forced on first login
  - [ ] TOTP/MFA enrollment forced for admin
  - [ ] Redirect to original destination after auth
- [ ] **TC-05**: Regular users can log in (`user1`, `user2`)
  - [ ] Password update forced on first login
  - [ ] No MFA prompt for regular users
  - [ ] Redirect to original destination

### Service Access
- [ ] **TC-06**: All services accessible after authentication
  - [ ] ComfyUI UI loads
  - [ ] Ollama API accessible
  - [ ] LangChain accessible
  - [ ] LangFlow UI loads
  - [ ] Model Vault accessible

### Authorization
- [ ] **TC-07**: Role claims present in userinfo
  - [ ] Admin user has `comfyui_admin` role
  - [ ] Regular users have `comfyui_user` role

### Logout
- [ ] **TC-08**: Logout flow works
  - [ ] Access `/oauth2/sign_out` terminates session
  - [ ] Protected resources require re-authentication after logout

### Edge Cases
- [ ] **TC-09**: Session persists across browser tabs
- [ ] **TC-10**: Non-allowlisted users denied (if test user created)

---

## Test Execution Guide

### Phase 1: Infrastructure (Automated)
```bash
# Run automated test script
./tools/test-sso-flow.sh

# Or run individual tests
curl -k https://homelab.lan:8444/healthz
curl -k https://homelab.lan:8444/ -L | grep -i keycloak
```

### Phase 2: Authentication (Manual)
1. Open browser in private/incognito mode
2. Test admin login flow (TC-04)
3. Logout and test user1 login (TC-05)
4. Document any issues

### Phase 3: Service Access (Semi-Automated)
1. Export cookies from browser session
2. Run curl tests with cookies
3. Or manually navigate to each service in browser

### Phase 4: RBAC & Edge Cases (Manual)
1. Check user claims via `/oauth2/userinfo`
2. Test logout flow
3. Test session persistence

---

## Success Criteria Summary

All tests must pass for SSO to be considered production-ready:

### P0 (Must Pass)
- ✓ All infrastructure health checks pass
- ✓ Keycloak admin console accessible
- ✓ Unauthenticated access properly redirected
- ✓ Admin can log in with MFA enrollment
- ✓ Protected services require authentication

### P1 (Should Pass)
- ✓ Regular users can log in
- ✓ All services accessible after authentication
- ✓ Role claims present in tokens
- ✓ Logout flow works correctly

### P2 (Nice to Have)
- ✓ Session cookies have correct attributes
- ✓ Session timeout enforced
- ✓ Email allowlist enforced
- ✓ Token refresh works transparently

---

## Troubleshooting Guide

### Common Issues

#### Issue: Redirect loop
**Symptoms**: Constant redirects between OAuth2-Proxy and Keycloak  
**Causes**:
- Incorrect `OAUTH2_PROXY_REDIRECT_URL`
- Keycloak client redirect URI mismatch
- Cookie domain mismatch

**Debug**:
```bash
# Check OAuth2-Proxy logs
docker logs comfyui-homelab-oauth2-proxy-1

# Check redirect URL configuration
grep OAUTH2_PROXY_REDIRECT_URL .env.homelab

# Verify Keycloak client settings
# Admin Console → Clients → comfyui-ingress → Valid Redirect URIs
```

---

#### Issue: 403 Forbidden after successful Keycloak login
**Symptoms**: Keycloak auth succeeds but OAuth2-Proxy denies access  
**Causes**:
- Email not in allowlist
- Email domain restriction

**Debug**:
```bash
# Check allowlist
cat config/oauth2-proxy/allowed_emails.txt

# Check OAuth2-Proxy config
cat config/oauth2-proxy/oauth2-proxy.cfg | grep email

# Check OAuth2-Proxy logs for email validation
docker logs comfyui-homelab-oauth2-proxy-1 | grep -i email
```

---

#### Issue: Session not persisting
**Symptoms**: Re-authentication required on every request  
**Causes**:
- Cookie not being set
- Secure flag mismatch (HTTP vs HTTPS)
- Cookie domain issue

**Debug**:
```bash
# Check if cookies are being set
curl -v -k https://homelab.lan:8444/oauth2/callback 2>&1 | grep -i "set-cookie"

# Check OAuth2-Proxy cookie configuration
docker exec comfyui-homelab-oauth2-proxy-1 \
  cat /etc/oauth2-proxy/oauth2-proxy.cfg | grep cookie
```

---

#### Issue: OIDC issuer unreachable
**Symptoms**: OAuth2-Proxy cannot connect to Keycloak  
**Causes**:
- Docker DNS issue
- Wrong `OIDC_ISSUER_URL`
- Keycloak not ready

**Debug**:
```bash
# Check OIDC issuer URL
grep OIDC_ISSUER_URL .env.homelab

# Test connectivity from OAuth2-Proxy container
docker exec comfyui-homelab-oauth2-proxy-1 \
  wget -O - http://keycloak:8080/keycloak/realms/comfyui/.well-known/openid-configuration

# Check Keycloak health
docker exec comfyui-homelab-keycloak-1 \
  curl http://localhost:9000/health/ready
```

---

## Notes for Future Automation

### Browser Automation Options
For full test automation, consider:
- **Playwright** (Python/Node.js): Full browser automation
- **Selenium**: Traditional browser automation
- **Puppeteer**: Chrome/Chromium automation

### Example Playwright Test
```python
from playwright.sync_api import sync_playwright

def test_sso_login():
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page()
        
        # Navigate to protected resource
        page.goto('https://homelab.lan:8444/comfyui/')
        
        # Should redirect to Keycloak login
        assert 'keycloak' in page.url
        
        # Fill in credentials
        page.fill('input[name="username"]', 'admin@homelab.lan')
        page.fill('input[name="password"]', 'password')
        page.click('input[type="submit"]')
        
        # Should redirect back to ComfyUI
        page.wait_for_url('**/comfyui/**')
        assert page.url.endswith('/comfyui/')
        
        browser.close()
```

---

## Appendix: Quick Reference

### Key URLs
- Keycloak Admin: `https://homelab.lan:8444/keycloak/admin/`
- OAuth2 Login Start: `https://homelab.lan:8444/oauth2/start`
- OAuth2 Callback: `https://homelab.lan:8444/oauth2/callback`
- OAuth2 Userinfo: `https://homelab.lan:8444/oauth2/userinfo`
- OAuth2 Logout: `https://homelab.lan:8444/oauth2/sign_out`
- Healthz: `https://homelab.lan:8444/healthz`

### Key Files
- OAuth2-Proxy Config: `config/oauth2-proxy/oauth2-proxy.cfg`
- Email Allowlist: `config/oauth2-proxy/allowed_emails.txt`
- Environment: `.env.homelab`
- Nginx Template: `nginx.conf.template`
- Keycloak Realm: `config/keycloak/realm-comfyui.json`

### Useful Commands
```bash
# Check SSO services
docker ps --filter "name=keycloak|oauth2-proxy"

# View OAuth2-Proxy logs
docker logs -f comfyui-homelab-oauth2-proxy-1

# View Keycloak logs
docker logs -f comfyui-homelab-keycloak-1

# Restart SSO services
docker compose -f docker-compose.homelab.yml --profile sso restart keycloak oauth2-proxy nginx

# Export browser cookies for testing
# Chrome: Dev Tools → Application → Cookies → Export
# Firefox: Dev Tools → Storage → Cookies → Copy

# Test with curl using exported cookies
curl -b cookies.txt https://homelab.lan:8444/comfyui/ -k
```

---

**Document Version**: 1.0  
**Last Updated**: 2026-01-02  
**Test Environment**: homelab.lan (Docker Compose with SSO profile)
