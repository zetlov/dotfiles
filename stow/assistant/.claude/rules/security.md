# Security

Before any commit, verify:
- No hardcoded secrets — env vars or a secret manager only; validate required secrets at startup; rotate anything exposed.
- All user input validated; parameterized queries (SQLi); sanitized HTML (XSS); CSRF protection; authn/authz verified; rate limiting on endpoints; error messages don't leak internals.

If a security issue is found: stop, use the security-reviewer agent, fix CRITICAL issues before continuing, rotate exposed secrets, and sweep the codebase for the same pattern.
